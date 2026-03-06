# ============================================================
# CIS Hardening — Windows Server 2022 Golden Image
# Applies baseline CIS Benchmark controls.
# Additional role-specific hardening is applied by Ansible.
# ============================================================

$ErrorActionPreference = "Stop"

Write-Output "========================================="
Write-Output " Windows Server 2022 — CIS Hardening"
Write-Output "========================================="

# =============================================================
# 1. ACCOUNT AND PASSWORD POLICIES (CIS 1.1.x, 1.2.x)
# =============================================================
Write-Output "[1/8] Configuring account and password policies..."

# Export current security policy, modify, and re-import
$secEditPath = "$env:TEMP\secpol.cfg"
secedit /export /cfg $secEditPath | Out-Null

# Password policies (CIS 1.1.x)
(Get-Content $secEditPath) -replace 'MinimumPasswordAge\s*=\s*\d+', 'MinimumPasswordAge = 1' |
    Set-Content $secEditPath
(Get-Content $secEditPath) -replace 'MaximumPasswordAge\s*=\s*\d+', 'MaximumPasswordAge = 90' |
    Set-Content $secEditPath
(Get-Content $secEditPath) -replace 'MinimumPasswordLength\s*=\s*\d+', 'MinimumPasswordLength = 14' |
    Set-Content $secEditPath
(Get-Content $secEditPath) -replace 'PasswordComplexity\s*=\s*\d+', 'PasswordComplexity = 1' |
    Set-Content $secEditPath
(Get-Content $secEditPath) -replace 'PasswordHistorySize\s*=\s*\d+', 'PasswordHistorySize = 24' |
    Set-Content $secEditPath

# Account lockout policies (CIS 1.2.x)
(Get-Content $secEditPath) -replace 'LockoutBadCount\s*=\s*\d+', 'LockoutBadCount = 5' |
    Set-Content $secEditPath
(Get-Content $secEditPath) -replace 'LockoutDuration\s*=\s*\d+', 'LockoutDuration = 15' |
    Set-Content $secEditPath
(Get-Content $secEditPath) -replace 'ResetLockoutCount\s*=\s*\d+', 'ResetLockoutCount = 15' |
    Set-Content $secEditPath

secedit /configure /db C:\Windows\security\local.sdb /cfg $secEditPath /areas SECURITYPOLICY | Out-Null
Remove-Item $secEditPath -Force -ErrorAction SilentlyContinue

# =============================================================
# 2. AUDIT POLICIES (CIS 17.x)
# =============================================================
Write-Output "[2/8] Configuring audit policies..."

$auditCategories = @{
    "Account Logon"       = "Success,Failure"
    "Account Management"  = "Success,Failure"
    "Logon/Logoff"        = "Success,Failure"
    "Object Access"       = "Failure"
    "Policy Change"       = "Success,Failure"
    "Privilege Use"       = "Success,Failure"
    "System"              = "Success,Failure"
}

foreach ($category in $auditCategories.GetEnumerator()) {
    auditpol /set /category:"$($category.Key)" /success:enable /failure:enable 2>$null | Out-Null
}

# =============================================================
# 3. DISABLE UNNECESSARY SERVICES (CIS 5.x)
# =============================================================
Write-Output "[3/8] Disabling unnecessary services..."

$servicesToDisable = @(
    "Browser",          # Computer Browser
    "IISADMIN",         # IIS Admin Service
    "irmon",            # Infrared Monitor
    "SharedAccess",     # Internet Connection Sharing
    "LxssManager",      # Windows Subsystem for Linux
    "FTPSVC",           # FTP Publishing Service
    "RpcLocator",       # Remote Procedure Call Locator
    "RemoteAccess",     # Routing and Remote Access
    "simptcp",          # Simple TCP/IP Services
    "SSDPSRV",          # SSDP Discovery
    "upnphost",         # UPnP Device Host
    "WMSvc",            # Web Management Service
    "WMPNetworkSvc",    # Windows Media Player Network Sharing
    "icssvc",           # Windows Mobile Hotspot
    "XblAuthManager",   # Xbox Live Auth Manager
    "XblGameSave",      # Xbox Live Game Save
    "XboxNetApiSvc"     # Xbox Live Networking Service
)

foreach ($svc in $servicesToDisable) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service -and $service.StartType -ne 'Disabled') {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Output "  Disabled: $svc"
    }
}

# =============================================================
# 4. WINDOWS FIREWALL HARDENING (CIS 9.x)
# =============================================================
Write-Output "[4/8] Configuring Windows Firewall..."

# Enable Windows Firewall for all profiles
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True

# Set default policies: block inbound, allow outbound
Set-NetFirewallProfile -Profile Domain,Public,Private `
    -DefaultInboundAction Block `
    -DefaultOutboundAction Allow

# Enable firewall logging
$logPath = "%SystemRoot%\System32\LogFiles\Firewall\pfirewall.log"
Set-NetFirewallProfile -Profile Domain -LogFileName $logPath -LogBlocked True -LogMaxSizeKilobytes 16384
Set-NetFirewallProfile -Profile Private -LogFileName $logPath -LogBlocked True -LogMaxSizeKilobytes 16384
Set-NetFirewallProfile -Profile Public -LogFileName $logPath -LogBlocked True -LogMaxSizeKilobytes 16384

