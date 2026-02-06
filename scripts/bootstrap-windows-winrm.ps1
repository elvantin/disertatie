# ============================================================
# WinRM Bootstrap Script for Windows Server VMs
# Enables WinRM for Ansible Connectivity
# ============================================================

# Enable verbose logging
$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"

# Setup logging
$LogFile = "C:\Temp\winrm-bootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
New-Item -Path "C:\Temp" -ItemType Directory -Force | Out-Null
Start-Transcript -Path $LogFile -Append

Write-Host "========================================="
Write-Host "SC MEDIA SRL - Windows WinRM Bootstrap"
Write-Host "Windows Server 2022 Configuration"
Write-Host "Logging to: $LogFile"
Write-Host "========================================="
Write-Host ""

# =============================================================================
# STEP 1: Enable PowerShell Remoting
# =============================================================================

Write-Host "[1/8] Enabling PowerShell Remoting..." -ForegroundColor Cyan
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    Write-Host "  ✓ PowerShell Remoting enabled" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Failed to enable PowerShell Remoting: $_" -ForegroundColor Red
    throw
}

# =============================================================================
# STEP 2: Configure WinRM Service
# =============================================================================

Write-Host "[2/8] Configuring WinRM service..." -ForegroundColor Cyan
try {
    # Set WinRM service to automatic start
    Set-Service -Name WinRM -StartupType Automatic

    # Start WinRM service
    Start-Service -Name WinRM

    # Verify service is running
    $winrmStatus = Get-Service -Name WinRM
    if ($winrmStatus.Status -eq "Running") {
        Write-Host "  ✓ WinRM service is running" -ForegroundColor Green
    } else {
        throw "WinRM service failed to start"
    }
} catch {
    Write-Host "  ✗ Failed to configure WinRM service: $_" -ForegroundColor Red
    throw
}

# =============================================================================
# STEP 3: Configure WinRM for HTTP (Port 5985)
# =============================================================================

Write-Host "[3/8] Configuring WinRM HTTP listener..." -ForegroundColor Cyan
try {
    # Remove existing HTTP listener if present
    Get-ChildItem -Path WSMan:\localhost\Listener | Where-Object { $_.Keys -contains "Transport=HTTP" } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # Create new HTTP listener
    New-Item -Path WSMan:\localhost\Listener -Transport HTTP -Address * -Force | Out-Null

    Write-Host "  ✓ WinRM HTTP listener configured on port 5985" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Failed to configure HTTP listener: $_" -ForegroundColor Red
    throw
}

# =============================================================================
# STEP 4: Configure WinRM Settings for Ansible
# =============================================================================

Write-Host "[4/8] Configuring WinRM settings for Ansible..." -ForegroundColor Cyan
try {
    # Allow unencrypted traffic (required for HTTP, but use with caution)
    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force

    # Configure authentication methods
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Certificate -Value $false -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Kerberos -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\CredSSP -Value $true -Force

    # Increase memory limit for PowerShell commands
    Set-Item -Path WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 1024 -Force

    # Increase timeout values
    Set-Item -Path WSMan:\localhost\MaxTimeoutms -Value 1800000 -Force

    # Configure trusted hosts (allow all for internal network)
    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

    Write-Host "  ✓ WinRM settings configured for Ansible" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Failed to configure WinRM settings: $_" -ForegroundColor Red
    throw
}

# =============================================================================
# STEP 5: Configure Windows Firewall Rules
# =============================================================================

Write-Host "[5/8] Configuring Windows Firewall rules..." -ForegroundColor Cyan
try {
    # Enable WinRM HTTP firewall rule
    Enable-NetFirewallRule -Name "WINRM-HTTP-In-TCP-PUBLIC" -ErrorAction SilentlyContinue

    # Create custom firewall rule if needed
    $firewallRule = Get-NetFirewallRule -Name "WinRM-HTTP-In-TCP" -ErrorAction SilentlyContinue
    if (-not $firewallRule) {
        New-NetFirewallRule -Name "WinRM-HTTP-In-TCP" `
            -DisplayName "Windows Remote Management (HTTP-In)" `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort 5985 `
            -Action Allow `
            -Profile Any | Out-Null
        Write-Host "  ✓ Created WinRM firewall rule" -ForegroundColor Green
    } else {
        Set-NetFirewallRule -Name "WinRM-HTTP-In-TCP" -Enabled True -RemoteAddress Any
        Write-Host "  ✓ Updated existing WinRM firewall rule" -ForegroundColor Green
    }

    # Allow WinRM through all network profiles
    Set-NetFirewallRule -DisplayGroup "Windows Remote Management" -Enabled True -Profile Any

    Write-Host "  ✓ Firewall rules configured" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Failed to configure firewall rules: $_" -ForegroundColor Red
    throw
}

