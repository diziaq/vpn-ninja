<#
.SYNOPSIS
  Phase 0 of the gated rollout plan: audit RU-PC (step 0.2) and record a direct baseline (step 0.4).

.DESCRIPTION
  Read-only. Installs nothing and changes no settings.

  EVIDENCE (send this file back):
    evidence\EVIDENCE-phase0-audit-<timestamp>.txt
  It is written at the end of every run, also when the run fails or is stopped with Ctrl+C.
  The public IP is masked and the computer name is replaced by a short hash.

  Raw files stay on this PC (send only if asked):
    runs\phase0-audit-<timestamp>\audit.json, baseline.csv, console.log

  Run from a normal (non-admin) PowerShell window:
    powershell -NoProfile -ExecutionPolicy Bypass -File .\phase0-audit.ps1

  Compatible with Windows PowerShell 5.1 and PowerShell 7.
#>
[CmdletBinding()]
param(
  [string]$ServicesFile = '',
  [int]$TimeoutSec = 15
)

$ScriptVersion = '1.1'
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
if (-not $PSScriptRoot) { Write-Host 'Run this as a file (-File .\phase0-audit.ps1), not by pasting it.'; exit 1 }
if (-not $ServicesFile) { $ServicesFile = Join-Path $PSScriptRoot 'services.txt' }
$Error.Clear()

$started = Get-Date
$stamp   = $started.ToString('yyyyMMdd-HHmmss')
$RunDir  = Join-Path $PSScriptRoot "runs\phase0-audit-$stamp"
$EvDir   = Join-Path $PSScriptRoot 'evidence'
$EvFile  = Join-Path $EvDir "EVIDENCE-phase0-audit-$stamp.txt"
New-Item -ItemType Directory -Path $RunDir -Force | Out-Null
New-Item -ItemType Directory -Path $EvDir -Force | Out-Null

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

$MachineId = Get-ShortHash ($env:COMPUTERNAME + '|' + $env:USERDOMAIN)
$RunId     = "phase0-audit-$stamp-$MachineId"

$audit   = [ordered]@{ runId = $RunId; generatedLocal = $started.ToString('s'); generatedUtc = $started.ToUniversalTime().ToString('s') }
$summary = New-Object System.Collections.Generic.List[string]
$console = New-Object System.Collections.Generic.List[string]
$rows    = @()
function Log([string]$line) { $console.Add($line); Write-Host $line }
function Say([string]$line) { $summary.Add($line); Log $line }

# ---------- helpers ----------

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
    $tcp.ReceiveTimeout = $TimeoutMs
    $tcp.SendTimeout = $TimeoutMs
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
    if ($r) { return (($r | Select-Object -First 3) -join ' ') }
    return 'NO_A_RECORD'
  } catch { return 'DNS_FAIL' }
}

$curlOk = [bool](Get-Command curl.exe -ErrorAction SilentlyContinue)
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36'

