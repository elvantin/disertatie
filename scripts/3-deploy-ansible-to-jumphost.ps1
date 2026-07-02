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
#   .\scripts\3-deploy-ansible-to-jumphost.ps1              # prompt interactiv
#   .\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment dev
#   .\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment prod
#   .\scripts\3-deploy-ansible-to-jumphost.ps1 -SkipCopy           # sare peste SCP (fisierele exista deja)
#   .\scripts\3-deploy-ansible-to-jumphost.ps1 -SkipConfig         # sare peste permisiuni + inventory
#   .\scripts\3-deploy-ansible-to-jumphost.ps1 -SkipVault          # sare peste scrierea ~/.vault-pass
#   .\scripts\3-deploy-ansible-to-jumphost.ps1 -SkipCopy -SkipConfig  # doar Vault
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
    [switch]$SkipVault,

    [Parameter(Mandatory=$false)]
    [string]$KeyFile = ""
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

$SSHOpts = @(
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=/dev/null",
    "-o", "PasswordAuthentication=yes",
    "-o", "PreferredAuthentications=publickey,keyboard-interactive,password",
    "-o", "LogLevel=ERROR"
)
if ($KeyFile) {
    $SSHOpts += @("-i", $KeyFile)
    Write-Log-Info "Cheie SSH     : $KeyFile"
}

if (-not (Test-Path $LocalPath)) {
    Write-Log-Fail "Directorul '$LocalPath' nu a fost găsit" -Detail "Rulează scriptul din rădăcina proiectului (IT/)"
    Stop-LogSession; exit 1
}

# =============================================================================
# STEP 1: Copiaza fisierele Ansible pe jumphost
# =============================================================================

Write-Log-Header "Copiere fișiere Ansible pe jumphost" -Step 1 -Total 2
if ($SkipCopy) {
    Write-Log-Warn "SKIP: Copiere fișiere (-SkipCopy)" -Detail "Se presupune că fișierele există deja pe jumphost"
} else {
    # Convert CRLF -> LF on Windows before archiving.
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $linuxExts = '*.sh','*.py','*.yml','*.yaml','*.j2','*.cfg','*.conf','*.ini','*.json'
    $converted = 0
    foreach ($ext in $linuxExts) {
        Get-ChildItem -Path $LocalPath -Recurse -Include $ext -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $raw = [System.IO.File]::ReadAllText($_.FullName)
            $lf  = $raw -replace "`r`n", "`n" -replace "`r", "`n"
            if ($lf -ne $raw) {
                [System.IO.File]::WriteAllText($_.FullName, $lf, $utf8NoBom)
                $converted++
            }
        }
    }
    Write-Log-OK "CRLF → LF" -Detail "$converted fisiere convertite"

    # tar-pipe: arhiva comprimata transferata si extrasa intr-o singura conexiune SSH (1 autentificare)
    Write-Log-Step "tar-pipe $LocalPath → ${SSHTarget}:${RemotePath} ..."
    tar -czf - -C $LocalPath . | ssh @SSHOpts $SSHTarget "mkdir -p ${RemotePath} && tar -xzf - -C ${RemotePath}"
    if ($LASTEXITCODE -ne 0) {
        Write-Log-Fail "Copiere esuata (tar-pipe)" -Detail "Verifica ca tar.exe este disponibil (Windows 10+)"
        Stop-LogSession; exit 1
    }
    Write-Log-OK "Fișiere Ansible copiate" -Detail "${SSHTarget}:${RemotePath}"
}

# =============================================================================
# STEP 2: Permisiuni + activeaza inventory + verificare
# =============================================================================

# Compute deploy domain as a PowerShell variable so it expands correctly inside the @"..."@ here-string
$DeployDomain = if ($Environment -eq 'dev') { 'mediasrl-dev.swedencentral.cloudapp.azure.com' } else { 'mediasrl.swedencentral.cloudapp.azure.com' }

Write-Log-Header "Configurare permisiuni, inventory și vault" -Step 2 -Total 2

