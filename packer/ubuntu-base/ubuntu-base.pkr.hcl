// ============================================================
// Packer Template — Ubuntu 22.04 Base Golden Image
// Builds a base Ubuntu image with updates and common packages
// for production VMs (web, app, cms servers).
// ============================================================

packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "~> 2"
    }
  }
}

// ----- Source: Azure ARM Builder -----

source "azure-arm" "ubuntu-base" {
  // Authentication
  use_azure_cli_auth = var.use_azure_cli_auth
  subscription_id    = var.subscription_id
  tenant_id          = var.tenant_id
  client_id          = var.client_id
  client_secret      = var.client_secret

  // Source marketplace image
  os_type         = "Linux"
  image_publisher = var.image_publisher
  image_offer     = var.image_offer
  image_sku       = var.image_sku

  // Build VM configuration
  location = var.location
  vm_size  = var.vm_size

  // Publish to Azure Compute Gallery
  shared_image_gallery_destination {
    resource_group       = var.gallery_resource_group
    gallery_name         = var.gallery_name
    image_name           = var.image_definition
    image_version        = var.image_version
    replication_regions  = var.replication_regions
    storage_account_type = "Standard_LRS"
  }

  // Temporary resource group (auto-created and auto-deleted by Packer)
  temp_resource_group_name = "rg-packer-ubuntu-base-build"

  // Tags applied to the build VM
  azure_tags = {
    project     = "mediasrl"
    environment = "productie"
    managed-by  = "packer"
    owner       = "IT Security SRL"
    os          = "ubuntu-2204-base"
  }
}

// ----- Build Pipeline -----

build {
  sources = ["source.azure-arm.ubuntu-base"]

  // Step 1: Base OS setup — updates, common packages, SSH hardening
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    script          = "${path.root}/scripts/base-setup.sh"
    pause_before    = "10s"
  }

  // Step 2: Deprovision the Azure Linux Agent (generalize the VM)
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    inline = [
      "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync"
    ]
  }
}
