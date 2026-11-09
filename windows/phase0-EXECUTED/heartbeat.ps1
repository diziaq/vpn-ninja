<#
.SYNOPSIS
  Phase 0 of the gated rollout plan: checks that RU-PC stays awake and online for hours.

.DESCRIPTION
  Every minute it requests one Russian site (ya.ru) and one foreign site (gstatic.com).
  While it runs it keeps the PC from sleeping (this ends when the window closes).
  It changes no settings and installs nothing.

  EVIDENCE (send this file back):
    evidence\EVIDENCE-phase0-heartbeat-<timestamp>.txt
  Refreshed every 15 minutes and rewritten at the end, also after Ctrl+C.
  If its Status still says RUNNING and the Updated time is old, the script was killed
  (window closed, sign-out, reboot or power loss); that is itself a result.

  Raw data stays on this PC (send only if asked):
    runs\phase0-heartbeat-<timestamp>.csv

  Start (leave the window open, then close Remote Desktop with the X; do NOT sign out):
    powershell -NoProfile -ExecutionPolicy Bypass -File .\heartbeat.ps1 -Hours 12

  Re-create the evidence from an existing CSV:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\heartbeat.ps1 -Analyze .\runs\phase0-heartbeat-YYYYMMDD-HHMMSS.csv

  Measure the PC's normal sleep behaviour instead (does not keep it awake): add -AllowSleep
#>
[CmdletBinding()]
param(
  [double]$Hours = 12,
  [int]$IntervalSec = 60,
  [int]$EvidenceEveryMin = 15,
  [switch]$AllowSleep,
  [string]$Analyze = ''
)

$ScriptVersion = '1.1'
$ErrorActionPreference = 'Continue'
if (-not $PSScriptRoot) { Write-Host 'Run this as a file (-File .\heartbeat.ps1).'; exit 1 }

$started = Get-Date
$stamp   = $started.ToString('yyyyMMdd-HHmmss')
$EvDir   = Join-Path $PSScriptRoot 'evidence'
$RunsDir = Join-Path $PSScriptRoot 'runs'
New-Item -ItemType Directory -Path $EvDir -Force | Out-Null
New-Item -ItemType Directory -Path $RunsDir -Force | Out-Null

function Get-ShortHash([string]$s) {
  try {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $b = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($s))
    return (($b[0..3] | ForEach-Object { $_.ToString('x2') }) -join '')
  } catch { return 'unknown' }
}
function Get-Sha256([string]$path) {
  try { return (Get-FileHash -Algorithm SHA256 -Path $path -ErrorAction Stop).Hash.ToLower() } catch { return 'n/a' }
}
function Test-Code([string]$c) { return ($c -match '^[23]\d\d$') }
function To-Num([string]$s) {
  $d = 0.0
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
  return $null
}
function Get-Median($vals) {
  $v = @($vals | Where-Object { $_ -ne $null } | Sort-Object)
  if ($v.Count -eq 0) { return '-' }
  $m = [int][math]::Floor($v.Count / 2)
  if ($v.Count % 2) { return ('{0:N2}' -f $v[$m]) }
  return ('{0:N2}' -f (($v[$m - 1] + $v[$m]) / 2))
}

$MachineId = Get-ShortHash ($env:COMPUTERNAME + '|' + $env:USERDOMAIN)

