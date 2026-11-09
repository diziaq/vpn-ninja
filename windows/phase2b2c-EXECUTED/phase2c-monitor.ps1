<#
.SYNOPSIS
  Phase 2c: long-running monitor of the VPN links from this Russian PC.
  No admin rights, no drivers: portable Xray clients as local proxies on 127.0.0.1 only.

.DESCRIPTION
  Every 2.5 minutes (one "cycle") it checks, for every vless:// link in links.txt:
    - a tiny test page through the tunnel        (is the tunnel alive?)
    - one blocked site from services.txt group A (does it reach what you need?)
    - a 1 MB download through the tunnel          (catches the ~16 KB freeze)
  and, without the tunnel, ya.ru as a control     (was the office line itself up?)
  It prints ONE short line per cycle, keeps the PC awake while it runs, and rewrites its
  evidence file after every cycle, so the file is useful even if the window is closed.

  Safe to start again at any time: every start writes a NEW evidence file. Send back ALL
    evidence\EVIDENCE-phase2c-monitor-*.txt
  Only one monitor can run at a time (lock file monitor.lock). If one is already running,
  this script says so and tells you how to stop it.

  links.txt is re-read every cycle: paste new links (for example server B) and they are
  picked up without a restart.

  v1.1: evidence file was never written in v1.0 (loop variable $e overwrote $E: PowerShell names
        ignore case); save errors are now shown on screen. A blocked site now counts as reached on any
        HTTP answer (facebook.com answers 400 to scripts through a working tunnel). Both found in the
        Docker test before first use.

  Start:  double-click 2-START-MONITOR.cmd     (or: powershell -NoProfile -ExecutionPolicy Bypass -File .\phase2c-monitor.ps1)
  Stop:   double-click 3-STOP-MONITOR.cmd, or press Ctrl+C in the monitor window.
  Leave Remote Desktop with the X button. Do NOT sign out (that ends the monitor).
#>
[CmdletBinding()]
param(
  [int]$IntervalSec = 150,
  [double]$Hours = 0,
  [int]$DownloadBytes = 1000000,
  [string]$LinksFile = '',
  [string]$ServicesFile = '',
  [string]$XrayPath = '',
  [switch]$Stop
)

$ScriptVersion = '1.1'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
if (-not $PSScriptRoot) { Write-Host 'Run this as a file (-File .\phase2c-monitor.ps1), not by pasting it.'; exit 1 }
$onWindows = ($env:OS -eq 'Windows_NT')
if (-not $LinksFile)    { $LinksFile    = Join-Path $PSScriptRoot 'links.txt' }
if (-not $ServicesFile) { $ServicesFile = Join-Path $PSScriptRoot 'services.txt' }
if (-not $XrayPath)     { $XrayPath = Join-Path $PSScriptRoot $(if ($onWindows) { 'bin\xray.exe' } else { 'bin/xray' }) }
$LockFile    = Join-Path $PSScriptRoot 'monitor.lock'
$StopRequest = Join-Path $PSScriptRoot 'monitor.stop'
$EvDir       = Join-Path $PSScriptRoot 'evidence'
$NullDev     = $(if ($onWindows) { 'NUL' } else { '/dev/null' })
$TestUrl     = 'https://www.gstatic.com/generate_204'
$DirectUrl   = 'https://ya.ru/'
$DownUrl     = "https://speed.cloudflare.com/__down?bytes=$DownloadBytes"
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

