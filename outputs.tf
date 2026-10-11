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