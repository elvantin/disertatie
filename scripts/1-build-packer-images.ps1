# ============================================================
# SC MEDIA SRL - Build & Publish Packer Images
# Automatizare completa: Gallery + Image Definitions + Packer Build
# - Auto-increment versiune per imagine
# - Confirmare interactiva per imagine
# - Output salvat in fisier log
# Rulare: .\scripts\1-build-packer-images.ps1 [-SkipGallery] [-NoConfirm]
# ============================================================

param(
    [switch]$SkipGallery,
    [switch]$NoConfirm
)

$ErrorActionPreference = "Continue"
$ProjectRoot = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $ProjectRoot "logs"

. "$PSScriptRoot\lib\Write-Log.ps1"
Start-LogSession -ScriptTitle "Packer Image Builder" -LogDirectory $LogDir

trap {
    Write-Log-Fail "Eroare neasteptata: $_" -Detail "Script oprit prematur"
    Stop-LogSession
    break
}

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

Write-Log-Header "Verificări preliminare" -Step 1 -Total 4
Write-Log-Step "Verificare Azure CLI..."
az account show 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Log-Fail "Nu ești autentificat în Azure CLI" -Detail "Rulează: az login"
    Stop-LogSession; exit 1
}
$SubscriptionId = (az account show --query id -o tsv)
$ResourceGroup  = "rg-mediasrl-packer-$Location"
Write-Log-OK "Azure CLI autentificat" -Detail $SubscriptionId

Write-Log-Step "Verificare Packer..."
$packerVersion = packer --version 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Log-Fail "Packer nu este instalat" -Detail "winget install HashiCorp.Packer"
    Stop-LogSession; exit 1
}
Write-Log-OK "Packer disponibil" -Detail "v$packerVersion"

Write-Log-Step "Verificare Resource Group '$ResourceGroup'..."
$rgExists = az group exists --name $ResourceGroup -o tsv
if ($rgExists -ne "true") {
    az group create --name $ResourceGroup --location $Location --tags environment=productie project=mediasrl managed-by=packer
    if ($LASTEXITCODE -ne 0) {
        Write-Log-Fail "Eroare la crearea Resource Group" -Detail $ResourceGroup
        Stop-LogSession; exit 1
    }
    Write-Log-OK "Resource Group creat" -Detail $ResourceGroup
} else {
    Write-Log-OK "Resource Group există" -Detail $ResourceGroup
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
        Write-Log-Warn "Image Definition deja există — skip" -Detail $DefName
        return
    }

    az sig image-definition create --resource-group $ResourceGroup --gallery-name $GalleryName --gallery-image-definition $DefName --publisher $Publisher --offer $Offer --sku $Sku --os-type $OsType --os-state Generalized --hyper-v-generation V2 --location $Location --tags $TagsList
    if ($LASTEXITCODE -ne 0) {
        Write-Log-Fail "Eroare la crearea Image Definition" -Detail $DefName
        Stop-LogSession; exit 1
    }
    Write-Log-OK "Image Definition creat" -Detail $DefName
}

