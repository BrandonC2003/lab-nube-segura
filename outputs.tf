output "grupos_de_recursos" {
    description = "Nombres de los grupos de recursos creados"
    value       = { for clave, rg in azurerm_resource_group.rg : clave => rg.name}
}