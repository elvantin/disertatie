# ============================================================
# Base Setup — Windows Server 2022 Golden Image
# Installs Windows features, common tools, and prepares
# the OS for role-specific Ansible configuration.
# ============================================================

$ErrorActionPreference = "Stop"

Write-Output "========================================="
Write-Output " Windows Server 2022 — Base Setup"
Write-Output "========================================="

# ----- Extend C: partition to use full disk -----
Write-Output "[0/6] Extending C: partition to use all available disk space..."

$maxSize = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
$currentSize = (Get-Partition -DriveLetter C).Size
if ($maxSize -gt ($currentSize + 1GB)) {
    Resize-Partition -DriveLetter C -Size $maxSize
    $newSizeGB = [math]::Round($maxSize / 1GB, 1)
    Write-Output "  Partition C: extended to $newSizeGB GB"
} else {
    $currentGB = [math]::Round($currentSize / 1GB, 1)
    Write-Output "  Partition C: already at maximum size ($currentGB GB)"
}

# ----- Install Windows Features -----
Write-Output "[1/6] Installing Windows features..."

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
Write-Output "[2/6] Configuring PowerShell..."

# Enable PowerShell script execution for Ansible
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Force

# Enable PowerShell remoting for Ansible WinRM
Enable-PSRemoting -Force -SkipNetworkProfileCheck

# ----- Configure WinRM for Ansible -----
Write-Output "[3/6] Configuring WinRM for Ansible management..."

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
Write-Output "[4/6] Configuring time synchronization..."

# Configure Windows Time service
w32tm /config /manualpeerlist:"time.windows.com" /syncfromflags:manual /reliable:YES /update | Out-Null
Restart-Service w32time -ErrorAction SilentlyContinue
w32tm /resync /force | Out-Null

# ----- Install Visual C++ Redistributable (required by MySQL Server) -----
Write-Output "[5/6] Installing Visual C++ 2015-2022 Redistributable x64..."

$vcRedistUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$vcRedistPath = "$env:TEMP\vc_redist.x64.exe"
Invoke-WebRequest -Uri $vcRedistUrl -OutFile $vcRedistPath -UseBasicParsing
Start-Process -FilePath $vcRedistPath -ArgumentList "/install", "/quiet", "/norestart" -Wait -NoNewWindow
Remove-Item $vcRedistPath -Force -ErrorAction SilentlyContinue
Write-Output "  Visual C++ Redistributable installed"

# ----- Install Windows Updates (Round 1) -----
Write-Output "[6/6] Installing Windows Updates (Round 1 — via COM)..."
Write-Output "  This can take 30-90 min on a fresh marketplace image."

$ErrorActionPreference = "Continue"

try {
    $UpdateSession  = New-Object -ComObject Microsoft.Update.Session
    $UpdateSearcher = $UpdateSession.CreateUpdateSearcher()

    Write-Output "  Searching for available updates..."
    $SearchResult = $UpdateSearcher.Search("IsInstalled=0 AND IsHidden=0 AND Type='Software'")
    Write-Output "  Updates found: $($SearchResult.Updates.Count)"

    if ($SearchResult.Updates.Count -gt 0) {
        $Updates = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($Update in $SearchResult.Updates) {
            Write-Output "    - $($Update.Title)"
            $Updates.Add($Update) | Out-Null
        }

        Write-Output "  Downloading updates..."
        $Downloader = $UpdateSession.CreateUpdateDownloader()
        $Downloader.Updates = $Updates
        $Downloader.Download() | Out-Null

        Write-Output "  Installing updates..."
        $Installer = $UpdateSession.CreateUpdateInstaller()
        $Installer.Updates = $Updates
        $InstallResult = $Installer.Install()

        Write-Output "  Install result code : $($InstallResult.ResultCode)"
        Write-Output "  Reboot required     : $($InstallResult.RebootRequired)"
        # Packer's windows-restart provisioner handles the actual reboot.
    } else {
        Write-Output "  No updates available on this image."
    }
} catch {
    # Fallback: PSWindowsUpdate (requires internet access to PSGallery)
    Write-Output "  COM approach failed: $_"
    Write-Output "  Falling back to PSWindowsUpdate module..."
    try {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        Install-Module -Name PSWindowsUpdate -Force -Confirm:$false | Out-Null
        Import-Module PSWindowsUpdate
        Get-WindowsUpdate -AcceptAll -Install -IgnoreReboot -ErrorAction SilentlyContinue | Out-Null
        Write-Output "  PSWindowsUpdate completed."
    } catch {
        Write-Output "  WARNING: Both update methods failed: $_"
        Write-Output "  The Packer build will continue. Re-run or investigate manually."
    }
}

$ErrorActionPreference = "Stop"

Write-Output "========================================="
Write-Output " Base Setup Complete"
Write-Output " (Packer will reboot next to clear pending ops)"
Write-Output "========================================="
