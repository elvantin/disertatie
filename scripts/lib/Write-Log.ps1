# ============================================================
# Write-Log.ps1 — SC MEDIA SRL — Shared Logging Library
#
# Dot-source at the beginning of each PowerShell script:
#   . "$PSScriptRoot\lib\Write-Log.ps1"
#
# Typical usage:
#   $LogDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs'
#   Start-LogSession -ScriptTitle "My Script" -LogDirectory $LogDir
#   Write-Log-Header "Section name" -Step 1 -Total 4
#   Write-Log-Step   "Doing something..."
#   Write-Log-OK     "Resource created" -Detail "rg-mediasrl-productie"
#   Write-Log-Warn   "Already exists — skip"
#   Write-Log-Fail   "Authentication failed"
#   Write-Log-Info   "Additional detail line"
#   Stop-LogSession
# ============================================================

$script:_Entries   = [System.Collections.Generic.List[hashtable]]::new()
$script:_StartTime = $null
$script:_Title     = "Script"
$script:_LogFile   = ""
$script:_HtmlFile  = ""

# ── Public API ────────────────────────────────────────────────

function Start-LogSession {
    param(
        [string]$ScriptTitle,
        [string]$LogDirectory
    )
    $script:_Title     = $ScriptTitle
    $script:_StartTime = Get-Date
    $script:_Entries.Clear()

    if (-not (Test-Path $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $ts       = $script:_StartTime.ToString("yyyyMMdd-HHmmss")
    $safeName = ($ScriptTitle -replace '[^a-zA-Z0-9 ]', '' -replace ' +', '-').ToLower()
    $base     = Join-Path $LogDirectory "$safeName-$ts"
    $script:_LogFile  = "${base}.log"
    $script:_HtmlFile = "${base}.html"

    try { Start-Transcript -Path $script:_LogFile -Force | Out-Null } catch {}

    _Write-Banner
}

function Stop-LogSession {
    $dur      = (Get-Date) - $script:_StartTime
    $durStr   = "$([int]$dur.TotalMinutes)m $($dur.Seconds)s"
    $ok       = @($script:_Entries | Where-Object { $_.Type -eq 'OK'   }).Count
    $fail     = @($script:_Entries | Where-Object { $_.Type -eq 'FAIL' }).Count
    $warn     = @($script:_Entries | Where-Object { $_.Type -eq 'WARN' }).Count

    $lineColor = if ($fail -gt 0) { 'Red' } elseif ($warn -gt 0) { 'Yellow' } else { 'Green' }
    $statusMsg = if ($fail -gt 0) { "EXECUȚIE CU ERORI ($fail erori)" } `
                 elseif ($warn -gt 0) { "FINALIZAT CU AVERTISMENTE ($warn)" } `
                 else { "EXECUȚIE REUȘITĂ" }

    Write-Host ""
    _Separator $lineColor
    Write-Host "  $statusMsg" -ForegroundColor $lineColor
    Write-Host "  Durată : $durStr   |   OK: $ok   FAIL: $fail   WARN: $warn" -ForegroundColor Gray
    Write-Host "  Log    : $(Split-Path $script:_LogFile  -Leaf)" -ForegroundColor DarkGray
    Write-Host "  HTML   : $(Split-Path $script:_HtmlFile -Leaf)" -ForegroundColor DarkGray
    _Separator $lineColor
    Write-Host ""

    _Export-HtmlReport -Duration $durStr
    try { Stop-Transcript | Out-Null } catch {}
}

function Write-Log-Header {
    param([string]$Title, [int]$Step = 0, [int]$Total = 0)
    $stepStr = if ($Step -gt 0 -and $Total -gt 0) { "  [$Step/$Total]" } else { "" }
    $display = "$Title$stepStr"
    Write-Host ""
    Write-Host "  ┌─── $display" -ForegroundColor Cyan
    Write-Host ""
    $script:_Entries.Add(@{ Type = 'Header'; Message = $display; Time = (Get-Date) })
}

function Write-Log-Step {
    param([string]$Message)
    Write-Host "  [>>] $Message" -ForegroundColor Yellow
    $script:_Entries.Add(@{ Type = 'Step'; Message = $Message; Time = (Get-Date) })
}

function Write-Log-OK {
    param([string]$Message, [string]$Detail = '')
    Write-Host "  [OK] $Message" -ForegroundColor Green
    if ($Detail) { Write-Host "       $Detail" -ForegroundColor DarkGreen }
    $script:_Entries.Add(@{ Type = 'OK'; Message = $Message; Detail = $Detail; Time = (Get-Date) })
}

function Write-Log-Fail {
    param([string]$Message, [string]$Detail = '')
    Write-Host "  [!!] $Message" -ForegroundColor Red
    if ($Detail) { Write-Host "       $Detail" -ForegroundColor DarkRed }
    $script:_Entries.Add(@{ Type = 'FAIL'; Message = $Message; Detail = $Detail; Time = (Get-Date) })
}

function Write-Log-Warn {
    param([string]$Message, [string]$Detail = '')
    Write-Host "  [!]  $Message" -ForegroundColor Yellow
    if ($Detail) { Write-Host "       $Detail" -ForegroundColor DarkYellow }
    $script:_Entries.Add(@{ Type = 'WARN'; Message = $Message; Detail = $Detail; Time = (Get-Date) })
}

function Write-Log-Info {
    param([string]$Message)
    Write-Host "       $Message" -ForegroundColor Gray
    $script:_Entries.Add(@{ Type = 'Info'; Message = $Message; Time = (Get-Date) })
}

function Write-Log-Block {
    param([string]$Label, [string]$Content)
    # Strip ANSI escape codes so HTML renders clean text, not escape sequences
    $clean = $Content -replace '\x1B(\[[0-9;]*[A-Za-z]|\(B)', ''
    $lc = ($clean -split "`n").Count
    Write-Host "  [╡] $Label  ($lc linii → vedeți HTML)" -ForegroundColor DarkCyan
    $script:_Entries.Add(@{ Type = 'Block'; Message = $Label; Content = $clean; Time = (Get-Date) })
}

# ── Private helpers ──────────────────────────────────────────

function _Separator([string]$Color = 'Cyan') {
    Write-Host ("  " + ("=" * 60)) -ForegroundColor $Color
}

function _Write-Banner {
    $now  = $script:_StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    $leaf = Split-Path $script:_LogFile -Leaf
    Write-Host ""
    _Separator
    Write-Host "  SC MEDIA SRL — $($script:_Title)" -ForegroundColor White
    Write-Host "  Data  : $now" -ForegroundColor Gray
    Write-Host "  Log   : $leaf" -ForegroundColor DarkGray
    _Separator
    Write-Host ""
}

function _HtmlEnc([string]$s) {
    $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
}

function _Export-HtmlReport {
    param([string]$Duration)

    $now      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $ok       = @($script:_Entries | Where-Object { $_.Type -eq 'OK'   }).Count
    $fail     = @($script:_Entries | Where-Object { $_.Type -eq 'FAIL' }).Count
    $warn     = @($script:_Entries | Where-Object { $_.Type -eq 'WARN' }).Count
    $total    = $ok + $fail + $warn
    $pct      = if ($total -gt 0) { [int](100 * $ok / $total) } else { 100 }
    $barColor = if ($fail -gt 0) { '#f85149' } elseif ($warn -gt 0) { '#d29922' } else { '#3fb950' }
    $statusCls = if ($fail -gt 0) { 'fail' } elseif ($warn -gt 0) { 'warn' } else { 'ok' }
    $statusTxt = if ($fail -gt 0) { "EXECUȚIE CU ERORI &nbsp;·&nbsp; $fail erori detectate" } `
                 elseif ($warn -gt 0) { "FINALIZAT CU AVERTISMENTE &nbsp;·&nbsp; $warn avertismente" } `
                 else { "EXECUȚIE REUȘITĂ &nbsp;·&nbsp; Toate operațiile au trecut" }

    # Build entries HTML — group by Header sections
    $body  = ""
    $inSec = $false
    foreach ($e in $script:_Entries) {
        $t = $e.Time.ToString("HH:mm:ss")
        $m = _HtmlEnc $e.Message

        if ($e.Type -eq 'Header') {
            if ($inSec) { $body += "</div></div>`n" }
            $body += "<div class='section'><div class='sec-title'><span class='ts'>$t</span>$m</div><div class='sec-body'>`n"
            $inSec = $true
        } elseif ($e.Type -eq 'Step') {
            $body += "<div class='row step'><span class='ts'>$t</span><span class='arrow'>&#8594;</span>$m</div>`n"
        } elseif ($e.Type -eq 'OK') {
            $det = if ($e.Detail) { " <span class='det'>· $(_HtmlEnc $e.Detail)</span>" } else { '' }
            $body += "<div class='row ok'><span class='ts'>$t</span><span class='badge ok-b'>OK</span>$m$det</div>`n"
        } elseif ($e.Type -eq 'FAIL') {
            $det = if ($e.Detail) { " <span class='det'>· $(_HtmlEnc $e.Detail)</span>" } else { '' }
            $body += "<div class='row fail'><span class='ts'>$t</span><span class='badge fail-b'>FAIL</span>$m$det</div>`n"
        } elseif ($e.Type -eq 'WARN') {
            $det = if ($e.Detail) { " <span class='det'>· $(_HtmlEnc $e.Detail)</span>" } else { '' }
            $body += "<div class='row warn'><span class='ts'>$t</span><span class='badge warn-b'>WARN</span>$m$det</div>`n"
        } elseif ($e.Type -eq 'Info') {
            $body += "<div class='row info'><span class='ts'>$t</span>$m</div>`n"
        } elseif ($e.Type -eq 'Block') {
            $lc  = ($e.Content -split "`n").Count
            $cnt = _HtmlEnc $e.Content
            $body += "<details class='log-block'><summary><span class='ts'>$t</span><span>$m</span><span class='det'>&nbsp;($lc linii)</span></summary><pre class='block-pre'>$cnt</pre></details>`n"
        }
    }
    if ($inSec) { $body += "</div></div>`n" }

    $titleEnc = _HtmlEnc $script:_Title
    $logLeaf  = Split-Path $script:_LogFile -Leaf

    $html = @"
<!DOCTYPE html>
<html lang="ro">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$titleEnc — Execution Log</title>
<style>
:root{--bg:#0d1117;--bg2:#161b22;--bg3:#21262d;--bdr:#30363d;--txt:#c9d1d9;--muted:#8b949e;
      --blue:#58a6ff;--green:#3fb950;--yel:#d29922;--red:#f85149;--cyan:#39c5cf;}
*{box-sizing:border-box;margin:0;padding:0;}
body{font-family:'Segoe UI',Consolas,monospace;background:var(--bg);color:var(--txt);padding:24px;line-height:1.55;}
.wrap{max-width:960px;margin:0 auto;}

.hcard{background:linear-gradient(135deg,#0d1117,#161b22);border:1px solid var(--bdr);
       border-top:3px solid var(--cyan);border-radius:8px;padding:28px 32px;margin-bottom:18px;}
.hcard h1{color:var(--cyan);font-size:1.45em;margin-bottom:6px;}
.hcard .sub{color:var(--muted);font-size:.83em;margin-bottom:14px;}
.meta{display:flex;gap:28px;flex-wrap:wrap;}
.meta-i{font-size:.81em;color:var(--muted);}
.meta-i strong{color:var(--txt);}

.banner{text-align:center;padding:11px 20px;border-radius:6px;font-weight:700;
        font-size:.95em;letter-spacing:1.2px;margin-bottom:18px;text-transform:uppercase;}
.banner.ok  {background:rgba(63,185,80,.12);border:1px solid var(--green);color:var(--green);}
.banner.fail{background:rgba(248,81,73,.12); border:1px solid var(--red);  color:var(--red);}
.banner.warn{background:rgba(210,153,34,.12);border:1px solid var(--yel);  color:var(--yel);}

.stats{display:flex;gap:14px;margin-bottom:18px;}
.stat{flex:1;background:var(--bg2);border:1px solid var(--bdr);border-radius:8px;
      padding:18px 14px;text-align:center;}
.stat .n{font-size:2.5em;font-weight:700;line-height:1;}
.stat .l{font-size:.72em;color:var(--muted);margin-top:5px;text-transform:uppercase;letter-spacing:.5px;}
.s-ok .n{color:var(--green);}.s-fail .n{color:var(--red);}.s-warn .n{color:var(--yel);}

.prog-wrap{margin-bottom:20px;}
.prog-lbl{font-size:.78em;color:var(--muted);margin-bottom:5px;}
.prog-bg{background:var(--bg3);border-radius:4px;height:7px;overflow:hidden;}
.prog-fill{height:100%;border-radius:4px;background:$barColor;width:$pct%;}

.section{background:var(--bg2);border:1px solid var(--bdr);border-radius:8px;margin-bottom:10px;overflow:hidden;}
.sec-title{background:var(--bg3);padding:9px 18px;font-weight:600;color:var(--cyan);
           font-size:.88em;letter-spacing:.3px;border-bottom:1px solid var(--bdr);}
.sec-body{padding:6px 0;}

.row{display:flex;align-items:baseline;gap:7px;padding:3px 18px;font-size:.87em;}
.row.ok  {color:var(--green);}
.row.fail{color:var(--red);  background:rgba(248,81,73,.06); border-left:3px solid var(--red); padding-left:15px;}
.row.warn{color:var(--yel);  background:rgba(210,153,34,.06);border-left:3px solid var(--yel); padding-left:15px;}
.row.info{color:var(--muted);}
.row.step{color:#e9c46a;}
.badge{display:inline-block;padding:1px 7px;border-radius:20px;font-size:.71em;font-weight:700;
       text-transform:uppercase;letter-spacing:.5px;flex-shrink:0;}
.ok-b  {background:rgba(63,185,80,.18); color:var(--green);border:1px solid var(--green);}
.fail-b{background:rgba(248,81,73,.18); color:var(--red);  border:1px solid var(--red);}
.warn-b{background:rgba(210,153,34,.18);color:var(--yel);  border:1px solid var(--yel);}
.ts{color:#3d444d;font-size:.77em;font-family:Consolas,monospace;flex-shrink:0;}
.arrow{color:#e9c46a;flex-shrink:0;}
.det{color:var(--muted);}

.footer{text-align:center;color:var(--muted);font-size:.73em;margin-top:26px;
        padding-top:14px;border-top:1px solid var(--bdr);}
.footer strong{color:var(--cyan);}
@media(max-width:600px){.stats,.meta{flex-direction:column;}}
details.log-block{margin:4px 18px;}
details.log-block>summary{display:flex;gap:7px;align-items:center;padding:4px 0;cursor:pointer;
  font-size:.85em;color:var(--blue);list-style:none;user-select:none;}
details.log-block>summary::-webkit-details-marker{display:none;}
details.log-block>summary::before{content:'▶';font-size:.68em;color:var(--muted);
  transition:transform .15s;flex-shrink:0;}
details.log-block[open]>summary::before{transform:rotate(90deg);}
details.log-block>summary:hover{color:var(--cyan);}
.block-pre{background:#010409;border:1px solid var(--bdr);padding:10px 16px;border-radius:0 0 4px 4px;
  font-family:Consolas,monospace;font-size:.75em;color:#8b949e;white-space:pre-wrap;
  word-break:break-word;max-height:460px;overflow-y:auto;border-left:3px solid var(--blue);}
</style>
</head>
<body>
<div class="wrap">

<div class="hcard">
  <h1>SC MEDIA SRL &mdash; $titleEnc</h1>
  <p class="sub">Log de execuție generat automat &middot; Proiect disertație master</p>
  <div class="meta">
    <div class="meta-i">Data execuției: <strong>$now</strong></div>
    <div class="meta-i">Durată totală: <strong>$Duration</strong></div>
    <div class="meta-i">Fișier text: <strong>$logLeaf</strong></div>
  </div>
</div>

<div class="banner $statusCls">$statusTxt</div>

<div class="stats">
  <div class="stat s-ok">  <div class="n">$ok</div>  <div class="l">Operații reușite</div></div>
  <div class="stat s-fail"><div class="n">$fail</div><div class="l">Erori</div></div>
  <div class="stat s-warn"><div class="n">$warn</div><div class="l">Avertismente</div></div>
</div>

<div class="prog-wrap">
  <div class="prog-lbl">Rată de succes: $pct% &nbsp;($ok din $total operații înregistrate)</div>
  <div class="prog-bg"><div class="prog-fill"></div></div>
</div>

$body

<div class="footer">
  Generat de <strong>SC IT SECURITY SRL</strong> pentru <strong>SC MEDIA SRL</strong><br>
  Infrastructură cloud Azure &middot; Bicep &middot; Packer &middot; Ansible<br>
  Proiect disertație master &mdash; $now
</div>

</div></body></html>
"@

    $html | Out-File -FilePath $script:_HtmlFile -Encoding UTF8 -Force
}
