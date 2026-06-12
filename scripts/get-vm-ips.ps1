# ============================================================
# Get VM IP Addresses Script
# Retrieves private and public IPs for all VMs in resource group
# ============================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "rg-mediasrl-productie-swedencentral"
)

. "$PSScriptRoot\lib\Write-Log.ps1"
$_LogDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs'
Start-LogSession -ScriptTitle "VM IP Address Retrieval" -LogDirectory $_LogDir

trap {
    Write-Log-Fail "Eroare neasteptata: $_" -Detail "Script oprit prematur"
    Stop-LogSession
    break
}

Write-Log-Header "Verificări preliminare"
Write-Log-Info "Resource Group: $ResourceGroup"

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Log-Fail "Azure CLI nu este instalat sau nu este în PATH" -Detail "winget install Microsoft.AzureCLI"
    Stop-LogSession; exit 1
}

$account = az account show 2>$null
if (-not $account) {
    Write-Log-Fail "Nu ești autentificat în Azure" -Detail "Rulează: az login"
    Stop-LogSession; exit 1
}
Write-Log-OK "Azure CLI autentificat"

Write-Log-Header "Colectare IP-uri VM-uri"

# Get all VMs in the resource group
$vms = az vm list --resource-group $ResourceGroup --query "[].{Name:name, OsType:storageProfile.osDisk.osType}" -o json | ConvertFrom-Json

if ($vms.Count -eq 0) {
    Write-Log-Fail "Nu s-au găsit VM-uri în '$ResourceGroup'"
    Stop-LogSession; exit 1
}
Write-Log-OK "$($vms.Count) VM-uri găsite în $ResourceGroup"

# Create a collection to store VM details
$vmDetails = @()

foreach ($vm in $vms) {
    $vmName = $vm.Name
    $osType = $vm.OsType

    Write-Log-Step "Colectare IP-uri: $vmName ($osType)..."

    # Get IP addresses for this VM
    $ipInfo = az vm list-ip-addresses --resource-group $ResourceGroup --name $vmName -o json | ConvertFrom-Json

    $privateIp = $null
    $publicIp = $null

    if ($ipInfo -and $ipInfo.Count -gt 0) {
        $networkInterface = $ipInfo[0].virtualMachine.network.privateIpAddresses
        if ($networkInterface -and $networkInterface.Count -gt 0) {
            $privateIp = $networkInterface[0]
        }

        $publicIpAddresses = $ipInfo[0].virtualMachine.network.publicIpAddresses
        if ($publicIpAddresses -and $publicIpAddresses.Count -gt 0) {
            $publicIp = $publicIpAddresses[0].ipAddress
        }
    }

    $vmDetails += [PSCustomObject]@{
        Name = $vmName
        OsType = $osType
        PrivateIP = if ($privateIp) { $privateIp } else { "N/A" }
        PublicIP = if ($publicIp) { $publicIp } else { "N/A" }
    }
}

Write-Log-Header "Rezumat IP-uri VM-uri"

foreach ($vm in $vmDetails) {
    Write-Log-OK "$($vm.Name) [$($vm.OsType)]" -Detail "Private: $($vm.PrivateIP)  |  Public: $($vm.PublicIP)"
}

$tblStr = ($vmDetails | Format-Table -AutoSize | Out-String).Trim()
Write-Log-Block -Label "Tabel IP-uri VM-uri — $ResourceGroup" -Content $tblStr

$csvPath = Join-Path (Split-Path $PSScriptRoot -Parent) "logs\vm-ip-addresses.csv"
$vmDetails | Export-Csv -Path $csvPath -NoTypeInformation -Force
Write-Log-OK "Export CSV" -Detail $csvPath

Write-Log-Header "Configurare Ansible Inventory"

$linuxVms = $vmDetails | Where-Object { $_.OsType -eq "Linux" -and $_.Name -ne "vm-jmp-01" }
$windowsVms = $vmDetails | Where-Object { $_.OsType -eq "Windows" }
$jumphost = $vmDetails | Where-Object { $_.Name -eq "vm-jmp-01" }