# =============================================================================
# STEP 6: Configure Network Connection Profile
# =============================================================================

Write-Host "[6/8] Configuring network connection profile..." -ForegroundColor Cyan
try {
    # Set network profile to Private (required for WinRM)
    $networkProfile = Get-NetConnectionProfile
    if ($networkProfile.NetworkCategory -ne "Private") {
        Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
        Write-Host "  ✓ Network profile set to Private" -ForegroundColor Green
    } else {
        Write-Host "  ✓ Network profile already set to Private" -ForegroundColor Green
    }
} catch {
    Write-Host "  ⚠ Could not set network profile (non-critical): $_" -ForegroundColor Yellow
}

# =============================================================================
# STEP 7: Configure Local Security Policy for WinRM
# =============================================================================

Write-Host "[7/8] Configuring local security policy..." -ForegroundColor Cyan
try {
    # Enable CredSSP for delegated authentication
    Enable-WSManCredSSP -Role Server -Force | Out-Null

    Write-Host "  ✓ CredSSP configured for delegated authentication" -ForegroundColor Green
} catch {
    Write-Host "  ⚠ Could not configure CredSSP (non-critical): $_" -ForegroundColor Yellow
}

# =============================================================================
# STEP 8: Test WinRM Configuration
# =============================================================================

Write-Host "[8/8] Testing WinRM configuration..." -ForegroundColor Cyan
try {
    # Test WinRM locally
    $testResult = Test-WSMan -ComputerName localhost -ErrorAction Stop

    if ($testResult) {
        Write-Host "  ✓ WinRM is responding correctly" -ForegroundColor Green
    }

    # Display WinRM configuration
    Write-Host ""
    Write-Host "WinRM Configuration Summary:" -ForegroundColor Cyan
    winrm get winrm/config

} catch {
    Write-Host "  ✗ WinRM test failed: $_" -ForegroundColor Red
    throw
}

# =============================================================================
# COMPLETION
# =============================================================================

Write-Host ""
Write-Host "========================================="
Write-Host "WinRM Bootstrap Complete!"
Write-Host "========================================="
Write-Host ""
Write-Host "WinRM Configuration Summary:" -ForegroundColor Green
Write-Host "  - HTTP Listener: Port 5985" -ForegroundColor White
Write-Host "  - Authentication: Basic, Negotiate, Kerberos, CredSSP" -ForegroundColor White
Write-Host "  - Service Status: Running (Automatic)" -ForegroundColor White
Write-Host "  - Firewall: Configured (Port 5985 open)" -ForegroundColor White
Write-Host ""
Write-Host "Test from Ansible Control Node (Jumphost):" -ForegroundColor Cyan
Write-Host "  ansible windows -m win_ping" -ForegroundColor White
Write-Host ""
Write-Host "Ansible Inventory Configuration:" -ForegroundColor Cyan
Write-Host "  ansible_connection=winrm" -ForegroundColor White
Write-Host "  ansible_winrm_transport=ntlm" -ForegroundColor White
Write-Host "  ansible_winrm_server_cert_validation=ignore" -ForegroundColor White
Write-Host "  ansible_port=5985" -ForegroundColor White
Write-Host ""
Write-Host "Bootstrap Log File: $LogFile" -ForegroundColor Yellow
Write-Host "========================================="

Stop-Transcript

# Reboot notification (optional - uncomment if reboot is required)
# Write-Host ""
# Write-Host "System will reboot in 30 seconds..." -ForegroundColor Yellow
# Start-Sleep -Seconds 30
# Restart-Computer -Force
