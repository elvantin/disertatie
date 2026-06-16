# ============================================================
# SC MEDIA SRL — Infrastructure Test Suite
# Runs from local machine (Windows) to validate Azure deployment
# Tests: Azure resources, NSG rules, connectivity, idempotency
# Usage: .\scripts\4-test-infrastructure.ps1
# ============================================================

param(
    [switch]$SkipIdempotency  # Skip Bicep idempotency test (takes ~5 min)
)

$ErrorActionPreference = "Continue"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

$LogDir = Join-Path $ProjectRoot "logs"

. "$PSScriptRoot\lib\Write-Log.ps1"
Start-LogSession -ScriptTitle "Infrastructure Test Suite" -LogDirectory $LogDir

trap {
    Write-Log-Fail "Eroare neasteptata: $_" -Detail "Script oprit prematur"
    Stop-LogSession
    break
}

# Counters for test results (separate from Write-Log counters)
$script:passed  = 0
$script:failed  = 0
$script:warnings = 0
$script:results  = @()

# ----- Helper Functions -----

function Test-Check {
    param(
        [string]$Category,
        [string]$TestName,
        [scriptblock]$Test
    )

    try {
        $result = & $Test
        if ($result) {
            Write-Log-OK $TestName -Detail $Category
            $script:passed++
            $script:results += @{ Category = $Category; Test = $TestName; Status = "PASS" }
        } else {
            Write-Log-Fail $TestName -Detail $Category
            $script:failed++
            $script:results += @{ Category = $Category; Test = $TestName; Status = "FAIL" }
        }
    } catch {
        Write-Log-Fail "$TestName — $($_.Exception.Message)" -Detail $Category
        $script:failed++
        $script:results += @{ Category = $Category; Test = $TestName; Status = "FAIL" }
    }
}

function Test-Warn {
    param([string]$Category, [string]$Message)
    Write-Log-Warn $Message -Detail $Category
    $script:warnings++
    $script:results += @{ Category = $Category; Test = $Message; Status = "WARN" }
}

Write-Log-Header "Verificare Azure CLI"
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log-Fail "Nu ești autentificat în Azure CLI" -Detail "Rulează: az login"
    Stop-LogSession; exit 1
}
$SubscriptionId = az account show --query id -o tsv
Write-Log-OK "Azure CLI autentificat" -Detail $SubscriptionId

# ============================================================
# CATEGORIA 1: RESURSE AZURE (exista si sunt corect configurate?)
# ============================================================

$RgMain = "rg-mediasrl-productie-swedencentral"
$RgPacker = "rg-mediasrl-packer-swedencentral"
$RgPersistent = "rg-mediasrl-persistent"

Write-Log-Header "1. Teste Resurse Azure" -Step 1 -Total 6

# Resource Groups
Test-Check "Azure Resources" "Resource Group '$RgMain' exists" {
    $result = az group exists --name $RgMain -o tsv
    $result -eq "true"
}

Test-Check "Azure Resources" "Resource Group '$RgPacker' exists" {
    $result = az group exists --name $RgPacker -o tsv
    $result -eq "true"
}

Test-Check "Azure Resources" "Resource Group '$RgPersistent' exists" {
    $result = az group exists --name $RgPersistent -o tsv
    $result -eq "true"
}

# VNet
Test-Check "Azure Resources" "VNet 'vnet-mediasrl-productie' exists" {
    az network vnet show -g $RgMain -n vnet-mediasrl-productie --query name -o tsv 2>$null
    $LASTEXITCODE -eq 0
}

# Subnets
foreach ($subnet in @("snet-prod", "snet-dev", "snet-mgmt")) {
    Test-Check "Azure Resources" "Subnet '$subnet' exists" {
        az network vnet subnet show -g $RgMain --vnet-name vnet-mediasrl-productie -n $subnet --query name -o tsv 2>$null
        $LASTEXITCODE -eq 0
    }
}

# NSGs
foreach ($nsg in @("nsg-prod", "nsg-dev", "nsg-mgmt")) {
    Test-Check "Azure Resources" "NSG '$nsg' exists" {
        az network nsg show -g $RgMain -n $nsg --query name -o tsv 2>$null
        $LASTEXITCODE -eq 0
    }
}

# Key Vault
Test-Check "Azure Resources" "Key Vault exists with soft-delete enabled" {
    $kv = az keyvault show -g $RgMain -n kv-mediasrl-productie --query "properties.enableSoftDelete" -o tsv 2>$null
    $LASTEXITCODE -eq 0 -and $kv -eq "true"
}

# Log Analytics
Test-Check "Azure Resources" "Log Analytics Workspace exists" {
    az monitor log-analytics workspace show -g $RgMain -n log-mediasrl-productie --query name -o tsv 2>$null
    $LASTEXITCODE -eq 0
}

