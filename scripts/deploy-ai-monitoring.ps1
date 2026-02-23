# ============================================================
# Deploy AI Monitoring Stack — SC MEDIA SRL
# Bicep: Azure OpenAI + Azure Function + Application Insights
# ============================================================
# Utilizare:
#   .\scripts\deploy-ai-monitoring.ps1
#   .\scripts\deploy-ai-monitoring.ps1 -ValidateOnly
# ============================================================

param(
    [switch]$ValidateOnly,
    [switch]$NoConfirm
)

$ErrorActionPreference = "Stop"
$PARAMS_FILE = "bicep/parameters/ai-monitoring.bicepparam"
$TEMPLATE    = "bicep/ai-monitoring.bicep"
$LOCATION    = "swedencentral"

Write-Host ""
Write-Host "============================================================"
Write-Host " AI Monitoring Stack — SC MEDIA SRL"
Write-Host " Azure OpenAI (GPT-4o) + Azure Functions + App Insights"
Write-Host "============================================================"
Write-Host ""

# --- Verifica az login ---
$account = az account show 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "[!] Nu esti autentificat. Rulam az login..." -ForegroundColor Yellow
    az login
    $account = az account show | ConvertFrom-Json
}
Write-Host "[OK] Subscriptie: $($account.name) ($($account.id))" -ForegroundColor Green

# --- Verifica workspace ID ---
Write-Host ""
Write-Host "[i] Verificam Log Analytics Workspace..." -ForegroundColor Cyan
$ws = az monitor log-analytics workspace show `
    --resource-group rg-mediasrl-productie-swedencentral `
    --workspace-name log-mediasrl-productie `
    --query "{id:id, customerId:properties.customerId}" `
    -o json 2>$null | ConvertFrom-Json

if (-not $ws) {
    Write-Host "[!] ATENTIE: Nu s-a gasit log-mediasrl-productie." -ForegroundColor Red
    Write-Host "    Asigurati-va ca infrastructura de productie este deployata primul."
    exit 1
}

Write-Host "[OK] Workspace ID   : $($ws.id)" -ForegroundColor Green
Write-Host "[OK] Customer ID    : $($ws.customerId)" -ForegroundColor Green

# Actualizeaza automat customer ID in params daca lipseste
$paramsContent = Get-Content $PARAMS_FILE -Raw
if ($paramsContent -match "logAnalyticsWorkspaceCustomerId = ''") {
    Write-Host ""
    Write-Host "[i] Actualizez automat logAnalyticsWorkspaceCustomerId in params..." -ForegroundColor Cyan
    $paramsContent = $paramsContent -replace "logAnalyticsWorkspaceCustomerId = ''", "logAnalyticsWorkspaceCustomerId = '$($ws.customerId)'"
    Set-Content $PARAMS_FILE $paramsContent -Encoding UTF8
    Write-Host "[OK] Parametru actualizat." -ForegroundColor Green
}

# --- Sumar resurse ---
Write-Host ""
Write-Host "Resurse ce vor fi create:" -ForegroundColor Cyan
Write-Host "  Resource Group : rg-mediasrl-aimonitoring-swedencentral"
Write-Host "  Azure OpenAI   : aoai-mediasrl-productie (GPT-4o, 10K TPM)"
Write-Host "  Function App   : func-mediasrl-logmonitor (Python 3.11, timer 15min)"
Write-Host "  App Insights   : appi-mediasrl-logmonitor (workspace-based)"
Write-Host "  Storage Acc.   : stmediasrlmonitor"
Write-Host "  Role assignments: Managed Identity -> Log Analytics Reader + AOAI User"
Write-Host ""

if ($ValidateOnly) {
    Write-Host "[i] Mod VALIDATE — nu se face deploy efectiv." -ForegroundColor Yellow
    az deployment sub validate `
        --location $LOCATION `
        --template-file $TEMPLATE `
        --parameters $PARAMS_FILE
    Write-Host "[OK] Validare completa." -ForegroundColor Green
    exit 0
}

if (-not $NoConfirm) {
    $confirm = Read-Host "Continui cu deploy-ul? (da/nu)"
    if ($confirm -ne "da") { Write-Host "Anulat."; exit 0 }
}

# --- What-if ---
Write-Host ""
Write-Host "[i] Rulam what-if pentru previzualizare modificari..." -ForegroundColor Cyan
az deployment sub what-if `
    --location $LOCATION `
    --template-file $TEMPLATE `
    --parameters $PARAMS_FILE

if (-not $NoConfirm) {
    $confirm2 = Read-Host "Aplici modificarile? (da/nu)"
    if ($confirm2 -ne "da") { Write-Host "Anulat."; exit 0 }
}

# --- Deploy ---
Write-Host ""
Write-Host "[i] Incepem deploy-ul..." -ForegroundColor Cyan
$deployName = "aiMonitoring-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

az deployment sub create `
    --name $deployName `
    --location $LOCATION `
    --template-file $TEMPLATE `
    --parameters $PARAMS_FILE `
    --output json | Tee-Object -Variable deployOutput

$result = $deployOutput | ConvertFrom-Json
if ($result.properties.provisioningState -ne "Succeeded") {
    Write-Host "[EROARE] Deploy esuat!" -ForegroundColor Red
    exit 1
}

# --- Afiseaza output-uri ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " Deploy reusit!" -ForegroundColor Green
Write-Host "============================================================"
$outputs = $result.properties.outputs
Write-Host " Function App   : $($outputs.functionAppName.value)"
Write-Host " AOAI Endpoint  : $($outputs.aoaiEndpoint.value)"
Write-Host " Principal ID   : $($outputs.functionAppPrincipalId.value)"
Write-Host ""
Write-Host "Pasi urmatori:" -ForegroundColor Cyan
Write-Host "  1. Deploy codul functiei:"
Write-Host "     cd azure-functions/log-monitor"
Write-Host "     func azure functionapp publish func-mediasrl-logmonitor --python"
Write-Host ""
Write-Host "  2. Sau prin pipeline Azure DevOps:"
Write-Host "     git push origin master  (trigger automat)"
Write-Host ""
Write-Host "  3. Verifica loguri in Azure Portal:"
Write-Host "     Portal -> appi-mediasrl-logmonitor -> Logs ->"
Write-Host "     AppTraces | where Message startswith '[LogMonitor]' | order by TimeGenerated desc"
Write-Host ""
