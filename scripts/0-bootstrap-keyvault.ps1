# ============================================================
# Script 0: Bootstrap Persistent Key Vault — SC MEDIA SRL
#
# Run ONCE before any main.bicep deployment.
# Creates the persistent KV in rg-mediasrl-persistent and
# populates all infrastructure secrets.
#
# Prerequisites:
#   az login (as the admin user whose objectId is in tenantId/adminObjectId)
#   bicep CLI (az bicep install)
#
# Usage:
#   .\scripts\0-bootstrap-keyvault.ps1                  <- setup initial (rescrie fortat toate secretele)
#   .\scripts\0-bootstrap-keyvault.ps1 -Environment dev <- setup pentru dev
# ============================================================

param(
    [ValidateSet('prod', 'dev')]
    [string]$Environment = 'prod'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\Write-Log.ps1"
$_LogDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs'
Start-LogSession -ScriptTitle "Bootstrap Key Vault" -LogDirectory $_LogDir

trap {
    Write-Log-Fail "Eroare neasteptata: $_" -Detail "Script oprit prematur"
    Stop-LogSession
    break
}

# ============================================================
# Configuration
# ============================================================

$TenantId            = 'ac82a445-2540-4eda-a5c6-839042376d8f'
$AdminObjectId       = '9f286d78-d412-436b-9f1d-cdd24b456a0c'
$SubscriptionId      = '7a0255bf-d664-4920-afb0-c523b49c1908'
$Location            = 'swedencentral'
$PersistentRgName    = 'rg-mediasrl-persistent'
$KvName              = 'kv-mediasrl-persistent'

# ============================================================
# Helper: citire valoare secreta (env var -> prompt securizat)
# ============================================================

function Get-SecretValue([string]$EnvVar, [string]$Prompt) {
    $envVal = [System.Environment]::GetEnvironmentVariable($EnvVar)
    if ($envVal) { return $envVal }
    $secure = Read-Host -Prompt "  $Prompt" -AsSecureString
    return [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    )
}

# Numele secretelor definite de utilizator (fara ansible-vault-password, acela e auto-generat)
$UserSecretNames = @(
    'vm-admin-password',
    'mysql-root-password',
    'mysql-wordpress-password',
    'mysql-monitoring-password',
    'mysql-api-password',
    'wordpress-admin-password'
)

# ============================================================
# Selectie mod introducere parole
# ============================================================

Write-Host ""
Write-Host "  Cum introduci parolele?" -ForegroundColor White
Write-Host ""
Write-Host "  [1] Fisier CSV  — citeste parolele dintr-un fisier .csv" -ForegroundColor Cyan
Write-Host "                    Format: SecretName,Value (cu header)" -ForegroundColor Gray
Write-Host "                    Exemplu: scripts/secrets.csv.example" -ForegroundColor Gray
Write-Host ""
Write-Host "  [2] Manual      — introduce fiecare parola de la tastatura" -ForegroundColor Yellow
Write-Host "                    (sau seteaza env vars: SECRET_VM_ADMIN etc.)" -ForegroundColor Gray
Write-Host ""

do {
    $inputChoice = Read-Host "  Alege (1/2)"
} while ($inputChoice -ne '1' -and $inputChoice -ne '2')

$Secrets = @{}

# ============================================================
# Mod CSV
# ============================================================

if ($inputChoice -eq '1') {
    Write-Host ""

    # Citire cale fisier (cu retry daca nu exista)
    do {
        $csvPath = (Read-Host "  Cale fisier CSV").Trim('"').Trim("'")
        if (-not (Test-Path $csvPath)) {
            Write-Host "  [!!] Fisierul '$csvPath' nu exista. Incearca din nou." -ForegroundColor Red
        }
    } while (-not (Test-Path $csvPath))

    # Parsare CSV
    try {
        $csvRows = Import-Csv -Path $csvPath -ErrorAction Stop
    } catch {
        Write-Host "  [!!] Eroare la citirea CSV: $_" -ForegroundColor Red
        exit 1
    }

    # Validare coloane
    $firstRow = $csvRows | Select-Object -First 1
    if (-not ($firstRow.PSObject.Properties.Name -contains 'SecretName') -or
        -not ($firstRow.PSObject.Properties.Name -contains 'Value')) {
        Write-Host "  [!!] CSV-ul trebuie sa aiba coloanele 'SecretName' si 'Value'." -ForegroundColor Red
        Write-Host "       Verifica scripts/secrets.csv.example pentru formatul corect." -ForegroundColor Gray
        exit 1
    }

    foreach ($row in $csvRows) {
        $name = $row.SecretName.Trim()
        $val  = $row.Value
        if ($name -ne '' -and $null -ne $val) {
            $Secrets[$name] = $val
        }
    }

    # Validare: toate secretele necesare sunt prezente
    $missing = @($UserSecretNames | Where-Object { -not $Secrets.ContainsKey($_) })
    if ($missing.Count -gt 0) {
        Write-Host ""
        Write-Host "  [!!] Secretele urmatoare lipsesc din CSV:" -ForegroundColor Red
        $missing | ForEach-Object { Write-Host "       - $_" -ForegroundColor Red }
        Write-Host ""
        Write-Host "  Verifica scripts/secrets.csv.example pentru lista completa." -ForegroundColor Gray
        exit 1
    }

    Write-Host "  [OK] CSV incarcat: $($Secrets.Count) secrete citite din '$csvPath'." -ForegroundColor Green

# ============================================================
# Mod Manual
# ============================================================

} else {
    Write-Host ""
    Write-Host "  Introduceti parolele (env vars au prioritate daca sunt setate):" -ForegroundColor Yellow
    Write-Host ""

    $Secrets['vm-admin-password']         = Get-SecretValue 'SECRET_VM_ADMIN'   'VM admin password (azureadmin)'
    $Secrets['mysql-root-password']       = Get-SecretValue 'SECRET_MYSQL_ROOT' 'MySQL root password'
    $Secrets['mysql-wordpress-password']  = Get-SecretValue 'SECRET_MYSQL_WP'   'MySQL wordpress user password'
    $Secrets['mysql-monitoring-password'] = Get-SecretValue 'SECRET_MYSQL_MON'  'MySQL monitoring user password'
    $Secrets['mysql-api-password']        = Get-SecretValue 'SECRET_MYSQL_API'  'MySQL API user password'
    $Secrets['wordpress-admin-password']  = Get-SecretValue 'SECRET_WP_ADMIN'   'WordPress admin password'
}

# ansible-vault-password este intotdeauna auto-generat, nu se cere utilizatorului.
# Logica de skip/rotate este tratata in Step 4.
$Secrets['ansible-vault-password'] = [System.Guid]::NewGuid().ToString('N') + [System.Guid]::NewGuid().ToString('N')

# mysql-backup-encryption-key: generat aleator, NICIODATA rotat automat.
# Rotirea ar face imposibila decriptarea backup-urilor AES existente.
# Verificarea de existenta se face in Step 4 (dupa ce KV este garantat creat).
$Secrets['mysql-backup-encryption-key'] = [System.Guid]::NewGuid().ToString('N') + [System.Guid]::NewGuid().ToString('N')

# ============================================================
# Step 1: Set subscription context
# ============================================================

Write-Log-Header "Autentificare Azure" -Step 1 -Total 5
Write-Log-Step "az account set --subscription $SubscriptionId"
az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    Write-Log-Fail "az account set failed"
    Stop-LogSession; throw "az account set failed"
}
Write-Log-OK "Subscripție activată" -Detail $SubscriptionId

