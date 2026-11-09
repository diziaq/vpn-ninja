#!/usr/bin/env bash
# setup-server.sh v1.3 - Phase 2b of the gated rollout plan.
# 1) Hardens the server: SSH key-only login, firewall, automatic security updates, BBR.
# 2) Installs Xray-core and configures two VPN entry points:
#      VLESS + Reality + Vision on TCP 443
#      VLESS + Reality + XHTTP  on TCP 8443
#    The Reality camouflage site is picked automatically from TLS 1.3 sites in this
#    server's own /24 network (falls back to the hoster's looking-glass site).
# 3) Writes the client links to /root/vpn-links.txt (SECRET) and an evidence file
#    without secrets to /root/EVIDENCE-phase2b-server-<time>.txt
#
# Run as root:   bash /root/setup-server.sh
# v1.2: config group follows the Xray service user (newer installer runs as 'xray',
#       v1.1 assumed nogroup and Xray failed with 'permission denied').
# v1.3: version variable renamed; sourcing /etc/os-release overwrote VERSION, so the
#       evidence header showed the Ubuntu version instead of the script version.
# Re-run safely: shows the existing result. To regenerate keys: FORCE=1 bash /root/setup-server.sh

set -uo pipefail
SCRIPT_VERSION="1.3"
STAMP=$(date -u +%Y%m%d-%H%M%S)
EVIDENCE="/root/EVIDENCE-phase2b-server-$STAMP.txt"
LINKS="/root/vpn-links.txt"
CONF="/usr/local/etc/xray/config.json"
XRAY="/usr/local/bin/xray"
LOG="/root/setup-server-$STAMP.log"
exec > >(tee -a "$LOG") 2>&1

say()  { printf '\n=== %s ===\n' "$*"; }
fail() { echo "ERROR: $*"; echo "Status: FAILED at: $*" >> "$EVIDENCE.partial"; finish "FAILED: $*"; exit 1; }
EV=()
ev()   { EV+=("$*"); echo "  $*"; }

finish() {
  {
    echo "==== RU-PROBE EVIDENCE ===="
    echo "Script:     setup-server.sh v$SCRIPT_VERSION"
    echo "Host:       $(hostname -s)  ($(. /etc/os-release; echo "$PRETTY_NAME"))"
    echo "Time:       $(date -u +%Y-%m-%dT%H:%M:%SZ) UTC"
    echo "Status:     $1"
    echo
    echo "---- Results (no secrets) ----"
    for l in "${EV[@]}"; do echo "$l"; done
    echo
    echo "---- Listening ports ----"
    ss -ltnup 2>/dev/null | awk 'NR==1 || /:(22|443|8443) /'
    echo
    echo "---- Firewall ----"
    ufw status 2>/dev/null
    echo "==== END ===="
  } > "$EVIDENCE"
  rm -f "$EVIDENCE.partial"
  echo
  echo "EVIDENCE FILE: $EVIDENCE   (show it with: cat $EVIDENCE)"
}

[ "$(id -u)" -eq 0 ] || { echo "Run as root."; exit 1; }
. /etc/os-release
case "$ID" in ubuntu|debian) ;; *) echo "Ubuntu or Debian only (found $ID)."; exit 1;; esac

if [ -s "$LINKS" ] && [ "${FORCE:-0}" != "1" ]; then
  say "Already set up"
  ev "Existing setup kept (links in $LINKS). To regenerate keys: FORCE=1 bash $0"
  ev "Xray service: $(systemctl is-active xray 2>/dev/null)"
  finish "ALREADY-SET-UP"
  exit 0
fi

