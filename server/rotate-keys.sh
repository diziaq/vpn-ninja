#!/usr/bin/env bash
# rotate-keys.sh v1.0 - replace all VPN secrets on this server, keep everything else.
#
# Use when the vless:// links may have leaked (shared on another machine, chat, photo).
# Replaces: client ID (UUID), Reality key pair, short ID, XHTTP path.
# Keeps:    ports, camouflage site (dest + serverNames), firewall, SSH, everything else.
# After it: the OLD links stop working at once; new links are in /root/vpn-links.txt (SECRET).
#
# Safe: backs up the config, validates the new one with 'xray run -test', and puts the
# old config back if the new one is rejected or Xray does not come up. Verifies the
# effective state (service active, both ports listening, old client ID gone from the config).
# Writes an evidence file without secrets: /root/EVIDENCE-rotate-keys-<time>.txt
#
# Run as root:   bash /root/rotate-keys.sh

set -uo pipefail
SCRIPT_VERSION="1.0"
STAMP=$(date -u +%Y%m%d-%H%M%S)
CONF="${CONF:-/usr/local/etc/xray/config.json}"
XRAY="${XRAY:-/usr/local/bin/xray}"
LINKS="${LINKS:-/root/vpn-links.txt}"
EVDIR="${EVDIR:-/root}"
EVIDENCE="$EVDIR/EVIDENCE-rotate-keys-$STAMP.txt"
BACKUP="$CONF.bak-rotate-$STAMP"
EV=()
ev()   { EV+=("$*"); echo "  $*"; }
say()  { printf '\n=== %s ===\n' "$*"; }
finish() {
  {
    echo "==== RU-PROBE EVIDENCE ===="
    echo "Script:     rotate-keys.sh v$SCRIPT_VERSION"
    echo "Host:       $(hostname -s)"
    echo "Time:       $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC"
    echo "Status:     $1"
    echo
    echo "---- Results (no secrets) ----"
    for l in "${EV[@]}"; do echo "$l"; done
    echo
    echo "---- Listening ports ----"
    ss -ltn 2>/dev/null | awk 'NR==1 || /:(443|8443) /'
    echo "==== END ===="
  } > "$EVIDENCE"
  echo
  echo "EVIDENCE FILE: $EVIDENCE   (show it with: cat $EVIDENCE)"
}
fail() { echo "ERROR: $*"; ev "FAILED: $*"; finish "FAILED: $*"; exit 1; }
restore() {
  ev "Restoring the previous configuration from backup"
  cp -p "$BACKUP" "$CONF" && systemctl restart xray
  sleep 2
  ev "Xray after restore: $(systemctl is-active xray 2>/dev/null)"
}

[ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }
[ -s "$CONF" ] || { echo "No Xray config at $CONF. Run setup-server.sh first."; exit 1; }
[ -x "$XRAY" ] || { echo "No xray binary at $XRAY."; exit 1; }
command -v python3 >/dev/null || { echo "python3 is missing (apt-get install -y python3)."; exit 1; }

say "1. Current configuration"
OLD_IDS=$(python3 - "$CONF" <<'PY'
import json, sys
c = json.load(open(sys.argv[1]))
ids = sorted({cl["id"] for ib in c.get("inbounds", []) for cl in ib.get("settings", {}).get("clients", [])})
print(" ".join(ids))
PY
) || fail "could not read $CONF as JSON"
[ -n "$OLD_IDS" ] || fail "no client IDs found in $CONF"
for i in $OLD_IDS; do ev "Old client ID ends with: ...${i: -4} (will be removed)"; done
TARGET=$(python3 -c 'import json,sys; c=json.load(open(sys.argv[1])); print([ib for ib in c["inbounds"] if ib["port"]==443][0]["streamSettings"]["realitySettings"]["serverNames"][0])' "$CONF") || fail "no Reality inbound on port 443"
ev "Camouflage site kept: $TARGET"

