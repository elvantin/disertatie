# ============================================================
# SC MEDIA SRL — Deploy / Teardown Bicep
#
# Ofera doua operatii:
#   DEPLOY   — Valideaza, ruleaza what-if si deployaza infrastructura
#   TEARDOWN — Sterge Resource Group-ul principal (pastreaza persistent RG)
#
# Rulare interactiva (recomandat):
#   .\scripts\2-deploy-teardown-bicep.ps1
#
# Rulare cu parametri (CI / scripturi):
#   .\scripts\2-deploy-teardown-bicep.ps1 -Action deploy   -Environment prod
#   .\scripts\2-deploy-teardown-bicep.ps1 -Action teardown -Environment dev -NoConfirm
# ============================================================

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('deploy','teardown','')]
    [string]$Action = '',

    [Parameter(Mandatory=$false)]
    [ValidateSet('dev','prod','')]
    [string]$Environment = '',

    [Parameter(Mandatory=$false)]
    [switch]$ValidateOnly,

    [Parameter(Mandatory=$false)]
    [switch]$NoConfirm
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Force UTF-8 throughout so az CLI (Python) can output Unicode (→, ✓ etc.) when piped.
# PYTHONIOENCODING alone is not enough on Windows — az uses locale.getpreferredencoding()
# which returns cp1252 for pipes. PYTHONUTF8=1 overrides locale entirely (Python 3.7+).
$env:PYTHONUTF8              = '1'
$env:PYTHONIOENCODING        = 'utf-8'
[Console]::OutputEncoding    = [System.Text.Encoding]::UTF8
$OutputEncoding              = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\lib\Write-Log.ps1"
$_LogDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs'
Start-LogSession -ScriptTitle "Deploy / Teardown Bicep" -LogDirectory $_LogDir

# Ensure the HTML log is always written even if the script crashes unexpectedly.
trap {
    Write-Log-Fail "Eroare neasteptata: $_" -Detail "Script oprit prematur"
    Stop-LogSession
    break
}

# ============================================================
# Helpers — delegate to shared logging library
# ============================================================

function Write-Header([string]$msg) { Write-Log-Header $msg }
function Write-Step([string]$msg)   { Write-Log-Step   $msg }
function Write-OK([string]$msg)     { Write-Log-OK     $msg }
function Write-Fail([string]$msg)   { Write-Log-Fail   $msg }
function Write-Info([string]$msg)   { Write-Log-Info   $msg }
function Write-Warn([string]$msg)   { Write-Log-Warn   $msg }

# ============================================================
# PASUL 0: Verificare autentificare Azure CLI
# ============================================================

Write-Log-Header "SC MEDIA SRL — Deploy / Teardown Bicep"

Write-Step "Verificare autentificare Azure CLI..."
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Nu ești autentificat. Rulează: az login"
    Stop-LogSession; exit 1
}
$subId   = az account show --query id   -o tsv
$subName = az account show --query name -o tsv
Write-OK "Subscriptie activa: $subName ($subId)"

# ============================================================
# PASUL 1: Selectie actiune
# ============================================================

if ($Action -eq '') {
    Write-Host ""
    Write-Host "  Ce doresti sa faci?" -ForegroundColor White
    Write-Host ""
    Write-Host "  [1] DEPLOY   — Deployaza / actualizeaza infrastructura" -ForegroundColor Green
    Write-Host "  [2] TEARDOWN — Sterge Resource Group-ul principal" -ForegroundColor Red
    Write-Host ""

    do {
        $actionChoice = Read-Host "  Alege (1/2)"
    } while ($actionChoice -ne '1' -and $actionChoice -ne '2')

    $Action = if ($actionChoice -eq '1') { 'deploy' } else { 'teardown' }
}

# ============================================================
# PASUL 2: Selectie mediu
# ============================================================

