# ============================================================
# Pre-Sysprep Preparation — Windows Server 2022 Golden Image
#
# Run AFTER all updates and hardening, BEFORE sysprep.
# Goals:
#   1. Stop Windows Update services (prevents WU from running during sysprep)
#   2. Clear SoftwareDistribution\Download cache (reduces image size 1-3 GB)
#   3. Re-register Windows Update + Task Scheduler COM DLLs (ensures clean state)
#   4. Restart services and VERIFY COM works before baking the image
#   5. Fail the Packer build if COM is still broken (better now than at deploy time)
#
# Error 0x800703FA ("registry key marked for deletion") in Ansible win_updates
# means Task Scheduler COM is broken in the image. This script prevents that
# by verifying COM works before sysprep captures the image.
# ============================================================

$ErrorActionPreference = "Continue"

Write-Output "========================================="
Write-Output " Pre-Sysprep Preparation"
Write-Output "========================================="

# ── 1. Stop Windows Update services ──────────────────────────────────────────
Write-Output "[1/5] Stopping Windows Update services..."

$wuServices = @('wuauserv', 'bits', 'cryptsvc', 'msiserver', 'TrustedInstaller', 'UsoSvc', 'WaaSMedicSvc')
foreach ($svc in $wuServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($s -and $s.Status -eq 'Running') {
            Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
            Write-Output "  Stopped: $svc"
        }
    } catch { }
}
Start-Sleep 3
Write-Output "  [OK] Windows Update services stopped"

# ── 2. Clear WU download cache ────────────────────────────────────────────────
Write-Output "[2/5] Clearing SoftwareDistribution download cache..."

$cachePath = "C:\Windows\SoftwareDistribution\Download"
try {
    $sizeBefore = (Get-ChildItem $cachePath -Recurse -ErrorAction SilentlyContinue |
                   Measure-Object -Property Length -Sum).Sum
    Remove-Item -Path "$cachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
    $sizeBeforeGB = [math]::Round($sizeBefore / 1GB, 2)
    Write-Output "  Cleared $sizeBeforeGB GB from WU download cache"
} catch {
    Write-Output "  WARNING: Could not clear cache: $_"
}

# ── 3. Re-register COM DLLs ───────────────────────────────────────────────────
Write-Output "[3/5] Re-registering Windows Update and Task Scheduler COM DLLs..."

# Task Scheduler COM DLLs (required for Ansible win_updates async)
$schedDlls = @('taskschd.dll', 'schedsvc.dll', 'atl.dll')
# Windows Update COM DLLs
$wuDlls = @(
    'wuapi.dll', 'wuaueng.dll', 'wucltux.dll', 'wudriver.dll',
    'wups.dll', 'wups2.dll', 'wuwebv.dll'
)
# Core COM infrastructure
$comDlls = @('ole32.dll', 'oleaut32.dll', 'msxml.dll', 'msxml3.dll', 'msxml6.dll')

$allDlls = $schedDlls + $wuDlls + $comDlls
foreach ($dll in $allDlls) {
    $result = & regsvr32 /s $dll 2>&1
    # regsvr32 /s is silent on success (exit 0) and silent on "not found" (non-zero)
}
Write-Output "  [OK] DLLs re-registered"

# ── 4. Restart Task Scheduler and WU services cleanly ─────────────────────────
Write-Output "[4/5] Restarting Task Scheduler and Windows Update services..."

# Task Scheduler must start first (WU depends on it)
Stop-Service Schedule -Force -ErrorAction SilentlyContinue
Start-Sleep 2
Start-Service Schedule -ErrorAction SilentlyContinue
Start-Sleep 3

# Start WU services
foreach ($svc in @('bits', 'cryptsvc', 'wuauserv')) {
    try {
        Start-Service $svc -ErrorAction SilentlyContinue
    } catch { }
}
Start-Sleep 5

# ── 5. Verify COM works ───────────────────────────────────────────────────────
Write-Output "[5/5] Verifying COM components (fail-fast before baking image)..."

$schedOk = $false
$wuOk    = $false

try {
    $sched = New-Object -ComObject 'Schedule.Service'
    $sched.Connect()
    $schedOk = $true
    Write-Output "  [OK] Task Scheduler COM (Schedule.Service) — working"
} catch {
    Write-Output "  [FAIL] Task Scheduler COM broken: $_"
}

try {
    $null = New-Object -ComObject 'Microsoft.Update.Session'
    $wuOk = $true
    Write-Output "  [OK] Windows Update COM (Microsoft.Update.Session) — working"
} catch {
    Write-Output "  [FAIL] Windows Update COM broken: $_"
}

# Check pending file rename operations (should be clear after the last reboot)
$pendingKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
$pending = Get-ItemProperty $pendingKey -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
if ($pending) {
    Write-Output "  [WARN] PendingFileRenameOperations still present — will be cleared by next reboot"
} else {
    Write-Output "  [OK] No pending file rename operations"
}

# Fail the Packer build if either COM is broken — a broken image is worse than a failed build
if (-not $schedOk) {
    Write-Output ""
    Write-Output "FATAL: Task Scheduler COM is broken in this image."
    Write-Output "Ansible win_updates (async) will fail with 0x800703FA after deployment."
    Write-Output "Investigate the build VM before re-running packer build."
    exit 1
}

if (-not $wuOk) {
    Write-Output ""
    Write-Output "FATAL: Windows Update COM is broken in this image."
    Write-Output "Ansible win_updates will fail after deployment."
    exit 1
}

Write-Output ""
Write-Output "========================================="
Write-Output " Pre-Sysprep Preparation — PASSED"
Write-Output " COM is working. Safe to run sysprep."
Write-Output "========================================="
