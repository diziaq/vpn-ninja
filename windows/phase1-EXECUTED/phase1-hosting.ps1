<#
.SYNOPSIS
  Phase 1 of the gated rollout plan: which hosting providers can this Russian line reach
  without blocking or the ~16 KB freeze? Plus a few line checks. 5-10 minutes.

.DESCRIPTION
  Read-only. Installs nothing and changes no settings. Downloads at most ~2 MB per test file
  (about 80 MB in total in the worst case).

  For every entry in providers.txt it downloads the first 2 MB of a public test file hosted
  in that provider's network and classifies the result:
    OK           2 MB arrived
    SLOW         some data arrived but less than 1 MB before the time limit
    FREEZE       stalled after a few KB (typical of the ~16 KB throttling)
    BLOCKED      no connection, TLS failure, reset or timeout with no data
    URL-BROKEN   server answered with an error or the name does not exist (test file moved)
  Entries that are not OK are retried once.

  EVIDENCE (send this file back):
    evidence\EVIDENCE-phase1-hosting-<timestamp>.txt
  Written at the end of every run, also on failure or Ctrl+C. Public IP masked.

  Run from a normal (non-admin) PowerShell window:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\phase1-hosting.ps1
#>
[CmdletBinding()]
param(
  [string]$ProvidersFile = '',
  [int]$MaxTime = 20,
  [int]$RangeBytes = 2097152
)

$ScriptVersion = '1.0'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
if (-not $PSScriptRoot) { Write-Host 'Run this as a file (-File .\phase1-hosting.ps1), not by pasting it.'; exit 1 }
if (-not $ProvidersFile) { $ProvidersFile = Join-Path $PSScriptRoot 'providers.txt' }
$Error.Clear()