# Compute Gallery
Test-Check "Azure Resources" "Compute Gallery 'gal_mediasrl' exists" {
    az sig show -g $RgPacker --gallery-name gal_mediasrl --query name -o tsv 2>$null
    $LASTEXITCODE -eq 0
}

# Image Definitions
foreach ($imgDef in @("imgdef-ubuntu2204", "imgdef-ubuntu2204-jumphost", "imgdef-winserver2022")) {
    $imgDefCopy = $imgDef  # capture by value to avoid foreach closure issues
    Test-Check "Azure Resources" "Image Definition '$imgDef' has versions" {
        $versionList = az sig image-version list -g $RgPacker --gallery-name gal_mediasrl --gallery-image-definition $imgDefCopy -o json 2>$null | ConvertFrom-Json
        $LASTEXITCODE -eq 0 -and $null -ne $versionList -and $versionList.Count -gt 0
    }
}

Write-Host ""

# ============================================================
# CATEGORIA 2: VIRTUAL MACHINES (exista, pornite, cu IP-uri corecte?)
# ============================================================

Write-Log-Header "2. Teste Virtual Machines" -Step 2 -Total 6

$ExpectedVMs = @("vm-jmp-01", "vm-web-01", "vm-app-01", "vm-cms-01", "vm-db-01", "vm-fs-01")

foreach ($vmName in $ExpectedVMs) {
    $vmNameCopy = $vmName  # capture by value to avoid foreach closure issues
    Test-Check "Virtual Machines" "VM '$vmNameCopy' exists and is running" {
        $powerState = az vm show -g $RgMain -n $vmNameCopy -d --query powerState -o tsv 2>$null
        $LASTEXITCODE -eq 0 -and $powerState -eq "VM running"
    }
}

# Persistent Public IPs
Test-Check "Virtual Machines" "Jumphost has persistent public IP" {
    $ip = az network public-ip show -g $RgPersistent -n pip-vm-jmp-01 --query ipAddress -o tsv 2>$null
    $LASTEXITCODE -eq 0 -and $ip -match '^\d+\.\d+\.\d+\.\d+$'
}

Test-Check "Virtual Machines" "Webserver has persistent public IP" {
    $ip = az network public-ip show -g $RgPersistent -n pip-vm-web-01 --query ipAddress -o tsv 2>$null
    $LASTEXITCODE -eq 0 -and $ip -match '^\d+\.\d+\.\d+\.\d+$'
}

$vmDetailLines = [System.Collections.Generic.List[string]]::new()
az vm list -g $RgMain -d -o table `
    --query "[].{VM:name, State:powerState, OS:storageProfile.osDisk.osType, PrivateIP:privateIps}" 2>$null | ForEach-Object { [void]$vmDetailLines.Add([string]$_) }
if ($vmDetailLines.Count -gt 0) {
    Write-Log-Block -Label "Stare VM-uri — $RgMain" -Content ($vmDetailLines -join "`n")
}

Write-Host ""

# ============================================================
# CATEGORIA 3: SECURITATE (NSG rules, policies, tags)
# ============================================================

Write-Log-Header "3. Teste Securitate" -Step 3 -Total 6

# NSG nsg-mgmt: RDP si SSH doar de la admin IP
Test-Check "Security" "NSG-mgmt: RDP allowed only from admin IP" {
    $rule = az network nsg rule show -g $RgMain --nsg-name nsg-mgmt -n Allow-RDP-From-Admin --query "sourceAddressPrefix" -o tsv 2>$null
    $LASTEXITCODE -eq 0 -and $rule -ne "*"
}

Test-Check "Security" "NSG-mgmt: SSH allowed only from admin IP" {
    $rule = az network nsg rule show -g $RgMain --nsg-name nsg-mgmt -n Allow-SSH-From-Admin --query "sourceAddressPrefix" -o tsv 2>$null
    $LASTEXITCODE -eq 0 -and $rule -ne "*"
}

# NSG nsg-prod: Deny all inbound (default deny exists)
Test-Check "Security" "NSG-prod: Default deny all inbound exists" {
    $rules = az network nsg rule list -g $RgMain --nsg-name nsg-prod --query "[?access=='Deny' && direction=='Inbound'].name" -o tsv 2>$null
    $LASTEXITCODE -eq 0 -and $rules
}

# NSG nsg-prod: HTTP/HTTPS allowed
Test-Check "Security" "NSG-prod: HTTPS (443) allowed for webserver" {
    $rules = az network nsg rule list -g $RgMain --nsg-name nsg-prod --query "[?destinationPortRange=='443' || contains(destinationPortRanges,'443')].name" -o tsv 2>$null
    $LASTEXITCODE -eq 0 -and $rules
}