if ($SkipConfig -and $SkipVault) {
    Write-Log-Warn "SKIP: Configurare + Vault (-SkipConfig și -SkipVault)"
} else {
    $combinedParts = [System.Collections.Generic.List[string]]::new()

    if (-not $SkipConfig) {
        Write-Log-Step "Permisiuni, activare inventory ($SourceInventory → $ActiveInventory), domain: $DeployDomain"
        $step2Content = @"
echo '========================================='
echo 'STEP 2: Configurare finala'
echo '========================================='

echo ''
echo '--- Permisiuni ---'
chmod 755 ${RemotePath}
mkdir -p ${RemotePath}/logs && chmod 775 ${RemotePath}/logs
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
find ${RemotePath} -name '*.sh' -type f | xargs -r perl -pi -e 's/\r\n/\n/g; s/\r/\n/g'
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
# vault-pass nu exista inca la aceasta etapa (se creeaza din KV mai jos).
# Eroarea de vault de mai jos este asteptata si nu opreste scriptul.
cd ${RemotePath} && ansible all --list-hosts 2>&1 | head -20 || true
"@ -replace "`r`n", "`n"
        [void]$combinedParts.Add($step2Content)
    }

    if (-not $SkipVault) {
        Write-Log-Step "Vault: MSI → KV → vault.yml AES-256..."
        # ANSIBLE_CONFIG trebuie setat explicit — sesiunile SSH non-interactive nu surseaza .bashrc
        $vaultContent = @"

echo ''
echo '========================================='
echo 'Ansible Vault Bootstrap'
echo '========================================='
export ANSIBLE_CONFIG=${RemotePath}/ansible.cfg
cd ${RemotePath}
bash scripts/create-ansible-vault.sh
"@ -replace "`r`n", "`n"
        [void]$combinedParts.Add($vaultContent)
    }

    $combinedScript = ($combinedParts -join "`n")
    $combinedLines = [System.Collections.Generic.List[string]]::new()
    # Scriem scriptul in fisier temp pe remote si facem strip de \r (CRLF Windows) inainte de executie
    $combinedScript | ssh @SSHOpts $SSHTarget 'cat > /tmp/_deploy_cs.sh && sed -i "s/\r//" /tmp/_deploy_cs.sh && bash /tmp/_deploy_cs.sh; rc=$?; rm -f /tmp/_deploy_cs.sh; exit $rc' 2>&1 | ForEach-Object { Write-Host $_; [void]$combinedLines.Add([string]$_) }
    $combinedExit = $LASTEXITCODE

    $labelParts = [System.Collections.Generic.List[string]]::new()
    if (-not $SkipConfig) { [void]$labelParts.Add("permisiuni+inventory") }
    if (-not $SkipVault)  { [void]$labelParts.Add("vault") }
    Write-Log-Block -Label "Output SSH: $($labelParts -join ' + ')" -Content ($combinedLines -join "`n")

    if ($combinedExit -ne 0) {
        $failDetail = if (-not $SkipVault) { "Verifica: MSI are 'Key Vault Secrets User' pe kv-mediasrl-persistent | toate secretele exista (ruleaza 0-bootstrap-keyvault.ps1)" } else { "SSH exit code $combinedExit" }
        Write-Log-Fail "Configurare/Vault esuat" -Detail $failDetail
        Stop-LogSession; exit 1
    }
    if (-not $SkipConfig) {
        Write-Log-OK "Permisiuni setate, inventory activat" -Detail "$SourceInventory → $ActiveInventory  |  domain=$DeployDomain"
    }
    if (-not $SkipVault) {
        Write-Log-OK "Vault configurat" -Detail "~/.vault-pass + group_vars/all/vault.yml (AES-256)"
    }
}

# =============================================================================
# REZULTAT FINAL
# =============================================================================

Write-Log-Header "Rezultat deployment"
Write-Log-OK "Fisiere Ansible configurate pe jumphost" -Detail "${RemotePath}"
Write-Log-OK "~/.vault-pass setat — vault.yml (AES-256) decriptabil"
Write-Log-Info "Pasul urmator — conectare la jumphost si rulare playbook-uri:"
Write-Log-Info "  ssh ${User}@${JumphostIP}"
Write-Log-Info "  cd ${RemotePath}"
Write-Log-Info "  ansible linux   -m ping                          # verifica conectivitate"
Write-Log-Info "  ansible windows -m win_ping"
Write-Log-Info "  ./run-playbook.sh 1-base-setup.yml"
Write-Log-Info "  ./run-playbook.sh 2-deploy-wordpress.yml"
Write-Log-Info "  ./run-playbook.sh 3-wordpress-config.yml"
Write-Log-Info "  ./run-playbook.sh 4-harden-nginx-ssl_ssllabs.com_ssltest.yml"
Write-Log-Info "  bash scripts/certbot-letsencrypt.sh --env prod   # certificat TLS"
Write-Log-Info "  ./run-playbook.sh 'harden-security.yml'"
Write-Log-Info "  ./run-playbook.sh 6-monitoring.yml"
Write-Log-Info "Sau testeaza mai intai infrastructura Azure: .\scripts\4-test-infrastructure.ps1"

Stop-LogSession
