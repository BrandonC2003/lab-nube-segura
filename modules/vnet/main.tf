resource "azurerm_virtual_network" "this" {
  name                = var.nombre
  location            = var.ubicacion
  resource_group_name = var.grupo_recursos
  address_space       = var.espacio_direcciones
  tags                = var.etiquetas
}

resource "azurerm_subnet" "this" {
  for_each = var.subredes

  name                 = each.key
  resource_group_name  = var.grupo_recursos
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.prefijo]

  private_endpoint_network_policies = each.value.endpoints_privados ? "Enabled" : "Disabled"
}

locals {
  subredes_con_nsg = { for clave, s in var.subredes : clave => s if s.con_nsg }
}

resource "azurerm_network_security_group" "this" {
  for_each = local.subredes_con_nsg

  name                = "nsg-${each.key}"
  location            = var.ubicacion
  resource_group_name = var.grupo_recursos
  tags                = var.etiquetas

  dynamic "security_rule" {
    for_each = each.value.reglas_nsg
    content {
      name                       = security_rule.value.nombre
      priority                   = security_rule.value.prioridad
      direction                  = security_rule.value.direccion
      access                     = security_rule.value.acceso
      protocol                   = security_rule.value.protocolo
      source_port_range          = "*"
      destination_port_range     = length(security_rule.value.puertos) == 1 ? security_rule.value.puertos[0] : null
      destination_port_ranges    = length(security_rule.value.puertos) > 1 ? security_rule.value.puertos : null
      source_address_prefix      = security_rule.value.origen
      destination_address_prefix = security_rule.value.destino
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = local.subredes_con_nsg

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}