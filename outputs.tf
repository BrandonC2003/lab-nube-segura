output "grupos_de_recursos" {
  description = "Nombres de los grupos de recursos creados"
  value       = { for clave, rg in azurerm_resource_group.rg : clave => rg.name }
}

output "vnet_hub_subredes" {
  value = module.vnet_hub.subredes
}

output "vnet_cargas_subredes" {
  value = module.vnet_cargas.subredes
}

output "ip_publica_router_sede" {
  value = azurerm_public_ip.router_sede.ip_address
}

output "ip_publica_vpn_gateway" {
  value = azurerm_public_ip.vpn_gateway.ip_address
}

output "vpn_psk" {
  value     = random_password.vpn_psk.result
  sensitive = true
}

output "ssh_router_sede" {
  value = "ssh -i ~/.ssh/lab_azure azureadmin@${azurerm_public_ip.router_sede.ip_address}"
}