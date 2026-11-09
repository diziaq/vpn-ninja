<#
.SYNOPSIS
  Phase 2b: do the VPN protocols on our server get through this Russian line?
  No admin rights, no drivers: uses the portable Xray client as a local proxy. 10-15 minutes.

.DESCRIPTION
  Reads the VPN links (vless://...) from links.txt. For each link it tries several browser
  fingerprints. For every variant it starts xray.exe as a local proxy on 127.0.0.1 and checks:
    - exit IP     traffic really leaves through the server
    - series      repeated requests to a site blocked in Russia (catches delayed blocking)
    - download    20 MB through the tunnel (catches the ~16 KB freeze, measures speed)
    - services    the services.txt list through the tunnel
  xray.exe is downloaded once from the official GitHub release into .\bin if it is missing.

  EVIDENCE (send this file back):
    evidence\EVIDENCE-phase2b-tunnel-<timestamp>.txt
  Secrets (client ID, keys) are masked in it. Written even on failure or Ctrl+C.

  Run from a normal (non-admin) PowerShell window:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\phase2b-tunnel.ps1
#>
[CmdletBinding()]
param(
  [string]$LinksFile = '',
  [string]$ServicesFile = '',
  [string]$XrayPath = '',
  [int]$SeriesCount = 6,
  [int]$SeriesGap = 10
)

$ScriptVersion = '1.0'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
if (-not $PSScriptRoot) { Write-Host 'Run this as a file (-File .\phase2b-tunnel.ps1), not by pasting it.'; exit 1 }
if (-not $LinksFile)    { $LinksFile    = Join-Path $PSScriptRoot 'links.txt' }
if (-not $ServicesFile) { $ServicesFile = Join-Path $PSScriptRoot 'services.txt' }
$onWindows = ($env:OS -eq 'Windows_NT')
if (-not $XrayPath) { $XrayPath = Join-Path $PSScriptRoot $(if ($onWindows) { 'bin\xray.exe' } else { 'bin/xray' }) }
$Error.Clear()

$started = Get-Date
$stamp   = $started.ToString('yyyyMMdd-HHmmss')
$RunDir  = Join-Path $PSScriptRoot "runs\phase2b-tunnel-$stamp"
$EvDir   = Join-Path $PSScriptRoot 'evidence'
$EvFile  = Join-Path $EvDir "EVIDENCE-phase2b-tunnel-$stamp.txt"
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $EvDir -Force | Out-Null

# ---------- helpers ----------
function Get-ShortHash([string]$s) {
  try { $sha = [System.Security.Cryptography.SHA256]::Create(); $b = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($s)); return (($b[0..3] | ForEach-Object { $_.ToString('x2') }) -join '') } catch { return 'unknown' }
}
function Get-Sha256([string]$path) {
  try { return (Get-FileHash -Algorithm SHA256 -Path $path -ErrorAction Stop).Hash.ToLower() } catch { return 'n/a' }
}
function Test-Tcp([string]$HostName, [int]$Port, [int]$TimeoutMs = 1500) {
  $c = $null
  try { $c = New-Object System.Net.Sockets.TcpClient; $iar = $c.BeginConnect($HostName, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return $false }; $c.EndConnect($iar); return $true }
  catch { return $false } finally { if ($c) { $c.Close() } }
}
function To-Num([string]$s) {
  $d = 0.0
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
  return 0.0
}
function Write-NoBom([string]$path, [string]$text) { [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false))) }
function Mask([string]$s) { if (-not $s) { return '' }; if ($s.Length -le 8) { return '****' }; return ($s.Substring(0, 4) + '...' + $s.Substring($s.Length - 4)) }

