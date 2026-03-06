# ============================================================
# SC MEDIA SRL - Build & Publish Packer Images
# Automatizare completa: Gallery + Image Definitions + Packer Build
# - Auto-increment versiune per imagine
# - Confirmare interactiva per imagine
# - Output salvat in fisier log
# Rulare: .\scripts\build-packer-images.ps1 [-SkipGallery] [-NoConfirm]
# ============================================================

param(
    [switch]$SkipGallery,
    [switch]$NoConfirm
)

$ErrorActionPreference = "Continue"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $ProjectRoot "logs"

# Creare director logs daca nu exista
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " SC MEDIA SRL - Packer Image Builder"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# ----- Variabile -----
$Location = "swedencentral"
$GalleryName = "gal_mediasrl"
$TagsList = @("environment=productie", "project=mediasrl", "managed-by=packer")

# Definitiile imaginilor: Name, PackerDir, ImageDefinition
$ImageConfigs = @(
    @{
        Name = "Ubuntu 22.04 Base"
        Key = "ubuntu-base"
        PackerDir = Join-Path $ProjectRoot "packer\ubuntu-base"
        ImgDef = "imgdef-ubuntu2204"
    },
    @{
        Name = "Ubuntu 22.04 Jumphost"
        Key = "jumphost"
        PackerDir = Join-Path $ProjectRoot "packer\ubuntu-jumphost"
        ImgDef = "imgdef-ubuntu2204-jumphost"
    },
    @{
        Name = "Windows Server 2022"
        Key = "windows"
        PackerDir = Join-Path $ProjectRoot "packer\windows-server"
        ImgDef = "imgdef-winserver2022"
    }
)

# ----- Verificari preliminare -----

Write-Host "[CHECK] Verificare Azure CLI..." -ForegroundColor Yellow
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Nu esti autentificat in Azure CLI. Ruleaza 'az login' mai intai." -ForegroundColor Red
    exit 1
}
$SubscriptionId = (az account show --query id -o tsv)
$ResourceGroup = "rg-mediasrl-packer-$Location"
Write-Host "  Subscription: $SubscriptionId" -ForegroundColor Gray
Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor Gray
Write-Host ""

Write-Host "[CHECK] Verificare Packer..." -ForegroundColor Yellow
$packerVersion = packer --version 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Packer nu este instalat. Ruleaza 'winget install HashiCorp.Packer'." -ForegroundColor Red
    exit 1
}
Write-Host "  Packer version: $packerVersion" -ForegroundColor Gray
Write-Host ""

# ----- Verificare/Creare Resource Group -----

Write-Host "[CHECK] Verificare Resource Group '$ResourceGroup'..." -ForegroundColor Yellow
$rgExists = az group exists --name $ResourceGroup -o tsv
if ($rgExists -ne "true") {
    Write-Host "  Resource Group nu exista, se creeaza..." -ForegroundColor Yellow
    az group create --name $ResourceGroup --location $Location --tags environment=productie project=mediasrl managed-by=packer
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [FAIL] Eroare la crearea Resource Group" -ForegroundColor Red
        exit 1
    }
    Write-Host "  [OK] Resource Group creat" -ForegroundColor Green
}
else {
    Write-Host "  [OK] Resource Group exista" -ForegroundColor Green
}
Write-Host ""

# ============================================================
# FUNCTII HELPER
# ============================================================

function Get-NextImageVersion {
    param([string]$ImgDef)

    $versions = az sig image-version list --resource-group $ResourceGroup --gallery-name $GalleryName --gallery-image-definition $ImgDef --query "[].name" -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $versions) {
        return "1.0.0"
    }

    # Gaseste cea mai mare versiune
    $latest = $versions -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_ } | Select-Object -Last 1

    if (-not $latest) {
        return "1.0.0"
    }

    # Incrementeaza patch version
    $parts = $latest -split '\.'
    $major = [int]$parts[0]
    $minor = [int]$parts[1]
    $patch = [int]$parts[2] + 1
    return "$major.$minor.$patch"
}

function New-ImageDefinition {
    param(
        [string]$DefName,
        [string]$Publisher,
        [string]$Offer,
        [string]$Sku,
        [string]$OsType
    )

    az sig image-definition show --resource-group $ResourceGroup --gallery-name $GalleryName --gallery-image-definition $DefName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Image Definition '$DefName' exista deja" -ForegroundColor Green
        return
    }

    az sig image-definition create --resource-group $ResourceGroup --gallery-name $GalleryName --gallery-image-definition $DefName --publisher $Publisher --offer $Offer --sku $Sku --os-type $OsType --os-state Generalized --hyper-v-generation V2 --location $Location --tags $TagsList
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [FAIL] Eroare la crearea image definition '$DefName'" -ForegroundColor Red
        exit 1
    }
    Write-Host "  [OK] Image Definition '$DefName' creat" -ForegroundColor Green
}

