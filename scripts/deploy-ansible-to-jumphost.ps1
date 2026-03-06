# ============================================================
# Deploy Ansible Configuration to Jumphost
# Copiaza ansible/ pe jumphost si activeaza inventarul corect.
#
# Nota: Ansible Galaxy collections (inclusiv azure.azcollection >=3.15.0)
# si dependentele Python sunt pre-installed in imaginea Packer a jumphost-ului.
# Autentificarea foloseste Managed Identity (auth_source: msi) — fara az login.
#
# Strategia inventory:
#   ansible.cfg pointeaza intotdeauna la ./inventory/azure_rm.yml
#   Scriptul copiaza fisierul sursa corect ca azure_rm.yml:
#     dev  -> azure_rm_dev.yml -> azure_rm.yml  (RG: dezvoltare)
#     prod -> azure_rm.yml     -> azure_rm.yml  (RG: productie, nicio copiere)
#
# Usage:
#   .\scripts\deploy-ansible-to-jumphost.ps1              # prompt interactiv
#   .\scripts\deploy-ansible-to-jumphost.ps1 -Environment dev
#   .\scripts\deploy-ansible-to-jumphost.ps1 -Environment prod
# ============================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$JumphostIP = "51.12.82.4",

    [Parameter(Mandatory=$false)]
    [string]$User = "azureadmin",

    [Parameter(Mandatory=$false)]
    [string]$RemotePath = "/home/azureadmin/ansible",

    [Parameter(Mandatory=$false)]
    [string]$LocalPath = "ansible",

    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'prod', '')]
    [string]$Environment = ""
)

Write-Host "========================================="
Write-Host "SC MEDIA SRL - Deploy Ansible to Jumphost"
Write-Host "========================================="
Write-Host ""

# --- Prompt pentru environment daca nu e specificat ---
if (-not $Environment) {
    do {
        $raw = Read-Host "Environment [dev/prod]"
        $raw = $raw.Trim().ToLower()
    } while ($raw -ne 'dev' -and $raw -ne 'prod')
    $Environment = $raw
}

# --- Sursa inventory in repo si numele activ pe jumphost ---
# ansible.cfg pointeaza intotdeauna la azure_rm.yml; scriptul
# copiaza fisierul sursa corect ca azure_rm.yml pe jumphost.
$SourceInventory = if ($Environment -eq 'prod') { 'azure_rm.yml' } else { "azure_rm_${Environment}.yml" }
$ActiveInventory  = 'azure_rm.yml'

$SSHTarget = "${User}@${JumphostIP}"

Write-Host "Jumphost:        $SSHTarget"
Write-Host "Local:           $LocalPath"
Write-Host "Remote:          $RemotePath"
Write-Host "Env:             $Environment"
Write-Host "Sursa inventory: $SourceInventory"
Write-Host "Activ ca:        $ActiveInventory  (azure_rm.yml)"
Write-Host ""

# SSH options — ignora known_hosts, autentificare parola
$SSHOpts = @(
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "PasswordAuthentication=yes",
    "-o", "PreferredAuthentications=keyboard-interactive,password,publickey",
    "-o", "LogLevel=ERROR"
)

# --- Verifica ca directorul local exista ---
if (-not (Test-Path $LocalPath)) {
    Write-Host "ERROR: Directory '$LocalPath' not found!" -ForegroundColor Red
    Write-Host "Ruleaza scriptul din radacina proiectului (IT/)" -ForegroundColor Yellow
    exit 1
}

# =============================================================================
# STEP 1: Copiaza fisierele Ansible pe jumphost
# =============================================================================

Write-Host "[1/2] Copiind fisierele Ansible pe jumphost..."
scp @SSHOpts -r "${LocalPath}\*" "${SSHTarget}:${RemotePath}/"

if ($LASTEXITCODE -ne 0) {
    Write-Host "  SCP a esuat, incerc tar+ssh..." -ForegroundColor Yellow
    tar -cf - -C $LocalPath . | ssh @SSHOpts $SSHTarget "mkdir -p ${RemotePath} && tar -xf - -C ${RemotePath}"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Copierea fisierelor a esuat!" -ForegroundColor Red
        exit 1
    }
}

# =============================================================================
# STEP 2: Permisiuni + activeaza inventory + verificare
# =============================================================================

Write-Host "[2/2] Permisiuni, activare inventory ($SourceInventory -> $ActiveInventory), verificare..."

ssh @SSHOpts $SSHTarget @"
echo '========================================='
echo 'STEP 3: Configurare finala'
echo '========================================='

echo ''
echo '--- Permisiuni ---'
chmod 755 ${RemotePath}
chmod 755 ${RemotePath}/inventory   2>/dev/null || true
chmod 755 ${RemotePath}/group_vars  2>/dev/null || true
chmod 755 ${RemotePath}/playbooks   2>/dev/null || true
chmod 755 ${RemotePath}/roles       2>/dev/null || true
chmod 644 ${RemotePath}/ansible.cfg
chmod 644 ${RemotePath}/inventory/*.yml 2>/dev/null || true
chmod 644 ${RemotePath}/inventory/*.ini 2>/dev/null || true
find ${RemotePath} -name '*.yml' -exec chmod 644 {} + 2>/dev/null || true
echo '  OK'

echo ''
echo '--- Activare inventory pentru mediul: $Environment ---'
# Copiaza sursa corecta ca azure_rm.yml (fisierul pe care il stie ansible.cfg)
if [ "$SourceInventory" != "$ActiveInventory" ]; then
    cp ${RemotePath}/inventory/$SourceInventory ${RemotePath}/inventory/$ActiveInventory
    echo '  Copiat: $SourceInventory -> $ActiveInventory'
else
    echo '  Nicio copiere necesara ($SourceInventory este deja $ActiveInventory)'
fi

echo ''
echo '--- Inventory activ in ansible.cfg ---'
grep '^inventory' ${RemotePath}/ansible.cfg

echo ''
echo '--- Versiune Ansible ---'
ansible --version 2>&1 | head -3

echo ''
echo '--- Lista hosturi ---'
cd ${RemotePath} && ansible all --list-hosts 2>&1 | head -20

echo ''
echo '========================================='
echo 'Deployment complet!'
echo ''
echo 'Jumphost-ul foloseste Managed Identity (auth_source: msi).'
echo 'Nu este necesara autentificarea manuala (az login).'
echo ''
echo "  cd ${RemotePath}"
echo '  ansible linux   -m ping'
echo '  ansible windows -m win_ping'
echo '========================================='
"@

Write-Host ""
Write-Host "=========================================" -ForegroundColor Green
Write-Host "Deployment complet!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Conecteaza-te la jumphost si ruleaza:" -ForegroundColor Cyan
Write-Host "  ssh ${User}@${JumphostIP}"
Write-Host "  cd ${RemotePath}"
Write-Host "  ansible linux   -m ping"
Write-Host "  ansible windows -m win_ping"
Write-Host "  (Fara az login — autentificare prin Managed Identity)"
Write-Host "========================================="
