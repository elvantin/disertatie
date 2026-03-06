# ============================================================
# Get VM IP Addresses Script
# Retrieves private and public IPs for all VMs in resource group
# ============================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup = "rg-mediasrl-productie-swedencentral"
)

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "SC MEDIA SRL - VM IP Address Retrieval" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Resource Group: $ResourceGroup" -ForegroundColor Yellow
Write-Host ""

# Check if Azure CLI is available
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: Azure CLI is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Install with: winget install Microsoft.AzureCLI" -ForegroundColor Yellow
    exit 1
}

# Check if logged in to Azure
$account = az account show 2>$null
if (-not $account) {
    Write-Host "ERROR: Not logged in to Azure" -ForegroundColor Red
    Write-Host "Run: az login" -ForegroundColor Yellow
    exit 1
}

Write-Host "Retrieving VM information..." -ForegroundColor Cyan
Write-Host ""

# Get all VMs in the resource group
$vms = az vm list --resource-group $ResourceGroup --query "[].{Name:name, OsType:storageProfile.osDisk.osType}" -o json | ConvertFrom-Json

if ($vms.Count -eq 0) {
    Write-Host "ERROR: No VMs found in resource group '$ResourceGroup'" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($vms.Count) VMs:" -ForegroundColor Green
Write-Host ""

# Create a collection to store VM details
$vmDetails = @()

foreach ($vm in $vms) {
    $vmName = $vm.Name
    $osType = $vm.OsType

    Write-Host "Processing: $vmName ($osType)..." -ForegroundColor White

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

# Display results in table format
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "VM IP Addresses Summary" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$vmDetails | Format-Table -AutoSize

# Export to CSV
$csvPath = "vm-ip-addresses.csv"
$vmDetails | Export-Csv -Path $csvPath -NoTypeInformation -Force
Write-Host ""
Write-Host "Exported to: $csvPath" -ForegroundColor Green

# Generate Ansible inventory snippet
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Ansible Inventory Configuration" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

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
ansible_password=Str0ng_P@ssw0rd_2026!

[linux:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

# ============================================================
# Notes:
# - Update ansible_password in group_vars/all/vault.yml (encrypted)
# - Configure SSH keys with: ansible-playbook playbooks/1-setup-ssh-keys.yml
# - Test connectivity: ansible all -m ping
# ============================================================
"@

Write-Host $inventoryContent

# Save inventory to file
$inventoryPath = "ansible-inventory-hosts.ini"
$inventoryContent | Out-File -FilePath $inventoryPath -Encoding UTF8 -Force
Write-Host ""
Write-Host "Ansible inventory saved to: $inventoryPath" -ForegroundColor Green

# Connection instructions
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Quick Connection Guide" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

if ($jumphost) {
    Write-Host "Connect to Jumphost via RDP:" -ForegroundColor Yellow
    if ($jumphost.PublicIP -ne "N/A") {
        Write-Host "  mstsc /v:$($jumphost.PublicIP):3389" -ForegroundColor White
    } else {
        Write-Host "  (No public IP configured for jumphost)" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "From Jumphost, SSH to Linux VMs:" -ForegroundColor Yellow
foreach ($vm in $linuxVms) {
    Write-Host "  ssh azureadmin@$($vm.Name)  # $($vm.PrivateIP)" -ForegroundColor White
}
Write-Host ""

Write-Host "From Jumphost, RDP to Windows VMs (via Remmina):" -ForegroundColor Yellow
foreach ($vm in $windowsVms) {
    Write-Host "  Use Remmina GUI → Connect to $($vm.Name)  # $($vm.PrivateIP)" -ForegroundColor White
}
Write-Host ""

Write-Host "Test Ansible Connectivity:" -ForegroundColor Yellow
Write-Host "  ansible all -m ping -i ansible-inventory-hosts.ini" -ForegroundColor White
Write-Host ""

Write-Host "=========================================" -ForegroundColor Green
Write-Host "Script completed successfully!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