function Build-Evidence([string]$CsvPath, [string]$Status, [string]$Mode, [string]$RunId, [string]$Params) {
  $rows = @()
  if (Test-Path $CsvPath) { $rows = @(Import-Csv $CsvPath) }
  $now = Get-Date
  $L = New-Object System.Collections.Generic.List[string]
  $L.Add('==== RU-PROBE EVIDENCE ====')
  $L.Add("Script:     heartbeat.ps1 v$ScriptVersion ($Mode)")
  $L.Add("Run ID:     $RunId")
  $L.Add("Machine:    $MachineId (hash of computer name)")
  if ($rows.Count -gt 0) { $L.Add(("Started:    {0} local / {1} UTC (first check)" -f $rows[0].local, $rows[0].utc)) }
  $L.Add(("Updated:    {0} local / {1} UTC" -f $now.ToString('s'), $now.ToUniversalTime().ToString('s')))
  $L.Add("Status:     $Status")
  $L.Add("Parameters: $Params")
  $L.Add('')
  $L.Add('---- Summary ----')
  if ($rows.Count -lt 2) {
    $L.Add('Not enough data yet (fewer than 2 checks).')
  } else {
    $times = @($rows | ForEach-Object { [datetime]::Parse($_.utc, [Globalization.CultureInfo]::InvariantCulture) })
    $interval = [int]$rows[0].interval
    $span = $times[-1] - $times[0]
    $gaps = @()
    for ($i = 1; $i -lt $times.Count; $i++) {
      $d = ($times[$i] - $times[$i - 1]).TotalSeconds
      if ($d -gt (2.5 * $interval)) { $gaps += ('   {0} -> {1} ({2:N1} min)' -f $rows[$i - 1].local, $rows[$i].local, ($d / 60)) }
    }
    $ruOk = @($rows | Where-Object { Test-Code $_.ru_code }).Count
    $inOk = @($rows | Where-Object { Test-Code $_.intl_code }).Count
    $n = $rows.Count
    $L.Add(('Covered:    {0:N1} hours, {1} checks, interval {2}s' -f $span.TotalHours, $n, $interval))
    $L.Add(('Gaps over {0}s (asleep, off, frozen): {1}' -f [int](2.5 * $interval), $gaps.Count))
    foreach ($g in ($gaps | Select-Object -First 20)) { $L.Add($g) }
    $L.Add(('Russian site (ya.ru) OK:        {0} of {1} ({2:N1}%)' -f $ruOk, $n, (100.0 * $ruOk / $n)))
    $L.Add(('Foreign site (gstatic.com) OK:  {0} of {1} ({2:N1}%)' -f $inOk, $n, (100.0 * $inOk / $n)))
    $pass = ($span.TotalHours -ge 2) -and ($gaps.Count -eq 0) -and (($ruOk / $n) -ge 0.97)
    $L.Add(('Gate G0 uptime check: {0}' -f $(if ($pass) { 'PASS' } else { 'NOT YET (needs 2+ hours, no gaps, 97%+ Russian-site success)' })))

    $L.Add('')
    $L.Add('---- Per hour (local time) ----')
    $L.Add(('{0,-14} {1,6} {2,6} {3,10} {4,9} {5,13}' -f 'hour', 'checks', 'ru ok', 'foreign ok', 'ru med s', 'foreign med s'))
    foreach ($h in ($rows | Group-Object { $_.local.Substring(0, 13) })) {
      $g = @($h.Group)
      $L.Add(('{0,-14} {1,6} {2,6} {3,10} {4,9} {5,13}' -f ($h.Name + ':00'), $g.Count,
        @($g | Where-Object { Test-Code $_.ru_code }).Count,
        @($g | Where-Object { Test-Code $_.intl_code }).Count,
        (Get-Median ($g | ForEach-Object { To-Num $_.ru_time })),
        (Get-Median ($g | ForEach-Object { To-Num $_.intl_time }))))
    }

    $L.Add('')
    $L.Add('---- Failed checks (first 100) ----')
    $fails = @($rows | Where-Object { -not (Test-Code $_.ru_code) -or -not (Test-Code $_.intl_code) })
    if ($fails.Count -eq 0) { $L.Add('(none)') }
    foreach ($f in ($fails | Select-Object -First 100)) {
      $L.Add(('{0}  ru {1} {2}s  foreign {3} {4}s' -f $f.local, $f.ru_code, $f.ru_time, $f.intl_code, $f.intl_time))
    }
  }
  $L.Add('')
  $L.Add('---- Raw data kept on the PC (send only if asked) ----')
  if (Test-Path $CsvPath) { $L.Add(('runs\{0}  sha256 {1}' -f (Split-Path $CsvPath -Leaf), (Get-Sha256 $CsvPath))) }
  $L.Add('==== END ====')
  return $L
}