# Extrage linii semnificative din output-ul packer build pentru raportul HTML.
# Filtreaza dump-urile VERBOSE de cod PowerShell (sute de linii inutile).
function Get-PackerMilestones {
    param([string[]]$Lines)
    $result = [System.Collections.Generic.List[string]]::new()
    $inVerboseDump = $false
    foreach ($rawLine in $Lines) {
        $line = [string]$rawLine
        # Detecteaza inceputul unui dump VERBOSE de cod PS
        if ($line -match 'VERBOSE: Running command') { $inVerboseDump = $true; continue }
        if ($inVerboseDump) {
            # Dumpl-ul se termina la urmatoarea linie ==> care nu e VERBOSE
            if ($line -match '^==> ' -and $line -notmatch 'VERBOSE:') { $inVerboseDump = $false }
            else { continue }
        }
        # Extrage continut din "==> azure-arm.xxx: <continut>"
        if ($line -match '^==> azure-arm\.[^:]+: (.+)$') {
            $content = $Matches[1].Trim()
            if (-not $content) { continue }
            # Sare peste sub-proprietati "->" EXCEPTAND versiunea SIG
            if ($content -match '^ *->' -and $content -notmatch 'SIG image version' -and $content -notmatch 'Shared Gallery Image Version') { continue }
            if ($content -match '^VERBOSE:') { continue }
            if ($content -match '^" to ') { continue }

            $keep = $content -match '^\[' -or
                    $content -match 'Creating resource group' -or
                    $content -match 'WinRM' -or
                    $content -match 'Connected to' -or
                    $content -match 'Restarting Machine' -or
                    $content -match 'restarted\.' -or
                    $content -match 'successfully restarted' -or
                    $content -match 'Provisioning with Powershell' -or
                    $content -match 'Cleaning up' -or
                    $content -match 'Sysprep' -or
                    $content -match 'Image state:' -or
                    $content -match 'Powering off' -or
                    $content -match 'Generaliz' -or
                    $content -match 'Publishing to Shared' -or
                    $content -match 'SIG image version' -or
                    $content -match 'Shared Gallery Image Version' -or
                    $content -match 'Deleting Virtual Machine' -or
                    $content -match 'Resource group has been deleted' -or
                    $content -match 'Deleted ->'
            if ($keep) { [void]$result.Add($content) }
        }
        # Linie de finalizare build (nu are prefix ==>)
        elseif ($line -match "^Build '.+' (finished after|FAILED|errored)") {
            [void]$result.Add($line)
        }
        # Linii de artifact final (--> azure-arm.xxx: OSType/ManagedImage/SharedImageGallery)
        elseif ($line -match '^--> azure-arm\.[^:]+: (OSType|ManagedImage|SharedImageGallery)') {
            [void]$result.Add(($line -replace '^--> azure-arm\.[^:]+: ', ''))
        }
    }
    return $result.ToArray()
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

    Write-Log-Step "$Name  v$ImgVersion"
    Write-Log-Info "Dir: $PackerDir"
    Write-Log-Info "Log: $(Split-Path $LogFile -Leaf)"

    # Header in log file
    "=" * 60 | Out-File -FilePath $LogFile -Encoding UTF8
    "Build: $Name"                                  | Out-File -FilePath $LogFile -Append -Encoding UTF8
    "Version: $ImgVersion"                          | Out-File -FilePath $LogFile -Append -Encoding UTF8
    "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    "=" * 60 | Out-File -FilePath $LogFile -Append -Encoding UTF8

    Push-Location $PackerDir
    try {
        # packer init
        Write-Log-Step "  packer init..."
        $initLines = [System.Collections.Generic.List[string]]::new()
        packer init . 2>&1 | Tee-Object -FilePath $LogFile -Append | ForEach-Object { [void]$initLines.Add([string]$_) }
        if ($LASTEXITCODE -ne 0) {
            Write-Log-Fail "packer init a eșuat" -Detail "$(Split-Path $LogFile -Leaf)"
            Write-Log-Block -Label "Output packer init — $Name" -Content ($initLines -join "`n")
            $script:buildResults[$Name] = "FAILED (init)"; return
        }
        Write-Log-OK "packer init OK"

        # packer validate
        Write-Log-Step "  packer validate..."
        $valLines = [System.Collections.Generic.List[string]]::new()
        packer validate -var "subscription_id=$SubId" -var "gallery_resource_group=$RG" -var "image_version=$ImgVersion" . 2>&1 |
            Tee-Object -FilePath $LogFile -Append | ForEach-Object { [void]$valLines.Add([string]$_) }
        if ($LASTEXITCODE -ne 0) {
            Write-Log-Fail "packer validate a eșuat" -Detail "$(Split-Path $LogFile -Leaf)"
            Write-Log-Block -Label "Output packer validate — $Name" -Content ($valLines -join "`n")
            $script:buildResults[$Name] = "FAILED (validate)"; return
        }
        Write-Log-OK "packer validate OK"

        # packer build — capturare completa + milestone-uri cheie
        Write-Log-Step "  packer build — poate dura 10-30 minute..."
        $buildLines = [System.Collections.Generic.List[string]]::new()
        packer build -var "subscription_id=$SubId" -var "gallery_resource_group=$RG" -var "image_version=$ImgVersion" -color=false . 2>&1 |
            Tee-Object -FilePath $LogFile -Append | ForEach-Object { [void]$buildLines.Add([string]$_) }
        $buildExit = $LASTEXITCODE

        # Milestone-uri cheie ca linii Info in HTML
        $milestones = Get-PackerMilestones -Lines $buildLines.ToArray()
        foreach ($m in $milestones) { Write-Log-Info "    $m" }

        # Output complet ca bloc colapsibil in HTML
        Write-Log-Block -Label "Output complet: packer build $Name v$ImgVersion" -Content ($buildLines -join "`n")

        if ($buildExit -ne 0) {
            Write-Log-Fail "packer build a eșuat" -Detail "$(Split-Path $LogFile -Leaf)"
            $script:buildResults[$Name] = "FAILED (build)"; return
        }

        Write-Log-OK "Build complet" -Detail "$Name v$ImgVersion"
        $script:buildResults[$Name] = "SUCCESS"
    }
    finally {
        Pop-Location
    }
}

# ============================================================
# PASUL 1: Creare Azure Compute Gallery + Image Definitions
# ============================================================