function Build-PackerImage {
    param(
        [string]$Name,
        [string]$PackerDir,
        [string]$SubId,
        [string]$RG,
        [string]$ImgVersion,
        [string]$LogFile
    )

    Write-Host "--- Building: $Name ---" -ForegroundColor Cyan
    Write-Host "  Directory: $PackerDir" -ForegroundColor Gray
    Write-Host "  Image Version: $ImgVersion" -ForegroundColor Gray
    Write-Host "  Log: $LogFile" -ForegroundColor Gray
    Write-Host ""

    # Header in log file
    "=" * 60 | Out-File -FilePath $LogFile -Encoding UTF8
    "Build: $Name" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    "Version: $ImgVersion" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    "=" * 60 | Out-File -FilePath $LogFile -Append -Encoding UTF8

    Push-Location $PackerDir

    try {
        # Packer Init
        Write-Host "  [INIT] packer init..." -ForegroundColor Yellow
        packer init . 2>&1 | Tee-Object -FilePath $LogFile -Append
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] packer init a esuat. Vezi log: $LogFile" -ForegroundColor Red
            $script:buildResults[$Name] = "FAILED (init)"
            return
        }

        # Packer Validate
        Write-Host "  [VALIDATE] packer validate..." -ForegroundColor Yellow
        packer validate -var "subscription_id=$SubId" -var "gallery_resource_group=$RG" -var "image_version=$ImgVersion" . 2>&1 | Tee-Object -FilePath $LogFile -Append
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] packer validate a esuat. Vezi log: $LogFile" -ForegroundColor Red
            $script:buildResults[$Name] = "FAILED (validate)"
            return
        }

        # Packer Build
        Write-Host "  [BUILD] packer build (aceasta poate dura 10-30 minute)..." -ForegroundColor Yellow
        packer build -var "subscription_id=$SubId" -var "gallery_resource_group=$RG" -var "image_version=$ImgVersion" -color=false . 2>&1 | Tee-Object -FilePath $LogFile -Append
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] packer build a esuat. Vezi log: $LogFile" -ForegroundColor Red
            $script:buildResults[$Name] = "FAILED (build)"
            return
        }

        Write-Host "  [OK] $Name - build complet!" -ForegroundColor Green
        $script:buildResults[$Name] = "SUCCESS"
    }
    finally {
        Pop-Location
    }
    Write-Host ""
}

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
    az sig show --resource-group $ResourceGroup --gallery-name $GalleryName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Gallery exista deja, se continua" -ForegroundColor Green
    }
    else {
        az sig create --resource-group $ResourceGroup --gallery-name $GalleryName --location $Location --tags $TagsList
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [FAIL] Eroare la crearea gallery" -ForegroundColor Red
            exit 1
        }
        Write-Host "  [OK] Gallery creat" -ForegroundColor Green
    }

    # Image Definitions
    Write-Host "[2/4] Creare Image Definition 'imgdef-ubuntu2204'..." -ForegroundColor Yellow
    New-ImageDefinition -DefName "imgdef-ubuntu2204" -Publisher "SCMediaSRL" -Offer "Ubuntu" -Sku "22.04-LTS-Base" -OsType "Linux"

    Write-Host "[3/4] Creare Image Definition 'imgdef-ubuntu2204-jumphost'..." -ForegroundColor Yellow
    New-ImageDefinition -DefName "imgdef-ubuntu2204-jumphost" -Publisher "SCMediaSRL" -Offer "Ubuntu" -Sku "22.04-LTS-Jumphost" -OsType "Linux"

    Write-Host "[4/4] Creare Image Definition 'imgdef-winserver2022'..." -ForegroundColor Yellow
    New-ImageDefinition -DefName "imgdef-winserver2022" -Publisher "SCMediaSRL" -Offer "WindowsServer" -Sku "2022-Datacenter" -OsType "Windows"

    Write-Host ""
    Write-Host "[OK] Gallery si Image Definitions sunt pregatite!" -ForegroundColor Green
    Write-Host ""
}

