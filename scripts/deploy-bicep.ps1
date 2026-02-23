# ============================================================
# SC MEDIA SRL - Interactive Bicep Deployment Script
# Selecteaza interactiv mediul de deployment (dev sau prod)
# Nu afecteaza pipeline-urile Azure DevOps.
# Rulare: .\scripts\deploy-bicep.ps1
# ============================================================

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('dev','prod','')]
    [string]$Environment = '',

    [Parameter(Mandatory=$false)]
    [switch]$ValidateOnly,

    [Parameter(Mandatory=$false)]
    [switch]$NoConfirm
)

$ErrorActionPreference = 'Stop'

# ============================================================
# HELPER: colored output
# ============================================================

function Write-Header([string]$msg) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Step([string]$msg)    { Write-Host "[>>] $msg" -ForegroundColor Yellow }
function Write-OK([string]$msg)      { Write-Host "[OK] $msg" -ForegroundColor Green  }
function Write-Fail([string]$msg)    { Write-Host "[!!] $msg" -ForegroundColor Red    }
function Write-Info([string]$msg)    { Write-Host "     $msg" -ForegroundColor Gray   }

# ============================================================
# PASUL 0: Verificari preliminare
# ============================================================

Write-Header "SC MEDIA SRL - Bicep Interactive Deploy"

Write-Step "Verificare autentificare Azure CLI..."
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Nu esti autentificat. Ruleaza: az login"
    exit 1
}
$subId   = az account show --query id   -o tsv
$subName = az account show --query name -o tsv
Write-OK  "Autentificat pe subscriptia: $subName ($subId)"

# ============================================================
# PASUL 1: Selectie mediu
# ============================================================

if ($Environment -eq '') {
    Write-Host ""
    Write-Host "  Selecteaza mediul de deployment:" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] DEV  — rg-mediasrl-dezvoltare-swedencentral" -ForegroundColor Yellow
    Write-Host "             IP-uri persistente: rg-mediasrl-persistent-dev" -ForegroundColor Gray
    Write-Host "             DNS webserver: mediasrl-dev.swedencentral.cloudapp.azure.com" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  [2] PROD — rg-mediasrl-productie-swedencentral" -ForegroundColor Green
    Write-Host "             IP-uri persistente: rg-mediasrl-persistent" -ForegroundColor Gray
    Write-Host "             DNS webserver: mediasrl.swedencentral.cloudapp.azure.com" -ForegroundColor Gray
    Write-Host ""

    do {
        $choice = Read-Host "  Alege (1/2)"
    } while ($choice -ne '1' -and $choice -ne '2')

    $Environment = if ($choice -eq '1') { 'dev' } else { 'prod' }
}

# ============================================================
# PASUL 2: Configurare parametri in functie de mediu
# ============================================================

switch ($Environment) {
    'dev' {
        $ParamsFile       = 'bicep/parameters/dev.bicepparam'
        $MainRgName       = 'rg-mediasrl-dezvoltare-swedencentral'
        $PersistentRgName = 'rg-mediasrl-persistent-dev'
        $JmpPipName       = 'pip-dev-vm-jmp-01'
        $WebPipName       = 'pip-dev-vm-web-01'
        $DeployName       = "deploy-mediasrl-dev-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $EnvLabel         = 'DEZVOLTARE (DEV)'
        $EnvColor         = 'Yellow'
    }
    'prod' {
        $ParamsFile       = 'bicep/parameters/prod.bicepparam'
        $MainRgName       = 'rg-mediasrl-productie-swedencentral'
        $PersistentRgName = 'rg-mediasrl-persistent'
        $JmpPipName       = 'pip-vm-jmp-01'
        $WebPipName       = 'pip-vm-web-01'
        $DeployName       = "deploy-mediasrl-prod-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $EnvLabel         = 'PRODUCTIE (PROD)'
        $EnvColor         = 'Green'
    }
}

# ============================================================
# PASUL 3: Rezumat + confirmare
# ============================================================

Write-Host ""
Write-Host "  Mediu selectat: " -NoNewline
Write-Host $EnvLabel -ForegroundColor $EnvColor
Write-Host ""
Write-Host "  Fisier parametri : $ParamsFile" -ForegroundColor Gray
Write-Host "  Resource Group   : $MainRgName" -ForegroundColor Gray
Write-Host "  RG IP persistente: $PersistentRgName" -ForegroundColor Gray
Write-Host "  Deployment name  : $DeployName" -ForegroundColor Gray
if ($ValidateOnly) {
    Write-Host "  Mod              : VALIDARE ONLY (fara creare resurse)" -ForegroundColor Magenta
} else {
    Write-Host "  Mod              : DEPLOY COMPLET" -ForegroundColor White
}
Write-Host ""

# Verifica existenta fisierului de parametri
if (-not (Test-Path $ParamsFile)) {
    Write-Fail "Fisierul '$ParamsFile' nu exista. Ruleaza scriptul din radacina proiectului (IT/)."
    exit 1
}

if (-not $NoConfirm) {
    $confirm = Read-Host "  Continui? (d/n)"
    if ($confirm -notin @('d','D','da','Da','y','Y','yes')) {
        Write-Host ""
        Write-Host "  Anulat." -ForegroundColor Yellow
        exit 0
    }
}

