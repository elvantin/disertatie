# ============================================================
# Deploy Ansible Configuration to Jumphost
# Copiaza ansible/ pe jumphost, instaleaza azure.azcollection
# + Python deps, activeaza inventarul corect ca azure_rm.yml.
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

Write-Host "[1/3] Copiind fisierele Ansible pe jumphost..."
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
# STEP 2: Instaleaza azure.azcollection + dependente Python pe jumphost
# =============================================================================
# IMPORTANT despre escaping in PowerShell heredoc @"..."@:
#   - PowerShell expandeaza $variable si $(expression) in @"..."@
#   - Pentru a trimite un $ literal catre bash, folosim `$ (backtick)
#   - \$ NU functioneaza in PowerShell (\ nu este caracter de escape in PS)
# =============================================================================

Write-Host "[2/3] Instaland/actualizand Ansible Galaxy collections pe jumphost..."
Write-Host "  (requirements.yml: ansible.windows, ansible.posix, community.general, community.windows, azure.azcollection)"
Write-Host "  (Poate dura 2-5 minute la prima rulare)"
Write-Host ""

ssh @SSHOpts $SSHTarget @"
echo '========================================='
echo 'STEP 2: Ansible Galaxy collections setup'
echo '========================================='

echo ''
echo '--- [2a] Instalare colectii din requirements.yml ---'
# Colectiile sunt deja pre-baked in imaginea Packer.
# Aceasta comanda asigura versiunile corecte si aplica pinning-ul din requirements.yml
# (important: community.general trebuie sa fie <12.0.0 pentru a evita tombstone ERROR)
cd ${RemotePath} && ansible-galaxy collection install -r requirements.yml --force
echo ''

echo '--- [2b] Python dependencies pentru azure.azcollection ---'
# Verificam ambele locatii posibile (./collections si ~/.ansible/collections)
COLL1=${RemotePath}/collections/ansible_collections/azure/azcollection
COLL2=~/.ansible/collections/ansible_collections/azure/azcollection

if [ -f "`$COLL1/requirements.txt" ]; then
    REQS_PATH=`$COLL1/requirements.txt
    echo "  Gasit in collections_path: `$REQS_PATH"
elif [ -f "`$COLL2/requirements.txt" ]; then
    REQS_PATH=`$COLL2/requirements.txt
    echo "  Gasit in ~/.ansible: `$REQS_PATH"
else
    REQS_PATH=""
    echo '  WARN: requirements.txt negasit'
fi

if [ -n "`$REQS_PATH" ]; then
    pip3 install -r "`$REQS_PATH" --quiet 2>&1 | tail -5
    echo '  OK: Python deps instalate'
fi
echo ''

echo '--- [2c] Verificare azure-cli-core (pentru auth_source: cli) ---'
pip3 install azure-cli-core --upgrade --quiet 2>&1 | tail -3
python3 -c "
from azure.cli.core._profile import Profile
print('  OK: azure.cli.core._profile.Profile disponibil')
" 2>&1 || echo '  WARN: azure.cli.core._profile nu se poate importa'
echo ''
"@

if ($LASTEXITCODE -ne 0) {
    Write-Host "WARN: Step 2 a raportat erori (vezi output)" -ForegroundColor Yellow
    Write-Host "      Continui cu configurarea..." -ForegroundColor Yellow
    Write-Host ""
}

# =============================================================================
# STEP 3: Permisiuni + activeaza inventory + patch ansible.cfg + verificare
# =============================================================================

Write-Host "[3/3] Permisiuni, activare inventory ($SourceInventory -> $ActiveInventory), verificare..."

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
echo '--- Lista hosturi (necesita az login) ---'
cd ${RemotePath} && ansible all --list-hosts 2>&1 | head -20

echo ''
echo '========================================='
echo 'Deployment complet!'
echo ''
echo 'PASUL URMATOR (pe jumphost):'
echo '  az login'
echo '  (sau: az login --use-device-code  daca nu ai browser deschis)'
echo ''
echo 'Dupa az login:'
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
Write-Host "  az login"
Write-Host "  cd ${RemotePath}"
Write-Host "  ansible linux   -m ping"
Write-Host "  ansible windows -m win_ping"
Write-Host "========================================="
