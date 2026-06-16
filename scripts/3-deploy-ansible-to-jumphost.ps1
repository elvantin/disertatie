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
#   .\scripts\deploy-ansible-to-jumphost.ps1 -SkipCopy           # sare peste SCP (fisierele exista deja)
#   .\scripts\deploy-ansible-to-jumphost.ps1 -SkipConfig         # sare peste permisiuni + inventory
#   .\scripts\deploy-ansible-to-jumphost.ps1 -SkipVault          # sare peste create-ansible-vault.sh
#   .\scripts\deploy-ansible-to-jumphost.ps1 -SkipCopy -SkipConfig  # doar Vault
# ============================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$JumphostIP = "4.223.228.18",

    [Parameter(Mandatory=$false)]
    [string]$User = "azureadmin",

    [Parameter(Mandatory=$false)]
    [string]$RemotePath = "/home/azureadmin/ansible",

    [Parameter(Mandatory=$false)]
    [string]$LocalPath = "ansible",

    [Parameter(Mandatory=$false)]
    [ValidateSet('dev', 'prod', '')]
    [string]$Environment = "",

    [Parameter(Mandatory=$false)]
    [switch]$SkipCopy,

    [Parameter(Mandatory=$false)]
    [switch]$SkipConfig,

    [Parameter(Mandatory=$false)]
    [switch]$SkipVault
)

. "$PSScriptRoot\lib\Write-Log.ps1"
$_LogDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs'
Start-LogSession -ScriptTitle "Deploy Ansible to Jumphost" -LogDirectory $_LogDir

trap {
    Write-Log-Fail "Eroare neasteptata: $_" -Detail "Script oprit prematur"
    Stop-LogSession
    break
}

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

Write-Log-Header "Configurare conexiune"
Write-Log-Info "Jumphost      : $SSHTarget"
Write-Log-Info "Local         : $LocalPath"
Write-Log-Info "Remote        : $RemotePath"
Write-Log-Info "Environment   : $Environment"
Write-Log-Info "Inventory src : $SourceInventory → $ActiveInventory"
Write-Log-Info "Skip flags    : Copy=$($SkipCopy.IsPresent)  Config=$($SkipConfig.IsPresent)  Vault=$($SkipVault.IsPresent)"

# SSH options — ignora known_hosts, autentificare parola
$SSHOpts = @(
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "PasswordAuthentication=yes",
    "-o", "PreferredAuthentications=keyboard-interactive,password,publickey",
    "-o", "LogLevel=ERROR"
)

if (-not (Test-Path $LocalPath)) {
    Write-Log-Fail "Directorul '$LocalPath' nu a fost găsit" -Detail "Rulează scriptul din rădăcina proiectului (IT/)"
    Stop-LogSession; exit 1
}

# =============================================================================
# STEP 1: Copiaza fisierele Ansible pe jumphost
# =============================================================================

Write-Log-Header "Copiere fișiere Ansible pe jumphost" -Step 1 -Total 3
if ($SkipCopy) {
    Write-Log-Warn "SKIP: Copiere fișiere (-SkipCopy)" -Detail "Se presupune că fișierele există deja pe jumphost"
} else {
    Write-Log-Step "scp $LocalPath → ${SSHTarget}:${RemotePath} ..."
    scp @SSHOpts -r "${LocalPath}\*" "${SSHTarget}:${RemotePath}/"

    if ($LASTEXITCODE -ne 0) {
        Write-Log-Warn "SCP a eșuat — încerc tar+ssh..."
        tar -cf - -C $LocalPath . | ssh @SSHOpts $SSHTarget "mkdir -p ${RemotePath} && tar -xf - -C ${RemotePath}"
        if ($LASTEXITCODE -ne 0) {
            Write-Log-Fail "Copierea fișierelor a eșuat" -Detail "SCP și tar au eșuat"
            Stop-LogSession; exit 1
        }
    }
    Write-Log-OK "Fișiere Ansible copiate" -Detail "${SSHTarget}:${RemotePath}"
}

# =============================================================================
# STEP 2: Permisiuni + activeaza inventory + verificare
# =============================================================================

# Compute deploy domain as a PowerShell variable so it expands correctly inside the @"..."@ here-string
$DeployDomain = if ($Environment -eq 'dev') { 'mediasrl-dev.swedencentral.cloudapp.azure.com' } else { 'mediasrl.swedencentral.cloudapp.azure.com' }