Write-Log-Header "Persistent Resource Group" -Step 2 -Total 5
$rgExists = az group exists --name $PersistentRgName | ConvertFrom-Json
if (-not $rgExists) {
    Write-Log-Step "Creare Resource Group $PersistentRgName..."
    az group create --name $PersistentRgName --location $Location `
        --tags environment=persistent project=mediasrl 'managed-by=bicep' | Out-Null
    Write-Log-OK "Resource Group creat" -Detail $PersistentRgName
} else {
    Write-Log-Warn "Resource Group deja există — skip" -Detail $PersistentRgName
}

Write-Log-Header "Deploy Key Vault via Bicep" -Step 3 -Total 5

# az deployment group create (Incremental) ar suprascrie accessPolicies cu
# doar cele din template, eliminand orice policy adaugata ulterior (ex: VM MSI).
$kvExists = az keyvault show --name $KvName --resource-group $PersistentRgName `
    --query name -o tsv 2>$null
$isNewKv  = [string]::IsNullOrEmpty($kvExists)

if ($isNewKv) {
    $deployName = "bootstrap-kv-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Log-Step "Deployment: $deployName"
    $kvDeployLines = [System.Collections.Generic.List[string]]::new()
    az deployment group create `
        --name $deployName `
        --resource-group $PersistentRgName `
        --template-file "$PSScriptRoot\..\bicep\bootstrap\keyvault-persistent.bicep" `
        --parameters `
            location=$Location `
            keyVaultName=$KvName `
            tenantId=$TenantId `
            adminObjectId=$AdminObjectId 2>&1 | ForEach-Object { Write-Host $_; [void]$kvDeployLines.Add([string]$_) }
    $kvDeployExit = $LASTEXITCODE
    Write-Log-Block -Label "Output az deployment group create — $deployName" -Content ($kvDeployLines -join "`n")

    if ($kvDeployExit -ne 0) {
        Write-Log-Fail "Key Vault deployment failed"
        Stop-LogSession; throw "Key Vault deployment failed"
    }
    Write-Log-OK "Key Vault creat" -Detail "https://$KvName.vault.azure.net/"
} else {
    Write-Log-Warn "Key Vault deja există — skip Bicep deploy (access policies păstrate)" -Detail $KvName
}

Write-Log-Header "Stocare secrete în Key Vault" -Step 4 -Total 5

foreach ($entry in $Secrets.GetEnumerator()) {
    $secretName  = $entry.Key
    $secretValue = $entry.Value

    # mysql-backup-encryption-key nu se roteste niciodata automat:
    # backup-urile vechi criptate cu cheia veche ar deveni indecriptabile.
    if ($secretName -eq 'mysql-backup-encryption-key') {
        $existing = az keyvault secret show `
            --vault-name $KvName `
            --name $secretName `
            --query value -o tsv 2>$null
        if (-not [string]::IsNullOrEmpty($existing)) {
            Write-Log-Warn "Secret pastrat (nu se roteste)" -Detail $secretName
            continue
        }
    }

    az keyvault secret set `
        --vault-name $KvName `
        --name $secretName `
        --value $secretValue `
        --output none

    if ($LASTEXITCODE -eq 0) {
        Write-Log-OK "Secret stocat (rescris)" -Detail $secretName
    } else {
        Write-Log-Warn "Nu s-a putut seta secretul" -Detail $secretName
    }
}

Write-Log-Header "Pași următori" -Step 5 -Total 5
Write-Log-Info "1. Construieste imagini Packer:  .\scripts\1-build-packer-images.ps1"
Write-Log-Info "2. Deployaza infrastructura:     .\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod"
Write-Log-Info "3. Copiaza Ansible pe jumphost:  .\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment prod -JumphostIP <IP>"
Write-Log-Info "4. Ruleaza playbook-urile (din ~/ansible pe jumphost):  ./run-playbook.sh <playbook>"
Write-Log-OK "Bootstrap complet — $KvName populat cu $($Secrets.Count) secrete" -Detail "https://$KvName.vault.azure.net/"

Stop-LogSession