function Invoke-Probe([string]$Url, [int]$MaxTime, [string]$Range = '') {
  $cargs = @('-s', '-o', 'NUL', '-m', "$MaxTime", '--connect-timeout', '10', '-A', $UA,
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
  [pscustomobject]@{
    status = $status; curlExit = $exit; httpCode = $f[0]; bytes = $size
    tConnect = $f[2]; tTls = $f[3]; tTotal = $f[4]; remoteIp = $f[5]
  }
}

function Test-Ok([string]$status) { return ($status -match '^HTTP_[23]\d\d$' -or $status -eq 'TCP_OPEN') }

function Mask-Ip([string]$ip) {
  if ($ip -match '^(\d+\.\d+\.\d+)\.\d+$') { return "$($Matches[1]).x" }
  if ($ip -match ':') { return (($ip -split ':')[0..2] -join ':') + ':...' }
  return $ip
}

Log ''
Log "Phase 0 audit v$ScriptVersion started. Run ID: $RunId"
Log 'This takes 5-10 minutes. Leave the window open.'
Log "Evidence file will be: $EvFile"
Log ''

$status = 'STOPPED (interrupted before completion)'
try {
  try {
    Say '== 1. System =='
    try {
      $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
      $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
      $audit.os = "$($os.Caption) $($os.Version) build $($os.BuildNumber)"
      $audit.lastBoot = ([datetime]$os.LastBootUpTime).ToString('s')
      $audit.domainJoined = [bool]$cs.PartOfDomain
      $audit.hypervisorPresent = [bool]$cs.HypervisorPresent
    } catch { $audit.os = 'UNKNOWN' }
    try { $audit.virtualizationInFirmware = [bool]((Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1).VirtualizationFirmwareEnabled) } catch { }
    $audit.arch = $env:PROCESSOR_ARCHITECTURE
    $audit.psVersion = $PSVersionTable.PSVersion.ToString()
    $audit.languageMode = [string]$ExecutionContext.SessionState.LanguageMode

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $audit.elevatedSession = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    try {
      $groups = whoami /groups /fo csv /nh | ConvertFrom-Csv -Header Name, Type, SID, Attributes
      $audit.memberOfAdministrators = [bool]($groups | Where-Object { $_.SID -eq 'S-1-5-32-544' })
    } catch { $audit.memberOfAdministrators = 'UNKNOWN' }

    $audit.executionPolicy = (Get-ExecutionPolicy -List | ForEach-Object { "$($_.Scope)=$($_.ExecutionPolicy)" }) -join '; '

    $audit.curl = if ($curlOk) { ((& curl.exe --version 2>$null) | Select-Object -First 1) } else { 'MISSING' }
    $audit.winget = [bool](Get-Command winget.exe -ErrorAction SilentlyContinue)
    $audit.wsl = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)

    # Can a portable program run from a user folder? (needed later for sing-box / xray)
    $audit.portableExeRuns = 'UNKNOWN'
    if ($curlOk) {
      $probeExe = Join-Path ([IO.Path]::GetTempPath()) 'phase0-probe-copy.exe'
      try {
        Copy-Item (Get-Command curl.exe).Source $probeExe -Force -ErrorAction Stop
        $v = & $probeExe --version 2>$null
        $audit.portableExeRuns = [bool]$v
      } catch { $audit.portableExeRuns = $false }
      finally { Remove-Item $probeExe -Force -ErrorAction SilentlyContinue }
    }

    # Sleep timeout (0 = never). Last two hex values in powercfg output are AC and DC.
    try {
      $q = (powercfg /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 2>$null) -join "`n"
      $hex = @([regex]::Matches($q, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
      if ($hex.Count -ge 2) {
        $audit.sleepAfterMinutesAC = [math]::Round([Convert]::ToInt64($hex[$hex.Count - 2], 16) / 60)
        $audit.sleepAfterMinutesDC = [math]::Round([Convert]::ToInt64($hex[$hex.Count - 1], 16) / 60)
      }
    } catch { }

    Say ("OS: {0} ({1}), PowerShell {2}, language mode {3}" -f $audit.os, $audit.arch, $audit.psVersion, $audit.languageMode)
    Say ("Admin group member: {0}; elevated now: {1}; domain joined: {2}" -f $audit.memberOfAdministrators, $audit.elevatedSession, $audit.domainJoined)
    Say ("Execution policy: {0}" -f $audit.executionPolicy)
    Say ("curl: {0}" -f $audit.curl)
    Say ("Portable .exe from user folder runs: {0}; winget: {1}; WSL: {2}" -f $audit.portableExeRuns, $audit.winget, $audit.wsl)
    Say ("Sleep after (min, 0 = never): AC {0}, battery {1}" -f $audit.sleepAfterMinutesAC, $audit.sleepAfterMinutesDC)
    if ($audit.languageMode -ne 'FullLanguage') { Say 'WARNING: PowerShell is restricted (not FullLanguage). Some checks below will report errors.' }
  } catch {
    Say ("ERROR in section 1. System: " + $_.Exception.Message)
  }
  try {
    # ---------- 2. Network setup ----------
    Say ''
    Say '== 2. Network setup =='
    $audit.vpnAdaptersUp = @()
    $vpnPattern = 'PANGP|GlobalProtect|AnyConnect|Cisco|Fortinet|FortiClient|WireGuard|Wintun|TAP-Windows|OpenVPN|Juniper|Pulse|Check ?Point|Zscaler|NordLynx|Amnezia|sing-box|Hiddify|Kaspersky VPN|Proton'
    try {
      $adapters = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' } |
        Select-Object Name, InterfaceDescription, LinkSpeed
      $audit.adaptersUp = $adapters
      $vpnUp = @($adapters | Where-Object { ($_.InterfaceDescription + ' ' + $_.Name) -match $vpnPattern })
      $audit.vpnAdaptersUp = $vpnUp
      foreach ($a in $adapters) { Say ("Adapter up: {0} | {1} | {2}" -f $a.Name, $a.InterfaceDescription, $a.LinkSpeed) }
      if ($vpnUp.Count -gt 0) { Say 'WARNING: a VPN-like adapter is active. Traffic may not leave through the Russian ISP.' }
    } catch { Say 'Adapters: could not read (restricted).' }

    try {
      $audit.dnsServers = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.ServerAddresses } | ForEach-Object { "$($_.InterfaceAlias): $($_.ServerAddresses -join ', ')" })
    } catch { }

    try {
      $ie = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
      $audit.userProxyEnabled = [bool]$ie.ProxyEnable
      $audit.userProxyServer  = [string]$ie.ProxyServer
      $audit.userProxyPac     = [string]$ie.AutoConfigURL
    } catch { }
    if (Get-Command netsh.exe -ErrorAction SilentlyContinue) { $audit.winhttpProxy = ((netsh.exe winhttp show proxy 2>$null) -join ' ') -replace '\s+', ' ' }
    $audit.envProxy = (@($env:HTTP_PROXY, $env:HTTPS_PROXY, $env:ALL_PROXY) | Where-Object { $_ }) -join ' '
    $proxyInUse = $audit.userProxyEnabled -or [bool]$audit.userProxyPac -or [bool]$audit.envProxy
    Say ("Browser proxy enabled: {0}; PAC: {1}; env proxy: {2}" -f $audit.userProxyEnabled, ($(if ($audit.userProxyPac) { 'yes' } else { 'no' })), ($(if ($audit.envProxy) { 'yes' } else { 'no' })))
    if ($proxyInUse) { Say 'NOTE: a proxy is configured for browsers. curl tests below go direct, like VPN traffic would.' }
  } catch {
    Say ("ERROR in section 2. Network setup: " + $_.Exception.Message)
  }
  try {
    # ---------- 3. Public IP and ISP ----------
    Say ''
    Say '== 3. Public IP and ISP =='
    $geo = $null
    $geoSources = @('https://ipinfo.io/json', 'https://ifconfig.co/json', 'https://api.ip.sb/geoip')
    if ($curlOk) {
      foreach ($src in $geoSources) {
        try {
          $raw = (& curl.exe -s -m 12 -A $UA $src 2>$null) -join "`n"
          if ($raw) { $j = $raw | ConvertFrom-Json -ErrorAction Stop; if ($j) { $geo = $j; $audit.geoSource = $src; break } }
        } catch { }
      }
    }
    if ($geo) {
      $ip      = [string]$(if ($geo.ip) { $geo.ip } else { $geo.ip_addr })
      $country = [string]$(if ($geo.country_iso) { $geo.country_iso } elseif ($geo.country_code) { $geo.country_code } else { $geo.country })
      $org     = [string]$(if ($geo.org) { $geo.org } elseif ($geo.asn_org) { "AS$($geo.asn) $($geo.asn_org)" } elseif ($geo.isp) { "AS$($geo.asn) $($geo.isp)" } else { '' })
      $city    = [string]$geo.city
      $audit.publicIp = $ip; $audit.country = $country; $audit.org = $org; $audit.city = $city
      $dcPattern = 'hosting|cloud|data ?cent|datacenter|server|vps|vds|selectel|yandex|timeweb|beget|aeza|reg\.ru|firstvds|ruvds|digitalocean|amazon|google|microsoft|azure|ovh|hetzner|linode|akamai|oracle|scaleway|contabo|vultr|m247|leaseweb|cloudflare'
      $looksDc = $org -match $dcPattern
      $audit.looksLikeDataCenter = $looksDc
      Say ("Public IP: {0} (masked) | country {1} | city {2}" -f (Mask-Ip $ip), $country, $city)
      Say ("Network: {0}" -f $org)
      if ($country -ne 'RU') { Say 'WARNING: traffic does not leave in Russia. Tests from here would not show Russian filtering.' }
      if ($looksDc) { Say 'WARNING: the network name looks like a data center or cloud, not a regular ISP.' }
    } else {
      Say 'Public IP lookup failed on all sources.'
    }
  } catch {
    Say ("ERROR in section 3. Public IP and ISP: " + $_.Exception.Message)
  }
  try {
    # ---------- 4. Protocol and port checks ----------
    Say ''
    Say '== 4. UDP, ports and TLS =='
    $udp = [ordered]@{}
    foreach ($srv in @('1.1.1.1', '8.8.8.8', '77.88.8.8')) { $udp[$srv] = Resolve-A -Name 'example.com' -Server $srv }
    $audit.udpDnsToPublicResolvers = $udp
    Say ("Plain DNS (UDP 53) to public resolvers: " + (($udp.GetEnumerator() | ForEach-Object { "$($_.Key)=" + $(if ($_.Value -match '^\d') { 'OK' } else { $_.Value }) }) -join ', '))

    $portTests = [ordered]@{
      'github.com:22'      = @('github.com', 22)
      'github.com:443'     = @('github.com', 443)
      'portquiz.net:80'    = @('portquiz.net', 80)
      'portquiz.net:8080'  = @('portquiz.net', 8080)
      'portquiz.net:8443'  = @('portquiz.net', 8443)
      'portquiz.net:2053'  = @('portquiz.net', 2053)
      '1.1.1.1:853'        = @('1.1.1.1', 853)
    }
    $ports = [ordered]@{}
    foreach ($k in $portTests.Keys) { $ports[$k] = Test-Tcp $portTests[$k][0] $portTests[$k][1] }
    $audit.tcpPorts = $ports
    Say ("Outbound TCP: " + (($ports.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '))

    $tlsHosts = @('www.microsoft.com', 'github.com', 'www.wikipedia.org', 'ya.ru', 'www.google.com')
    $issuers = [ordered]@{}
    foreach ($h in $tlsHosts) { $issuers[$h] = Get-TlsIssuer $h }
    $audit.tlsIssuers = $issuers
    $validIssuers = @($issuers.Values | Where-Object { $_ -and ($_ -notmatch '^(TLS_ERROR|TCP_TIMEOUT)') })
    $distinct = @($validIssuers | Select-Object -Unique)
    $interception = ($validIssuers.Count -ge 3 -and $distinct.Count -eq 1)
    $audit.tlsInterceptionSuspected = $interception
    foreach ($h in $tlsHosts) { Say ("TLS issuer {0}: {1}" -f $h, $issuers[$h]) }
    if ($interception) { Say 'WARNING: every site shows the same certificate issuer. A corporate proxy is likely inspecting HTTPS.' }
  } catch {
    Say ("ERROR in section 4. Protocol and port checks: " + $_.Exception.Message)
  }
  try {
    # ---------- 5. DNS answers for blocked domains ----------
    Say ''
    Say '== 5. DNS answers (system resolver vs 1.1.1.1) =='
    $dnsCmp = @()
    foreach ($d in @('www.instagram.com', 'www.facebook.com', 'x.com', 'www.linkedin.com', 'discord.com', 'www.youtube.com')) {
      $sys = Resolve-A -Name $d
      $pub = Resolve-A -Name $d -Server '1.1.1.1'
      $dnsCmp += [pscustomobject]@{ domain = $d; system = $sys; cloudflare = $pub }
      Say ("{0,-20} system: {1,-35} 1.1.1.1: {2}" -f $d, $sys, $pub)
    }
    $audit.dnsComparison = $dnsCmp
  } catch {
    Say ("ERROR in section 5. DNS answers for blocked domains: " + $_.Exception.Message)
  }
  try {
    # ---------- 6. Direct baseline ----------
    Say ''
    Say '== 6. Direct baseline (no VPN) =='
    $rows = @()
    if (-not $curlOk) {
      Say 'curl.exe is missing: baseline skipped. Windows 10 (1803+) and 11 include it.'
    } elseif (-not (Test-Path $ServicesFile)) {
      Say "services.txt not found at $ServicesFile : baseline skipped."
    } else {
      $lines = Get-Content $ServicesFile | Where-Object { $_ -and ($_.Trim() -notmatch '^#') }
      foreach ($line in $lines) {
        $parts = $line.Trim() -split '\s+', 3
        if ($parts.Count -lt 2) { continue }
        $group = $parts[0].ToUpper(); $target = $parts[1]
        if ($target -match 'YOUR-') { continue }
        Log ("  testing [{0}] {1}" -f $group, $target)
        if ($target -match '^tcp://([^:/]+):(\d+)') {
          $r = Test-Tcp $Matches[1] ([int]$Matches[2]) 8000
          $rows += [pscustomobject]@{ group = $group; target = $target; status = "TCP_$r"; httpCode = ''; bytes = ''; tConnect = ''; tTls = ''; tTotal = ''; remoteIp = '' }
          continue
        }
        if ($group -eq 'T') { $p = Invoke-Probe $target 30 '0-1048575' } else { $p = Invoke-Probe $target $TimeoutSec }
        $rows += [pscustomobject]@{ group = $group; target = $target; status = $p.status; httpCode = $p.httpCode; bytes = $p.bytes
                                   tConnect = $p.tConnect; tTls = $p.tTls; tTotal = $p.tTotal; remoteIp = $p.remoteIp }
      }

      $labels = @{ A = 'A blocked in Russia (expected to fail)'; B = 'B Russian services (expected to work)'; C = 'C foreign, refuse RU IPs (observe)'
                   D = 'D work endpoints'; T = 'T big-cloud throttling probes (1 MB)'; X = 'X controls (expected to work)' }
      foreach ($g in @('X', 'A', 'B', 'C', 'D', 'T')) {
        $gr = @($rows | Where-Object { $_.group -eq $g })
        if ($gr.Count -eq 0) { continue }
        $ok = @($gr | Where-Object { Test-Ok $_.status }).Count
        Say ''
        Say ("{0}: {1} of {2} reachable" -f $labels[$g], $ok, $gr.Count)
        foreach ($r in $gr) {
          $extra = if ($g -eq 'T' -and $r.bytes) { " ($($r.bytes) bytes in $($r.tTotal)s)" } else { '' }
          Say ("   {0,-24} {1}{2}" -f $r.status, $r.target, $extra)
        }
      }
    }
  } catch {
    Say ("ERROR in section 6. Direct baseline: " + $_.Exception.Message)
  }
  try {
    # ---------- 7. Preliminary Gate G0 verdict ----------
    Say ''
    Say '== 7. Preliminary Gate G0 verdict =='
    $tools = ($curlOk -and ($audit.portableExeRuns -eq $true) -and ($audit.languageMode -eq 'FullLanguage'))
    $egressOk = ($audit.country -eq 'RU') -and (-not $audit.looksLikeDataCenter) -and (@($audit.vpnAdaptersUp).Count -eq 0)
    $aRows = @($rows | Where-Object { $_.group -eq 'A' })
    $aFail = @($aRows | Where-Object { -not (Test-Ok $_.status) }).Count
    $xRows = @($rows | Where-Object { $_.group -eq 'X' })
    $xOk = @($xRows | Where-Object { Test-Ok $_.status }).Count
    $filtering = ($aRows.Count -gt 0) -and ($aFail -ge 2) -and ($xOk -ge 1)

    Say ("Tools can run here:            {0}" -f $(if ($tools) { 'PASS' } else { 'CHECK (see sections 1 and 2)' }))
    Say ("Egress is a regular RU ISP:    {0}" -f $(if ($egressOk) { 'PASS' } else { 'CHECK (see sections 2 and 3)' }))
    Say ("Russian filtering is visible:  {0}" -f $(if ($filtering) { "PASS ($aFail of $($aRows.Count) group A blocked, controls work)" } else { 'CHECK (see section 6)' }))
    Say ("HTTPS inspection by a proxy:   {0}" -f $(if ($interception) { 'SUSPECTED (results may be too pessimistic)' } else { 'not detected' }))
    Say  "Session and overnight uptime:  PENDING (run heartbeat.ps1 for 2+ hours, ideally overnight)"
  } catch {
    Say ("ERROR in section 7. Preliminary Gate G0 verdict: " + $_.Exception.Message)
  }
  $status = 'COMPLETED'
} catch {
  $status = 'FAILED'
  Say ("ERROR (run aborted): " + $_.Exception.Message)
} finally {
  # ---------- raw files ----------
  $audit.baselineRows = @($rows).Count
  $audit.status = $status
  try { $audit | ConvertTo-Json -Depth 6 | Out-File (Join-Path $RunDir 'audit.json') -Encoding UTF8 } catch { }
  if (@($rows).Count -gt 0) { try { $rows | Export-Csv -Path (Join-Path $RunDir 'baseline.csv') -NoTypeInformation -Encoding UTF8 } catch { } }
  try { $console | Out-File (Join-Path $RunDir 'console.log') -Encoding UTF8 } catch { }

  # ---------- evidence ----------
  $finished = Get-Date
  $ev = New-Object System.Collections.Generic.List[string]
  $ev.Add('==== RU-PROBE EVIDENCE ====')
  $ev.Add("Script:     phase0-audit.ps1 v$ScriptVersion")
  $ev.Add("Run ID:     $RunId")
  $ev.Add("Machine:    $MachineId (hash of computer name)")
  $ev.Add(("Started:    {0} local / {1} UTC" -f $started.ToString('s'), $started.ToUniversalTime().ToString('s')))
  $ev.Add(("Finished:   {0} local / {1} UTC ({2:N1} min)" -f $finished.ToString('s'), $finished.ToUniversalTime().ToString('s'), ($finished - $started).TotalMinutes))
  $ev.Add("Status:     $status")
  $svcInfo = if (Test-Path $ServicesFile) { "{0} ({1} entries, sha256 {2})" -f (Split-Path $ServicesFile -Leaf), @(Get-Content $ServicesFile | Where-Object { $_ -and ($_.Trim() -notmatch '^#') }).Count, (Get-Sha256 $ServicesFile).Substring(0, 16) } else { 'not found' }
  $ev.Add("Parameters: TimeoutSec=$TimeoutSec; ServicesFile=$svcInfo")
  $ev.Add('')
  $ev.Add('---- Results ----')
  foreach ($l in $summary) { $ev.Add($l) }
  $ev.Add('')
  $ev.Add('---- Baseline detail (direct, no VPN) ----')
  if (@($rows).Count -eq 0) { $ev.Add('(no baseline rows)') } else {
    $ev.Add(('{0,-2} {1,-24} {2,-4} {3,9} {4,8} {5,8} {6,8}  {7}' -f 'G', 'status', 'http', 'bytes', 'connect', 'tls', 'total', 'target'))
    foreach ($r in $rows) {
      $ev.Add(('{0,-2} {1,-24} {2,-4} {3,9} {4,8} {5,8} {6,8}  {7}' -f $r.group, $r.status, $r.httpCode, $r.bytes, $r.tConnect, $r.tTls, $r.tTotal, $r.target))
    }
  }
  $ev.Add('')
  $ev.Add('---- Errors during run (includes ones the script handled; for diagnosis) ----')
  $errGroups = @($Error | Group-Object { (($_.Exception.Message -replace '\s+', ' ').Trim()) } | Sort-Object Count -Descending | Select-Object -First 15)
  if ($errGroups.Count -eq 0) { $ev.Add('(none)') } else {
    foreach ($g in $errGroups) { $ev.Add(('- [{0}x] {1}' -f $g.Count, $g.Name)) }
  }
  $ev.Add('')
  $ev.Add('---- Raw files kept on the PC (send only if asked) ----')
  foreach ($f in @('audit.json', 'baseline.csv', 'console.log')) {
    $p = Join-Path $RunDir $f
    if (Test-Path $p) { $ev.Add(("runs\phase0-audit-{0}\{1}  sha256 {2}" -f $stamp, $f, (Get-Sha256 $p))) }
  }
  $ev.Add('==== END ====')
  $ev | Out-File $EvFile -Encoding UTF8

  Write-Host ''
  Write-Host "Status: $status"
  Write-Host "EVIDENCE FILE TO SEND BACK: $EvFile"
}
