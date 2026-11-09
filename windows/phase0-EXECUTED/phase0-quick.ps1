<#
.SYNOPSIS
  Phase 0, quick pass: the minimum facts needed to decide what to research next. 2-4 minutes.

.DESCRIPTION
  Read-only. Installs nothing and changes no settings.
  Checks: can tools run here, which network the PC uses, whether Russian filtering is visible,
  and whether Amazon Web Services (AWS) is reachable: API endpoints in several regions, S3,
  CloudFront, the AWS console, and large transfers (to catch freezes after ~16 KB).
  If services.txt has filled-in D lines (work endpoints), they are tested too.

  EVIDENCE (send this file back):
    evidence\EVIDENCE-phase0-quick-<timestamp>.txt
  Written at the end of every run, also on failure or Ctrl+C. Public IP masked.

  Run from a normal (non-admin) PowerShell window:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\phase0-quick.ps1
#>
[CmdletBinding()]
param([string]$ServicesFile = '')

$ScriptVersion = '1.0'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
if (-not $PSScriptRoot) { Write-Host 'Run this as a file (-File .\phase0-quick.ps1), not by pasting it.'; exit 1 }
if (-not $ServicesFile) { $ServicesFile = Join-Path $PSScriptRoot 'services.txt' }
$Error.Clear()

$started = Get-Date
$stamp   = $started.ToString('yyyyMMdd-HHmmss')
$RunDir  = Join-Path $PSScriptRoot "runs\phase0-quick-$stamp"
$EvDir   = Join-Path $PSScriptRoot 'evidence'
$EvFile  = Join-Path $EvDir "EVIDENCE-phase0-quick-$stamp.txt"
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
function Mask-Ip([string]$ip) {
  if ($ip -match '^(\d+\.\d+\.\d+)\.\d+$') { return "$($Matches[1]).x" }
  if ($ip -match ':') { return (($ip -split ':')[0..2] -join ':') + ':...' }
  return $ip
}

$curlOk = [bool](Get-Command curl.exe -ErrorAction SilentlyContinue)
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

# One HTTP(S) probe. Any HTTP code means the server was reached; the code says how it answered.
function Invoke-Probe([string]$Url, [int]$MaxTime = 10, [string]$Range = '') {
  $cargs = @('-s', '-o', 'NUL', '-m', "$MaxTime", '--connect-timeout', '6', '-A', $UA,
             '-w', '%{http_code}|%{size_download}|%{time_connect}|%{time_appconnect}|%{time_total}|%{remote_ip}')
  if ($Range) { $cargs += @('-r', $Range) }
  $cargs += $Url
  $raw  = (& curl.exe @cargs 2>$null) -join ''
  $exit = $LASTEXITCODE
  $f = $raw -split '\|'
  while ($f.Count -lt 6) { $f += '' }
  $size = 0; [void][int64]::TryParse($f[1], [ref]$size)
  $status = switch ($exit) {
    0  { 'HTTP_' + $f[0] }
    6  { 'DNS_FAIL' }
    7  { 'CONNECT_FAIL' }
    28 { if ($size -gt 0 -and $size -lt 65536) { "FREEZE_AFTER_$($size)B" } else { 'TIMEOUT' } }
    35 { 'TLS_FAIL' }
    52 { 'EMPTY_REPLY' }
    56 { if ($size -gt 0 -and $size -lt 65536) { "RESET_AFTER_$($size)B" } else { 'RESET' } }
    default { "CURL_EXIT_$exit" }
  }
  [pscustomobject]@{ status = $status; http = $f[0]; bytes = $size; tConnect = $f[2]; tTls = $f[3]; tTotal = $f[4]; ip = $f[5] }
}
function Test-Ok([string]$s) { return ($s -match '^HTTP_[23]\d\d$') }
function Test-Reached([string]$s) { return ($s -match '^HTTP_\d\d\d$' -and $s -ne 'HTTP_000') }

