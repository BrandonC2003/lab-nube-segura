output "ip_publica_appgw" {
  value = azurerm_public_ip.appgw.ip_address
}

output "ip_privada_firewall" {
  value = local.ip_firewall
}

output "vpn_conexion_id" {
  value = azurerm_virtual_network_gateway_connection.sede.id
}

output "firewall_id" {
  value = azurerm_firewall.this.id
}

output "appgw_id" {
  value = azurerm_application_gateway.this.id
}
