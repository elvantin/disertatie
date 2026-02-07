# ============================================================
# Deploy Ansible Configuration to Jumphost
# Copies ansible/ directory to jumphost via SCP
# ============================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$JumphostIP = "4.223.123.150",

    [Parameter(Mandatory=$false)]
    [string]$User = "azureadmin",

    [Parameter(Mandatory=$false)]
    [string]$RemotePath = "/home/azureadmin/ansible",

    [Parameter(Mandatory=$false)]
    [string]$LocalPath = "ansible"
)

Write-Host "========================================="
Write-Host "SC MEDIA SRL - Deploy Ansible to Jumphost"
Write-Host "========================================="
Write-Host ""
Write-Host "Jumphost: ${User}@${JumphostIP}"
Write-Host "Local Path: $LocalPath"
Write-Host "Remote Path: $RemotePath"
Write-Host ""

# Check if ansible directory exists
if (-not (Test-Path $LocalPath)) {
    Write-Host "ERROR: Directory '$LocalPath' not found!" -ForegroundColor Red
    Write-Host "Run this script from the project root directory (IT/)" -ForegroundColor Yellow
    exit 1
}

# Step 1: Create remote directory
Write-Host "[1/4] Creating remote directory..."
ssh -o StrictHostKeyChecking=no "${User}@${JumphostIP}" "mkdir -p ${RemotePath}"

# Step 2: Copy ansible files via SCP
Write-Host "[2/4] Copying ansible files to jumphost..."
scp -o StrictHostKeyChecking=no -r "${LocalPath}\*" "${User}@${JumphostIP}:${RemotePath}/"

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: SCP failed! Trying rsync alternative..." -ForegroundColor Yellow
    # Alternative: use tar + ssh
    Write-Host "Using tar + ssh method..."
    tar -cf - -C $LocalPath . | ssh -o StrictHostKeyChecking=no "${User}@${JumphostIP}" "mkdir -p ${RemotePath} && tar -xf - -C ${RemotePath}"
}

# Step 3: Set correct permissions
Write-Host "[3/4] Setting permissions..."
ssh -o StrictHostKeyChecking=no "${User}@${JumphostIP}" @"
chmod 644 ${RemotePath}/ansible.cfg
chmod 644 ${RemotePath}/inventory/hosts.ini
chmod 755 ${RemotePath}/playbooks
chmod 755 ${RemotePath}/roles
find ${RemotePath} -name '*.yml' -exec chmod 644 {} \;
"@

# Step 4: Verify deployment
Write-Host "[4/4] Verifying deployment..."
ssh -o StrictHostKeyChecking=no "${User}@${JumphostIP}" @"
echo ''
echo '========================================='
echo 'Ansible files deployed successfully!'
echo '========================================='
echo ''
echo 'Directory structure:'
find ${RemotePath} -maxdepth 3 -type f | head -30
echo ''
echo 'Testing ansible...'
cd ${RemotePath} && ansible --version
echo ''
echo 'Listing inventory hosts...'
cd ${RemotePath} && ansible all --list-hosts 2>/dev/null || echo 'Inventory listing requires ansible.cfg in current directory'
echo ''
echo '========================================='
echo 'Next steps (run on jumphost):'
echo '  cd ${RemotePath}'
echo '  ansible all --list-hosts'
echo '  ansible windows -m win_ping'
echo '  ansible linux -m ping --ask-pass'
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
Write-Host "  ansible linux -m ping --ask-pass"
Write-Host "========================================="