# ============================================================
# PASUL 2: Detectare versiuni si confirmare per imagine
# ============================================================

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " PASUL 2: Build Packer Images"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$buildResults = @{}
$imagesToBuild = @()

# Detecteaza versiunea urmatoare si intreaba pentru fiecare imagine
foreach ($img in $ImageConfigs) {
    $nextVersion = Get-NextImageVersion -ImgDef $img.ImgDef
    $currentVersions = az sig image-version list --resource-group $ResourceGroup --gallery-name $GalleryName --gallery-image-definition $img.ImgDef --query "[].name" -o tsv 2>$null

    Write-Host "  $($img.Name)" -ForegroundColor White
    if ($currentVersions) {
        $latestVer = $currentVersions -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_ } | Select-Object -Last 1
        Write-Host "    Versiune curenta: $latestVer" -ForegroundColor Gray
    }
    else {
        Write-Host "    Versiune curenta: (niciuna)" -ForegroundColor Gray
    }
    Write-Host "    Versiune noua:    $nextVersion" -ForegroundColor Yellow

    if ($NoConfirm) {
        $imagesToBuild += @{ Config = $img; Version = $nextVersion }
        Write-Host "    -> Se va construi (NoConfirm)" -ForegroundColor Green
    }
    else {
        $answer = Read-Host "    Doresti sa construiesti aceasta imagine? (d/n)"
        if ($answer -eq "d" -or $answer -eq "D" -or $answer -eq "da" -or $answer -eq "Da" -or $answer -eq "y" -or $answer -eq "Y") {
            $imagesToBuild += @{ Config = $img; Version = $nextVersion }
            Write-Host "    -> Se va construi" -ForegroundColor Green
        }
        else {
            Write-Host "    -> Se va sari" -ForegroundColor Gray
        }
    }
    Write-Host ""
}

if ($imagesToBuild.Count -eq 0) {
    Write-Host "[INFO] Nicio imagine selectata pentru build. Se iese." -ForegroundColor Yellow
    exit 0
}

Write-Host "--- Incepem build-ul pentru $($imagesToBuild.Count) imagine(i) ---" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# PASUL 3: Build Packer Images
# ============================================================

foreach ($item in $imagesToBuild) {
    $img = $item.Config
    $version = $item.Version
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logFile = Join-Path $LogDir "packer-$($img.Key)-$timestamp.log"

    Build-PackerImage -Name $img.Name -PackerDir $img.PackerDir -SubId $SubscriptionId -RG $ResourceGroup -ImgVersion $version -LogFile $logFile
}

# ============================================================
# PASUL 4: Verificare
# ============================================================

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " PASUL 4: Verificare imagini publicate"
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$definitions = @("imgdef-ubuntu2204", "imgdef-ubuntu2204-jumphost", "imgdef-winserver2022")
foreach ($def in $definitions) {
    Write-Host "  ${def}: " -ForegroundColor Yellow -NoNewline
    $versions = az sig image-version list --resource-group $ResourceGroup --gallery-name $GalleryName --gallery-image-definition $def --query "[].name" -o tsv 2>$null
    if ($LASTEXITCODE -eq 0 -and $versions) {
        $verList = ($versions -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ", "
        Write-Host $verList -ForegroundColor Green
    }
    else {
        Write-Host "(nicio versiune)" -ForegroundColor Gray
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
    if ($entry.Value -eq "SUCCESS") {
        Write-Host "  $($entry.Key): $($entry.Value)" -ForegroundColor Green
    }
    else {
        Write-Host "  $($entry.Key): $($entry.Value)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "  Loguri salvate in: $LogDir" -ForegroundColor Gray
Write-Host ""

$failCount = @($buildResults.Values | Where-Object { $_ -ne "SUCCESS" }).Count
if ($failCount -eq 0 -and $buildResults.Count -gt 0) {
    Write-Host "[OK] Toate imaginile au fost construite si publicate cu succes!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Pasul urmator: Seteaza 'useMarketplaceImages = false' in prod.bicepparam" -ForegroundColor Yellow
    Write-Host "si re-deployeaza cu:" -ForegroundColor Yellow
    Write-Host "  az deployment sub create --location swedencentral --template-file bicep/main.bicep --parameters bicep/parameters/prod.bicepparam" -ForegroundColor White
}
elseif ($failCount -gt 0) {
    Write-Host "[WARN] $failCount imagine(i) au esuat. Verifica logurile din $LogDir" -ForegroundColor Red
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
