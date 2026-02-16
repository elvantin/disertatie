# ============================================================
# SC MEDIA SRL — Infrastructure Test Suite
# Runs from local machine (Windows) to validate Azure deployment
# Tests: Azure resources, NSG rules, connectivity, idempotency
# Usage: .\scripts\test-infrastructure.ps1
# ============================================================

param(
    [switch]$SkipIdempotency  # Skip Bicep idempotency test (takes ~5 min)
)

$ErrorActionPreference = "Continue"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

# Counters
$script:passed = 0
$script:failed = 0
$script:warnings = 0
$script:results = @()

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
            Write-Host "  [PASS] $TestName" -ForegroundColor Green
            $script:passed++
            $script:results += @{ Category = $Category; Test = $TestName; Status = "PASS" }
        } else {
            Write-Host "  [FAIL] $TestName" -ForegroundColor Red
            $script:failed++
            $script:results += @{ Category = $Category; Test = $TestName; Status = "FAIL" }
        }
    } catch {
        Write-Host "  [FAIL] $TestName — $($_.Exception.Message)" -ForegroundColor Red
        $script:failed++
        $script:results += @{ Category = $Category; Test = $TestName; Status = "FAIL" }
    }
}

function Test-Warn {
    param([string]$Category, [string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
    $script:warnings++
    $script:results += @{ Category = $Category; Test = $Message; Status = "WARN" }
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " SC MEDIA SRL — Infrastructure Test Suite"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# ----- Verificare Azure CLI -----

Write-Host "[CHECK] Verificare Azure CLI..." -ForegroundColor Yellow
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Nu esti autentificat in Azure CLI. Ruleaza 'az login'." -ForegroundColor Red
    exit 1
}
$SubscriptionId = az account show --query id -o tsv
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor Gray
Write-Host ""

# ============================================================
# CATEGORIA 1: RESURSE AZURE (exista si sunt corect configurate?)
# ============================================================

$RgMain = "rg-mediasrl-productie-swedencentral"
$RgPacker = "rg-mediasrl-packer-swedencentral"
$RgPersistent = "rg-mediasrl-persistent"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " 1. TESTE RESURSE AZURE"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

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
    Test-Check "Azure Resources" "Image Definition '$imgDef' has versions" {
        $versions = az sig image-version list -g $RgPacker --gallery-name gal_mediasrl --gallery-image-definition $imgDef --query "length(@)" -o tsv 2>$null
        $LASTEXITCODE -eq 0 -and [int]$versions -gt 0
    }
}

Write-Host ""

# ============================================================
# CATEGORIA 2: VIRTUAL MACHINES (exista, pornite, cu IP-uri corecte?)
# ============================================================

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " 2. TESTE VIRTUAL MACHINES"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$ExpectedVMs = @("vm-jmp-01", "vm-web-01", "vm-app-01", "vm-cms-01", "vm-db-01", "vm-fs-01")

foreach ($vmName in $ExpectedVMs) {
    Test-Check "Virtual Machines" "VM '$vmName' exists and is running" {
        $powerState = az vm get-instance-view -g $RgMain -n $vmName --query "instanceView.statuses[?starts_with(code,'PowerState/')].displayStatus" -o tsv 2>$null
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

Write-Host ""

# ============================================================
# CATEGORIA 3: SECURITATE (NSG rules, policies, tags)
# ============================================================

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " 3. TESTE SECURITATE"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# NSG nsg-mgmt: RDP si SSH doar de la admin IP
Test-Check "Security" "NSG-mgmt: RDP allowed only from admin IP" {
    $rule = az network nsg rule show -g $RgMain --nsg-name nsg-mgmt -n AllowRDP --query "sourceAddressPrefix" -o tsv 2>$null
    $LASTEXITCODE -eq 0 -and $rule -ne "*"
}

Test-Check "Security" "NSG-mgmt: SSH allowed only from admin IP" {
    $rule = az network nsg rule show -g $RgMain --nsg-name nsg-mgmt -n AllowSSH --query "sourceAddressPrefix" -o tsv 2>$null
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

# Azure Policy assignments
Test-Check "Security" "Azure Policy assignments exist on subscription" {
    $count = az policy assignment list --query "length(@)" -o tsv 2>$null
    $LASTEXITCODE -eq 0 -and [int]$count -gt 0
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

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " 4. TESTE CONECTIVITATE"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

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
    Test-Check "Connectivity" "Webserver HTTP port (80) reachable" {
        $tcp = New-Object System.Net.Sockets.TcpClient
        try {
            $tcp.Connect($WebIp, 80)
            $result = $tcp.Connected
            $tcp.Close()
            $result
        } catch {
            $false
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

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " 5. TESTE IDEMPOTENTA"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

if ($SkipIdempotency) {
    Write-Host "  [SKIP] Idempotency tests skipped (-SkipIdempotency)" -ForegroundColor Yellow
} else {
    Test-Check "Idempotency" "Bicep what-if shows no changes (NoChange/Ignore only)" {
        Write-Host "    Running what-if (this may take 1-2 minutes)..." -ForegroundColor Gray
        $whatif = az deployment sub what-if --location swedencentral --template-file "$ProjectRoot\bicep\main.bicep" --parameters "$ProjectRoot\bicep\parameters\prod.bicepparam" --no-pretty-print --query "changes[?changeType!='NoChange' && changeType!='Ignore'].{Name:resourceId, Change:changeType}" -o json 2>$null
        $changes = $whatif | ConvertFrom-Json
        if ($null -eq $changes -or $changes.Count -eq 0) {
            $true
        } else {
            Write-Host "    Unexpected changes detected:" -ForegroundColor Yellow
            foreach ($c in $changes) {
                Write-Host "      $($c.Change): $($c.Name)" -ForegroundColor Yellow
            }
            $false
        }
    }
}

Write-Host ""

# ============================================================
# CATEGORIA 6: PERFORMANTA (response time)
# ============================================================

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " 6. TESTE PERFORMANTA"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

if ($WebIp) {
    Test-Check "Performance" "Webserver responds within 5 seconds" {
        try {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $response = Invoke-WebRequest -Uri "http://$WebIp" -TimeoutSec 5 -UseBasicParsing -ErrorAction SilentlyContinue
            $stopwatch.Stop()
            $ms = $stopwatch.ElapsedMilliseconds
            Write-Host "    Response time: ${ms}ms (HTTP $($response.StatusCode))" -ForegroundColor Gray
            $ms -lt 5000
        } catch {
            Write-Host "    Webserver did not respond (may not be configured yet by Ansible)" -ForegroundColor Yellow
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
            Write-Host "    SSH connect time: ${ms}ms" -ForegroundColor Gray
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

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host " REZUMAT TESTE"
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Passed:   $($script:passed)" -ForegroundColor Green
Write-Host "  Failed:   $($script:failed)" -ForegroundColor $(if ($script:failed -gt 0) { "Red" } else { "Green" })
Write-Host "  Warnings: $($script:warnings)" -ForegroundColor $(if ($script:warnings -gt 0) { "Yellow" } else { "Green" })
Write-Host "  Total:    $($script:passed + $script:failed + $script:warnings)" -ForegroundColor White
Write-Host ""

# Detailed results table
Write-Host "  Detalii per categorie:" -ForegroundColor White
$categories = $script:results | Group-Object -Property Category
foreach ($cat in $categories) {
    $catPassed = @($cat.Group | Where-Object { $_.Status -eq "PASS" }).Count
    $catTotal = $cat.Group.Count
    $color = if ($catPassed -eq $catTotal) { "Green" } else { "Yellow" }
    Write-Host "    $($cat.Name): $catPassed/$catTotal" -ForegroundColor $color
}

Write-Host ""
if ($script:failed -eq 0) {
    Write-Host "  [OK] Toate testele au trecut cu succes!" -ForegroundColor Green
} else {
    Write-Host "  [WARN] $($script:failed) test(e) au esuat. Verifica detaliile de mai sus." -ForegroundColor Red
}
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