# Key Vault purge protection
Test-Check "Security" "Key Vault has purge protection enabled" {
    $purge = az keyvault show -g $RgMain -n kv-mediasrl-productie --query "properties.enablePurgeProtection" -o tsv 2>$null
    $LASTEXITCODE -eq 0 -and $purge -eq "true"
}

# Azure Policy assignments — check for a specific known assignment deployed by policy.bicep
Test-Check "Security" "Azure Policy assignments exist on subscription" {
    az policy assignment show --name "policy-allowed-locations" --scope "/subscriptions/$SubscriptionId" 2>$null | Out-Null
    $LASTEXITCODE -eq 0
}

# Tags on main resource group
Test-Check "Security" "Resource Group has required tags (environment, project)" {
    $tags = az group show -n $RgMain --query "tags" -o json 2>$null | ConvertFrom-Json
    $tags.environment -and $tags.project
}

Write-Host ""

# ============================================================
# CATEGORIA 4: CONECTIVITATE (pot ajunge la VM-uri?)
# ============================================================

Write-Log-Header "4. Teste Conectivitate" -Step 4 -Total 6

# Jumphost SSH reachability (port 22)
$JumphostIp = az network public-ip show -g $RgPersistent -n pip-vm-jmp-01 --query ipAddress -o tsv 2>$null

if ($JumphostIp) {
    Test-Check "Connectivity" "Jumphost SSH port (22) reachable from admin IP" {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.Connect($JumphostIp, 22)
            $result = $tcp.Connected
            $tcp.Close()
            $result
        } catch {
            $false
        }
    }

    Test-Check "Connectivity" "Jumphost RDP port (3389) reachable from admin IP" {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.Connect($JumphostIp, 3389)
            $result = $tcp.Connected
            $tcp.Close()
            $result
        } catch {
            $false
        }
    }
} else {
    Test-Warn "Connectivity" "Cannot determine jumphost IP — skipping connectivity tests"
}

# Webserver HTTP/HTTPS reachability
$WebIp = az network public-ip show -g $RgPersistent -n pip-vm-web-01 --query ipAddress -o tsv 2>$null

if ($WebIp) {
    Test-Check "Connectivity" "Webserver HTTP port (80) blocked from internet (VNet-only)" {
        # Port 80 is restricted to VNet CIDR (10.10.0.0/20) by NSG — must NOT be reachable from outside
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.ConnectAsync($WebIp, 80).Wait(2000) | Out-Null
            $connected = $tcp.Connected
            $tcp.Close()
            -not $connected  # PASS if connection was refused/timed out
        } catch {
            $true  # connection failed = port is blocked = correct behaviour
        }
    }

    Test-Check "Connectivity" "Webserver HTTPS port (443) reachable" {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.Connect($WebIp, 443)
            $result = $tcp.Connected
            $tcp.Close()
            $result
        } catch {
            $false
        }
    }
} else {
    Test-Warn "Connectivity" "Cannot determine webserver IP — skipping connectivity tests"
}

Write-Host ""

# ============================================================
# CATEGORIA 5: IDEMPOTENTA (re-deploy nu schimba nimic)
# ============================================================

Write-Log-Header "5. Teste Idempotență" -Step 5 -Total 6

if ($SkipIdempotency) {
    Write-Host "  [SKIP] Idempotency tests skipped (-SkipIdempotency)" -ForegroundColor Yellow
} else {
    Test-Check "Idempotency" "Bicep what-if shows no Create/Delete changes" {
        Write-Log-Info "Rulare what-if (poate dura 1-2 minute)..."
        # Only flag Create/Delete as unexpected — Modify is a known ARM what-if false positive
        # (policy assignments, NICs, public IPs always show Modify due to internal ARM properties)
        $whatif = az deployment sub what-if --location swedencentral --template-file "$ProjectRoot\bicep\main.bicep" --parameters "$ProjectRoot\bicep\parameters\prod.bicepparam" --no-pretty-print --query "changes[?changeType=='Create' || changeType=='Delete'].{Name:resourceId, Change:changeType}" -o json 2>$null
        $changes = $whatif | ConvertFrom-Json
        $modifyOnly = az deployment sub what-if --location swedencentral --template-file "$ProjectRoot\bicep\main.bicep" --parameters "$ProjectRoot\bicep\parameters\prod.bicepparam" --no-pretty-print --query "changes[?changeType=='Modify'].resourceId" -o json 2>$null | ConvertFrom-Json
        if ($null -ne $modifyOnly -and $modifyOnly.Count -gt 0) {
            Write-Log-Info "Modify-only changes (ARM false positives, not blocking): $($modifyOnly.Count)"
            foreach ($r in $modifyOnly) { Write-Log-Info "  Modify: $r" }
        }
        if ($null -eq $changes -or $changes.Count -eq 0) {
            $true
        } else {
            Write-Log-Warn "Unexpected Create/Delete changes detected:"
            foreach ($c in $changes) {
                Write-Log-Warn "  $($c.Change): $($c.Name)"
            }
            $false
        }
    }
}