$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'
function Invoke-ViaProxy([int]$Port, [string]$Url, [int]$MaxTime) {
  $cargs = @('-s', '-o', 'NUL', '-m', "$MaxTime", '--connect-timeout', '10', '-A', $UA, '--socks5-hostname', "127.0.0.1:$Port",
             '-w', '%{http_code}|%{size_download}|%{speed_download}|%{time_total}', $Url)
  if (-not $onWindows) { $cargs[2] = '/dev/null' }
  $raw = (& curl.exe @cargs 2>$null) -join ''
  $exit = $LASTEXITCODE
  $f = $raw -split '\|'; while ($f.Count -lt 4) { $f += '' }
  [pscustomobject]@{ exit = $exit; http = $f[0]; bytes = [int64](To-Num $f[1]); mbps = [math]::Round((To-Num $f[2]) * 8 / 1e6, 1); total = $f[3] }
}
function Get-ViaProxyText([int]$Port, [string]$Url) {
  return ((& curl.exe -s -m 15 --socks5-hostname "127.0.0.1:$Port" $Url 2>$null) -join '').Trim()
}

function Parse-Vless([string]$line) {
  $u = [System.Uri]$line.Trim()
  $q = @{}
  foreach ($kv in ($u.Query.TrimStart('?') -split '&')) {
    if (-not $kv) { continue }
    $p = $kv -split '=', 2
    $q[$p[0]] = [System.Uri]::UnescapeDataString($(if ($p.Count -gt 1) { $p[1] } else { '' }))
  }
  [pscustomobject]@{
    name = [System.Uri]::UnescapeDataString($u.Fragment.TrimStart('#')); id = [System.Uri]::UnescapeDataString($u.UserInfo)
    host = $u.Host; port = $u.Port; type = $(if ($q['type']) { $q['type'] } else { 'tcp' }); flow = [string]$q['flow']
    sni = [string]$q['sni']; pbk = [string]$q['pbk']; sid = [string]$q['sid']; path = [string]$q['path']; mode = $(if ($q['mode']) { $q['mode'] } else { 'auto' })
  }
}

