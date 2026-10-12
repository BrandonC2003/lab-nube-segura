output "id" {
  value = azurerm_linux_virtual_machine.this.id
}

output "ip_privada" {
  value = azurerm_network_interface.this.private_ip_address
}

output "principal_id" {
  description = "ID de la identidad administrada de la VM"
  value       = azurerm_linux_virtual_machine.this.identity[0].principal_id
}