if ($Environment -eq '') {
    Write-Host ""
    Write-Host "  Selecteaza mediul:" -ForegroundColor White
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
        $envChoice = Read-Host "  Alege (1/2)"
    } while ($envChoice -ne '1' -and $envChoice -ne '2')

    $Environment = if ($envChoice -eq '1') { 'dev' } else { 'prod' }
}

# ============================================================
# PASUL 3: Configurare parametri in functie de mediu
# ============================================================

switch ($Environment) {
    'dev' {
        $ParamsFile       = 'bicep/parameters/dev.bicepparam'
        $MainRgName       = 'rg-mediasrl-dezvoltare-swedencentral'
        $PersistentRgName = 'rg-mediasrl-persistent-dev'
        $JmpPipName       = 'pip-dev-vm-jmp-01'
        $DeployName       = "deploy-mediasrl-dev-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $EnvLabel         = 'DEZVOLTARE (DEV)'
        $EnvColor         = 'Yellow'
        $ConfirmWord      = 'DEZVOLTARE'
    }
    'prod' {
        $ParamsFile       = 'bicep/parameters/prod.bicepparam'
        $MainRgName       = 'rg-mediasrl-productie-swedencentral'
        $PersistentRgName = 'rg-mediasrl-persistent'
        $JmpPipName       = 'pip-vm-jmp-01'
        $DeployName       = "deploy-mediasrl-prod-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $EnvLabel         = 'PRODUCTIE (PROD)'
        $EnvColor         = 'Green'
        $ConfirmWord      = 'PRODUCTIE'
    }
}

# ============================================================
# ============================================================
# RAMURA DEPLOY
# ============================================================
# ============================================================