function New-ClientConfig($L, [string]$Fp, [int]$Port) {
  $stream = [ordered]@{
    network = $L.type; security = 'reality'
    realitySettings = [ordered]@{ serverName = $L.sni; fingerprint = $Fp; publicKey = $L.pbk; password = $L.pbk; shortId = $L.sid; spiderX = '' }
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

$MachineId = Get-ShortHash ($env:COMPUTERNAME + '|' + $env:USERDOMAIN)
$RunId     = "phase2b-tunnel-$stamp-$MachineId"
$summary = New-Object System.Collections.Generic.List[string]
$console = New-Object System.Collections.Generic.List[string]
$rows    = New-Object System.Collections.Generic.List[object]
function Log([string]$line) { $console.Add($line); Write-Host $line }
function Say([string]$line) { $summary.Add($line); Log $line }

Log ''
Log "Phase 2b tunnel test v$ScriptVersion. Run ID: $RunId"
Log 'Takes 10-15 minutes. Leave the window open.'
Log "Evidence file will be: $EvFile"
Log ''

$status = 'STOPPED (interrupted before completion)'
$proc = $null
$links = @()
$xrayVersion = 'n/a'
try {
  if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe is missing.' }

  # ---------- 1. Xray client ----------
  Say '== 1. Portable Xray client =='
  if (-not (Test-Path $XrayPath)) {
    $bin = Split-Path $XrayPath -Parent
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    $zip = Join-Path $bin 'xray.zip'
    Log 'Downloading Xray-windows-64.zip from the official GitHub release ...'
    & curl.exe -s -L -m 180 -o $zip 'https://github.com/XTLS/Xray-core/releases/latest/download/Xray-windows-64.zip' 2>$null
    if ((Test-Path $zip) -and ((Get-Item $zip).Length -gt 1000000)) {
      Expand-Archive -Path $zip -DestinationPath $bin -Force
      Remove-Item $zip -Force -ErrorAction SilentlyContinue
    } else { throw 'Could not download Xray from github.com. Copy Xray-windows-64.zip into the bin folder manually and unzip it there.' }
  }
  Start-Sleep -Seconds 2
  if (-not (Test-Path $XrayPath)) { throw 'xray.exe disappeared after download (antivirus?). This itself is a result: send this evidence file.' }
  $xrayVersion = ((& $XrayPath version 2>$null) | Select-Object -First 1)
  if (-not $xrayVersion) { throw 'xray.exe does not start (blocked by policy or antivirus?).' }
  Say "Xray client: $xrayVersion"

  # ---------- 2. Links ----------
  Say ''
  Say '== 2. VPN links =='
  if (-not (Test-Path $LinksFile)) { throw "links.txt not found at $LinksFile" }
  $links = @(Get-Content $LinksFile | Where-Object { $_ -match '^\s*vless://' } | ForEach-Object { Parse-Vless $_ })
  if ($links.Count -eq 0) { throw 'No vless:// links in links.txt. Paste the two lines printed by the server script.' }
  foreach ($L in $links) { Say ("{0}: {1}:{2} type={3} flow={4} sni={5} id={6}" -f $L.name, $L.host, $L.port, $L.type, $(if ($L.flow) { $L.flow } else { '-' }), $L.sni, (Mask $L.id)) }

  # ---------- 3. Service list ----------
  $services = @()
  if (Test-Path $ServicesFile) {
    $services = @(Get-Content $ServicesFile | Where-Object { $_ -and ($_.Trim() -notmatch '^#') } | ForEach-Object {
      $p = $_.Trim() -split '\s+', 3
      if ($p.Count -ge 2 -and $p[0] -match '^[XABC]$' -and $p[1] -match '^https?://') { [pscustomobject]@{ group = $p[0].ToUpper(); url = $p[1] } }
    })
  }

  # ---------- 4. Variants ----------
  $variants = @()
  foreach ($L in $links) {
    $fps = if ($L.type -eq 'xhttp') { @('chrome', 'firefox') } else { @('chrome', 'firefox', 'safari') }
    foreach ($fp in $fps) { $variants += [pscustomobject]@{ link = $L; fp = $fp } }
  }
  $port = 10800
  $vi = 0
  foreach ($v in $variants) {
    $vi++; $port++
    $L = $v.link
    $vname = "$($L.name) fp=$($v.fp)"
    Say ''
    Say ("== 3.{0} Variant: {1} ==" -f $vi, $vname)
    try {
      $cfgPath = Join-Path $RunDir ("client-{0}.json" -f $vi)
      Write-NoBom $cfgPath (New-ClientConfig $L $v.fp $port)
      $outLog = Join-Path $RunDir ("xray-{0}.out.log" -f $vi)
      $errLog = Join-Path $RunDir ("xray-{0}.err.log" -f $vi)
      $proc = Start-Process -FilePath $XrayPath -ArgumentList @('run', '-c', "`"$cfgPath`"") -PassThru -NoNewWindow -RedirectStandardOutput $outLog -RedirectStandardError $errLog
      $up = $false
      for ($t = 0; $t -lt 20; $t++) { if (Test-Tcp '127.0.0.1' $port 500) { $up = $true; break }; Start-Sleep -Milliseconds 500 }
      if (-not $up) { Say 'Local proxy did not start (see xray log).'; $rows.Add([pscustomobject]@{ variant = $vname; test = 'start'; result = 'FAIL'; detail = 'xray did not listen' }); continue }

      # exit IP
      $exitIp = Get-ViaProxyText $port 'https://api.ipify.org'
      $ipOk = ($exitIp -eq $L.host)
      $rows.Add([pscustomobject]@{ variant = $vname; test = 'exit-ip'; result = $(if ($ipOk) { 'OK' } elseif ($exitIp) { 'OTHER' } else { 'FAIL' }); detail = $(if ($exitIp) { $exitIp } else { 'no answer' }) })
      Say ("Exit IP through tunnel: {0} ({1})" -f $(if ($exitIp) { $exitIp } else { 'no answer' }), $(if ($ipOk) { 'matches server' } else { 'PROBLEM' }))

      # series
      $okS = 0; $marks = @()
      for ($n = 1; $n -le $SeriesCount; $n++) {
        $r = Invoke-ViaProxy $port 'https://www.instagram.com/' 20
        $good = ($r.exit -eq 0 -and $r.http -match '^[23]')
        if ($good) { $okS++ }
        $marks += $(if ($good) { $r.http } else { "x$($r.exit)" })
        if ($n -lt $SeriesCount) { Start-Sleep -Seconds $SeriesGap }
      }
      $rows.Add([pscustomobject]@{ variant = $vname; test = 'series'; result = "$okS/$SeriesCount"; detail = ($marks -join ' ') })
      Say ("Series to instagram.com: {0}/{1} OK  [{2}]" -f $okS, $SeriesCount, ($marks -join ' '))

      # download
      $d = Invoke-ViaProxy $port 'https://speed.cloudflare.com/__down?bytes=20000000' 45
      $dClass = if ($d.exit -eq 0 -and $d.bytes -ge 19000000) { 'OK' } elseif ($d.bytes -ge 1000000) { 'SLOW' } elseif ($d.bytes -gt 0) { 'FREEZE' } else { 'FAIL' }
      $rows.Add([pscustomobject]@{ variant = $vname; test = 'download-20MB'; result = $dClass; detail = ("{0} bytes, {1} Mbit/s, exit {2}" -f $d.bytes, $d.mbps, $d.exit) })
      Say ("Download 20 MB: {0} ({1} bytes, {2} Mbit/s)" -f $dClass, $d.bytes, $d.mbps)

      # services
      $grp = @{}
      foreach ($s in $services) {
        $r = Invoke-ViaProxy $port $s.url 12
        $good = ($r.exit -eq 0 -and $r.http -match '^[23]')
        if (-not $grp.ContainsKey($s.group)) { $grp[$s.group] = @(0, 0) }
        $grp[$s.group][1]++; if ($good) { $grp[$s.group][0]++ }
        $rows.Add([pscustomobject]@{ variant = $vname; test = "svc-$($s.group)"; result = $(if ($good) { 'OK' } else { 'FAIL' }); detail = ("{0} {1}" -f $(if ($r.exit -eq 0) { "HTTP_$($r.http)" } else { "exit $($r.exit)" }), $s.url) })
      }
      $svcLine = (@('X', 'A', 'C', 'B') | Where-Object { $grp.ContainsKey($_) } | ForEach-Object { "$_ $($grp[$_][0])/$($grp[$_][1])" }) -join ', '
      Say ("Services through tunnel: {0}" -f $svcLine)

      $aOk = if ($grp.ContainsKey('A') -and $grp['A'][1] -gt 0) { $grp['A'][0] / $grp['A'][1] } else { 0 }
      $pass = $ipOk -and ($okS -ge ($SeriesCount - 1)) -and ($dClass -eq 'OK') -and ($aOk -ge 0.8)
      $verdict = if ($pass) { 'PASS' } elseif ($ipOk -and $okS -gt 0) { 'PARTIAL' } else { 'FAIL' }
      $rows.Add([pscustomobject]@{ variant = $vname; test = 'VERDICT'; result = $verdict; detail = '' })
      Say ("Variant verdict: {0}" -f $verdict)
      if ($verdict -ne 'PASS' -and (Test-Path $errLog)) {
        $tail = @(Get-Content $errLog -Tail 5 -ErrorAction SilentlyContinue) + @(Get-Content $outLog -Tail 5 -ErrorAction SilentlyContinue)
        foreach ($t in $tail) { if ($t) { Say ('   xray: ' + ($t -replace [regex]::Escape($L.id), (Mask $L.id))) } }
      }
    } catch { Say ("ERROR in variant {0}: {1}" -f $vname, $_.Exception.Message) }
    finally { if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch { } }; $proc = $null }
  }

  # ---------- 5. Overall ----------
  Say ''
  Say '== 4. Overall =='
  $verdicts = @($rows | Where-Object { $_.test -eq 'VERDICT' })
  foreach ($vv in $verdicts) { Say ("   {0,-40} {1}" -f $vv.variant, $vv.result) }
  $passN = @($verdicts | Where-Object { $_.result -eq 'PASS' }).Count
  Say ("Variants passing: {0} of {1}" -f $passN, $verdicts.Count)
  Say ("Protocol check for this server (part of Gate G2): {0}" -f $(if ($passN -ge 1) { 'PASS (at least one VLESS variant works; 24-hour soak still needed)' } else { 'NOT PASSED' }))
  $status = 'COMPLETED'
} catch {
  $status = 'FAILED'
  Say ('ERROR (run aborted): ' + $_.Exception.Message)
} finally {
  if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch { } }
  try { $rows | Export-Csv -Path (Join-Path $RunDir 'tunnel.csv') -NoTypeInformation -Encoding UTF8 } catch { }
  try { $console | Out-File (Join-Path $RunDir 'console.log') -Encoding UTF8 } catch { }
  # client configs contain secrets: remove them after the run
  Get-ChildItem $RunDir -Filter 'client-*.json' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

  $finished = Get-Date
  $ev = New-Object System.Collections.Generic.List[string]
  $ev.Add('==== RU-PROBE EVIDENCE ====')
  $ev.Add("Script:     phase2b-tunnel.ps1 v$ScriptVersion")
  $ev.Add("Run ID:     $RunId")
  $ev.Add("Machine:    $MachineId (hash of computer name)")
  $ev.Add(("Started:    {0} local / {1} UTC" -f $started.ToString('s'), $started.ToUniversalTime().ToString('s')))
  $ev.Add(("Finished:   {0} local / {1} UTC ({2:N1} min)" -f $finished.ToString('s'), $finished.ToUniversalTime().ToString('s'), ($finished - $started).TotalMinutes))
  $ev.Add("Status:     $status")
  $ev.Add("Parameters: SeriesCount=$SeriesCount; SeriesGap=$SeriesGap s; links=$(@($links).Count); xray=$xrayVersion")
  $ev.Add('')
  $ev.Add('---- Results ----')
  foreach ($l in $summary) { $ev.Add($l) }
  $ev.Add('')
  $ev.Add('---- Detail ----')
  foreach ($r in $rows) { $ev.Add(('{0,-40} {1,-14} {2,-8} {3}' -f $r.variant, $r.test, $r.result, $r.detail)) }
  $ev.Add('')
  $ev.Add('---- Errors during run (includes ones the script handled; for diagnosis) ----')
  $errGroups = @($Error | Group-Object { (($_.Exception.Message -replace '\s+', ' ').Trim()) } | Sort-Object Count -Descending | Select-Object -First 15)
  if ($errGroups.Count -eq 0) { $ev.Add('(none)') } else { foreach ($g in $errGroups) { $ev.Add(('- [{0}x] {1}' -f $g.Count, $g.Name)) } }
  $ev.Add('')
  $ev.Add('---- Raw files kept on the PC (send only if asked) ----')
  foreach ($f in @('tunnel.csv', 'console.log')) {
    $p = Join-Path $RunDir $f
    if (Test-Path $p) { $ev.Add(("runs\phase2b-tunnel-{0}\{1}  sha256 {2}" -f $stamp, $f, (Get-Sha256 $p))) }
  }
  $ev.Add('==== END ====')
  $ev | Out-File $EvFile -Encoding UTF8
  Write-Host ''
  Write-Host "Status: $status"
  Write-Host "EVIDENCE FILE TO SEND BACK: $EvFile"
}
