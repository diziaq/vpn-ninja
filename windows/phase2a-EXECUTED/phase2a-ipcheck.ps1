<#
.SYNOPSIS
  Phase 2a: is the IP address of a newly rented server usable from this Russian line?
  Run right after renting, before any VPN setup. 3-5 minutes per server.

.DESCRIPTION
  Read-only on this PC. Expects the temporary test web server to be running on the
  rented server (one command from the instructions); it serves /test.bin on ports 80 and 443.

  For each server in servers.txt:
    - TCP connect to ports 22, 80, 443 (3 tries each)
    - HTTP download on port 80 (3 attempts, 10 s apart)
    - HTTPS download on port 443 without a server name (SNI) (3 attempts)
    - HTTPS download on port 443 with a neutral server name (3 attempts)
  Each download is classified OK / SLOW / FREEZE / BLOCKED / NO-TEST-SERVER.

  EVIDENCE (send this file back):
    evidence\EVIDENCE-phase2a-ipcheck-<timestamp>.txt
  Written at the end of every run, also on failure or Ctrl+C. Server IPs appear in it.

  Run from a normal (non-admin) PowerShell window:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\phase2a-ipcheck.ps1
#>
[CmdletBinding()]
param(
  [string]$ServersFile = '',
  [int]$MaxTime = 25
)

$ScriptVersion = '1.0'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
if (-not $PSScriptRoot) { Write-Host 'Run this as a file (-File .\phase2a-ipcheck.ps1), not by pasting it.'; exit 1 }
if (-not $ServersFile) { $ServersFile = Join-Path $PSScriptRoot 'servers.txt' }
$Error.Clear()

$started = Get-Date
$stamp   = $started.ToString('yyyyMMdd-HHmmss')
$RunDir  = Join-Path $PSScriptRoot "runs\phase2a-ipcheck-$stamp"
$EvDir   = Join-Path $PSScriptRoot 'evidence'
$EvFile  = Join-Path $EvDir "EVIDENCE-phase2a-ipcheck-$stamp.txt"
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $EvDir -Force | Out-Null

# ---------- helpers ----------
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
function Get-SockErr($err) {
  $e = $err.Exception
  while ($e) {
    if ($e -is [System.Net.Sockets.SocketException]) { return [string]$e.SocketErrorCode }
    $e = $e.InnerException
  }
  return $err.Exception.GetType().Name
}
function Test-Tcp([string]$HostName, [int]$Port, [int]$TimeoutMs = 6000) {
  $client = $null
  try {
    $client = New-Object System.Net.Sockets.TcpClient
    $iar = $client.BeginConnect($HostName, $Port, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return 'TIMEOUT' }
    try { $client.EndConnect($iar); return 'OPEN' } catch { return (Get-SockErr $_) }
  } catch { return (Get-SockErr $_) }
  finally { if ($client) { $client.Close() } }
}
function To-Num([string]$s) {
  $d = 0.0
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
  return 0.0
}

$curlOk = [bool](Get-Command curl.exe -ErrorAction SilentlyContinue)
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

function Invoke-Download([string]$Url, [string[]]$Extra) {
  $cargs = @('-s', '-k', '-o', 'NUL', '-m', "$MaxTime", '--connect-timeout', '8', '-A', $UA)
  if ($Extra) { $cargs += $Extra }
  $cargs += @('-w', '%{http_code}|%{size_download}|%{speed_download}|%{time_connect}|%{time_appconnect}|%{time_total}', $Url)
  $raw  = (& curl.exe @cargs 2>$null) -join ''
  $exit = $LASTEXITCODE
  $f = $raw -split '\|'
  while ($f.Count -lt 6) { $f += '' }
  $bytes = [int64](To-Num $f[1])
  $http = $f[0]
  $class = 'BLOCKED'
  if ($exit -eq 0 -and $http -eq '200' -and $bytes -ge 1000000) { $class = 'OK' }
  elseif ($exit -eq 0 -and $http -match '^[45]\d\d$') { $class = 'NO-TEST-FILE' }
  elseif ($exit -eq 7 -or ($exit -eq 0 -and $bytes -lt 1000000 -and $http -eq '200')) { $class = $(if ($exit -eq 7) { 'NO-TEST-SERVER-OR-BLOCKED' } else { 'FILE-TOO-SMALL' }) }
  elseif ($bytes -ge 1000000) { $class = 'OK' }
  elseif ($bytes -ge 65536) { $class = 'SLOW' }
  elseif ($bytes -gt 0) { $class = 'FREEZE' }
  $detail = switch ($exit) { 0 { "HTTP_$http" } 7 { 'CONNECT_FAIL' } 28 { 'TIMEOUT' } 35 { 'TLS_FAIL' } 52 { 'EMPTY_REPLY' } 56 { 'RESET' } default { "CURL_EXIT_$exit" } }
  [pscustomobject]@{ class = $class; detail = $detail; bytes = $bytes; mbps = [math]::Round((To-Num $f[2]) * 8 / 1e6, 1)
                     tConnect = $f[3]; tTls = $f[4]; tTotal = $f[5] }
}