PUBIP=$(curl -4 -s --max-time 10 https://api.ipify.org || true)
[ -n "$PUBIP" ] || PUBIP=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
echo "$PUBIP" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || fail "could not detect the public IPv4"
ev "Public IPv4: $PUBIP"

say "1. Packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null || fail "apt-get update"
apt-get install -y curl unzip openssl ufw unattended-upgrades ca-certificates >/dev/null || fail "apt-get install"
ev "Packages: OK"

say "2. SSH: key-only login"
[ -s /root/.ssh/authorized_keys ] || fail "no SSH key in /root/.ssh/authorized_keys (run ssh-copy-id from the Mac first)"
cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak-$STAMP"
# sshd uses the FIRST value it reads, so neutralise conflicting lines elsewhere and make sure our file is read first
grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config || sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
for f in /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf; do
  [ -f "$f" ] || continue
  [ "$f" = /etc/ssh/sshd_config.d/00-hardening.conf ] && continue
  sed -i -E 's/^[[:space:]]*(PermitRootLogin|PasswordAuthentication|KbdInteractiveAuthentication|ChallengeResponseAuthentication)[[:space:]]/# hardening-disabled: &/I' "$f"
done
cat > /etc/ssh/sshd_config.d/00-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
if ! sshd -t; then cp "/etc/ssh/sshd_config.bak-$STAMP" /etc/ssh/sshd_config; fail "sshd configuration test (original restored)"; fi
systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
EFF=$(sshd -T 2>/dev/null | grep -E '^(passwordauthentication|kbdinteractiveauthentication|permitrootlogin) ' | tr '\n' ' ')
echo "$EFF" | grep -q 'passwordauthentication no' && echo "$EFF" | grep -qE 'permitrootlogin (without-password|prohibit-password)' \
  || fail "SSH hardening not effective: $EFF"
ev "SSH: key login only, verified: $EFF"
apt-get install -y fail2ban >/dev/null 2>&1 && systemctl enable --now fail2ban >/dev/null 2>&1
ev "fail2ban: $(systemctl is-active fail2ban 2>/dev/null)"

say "3. Firewall"
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow 22/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw allow 8443/tcp >/dev/null
ufw --force enable >/dev/null || fail "ufw enable"
ev "Firewall: active, open TCP 22, 443, 8443"

say "4. Automatic security updates, BBR"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
cat > /etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF
sysctl --system >/dev/null 2>&1
ev "Auto security updates: on; TCP congestion control: $(sysctl -n net.ipv4.tcp_congestion_control)"

say "5. Xray-core (official installer)"
bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null || fail "Xray install"
[ -x "$XRAY" ] || fail "xray binary missing after install"
ev "Xray: $($XRAY version | head -1)"

say "6. Reality camouflage site"
check_target() {   # TLS 1.3 + HTTP/2 with this name as SNI
  local out
  out=$(echo | timeout 8 openssl s_client -connect "$1:443" -servername "$1" -tls1_3 -alpn h2 2>/dev/null) || return 1
  echo "$out" | grep -q "ALPN protocol: h2" || return 1
  echo "$out" | grep -q "TLSv1.3" || return 1
}
cat > /tmp/scan1.sh <<'EOF'
#!/bin/bash
ip=$1
out=$(echo | timeout 4 openssl s_client -connect "$ip:443" -tls1_3 -alpn h2 2>/dev/null) || exit 0
echo "$out" | grep -q "ALPN protocol: h2" || exit 0
cn=$(printf '%s\n' "$out" | openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null | sed -n 's/.*CN=\([^,]*\).*/\1/p')
case "$cn" in ""|\**|*" "*|localhost*) exit 0;; esac
echo "$cn" | grep -q '\.' || exit 0
res=" $(getent ahostsv4 "$cn" | awk '{print $1}' | sort -u | tr '\n' ' ')"
case "$res" in *" $ip "*) echo "$ip $cn";; esac
EOF
chmod +x /tmp/scan1.sh
NET=${PUBIP%.*}
echo "Scanning $NET.0/24 for TLS 1.3 sites hosted next to this server (about 1 minute)..."
CANDS=$(for i in $(seq 1 254); do [ "$NET.$i" != "$PUBIP" ] && echo "$NET.$i"; done | xargs -P 8 -n 1 /tmp/scan1.sh 2>/dev/null)
TARGET=""
while read -r ip cn; do
  [ -n "${cn:-}" ] || continue
  if check_target "$cn" && curl -s -o /dev/null --max-time 8 -w '%{http_code}' "https://$cn/" | grep -Eq '^[23]'; then TARGET="$cn"; TARGET_IP="$ip"; break; fi
done <<< "$CANDS"
if [ -n "$TARGET" ]; then
  ev "Camouflage site: $TARGET (same /24 network, $TARGET_IP)"
else
  for f in lg.time4vps.com; do
    if check_target "$f"; then TARGET="$f"; break; fi
  done
  [ -n "$TARGET" ] || fail "no suitable camouflage site found; send this output to the assistant"
  ev "Camouflage site: $TARGET (fallback: hoster's own site; no neighbour site found)"
