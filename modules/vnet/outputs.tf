output "id" {
  value = azurerm_virtual_network.this.id
}

output "nombre" {
  value = azurerm_virtual_network.this.name
}

output "subredes" {
  description = "Mapa nombre de subred => ID"
  value       = { for clave, s in azurerm_subnet.this : clave => s.id }
}