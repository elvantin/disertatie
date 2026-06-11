# ============================================================
# WinRM Bootstrap Script for Windows Server VMs
# Enables WinRM for Ansible Connectivity
# ============================================================

$VerbosePreference = "Continue"
$ErrorActionPreference = "Stop"

# Log file on the Windows VM (no shared library — this runs as Custom Script Extension)
$LogDir  = "C:\Logs\mediasrl"
$LogFile = "$LogDir\winrm-bootstrap-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
Start-Transcript -Path $LogFile -Append

# Inline logging helpers (no lib available in CSE context)
function _LogOK([string]$m)   { Write-Host "  [OK] $m" -ForegroundColor Green  }
function _LogFail([string]$m) { Write-Host "  [!!] $m" -ForegroundColor Red    }
function _LogWarn([string]$m) { Write-Host "  [!]  $m" -ForegroundColor Yellow }
function _LogStep([string]$m) { Write-Host "  [>>] $m" -ForegroundColor Yellow }

$_StartTime = Get-Date
$_OK = 0; $_FAIL = 0; $_WARN = 0

Write-Host ""
Write-Host ("  " + ("=" * 58)) -ForegroundColor Cyan
Write-Host "  SC MEDIA SRL — Windows WinRM Bootstrap" -ForegroundColor White
Write-Host "  Windows Server 2022 · $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "  Log: $LogFile" -ForegroundColor DarkGray
Write-Host ("  " + ("=" * 58)) -ForegroundColor Cyan
Write-Host ""

# STEP 1: Enable PowerShell Remoting
_LogStep "[1/8] Enabling PowerShell Remoting..."
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    _LogOK "PowerShell Remoting enabled"; $_OK++
}
catch {
    _LogFail "Failed to enable PowerShell Remoting: $_"; $_FAIL++
    throw
}

# STEP 2: Configure WinRM Service
_LogStep "[2/8] Configuring WinRM service..."
try {
    Set-Service -Name WinRM -StartupType Automatic
    Start-Service -Name WinRM
    $winrmStatus = Get-Service -Name WinRM
    if ($winrmStatus.Status -eq "Running") {
        _LogOK "WinRM service is running"; $_OK++
    } else {
        throw "WinRM service failed to start"
    }
}
catch {
    _LogFail "Failed to configure WinRM service: $_"; $_FAIL++
    throw
}