fi
ev "Neighbour candidates found: $(echo "$CANDS" | grep -c . || true)"

say "7. Keys and configuration"
KEYS=$($XRAY x25519)
PRIV=$(echo "$KEYS" | awk -F': *' 'tolower($1) ~ /private/ {print $2; exit}' | tr -d '[:space:]')
PUB=$(echo "$KEYS" | awk -F': *' 'tolower($1) ~ /public|password/ {print $2; exit}' | tr -d '[:space:]')
[ -n "$PRIV" ] && [ -n "$PUB" ] || fail "could not read keys from 'xray x25519'"
UUID=$($XRAY uuid | tr -d '[:space:]')
SID=$(openssl rand -hex 8)
XPATH="/$(openssl rand -hex 6)"
[ -f "$CONF" ] && cp "$CONF" "$CONF.bak-$STAMP"
cat > "$CONF" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "vless-vision", "listen": "0.0.0.0", "port": 443, "protocol": "vless",
      "settings": { "clients": [ { "id": "$UUID", "flow": "xtls-rprx-vision", "email": "owner-vision" } ], "decryption": "none" },
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": { "show": false, "dest": "$TARGET:443", "xver": 0,
          "serverNames": [ "$TARGET" ], "privateKey": "$PRIV", "shortIds": [ "$SID" ] }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] }
    },
    {
      "tag": "vless-xhttp", "listen": "0.0.0.0", "port": 8443, "protocol": "vless",
      "settings": { "clients": [ { "id": "$UUID", "email": "owner-xhttp" } ], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp", "xhttpSettings": { "path": "$XPATH", "mode": "auto" },
        "security": "reality",
        "realitySettings": { "show": false, "dest": "$TARGET:443", "xver": 0,
          "serverNames": [ "$TARGET" ], "privateKey": "$PRIV", "shortIds": [ "$SID" ] }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" }, { "protocol": "blackhole", "tag": "block" } ],
  "routing": { "rules": [ { "type": "field", "ip": [ "geoip:private" ], "outboundTag": "block" } ] }
}
EOF
# The Xray service user differs between installer versions (nobody, xray): give the
# config to that user's group, then verify the user can actually read it (v1.2).
XUSER=$(systemctl show -p User --value xray 2>/dev/null)
XUSER=${XUSER:-root}
XGROUP=$(id -gn "$XUSER" 2>/dev/null) || fail "Xray service user '$XUSER' does not exist"
chown root:"$XGROUP" "$CONF" && chmod 640 "$CONF" || fail "could not set permissions on $CONF"
runuser -u "$XUSER" -- test -r "$CONF" || fail "Xray service user '$XUSER' cannot read $CONF"
ev "Xray runs as user '$XUSER'; config readable by it (root:$XGROUP 640)"
$XRAY run -test -c "$CONF" >/dev/null 2>&1 || { $XRAY run -test -c "$CONF"; fail "Xray rejected the configuration"; }
systemctl enable xray >/dev/null 2>&1
systemctl restart xray
sleep 3
[ "$(systemctl is-active xray)" = "active" ] || { journalctl -u xray -n 20 --no-pager; fail "Xray service did not start"; }
ss -ltn | grep -q ':443 ' || fail "nothing listens on 443"
ss -ltn | grep -q ':8443 ' || fail "nothing listens on 8443"
ev "Xray service: active; listening on 443 (Vision) and 8443 (XHTTP)"

say "8. Client links"
NAME=$(hostname -s)
L1="vless://$UUID@$PUBIP:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$TARGET&fp=chrome&pbk=$PUB&sid=$SID&type=tcp#$NAME-vision"
L2="vless://$UUID@$PUBIP:8443?encryption=none&security=reality&sni=$TARGET&fp=chrome&pbk=$PUB&sid=$SID&type=xhttp&path=%2F${XPATH#/}&mode=auto#$NAME-xhttp"
umask 077
printf '%s\n%s\n' "$L1" "$L2" > "$LINKS"
chmod 600 "$LINKS"
ev "Client links written to $LINKS (2 links; secret, not included here)"
ev "Client ID ends with: ...${UUID: -4}"

finish "COMPLETED"
echo
echo "================ SECRET: YOUR TWO VPN LINKS ================"
cat "$LINKS"
echo "============================================================"
echo "Save both lines in your password manager. Do not post them in chats."