# Allow ICMP Echo (ping) inbound — needed for monitoring and VNet diagnostics.
# DefaultInboundAction=Block above would otherwise silently drop pings.
New-NetFirewallRule -DisplayName "Allow-ICMP-Echo-In" `
    -Name "Allow-ICMP-Echo-In" `
    -Protocol ICMPv4 `
    -IcmpType 8 `
    -Direction Inbound `
    -Action Allow `
    -Profile Any `
    -ErrorAction SilentlyContinue | Out-Null
Write-Output "  ICMP Echo (ping) allowed inbound"

# =============================================================
# 5. TLS/SSL HARDENING (CIS 18.x)
# =============================================================
Write-Output "[5/8] Hardening TLS/SSL protocols..."

# Disable SSL 2.0
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server" -Name "Enabled" -Value 0 -Type DWord
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Client" -Name "Enabled" -Value 0 -Type DWord

# Disable SSL 3.0
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server" -Name "Enabled" -Value 0 -Type DWord
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Client" -Name "Enabled" -Value 0 -Type DWord

# Disable TLS 1.0
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server" -Name "Enabled" -Value 0 -Type DWord
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Client" -Name "Enabled" -Value 0 -Type DWord

# Disable TLS 1.1
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server" -Name "Enabled" -Value 0 -Type DWord
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Client" -Name "Enabled" -Value 0 -Type DWord

# Ensure TLS 1.2 is enabled
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server" -Name "Enabled" -Value 1 -Type DWord
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client" -Name "Enabled" -Value 1 -Type DWord

# Ensure TLS 1.3 is enabled
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server" -Name "Enabled" -Value 1 -Type DWord
New-Item -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Client" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Client" -Name "Enabled" -Value 1 -Type DWord

# =============================================================
# 6. DISABLE SMBv1 (CIS 18.4.x)
# =============================================================
Write-Output "[6/8] Disabling SMBv1..."

# Disable SMBv1 protocol
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null

# Enable SMB signing
Set-SmbServerConfiguration -RequireSecuritySignature $true -Force -ErrorAction SilentlyContinue

# =============================================================
# 7. REGISTRY HARDENING (CIS 2.3.x, 18.x)
# =============================================================
Write-Output "[7/8] Applying registry hardening..."

# Disable anonymous SID enumeration (CIS 2.3.10.2)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymousSAM" -Value 1 -Type DWord
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymous" -Value 1 -Type DWord

# Disable storage of LAN Manager hash (CIS 2.3.11.7)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "NoLMHash" -Value 1 -Type DWord

# LAN Manager authentication level — Send NTLMv2 only, refuse LM & NTLM (CIS 2.3.11.8)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "LmCompatibilityLevel" -Value 5 -Type DWord

# Disable autoplay for all drives (CIS 18.9.8.3)
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoDriveTypeAutoRun" -Value 255 -Type DWord

# Disable Remote Desktop (will be enabled per-role by Ansible) (CIS 18.9.65.x)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 1 -Type DWord

# Enable NLA for Remote Desktop (CIS 18.9.65.3.9.2)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 1 -Type DWord

# Set screen saver timeout and lock (CIS 18.9.x)
New-Item -Path "HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop" -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value "900" -ErrorAction SilentlyContinue
Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Control Panel\Desktop" -Name "ScreenSaverIsSecure" -Value "1" -ErrorAction SilentlyContinue

# Disable Windows Script Host (CIS 18.9.x)
New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings" -Name "Enabled" -Value 0 -Type DWord

# =============================================================
# 8. LEGAL NOTICE BANNER (CIS 2.3.7.x)
# =============================================================
Write-Output "[8/8] Setting legal notice banner..."

$bannerText = "This is a private system. Unauthorized access is prohibited. All activity is monitored and logged."
$bannerTitle = "NOTICE"

Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LegalNoticeCaption" -Value $bannerTitle
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LegalNoticeText" -Value $bannerText

Write-Output "========================================="
Write-Output " CIS Hardening Complete"
Write-Output "========================================="
Write-Output ""
Write-Output " Applied controls:"
Write-Output "  - Password: min 14 chars, 90-day expiry, 24 history, lockout after 5"
Write-Output "  - Audit: logon, account mgmt, policy change, privilege use"
Write-Output "  - Services: disabled 17 unnecessary services"
Write-Output "  - Firewall: enabled all profiles, block inbound, logging on"
Write-Output "  - TLS: disabled SSL 2.0/3.0, TLS 1.0/1.1; enabled TLS 1.2/1.3"
Write-Output "  - SMB: disabled v1, enforced signing"
Write-Output "  - Registry: NTLMv2 only, no LM hash, no anonymous, NLA for RDP"
Write-Output "  - Banner: legal notice configured"
Write-Output ""
Write-Output " NOTE: Role-specific hardening will be applied by Ansible."
Write-Output "========================================="