# STEP 3: Configure WinRM for HTTP (Port 5985)
_LogStep "[3/8] Configuring WinRM HTTP listener (port 5985)..."
try {
    $listeners = Get-ChildItem -Path WSMan:\localhost\Listener -ErrorAction SilentlyContinue
    foreach ($listener in $listeners) {
        if ($listener.Keys -contains "Transport=HTTP") {
            Remove-Item -Path $listener.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    New-Item -Path WSMan:\localhost\Listener -Transport HTTP -Address * -Force | Out-Null
    _LogOK "WinRM HTTP listener configured on port 5985"; $_OK++
}
catch {
    _LogFail "Failed to configure HTTP listener: $_"; $_FAIL++
    throw
}

# STEP 4: Configure WinRM Settings for Ansible
_LogStep "[4/8] Configuring WinRM settings for Ansible..."
try {
    Set-Item -Path WSMan:\localhost\Service\AllowUnencrypted -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Basic       -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Certificate -Value $false -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Kerberos    -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate   -Value $true -Force
    Set-Item -Path WSMan:\localhost\Service\Auth\CredSSP     -Value $true -Force
    Set-Item -Path WSMan:\localhost\Shell\MaxMemoryPerShellMB -Value 1024 -Force
    Set-Item -Path WSMan:\localhost\MaxTimeoutms             -Value 1800000 -Force
    Set-Item -Path WSMan:\localhost\Client\TrustedHosts      -Value "*" -Force
    _LogOK "WinRM settings configured (Basic, Kerberos, Negotiate, CredSSP)"; $_OK++
}
catch {
    _LogFail "Failed to configure WinRM settings: $_"; $_FAIL++
    throw
}

# STEP 5: Configure Windows Firewall Rules
_LogStep "[5/8] Configuring Windows Firewall rules..."
try {
    Enable-NetFirewallRule -Name "WINRM-HTTP-In-TCP-PUBLIC" -ErrorAction SilentlyContinue
    $firewallRule = Get-NetFirewallRule -Name "WinRM-HTTP-In-TCP" -ErrorAction SilentlyContinue
    if (-not $firewallRule) {
        New-NetFirewallRule -Name "WinRM-HTTP-In-TCP" -DisplayName "Windows Remote Management (HTTP-In)" `
            -Enabled True -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any | Out-Null
        _LogOK "WinRM firewall rule created (port 5985 inbound)"; $_OK++
    } else {
        Set-NetFirewallRule -Name "WinRM-HTTP-In-TCP" -Enabled True -RemoteAddress Any
        _LogOK "WinRM firewall rule updated (port 5985 inbound)"; $_OK++
    }
    Set-NetFirewallRule -DisplayGroup "Windows Remote Management" -Enabled True -Profile Any
}
catch {
    _LogFail "Failed to configure firewall rules: $_"; $_FAIL++
    throw
}

# STEP 6: Configure Network Connection Profile
_LogStep "[6/8] Configuring network connection profile..."
try {
    $networkProfile = Get-NetConnectionProfile
    if ($networkProfile.NetworkCategory -ne "Private") {
        Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
        _LogOK "Network profile set to Private"; $_OK++
    } else {
        _LogOK "Network profile already Private"; $_OK++
    }
}
catch {
    _LogWarn "Could not set network profile (non-critical): $_"; $_WARN++
}

# STEP 7: Configure CredSSP
_LogStep "[7/8] Configuring CredSSP for delegated authentication..."
try {
    Enable-WSManCredSSP -Role Server -Force | Out-Null
    _LogOK "CredSSP configured"; $_OK++
}
catch {
    _LogWarn "Could not configure CredSSP (non-critical): $_"; $_WARN++
}

# STEP 8: Test WinRM Configuration
_LogStep "[8/8] Testing WinRM configuration..."
try {
    $testResult = Test-WSMan -ComputerName localhost -ErrorAction Stop
    if ($testResult) {
        _LogOK "WinRM responding correctly on localhost"; $_OK++
    }
    Write-Host ""
    winrm get winrm/config
}
catch {
    _LogFail "WinRM test failed: $_"; $_FAIL++
    throw
}

# Summary
$_Dur = [int]((Get-Date) - $_StartTime).TotalSeconds
$_DurStr = "$([int]$_Dur/60)m $($_Dur%60)s"
$_SumColor = if ($_FAIL -gt 0) { 'Red' } elseif ($_WARN -gt 0) { 'Yellow' } else { 'Green' }

Write-Host ""
Write-Host ("  " + ("=" * 58)) -ForegroundColor $_SumColor
Write-Host "  WinRM Bootstrap $(if ($_FAIL -gt 0) { 'FAILED' } else { 'COMPLETE' })" -ForegroundColor $_SumColor
Write-Host ("  " + ("=" * 58)) -ForegroundColor $_SumColor
Write-Host "  Durată : $_DurStr   |   OK: $_OK   FAIL: $_FAIL   WARN: $_WARN" -ForegroundColor Gray
Write-Host "  Port   : 5985 (HTTP)  |  Auth: Basic, Negotiate, Kerberos, CredSSP" -ForegroundColor Gray
Write-Host "  Test   : ansible windows -m win_ping" -ForegroundColor Gray
Write-Host "  Log    : $LogFile" -ForegroundColor DarkGray
Write-Host ("  " + ("=" * 58)) -ForegroundColor $_SumColor

Stop-Transcript
