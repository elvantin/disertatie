// ============================================================
// Packer Template — Ubuntu 22.04 Jumphost Golden Image
// Builds a fully provisioned jumphost with XFCE, xRDP, Ansible,
// Azure CLI, DevOps tools and publishes to Azure Compute Gallery.
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

source "azure-arm" "ubuntu-jumphost" {
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
  temp_resource_group_name = "rg-packer-ubuntu-jumphost-build"

  // Tags applied to the build VM
  azure_tags = {
    project     = "mediasrl"
    environment = "productie"
    managed-by  = "packer"
    owner       = "IT Security SRL"
    os          = "ubuntu-2204-jumphost"
  }
}

// ----- Build Pipeline -----

build {
  sources = ["source.azure-arm.ubuntu-jumphost"]

  // Step 1: Full jumphost provisioning (XFCE, xRDP, Ansible, Azure CLI, tools)
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    script          = "${path.root}/scripts/provision-jumphost.sh"
    pause_before    = "10s"
  }

  // Step 2: Deprovision the Azure Linux Agent (generalize the VM)
  // cloud-init clean MUST run before waagent deprovision — see ubuntu-base
  // build for the full explanation (stale /var/lib/cloud/ cache can make
  // cloud-init skip admin user creation on the next VM's first boot).
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E bash '{{ .Path }}'"
    inline = [
      "cloud-init clean --logs --seed || true",
      "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync"
    ]
  }
}
