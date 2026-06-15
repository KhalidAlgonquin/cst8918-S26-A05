# Configure the Terraform runtime requirements.
terraform {
  required_version = ">= 1.1.0"

  required_providers {
    # Azure Resource Manager provider and version
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0.2"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.3"
    }
  }
}

# Define providers and their config params
provider "azurerm" {
  # Leave the features block empty to accept all defaults
  features {}
}

provider "cloudinit" {
  # Configuration options
}

# -----------------------------
# Variables
# -----------------------------

variable "labelPrefix" {
  description = "Your college username. This will form the beginning of various resource names."
  type        = string
}

variable "region" {
  description = "Azure region for the deployment."
  type        = string
  default     = "canadacentral"
}

variable "admin_username" {
  description = "Admin username for the Linux VM."
  type        = string
  default     = "azureadmin"
}

# -----------------------------
# Resource Group
# -----------------------------

resource "azurerm_resource_group" "rg" {
  name     = "${var.labelPrefix}-A05-RG"
  location = var.region
}

# -----------------------------
# Public IP Address
# -----------------------------

resource "azurerm_public_ip" "public_ip" {
  name                = "${var.labelPrefix}-A05-PIP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# -----------------------------
# Virtual Network
# -----------------------------

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.labelPrefix}-A05-VNET"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

# -----------------------------
# Subnet
# -----------------------------

resource "azurerm_subnet" "subnet" {
  name                 = "${var.labelPrefix}-A05-SUBNET"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# -----------------------------
# Network Security Group
# Allows SSH and HTTP traffic
# -----------------------------

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.labelPrefix}-A05-NSG"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "Allow-SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# -----------------------------
# Network Interface Card
# -----------------------------

resource "azurerm_network_interface" "nic" {
  name                = "${var.labelPrefix}-A05-NIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "${var.labelPrefix}-A05-IPCONFIG"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

# -----------------------------
# Apply NSG to NIC
# -----------------------------

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# -----------------------------
# Cloud-init configuration
# -----------------------------

data "cloudinit_config" "web_server_config" {
  gzip          = false
  base64_encode = true

  part {
    filename     = "init.sh"
    content_type = "text/x-shellscript"
    content      = file("${path.module}/init.sh")
  }
}

# -----------------------------
# Linux Virtual Machine
# -----------------------------

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "${var.labelPrefix}-A05-VM"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  size                = "Standard_B1s"
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file("~/.ssh/id_rsa.pub")
  }

  os_disk {
    name                 = "${var.labelPrefix}-A05-OSDISK"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  custom_data = data.cloudinit_config.web_server_config.rendered
}

# -----------------------------
# Output Values
# -----------------------------

output "resource_group_name" {
  description = "Name of the Azure resource group."
  value       = azurerm_resource_group.rg.name
}

output "public_ip_address" {
  description = "Public IP address of the web server."
  value       = azurerm_public_ip.public_ip.ip_address
}

