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

output "key_vault_nombre" {
  description = "Nombre del Key Vault (incluye el sufijo aleatorio)"
  value       = azurerm_key_vault.principal.name
}

output "sql_servidor_fqdn" {
  description = "Nombre DNS del servidor SQL; desde las redes enlazadas resuelve a una IP privada"
  value       = azurerm_mssql_server.erp.fully_qualified_domain_name
}

output "sql_base_datos" {
  value = azurerm_mssql_database.erp.name
}

output "sql_ip_privada" {
  description = "IP privada asignada al punto de conexión de SQL en snet-datos"
  value       = azurerm_private_endpoint.sql.private_service_connection[0].private_ip_address
}