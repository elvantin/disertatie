# ============================================================
# Base Setup — Windows Server 2022 Golden Image
# Installs Windows features, common tools, and prepares
# the OS for role-specific Ansible configuration.
# ============================================================

$ErrorActionPreference = "Stop"

Write-Output "========================================="
Write-Output " Windows Server 2022 — Base Setup"
Write-Output "========================================="

# ----- Install Windows Features -----
Write-Output "[1/5] Installing Windows features..."

$features = @(
    "NET-Framework-45-Core",    # .NET Framework 4.5
    "NET-Framework-45-Features",
    "Windows-Defender",         # Windows Defender
    "RSAT-AD-Tools",            # Remote Server Admin Tools
    "Telnet-Client",            # Telnet client (for diagnostics)
    "SNMP-Service"              # SNMP monitoring
)

foreach ($feature in $features) {
    $result = Install-WindowsFeature -Name $feature -ErrorAction SilentlyContinue
    if ($result.Success) {
        Write-Output "  Installed: $feature"
    } else {
        Write-Output "  Skipped (not available or already installed): $feature"
    }
}

# ----- Configure PowerShell -----
Write-Output "[2/5] Configuring PowerShell..."

# Enable PowerShell script execution for Ansible
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

# Enable PowerShell remoting for Ansible WinRM
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# ----- Configure WinRM for Ansible -----
Write-Output "[3/5] Configuring WinRM for Ansible management..."

# Set WinRM service to auto-start
Set-Service -Name WinRM -StartupType Automatic

# Configure WinRM listener
winrm quickconfig -force | Out-Null

# Allow unencrypted traffic (will be secured by HTTPS in production)
winrm set winrm/config/service '@{AllowUnencrypted="false"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/service/auth '@{CredSSP="true"}'

# Increase WinRM memory limit for Ansible
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="1024"}'

# ----- Configure NTP -----
Write-Output "[4/5] Configuring time synchronization..."

# Configure Windows Time service
w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /reliable:YES /update | Out-Null
Restart-Service w32time -ErrorAction SilentlyContinue
w32tm /resync /force | Out-Null

# ----- Install Windows Updates -----
Write-Output "[5/5] Installing Windows Updates..."

# Install PSWindowsUpdate module for update management
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
Install-Module -Name PSWindowsUpdate -Force -Confirm:$false | Out-Null
Import-Module PSWindowsUpdate

# Install all available updates (critical + security)
Write-Output "  Downloading and installing updates (this may take a while)..."
Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -ErrorAction SilentlyContinue | Out-Null

Write-Output "========================================="
Write-Output " Base Setup Complete"
Write-Output "========================================="
