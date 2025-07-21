provider "azurerm" {
  features {}
  subscription_id = "343c17eb-34b6-4481-92a2-a0a5a04bdd88"
}

data "azurerm_resource_group" "dev_rg" {
  name = "rg-cp-srivaibhavi-b"
}

data "azurerm_client_config" "current" {}

resource "azurerm_virtual_network" "vnet" {
  name                = "v-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = data.azurerm_resource_group.dev_rg.location
  resource_group_name = data.azurerm_resource_group.dev_rg.name
}
 
resource "azurerm_subnet" "subnet" {
  name                 = "v-subnet"
  resource_group_name  = data.azurerm_resource_group.dev_rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}
 
resource "azurerm_public_ip" "public_ip" {
  name                = "v-ip"
  location            = data.azurerm_resource_group.dev_rg.location
  resource_group_name = data.azurerm_resource_group.dev_rg.name
  allocation_method   = "Static"
}

output "public_ip" {
  value = azurerm_public_ip.public_ip.ip_address
}

resource "azurerm_virtual_network" "win_net" {
  name                = "ws-vnet"
  address_space       = ["10.1.0.0/16"]
  location            = data.azurerm_resource_group.dev_rg.location
  resource_group_name = data.azurerm_resource_group.dev_rg.name
}

resource "azurerm_subnet" "win_subnet" {
  name                 = "ws-subnet"
  resource_group_name  = data.azurerm_resource_group.dev_rg.name
  virtual_network_name = azurerm_virtual_network.win_net.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_network_interface" "win_nic" {
  name                = "ws-nic"
  location            = data.azurerm_resource_group.dev_rg.location
  resource_group_name = data.azurerm_resource_group.dev_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                = "ws-vm"
  location            = data.azurerm_resource_group.dev_rg.location
  resource_group_name = data.azurerm_resource_group.dev_rg.name
  size                = "Standard_B2s"
  admin_username      = "azureuser"
  admin_password      = "P@ssword12345!" 

  identity {
    type = "SystemAssigned"
  }

  network_interface_ids = [
    azurerm_network_interface.win_nic.id,
  ]

  os_disk {
    name                 = "ws-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  computer_name  = "wsvm"
  provision_vm_agent = true
  tags = {
    Environment = "Dev"
    Owner       = "srivaibhavi.b@kyndryl.com"
  }
}

output "windows_vm_public_ip" {
  value = azurerm_public_ip.public_ip.ip_address
}

resource "azurerm_recovery_services_vault" "v-vault" {
  name                = "windows-backup-vault"
  location            = data.azurerm_resource_group.dev_rg.location
  resource_group_name = data.azurerm_resource_group.dev_rg.name
  sku                 = "Standard"

  tags = {
    Environment = "Dev"
  }
}

resource "azurerm_backup_policy_vm" "policy" {
  name                = "yearly-retention-policy"
  resource_group_name = data.azurerm_resource_group.dev_rg.name
  recovery_vault_name = azurerm_recovery_services_vault.v-vault.name
  timezone            = "UTC"

  backup {
    frequency = "Weekly"
    time      = "23:00"
    weekdays  = ["Sunday"]
  }
  retention_weekly {
    count = 1
    weekdays = ["Sunday"]
  }
  retention_yearly {
    count    = 1
    weekdays = ["Sunday"]
    weeks    = ["First"]
    months   = ["January"]
  }
}

#resource "azurerm_backup_protected_vm" "windows_vm_backup" {
  #resource_group_name  = data.azurerm_resource_group.dev_rg.name
  #recovery_vault_name  = azurerm_recovery_services_vault.v-vault.name
  #source_vm_id         = azurerm_windows_virtual_machine.vm.id
  #backup_policy_id     = azurerm_backup_policy_vm.policy.id
#}

resource "azurerm_key_vault" "win_kv" {
  name                = "v-vault-${random_string.suffix.result}"
  location            = data.azurerm_resource_group.dev_rg.location
  resource_group_name = data.azurerm_resource_group.dev_rg.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id  # your own identity to create the secret

    secret_permissions = ["Get", "List", "Set"]
  }

  tags = {
    Environment = "Dev"
  }
}

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

resource "azurerm_key_vault_secret" "vm_secret" {
  name         = "v-vault-pass"
  value        = "Vaibs@004KQ6"
  key_vault_id = azurerm_key_vault.win_kv.id
}

resource "azurerm_key_vault_access_policy" "win_vm_access" {
  key_vault_id = azurerm_key_vault.win_kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = azurerm_windows_virtual_machine.vm.identity[0].principal_id

  secret_permissions = [
    "Get", "List"
  ]
}

resource "azurerm_storage_account" "v_store" {
  name                     = "vstoreaccount"
  resource_group_name      = data.azurerm_resource_group.dev_rg.name
  location                 = data.azurerm_resource_group.dev_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  #allow_blob_public_access = false
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.v_store.id
  container_access_type = "private"
}

resource "azurerm_virtual_machine" "example" {
  name                  = "New-v-vm"
  resource_group_name   = "rg-cp-srivaibhavi-b"
  location              = "eastus"   # or your actual region
  network_interface_ids = ["/subscriptions/343c17eb-34b6-4481-92a2-a0a5a04bdd88/resourceGroups/rg-cp-srivaibhavi-b/providers/Microsoft.Network/networkInterfaces/New-v-vm",]
  vm_size               = "Standard_D2s_v3"
  delete_data_disks_on_termination = false
  delete_os_disk_on_termination    = false
  tags                  = {
        "Owner" = "Srivaibhavi.B@kyndryl.com"
    }
  storage_os_disk {
        caching                   = "ReadWrite"
        create_option             = "FromImage"
        disk_size_gb              = 64
        image_uri                 = null
        managed_disk_id           = "/subscriptions/343c17eb-34b6-4481-92a2-a0a5a04bdd88/resourceGroups/rg-cp-srivaibhavi-b/providers/Microsoft.Compute/disks/New-v-vm_OsDisk_1_2f4a5603691249b8829bbf859b0cbcd5"
        managed_disk_type         = "Premium_LRS"
        name                      = "New-v-vm_OsDisk_1_2f4a5603691249b8829bbf859b0cbcd5"
        os_type                   = "Linux"
        vhd_uri                   = null
        write_accelerator_enabled = false
    }
  os_profile {
    computer_name  = "New-v-vm"
    admin_username = "azureadmin"
    admin_password = "PassVM@7"
  }
  os_profile_linux_config {
        disable_password_authentication = false
    }
  storage_image_reference {
        id        = null
        offer     = "RHEL"
        publisher = "RedHat"
        sku       = "8-lvm-gen2"
        version   = "latest"
    }
}
