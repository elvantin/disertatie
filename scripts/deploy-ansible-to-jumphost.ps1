# ============================================================
# Deploy Ansible Configuration to Jumphost
# Copies ansible/ directory to jumphost via SCP
# Uses only 2 SSH connections (SCP + SSH) to minimize password prompts
# ============================================================

param(
    [Parameter(Mandatory=$false)]
    #[string]$JumphostIP = "4.223.123.150",
    [string]$JumphostIP = "51.12.82.4",

    [Parameter(Mandatory=$false)]
    [string]$User = "azureadmin",

    [Parameter(Mandatory=$false)]
    [string]$RemotePath = "/home/azureadmin/ansible",

    [Parameter(Mandatory=$false)]
    [string]$LocalPath = "ansible"
)

$SSHTarget = "${User}@${JumphostIP}"
$SSHOpts = "-o", "StrictHostKeyChecking=no"

Write-Host "========================================="
Write-Host "SC MEDIA SRL - Deploy Ansible to Jumphost"
Write-Host "========================================="
Write-Host ""
Write-Host "Jumphost: $SSHTarget"
Write-Host "Local Path: $LocalPath"
Write-Host "Remote Path: $RemotePath"
Write-Host ""

# Check if ansible directory exists
if (-not (Test-Path $LocalPath)) {
    Write-Host "ERROR: Directory '$LocalPath' not found!" -ForegroundColor Red
    Write-Host "Run this script from the project root directory (IT/)" -ForegroundColor Yellow
    exit 1
}

# Step 1: Copy ansible files via SCP (password prompt 1/2)
Write-Host "[1/2] Copying ansible files to jumphost..."
scp @SSHOpts -r "${LocalPath}\*" "${SSHTarget}:${RemotePath}/"

if ($LASTEXITCODE -ne 0) {
    Write-Host "SCP failed, trying tar+ssh method..." -ForegroundColor Yellow
    tar -cf - -C $LocalPath . | ssh @SSHOpts $SSHTarget "mkdir -p ${RemotePath} && tar -xf - -C ${RemotePath}"
}

# Step 2: Set permissions + verify (password prompt 2/2)
Write-Host "[2/2] Setting permissions and verifying deployment..."
ssh @SSHOpts $SSHTarget @"
# Fix world-writable directory (Ansible refuses ansible.cfg otherwise)
chmod 755 ${RemotePath}
chmod 755 ${RemotePath}/inventory
chmod 755 ${RemotePath}/group_vars
chmod 644 ${RemotePath}/ansible.cfg
chmod 644 ${RemotePath}/inventory/hosts.ini 2>/dev/null
chmod 755 ${RemotePath}/playbooks
chmod 755 ${RemotePath}/roles
find ${RemotePath} -name '*.yml' -exec chmod 644 {} \;

echo ''
echo '========================================='
echo 'Ansible files deployed successfully!'
echo '========================================='
echo ''
echo 'Directory structure:'
find ${RemotePath} -maxdepth 3 -type f | head -30
echo ''
echo 'Testing ansible...'
cd ${RemotePath} && ansible --version 2>&1 | head -3
echo ''
echo 'Listing inventory hosts...'
cd ${RemotePath} && ansible all --list-hosts 2>/dev/null || echo 'Inventory listing requires azure_rm plugin'
echo ''
echo '========================================='
echo 'Next steps (run on jumphost):'
echo '  cd ${RemotePath}'
echo '  ansible windows -m win_ping'
echo '  ansible linux -m ping'
echo '========================================='
"@

Write-Host ""
Write-Host "========================================="
Write-Host "Deployment complete!"
Write-Host "========================================="
Write-Host ""
Write-Host "Connect to jumphost:"
Write-Host "  ssh ${User}@${JumphostIP}"
Write-Host ""
Write-Host "Then test Ansible:"
Write-Host "  cd ${RemotePath}"
Write-Host "  ansible windows -m win_ping"
Write-Host "  ansible linux -m ping"
Write-Host "========================================="
