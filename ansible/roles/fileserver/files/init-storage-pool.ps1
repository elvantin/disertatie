# init-storage-pool.ps1
# Creates a Windows Storage Pool + VirtualDisk + D:\ from the raw data disk (LUN 0).
# Idempotent: exits immediately if D:\ already exists.

# Skip if D:\ already exists
if (Test-Path 'D:\') {
    Write-Output 'D:\ already exists - skipping storage pool creation'
    exit 0
}

# Find the raw (uninitialized) disk attached at LUN 0
$rawDisk = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' -and $_.BusType -eq 'SCSI' } | Select-Object -First 1
if ($null -eq $rawDisk) {
    Write-Error 'No raw SCSI disk found. Ensure a data disk is attached in Azure.'
    exit 1
}

# Create Storage Pool from the physical disk
$subSystem = Get-StorageSubSystem | Select-Object -First 1
$physDisk  = Get-PhysicalDisk -UniqueId $rawDisk.UniqueId
$pool = New-StoragePool `
    -FriendlyName 'MediaSRL-FileData' `
    -StorageSubSystemFriendlyName $subSystem.FriendlyName `
    -PhysicalDisks $physDisk

# Create a simple (no redundancy) VirtualDisk using maximum space
$vdisk = New-VirtualDisk `
    -StoragePoolFriendlyName 'MediaSRL-FileData' `
    -FriendlyName 'FileServerData' `
    -UseMaximumSize `
    -ProvisioningType Fixed `
    -ResiliencySettingName Simple

# Initialize, partition and format the VirtualDisk as D:\
$vdisk | Get-Disk | Initialize-Disk -PartitionStyle GPT -PassThru |
    New-Partition -DriveLetter D -UseMaximumSize |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel 'FileServerData' -Confirm:$false | Out-Null

Write-Output 'Storage pool created and D:\ formatted successfully'