if (-not $SkipGallery) {
    Write-Log-Header "Azure Compute Gallery Setup" -Step 2 -Total 4

    Write-Log-Step "Verificare/Creare Gallery '$GalleryName'..."
    az sig show --resource-group $ResourceGroup --gallery-name $GalleryName 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Log-Warn "Gallery deja există — skip" -Detail $GalleryName
    } else {
        az sig create --resource-group $ResourceGroup --gallery-name $GalleryName --location $Location --tags $TagsList
        if ($LASTEXITCODE -ne 0) {
            Write-Log-Fail "Eroare la crearea Gallery" -Detail $GalleryName
            Stop-LogSession; exit 1
        }
        Write-Log-OK "Gallery creat" -Detail $GalleryName
    }

    New-ImageDefinition -DefName "imgdef-ubuntu2204"          -Publisher "SCMediaSRL" -Offer "Ubuntu"        -Sku "22.04-LTS-Base"    -OsType "Linux"
    New-ImageDefinition -DefName "imgdef-ubuntu2204-jumphost" -Publisher "SCMediaSRL" -Offer "Ubuntu"        -Sku "22.04-LTS-Jumphost" -OsType "Linux"
    New-ImageDefinition -DefName "imgdef-winserver2022"       -Publisher "SCMediaSRL" -Offer "WindowsServer" -Sku "2022-Datacenter"    -OsType "Windows"

    Write-Log-OK "Gallery și Image Definitions pregătite"
}

Write-Log-Header "Detectare versiuni + confirmare" -Step 3 -Total 4

$buildResults = @{}
$imagesToBuild = @()

foreach ($img in $ImageConfigs) {
    $nextVersion = Get-NextImageVersion -ImgDef $img.ImgDef
    $currentVersions = az sig image-version list --resource-group $ResourceGroup --gallery-name $GalleryName --gallery-image-definition $img.ImgDef --query "[].name" -o tsv 2>$null

    Write-Host ""
    Write-Host "  $($img.Name)" -ForegroundColor White
    if ($currentVersions) {
        $latestVer = $currentVersions -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_ } | Select-Object -Last 1
        Write-Host "    Versiune curentă : $latestVer" -ForegroundColor Gray
    } else {
        Write-Host "    Versiune curentă : (niciuna)" -ForegroundColor Gray
    }
    Write-Host "    Versiune nouă    : $nextVersion" -ForegroundColor Yellow

    if ($NoConfirm) {
        $imagesToBuild += @{ Config = $img; Version = $nextVersion }
        Write-Log-OK "Adăugat la build list" -Detail "$($img.Name) v$nextVersion"
    } else {
        $answer = Read-Host "    Construiești această imagine? (d/n)"
        if ($answer -in @('d','D','da','Da','y','Y')) {
            $imagesToBuild += @{ Config = $img; Version = $nextVersion }
            Write-Log-OK "Selectat pentru build" -Detail "$($img.Name) v$nextVersion"
        } else {
            Write-Log-Info "Sărit: $($img.Name)"
        }
    }
}

if ($imagesToBuild.Count -eq 0) {
    Write-Log-Warn "Nicio imagine selectată — ieșire"
    Stop-LogSession; exit 0
}

Write-Log-Header "Packer Build ($($imagesToBuild.Count) imagine(i))" -Step 4 -Total 4

foreach ($item in $imagesToBuild) {
    $img      = $item.Config
    $version  = $item.Version
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $logFile  = Join-Path $LogDir "packer-$($img.Key)-$timestamp.log"
    Build-PackerImage -Name $img.Name -PackerDir $img.PackerDir -SubId $SubscriptionId -RG $ResourceGroup -ImgVersion $version -LogFile $logFile
}

# Verificare versiuni publicate
Write-Host ""
$definitions = @("imgdef-ubuntu2204", "imgdef-ubuntu2204-jumphost", "imgdef-winserver2022")
foreach ($def in $definitions) {
    $versions = az sig image-version list --resource-group $ResourceGroup --gallery-name $GalleryName --gallery-image-definition $def --query "[].name" -o tsv 2>$null
    if ($LASTEXITCODE -eq 0 -and $versions) {
        $verList = ($versions -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ", "
        Write-Log-OK "$def" -Detail $verList
    } else {
        Write-Log-Warn "$def" -Detail "(nicio versiune publicată)"
    }
}

# Rezumat final
$failCount = @($buildResults.Values | Where-Object { $_ -ne "SUCCESS" }).Count
foreach ($entry in $buildResults.GetEnumerator()) {
    if ($entry.Value -eq "SUCCESS") {
        Write-Log-OK $entry.Key -Detail $entry.Value
    } else {
        Write-Log-Fail $entry.Key -Detail $entry.Value
    }
}

if ($failCount -eq 0 -and $buildResults.Count -gt 0) {
    Write-Log-Info "Pasul urmator: .\scripts\2-deploy-teardown-bicep.ps1 -Action deploy -Environment prod"
}

Stop-LogSession