Write-Host ""

# ============================================================
# CATEGORIA 6: PERFORMANTA (response time)
# ============================================================

Write-Log-Header "6. Teste Performanță" -Step 6 -Total 6

if ($WebIp) {
    Test-Check "Performance" "Webserver HTTPS responds within 5 seconds" {
        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            # Use HTTPS — port 80 is VNet-only, port 443 is public; skip cert validation (self-signed accepted)
            $response = Invoke-WebRequest -Uri "https://$WebIp" -TimeoutSec 5 -UseBasicParsing -SkipCertificateCheck -ErrorAction SilentlyContinue
            $stopwatch.Stop()
            $ms = $stopwatch.ElapsedMilliseconds
            Write-Log-Info "Response time: ${ms}ms (HTTPS $($response.StatusCode))"
            $ms -lt 5000
        } catch {
            Write-Log-Warn "Webserver did not respond (may not be configured yet by Ansible)"
            $false
        }
    }
} else {
    Test-Warn "Performance" "No webserver IP — skipping performance tests"
}

if ($JumphostIp) {
    Test-Check "Performance" "SSH to jumphost responds within 3 seconds" {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.Connect($JumphostIp, 22)
            $stopwatch.Stop()
            $ms = $stopwatch.ElapsedMilliseconds
            $tcp.Close()
            Write-Log-Info "SSH connect time: ${ms}ms"
            $ms -lt 3000
        } catch {
            $stopwatch.Stop()
            $false
        }
    }
}

Write-Host ""

# ============================================================
# REZUMAT
# ============================================================

Write-Log-Header "Rezumat Teste"

$total = $script:passed + $script:failed + $script:warnings
Write-Log-Info "Total  : $total   PASS: $($script:passed)   FAIL: $($script:failed)   WARN: $($script:warnings)"

$categories = $script:results | Group-Object -Property Category
foreach ($cat in $categories) {
    $catPassed = @($cat.Group | Where-Object { $_.Status -eq "PASS" }).Count
    $catTotal  = $cat.Group.Count
    if ($catPassed -eq $catTotal) {
        Write-Log-OK "$($cat.Name)" -Detail "$catPassed/$catTotal teste trecute"
    } else {
        Write-Log-Warn "$($cat.Name)" -Detail "$catPassed/$catTotal teste trecute"
    }
}

if ($script:failed -eq 0) {
    Write-Log-OK "Toate testele au trecut cu succes" -Detail "$($script:passed) PASS · $($script:warnings) WARN"
} else {
    Write-Log-Fail "$($script:failed) test(e) au eșuat" -Detail "Verifică detaliile din log"
}

# ============================================================
# PAȘI URMĂTORI
# ============================================================

Write-Log-Header "Pași următori"

if (-not $JumphostIp) {
    $JumphostIp = az network public-ip show -g $RgPersistent -n pip-vm-jmp-01 --query ipAddress -o tsv 2>$null
}

if ($script:failed -eq 0) {
    Write-Log-OK "Infrastructura Azure validata — VM-urile sunt accesibile"
    Write-Log-Info "Daca Ansible nu a fost inca configurat pe jumphost:"
    if ($JumphostIp) {
        Write-Log-Info "  .\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment prod -JumphostIP $JumphostIp"
    } else {
        Write-Log-Info "  .\scripts\3-deploy-ansible-to-jumphost.ps1 -Environment prod -JumphostIP <IP>"
    }
    Write-Log-Info "Daca Ansible este deja configurat — conecteaza-te la jumphost:"
    Write-Log-Info "  ssh azureadmin@$(if ($JumphostIp) { $JumphostIp } else { '<IP_JUMPHOST>' })"
    Write-Log-Info "  cd ~/ansible"
    Write-Log-Info "  ./run-playbook.sh 1-base-setup.yml"
    Write-Log-Info "  ./run-playbook.sh 2-deploy-wordpress.yml"
    Write-Log-Info "  ./run-playbook.sh 3-wordpress-config.yml"
    Write-Log-Info "  ./run-playbook.sh 4-harden-nginx-ssl_ssllabs.com_ssltest.yml"
    Write-Log-Info "  bash scripts/certbot-letsencrypt.sh --env prod"
    Write-Log-Info "  ./run-playbook.sh 'harden-security(daca_nu_rulez_demouri).yml'"
    Write-Log-Info "  ./run-playbook.sh 6-monitoring.yml"
} else {
    Write-Log-Warn "Rezolva testele esuate inainte de a rula Ansible"
    Write-Log-Info "Redeploy Bicep daca resurse lipsesc:"
    Write-Log-Info "  .\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod"
}

Stop-LogSession
