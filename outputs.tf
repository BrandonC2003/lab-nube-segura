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

output "ips_cargas" {
  description = "IPs privadas de las VMs del spoke"
  value = {
    web01  = module.vm_web01.ip_privada
    erp01  = module.vm_erp01.ip_privada
    jump01 = module.vm_jump01.ip_privada
  }
}

output "ca_interna_pem" {
  description = "Certificado público de la CA interna (para confiar en web01 desde los clientes)"
  value       = tls_self_signed_cert.ca.cert_pem
}

# ---------- Perímetro (null cuando perimetro_activo = false) ----------
output "ip_publica_appgw" {
  description = "IP pública del WAF; prueba V7: curl -k https://<ip>"
  value       = one(module.perimetro[*].ip_publica_appgw)
}

output "ip_privada_firewall" {
  value = one(module.perimetro[*].ip_privada_firewall)
}

output "vpn_estado_conexion" {
  description = "Comando para consultar el estado del túnel (prueba V2)"
  value = try(
    "az network vpn-connection show --ids ${module.perimetro[0].vpn_conexion_id} --query connectionStatus -o tsv",
    "perímetro apagado"
  )
}

# ---------- Identidad ----------
output "usuarios_prueba" {
  description = "UPN de los usuarios de prueba; contraseñas en Key Vault (entra-<usuario>)"
  value       = { for clave, u in azuread_user.usuario : clave => u.user_principal_name }
}

output "cuentas_emergencia" {
  description = "UPN de las cuentas de emergencia (monitoreadas en Sentinel)"
  value       = [for u in azuread_user.emergencia : u.user_principal_name]
}