# ---------- analyze mode ----------
if ($Analyze) {
  $csvIn = (Resolve-Path $Analyze -ErrorAction SilentlyContinue)
  if (-not $csvIn) { Write-Host "File not found: $Analyze"; exit 1 }
  $base = [IO.Path]::GetFileNameWithoutExtension($csvIn.Path)
  $evOut = Join-Path $EvDir ("EVIDENCE-{0}-analysis-{1}.txt" -f $base, $stamp)
  $lines = Build-Evidence $csvIn.Path 'ANALYSIS OF EXISTING DATA' 'analyze' "$base-$MachineId" ("Analyze=" + (Split-Path $csvIn.Path -Leaf))
  $lines | Out-File $evOut -Encoding UTF8
  $lines | ForEach-Object { Write-Host $_ }
  Write-Host ''
  Write-Host "EVIDENCE FILE TO SEND BACK: $evOut"
  exit 0
}

# ---------- run mode ----------
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { Write-Host 'curl.exe not found.'; exit 1 }

$RunId  = "phase0-heartbeat-$stamp-$MachineId"
$csv    = Join-Path $RunsDir "phase0-heartbeat-$stamp.csv"
$EvFile = Join-Path $EvDir "EVIDENCE-phase0-heartbeat-$stamp.txt"
'utc,local,interval,ru_code,ru_time,intl_code,intl_time' | Out-File $csv -Encoding ascii

$awake = $false
if (-not $AllowSleep) {
  try {
    Add-Type -Namespace Phase0 -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);' -ErrorAction Stop
    # ES_CONTINUOUS (0x80000000) + ES_SYSTEM_REQUIRED (0x1)
    [void][Phase0.Power]::SetThreadExecutionState([uint32]2147483649)
    $awake = $true
  } catch { Write-Host 'Could not keep the PC awake (restricted PowerShell). Measuring as is.' }
}
$params = "Hours=$Hours; IntervalSec=$IntervalSec; KeepAwake=$awake; AllowSleep=$([bool]$AllowSleep)"

$end = $started.AddHours($Hours)
Write-Host ("Heartbeat v{0} running until {1}." -f $ScriptVersion, $end.ToString('yyyy-MM-dd HH:mm'))
Write-Host "EVIDENCE FILE (refreshed every $EvidenceEveryMin min): $EvFile"
Write-Host 'Close Remote Desktop with the X button; do not sign out. Ctrl+C stops early and still writes the evidence.'
Build-Evidence $csv 'RUNNING (just started)' 'run' $RunId $params | Out-File $EvFile -Encoding UTF8

$status = 'STOPPED (Ctrl+C or interrupted)'
$lastEv = Get-Date
try {
  while ((Get-Date) -lt $end) {
    $t0 = Get-Date
    $ru = (& curl.exe -s -o NUL -m 15 -w '%{http_code},%{time_total}' https://ya.ru/ 2>$null) -join ''
    if (-not $ru) { $ru = '000,0' }
    $intl = (& curl.exe -s -o NUL -m 15 -w '%{http_code},%{time_total}' https://www.gstatic.com/generate_204 2>$null) -join ''
    if (-not $intl) { $intl = '000,0' }
    Add-Content -Path $csv -Value ('{0},{1},{2},{3},{4}' -f $t0.ToUniversalTime().ToString('s'), $t0.ToString('s'), $IntervalSec, $ru, $intl)
    Write-Host ('{0}  ru {1}  foreign {2}' -f $t0.ToString('HH:mm:ss'), $ru, $intl)

    if (((Get-Date) - $lastEv).TotalMinutes -ge $EvidenceEveryMin) {
      $runningNote = 'RUNNING (partial; refreshed every {0} min, planned end {1})' -f $EvidenceEveryMin, $end.ToString('s')
      Build-Evidence $csv $runningNote 'run' $RunId $params | Out-File $EvFile -Encoding UTF8
      $lastEv = Get-Date
    }
    $wait = $IntervalSec - ((Get-Date) - $t0).TotalSeconds
    if ($wait -gt 0) { Start-Sleep -Seconds ([int][math]::Ceiling($wait)) }
  }
  $status = 'COMPLETED'
} catch {
  $status = 'FAILED: ' + $_.Exception.Message
} finally {
  if ($awake) { try { [void][Phase0.Power]::SetThreadExecutionState([uint32]2147483648) } catch { } }
  $lines = Build-Evidence $csv $status 'run' $RunId $params
  $lines | Out-File $EvFile -Encoding UTF8
  Write-Host ''
  $lines | Select-Object -First 30 | ForEach-Object { Write-Host $_ }
  Write-Host ''
  Write-Host "EVIDENCE FILE TO SEND BACK: $EvFile"
}
