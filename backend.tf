terraform {
  backend "azurerm" {
    resource_group_name  = "rg-proto-tfstate"
    storage_account_name = "sttfstateproto7773"
    container_name       = "tfstate"
    key                  = "lab-nube-segura.tfstate"
    use_azuread_auth     = true
  }
}