# ============================================================
# PASUL 4: Validare Bicep
# ============================================================

Write-Header "PASUL 1/2 — Validare Bicep"

Write-Step "Rulare az deployment sub validate..."
az deployment sub validate `
    --location swedencentral `
    --template-file bicep/main.bicep `
    --parameters $ParamsFile `
    --name $DeployName

if ($LASTEXITCODE -ne 0) {
    Write-Fail "Validarea a esuat. Corecteaza erorile si relanseaza scriptul."
    exit 1
}

Write-OK "Validare OK."

if ($ValidateOnly) {
    Write-Host ""
    Write-Host "  Mod ValidateOnly — deployment oprit dupa validare." -ForegroundColor Magenta
    exit 0
}

# ============================================================
# PASUL 5: What-If (preview)
# ============================================================

Write-Header "PASUL 1.5 — What-If Preview"
Write-Step "Rulare what-if (previzualizare modificari)..."

az deployment sub what-if `
    --location swedencentral `
    --template-file bicep/main.bicep `
    --parameters $ParamsFile `
    --name $DeployName

Write-Host ""
if (-not $NoConfirm) {
    $confirm2 = Read-Host "  Aplici modificarile de mai sus? (d/n)"
    if ($confirm2 -notin @('d','D','da','Da','y','Y','yes')) {
        Write-Host ""
        Write-Host "  Deployment anulat dupa what-if." -ForegroundColor Yellow
        exit 0
    }
}

# ============================================================
# PASUL 6: Deploy
# ============================================================

Write-Header "PASUL 2/2 — Deploy $EnvLabel"
Write-Step "Rulare az deployment sub create..."
Write-Info "(poate dura 8-15 minute)"
Write-Host ""

$startTime = Get-Date

az deployment sub create `
    --location swedencentral `
    --template-file bicep/main.bicep `
    --parameters $ParamsFile `
    --name $DeployName

if ($LASTEXITCODE -ne 0) {
    Write-Fail "Deployment a esuat. Verifica erorile de mai sus."
    exit 1
}

$duration = [int]((Get-Date) - $startTime).TotalMinutes
Write-OK "Deployment complet in ~$duration minute(e)."

# ============================================================
# PASUL 7: Afisare output-uri
# ============================================================

Write-Header "Resurse create — $EnvLabel"

# IP-uri persistente
Write-Step "IP-uri publice persistente ($PersistentRgName):"
$pipExists = az group exists --name $PersistentRgName -o tsv
if ($pipExists -eq 'true') {
    $pips = az network public-ip list -g $PersistentRgName -o json | ConvertFrom-Json
    foreach ($pip in $pips) {
        $ip   = $pip.properties.ipAddress
        $fqdn = $pip.properties.dnsSettings?.fqdn
        Write-Host ""
        Write-Host "  $($pip.name)" -ForegroundColor White
        Write-Host "    IP  : $ip" -ForegroundColor Green
        if ($fqdn) {
            Write-Host "    DNS : $fqdn" -ForegroundColor Green
        }
    }
} else {
    Write-Info "(RG $PersistentRgName nu exista inca)"
}

# VM-uri
Write-Host ""
Write-Step "VM-uri in $MainRgName"
$rgExists = az group exists --name $MainRgName -o tsv
if ($rgExists -eq 'true') {
    az vm list -g $MainRgName -o table --query "[].{VM:name, OS:storageProfile.osDisk.osType, Size:hardwareProfile.vmSize}"
}

# ============================================================
# PASUL 8: Pasii urmatori
# ============================================================

Write-Header "Pasii urmatori"

$jmpIp = $null
if ($pipExists -eq 'true') {
    $jmpIp = az network public-ip show -g $PersistentRgName -n $JmpPipName --query ipAddress -o tsv 2>$null
}

Write-Host "  1. Copiaza Ansible pe jumphost:" -ForegroundColor White
if ($jmpIp) {
    Write-Host "     .\scripts\deploy-ansible-to-jumphost.ps1 -JumphostIP $jmpIp" -ForegroundColor Cyan
} else {
    Write-Host "     .\scripts\deploy-ansible-to-jumphost.ps1 -JumphostIP <IP_JUMPHOST>" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "  2. Conecteaza-te RDP la jumphost:" -ForegroundColor White
if ($jmpIp) {
    Write-Host "     mstsc /v:$jmpIp" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "  3. Din jumphost, ruleaza Ansible:" -ForegroundColor White
if ($Environment -eq 'dev') {
    Write-Host "     cd ~/ansible" -ForegroundColor Cyan
    Write-Host "     ansible-playbook playbooks/site.yml -i inventory/azure_rm_dev.yml" -ForegroundColor Cyan
} else {
    Write-Host "     cd ~/ansible" -ForegroundColor Cyan
    Write-Host "     ansible-playbook playbooks/site.yml" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "  4. Teste infrastructura (local):" -ForegroundColor White
Write-Host "     .\scripts\test-infrastructure.ps1" -ForegroundColor Cyan
Write-Host ""

Write-Host "==========================================" -ForegroundColor $EnvColor
Write-Host "  Deploy $EnvLabel — FINALIZAT" -ForegroundColor $EnvColor
Write-Host "==========================================" -ForegroundColor $EnvColor
Write-Host ""