if ($Action -eq 'deploy') {

    # --- Detectare IP public admin (pentru whitelist NSG) ---
    $AdminIp = $null
    try {
        $rawIp = (Invoke-WebRequest -Uri 'https://api.ipify.org' -UseBasicParsing -TimeoutSec 10).Content.Trim()
        if ($rawIp -match '^\d+\.\d+\.\d+\.\d+$') { $AdminIp = "$rawIp/32" }
    } catch { }

    # --- Rezumat ---

    Write-Host ""
    Write-Host "  Actiune  : " -NoNewline; Write-Host "DEPLOY" -ForegroundColor Green
    Write-Host "  Mediu    : " -NoNewline; Write-Host $EnvLabel -ForegroundColor $EnvColor
    Write-Host ""
    Write-Host "  Parametri    : $ParamsFile" -ForegroundColor Gray
    Write-Host "  Main RG      : $MainRgName" -ForegroundColor Gray
    Write-Host "  Persistent RG: $PersistentRgName" -ForegroundColor Gray
    Write-Host "  Deployment   : $DeployName" -ForegroundColor Gray
    if ($AdminIp) {
        Write-Host "  Admin IP     : " -NoNewline; Write-Host $AdminIp -ForegroundColor Cyan
    } else {
        Write-Host "  Admin IP     : " -NoNewline; Write-Host "(din $ParamsFile — detectie IP esuata)" -ForegroundColor DarkGray
    }
    if ($ValidateOnly) {
        Write-Host "  Mod          : VALIDARE ONLY (fara creare resurse)" -ForegroundColor Magenta
    }
    Write-Host ""

    if (-not (Test-Path $ParamsFile)) {
        Write-Fail "Fișierul '$ParamsFile' nu există. Rulează scriptul din rădăcina proiectului (IT/)."
        Stop-LogSession; exit 1
    }

    if (-not $NoConfirm) {
        $c = Read-Host "  Continui cu deployment-ul? (d/n)"
        if ($c -notin @('d','D','da','Da','y','Y','yes')) {
            Write-Log-Warn "Deployment anulat de utilizator"
            Stop-LogSession; exit 0
        }
    }

    # Build override array — passed to all three az deployment commands (validate / what-if / create)
    # Empty array when IP detection failed: az uses the value from the .bicepparam file instead
    $AzParamOverrides = @()
    if ($AdminIp) {
        Write-Log-OK "Admin IP detectat" -Detail "$AdminIp → whitelist NSG (Allow-SSH-From-Admin, Allow-RDP-From-Admin)"
        $AzParamOverrides = @("--parameters", "adminIpAddress=$AdminIp")
    } else {
        Write-Log-Warn "Admin IP nedetectat" -Detail "se va folosi adminIpAddress din $ParamsFile"
    }

    # --- Validare ---

    Write-Header "DEPLOY 1/3 — Validare Bicep"
    Write-Step "az deployment sub validate..."

    $valLines = [System.Collections.Generic.List[string]]::new()
    az deployment sub validate `
        --location swedencentral `
        --template-file bicep/main.bicep `
        --parameters $ParamsFile `
        @AzParamOverrides `
        --name $DeployName 2>&1 | ForEach-Object { Write-Host $_; [void]$valLines.Add([string]$_) }

    if ($LASTEXITCODE -ne 0) {
        Write-Log-Block -Label "Output validare Bicep — EȘUAT" -Content ($valLines -join "`n")
        Write-Fail "Validarea a eșuat. Corectează erorile și relansează scriptul."
        Stop-LogSession; exit 1
    }
    Write-OK "Validare Bicep OK"

    if ($ValidateOnly) {
        Write-Log-Info "Mod ValidateOnly — oprit după validare."
        Stop-LogSession; exit 0
    }

    # --- What-If ---

    Write-Header "DEPLOY 2/3 — What-If Preview"
    Write-Step "az deployment sub what-if (previzualizare modificări)..."

    # What-if outputs Unicode arrows (→, ✓) that cause a Python charmap encoding error
    # when piped on Windows. Running it unpipped lets az write directly to the console
    # which uses the correct encoding. The user reads it live and decides whether to apply.
    az deployment sub what-if `
        --location swedencentral `
        --template-file bicep/main.bicep `
        --parameters $ParamsFile `
        @AzParamOverrides `
        --name $DeployName

    Write-Log-Info "What-If afișat în terminal" -Detail "output interactiv — nu este capturat în HTML (caractere Unicode incompatibile cu pipe Windows)"

    Write-Host ""
    if (-not $NoConfirm) {
        $c2 = Read-Host "  Aplici modificările de mai sus? (d/n)"
        if ($c2 -notin @('d','D','da','Da','y','Y','yes')) {
            Write-Log-Warn "Deployment anulat după what-if"
            Stop-LogSession; exit 0
        }
    }

    # --- Deploy ---

    Write-Header "DEPLOY 3/3 — $EnvLabel"
    Write-Step "az deployment sub create..."
    Write-Info "(poate dura 8-15 minute)"

    $startTime = Get-Date
    $deployLines = [System.Collections.Generic.List[string]]::new()
    az deployment sub create `
        --location swedencentral `
        --template-file bicep/main.bicep `
        --parameters $ParamsFile `
        @AzParamOverrides `
        --name $DeployName 2>&1 | ForEach-Object { Write-Host $_; [void]$deployLines.Add([string]$_) }
    $deployExit = $LASTEXITCODE

    if ($deployExit -ne 0) {
        # On failure keep the raw output — it contains the error details
        Write-Log-Block -Label "Output az deployment create — EȘUAT" -Content ($deployLines -join "`n")
        Write-Fail "Deployment a eșuat. Verifică erorile de mai sus."
        Stop-LogSession; exit 1
    }

    $duration = [int]((Get-Date) - $startTime).TotalMinutes
    Write-Log-OK "Deployment complet" -Detail "~$duration minute(e) · $DeployName"

    # Fetch structured result and render as a formatted HTML card
    $deployResultJson = az deployment sub show --name $DeployName -o json 2>$null | ConvertFrom-Json
    if ($deployResultJson) {
        Write-Log-AzDeployment -DeploymentName $DeployName -Result $deployResultJson
    }

    # --- Output-uri ---

    Write-Header "Resurse create — $EnvLabel"

    $pipExists = az group exists --name $PersistentRgName -o tsv
    if ($pipExists -eq 'true') {
        $pips = az network public-ip list -g $PersistentRgName -o json | ConvertFrom-Json
        foreach ($pip in $pips) {
            $ip   = $pip.ipAddress
            $fqdn = if ($pip.PSObject.Properties.Name -contains 'dnsSettings') { $pip.dnsSettings?.fqdn } else { $null }
            Write-Log-OK "$($pip.name)" -Detail "IP: $ip$(if ($fqdn) { ' | DNS: ' + $fqdn })"
        }
    } else {
        Write-Info "(RG $PersistentRgName nu există încă)"
    }

    $rgExists = az group exists --name $MainRgName -o tsv
    if ($rgExists -eq 'true') {
        $vmTblLines = [System.Collections.Generic.List[string]]::new()
        az vm list -g $MainRgName -o table `
            --query "[].{VM:name, OS:storageProfile.osDisk.osType, Size:hardwareProfile.vmSize}" 2>&1 | ForEach-Object { Write-Host $_; [void]$vmTblLines.Add([string]$_) }
        Write-Log-Block -Label "VM-uri în $MainRgName" -Content ($vmTblLines -join "`n")
    }

    # --- Pași următori ---

    Write-Header "Pași următori"

    $jmpIp = $null
    if ($pipExists -eq 'true') {
        $jmpIp = az network public-ip show -g $PersistentRgName -n $JmpPipName --query ipAddress -o tsv 2>$null
    }

    if ($jmpIp) {
        Write-Log-Info "1. Deploy Ansible:  .\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment $Environment -JumphostIP $jmpIp"
    } else {
        Write-Log-Info "1. Deploy Ansible:  .\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment $Environment -JumphostIP <IP>"
    }
    Write-Log-Info "2. Teste Azure:     .\scripts\4-test-infrastructure.ps1"
    Write-Log-Info "3. SSH la jumphost: ssh azureadmin@$(if ($jmpIp) { $jmpIp } else { '<IP_JUMPHOST>' })"
    Write-Log-Info "4. Ruleaza playbook-urile (din ~/ansible pe jumphost):"
    Write-Log-Info "     ./run-playbook.sh 1-base-setup.yml"
    Write-Log-Info "     ./run-playbook.sh 2-deploy-wordpress.yml"
    Write-Log-Info "     ./run-playbook.sh 3-wordpress-config.yml"
    Write-Log-Info "     ./run-playbook.sh 4-harden-nginx-ssl_ssllabs.com_ssltest.yml"
    Write-Log-Info "     bash scripts/certbot-letsencrypt.sh --env prod"
    Write-Log-Info "     ./run-playbook.sh 'harden-security(daca_nu_rulez_demouri).yml'"
    Write-Log-Info "     ./run-playbook.sh 6-monitoring.yml"

    Write-Log-OK "Deploy $EnvLabel — FINALIZAT"
    Stop-LogSession
}

