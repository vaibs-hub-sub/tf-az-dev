terraform {
  backend "azurerm" {
    resource_group_name   = "rg-cp-srivaibhavi-b"
    storage_account_name  = "vstoreaccount"     # must be globally unique
    container_name        = "tfstate"
    key                   = "terraform.tfstate"
  }
}