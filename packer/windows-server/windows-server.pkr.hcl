// ============================================================
// Packer Template — Windows Server 2022 Golden Image
// Builds a hardened Windows Server 2022 image and publishes
// it to Azure Compute Gallery for use by Bicep deployments.
//
// Build pipeline (in order):
//   1.  configure-winrm.ps1   — WinRM for Packer communication
//   2.  windows-restart        — clears Azure first-boot pending ops
//   3.  base-setup.ps1         — features, VC++, WU round 1
//   4.  windows-restart        — clears round-1 update pending ops
//   5.  inline WU round 2      — catches updates that need previous updates
//   6.  windows-restart        — clears round-2 pending ops
//   7.  hardening.ps1          — CIS baseline hardening
//   8.  windows-restart        — clears hardening-induced pending ops
//   9.  prepare-for-sysprep.ps1 — stops WU, clears cache, verifies COM
//  10.  timezone + cleanup      — final inline steps
//  11.  sysprep                 — generalize image
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
    resource_group       = var.gallery_resource_group
    gallery_name         = var.gallery_name
    image_name           = var.image_definition
    image_version        = var.image_version
    replication_regions  = var.replication_regions
    storage_account_type = "Standard_LRS"
  }

  // Temporary resource group (auto-created and auto-deleted by Packer)
  temp_resource_group_name = "rg-packer-windows-build"

  // Tags applied to the build VM
  azure_tags = {
    project     = "media"
    environment = "prod"
    managed-by  = "packer"
    owner       = "SC MEDIA SRL"
    os          = "windows-server-2022"
  }
}

// ----- Build Pipeline -----

build {
  sources = ["source.azure-arm.windows-server"]

  // ── Step 1: Configure WinRM so Packer can communicate ────────────────────────
  provisioner "powershell" {
    script = "${path.root}/scripts/configure-winrm.ps1"
  }

  // ── Step 2: Initial reboot ────────────────────────────────────────────────────
  // Azure marketplace images complete first-boot setup on the first boot inside
  // Packer. That process leaves PendingFileRenameOperations in the registry.
  // Rebooting here clears those entries so subsequent steps start with a clean
  // COM/Task Scheduler state.
  provisioner "windows-restart" {
    restart_timeout      = "15m"
    restart_check_command = "powershell -command \"& {Write-Output 'Restarted'}\""
  }

  // ── Step 3: Base setup — features, VC++, Windows Update (round 1) ─────────────
  // Timeout: 2h to accommodate large cumulative update downloads on fresh images.
  provisioner "powershell" {
    script  = "${path.root}/scripts/base-setup.ps1"
    timeout = "7200s"
  }

  // ── Step 4: Reboot after update round 1 ──────────────────────────────────────
  // Clears PendingFileRenameOperations created by installed updates.
  // Required before round 2 so the new kernel/drivers are active.
  provisioner "windows-restart" {
    restart_timeout      = "20m"
    restart_check_command = "powershell -command \"& {Write-Output 'Restarted'}\""
  }

  // ── Step 5: Windows Update round 2 ───────────────────────────────────────────
  // Many updates unlock additional updates only after the first batch is applied.
  // This second round catches those and leaves the image fully patched.
  provisioner "powershell" {
    timeout = "7200s"
    inline = [
      "Write-Output '--- Windows Update Round 2 ---'",
      "$ErrorActionPreference = 'Continue'",
      "try {",
      "  $session  = New-Object -ComObject Microsoft.Update.Session",
      "  $searcher = $session.CreateUpdateSearcher()",
      "  $result   = $searcher.Search(\"IsInstalled=0 AND IsHidden=0 AND Type='Software'\")",
      "  Write-Output \"Updates available: $($result.Updates.Count)\"",
      "  if ($result.Updates.Count -gt 0) {",
      "    $updates = New-Object -ComObject Microsoft.Update.UpdateColl",
      "    foreach ($u in $result.Updates) { $updates.Add($u) | Out-Null }",
      "    $dl = $session.CreateUpdateDownloader(); $dl.Updates = $updates; $dl.Download() | Out-Null",
      "    $inst = $session.CreateUpdateInstaller(); $inst.Updates = $updates",
      "    $res = $inst.Install()",
      "    Write-Output \"Round 2 result: $($res.ResultCode), reboot: $($res.RebootRequired)\"",
      "  }",
      "} catch {",
      "  Write-Output \"Round 2 COM approach failed: $_\"",
      "  Write-Output 'Falling back to PSWindowsUpdate...'",
      "  try {",
      "    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {",
      "      Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null",
      "      Install-Module -Name PSWindowsUpdate -Force -Confirm:$false | Out-Null",
      "    }",
      "    Import-Module PSWindowsUpdate",
      "    Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -ErrorAction SilentlyContinue | Out-Null",
      "  } catch { Write-Output \"PSWindowsUpdate also failed: $_\" }",
      "}",
      "Write-Output '--- Windows Update Round 2 done ---'"
    ]
  }

  // ── Step 6: Reboot after update round 2 ──────────────────────────────────────
  provisioner "windows-restart" {
    restart_timeout      = "20m"
    restart_check_command = "powershell -command \"& {Write-Output 'Restarted'}\""
  }

  // ── Step 7: CIS baseline hardening ───────────────────────────────────────────
  provisioner "powershell" {
    script = "${path.root}/scripts/hardening.ps1"
  }

  // ── Step 8: Reboot after hardening ───────────────────────────────────────────
  // TLS registry changes and service disabling create pending ops.
  provisioner "windows-restart" {
    restart_timeout      = "15m"
    restart_check_command = "powershell -command \"& {Write-Output 'Restarted'}\""
  }

  // ── Step 9: Pre-sysprep cleanup and COM verification ─────────────────────────
  // Stops WU services, clears download cache (~1-3 GB), re-registers COM DLLs,
  // and VERIFIES that Task Scheduler and Windows Update COM are working.
  // Fails the Packer build if COM is still broken — better to fix now than to
  // bake a broken image that will fail every Ansible win_updates run.
  provisioner "powershell" {
    script = "${path.root}/scripts/prepare-for-sysprep.ps1"
  }

  // ── Step 10: Set timezone to Romania ─────────────────────────────────────────
  provisioner "powershell" {
    inline = [
      "Write-Output 'Setting timezone to Europe/Bucharest...'",
      "Set-TimeZone -Id 'E. Europe Standard Time'",
      "Write-Output \"Timezone: $((Get-TimeZone).DisplayName)\""
    ]
  }

  // ── Step 11: Final cleanup before sysprep ────────────────────────────────────
  provisioner "powershell" {
    inline = [
      "Write-Output 'Final cleanup...'",
      "Remove-Item -Path $env:TEMP\\* -Recurse -Force -ErrorAction SilentlyContinue",
      "Remove-Item -Path C:\\Windows\\Temp\\* -Recurse -Force -ErrorAction SilentlyContinue",
      "Clear-EventLog -LogName Application,System,Security -ErrorAction SilentlyContinue",
      "Write-Output 'Cleanup done'"
    ]
  }

  // ── Step 12: Generalize with Sysprep ─────────────────────────────────────────
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
