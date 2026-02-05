// ============================================================
// Packer Template — Windows Server 2022 Golden Image
// Builds a hardened Windows Server 2022 image and publishes
// it to Azure Compute Gallery for use by Bicep deployments.
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

source "azure-arm" "windows-server" {
  // Authentication
  use_azure_cli_auth = var.use_azure_cli_auth
  subscription_id    = var.subscription_id
  tenant_id          = var.tenant_id
  client_id          = var.client_id
  client_secret      = var.client_secret

  // Source marketplace image
  os_type         = "Windows"
  image_publisher = var.image_publisher
  image_offer     = var.image_offer
  image_sku       = var.image_sku

  // Build VM configuration
  location = var.location
  vm_size  = var.vm_size

  // WinRM communication
  communicator   = "winrm"
  winrm_use_ssl  = true
  winrm_insecure = true
  winrm_timeout  = "10m"
  winrm_username = var.winrm_username

  // Publish to Azure Compute Gallery
  shared_image_gallery_destination {
    resource_group = var.gallery_resource_group
    gallery_name   = var.gallery_name
    image_name     = var.image_definition
    image_version  = var.image_version
    replication_regions = var.replication_regions
    storage_account_type = "Standard_LRS"
  }

  // Temporary resource group (auto-created and auto-deleted by Packer)
  temp_resource_group_name = "rg-packer-windows-build"

  // Tags applied to the build VM
  azure_tags = {
    project     = "media"
    environment = "prod"
    managed-by  = "packer"
    owner       = "IT Security SRL"
    os          = "windows-server-2022"
  }
}

// ----- Build Pipeline -----

build {
  sources = ["source.azure-arm.windows-server"]

  // Step 1: Base OS setup — features, tools, updates
  provisioner "powershell" {
    script = "${path.root}/scripts/base-setup.ps1"
  }

  // Step 2: CIS Benchmark hardening
  provisioner "powershell" {
    script = "${path.root}/scripts/hardening.ps1"
  }

  // Step 3: Run Windows Update
  provisioner "windows-restart" {
    restart_timeout = "15m"
  }

  // Step 4: Final cleanup before sysprep
  provisioner "powershell" {
    inline = [
      "Write-Output 'Cleaning up temporary files...'",
      "Remove-Item -Path $env:TEMP\\* -Recurse -Force -ErrorAction SilentlyContinue",
      "Remove-Item -Path C:\\Windows\\Temp\\* -Recurse -Force -ErrorAction SilentlyContinue",
      "Clear-EventLog -LogName Application,System,Security -ErrorAction SilentlyContinue"
    ]
  }

  // Step 5: Generalize with Sysprep
  provisioner "powershell" {
    inline = [
      "Write-Output 'Running Sysprep...'",
      "& $env:SystemRoot\\System32\\Sysprep\\Sysprep.exe /oobe /generalize /quiet /quit /mode:vm",
      "while ($true) {",
      "  $imageState = (Get-ItemProperty HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Setup\\State).ImageState",
      "  Write-Output \"Image state: $imageState\"",
      "  if ($imageState -eq 'IMAGE_STATE_GENERALIZE_RESEAL_TO_OOBE') { break }",
      "  Start-Sleep -Seconds 10",
      "}"
    ]
  }
}
