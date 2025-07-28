variable "admin_ssh_key" {
  description = "Public SSH Key for the VM"
  type        = string
}

variable "admin_username" {
  description = "Admin username for the VM"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "vm_name" {
  description = "Name of the Virtual Machine"
  type        = string
}