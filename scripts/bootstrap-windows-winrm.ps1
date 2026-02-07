# ============================================================
# WinRM Bootstrap Script for Windows Server VMs
# Enables WinRM for Ansible Connectivity
# ============================================================

$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"

$LogFile = "C:\Temp\winrm-bootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
New-Item -Path "C:\Temp" -ItemType Directory -Force | Out-Null
Start-Transcript -Path $LogFile -Append

Write-Host "========================================="
Write-Host "SC MEDIA SRL - Windows WinRM Bootstrap"
Write-Host "Windows Server 2022 Configuration"
Write-Host "Logging to: $LogFile"
Write-Host "========================================="
Write-Host ""

# STEP 1: Enable PowerShell Remoting
Write-Host "[1/8] Enabling PowerShell Remoting..."
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    Write-Host "  [OK] PowerShell Remoting enabled"
}
catch {
    Write-Host "  [FAIL] Failed to enable PowerShell Remoting: $_"
    throw
}

# STEP 2: Configure WinRM Service
Write-Host "[2/8] Configuring WinRM service..."
try {
    Set-Service -Name WinRM -StartupType Automatic
    Start-Service -Name WinRM
    $winrmStatus = Get-Service -Name WinRM
    if ($winrmStatus.Status -eq "Running") {
        Write-Host "  [OK] WinRM service is running"
    }
    else {
        throw "WinRM service failed to start"
    }
}
catch {
    Write-Host "  [FAIL] Failed to configure WinRM service: $_"
    throw
}

# STEP 3: Configure WinRM for HTTP (Port 5985)
Write-Host "[3/8] Configuring WinRM HTTP listener..."
try {
    $listeners = Get-ChildItem -Path WSMan:\localhost\Listener -ErrorAction SilentlyContinue
    foreach ($listener in $listeners) {
        if ($listener.Keys -contains "Transport=HTTP") {
            Remove-Item -Path $listener.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    New-Item -Path WSMan:\localhost\Listener -Transport HTTP -Address * -Force | Out-Null
    Write-Host "  [OK] WinRM HTTP listener configured on port 5985"
}
catch {
    Write-Host "  [FAIL] Failed to configure HTTP listener: $_"
    throw
}

# STEP 4: Configure WinRM Settings for Ansible
Write-Host "[4/8] Configuring WinRM settings for Ansible..."
try {
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
}
catch {
    Write-Host "  [FAIL] Failed to configure WinRM settings: $_"
    throw
}

# STEP 5: Configure Windows Firewall Rules
Write-Host "[5/8] Configuring Windows Firewall rules..."
try {
    Enable-NetFirewallRule -Name "WINRM-HTTP-In-TCP-PUBLIC" -ErrorAction SilentlyContinue
    $firewallRule = Get-NetFirewallRule -Name "WinRM-HTTP-In-TCP" -ErrorAction SilentlyContinue
    if (-not $firewallRule) {
        New-NetFirewallRule -Name "WinRM-HTTP-In-TCP" -DisplayName "Windows Remote Management (HTTP-In)" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any | Out-Null
        Write-Host "  [OK] Created WinRM firewall rule"
    }
    else {
        Set-NetFirewallRule -Name "WinRM-HTTP-In-TCP" -Enabled True -RemoteAddress Any
        Write-Host "  [OK] Updated existing WinRM firewall rule"
    }
    Set-NetFirewallRule -DisplayGroup "Windows Remote Management" -Enabled True -Profile Any
    Write-Host "  [OK] Firewall rules configured"
}
catch {
    Write-Host "  [FAIL] Failed to configure firewall rules: $_"
    throw
}

# STEP 6: Configure Network Connection Profile
Write-Host "[6/8] Configuring network connection profile..."
try {
    $networkProfile = Get-NetConnectionProfile
    if ($networkProfile.NetworkCategory -ne "Private") {
        Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
        Write-Host "  [OK] Network profile set to Private"
    }
    else {
        Write-Host "  [OK] Network profile already set to Private"
    }
}
catch {
    Write-Host "  [WARN] Could not set network profile (non-critical): $_"
}

# STEP 7: Configure Local Security Policy for WinRM
Write-Host "[7/8] Configuring local security policy..."
try {
    Enable-WSManCredSSP -Role Server -Force | Out-Null
    Write-Host "  [OK] CredSSP configured for delegated authentication"
}
catch {
    Write-Host "  [WARN] Could not configure CredSSP (non-critical): $_"
}

# STEP 8: Test WinRM Configuration
Write-Host "[8/8] Testing WinRM configuration..."
try {
    $testResult = Test-WSMan -ComputerName localhost -ErrorAction Stop
    if ($testResult) {
        Write-Host "  [OK] WinRM is responding correctly"
    }
    Write-Host ""
    Write-Host "WinRM Configuration Summary:"
    winrm get winrm/config
}
catch {
    Write-Host "  [FAIL] WinRM test failed: $_"
    throw
}

# COMPLETION
Write-Host ""
Write-Host "========================================="
Write-Host "WinRM Bootstrap Complete!"
Write-Host "========================================="
Write-Host ""
Write-Host "Configuration:"
Write-Host "  - HTTP Listener: Port 5985"
Write-Host "  - Authentication: Basic, Negotiate, Kerberos, CredSSP"
Write-Host "  - Service Status: Running (Automatic)"
Write-Host "  - Firewall: Configured (Port 5985 open)"
Write-Host ""
Write-Host "Test from Jumphost: ansible windows -m win_ping"
Write-Host "Bootstrap Log File: $LogFile"
Write-Host "========================================="

Stop-Transcript
