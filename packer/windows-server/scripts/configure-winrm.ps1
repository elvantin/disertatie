# ============================================================
# Packer Provisioning Script — Windows Server 2022
# Configures WinRM for Ansible management
# Adapted from bootstrap-windows-winrm.ps1 for image baking
# ============================================================

$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"

Write-Host "========================================="
Write-Host "Packer: Windows Server 2022 WinRM Setup"
Write-Host "========================================="
Write-Host ""

# STEP 1: Enable PowerShell Remoting
Write-Host "[1/7] Enabling PowerShell Remoting..."
Enable-PSRemoting -Force -SkipNetworkProfileCheck
Write-Host "  [OK] PowerShell Remoting enabled"

# STEP 2: Configure WinRM Service
Write-Host "[2/7] Configuring WinRM service..."
Set-Service -Name WinRM -StartupType Automatic
Start-Service -Name WinRM
Write-Host "  [OK] WinRM service configured (Automatic)"

# STEP 3: Configure WinRM HTTP Listener (Port 5985)
Write-Host "[3/7] Configuring WinRM HTTP listener..."
$listeners = Get-ChildItem -Path WSMan:\localhost\Listener -ErrorAction SilentlyContinue
foreach ($listener in $listeners) {
    if ($listener.Keys -contains "Transport=HTTP") {
        Remove-Item -Path $listener.PSPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
New-Item -Path WSMan:\localhost\Listener -Transport HTTP -Address * -Force | Out-Null
Write-Host "  [OK] WinRM HTTP listener configured on port 5985"

# STEP 4: Configure WinRM Settings for Ansible
Write-Host "[4/7] Configuring WinRM settings for Ansible..."
Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force
Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true -Force
Set-Item -Path WSMan:\localhost\Service\Auth\Certificate -Value $false -Force
Set-Item -Path WSMan:\localhost\Service\Auth\Kerberos -Value $true -Force
Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate -Value $true -Force
Set-Item -Path WSMan:\localhost\Service\Auth\CredSSP -Value $true -Force
Set-Item -Path WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 1024 -Force
Set-Item -Path WSMan:\localhost\MaxTimeoutms -Value 1800000 -Force
Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
Write-Host "  [OK] WinRM settings configured for Ansible"

# STEP 5: Configure Windows Firewall Rules
Write-Host "[5/7] Configuring Windows Firewall rules..."
Enable-NetFirewallRule -Name "WINRM-HTTP-In-TCP-PUBLIC" -ErrorAction SilentlyContinue
$firewallRule = Get-NetFirewallRule -Name "WinRM-HTTP-In-TCP" -ErrorAction SilentlyContinue
if (-not $firewallRule) {
    New-NetFirewallRule -Name "WinRM-HTTP-In-TCP" `
        -DisplayName "Windows Remote Management (HTTP-In)" `
        -Enabled True -Direction Inbound -Protocol TCP `
        -LocalPort 5985 -Action Allow -Profile Any | Out-Null
    Write-Host "  [OK] Created WinRM firewall rule"
}
else {
    Set-NetFirewallRule -Name "WinRM-HTTP-In-TCP" -Enabled True -RemoteAddress Any
    Write-Host "  [OK] Updated existing WinRM firewall rule"
}
Set-NetFirewallRule -DisplayGroup "Windows Remote Management" -Enabled True -Profile Any
Write-Host "  [OK] Firewall rules configured"

# STEP 6: Configure CredSSP
Write-Host "[6/7] Configuring CredSSP..."
try {
    Enable-WSManCredSSP -Role Server -Force | Out-Null
    Write-Host "  [OK] CredSSP configured"
}
catch {
    Write-Host "  [WARN] Could not configure CredSSP (non-critical): $_"
}

# STEP 7: Test WinRM Configuration
Write-Host "[7/7] Testing WinRM configuration..."
$testResult = Test-WSMan -ComputerName localhost -ErrorAction Stop
if ($testResult) {
    Write-Host "  [OK] WinRM is responding correctly"
}

Write-Host ""
Write-Host "========================================="
Write-Host "Packer WinRM provisioning complete!"
Write-Host "========================================="
Write-Host ""
Write-Host "Configuration:"
Write-Host "  - HTTP Listener: Port 5985"
Write-Host "  - Authentication: Basic, Negotiate, Kerberos, CredSSP"
Write-Host "  - Service Status: Running (Automatic)"
Write-Host "  - Firewall: Port 5985 open"
Write-Host "========================================="