say "2. New secrets"
KEYS=$("$XRAY" x25519)
PRIV=$(echo "$KEYS" | awk -F': *' 'tolower($1) ~ /private/ {print $2; exit}' | tr -d '[:space:]')
PUB=$(echo "$KEYS" | awk -F': *' 'tolower($1) ~ /public|password/ {print $2; exit}' | tr -d '[:space:]')
[ -n "$PRIV" ] && [ -n "$PUB" ] || fail "could not read keys from 'xray x25519'"
UUID=$("$XRAY" uuid | tr -d '[:space:]')
[ ${#UUID} -eq 36 ] || fail "could not generate a client ID"
SID=$(openssl rand -hex 8)
XPATH="/$(openssl rand -hex 6)"
ev "New client ID ends with: ...${UUID: -4}"

say "3. Write and validate"
cp -p "$CONF" "$BACKUP" || fail "could not back up $CONF"
ev "Backup: $BACKUP"
TMP="${CONF%.json}.new-$STAMP.json"   # xray picks the format from the .json extension
python3 - "$CONF" "$TMP" "$UUID" "$PRIV" "$SID" "$XPATH" <<'PY' || fail "could not build the new configuration"
import json, sys
src, dst, uuid, priv, sid, xpath = sys.argv[1:7]
c = json.load(open(src))
n = 0
for ib in c.get("inbounds", []):
    if ib.get("protocol") != "vless":
        continue
    for cl in ib["settings"]["clients"]:
        cl["id"] = uuid
        n += 1
    ss = ib.get("streamSettings", {})
    rs = ss.get("realitySettings")
    if rs is not None:
        rs["privateKey"] = priv
        rs["shortIds"] = [sid]
    if ss.get("network") == "xhttp":
        ss.setdefault("xhttpSettings", {})["path"] = xpath
if n == 0:
    sys.exit("no vless clients")
json.dump(c, open(dst, "w"), indent=2)
PY
chown --reference="$BACKUP" "$TMP" && chmod --reference="$BACKUP" "$TMP" || fail "could not copy owner/permissions"
"$XRAY" run -test -c "$TMP" >/dev/null 2>&1 || { "$XRAY" run -test -c "$TMP"; rm -f "$TMP" "$BACKUP"; fail "Xray rejected the new configuration (old one untouched)"; }
mv -f "$TMP" "$CONF" || fail "could not install the new configuration"
ev "New configuration validated by 'xray run -test' and installed"

say "4. Restart and verify"
systemctl restart xray
sleep 3
OK=1
[ "$(systemctl is-active xray 2>/dev/null)" = "active" ] || OK=0
ss -ltn | grep -q ':443 ' || OK=0
ss -ltn | grep -q ':8443 ' || OK=0
if [ "$OK" -ne 1 ]; then
  journalctl -u xray -n 20 --no-pager 2>/dev/null
  restore
  fail "Xray did not come up with the new configuration; previous configuration restored"
fi
for i in $OLD_IDS; do grep -q "$i" "$CONF" && fail "old client ID still present in $CONF"; done
ev "Xray service: active; listening on 443 (Vision) and 8443 (XHTTP); old client IDs gone from the effective config"

say "5. New client links"
PUBIP=$(curl -4 -s --max-time 10 https://api.ipify.org || true)
[ -n "$PUBIP" ] || PUBIP=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
echo "$PUBIP" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || fail "could not detect the public IPv4 (config already rotated; old links are dead)"
NAME=$(hostname -s)
L1="vless://$UUID@$PUBIP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$TARGET&fp=chrome&pbk=$PUB&sid=$SID&type=tcp#$NAME-vision"
L2="vless://$UUID@$PUBIP:8443?encryption=none&security=reality&sni=$TARGET&fp=chrome&pbk=$PUB&sid=$SID&type=xhttp&path=%2F${XPATH#/}&mode=auto#$NAME-xhttp"
umask 077
printf '%s\n%s\n' "$L1" "$L2" > "$LINKS"
chmod 600 "$LINKS"
# The backup holds the OLD secrets only; they are dead now, but there is no reason to keep them.
rm -f "$BACKUP"
ev "New links written to $LINKS (2 links; secret, not included here). Old-secret backup deleted."

finish "COMPLETED"
echo
echo "================ SECRET: YOUR TWO NEW VPN LINKS ================"
cat "$LINKS"
echo "================================================================"
echo "Replace the old lines in your password manager. The old links no longer work."