# ---------------- small helpers ----------------
function Get-ShortHash([string]$s) {
  try { $sha = [System.Security.Cryptography.SHA256]::Create(); $b = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)); return (($b[0..3] | ForEach-Object { $_.ToString('x2') }) -join '') } catch { return 'unknown' }
}
function To-Num([string]$s) {
  $d = 0.0
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
  return 0.0
}
function Write-NoBom([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false))) }
function Mask([string]$s) { if (-not $s) { return '' }; if ($s.Length -le 8) { return '****' }; return ($s.Substring(0, 4) + '...' + $s.Substring($s.Length - 4)) }
function Fmt-Dur([double]$sec) { $t = [TimeSpan]::FromSeconds([math]::Max(0, $sec)); return ('{0}h{1:D2}m' -f [int][math]::Floor($t.TotalHours), $t.Minutes) }
function Test-Tcp([string]$HostName, [int]$Port, [int]$TimeoutMs = 700) {
  $c = $null
  try { $c = New-Object System.Net.Sockets.TcpClient; $iar = $c.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }; $c.EndConnect($iar); return $true }
  catch { return $false } finally { if ($c) { $c.Close() } }
}
function Invoke-Curl([string[]]$Extra, [string]$Url, [int]$MaxTime) {
  $cargs = @('-s', '-o', $NullDev, '-m', "$MaxTime", '--connect-timeout', '10', '-A', $UA) + $Extra + @('-w', '%{http_code}|%{size_download}|%{speed_download}', $Url)
  $raw = (& curl.exe @cargs 2>$null) -join ''
  $exit = $LASTEXITCODE
  $f = $raw -split '\|'; while ($f.Count -lt 3) { $f += '' }
  return [pscustomobject]@{ exit = $exit; http = $f[0]; bytes = [int64](To-Num $f[1]); mbps = [math]::Round((To-Num $f[2]) * 8 / 1e6, 1) }
}
function Read-Lock {
  # Returns the lock content as a hashtable, or $null. Opens with full sharing so it works while held.
  if (-not (Test-Path $LockFile)) { return $null }
  try {
    $fs = [IO.File]::Open($LockFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    $sr = New-Object IO.StreamReader($fs); $txt = $sr.ReadToEnd(); $sr.Close(); $fs.Close()
  } catch { return @{ unreadable = $true } }
  $h = @{}
  foreach ($line in ($txt -split "`r?`n")) { $p = $line -split '=', 2; if ($p.Count -eq 2) { $h[$p[0].Trim()] = $p[1].Trim() } }
  return $h
}
function Get-LockOwner($lock) {
  # The process named in the lock, only if it is still the same process (PID and start time match).
  if (-not $lock -or -not $lock['pid']) { return $null }
  $p = Get-Process -Id ([int]$lock['pid']) -ErrorAction SilentlyContinue
  if (-not $p) { return $null }
  try { if ($lock['start'] -and ([math]::Abs($p.StartTime.ToUniversalTime().Ticks - [int64]$lock['start']) -gt 20000000)) { return $null } } catch { }
  return $p
}
function Stop-OurXray {
  # Kills only xray processes started from THIS package's bin folder (leftovers of a killed run).
  $n = 0
  foreach ($p in @(Get-Process -Name xray -ErrorAction SilentlyContinue)) {
    try { if ($p.Path -and ([IO.Path]::GetFullPath($p.Path) -eq [IO.Path]::GetFullPath($XrayPath))) { $p.Kill(); $n++ } } catch { }
  }
  return $n
}
function Show-AlreadyRunning($lock, $owner) {
  Write-Host ''
  Write-Host '=================================================================' -ForegroundColor Yellow
  Write-Host ' THE MONITOR IS ALREADY RUNNING. A second copy will not start.' -ForegroundColor Yellow
  Write-Host '=================================================================' -ForegroundColor Yellow
  if ($lock -and $lock['pid']) {
    Write-Host ("  Process ID:   {0}" -f $lock['pid'])
    Write-Host ("  Started:      {0}" -f $lock['started'])
    Write-Host ("  Writing to:   {0}" -f $lock['evidence'])
  }
  Write-Host ''
  Write-Host '  It may be in another window (check the taskbar for "RU-PROBE MONITOR").'
  Write-Host '  If you want to restart it: double-click 3-STOP-MONITOR.cmd, then start again.'
  if ($lock -and $lock['pid']) { Write-Host ("  (Manual stop, if that fails: taskkill /PID {0} /T /F)" -f $lock['pid']) }
  Write-Host ''
}

# ---------------- -Stop mode ----------------
if ($Stop) {
  $lock = Read-Lock
  $owner = Get-LockOwner $lock
  if (-not $owner) {
    $k = Stop-OurXray
    if (Test-Path $LockFile) { Remove-Item $LockFile -Force -ErrorAction SilentlyContinue }
    Remove-Item $StopRequest -Force -ErrorAction SilentlyContinue
    Write-Host 'The monitor is not running. Nothing to stop.'
    if ($k -gt 0) { Write-Host "Cleaned up $k leftover xray process(es)." }
    exit 0
  }
  Write-Host ("Asking the monitor (PID {0}) to stop and write its final evidence ..." -f $owner.Id)
  Write-NoBom $StopRequest ("requested " + (Get-Date).ToString('s'))
  $gone = $false
  for ($i = 0; $i -lt 90; $i++) {
    Start-Sleep -Seconds 1
    if (-not (Get-Process -Id $owner.Id -ErrorAction SilentlyContinue)) { $gone = $true; break }
    if ($i % 5 -eq 4) { Write-Host -NoNewline '.' }
  }
  Write-Host ''
  if (-not $gone) {
    Write-Host 'It did not stop within 90 seconds. Forcing it to stop.'
    if ($onWindows) { & taskkill.exe /PID $owner.Id /T /F 2>$null | Out-Null } else { try { $owner.Kill() } catch { } }
    Start-Sleep -Seconds 2
    $k = Stop-OurXray
    Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    Write-Host 'Stopped by force. Its evidence file has the results up to the last cycle.'
  } else {
    Write-Host 'Stopped. Its evidence file is complete.'
  }
  Remove-Item $StopRequest -Force -ErrorAction SilentlyContinue
  if ($lock['evidence']) { Write-Host ("Evidence: {0}" -f $lock['evidence']) }
  exit 0
}

# ---------------- single-instance lock ----------------
New-Item -ItemType Directory -Path $EvDir -Force | Out-Null
$lockStream = $null
$oldLock = Read-Lock
$owner = Get-LockOwner $oldLock
if ($owner -and $owner.Id -ne $PID) { Show-AlreadyRunning $oldLock $owner; exit 2 }
try {
  # Held open (others may only read) for the whole run: a live monitor cannot be overwritten.
  $lockStream = [IO.File]::Open($LockFile, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
} catch {
  Show-AlreadyRunning (Read-Lock) $null; exit 2
}
$staleNote = ''
if ($oldLock -and $oldLock['pid']) { $staleNote = ("previous monitor (PID {0}, started {1}) had ended without cleanup" -f $oldLock['pid'], $oldLock['started']) }
$leftovers = Stop-OurXray
Remove-Item $StopRequest -Force -ErrorAction SilentlyContinue

$started = Get-Date
$stamp   = $started.ToString('yyyyMMdd-HHmmss')
$EvFile  = Join-Path $EvDir "EVIDENCE-phase2c-monitor-$stamp.txt"
$WorkDir = Join-Path $PSScriptRoot "runs\phase2c-monitor-$stamp"
New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
$MachineId = Get-ShortHash ($env:COMPUTERNAME + '|' + $env:USERDOMAIN)
$RunId = "phase2c-monitor-$stamp-$MachineId"
$myStart = (Get-Process -Id $PID).StartTime.ToUniversalTime().Ticks
$lockText = "pid=$PID`r`nstart=$myStart`r`nstarted=$($started.ToString('yyyy-MM-dd HH:mm:ss'))`r`nevidence=$EvFile`r`n"
$lockBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($lockText)
$lockStream.SetLength(0); $lockStream.Write($lockBytes, 0, $lockBytes.Length); $lockStream.Flush()

# ---------------- state ----------------
$events  = New-Object System.Collections.Generic.List[string]   # notable events, with time
$cycles  = New-Object System.Collections.Generic.List[object]   # one row per cycle
$stats   = @{}                                                   # per link name
$procs   = @{}                                                   # per link name -> process info
$linksHash = ''
$links   = @()
$groupA  = @()
$awake   = $false
$status  = 'RUNNING'
$xrayVersion = 'n/a'
function Add-Event([string]$msg) { $events.Add(((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + '  ' + $msg)) }
if ($staleNote) { Add-Event ("Start: " + $staleNote + "; lock taken over") }
if ($leftovers -gt 0) { Add-Event ("Start: stopped {0} leftover xray process(es) from an earlier run" -f $leftovers) }

function Parse-Vless([string]$line) {
  $u = [System.Uri]$line.Trim()
  $q = @{}
  foreach ($kv in ($u.Query.TrimStart('?') -split '&')) {
    if (-not $kv) { continue }
    $p = $kv -split '=', 2
    $q[$p[0]] = [System.Uri]::UnescapeDataString($(if ($p.Count -gt 1) { $p[1] } else { '' }))
  }
  $nm = [System.Uri]::UnescapeDataString($u.Fragment.TrimStart('#'))
  if (-not $nm) { $nm = "link-$($u.Port)" }
  [pscustomobject]@{
    name = $nm; id = [System.Uri]::UnescapeDataString($u.UserInfo)
    host = $u.Host; port = $u.Port; type = $(if ($q['type']) { $q['type'] } else { 'tcp' }); flow = [string]$q['flow']
    sni = [string]$q['sni']; pbk = [string]$q['pbk']; sid = [string]$q['sid']; path = [string]$q['path']
    mode = $(if ($q['mode']) { $q['mode'] } else { 'auto' }); fp = $(if ($q['fp']) { $q['fp'] } else { 'chrome' })
  }
}
function New-ClientConfig($L, [int]$Port) {
  $stream = [ordered]@{
    network = $L.type; security = 'reality'
    realitySettings = [ordered]@{ serverName = $L.sni; fingerprint = $L.fp; publicKey = $L.pbk; password = $L.pbk; shortId = $L.sid; spiderX = '' }
  }
  if ($L.type -eq 'xhttp') { $stream.xhttpSettings = [ordered]@{ path = $L.path; mode = $L.mode } }
  $user = [ordered]@{ id = $L.id; encryption = 'none' }
  if ($L.flow) { $user.flow = $L.flow }
  $cfg = [ordered]@{
    log = @{ loglevel = 'warning' }
    inbounds = @( [ordered]@{ listen = '127.0.0.1'; port = $Port; protocol = 'socks'; settings = @{ udp = $false } } )
    outbounds = @( [ordered]@{ protocol = 'vless'; tag = 'proxy'
                    settings = @{ vnext = @( [ordered]@{ address = $L.host; port = $L.port; users = @( $user ) } ) }
                    streamSettings = $stream } )
  }
  return ($cfg | ConvertTo-Json -Depth 12)
}
function Get-FreePort([int]$from) { $p = $from; while (Test-Tcp '127.0.0.1' $p 200) { $p++ }; return $p }
function Start-Proxy($L, [int]$idx) {
  $port = Get-FreePort (10900 + 10 * $idx)
  $cfg = Join-Path $WorkDir ("client-{0}.json" -f $idx)
  Write-NoBom $cfg (New-ClientConfig $L $port)
  $err = Join-Path $WorkDir ("xray-{0}.err.log" -f $idx)
  $out = Join-Path $WorkDir ("xray-{0}.out.log" -f $idx)
  $p = Start-Process -FilePath $XrayPath -ArgumentList @('run', '-c', "`"$cfg`"") -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
  $up = $false
  for ($t = 0; $t -lt 20; $t++) { if (Test-Tcp '127.0.0.1' $port 300) { $up = $true; break }; Start-Sleep -Milliseconds 300 }
  # The config holds the client ID: delete it as soon as xray has read it.
  Remove-Item $cfg -Force -ErrorAction SilentlyContinue
  return [pscustomobject]@{ proc = $p; port = $port; up = $up; link = $L; idx = $idx }
}
function Stop-Proxies {
  foreach ($k in @($procs.Keys)) { $x = $procs[$k]; try { if ($x.proc -and -not $x.proc.HasExited) { $x.proc.Kill() } } catch { } }
  $procs.Clear()
}
function Load-Links {
  if (-not (Test-Path $LinksFile)) { return $false }
  $raw = (Get-Content $LinksFile -ErrorAction SilentlyContinue) -join "`n"
  $h = Get-ShortHash $raw
  if ($h -eq $script:linksHash) { return $false }
  $script:linksHash = $h
  $parsed = @()
  foreach ($line in ($raw -split "`n")) {
    if ($line -match '^\s*vless://') { try { $parsed += Parse-Vless $line } catch { Add-Event ("links.txt: could not read one line: " + $_.Exception.Message) } }
  }
  Stop-Proxies
  $script:links = $parsed
  $i = 0
  foreach ($L in $script:links) {
    $i++
    $px = Start-Proxy $L $i
    $procs[$L.name] = $px
    if (-not $stats.ContainsKey($L.name)) {
      $stats[$L.name] = @{ n = 0; ok = 0; part = 0; fail = 0; nAdj = 0; okAdj = 0; eveN = 0; eveOk = 0; streak = 0; worst = 0; restarts = 0; mbps = New-Object System.Collections.Generic.List[double]; ipNote = ''; desc = '' }
    }
    $st = $stats[$L.name]
    $st.desc = ("{0}:{1} type={2} flow={3} fp={4} sni={5} id={6}" -f 'server', $L.port, $L.type, $(if ($L.flow) { $L.flow } else { '-' }), $L.fp, $L.sni, (Mask $L.id))
    if ($px.up) {
      $ip = ((& curl.exe -s -m 15 --socks5-hostname ("127.0.0.1:{0}" -f $px.port) 'https://api.ipify.org' 2>$null) -join '').Trim()
      $st.ipNote = $(if ($ip -eq $L.host) { 'exit address = server (OK)' } elseif ($ip) { 'exit address is NOT the server (' + (Mask $ip) + ')' } else { 'exit address: no answer' })
    } else { $st.ipNote = 'local proxy did not start' }
    Add-Event ("Link loaded: {0} ({1}); {2}" -f $L.name, $st.desc, $st.ipNote)
  }
  return $true
}
function Is-Evening([datetime]$t) { return ($t.Hour -ge 19 -and $t.Hour -lt 23) }

function Build-Evidence {
  $now = Get-Date
  $span = ($now - $started).TotalSeconds
  $E = New-Object System.Collections.Generic.List[string]
  $E.Add('==== RU-PROBE EVIDENCE ====')
  $E.Add("Script:     phase2c-monitor.ps1 v$ScriptVersion")
  $E.Add("Run ID:     $RunId")
  $E.Add("Machine:    $MachineId (hash of computer name)")
  $E.Add(("Started:    {0} local / {1} UTC" -f $started.ToString('s'), $started.ToUniversalTime().ToString('s')))
  $E.Add(("Updated:    {0} local ({1} running)" -f $now.ToString('s'), (Fmt-Dur $span)))
  if ($status -eq 'RUNNING') { $E.Add('Status:     RUNNING (rewritten after every cycle; if Updated is old, the monitor was closed or the PC slept/rebooted)') }
  else { $E.Add("Status:     $status") }
  $E.Add(("Parameters: IntervalSec={0}; Hours={1}; Download={2} bytes; KeepAwake={3}; xray={4}; links={5}" -f $IntervalSec, $(if ($Hours -gt 0) { $Hours } else { 'until stopped' }), $DownloadBytes, $awake, $xrayVersion, @($links).Count))
  $E.Add('')
  $E.Add('---- Results ----')
  $n = $cycles.Count
  $dirOk = @($cycles | Where-Object { $_.direct }).Count
  $E.Add(("Cycles: {0}. Office line (direct ya.ru) OK in {1} of {2} ({3}%)." -f $n, $dirOk, $n, $(if ($n) { [math]::Round(100 * $dirOk / $n, 1) } else { 0 })))
  $gaps = 0; $gapSec = 0.0
  for ($i = 1; $i -lt $n; $i++) { $d = ($cycles[$i].t - $cycles[$i - 1].t).TotalSeconds; if ($d -gt 2.5 * $IntervalSec) { $gaps++; $gapSec += $d } }
  $E.Add(("Gaps (no cycle for over {0} min; PC asleep or frozen): {1}, total {2}" -f [math]::Round(2.5 * $IntervalSec / 60, 1), $gaps, (Fmt-Dur $gapSec)))
  $eveCycles = @($cycles | Where-Object { Is-Evening $_.t }).Count
  $eveSec = $eveCycles * $IntervalSec
  $E.Add(("Evening coverage (19:00-23:00 local): about {0}" -f (Fmt-Dur $eveSec)))
  $E.Add('')
  $E.Add('Per link (OK = test page + blocked site + 1 MB download all passed in that cycle;')
  $E.Add('"line-adjusted" leaves out cycles in which the office line itself was down):')
  foreach ($k in @($stats.Keys | Sort-Object)) {
    $s = $stats[$k]
    $pct = $(if ($s.n) { [math]::Round(100 * $s.ok / $s.n, 1) } else { 0 })
    $pctA = $(if ($s.nAdj) { [math]::Round(100 * $s.okAdj / $s.nAdj, 1) } else { 0 })
    $pctE = $(if ($s.eveN) { [math]::Round(100 * $s.eveOk / $s.eveN, 1) } else { 0 })
    $med = '-'
    if ($s.mbps.Count) { $v = @($s.mbps | Sort-Object); $med = $v[[int][math]::Floor($v.Count / 2)] }
    $verdict = 'NOT YET (needs 3 h including 1 h of evening)'
    if ($s.nAdj -gt 0 -and ($s.nAdj * $IntervalSec) -ge 3 * 3600 -and $eveSec -ge 3600) { $verdict = $(if ($pctA -ge 97 -and ($s.worst * $IntervalSec) -lt 3600) { 'PASS' } else { 'FAIL' }) }
    elseif ($s.nAdj -ge 8 -and $pctA -lt 50) { $verdict = 'FAILING (under 50% so far)' }
    $E.Add(("  {0}" -f $k))
    $E.Add(("     {0}; {1}" -f $s.desc, $s.ipNote))
    $E.Add(("     cycles {0}: OK {1}, partial {2}, failed {3} -> {4}% (line-adjusted {5}%), evening {6}%" -f $s.n, $s.ok, $s.part, $s.fail, $pct, $pctA, $pctE))
    $E.Add(("     longest outage {0}; proxy restarts {1}; median speed {2} Mbit/s" -f (Fmt-Dur ($s.worst * $IntervalSec)), $s.restarts, $med))
    $E.Add(("     VERDICT: {0}" -f $verdict))
  }
  $E.Add('')
  $E.Add('---- Events ----')
  if ($events.Count -eq 0) { $E.Add('(none)') } else { foreach ($evLine in $events) { $E.Add($evLine) } }
  $E.Add('')
  $E.Add('---- Cycles (time, cycle, direct, then per link: test page/blocked site/download, Mbit/s) ----')
  foreach ($c in $cycles) { $E.Add($c.line) }
  $E.Add('')
  $E.Add('---- Errors during run (includes ones the script handled; for diagnosis) ----')
  $errGroups = @($Error | Group-Object { (($_.Exception.Message -replace '\s+', ' ').Trim()) } | Sort-Object Count -Descending | Select-Object -First 15)
  if ($errGroups.Count -eq 0) { $E.Add('(none)') } else { foreach ($g in $errGroups) { $E.Add(('- [{0}x] {1}' -f $g.Count, $g.Name)) } }
  $E.Add('==== END ====')
  return $E
}
function Save-Evidence {
  try {
    $tmp = $EvFile + '.tmp'
    (Build-Evidence) | Out-File $tmp -Encoding UTF8
    if (Test-Path $EvFile) { Remove-Item $EvFile -Force }
    Move-Item $tmp $EvFile -Force
  } catch {
    # Never silent: an evidence file that is not written is the worst failure of this script.
    if (-not $script:saveWarned) { Write-Host ('WARNING: could not write the evidence file: ' + $_.Exception.Message) -ForegroundColor Red; $script:saveWarned = $true }
  }
}

# ---------------- run ----------------
$Error.Clear()
try {
  try { $Host.UI.RawUI.WindowTitle = ('RU-PROBE MONITOR - started {0} - do not close' -f $started.ToString('HH:mm')) } catch { }
  if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe is missing.' }
  if (-not (Test-Path $XrayPath)) { throw "xray.exe not found at $XrayPath (antivirus? Run 1-RUN-TUNNEL-TEST.cmd first, it downloads it)." }
  $xrayVersion = ((& $XrayPath version 2>$null) | Select-Object -First 1)
  if (-not $xrayVersion) { throw 'xray.exe does not start (blocked by policy or antivirus?).' }
  if (Test-Path $ServicesFile) {
    $groupA = @(Get-Content $ServicesFile | ForEach-Object { $p = $_.Trim() -split '\s+', 3; if ($p.Count -ge 2 -and $p[0] -eq 'A' -and $p[1] -match '^https?://') { $p[1] } })
  }
  if ($groupA.Count -eq 0) { $groupA = @('https://www.youtube.com/') }
  if ($onWindows) {
    try {
      Add-Type -Namespace RuProbe -Name Power -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);' -ErrorAction Stop
      [void][RuProbe.Power]::SetThreadExecutionState([uint32]2147483649)   # ES_CONTINUOUS + ES_SYSTEM_REQUIRED
      $awake = $true
    } catch { Add-Event 'Could not keep the PC awake (restricted PowerShell).' }
  }
  [void](Load-Links)
  if (@($links).Count -eq 0) { throw 'No vless:// links in links.txt. Paste the lines from your password manager, save, start again.' }

  Write-Host ''
  Write-Host '=================================================================' -ForegroundColor Cyan
  Write-Host (' RU-PROBE MONITOR v{0}   started {1}' -f $ScriptVersion, $started.ToString('yyyy-MM-dd HH:mm')) -ForegroundColor Cyan
  Write-Host '=================================================================' -ForegroundColor Cyan
  Write-Host (' Evidence file (updated every cycle): evidence\{0}' -f (Split-Path $EvFile -Leaf))
  Write-Host (' One line every {0:N1} minutes:  + all OK   ~ partly   x failed' -f ($IntervalSec / 60))
  Write-Host ' To stop: 3-STOP-MONITOR.cmd or Ctrl+C. Leave Remote Desktop with X, do NOT sign out.'
  if ($staleNote) { Write-Host (' Note: ' + $staleNote + '.') -ForegroundColor Yellow }
  Write-Host ''
  Add-Event ("Monitor started. Keep-awake: {0}" -f $awake)
  Save-Evidence

  $endAt = $(if ($Hours -gt 0) { $started.AddHours($Hours) } else { [datetime]::MaxValue })
  $cycleNo = 0
  while ($true) {
    $cycleNo++
    $t0 = Get-Date
    if (Load-Links) { Write-Host ('{0}  links.txt changed: now {1} link(s)' -f $t0.ToString('HH:mm'), @($links).Count) -ForegroundColor Yellow }
    $d = Invoke-Curl @() $DirectUrl 12
    $directOk = ($d.exit -eq 0 -and $d.http -match '^[1-5]\d\d$')
    $aUrl = $groupA[($cycleNo - 1) % $groupA.Count]
    $parts = @(); $marks = @()
    foreach ($L in $links) {
      $px = $procs[$L.name]; $st = $stats[$L.name]
      if ($px.proc.HasExited) {
        $st.restarts++; Add-Event ("{0}: local xray had exited (code {1}); restarted" -f $L.name, $px.proc.ExitCode)
        $px = Start-Proxy $L $px.idx; $procs[$L.name] = $px
      }
      $ex = @('--socks5-hostname', ("127.0.0.1:{0}" -f $px.port))
      $r1 = Invoke-Curl $ex $TestUrl 15
      $ok1 = ($r1.exit -eq 0 -and $r1.http -eq '204')
      $r2 = Invoke-Curl $ex $aUrl 15
      $ok2 = ($r2.exit -eq 0 -and $r2.http -match '^[1-5]\d\d$')   # any HTTP answer = the site was reached; censorship shows as timeout/reset
      $r3 = Invoke-Curl $ex $DownUrl 40
      $ok3 = ($r3.exit -eq 0 -and $r3.bytes -ge $DownloadBytes)
      $nOk = @($ok1, $ok2, $ok3 | Where-Object { $_ }).Count
      $mark = $(if ($nOk -eq 3) { '+' } elseif ($nOk -gt 0) { '~' } else { 'x' })
      $st.n++
      if ($nOk -eq 3) { $st.ok++ } elseif ($nOk -gt 0) { $st.part++ } else { $st.fail++ }
      if ($directOk) { $st.nAdj++; if ($nOk -eq 3) { $st.okAdj++ } }
      if (Is-Evening $t0) { $st.eveN++; if ($nOk -eq 3) { $st.eveOk++ } }
      if ($nOk -eq 0 -and $directOk) { $st.streak++; if ($st.streak -gt $st.worst) { $st.worst = $st.streak } } elseif ($nOk -gt 0) { $st.streak = 0 }
      if ($ok3) { $st.mbps.Add($r3.mbps) }
      $parts += ('{0}={1}/{2}/{3},{4}' -f $L.name, $(if ($ok1) { 'ok' } else { "e$($r1.exit)h$($r1.http)" }), $(if ($ok2) { 'ok' } else { "e$($r2.exit)h$($r2.http)" }), $(if ($ok3) { 'ok' } else { "$($r3.bytes)B" }), $r3.mbps)
      $short = $L.name; if ($short.Length -gt 12) { $short = $short.Substring(0, 12) }
      $pct = [math]::Round(100 * $st.ok / $st.n)
      $marks += ('{0} {1} {2,3}%' -f $short, $mark, $pct)
    }
    $cycles.Add([pscustomobject]@{ t = $t0; direct = $directOk; line = ('{0} #{1} direct={2} {3}' -f $t0.ToString('s'), $cycleNo, $(if ($directOk) { 'ok' } else { "e$($d.exit)h$($d.http)" }), ($parts -join ' ')) })
    $line = ('{0}  #{1,-4} {2}  line {3}  | up {4}' -f $t0.ToString('HH:mm'), $cycleNo, ($marks -join '  '), $(if ($directOk) { '+' } else { 'x' }), (Fmt-Dur ((Get-Date) - $started).TotalSeconds))
    Write-Host $line
    Save-Evidence

    if ((Get-Date) -ge $endAt) { $status = 'COMPLETED (planned duration reached)'; break }
    $next = $t0.AddSeconds($IntervalSec)
    $stopNow = $false
    while ((Get-Date) -lt $next) {
      if (Test-Path $StopRequest) { $stopNow = $true; break }
      Start-Sleep -Seconds 1
    }
    if ($stopNow -or (Test-Path $StopRequest)) { $status = 'STOPPED (by 3-STOP-MONITOR)'; Add-Event 'Stop requested by 3-STOP-MONITOR.'; break }
  }
} catch {
  $status = 'FAILED: ' + $_.Exception.Message
  Add-Event ('ERROR: ' + $_.Exception.Message)
  Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
} finally {
  if ($status -eq 'RUNNING') { $status = 'STOPPED (Ctrl+C or window closed)' }
  Stop-Proxies
  if ($awake) { try { [void][RuProbe.Power]::SetThreadExecutionState([uint32]2147483648) } catch { } }
  Get-ChildItem $WorkDir -Filter 'client-*.json' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
  Save-Evidence
  try { if ($lockStream) { $lockStream.Close() }; Remove-Item $LockFile -Force -ErrorAction SilentlyContinue } catch { }
  Remove-Item $StopRequest -Force -ErrorAction SilentlyContinue
  Write-Host ''
  Write-Host "Status: $status"
  Write-Host "EVIDENCE FILE TO SEND BACK: $EvFile"
}
