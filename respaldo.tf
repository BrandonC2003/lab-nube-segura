# ================= AZURE BACKUP =================
# La eliminación temporal (14 días) está siempre activa en Azure Backup (secure by default)
resource "azurerm_recovery_services_vault" "principal" {
  name                = "rsv-${var.prefijo}-${local.sufijo}"
  location            = var.ubicacion
  resource_group_name = local.rg_core
  sku                 = "Standard"
  storage_mode_type   = "GeoRedundant"
  tags                = var.etiquetas
}

# ERP y aplicaciones web: RPO 4 h. Política mejorada cada 4 h,
# diarias por 30 días y mensuales por 12 meses.
resource "azurerm_backup_policy_vm" "cada_4h" {
  name                           = "pol-mejorada-4h"
  resource_group_name            = local.rg_core
  recovery_vault_name            = azurerm_recovery_services_vault.principal.name
  policy_type                    = "V2"
  timezone                       = "Central America Standard Time"
  instant_restore_retention_days = 7

  backup {
    frequency     = "Hourly"
    time          = "00:00"
    hour_interval = 4
    hour_duration = 24
  }

  retention_daily {
    count = 30
  }

  retention_monthly {
    count    = 12
    weekdays = ["Sunday"]
    weeks    = ["First"]
  }
}

# Controlador de dominio: RPO 24 h, retención de 30 días
resource "azurerm_backup_policy_vm" "diaria_30d" {
  name                = "pol-diaria-30d"
  resource_group_name = local.rg_core
  recovery_vault_name = azurerm_recovery_services_vault.principal.name
  policy_type         = "V2"
  timezone            = "Central America Standard Time"

  backup {
    frequency = "Daily"
    time      = "02:00"
  }

  retention_daily {
    count = 30
  }
}

locals {
  vms_respaldadas = {
    erp01 = { id = module.vm_erp01.id, politica = azurerm_backup_policy_vm.cada_4h.id }
    web01 = { id = module.vm_web01.id, politica = azurerm_backup_policy_vm.cada_4h.id }
    dc01  = { id = module.vm_dc01.id, politica = azurerm_backup_policy_vm.diaria_30d.id }
  }
}

resource "azurerm_backup_protected_vm" "vm" {
  for_each = local.vms_respaldadas

  resource_group_name = local.rg_core
  recovery_vault_name = azurerm_recovery_services_vault.principal.name
  source_vm_id        = each.value.id
  backup_policy_id    = each.value.politica
}

# ================= ENTORNO AISLADO DE RESTAURACIÓN (prueba V10) =================
# Sin peering ni rutas hacia el resto del laboratorio
module "vnet_aislada" {
  source = "./modules/vnet"

  nombre              = "vnet-${var.prefijo}-aislada"
  grupo_recursos      = local.rg_core
  ubicacion           = var.ubicacion
  espacio_direcciones = ["10.99.0.0/16"]
  etiquetas           = var.etiquetas

  subredes = {
    snet-restauracion = { prefijo = "10.99.1.0/24" }
  }
}

# Cuenta de almacenamiento de transición que exige la restauración de VMs
resource "azurerm_storage_account" "restauracion" {
  name                            = "st${var.prefijo}rest${local.sufijo}"
  location                        = var.ubicacion
  resource_group_name             = local.rg_core
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  tags                            = var.etiquetas
}