$MachineId = Get-ShortHash ($env:COMPUTERNAME + '|' + $env:USERDOMAIN)
$RunId     = "phase2a-ipcheck-$stamp-$MachineId"
$summary = New-Object System.Collections.Generic.List[string]
$console = New-Object System.Collections.Generic.List[string]
$rows    = New-Object System.Collections.Generic.List[object]
function Log([string]$line) { $console.Add($line); Write-Host $line }
function Say([string]$line) { $summary.Add($line); Log $line }

Log ''
Log "Phase 2a server IP check v$ScriptVersion. Run ID: $RunId"
Log 'About 3-5 minutes per server. Leave the window open.'
Log "Evidence file will be: $EvFile"
Log ''

$status = 'STOPPED (interrupted before completion)'
$servers = @()
try {
  if (-not $curlOk) { throw 'curl.exe is missing.' }
  if (-not (Test-Path $ServersFile)) { throw "servers.txt not found at $ServersFile" }
  $servers = @(Get-Content $ServersFile | Where-Object { $_ -and ($_.Trim() -notmatch '^#') -and ($_ -notmatch 'YOUR-') } | ForEach-Object {
    $p = $_.Trim() -split '\s+', 3
    if ($p.Count -ge 2 -and $p[1] -match '^\d+\.\d+\.\d+\.\d+$') { [pscustomobject]@{ label = $p[0]; ip = $p[1]; note = $(if ($p.Count -ge 3) { $p[2] } else { '' }) } }
  })
  if ($servers.Count -eq 0) { throw 'No server IPs in servers.txt (replace YOUR-SERVER-A-IP with the real IPv4 address).' }

  foreach ($s in $servers) {
    try {
      Say ''
      Say ("== Server {0}: {1} ({2}) ==" -f $s.label, $s.ip, $s.note)

      $tcp = foreach ($port in @(22, 80, 443)) {
        $r = @(1..3 | ForEach-Object { Test-Tcp $s.ip $port })
        $ok = @($r | Where-Object { $_ -eq 'OPEN' }).Count
        $rows.Add([pscustomobject]@{ server = $s.label; ip = $s.ip; test = "tcp-$port"; attempt = '1-3'; class = "$ok/3 OPEN"; detail = ($r -join ','); bytes = ''; mbps = ''; tConnect = ''; tTls = ''; tTotal = '' })
        "${port}: $ok/3 open"
      }
      Say ('TCP connect: ' + ($tcp -join '; '))

      $variants = @(
        @{ name = 'http-80';        url = "http://$($s.ip)/test.bin";  extra = @() },
        @{ name = 'https-443-noSNI'; url = "https://$($s.ip)/test.bin"; extra = @() },
        @{ name = 'https-443-SNI';  url = 'https://www.example.com/test.bin'; extra = @('--resolve', "www.example.com:443:$($s.ip)") }
      )
      foreach ($v in $variants) {
        $classes = @()
        for ($n = 1; $n -le 3; $n++) {
          Log ("  {0} attempt {1}/3 ..." -f $v.name, $n)
          $d = Invoke-Download $v.url $v.extra
          $classes += $d.class
          $rows.Add([pscustomobject]@{ server = $s.label; ip = $s.ip; test = $v.name; attempt = $n; class = $d.class; detail = $d.detail
                                       bytes = $d.bytes; mbps = $d.mbps; tConnect = $d.tConnect; tTls = $d.tTls; tTotal = $d.tTotal })
          if ($n -lt 3) { Start-Sleep -Seconds 10 }
        }
        $okN = @($classes | Where-Object { $_ -eq 'OK' }).Count
        $last = @($rows | Where-Object { $_.server -eq $s.label -and $_.test -eq $v.name } | Select-Object -Last 1)[0]
        Say ("{0,-16} OK {1}/3   attempts: {2}   last: {3} bytes, {4} Mbit/s" -f $v.name, $okN, ($classes -join ', '), $last.bytes, $last.mbps)
      }

      $all = @($rows | Where-Object { $_.server -eq $s.label -and $_.test -like 'http*' })
      $freeze = @($all | Where-Object { $_.class -eq 'FREEZE' }).Count
      $https  = @($all | Where-Object { $_.test -like 'https*' -and $_.class -eq 'OK' }).Count
      $noSrv  = @($all | Where-Object { $_.class -like 'NO-TEST*' -or $_.class -eq 'FILE-TOO-SMALL' }).Count
      $verdict =
        if ($noSrv -ge 6) { 'NO TEST SERVER (start the test command on the server, then re-run)' }
        elseif ($freeze -gt 0) { 'FROZEN: this IP is throttled (ask for another IP or use another provider)' }
        elseif ($https -ge 5) { 'PASS: IP usable, continue with VPN setup' }
        elseif ($https -ge 3) { 'UNSTABLE: works sometimes; re-run later before deciding' }
        else { 'BLOCKED: this IP is not usable from this line' }
      Say ("Verdict for server {0}: {1}" -f $s.label, $verdict)
    } catch { Say ("ERROR for server {0}: {1}" -f $s.label, $_.Exception.Message) }
  }
  $status = 'COMPLETED'
} catch {
  $status = 'FAILED'
  Say ('ERROR (run aborted): ' + $_.Exception.Message)
} finally {
  try { $rows | Export-Csv -Path (Join-Path $RunDir 'ipcheck.csv') -NoTypeInformation -Encoding UTF8 } catch { }
  try { $console | Out-File (Join-Path $RunDir 'console.log') -Encoding UTF8 } catch { }

  $finished = Get-Date
  $ev = New-Object System.Collections.Generic.List[string]
  $ev.Add('==== RU-PROBE EVIDENCE ====')
  $ev.Add("Script:     phase2a-ipcheck.ps1 v$ScriptVersion")
  $ev.Add("Run ID:     $RunId")
  $ev.Add("Machine:    $MachineId (hash of computer name)")
  $ev.Add(("Started:    {0} local / {1} UTC" -f $started.ToString('s'), $started.ToUniversalTime().ToString('s')))
  $ev.Add(("Finished:   {0} local / {1} UTC ({2:N1} min)" -f $finished.ToString('s'), $finished.ToUniversalTime().ToString('s'), ($finished - $started).TotalMinutes))
  $ev.Add("Status:     $status")
  $ev.Add("Parameters: MaxTime=$MaxTime s; servers=" + (($servers | ForEach-Object { "$($_.label)=$($_.ip)" }) -join ', '))
  $ev.Add('')
  $ev.Add('---- Results ----')
  foreach ($l in $summary) { $ev.Add($l) }
  $ev.Add('')
  $ev.Add('---- Detail ----')
  $fmt = '{0,-3} {1,-15} {2,-16} {3,-4} {4,-26} {5,-14} {6,9} {7,7} {8,8} {9,8} {10,8}'
  $ev.Add(($fmt -f 'srv', 'ip', 'test', '#', 'class', 'detail', 'bytes', 'Mbit/s', 'connect', 'tls', 'total'))
  foreach ($r in $rows) { $ev.Add(($fmt -f $r.server, $r.ip, $r.test, $r.attempt, $r.class, $r.detail, $r.bytes, $r.mbps, $r.tConnect, $r.tTls, $r.tTotal)) }
  $ev.Add('')
  $ev.Add('---- Errors during run (includes ones the script handled; for diagnosis) ----')
  $errGroups = @($Error | Group-Object { (($_.Exception.Message -replace '\s+', ' ').Trim()) } | Sort-Object Count -Descending | Select-Object -First 15)
  if ($errGroups.Count -eq 0) { $ev.Add('(none)') } else { foreach ($g in $errGroups) { $ev.Add(('- [{0}x] {1}' -f $g.Count, $g.Name)) } }
  $ev.Add('')
  $ev.Add('---- Raw files kept on the PC (send only if asked) ----')
  foreach ($f in @('ipcheck.csv', 'console.log')) {
    $p = Join-Path $RunDir $f
    if (Test-Path $p) { $ev.Add(("runs\phase2a-ipcheck-{0}\{1}  sha256 {2}" -f $stamp, $f, (Get-Sha256 $p))) }
  }
  $ev.Add('==== END ====')
  $ev | Out-File $EvFile -Encoding UTF8

  Write-Host ''
  Write-Host "Status: $status"
  Write-Host "EVIDENCE FILE TO SEND BACK: $EvFile"
}