# Generate inventory content
$inventoryContent = @"
# ============================================================
# Ansible Inventory - SC MEDIA SRL
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# ============================================================

[jumphost]
$($jumphost.Name) ansible_host=$($jumphost.PrivateIP) ansible_user=azureadmin

"@

if ($linuxVms.Count -gt 0) {
    foreach ($vm in $linuxVms) {
        $section = switch -Regex ($vm.Name) {
            "web" { "webserver" }
            "app" { "appserver" }
            "cms" { "cmsserver" }
            default { "linux" }
        }

        $inventoryContent += @"
[$section]
$($vm.Name) ansible_host=$($vm.PrivateIP) ansible_user=azureadmin

"@
    }
}

if ($windowsVms.Count -gt 0) {
    foreach ($vm in $windowsVms) {
        $section = switch -Regex ($vm.Name) {
            "db" { "database" }
            "fs" { "fileserver" }
            default { "windows" }
        }

        $inventoryContent += @"
[$section]
$($vm.Name) ansible_host=$($vm.PrivateIP) ansible_user=azureadmin ansible_connection=winrm ansible_winrm_transport=ntlm ansible_winrm_server_cert_validation=ignore ansible_port=5985

"@
    }
}

# Add group definitions
$inventoryContent += @"

# ============================================================
# Group Definitions
# ============================================================

[linux:children]
"@

if ($linuxVms.Count -gt 0) {
    foreach ($vm in $linuxVms) {
        $section = switch -Regex ($vm.Name) {
            "web" { "webserver" }
            "app" { "appserver" }
            "cms" { "cmsserver" }
            default { $null }
        }
        if ($section) {
            $inventoryContent += "`n$section"
        }
    }
}

$inventoryContent += @"


[windows:children]
"@

if ($windowsVms.Count -gt 0) {
    foreach ($vm in $windowsVms) {
        $section = switch -Regex ($vm.Name) {
            "db" { "database" }
            "fs" { "fileserver" }
            default { $null }
        }
        if ($section) {
            $inventoryContent += "`n$section"
        }
    }
}

$inventoryContent += @"


[all:vars]
ansible_python_interpreter=/usr/bin/python3

[windows:vars]
# ansible_password set via Ansible Vault (group_vars/windows.yml -> vault_admin_password)
# Run: bash scripts/create-ansible-vault.sh

[linux:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

# ============================================================
# Notes:
# - Passwords are in Ansible Vault: bash scripts/create-ansible-vault.sh
# - Configure SSH keys with: ansible-playbook playbooks/1-setup-ssh-keys.yml
# - Test connectivity: ansible all -m ping
# ============================================================
"@

Write-Log-Block -Label "Inventar Ansible generat (hosts.ini)" -Content $inventoryContent

# Save inventory to file
$inventoryPath = "ansible-inventory-hosts.ini"
$inventoryContent | Out-File -FilePath $inventoryPath -Encoding UTF8 -Force
Write-Log-OK "Inventar Ansible salvat" -Detail $inventoryPath

Write-Log-Header "Ghid conexiune rapidă"

if ($jumphost) {
    if ($jumphost.PublicIP -ne "N/A") {
        Write-Log-OK "Jumphost RDP" -Detail "mstsc /v:$($jumphost.PublicIP):3389"
    } else {
        Write-Log-Warn "Jumphost nu are IP public configurat"
    }
}
foreach ($vm in $linuxVms) {
    Write-Log-Info "SSH Linux  →  ssh azureadmin@$($vm.Name)  # $($vm.PrivateIP)"
}
foreach ($vm in $windowsVms) {
    Write-Log-Info "RDP Win    →  Remmina → $($vm.Name)  # $($vm.PrivateIP)"
}
Write-Log-Info "Ansible test  →  ansible all -m ping"

Stop-LogSession