$MachineId = Get-ShortHash ($env:COMPUTERNAME + '|' + $env:USERDOMAIN)
$RunId     = "phase0-quick-$stamp-$MachineId"
$summary = New-Object System.Collections.Generic.List[string]
$console = New-Object System.Collections.Generic.List[string]
$rows    = New-Object System.Collections.Generic.List[object]
function Log([string]$line) { $console.Add($line); Write-Host $line }
function Say([string]$line) { $summary.Add($line); Log $line }

function Add-Row([string]$section, [string]$name, [string]$url, $p) {
  $rows.Add([pscustomobject]@{ section = $section; name = $name; status = $p.status; http = $p.http; bytes = $p.bytes
                               tConnect = $p.tConnect; tTls = $p.tTls; tTotal = $p.tTotal; ip = $p.ip; url = $url })
}

Log ''
Log "Phase 0 quick check v$ScriptVersion. Run ID: $RunId"
Log 'Takes 2-4 minutes. Leave the window open.'
Log "Evidence file will be: $EvFile"
Log ''

$status = 'STOPPED (interrupted before completion)'
$facts = @{}
try {
  # ---------- 1. Environment ----------
  try {
    Say '== 1. Environment =='
    $facts.lang = [string]$ExecutionContext.SessionState.LanguageMode
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop; $osText = "$($os.Caption) build $($os.BuildNumber)" } catch { $osText = 'unknown' }
    $facts.curl = $curlOk
    $facts.portable = 'unknown'
    if ($curlOk) {
      $probeExe = Join-Path ([IO.Path]::GetTempPath()) 'phase0-probe-copy.exe'
      try {
        Copy-Item (Get-Command curl.exe).Source $probeExe -Force -ErrorAction Stop
        $facts.portable = [bool](& $probeExe --version 2>$null)
      } catch { $facts.portable = $false }
      finally { Remove-Item $probeExe -Force -ErrorAction SilentlyContinue }
    }
    try {
      $grp = whoami /groups /fo csv /nh | ConvertFrom-Csv -Header Name, Type, SID, Attributes
      $facts.admin = [bool]($grp | Where-Object { $_.SID -eq 'S-1-5-32-544' })
    } catch { $facts.admin = 'unknown' }
    $facts.proxy = $false
    try {
      $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
      $facts.proxy = [bool]$ie.ProxyEnable -or [bool]$ie.AutoConfigURL
    } catch { }
    $facts.vpn = @()
    try {
      $facts.vpn = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' -and (($_.InterfaceDescription + ' ' + $_.Name) -match 'PANGP|GlobalProtect|AnyConnect|Cisco|Forti|WireGuard|Wintun|TAP-Windows|OpenVPN|Juniper|Pulse|Check ?Point|Zscaler|NordLynx|Amnezia|sing-box|Hiddify') } |
        ForEach-Object { $_.InterfaceDescription })
    } catch { }
    Say ("OS: {0}; PowerShell {1} ({2})" -f $osText, $PSVersionTable.PSVersion, $facts.lang)
    Say ("curl: {0}; portable .exe runs from user folder: {1}; admin group member: {2}" -f $facts.curl, $facts.portable, $facts.admin)
    Say ("Browser proxy configured: {0}; active VPN-like adapters: {1}" -f $facts.proxy, $(if ($facts.vpn.Count) { $facts.vpn -join ', ' } else { 'none' }))
  } catch { Say ('ERROR in section 1: ' + $_.Exception.Message) }

  if (-not $curlOk) { throw 'curl.exe is missing; network checks cannot run.' }

  # ---------- 2. Network identity ----------
  try {
    Say ''
    Say '== 2. Network identity =='
    $geo = $null
    foreach ($src in @('https://ipinfo.io/json', 'https://ifconfig.co/json', 'https://api.ip.sb/geoip')) {
      try {
        $raw = (& curl.exe -s -m 10 -A $UA $src 2>$null) -join "`n"
        if ($raw) { $j = $raw | ConvertFrom-Json -ErrorAction Stop; if ($j) { $geo = $j; break } }
      } catch { }
    }
    if ($geo) {
      $ip      = [string]$(if ($geo.ip) { $geo.ip } else { $geo.ip_addr })
      $country = [string]$(if ($geo.country_iso) { $geo.country_iso } elseif ($geo.country_code) { $geo.country_code } else { $geo.country })
      $org     = [string]$(if ($geo.org) { $geo.org } elseif ($geo.asn_org) { "AS$($geo.asn) $($geo.asn_org)" } elseif ($geo.isp) { "AS$($geo.asn) $($geo.isp)" } else { '' })
      $facts.country = $country
      $facts.dc = $org -match 'hosting|cloud|data ?cent|datacenter|server|vps|vds|selectel|yandex|timeweb|beget|aeza|reg\.ru|firstvds|ruvds|digitalocean|amazon|google|microsoft|azure|ovh|hetzner|linode|akamai|oracle|scaleway|contabo|vultr|m247|leaseweb|cloudflare'
      Say ("Public IP {0} (masked); country {1}; city {2}" -f (Mask-Ip $ip), $country, $geo.city)
      Say ("Network: {0}{1}" -f $org, $(if ($facts.dc) { '  <- looks like a data center or cloud' } else { '' }))
    } else { Say 'Public IP lookup failed on all sources.' }
  } catch { Say ('ERROR in section 2: ' + $_.Exception.Message) }

  # ---------- 3. Filtering sanity ----------
  try {
    Say ''
    Say '== 3. Filtering sanity (direct, no VPN) =='
    $sanity = @(
      @('control', 'https://www.google.com/'), @('control', 'https://github.com/'), @('control', 'https://www.microsoft.com/'),
      @('blocked', 'https://www.instagram.com/'), @('blocked', 'https://www.youtube.com/'), @('blocked', 'https://www.linkedin.com/'),
      @('blocked', 'https://x.com/'), @('russian', 'https://ya.ru/'), @('russian', 'https://www.gosuslugi.ru/')
    )
    foreach ($s in $sanity) {
      $p = Invoke-Probe $s[1] 10
      Add-Row 'sanity' $s[0] $s[1] $p
      Say ("   {0,-8} {1,-24} {2}" -f $s[0], $p.status, $s[1])
    }
  } catch { Say ('ERROR in section 3: ' + $_.Exception.Message) }

  # ---------- 4. AWS availability ----------
  try {
    Say ''
    Say '== 4. AWS availability (direct, no VPN) =='
    Say 'Any HTTP code (even 400 or 403) means the AWS server was reached. DNS/CONNECT/TLS/TIMEOUT/RESET mean it was not.'
    $regions = New-Object System.Collections.Generic.List[string]
    foreach ($r in @('us-east-1', 'us-west-2', 'eu-west-1', 'eu-central-1', 'eu-north-1', 'ap-southeast-1')) { $regions.Add($r) }

    # Work endpoints from services.txt (D lines), if filled in
    $dLines = @()
    if (Test-Path $ServicesFile) {
      $dLines = @(Get-Content $ServicesFile | Where-Object { $_ -match '^\s*D\s+' -and $_ -notmatch 'YOUR-' } | ForEach-Object { ($_.Trim() -split '\s+', 3)[1] })
      foreach ($d in $dLines) { if ($d -match 'clientvpn\.([a-z0-9-]+)\.amazonaws\.com' -and -not $regions.Contains($Matches[1])) { $regions.Add($Matches[1]) } }
    }

    Say ''
    Say 'Regional endpoints (EC2 API and S3 in each region; these sit in Amazon''s own network):'
    Say ("   {0,-15} {1,-26} {2}" -f 'region', 'EC2 API', 'S3')
    $regionOk = 0
    foreach ($r in $regions) {
      $u1 = "https://ec2.$r.amazonaws.com/"; $p1 = Invoke-Probe $u1 10; Add-Row 'aws-region' "ec2 $r" $u1 $p1
      $u2 = "https://s3.$r.amazonaws.com/";  $p2 = Invoke-Probe $u2 10; Add-Row 'aws-region' "s3 $r"  $u2 $p2
      if ((Test-Reached $p1.status) -and (Test-Reached $p2.status)) { $regionOk++ }
      Say ("   {0,-15} {1,-26} {2}" -f $r, $p1.status, $p2.status)
    }
    $facts.awsRegionsOk = $regionOk; $facts.awsRegions = $regions.Count

    Say ''
    Say 'Global services:'
    $globals = @(
      @('STS global', 'https://sts.amazonaws.com/'),
      @('Sign-in', 'https://signin.aws.amazon.com/'),
      @('Console', 'https://console.aws.amazon.com/'),
      @('aws.amazon.com (CloudFront)', 'https://aws.amazon.com/')
    )
    $globalOk = 0
    foreach ($g in $globals) {
      $p = Invoke-Probe $g[1] 12
      Add-Row 'aws-global' $g[0] $g[1] $p
      if (Test-Reached $p.status) { $globalOk++ }
      Say ("   {0,-30} {1,-24} {2} bytes" -f $g[0], $p.status, $p.bytes)
    }
    $facts.awsGlobalOk = $globalOk

    Say ''
    Say 'Large transfers (1 MB or a large listing; a stall after ~16 KB means throttling):'
    $big = @(
      @('CloudFront: AWS CLI installer', 'https://awscli.amazonaws.com/AWSCLIV2.msi', '0-1048575'),
      @('S3 us-east-1: public bucket listing', 'https://noaa-goes16.s3.amazonaws.com/?list-type=2&max-keys=1000', ''),
      @('S3 eu-central-1: public bucket listing', 'https://copernicus-dem-30m.s3.eu-central-1.amazonaws.com/?list-type=2&max-keys=1000', '')
    )
    $freeze = 0
    foreach ($b in $big) {
      $p = Invoke-Probe $b[1] 30 $b[2]
      Add-Row 'aws-transfer' $b[0] $b[1] $p
      if ($p.status -match 'FREEZE|RESET_AFTER') { $freeze++ }
      $kbps = ''
      $t = 0.0
      if ([double]::TryParse($p.tTotal, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$t) -and $t -gt 0 -and $p.bytes -gt 0) {
        $kbps = (' {0:N0} KB/s' -f (($p.bytes / 1024) / $t))
      }
      Say ("   {0,-38} {1,-22} {2} bytes{3}" -f $b[0], $p.status, $p.bytes, $kbps)
    }
    $facts.awsFreeze = $freeze

    if ($dLines.Count -gt 0) {
      Say ''
      Say 'Your work endpoints (from services.txt):'
      foreach ($d in $dLines) {
        if ($d -match '^tcp://([^:/]+):(\d+)') {
          $r = Test-Tcp $Matches[1] ([int]$Matches[2]) 8000
          Add-Row 'work' 'tcp' $d ([pscustomobject]@{ status = "TCP_$r"; http = ''; bytes = ''; tConnect = ''; tTls = ''; tTotal = ''; ip = '' })
          Say ("   TCP_{0,-20} {1}" -f $r, $d)
        } else {
          $p = Invoke-Probe $d 12
          Add-Row 'work' 'https' $d $p
          Say ("   {0,-24} {1}" -f $p.status, $d)
        }
      }
    } else {
      Say ''
      Say 'Work endpoints: none filled in services.txt (skipped).'
    }
  } catch { Say ('ERROR in section 4: ' + $_.Exception.Message) }

  # ---------- 5. Quick verdict ----------
  try {
    Say ''
    Say '== 5. Quick verdict =='
    $san = @($rows | Where-Object { $_.section -eq 'sanity' })
    $ctrlOk  = @($san | Where-Object { $_.name -eq 'control' -and (Test-Ok $_.status) }).Count
    $blkFail = @($san | Where-Object { $_.name -eq 'blocked' -and -not (Test-Ok $_.status) }).Count
    $tools = $curlOk -and ($facts.portable -eq $true) -and ($facts.lang -eq 'FullLanguage')
    $egress = ($facts.country -eq 'RU') -and (-not $facts.dc) -and (@($facts.vpn).Count -eq 0)
    Say ("Tools can run here:          {0}" -f $(if ($tools) { 'YES' } else { 'CHECK section 1' }))
    Say ("Regular Russian ISP egress:  {0}" -f $(if ($egress) { 'YES' } else { 'CHECK sections 1-2' }))
    Say ("Russian filtering visible:   {0}" -f $(if ($blkFail -ge 2 -and $ctrlOk -ge 1) { "YES ($blkFail of 4 blocked sites fail, $ctrlOk of 3 controls work)" } else { "CHECK section 3 ($blkFail of 4 blocked fail, $ctrlOk of 3 controls work)" }))
    Say ("AWS regions reachable:       {0} of {1}" -f $facts.awsRegionsOk, $facts.awsRegions)
    Say ("AWS global services reached: {0} of 4" -f $facts.awsGlobalOk)
    Say ("AWS large-transfer stalls:   {0}" -f $(if ($facts.awsFreeze -gt 0) { "$($facts.awsFreeze) (throttling suspected)" } else { 'none seen' }))
  } catch { Say ('ERROR in section 5: ' + $_.Exception.Message) }

  $status = 'COMPLETED'
} catch {
  $status = 'FAILED'
  Say ('ERROR (run aborted): ' + $_.Exception.Message)
} finally {
  try { $rows | Export-Csv -Path (Join-Path $RunDir 'quick.csv') -NoTypeInformation -Encoding UTF8 } catch { }
  try { $console | Out-File (Join-Path $RunDir 'console.log') -Encoding UTF8 } catch { }

  $finished = Get-Date
  $ev = New-Object System.Collections.Generic.List[string]
  $ev.Add('==== RU-PROBE EVIDENCE ====')
  $ev.Add("Script:     phase0-quick.ps1 v$ScriptVersion")
  $ev.Add("Run ID:     $RunId")
  $ev.Add("Machine:    $MachineId (hash of computer name)")
  $ev.Add(("Started:    {0} local / {1} UTC" -f $started.ToString('s'), $started.ToUniversalTime().ToString('s')))
  $ev.Add(("Finished:   {0} local / {1} UTC ({2:N1} min)" -f $finished.ToString('s'), $finished.ToUniversalTime().ToString('s'), ($finished - $started).TotalMinutes))
  $ev.Add("Status:     $status")
  $ev.Add('')
  $ev.Add('---- Results ----')
  foreach ($l in $summary) { $ev.Add($l) }
  $ev.Add('')
  $ev.Add('---- Detail ----')
  $ev.Add(('{0,-12} {1,-40} {2,-22} {3,4} {4,9} {5,8} {6,8} {7,8} {8,-16} {9}' -f 'section', 'name', 'status', 'http', 'bytes', 'connect', 'tls', 'total', 'remote ip', 'url'))
  foreach ($r in $rows) {
    $ev.Add(('{0,-12} {1,-40} {2,-22} {3,4} {4,9} {5,8} {6,8} {7,8} {8,-16} {9}' -f $r.section, $r.name, $r.status, $r.http, $r.bytes, $r.tConnect, $r.tTls, $r.tTotal, $r.ip, $r.url))
  }
  $ev.Add('')
  $ev.Add('---- Errors during run (includes ones the script handled; for diagnosis) ----')
  $errGroups = @($Error | Group-Object { (($_.Exception.Message -replace '\s+', ' ').Trim()) } | Sort-Object Count -Descending | Select-Object -First 15)
  if ($errGroups.Count -eq 0) { $ev.Add('(none)') } else { foreach ($g in $errGroups) { $ev.Add(('- [{0}x] {1}' -f $g.Count, $g.Name)) } }
  $ev.Add('')
  $ev.Add('---- Raw files kept on the PC (send only if asked) ----')
  foreach ($f in @('quick.csv', 'console.log')) {
    $p = Join-Path $RunDir $f
    if (Test-Path $p) { $ev.Add(("runs\phase0-quick-{0}\{1}  sha256 {2}" -f $stamp, $f, (Get-Sha256 $p))) }
  }
  $ev.Add('==== END ====')
  $ev | Out-File $EvFile -Encoding UTF8

  Write-Host ''
  Write-Host "Status: $status"
  Write-Host "EVIDENCE FILE TO SEND BACK: $EvFile"
}
