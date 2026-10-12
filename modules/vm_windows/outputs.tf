output "id" {
  value = azurerm_windows_virtual_machine.this.id
}

output "ip_privada" {
  value = azurerm_network_interface.this.private_ip_address
}

output "principal_id" {
  description = "ID de la identidad administrada de la VM"
  value       = azurerm_windows_virtual_machine.this.identity[0].principal_id
}

output "contrasena_admin" {
  description = "Contraseña del administrador local; se guarda en Key Vault desde la raíz"
  value       = random_password.admin.result
  sensitive   = true
}
