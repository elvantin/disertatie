# ============================================================
# SC MEDIA SRL — Build & Publish Packer Images
# Automatizare completa: Gallery + Image Definitions + Packer Build
# Rulare: .\scripts\build-packer-images.ps1 [-SkipGallery] [-Only <ubuntu-base|jumphost|windows>]
# ============================================================

param(
    [switch]$SkipGallery,
    [ValidateSet("ubuntu-base", "jumphost", "windows", "all")]
    [string]$Only = "all",
    [string]$ImageVersion = "1.0.0"
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " SC MEDIA SRL — Packer Image Builder"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# ----- Variabile -----
$Location       = "swedencentral"
$GalleryName    = "gal_mediasrl"

# ----- Verificari preliminare -----

Write-Host "[CHECK] Verificare Azure CLI..." -ForegroundColor Yellow
$azAccount = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Nu esti autentificat in Azure CLI. Ruleaza 'az login' mai intai." -ForegroundColor Red
    exit 1
}
$SubscriptionId = (az account show --query id -o tsv)
$ResourceGroup  = "rg-mediasrl-productie-$Location"
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor Gray
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor Gray
Write-Host ""

Write-Host "[CHECK] Verificare Packer..." -ForegroundColor Yellow
$packerVersion = packer --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Packer nu este instalat. Ruleaza 'winget install HashiCorp.Packer'." -ForegroundColor Red
    exit 1
}
Write-Host "  Packer version: $packerVersion" -ForegroundColor Gray
Write-Host ""

# ----- Verificare existenta Resource Group -----

Write-Host "[CHECK] Verificare Resource Group '$ResourceGroup'..." -ForegroundColor Yellow
$rgExists = az group exists --name $ResourceGroup -o tsv
if ($rgExists -ne "true") {
    Write-Host "[FAIL] Resource Group '$ResourceGroup' nu exista." -ForegroundColor Red
    Write-Host "  Ruleaza mai intai deploymentul Bicep pentru a crea infrastructura." -ForegroundColor Red
    exit 1
}
Write-Host "  [OK] Resource Group exista" -ForegroundColor Green
Write-Host ""

# ============================================================
# PASUL 1: Creare Azure Compute Gallery + Image Definitions
# ============================================================

if (-not $SkipGallery) {
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host " PASUL 1: Azure Compute Gallery Setup"
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""

    # Creare Gallery
    Write-Host "[1/4] Creare Azure Compute Gallery '$GalleryName'..." -ForegroundColor Yellow
    $galleryExists = az sig show --resource-group $ResourceGroup --gallery-name $GalleryName 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Gallery exista deja, se continua" -ForegroundColor Green
    }
    else {
        az sig create `
            --resource-group $ResourceGroup `
            --gallery-name $GalleryName `
            --location $Location
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] Eroare la crearea gallery" -ForegroundColor Red
            exit 1
        }
        Write-Host "  [OK] Gallery creat" -ForegroundColor Green
    }

    # Image Definition — Ubuntu Base
    Write-Host "[2/4] Creare Image Definition 'imgdef-ubuntu2204'..." -ForegroundColor Yellow
    $imgdefExists = az sig image-definition show --resource-group $ResourceGroup --gallery-name $GalleryName --gallery-image-definition imgdef-ubuntu2204 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Image Definition exista deja" -ForegroundColor Green
    }
    else {
        az sig image-definition create `
            --resource-group $ResourceGroup `
            --gallery-name $GalleryName `
            --gallery-image-definition imgdef-ubuntu2204 `
            --publisher "SCMediaSRL" `
            --offer "Ubuntu" `
            --sku "22.04-LTS-Base" `
            --os-type Linux `
            --os-state Generalized `
            --hyper-v-generation V2 `
            --location $Location
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] Eroare la crearea image definition" -ForegroundColor Red
            exit 1
        }
        Write-Host "  [OK] Image Definition creat" -ForegroundColor Green
    }

    # Image Definition — Ubuntu Jumphost
    Write-Host "[3/4] Creare Image Definition 'imgdef-ubuntu2204-jumphost'..." -ForegroundColor Yellow
    $imgdefExists = az sig image-definition show --resource-group $ResourceGroup --gallery-name $GalleryName --gallery-image-definition imgdef-ubuntu2204-jumphost 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Image Definition exista deja" -ForegroundColor Green
    }
    else {
        az sig image-definition create `
            --resource-group $ResourceGroup `
            --gallery-name $GalleryName `
            --gallery-image-definition imgdef-ubuntu2204-jumphost `
            --publisher "SCMediaSRL" `
            --offer "Ubuntu" `
            --sku "22.04-LTS-Jumphost" `
            --os-type Linux `
            --os-state Generalized `
            --hyper-v-generation V2 `
            --location $Location
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] Eroare la crearea image definition" -ForegroundColor Red
            exit 1
        }
        Write-Host "  [OK] Image Definition creat" -ForegroundColor Green
    }

    # Image Definition — Windows Server 2022
    Write-Host "[4/4] Creare Image Definition 'imgdef-winserver2022'..." -ForegroundColor Yellow
    $imgdefExists = az sig image-definition show --resource-group $ResourceGroup --gallery-name $GalleryName --gallery-image-definition imgdef-winserver2022 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Image Definition exista deja" -ForegroundColor Green
    }
    else {
        az sig image-definition create `
            --resource-group $ResourceGroup `
            --gallery-name $GalleryName `
            --gallery-image-definition imgdef-winserver2022 `
            --publisher "SCMediaSRL" `
            --offer "WindowsServer" `
            --sku "2022-Datacenter" `
            --os-type Windows `
            --os-state Generalized `
            --hyper-v-generation V2 `
            --location $Location
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] Eroare la crearea image definition" -ForegroundColor Red
            exit 1
        }
        Write-Host "  [OK] Image Definition creat" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "[OK] Gallery si Image Definitions sunt pregatite!" -ForegroundColor Green
    Write-Host ""
}

# ============================================================
# PASUL 2: Build Packer Images
# ============================================================

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " PASUL 2: Build Packer Images"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$buildResults = @{}

function Build-PackerImage {
    param(
        [string]$Name,
        [string]$PackerDir,
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ImageVersion
    )

    Write-Host "--- Building: $Name ---" -ForegroundColor Cyan
    Write-Host "  Directory: $PackerDir" -ForegroundColor Gray
    Write-Host "  Image Version: $ImageVersion" -ForegroundColor Gray
    Write-Host ""

    Push-Location $PackerDir

    try {
        # Packer Init
        Write-Host "  [INIT] packer init..." -ForegroundColor Yellow
        packer init .
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] packer init a esuat" -ForegroundColor Red
            $buildResults[$Name] = "FAILED (init)"
            return
        }

        # Packer Validate
        Write-Host "  [VALIDATE] packer validate..." -ForegroundColor Yellow
        packer validate `
            -var "subscription_id=$SubscriptionId" `
            -var "gallery_resource_group=$ResourceGroup" `
            -var "image_version=$ImageVersion" `
            .
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] packer validate a esuat" -ForegroundColor Red
            $buildResults[$Name] = "FAILED (validate)"
            return
        }

        # Packer Build
        Write-Host "  [BUILD] packer build (aceasta poate dura 10-30 minute)..." -ForegroundColor Yellow
        packer build `
            -var "subscription_id=$SubscriptionId" `
            -var "gallery_resource_group=$ResourceGroup" `
            -var "image_version=$ImageVersion" `
            .
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] packer build a esuat" -ForegroundColor Red
            $buildResults[$Name] = "FAILED (build)"
            return
        }

        Write-Host "  [OK] $Name — build complet!" -ForegroundColor Green
        $buildResults[$Name] = "SUCCESS"
    }
    finally {
        Pop-Location
    }
    Write-Host ""
}

# --- Ubuntu Base ---
if ($Only -eq "all" -or $Only -eq "ubuntu-base") {
    Build-PackerImage `
        -Name "Ubuntu 22.04 Base" `
        -PackerDir "$ProjectRoot\packer\ubuntu-base" `
        -SubscriptionId $SubscriptionId `
        -ResourceGroup $ResourceGroup `
        -ImageVersion $ImageVersion
}

