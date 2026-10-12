data "azurerm_client_config" "actual" {}

locals {
  sufijo = random_string.sufijo.result
}

# ================= KEY VAULT =================
resource "azurerm_key_vault" "principal" {
  name                       = "kv-${var.prefijo}-${local.sufijo}"
  location                   = var.ubicacion
  resource_group_name        = local.rg_core
  tenant_id                  = data.azurerm_client_config.actual.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = true # obligatorio para TDE con CMK
  soft_delete_retention_days = 7
  tags                       = var.etiquetas

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices" # permite a SQL (servicio de confianza) leer su clave
    ip_rules       = concat([var.ip_admin], var.ips_equipo)
  }
}

# El equipo administra claves, secretos y certificados (plano de datos)
resource "azurerm_role_assignment" "kv_equipo" {
  for_each = toset(var.administradores_lab)

  scope                = azurerm_key_vault.principal.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = each.value
}

# Clave RSA 2048 para TDE, con rotación anual
resource "azurerm_key_vault_key" "tde" {
  name         = "clave-tde-sql"
  key_vault_id = azurerm_key_vault.principal.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["wrapKey", "unwrapKey"] # solo lo que TDE necesita: mínimo privilegio

  rotation_policy {
    automatic {
      time_after_creation = "P365D"
    }
    expire_after         = "P730D"
    notify_before_expiry = "P30D"
  }

  depends_on = [azurerm_role_assignment.kv_equipo]
}

# ================= AZURE SQL =================
resource "azurerm_mssql_server" "erp" {
  name                          = "sql-${var.prefijo}-${local.sufijo}"
  location                      = var.ubicacion
  resource_group_name           = local.rg_core
  version                       = "12.0"
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false # solo por punto de conexión privado
  tags                          = var.etiquetas

  azuread_administrator {
    login_username              = var.sql_admin.login
    object_id                   = var.sql_admin.object_id
    azuread_authentication_only = true # sin usuarios ni contraseñas SQL
  }

  identity {
    type = "SystemAssigned" # identidad con la que SQL leerá la clave de Key Vault
  }
}

resource "azurerm_mssql_database" "erp" {
  name        = "sqldb-erp"
  server_id   = azurerm_mssql_server.erp.id
  sku_name    = "Basic"
  max_size_gb = 2
  tags        = var.etiquetas

  short_term_retention_policy {
    retention_days = 7 # restauración a un punto en el tiempo (prueba V10)
  }
}

# SQL puede usar la clave para cifrar/descifrar (wrap/unwrap)
resource "azurerm_role_assignment" "kv_sql" {
  scope                = azurerm_key_vault.principal.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_mssql_server.erp.identity[0].principal_id
}

# Activa TDE con la clave del cliente (CMK)
resource "azurerm_mssql_server_transparent_data_encryption" "erp" {
  server_id             = azurerm_mssql_server.erp.id
  key_vault_key_id      = azurerm_key_vault_key.tde.id
  auto_rotation_enabled = true

  depends_on = [azurerm_role_assignment.kv_sql]
}

# ================= DNS PRIVADO =================
locals {
  zonas_privadas = {
    sql = "privatelink.database.windows.net"
    kv  = "privatelink.vaultcore.azure.net"
  }

  vnets_con_dns = {
    hub    = module.vnet_hub.id
    cargas = module.vnet_cargas.id
    sede   = module.vnet_sede.id
  }

  # Un enlace por cada combinación zona-VNet ("sql-hub", "kv-sede", ...)
  enlaces_dns = {
    for par in setproduct(keys(local.zonas_privadas), keys(local.vnets_con_dns)) :
    "${par[0]}-${par[1]}" => { zona = par[0], vnet = par[1] }
  }
}

resource "azurerm_private_dns_zone" "zona" {
  for_each = local.zonas_privadas

  name                = each.value
  resource_group_name = local.rg_core
  tags                = var.etiquetas
}

resource "azurerm_private_dns_zone_virtual_network_link" "enlace" {
  for_each = local.enlaces_dns

  name                  = "enlace-${each.key}"
  resource_group_name   = local.rg_core
  private_dns_zone_name = azurerm_private_dns_zone.zona[each.value.zona].name
  virtual_network_id    = local.vnets_con_dns[each.value.vnet]
  tags                  = var.etiquetas
}

# ================= PUNTOS DE CONEXIÓN PRIVADOS =================
resource "azurerm_private_endpoint" "sql" {
  name                = "pe-${var.prefijo}-sql"
  location            = var.ubicacion
  resource_group_name = local.rg_core
  subnet_id           = module.vnet_cargas.subredes["snet-datos"]
  tags                = var.etiquetas

  private_service_connection {
    name                           = "psc-sql"
    private_connection_resource_id = azurerm_mssql_server.erp.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-sql"
    private_dns_zone_ids = [azurerm_private_dns_zone.zona["sql"].id]
  }
}

resource "azurerm_private_endpoint" "kv" {
  name                = "pe-${var.prefijo}-kv"
  location            = var.ubicacion
  resource_group_name = local.rg_core
  subnet_id           = module.vnet_cargas.subredes["snet-seguridad"]
  tags                = var.etiquetas

  private_service_connection {
    name                           = "psc-kv"
    private_connection_resource_id = azurerm_key_vault.principal.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-kv"
    private_dns_zone_ids = [azurerm_private_dns_zone.zona["kv"].id]
  }
}