# ================= AZURE BACKUP =================
# La eliminación temporal (14 días) está siempre activa en Azure Backup (secure by default)
resource "azurerm_recovery_services_vault" "principal" {
  name                = "rsv-${var.prefijo}-${local.sufijo}"
  location            = var.ubicacion
  resource_group_name = local.rg_core
  sku                 = "Standard"
  storage_mode_type   = "GeoRedundant"
  tags                = var.etiquetas
}

# V2 (Enhanced) admite VMs con y sin Trusted Launch
resource "azurerm_backup_policy_vm" "diaria" {
  name                = "pol-diaria-7d"
  resource_group_name = local.rg_core
  recovery_vault_name = azurerm_recovery_services_vault.principal.name
  policy_type         = "V2"
  timezone            = "Central America Standard Time"

  backup {
    frequency = "Daily"
    time      = "02:00"
  }

  retention_daily {
    count = 7
  }
}

# La base de datos usa la restauración a un punto en el tiempo de Azure SQL (datos.tf).
# El controlador de dominio se respalda como VM completa.
locals {
  vms_respaldadas = {
    erp01 = module.vm_erp01.id
    web01 = module.vm_web01.id
    dc01  = module.vm_dc01.id
  }
}

resource "azurerm_backup_protected_vm" "vm" {
  for_each = local.vms_respaldadas

  resource_group_name = local.rg_core
  recovery_vault_name = azurerm_recovery_services_vault.principal.name
  source_vm_id        = each.value
  backup_policy_id    = azurerm_backup_policy_vm.diaria.id
}
