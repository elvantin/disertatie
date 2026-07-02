# init-storage-pool.ps1
# Initializes the 80 GB data disk as E:\ for SMB shares.
# Idempotent: exits immediately if E:\ is already formatted.
#
# Drive letter assignment uses diskpart (not Set-Partition / New-Partition -DriveLetter)
# because PowerShell's Storage WMI layer returns error 42002 "access path already in use"
# when a CD-ROM or stale reservation holds E: in the storage subsystem's in-memory state,
# even after MountedDevices registry cleanup.  diskpart talks to vds.exe directly and
# can force-reassign the letter without those caching issues.

function Invoke-DiskpartScript {
    param([string]$Commands)
    $tmp = Join-Path $env:TEMP "_dp_$(Get-Random).txt"
    [System.IO.File]::WriteAllText($tmp, $Commands, [System.Text.Encoding]::ASCII)
    $output = diskpart /s $tmp | Out-String
    Remove-Item $tmp -ErrorAction SilentlyContinue
    return $output
}

# Idempotency: E: already formatted -> skip everything
$existingVol = Get-Volume -DriveLetter E -ErrorAction SilentlyContinue
if ($existingVol -and $existingVol.FileSystem -ne '') {
    Write-Output "E:\ already formatted ($($existingVol.FileSystem), $($existingVol.FileSystemLabel)) - skipping"
    exit 0
}

# Find data disk: >50 GB excludes the 8 GB Azure temp disk; Number -gt 0 excludes OS disk
$dataDisk = Get-Disk |
    Where-Object { $_.Number -gt 0 -and $_.Size -gt 50GB } |
    Sort-Object Number |
    Select-Object -First 1

if ($null -eq $dataDisk) {
    Write-Error 'Data disk not found (>50 GB). Check Azure disk attachment in prod.bicepparam.'
    exit 1
}

Write-Output "Data disk: Disk $($dataDisk.Number), $([math]::Round($dataDisk.Size/1GB,1)) GB, PartitionStyle=$($dataDisk.PartitionStyle)"

# Initialize as GPT only if still RAW
if ($dataDisk.PartitionStyle -eq 'RAW') {
    Initialize-Disk -Number $dataDisk.Number -PartitionStyle GPT -ErrorAction Stop
    Write-Output "Disk $($dataDisk.Number) initialized as GPT"
    Start-Sleep -Seconds 2
}

# Find existing data partition by disk number (not by drive letter).
# Exclude GPT MSR partition: it is ~128 MB and Type=Reserved.
$dataPart = Get-Partition -DiskNumber $dataDisk.Number -ErrorAction SilentlyContinue |
    Where-Object { $_.Size -gt 100MB -and $_.Type -ne 'Reserved' } |
    Select-Object -Last 1

if ($null -eq $dataPart) {
    Write-Output "Creating partition on Disk $($dataDisk.Number) (no drive letter yet)..."
    $dataPart = New-Partition -DiskNumber $dataDisk.Number -UseMaximumSize -ErrorAction Stop
    if ($null -eq $dataPart) {
        Write-Error "New-Partition returned null"
        exit 1
    }
    Start-Sleep -Seconds 2
}

Write-Output "Partition: Disk $($dataDisk.Number) / Partition $($dataPart.PartitionNumber), Size=$([math]::Round($dataPart.Size/1GB,1)) GB, DriveLetter='$($dataPart.DriveLetter)'"

# Assign drive letter E: via diskpart
if ($dataPart.DriveLetter -ne 'E') {

    # Show current diskpart volume state for diagnostics
    $volList = Invoke-DiskpartScript "list volume`r`nexit"
    Write-Output "diskpart list volume:`n$volList"

    # If any volume currently has E:, remove it first (could be CD-ROM or stale reservation)
    $eVolLine = ($volList -split "`r?`n") |
        Where-Object { $_ -match '^\s+Volume\s+\d+' -and $_ -match '\s{2}E\s' } |
        Select-Object -First 1

    if ($eVolLine -and ($eVolLine -match 'Volume\s+(\d+)')) {
        $eVolNum = $Matches[1]
        Write-Output "Removing E: from diskpart Volume $eVolNum..."
        $removeOut = Invoke-DiskpartScript "select volume $eVolNum`r`nremove letter=E noerr`r`nexit"
        Write-Output $removeOut
        Start-Sleep -Seconds 2
    } else {
        Write-Output "No diskpart volume currently shows E: - proceeding to assign directly"
    }

    # Assign E: to our data partition
    $dpAssign  = "select disk $($dataDisk.Number)`r`nselect partition $($dataPart.PartitionNumber)`r`nassign letter=E`r`nexit"
    Write-Output "Assigning E: to Disk $($dataDisk.Number) Partition $($dataPart.PartitionNumber) via diskpart..."
    $assignOut = Invoke-DiskpartScript $dpAssign
    Write-Output $assignOut

    if ($assignOut -notmatch 'successfully assigned') {
        Write-Error "diskpart assign letter=E failed. See output above."
        exit 1
    }
    Start-Sleep -Seconds 2
}

# Verify E: is accessible before formatting
$checkVol = Get-Volume -DriveLetter E -ErrorAction SilentlyContinue
if ($null -eq $checkVol) {
    Write-Error "E: not accessible after drive letter assignment"
    exit 1
}

if ($checkVol.FileSystem -ne '') {
    Write-Output "E: already has filesystem ($($checkVol.FileSystem)) - skipping format"
    exit 0
}

# Format directly (not via pipeline, to avoid silent failures)
Write-Output "Formatting E: as NTFS..."
Format-Volume -DriveLetter E -FileSystem NTFS -NewFileSystemLabel 'FileServerData' -Confirm:$false -ErrorAction Stop

$vol = Get-Volume -DriveLetter E -ErrorAction SilentlyContinue
if ($null -eq $vol -or $vol.FileSystem -eq '') {
    Write-Error "Format-Volume did not produce a filesystem on E:"
    exit 1
}

Write-Output "E:\ ready: $($vol.FileSystem), label=$($vol.FileSystemLabel), size=$([math]::Round($vol.Size/1GB,1)) GB"
