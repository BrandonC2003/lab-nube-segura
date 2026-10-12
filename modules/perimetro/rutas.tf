# ================= RUTAS DEFINIDAS POR EL USUARIO (UDR) =================
# Todo el tráfico entre zonas pasa por el Firewall en ambos sentidos.

# App Gateway -> spoke. App Gateway v2 no admite 0.0.0.0/0 hacia un NVA.
resource "azurerm_route_table" "appgw" {
  name                = "rt-${var.prefijo}-appgw"
  location            = var.ubicacion
  resource_group_name = var.grupo_recursos
  tags                = var.etiquetas

  route {
    name                   = "cargas-por-firewall"
    address_prefix         = var.rangos.cargas
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.ip_firewall
  }
}

# Lo que entra por la VPN hacia el spoke pasa primero por el Firewall.
# En GatewaySubnet la propagación de rutas debe seguir habilitada.
resource "azurerm_route_table" "gateway" {
  name                = "rt-${var.prefijo}-gateway"
  location            = var.ubicacion
  resource_group_name = var.grupo_recursos
  tags                = var.etiquetas

  route {
    name                   = "cargas-por-firewall"
    address_prefix         = var.rangos.cargas
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.ip_firewall
  }
}

# Spoke: Internet, App Gateway y sede, todo por el Firewall (tráfico simétrico)
resource "azurerm_route_table" "spoke" {
  name                          = "rt-${var.prefijo}-spoke"
  location                      = var.ubicacion
  resource_group_name           = var.grupo_recursos
  bgp_route_propagation_enabled = false # evita rutas aprendidas por VPN que omitan el Firewall
  tags                          = var.etiquetas

  route {
    name                   = "internet-por-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.ip_firewall
  }

  route {
    name                   = "appgw-por-firewall"
    address_prefix         = var.rangos.appgw
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.ip_firewall
  }

  route {
    name                   = "sede-por-firewall"
    address_prefix         = var.rangos.sede
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.ip_firewall
  }
}

resource "azurerm_subnet_route_table_association" "appgw" {
  subnet_id      = var.subred_appgw_id
  route_table_id = azurerm_route_table.appgw.id
}

resource "azurerm_subnet_route_table_association" "gateway" {
  subnet_id      = var.subred_gateway_id
  route_table_id = azurerm_route_table.gateway.id

  # Asociar una tabla a GatewaySubnet mientras el gateway se crea puede fallar
  depends_on = [azurerm_virtual_network_gateway.this]
}

resource "azurerm_subnet_route_table_association" "spoke" {
  for_each = var.subredes_spoke_ids

  subnet_id      = each.value
  route_table_id = azurerm_route_table.spoke.id
}