# ============================================================
# ============================================================
# RAMURA TEARDOWN
# ============================================================
# ============================================================

elseif ($Action -eq 'teardown') {

    Write-Host ""
    Write-Host "  Actiune  : " -NoNewline; Write-Host "TEARDOWN" -ForegroundColor Red
    Write-Host "  Mediu    : " -NoNewline; Write-Host $EnvLabel -ForegroundColor $EnvColor
    Write-Host ""

    # Verifica daca RG-ul exista
    Write-Step "Verificare existenta Resource Group..."
    $rgExists = az group exists --name $MainRgName -o tsv
    if ($rgExists -ne 'true') {
        Write-Warn "Resource Group-ul '$MainRgName' nu exista. Nimic de sters."
        exit 0
    }

    Write-Step "Resurse în $MainRgName (înainte de ștergere):"
    $resLines = [System.Collections.Generic.List[string]]::new()
    az resource list -g $MainRgName -o table `
        --query "[].{Nume:name, Tip:type, Locatie:location}" 2>$null | ForEach-Object { Write-Host $_; [void]$resLines.Add([string]$_) }
    Write-Log-Block -Label "Resurse în $MainRgName" -Content ($resLines -join "`n")

    Write-Host ""
    Write-Log-OK "NU se șterge (persistent RG)" -Detail "$PersistentRgName — IP-uri statice + kv-mediasrl-persistent"
    Write-Warn "CE SE ȘTERGE: $MainRgName și TOATE resursele din el."
    Write-Warn "Această operație este IREVERSIBILĂ."

    if (-not $NoConfirm) {
        $c1 = Read-Host "  Ești sigur că vrei să ștergi '$MainRgName'? (d/n)"
        if ($c1 -notin @('d','D','da','Da','y','Y','yes')) {
            Write-Log-Warn "Teardown anulat de utilizator"
            Stop-LogSession; exit 0
        }

        if ($Environment -eq 'prod') {
            Write-Warn "ATENȚIE: Ești pe PRODUCȚIE."
            Write-Host "  Scrie '$ConfirmWord' (fără ghilimele) pentru a confirma:" -ForegroundColor Red
            $typed = Read-Host "  Confirmare"
            if ($typed -ne $ConfirmWord) {
                Write-Log-Warn "Confirmare incorectă — teardown anulat"
                Stop-LogSession; exit 0
            }
        }
    }

    # =========================================================
    # Dezactivare Azure Backup (obligatoriu inainte de az group delete)
    # Un Recovery Services Vault cu itemi protejati NU poate fi sters.
    # =========================================================

    Write-Header "Dezactivare Azure Backup"
    $vaultList = @(az backup vault list -g $MainRgName -o json 2>$null | ConvertFrom-Json)

    if ($vaultList.Count -gt 0) {
        foreach ($vault in $vaultList) {
            $vName = $vault.name
            Write-Log-Step "Recovery Services Vault: $vName"

            # Disable soft-delete so that stopped items are permanently deleted
            az backup vault backup-properties set `
                --vault-name $vName -g $MainRgName `
                --soft-delete-feature-state Disable 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Log-OK "Soft-delete dezactivat" -Detail $vName
            } else {
                Write-Log-Warn "Nu s-a putut dezactiva soft-delete pe $vName (continuam oricum)"
            }

            # Stop protection + delete backup data for every protected VM
            $items = @(az backup item list `
                --vault-name $vName -g $MainRgName `
                --backup-management-type AzureIaasVM `
                -o json 2>$null | ConvertFrom-Json)

            Write-Log-Info "$($items.Count) itemi protejati gasiti in $vName"

            foreach ($item in $items) {
                $cName      = $item.properties.containerName
                $iName      = $item.name
                $vmFriendly = $item.properties.friendlyName

                # deleteState is absent when soft-delete is disabled — use safe access to avoid
                # StrictMode terminating error when the property doesn't exist on the object
                $deleteState = if ($item.properties.PSObject.Properties.Name -contains 'deleteState') {
                    $item.properties.deleteState
                } else { $null }

                # Items in soft-deleted state must be undeleted before permanent delete
                if ($deleteState -eq 'ToBeDeleted') {
                    Write-Log-Step "  Reactivare (undelete): $vmFriendly..."
                    az backup protection undelete `
                        --vault-name $vName -g $MainRgName `
                        --container-name $cName --item-name $iName `
                        --backup-management-type AzureIaasVM --workload-type VM 2>$null | Out-Null
                }

                Write-Log-Step "  Stopare protectie + stergere date: $vmFriendly..."
                az backup protection disable `
                    --vault-name $vName -g $MainRgName `
                    --container-name $cName --item-name $iName `
                    --backup-management-type AzureIaasVM --workload-type VM `
                    --delete-backup-data true --yes 2>$null | Out-Null

                if ($LASTEXITCODE -eq 0) {
                    Write-Log-OK "Backup dezactivat: $vmFriendly" -Detail "date sterse definitiv"
                } else {
                    Write-Log-Warn "Nu s-a putut dezactiva: $vmFriendly" -Detail "continuam..."
                }
            }

            # az backup protection disable is async — wait for all jobs to finish
            # before attempting vault/group deletion (max 10 min)
            Write-Log-Step "Asteptare finalizare joburi backup in $vName (max 10 min)..."
            $maxWait = 60  # 60 x 10s = 10 minute
            $waited  = 0
            do {
                $pendingJobs = @(az backup job list `
                    --vault-name $vName -g $MainRgName `
                    --status InProgress -o json 2>$null | ConvertFrom-Json)
                if ($pendingJobs.Count -gt 0) {
                    Write-Log-Info "  $($pendingJobs.Count) joburi in curs... (astept 10s)"
                    Start-Sleep -Seconds 10
                }
                $waited++
            } while ($pendingJobs.Count -gt 0 -and $waited -lt $maxWait)

            if ($pendingJobs.Count -gt 0) {
                Write-Log-Warn "Joburi backup inca active dupa 10 minute — continuam oricum"
            } else {
                Write-Log-OK "Joburi backup finalizate" -Detail $vName
            }

            # Unregister all backup containers — vault deletion fails if containers remain
            # registered even after all protected items have been removed
            $containers = @(az backup container list `
                --vault-name $vName -g $MainRgName `
                --backup-management-type AzureIaasVM `
                -o json 2>$null | ConvertFrom-Json)
            Write-Log-Info "$($containers.Count) containere de dezinregistrat in $vName"
            foreach ($container in $containers) {
                $cnName = $container.name
                Write-Log-Step "  Dezinregistrare container: $cnName..."
                az backup container unregister `
                    --vault-name $vName -g $MainRgName `
                    --container-name $cnName `
                    --backup-management-type AzureIaasVM --yes 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Log-OK "Container dezinregistrat" -Detail $cnName
                } else {
                    Write-Log-Warn "Nu s-a putut dezinregistra containerul" -Detail $cnName
                }
            }

            # Vault must be explicitly deleted before the resource group — az group delete
            # alone will fail while the vault still exists (even with no protected items)
            Write-Log-Step "Stergere explicita vault: $vName..."
            az backup vault delete --name $vName -g $MainRgName --force --yes 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Log-OK "Vault sters" -Detail $vName
            } else {
                Write-Log-Warn "Stergerea directa a vault-ului a esuat — az group delete va incerca" -Detail $vName
            }
        }
    } else {
        Write-Log-Info "Niciun Recovery Services Vault in $MainRgName"
    }

    Write-Header "TEARDOWN — Ștergere $MainRgName"
    Write-Step "az group delete --name $MainRgName ..."
    Write-Info "(poate dura 5-12 minute)"

    $startTime = Get-Date

    az group delete `
        --name $MainRgName `
        --yes

    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Ștergerea a eșuat. Verifică erorile de mai sus."
        Stop-LogSession; exit 1
    }

    $duration = [int]((Get-Date) - $startTime).TotalMinutes
    Write-Log-OK "Resource Group șters" -Detail "$MainRgName · ~$duration minute(e)"

    Write-Step "Verificare persistent RG ($PersistentRgName)..."
    $persExists = az group exists --name $PersistentRgName -o tsv
    if ($persExists -eq 'true') {
        Write-Log-OK "$PersistentRgName intact" -Detail "IP-uri statice păstrate"
        $pips = az network public-ip list -g $PersistentRgName -o json | ConvertFrom-Json
        foreach ($pip in $pips) {
            $ip = $pip.ipAddress
            Write-Log-Info "$($pip.name) : $ip"
        }
    }

    Write-Log-Info "Redeploy: .\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment $Environment"
    Write-Log-OK "Teardown $EnvLabel — FINALIZAT"
    Stop-LogSession
}
