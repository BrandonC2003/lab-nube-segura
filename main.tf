locals {
  grupos = {
    core      = "Redes, VMs, datos y monitoreo - persistente"
    perimetro = "Firewall, App Gateway, y VPN Gateway - efimero"
    sede      = "Sede local simulada"
  }
}

resource "azurerm_resource_group" "rg" {
  for_each = local.grupos

  name     = "rg-${var.prefijo}-${each.key}"
  location = var.ubicacion
  tags     = merge(var.etiquetas, { descripcion = each.value })
}

# Sufijo para recursos cuyo nombre debe ser único en todo Azure
resource "random_string" "sufijo" {
  length  = 5
  upper   = false
  special = false
}