$started = Get-Date
$stamp   = $started.ToString('yyyyMMdd-HHmmss')
$RunDir  = Join-Path $PSScriptRoot "runs\phase1-hosting-$stamp"
$EvDir   = Join-Path $PSScriptRoot 'evidence'
$EvFile  = Join-Path $EvDir "EVIDENCE-phase1-hosting-$stamp.txt"
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
    if ($e -is [System.Security.Authentication.AuthenticationException]) { return 'TLS_AUTH_FAILED' }
    if ($e -is [System.IO.IOException]) { return 'IO_RESET' }
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
function Get-TlsIssuer([string]$HostName, [int]$TimeoutMs = 8000) {
  $tcp = $null
  try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $iar = $tcp.BeginConnect($HostName, 443, $null, $null)
    if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { return 'TCP_TIMEOUT' }
    $tcp.EndConnect($iar)
    $tcp.ReceiveTimeout = $TimeoutMs; $tcp.SendTimeout = $TimeoutMs
    $cb  = [System.Net.Security.RemoteCertificateValidationCallback] { param($s, $c, $ch, $e) $true }
    $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, $cb)
    $ssl.AuthenticateAsClient($HostName, $null, [System.Security.Authentication.SslProtocols]::Tls12, $false)
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl.RemoteCertificate)
    $ssl.Dispose()
    return $cert.Issuer
  } catch { return ('TLS_ERROR ' + (Get-SockErr $_)) }
  finally { if ($tcp) { $tcp.Close() } }
}
function Resolve-A([string]$Name, [string]$Server = '') {
  try {
    $p = @{ Name = $Name; Type = 'A'; DnsOnly = $true; QuickTimeout = $true; ErrorAction = 'Stop' }
    if ($Server) { $p.Server = $Server }
    $r = Resolve-DnsName @p | Where-Object { $_.Type -eq 'A' } | Select-Object -ExpandProperty IPAddress
    if ($r) { return (($r | Select-Object -First 2) -join ' ') }
    return 'NO_A_RECORD'
  } catch { return 'FAIL' }
}
function Mask-Ip([string]$ip) {
  if ($ip -match '^(\d+\.\d+\.\d+)\.\d+$') { return "$($Matches[1]).x" }
  if ($ip -match ':') { return (($ip -split ':')[0..2] -join ':') + ':...' }
  return $ip
}
function To-Num([string]$s) {
  $d = 0.0
  if ([double]::TryParse($s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
  return 0.0
}

$curlOk = [bool](Get-Command curl.exe -ErrorAction SilentlyContinue)
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

# Download the first $RangeBytes of a file; -k because only transport matters here, not certificate trust.
function Invoke-Transfer([string]$Url) {
  $cargs = @('-s', '-k', '-L', '-o', 'NUL', '-m', "$MaxTime", '--connect-timeout', '8', '-A', $UA, '-r', "0-$($RangeBytes - 1)",
             '-w', '%{http_code}|%{size_download}|%{speed_download}|%{time_connect}|%{time_appconnect}|%{time_total}|%{remote_ip}', $Url)
  $raw  = (& curl.exe @cargs 2>$null) -join ''
  $exit = $LASTEXITCODE
  $f = $raw -split '\|'
  while ($f.Count -lt 7) { $f += '' }
  $bytes = [int64](To-Num $f[1])
  $http  = $f[0]
  $class = 'BLOCKED'
  if ($exit -eq 6) { $class = 'URL-BROKEN' }
  elseif ($exit -eq 0 -and $http -match '^(200|206)$' -and $bytes -ge 1000000) { $class = 'OK' }
  elseif ($exit -eq 0 -and $http -match '^(200|206)$') { $class = 'OK-SMALL-FILE' }
  elseif ($exit -eq 0 -and $http -match '^[345]\d\d$') { $class = 'URL-BROKEN' }
  elseif ($bytes -ge 1000000) { $class = 'OK' }
  elseif ($bytes -ge 65536) { $class = 'SLOW' }
  elseif ($bytes -gt 0) { $class = 'FREEZE' }
  $detail = switch ($exit) { 0 { "HTTP_$http" } 6 { 'DNS_FAIL' } 7 { 'CONNECT_FAIL' } 28 { 'TIMEOUT' } 35 { 'TLS_FAIL' } 52 { 'EMPTY_REPLY' } 56 { 'RESET' } default { "CURL_EXIT_$exit" } }
  [pscustomobject]@{
    class = $class; detail = $detail; http = $http; bytes = $bytes
    mbps = [math]::Round((To-Num $f[2]) * 8 / 1e6, 1)
    tConnect = $f[3]; tTls = $f[4]; tTotal = $f[5]; ip = $f[6]
  }
}

$MachineId = Get-ShortHash ($env:COMPUTERNAME + '|' + $env:USERDOMAIN)
$RunId     = "phase1-hosting-$stamp-$MachineId"
$summary = New-Object System.Collections.Generic.List[string]
$console = New-Object System.Collections.Generic.List[string]
$rows    = New-Object System.Collections.Generic.List[object]
function Log([string]$line) { $console.Add($line); Write-Host $line }
function Say([string]$line) { $summary.Add($line); Log $line }

Log ''
Log "Phase 1 hosting check v$ScriptVersion. Run ID: $RunId"
Log 'Takes 5-10 minutes. Leave the window open.'
Log "Evidence file will be: $EvFile"
Log ''

$status = 'STOPPED (interrupted before completion)'
$entries = @()
try {
  if (-not $curlOk) { throw 'curl.exe is missing; network checks cannot run.' }

  # ---------- 1. Line identity ----------
  try {
    Say '== 1. Line identity =='
    $geo = $null
    $oldEnc = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    foreach ($src in @('https://ipinfo.io/json', 'https://ifconfig.co/json', 'https://api.ip.sb/geoip')) {
      try {
        $raw = (& curl.exe -s -m 10 -A $UA $src 2>$null) -join "`n"
        if ($raw) { $j = $raw | ConvertFrom-Json -ErrorAction Stop; if ($j) { $geo = $j; break } }
      } catch { }
    }
    try { [Console]::OutputEncoding = $oldEnc } catch { }
    if ($geo) {
      $ip      = [string]$(if ($geo.ip) { $geo.ip } else { $geo.ip_addr })
      $country = [string]$(if ($geo.country_iso) { $geo.country_iso } elseif ($geo.country_code) { $geo.country_code } else { $geo.country })
      $org     = [string]$(if ($geo.org) { $geo.org } elseif ($geo.asn_org) { "AS$($geo.asn) $($geo.asn_org)" } elseif ($geo.isp) { "AS$($geo.asn) $($geo.isp)" } else { '' })
      Say ("Public IP {0} (masked); country {1}; city {2}; network {3}" -f (Mask-Ip $ip), $country, $geo.city, $org)
    } else { Say 'Public IP lookup failed on all sources.' }
  } catch { Say ('ERROR in section 1: ' + $_.Exception.Message) }

  # ---------- 2. Line checks ----------
  try {
    Say ''
    Say '== 2. Line checks =='
    $udp = foreach ($srv in @('1.1.1.1', '8.8.8.8', '77.88.8.8')) { "$srv=" + $(if ((Resolve-A 'example.com' $srv) -match '^\d') { 'OK' } else { 'FAIL' }) }
    Say ('Plain DNS over UDP 53 to public resolvers: ' + ($udp -join ', '))
    $ports = foreach ($pt in @(22, 80, 443, 2053, 8080, 8443)) { "$pt=" + (Test-Tcp 'portquiz.net' $pt) }
    Say ('Outbound TCP ports (portquiz.net): ' + ($ports -join ', '))
    $issuers = [ordered]@{}
    foreach ($h in @('www.microsoft.com', 'github.com', 'www.wikipedia.org', 'ya.ru')) { $issuers[$h] = Get-TlsIssuer $h }
    foreach ($k in $issuers.Keys) { Say ("TLS issuer {0}: {1}" -f $k, $issuers[$k]) }
    $valid = @($issuers.Values | Where-Object { $_ -notmatch '^(TLS_ERROR|TCP_TIMEOUT)' })
    if ($valid.Count -ge 3 -and @($valid | Select-Object -Unique).Count -eq 1) { Say 'WARNING: all sites show the same issuer; HTTPS inspection by a proxy is likely.' }
    else { Say 'HTTPS inspection: not detected.' }
  } catch { Say ('ERROR in section 2: ' + $_.Exception.Message) }

  # ---------- 3. Hosting providers ----------
  try {
    Say ''
    Say '== 3. Hosting providers (first 2 MB of each test file, direct, no VPN) =='
    if (-not (Test-Path $ProvidersFile)) { throw "providers.txt not found at $ProvidersFile" }
    $entries = @(Get-Content $ProvidersFile | Where-Object { $_ -and ($_.Trim() -notmatch '^#') -and ($_ -match '\|') } | ForEach-Object {
      $p = $_ -split '\|'
      if ($p.Count -ge 4) { [pscustomobject]@{ role = $p[0].Trim().ToUpper(); provider = $p[1].Trim(); location = $p[2].Trim(); url = $p[3].Trim() } }
    })
    $i = 0
    foreach ($e in $entries) {
      $i++
      Log ("  [{0}/{1}] {2} {3} ..." -f $i, $entries.Count, $e.provider, $e.location)
      $a1 = Invoke-Transfer $e.url
      $final = $a1.class
      $attempts = @($a1)
      if ($a1.class -ne 'OK' -and $a1.class -ne 'URL-BROKEN') {
        Start-Sleep -Seconds 2
        $a2 = Invoke-Transfer $e.url
        $attempts += $a2
        if ($a2.class -eq 'OK') { $final = 'UNSTABLE' } else { $final = $a2.class }
      }
      $n = 0
      foreach ($a in $attempts) {
        $n++
        $rows.Add([pscustomobject]@{ role = $e.role; provider = $e.provider; location = $e.location; attempt = $n; final = $final
                                     class = $a.class; detail = $a.detail; bytes = $a.bytes; mbps = $a.mbps
                                     tConnect = $a.tConnect; tTls = $a.tTls; tTotal = $a.tTotal; ip = $a.ip; url = $e.url })
      }
    }

    foreach ($role in @('CANDIDATE', 'CONTROL-BAD', 'CONTROL-OK', 'INFO')) {
      $rr = @($rows | Where-Object { $_.role -eq $role -and $_.attempt -eq 1 })
      if ($rr.Count -eq 0) { continue }
      Say ''
      Say $(switch ($role) { 'CANDIDATE' { 'Candidates (providers we could rent from):' } 'CONTROL-BAD' { 'Calibration: big clouds often throttled in Russia:' } 'CONTROL-OK' { 'Calibration: Russian mirror (must be fast):' } default { 'For context:' } })
      foreach ($r in $rr) {
        $last = @($rows | Where-Object { $_.url -eq $r.url } | Sort-Object attempt)[-1]
        Say ("   {0,-13} {1,-15} {2,-11} {3,7} KB {4,7} Mbit/s  {5}" -f $r.provider, $r.location, $r.final, [math]::Round($last.bytes / 1024), $last.mbps, $last.detail)
      }
    }
  } catch { Say ('ERROR in section 3: ' + $_.Exception.Message) }

  # ---------- 4. Verdict ----------
  try {
    Say ''
    Say '== 4. Verdict =='
    $first = @($rows | Where-Object { $_.attempt -eq 1 })
    $provNames = @($first | Where-Object { $_.role -eq 'CANDIDATE' } | Select-Object -ExpandProperty provider -Unique)
    $passing = @()
    foreach ($pn in $provNames) {
      $locs = @($first | Where-Object { $_.role -eq 'CANDIDATE' -and $_.provider -eq $pn })
      $ok = @($locs | Where-Object { $_.final -eq 'OK' }).Count
      $bad = @($locs | Where-Object { $_.final -match 'FREEZE|BLOCKED|SLOW|UNSTABLE' }).Count
      $broken = @($locs | Where-Object { $_.final -match 'URL-BROKEN|OK-SMALL' }).Count
      $v = if ($ok -gt 0 -and $bad -eq 0) { 'PASS' } elseif ($ok -gt 0) { 'PARTIAL' } elseif ($bad -gt 0) { 'FAIL' } else { 'UNKNOWN (test files missing)' }
      if ($v -eq 'PASS') { $passing += $pn }
      Say ("   {0,-13} {1,-30} ok {2}, problems {3}, broken URLs {4}" -f $pn, $v, $ok, $bad, $broken)
    }
    $cb = @($first | Where-Object { $_.role -eq 'CONTROL-BAD' })
    $cbHit = @($cb | Where-Object { $_.final -match 'FREEZE|BLOCKED|SLOW|UNSTABLE' }).Count
    $cok = @($first | Where-Object { $_.role -eq 'CONTROL-OK' -and $_.final -eq 'OK' }).Count
    Say ''
    Say ("Russian mirror fast: {0}" -f $(if ($cok -gt 0) { 'YES (download path works)' } else { 'NO (results below are unreliable)' }))
    Say ("Big-cloud controls throttled or blocked: {0} of {1}" -f $cbHit, $cb.Count)
    if ($cb.Count -gt 0 -and $cbHit -eq 0) { Say 'NOTE: this line does not throttle big clouds right now, so a PASS here is weaker evidence; other ISPs may differ.' }
    Say ("Gate G1 (two or more candidate providers pass): {0}  [{1}]" -f $(if ($passing.Count -ge 2) { 'PASS' } else { 'NOT YET' }), ($passing -join ', '))
  } catch { Say ('ERROR in section 4: ' + $_.Exception.Message) }

  $status = 'COMPLETED'
} catch {
  $status = 'FAILED'
  Say ('ERROR (run aborted): ' + $_.Exception.Message)
} finally {
  try { $rows | Export-Csv -Path (Join-Path $RunDir 'hosting.csv') -NoTypeInformation -Encoding UTF8 } catch { }
  try { $console | Out-File (Join-Path $RunDir 'console.log') -Encoding UTF8 } catch { }

  $finished = Get-Date
  $ev = New-Object System.Collections.Generic.List[string]
  $ev.Add('==== RU-PROBE EVIDENCE ====')
  $ev.Add("Script:     phase1-hosting.ps1 v$ScriptVersion")
  $ev.Add("Run ID:     $RunId")
  $ev.Add("Machine:    $MachineId (hash of computer name)")
  $ev.Add(("Started:    {0} local / {1} UTC" -f $started.ToString('s'), $started.ToUniversalTime().ToString('s')))
  $ev.Add(("Finished:   {0} local / {1} UTC ({2:N1} min)" -f $finished.ToString('s'), $finished.ToUniversalTime().ToString('s'), ($finished - $started).TotalMinutes))
  $ev.Add("Status:     $status")
  $pInfo = if (Test-Path $ProvidersFile) { "{0} ({1} entries, sha256 {2})" -f (Split-Path $ProvidersFile -Leaf), @($entries).Count, (Get-Sha256 $ProvidersFile).Substring(0, 16) } else { 'not found' }
  $ev.Add("Parameters: MaxTime=$MaxTime s; RangeBytes=$RangeBytes; ProvidersFile=$pInfo")
  $ev.Add('')
  $ev.Add('---- Results ----')
  foreach ($l in $summary) { $ev.Add($l) }
  $ev.Add('')
  $ev.Add('---- Detail (every attempt) ----')
  $fmt = '{0,-11} {1,-13} {2,-15} {3,1} {4,-10} {5,-14} {6,9} {7,7} {8,8} {9,8} {10,8} {11,-16} {12}'
  $ev.Add(($fmt -f 'role', 'provider', 'location', '#', 'final', 'attempt', 'bytes', 'Mbit/s', 'connect', 'tls', 'total', 'remote ip', 'url'))
  foreach ($r in $rows) {
    $ev.Add(($fmt -f $r.role, $r.provider, $r.location, $r.attempt, $r.final, ($r.class + '/' + $r.detail), $r.bytes, $r.mbps, $r.tConnect, $r.tTls, $r.tTotal, $r.ip, $r.url))
  }
  $ev.Add('')
  $ev.Add('---- Errors during run (includes ones the script handled; for diagnosis) ----')
  $errGroups = @($Error | Group-Object { (($_.Exception.Message -replace '\s+', ' ').Trim()) } | Sort-Object Count -Descending | Select-Object -First 15)
  if ($errGroups.Count -eq 0) { $ev.Add('(none)') } else { foreach ($g in $errGroups) { $ev.Add(('- [{0}x] {1}' -f $g.Count, $g.Name)) } }
  $ev.Add('')
  $ev.Add('---- Raw files kept on the PC (send only if asked) ----')
  foreach ($f in @('hosting.csv', 'console.log')) {
    $p = Join-Path $RunDir $f
    if (Test-Path $p) { $ev.Add(("runs\phase1-hosting-{0}\{1}  sha256 {2}" -f $stamp, $f, (Get-Sha256 $p))) }
  }
  $ev.Add('==== END ====')
  $ev | Out-File $EvFile -Encoding UTF8

  Write-Host ''
  Write-Host "Status: $status"
  Write-Host "EVIDENCE FILE TO SEND BACK: $EvFile"
}
