#!/usr/bin/env bash
# Tests for tools/privacy.py: redaction keeps bytes (CRLF), replaces mapped and unknown values,
# keeps allowlisted IPs; the scanner blocks private values and passes clean files.
# Uses a temporary private map; needs no network and writes only under a temp dir.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf -- "$T"' EXIT
export VPN_NINJA_PRIVATE="$T/private"
mkdir -p "$VPN_NINJA_PRIVATE"
printf '%s\t%s\n' '203\.0\.113\.7' '<SERVER_X_IP>' '(?i)acme corp' 'the employer' > "$VPN_NINJA_PRIVATE/redact-map.tsv"
P="python3 $ROOT/tools/privacy.py"
fail() { echo "FAIL: $*" >&2; exit 1; }
# Sample values are assembled at runtime so this file itself passes the commit guard.
ip_mapped="203.0.113.$((3 + 4))"            # RFC 5737 documentation range
ip_other="100.64.$((1 + 1)).9"            # shared address space: not allowlisted
uuid="36a6a1b2-1111-2222-3333-$((4444 * 100000000 + 55556666))"

# 1. redaction: mapped value, unknown IP, allowlisted IP, CRLF preserved
printf 'server %s\r\nother %s\r\nlocal 127.0.0.1 at ACME Corp\r\n' "$ip_mapped" "$ip_other" > "$T/in.txt"
$P redact "$T/in.txt" "$T/out.txt"
expected=$'server <SERVER_X_IP>\r\nother <ip>\r\nlocal 127.0.0.1 at the employer\r\n'
[ "$(cat "$T/out.txt"; printf x)" = "${expected}x" ] || fail "redaction output differs: $(od -c "$T/out.txt" | head -5)"

# 2. scanner blocks the original, passes the redacted copy
if $P scan "$T/in.txt" > "$T/scan1.log" 2>&1; then fail "scanner passed a file with private values"; fi
grep -q 'private value' "$T/scan1.log" || fail "mapped value not reported"
grep -q 'IPv4 not in' "$T/scan1.log" || fail "unknown IPv4 not reported"
$P scan "$T/out.txt" > "$T/scan2.log" 2>&1 || fail "scanner blocked a clean file: $(cat "$T/scan2.log")"

# 3. generic checks work without any map
rm "$VPN_NINJA_PRIVATE/redact-map.tsv"
printf 'id %s\n' "$uuid" > "$T/uuid.txt"
if $P scan "$T/uuid.txt" > "$T/scan3.log" 2>&1; then fail "UUID not blocked without map"; fi
grep -q 'missing' "$T/scan3.log" || fail "missing-map warning not shown"

# 4. redaction refuses to run without the map (never 'redact' with nothing to redact)
if $P redact "$T/in.txt" "$T/out2.txt" 2>/dev/null; then fail "redact ran without a map"; fi

echo "privacy tests: PASS"
