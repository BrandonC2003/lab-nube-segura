locals {
    grupos = {
        core      = "Redes, VMs, datos y monitoreo - persistente"
        perimetro = "Firewall, App Gateway, y VPN Gateway - efimero"
        sede      = "Sede local simulada"
    }
}

resource "azurerm_resource_group" "rg" {
    for_each = local.grupos

    name = "rg-${var.prefijo}-${each.key}"
    location = var.ubicacion
    tags     = merge(var.etiquetas, { descripcion = each.value})
}