Write-Log-Header "Configurare permisiuni și inventory" -Step 2 -Total 3
if ($SkipConfig) {
    Write-Log-Warn "SKIP: Configurare permisiuni/inventory (-SkipConfig)"
} else {
Write-Log-Step "Permisiuni, activare inventory ($SourceInventory → $ActiveInventory), domain: $DeployDomain"

$sshStep2Lines = [System.Collections.Generic.List[string]]::new()
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
chmod +x ${RemotePath}/run-playbook.sh                  2>/dev/null || true
chmod +x ${RemotePath}/scripts/*.sh                     2>/dev/null || true
chmod +x ${RemotePath}/scripts/lib/*.sh                 2>/dev/null || true
echo '  OK'

echo ''
echo '--- Symlink group_vars (inventory/group_vars -> ../group_vars) ---'
rm -rf ${RemotePath}/inventory/group_vars 2>/dev/null || true
ln -sf ${RemotePath}/group_vars ${RemotePath}/inventory/group_vars
echo '  ${RemotePath}/inventory/group_vars -> ${RemotePath}/group_vars'

echo ''
echo '--- Configurare ANSIBLE_CONFIG ---'
sed -i '/ANSIBLE_CONFIG/d' ~/.bashrc 2>/dev/null || true
echo 'export ANSIBLE_CONFIG=${RemotePath}/ansible.cfg' >> ~/.bashrc
export ANSIBLE_CONFIG=${RemotePath}/ansible.cfg
echo '  export ANSIBLE_CONFIG=${RemotePath}/ansible.cfg'

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
echo '--- Scriere fisier environment (.deploy_env) ---'
printf 'DEPLOY_ENV=$Environment\nDEPLOY_DOMAIN=$DeployDomain\n' > ${RemotePath}/.deploy_env
chmod 644 ${RemotePath}/.deploy_env
echo '  Scris: ${RemotePath}/.deploy_env'
echo '  DEPLOY_ENV=$Environment  DEPLOY_DOMAIN=$DeployDomain'

echo ''
echo '--- Configurare website_domain in group_vars/linux.yml ---'
sed -i 's|^website_domain:.*|website_domain: "$DeployDomain"|' ${RemotePath}/group_vars/linux.yml
echo -n '  Verificare: '
grep '^website_domain:' ${RemotePath}/group_vars/linux.yml || echo '  WARN: linia website_domain nu a fost gasita in group_vars/linux.yml!'

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
"@ 2>&1 | ForEach-Object { Write-Host $_; [void]$sshStep2Lines.Add([string]$_) }
$sshStep2Exit = $LASTEXITCODE
Write-Log-Block -Label "Output SSH: configurare permisiuni, inventory, Ansible — $SSHTarget" -Content ($sshStep2Lines -join "`n")

if ($sshStep2Exit -ne 0) {
    Write-Log-Fail "Configurarea permisiunilor/inventory a eșuat" -Detail "SSH exit code $sshStep2Exit"
    Stop-LogSession; exit 1
}
Write-Log-OK "Permisiuni setate, inventory activat" -Detail "$SourceInventory → $ActiveInventory  |  domain=$DeployDomain"
} # end if -SkipConfig

# =============================================================================
# STEP 3: Ansible Vault — fetch secrets + create vault.yml via MSI
# =============================================================================

Write-Log-Header "Ansible Vault Setup (create-ansible-vault.sh)" -Step 3 -Total 3
if ($SkipVault) {
    Write-Log-Warn "SKIP: Ansible Vault (-SkipVault)" -Detail "Se presupune că vault.yml există deja pe jumphost"
} else {
    Write-Log-Step "Rulare create-ansible-vault.sh pe jumphost via SSH (Managed Identity)..."

    $vaultLines = [System.Collections.Generic.List[string]]::new()
    ssh @SSHOpts $SSHTarget "cd `"${RemotePath}`" && bash scripts/create-ansible-vault.sh" 2>&1 | ForEach-Object { Write-Host $_; [void]$vaultLines.Add([string]$_) }
    $vaultExit = $LASTEXITCODE
    Write-Log-Block -Label "Output SSH: create-ansible-vault.sh" -Content ($vaultLines -join "`n")

    if ($vaultExit -ne 0) {
        Write-Log-Fail "create-ansible-vault.sh a eșuat" -Detail "Verifică că MSI are acces la kv-mediasrl-persistent (role: Key Vault Secrets User)"
        Stop-LogSession; exit 1
    }
    Write-Log-OK "Ansible Vault configurat" -Detail "group_vars/all/vault.yml  (AES-256)  |  ~/.vault-pass  (mode 600)"
}

# =============================================================================
# REZULTAT FINAL
# =============================================================================

Write-Log-Header "Rezultat deployment"
Write-Log-OK "Fișiere Ansible configurate pe jumphost" -Detail "${RemotePath}"
Write-Log-OK "Vault criptat, secrete preluate din Key Vault"
Write-Log-Info "ssh ${User}@${JumphostIP}"
Write-Log-Info "cd ${RemotePath}"
Write-Log-Info "ansible linux   -m ping"
Write-Log-Info "ansible windows -m win_ping"
Write-Log-Info "(fără az login — autentificare prin Managed Identity)"

Stop-LogSession