# --- Ubuntu Jumphost ---
if ($Only -eq "all" -or $Only -eq "jumphost") {
    Build-PackerImage `
        -Name "Ubuntu 22.04 Jumphost" `
        -PackerDir "$ProjectRoot\packer\ubuntu-jumphost" `
        -SubscriptionId $SubscriptionId `
        -ResourceGroup $ResourceGroup `
        -ImageVersion $ImageVersion
}

# --- Windows Server ---
if ($Only -eq "all" -or $Only -eq "windows") {
    Build-PackerImage `
        -Name "Windows Server 2022" `
        -PackerDir "$ProjectRoot\packer\windows-server" `
        -SubscriptionId $SubscriptionId `
        -ResourceGroup $ResourceGroup `
        -ImageVersion $ImageVersion
}

# ============================================================
# PASUL 3: Verificare
# ============================================================

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " PASUL 3: Verificare imagini publicate"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$definitions = @("imgdef-ubuntu2204", "imgdef-ubuntu2204-jumphost", "imgdef-winserver2022")
foreach ($def in $definitions) {
    Write-Host "  $def :" -ForegroundColor Yellow -NoNewline
    $versions = az sig image-version list `
        --resource-group $ResourceGroup `
        --gallery-name $GalleryName `
        --gallery-image-definition $def `
        --query "[].name" -o tsv 2>&1
    if ($LASTEXITCODE -eq 0 -and $versions) {
        Write-Host " v$versions" -ForegroundColor Green
    }
    else {
        Write-Host " (nicio versiune)" -ForegroundColor Gray
    }
}

# ============================================================
# REZUMAT
# ============================================================

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " REZUMAT BUILD"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

foreach ($entry in $buildResults.GetEnumerator()) {
    $color = if ($entry.Value -eq "SUCCESS") { "Green" } else { "Red" }
    Write-Host "  $($entry.Key): $($entry.Value)" -ForegroundColor $color
}

Write-Host ""
$failCount = ($buildResults.Values | Where-Object { $_ -ne "SUCCESS" }).Count
if ($failCount -eq 0 -and $buildResults.Count -gt 0) {
    Write-Host "[OK] Toate imaginile au fost construite si publicate cu succes!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Pasul urmator: Seteaza 'useMarketplaceImages = false' in prod.bicepparam" -ForegroundColor Yellow
    Write-Host "si re-deployeaza cu:" -ForegroundColor Yellow
    Write-Host "  az deployment sub create --location swedencentral --template-file bicep/main.bicep --parameters bicep/parameters/prod.bicepparam" -ForegroundColor White
}
elseif ($failCount -gt 0) {
    Write-Host "[WARN] $failCount imagine(i) au esuat. Verifica erorile de mai sus." -ForegroundColor Red
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
