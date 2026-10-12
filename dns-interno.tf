# ================= DNS INTERNO (interno.lab) =================
# app.interno.lab apunta al servicio en la nube o, durante el plan de vuelta atrás
# (prueba V11), al servicio local de la sede. TTL corto para que el cambio se propague rápido.
locals {
  destinos_app = {
    nube  = local.ip_web01
    local = "192.168.30.10"
  }
}

resource "azurerm_private_dns_zone" "interno" {
  name                = "interno.lab"
  resource_group_name = local.rg_core
  tags                = var.etiquetas
}

resource "azurerm_private_dns_zone_virtual_network_link" "interno" {
  for_each = local.vnets_con_dns

  name                  = "enlace-interno-${each.key}"
  resource_group_name   = local.rg_core
  private_dns_zone_name = azurerm_private_dns_zone.interno.name
  virtual_network_id    = each.value
  tags                  = var.etiquetas
}

resource "azurerm_private_dns_a_record" "servidores" {
  for_each = {
    web01 = local.ip_web01
    erp01 = local.ip_erp01
    srv01 = "192.168.30.10"
  }

  name                = each.key
  zone_name           = azurerm_private_dns_zone.interno.name
  resource_group_name = local.rg_core
  ttl                 = 300
  records             = [each.value]
  tags                = var.etiquetas
}

resource "azurerm_private_dns_a_record" "app" {
  name                = "app"
  zone_name           = azurerm_private_dns_zone.interno.name
  resource_group_name = local.rg_core
  ttl                 = 60
  records             = [local.destinos_app[var.servicio_app_activo]]
  tags                = var.etiquetas
}
