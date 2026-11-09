#!/usr/bin/env bash
# Phase 2a helper: temporary test web server (ports 80 and 443) serving an 8 MB /test.bin.
# Run on a NEW server before VPN setup, then run windows/phase2a from the Russian PC.
# Stop it with test-web-stop.sh before running setup-server.sh (port 443 is needed by Xray).
mkdir -p /root/probe && cd /root/probe || exit 1
head -c 8000000 /dev/urandom > test.bin
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3 -subj "/CN=probe" 2>/dev/null
cat > tls.py <<'PYEOF'
import http.server, ssl
s = http.server.ThreadingHTTPServer(('0.0.0.0', 443), http.server.SimpleHTTPRequestHandler)
c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); c.load_cert_chain('cert.pem', 'key.pem')
s.socket = c.wrap_socket(s.socket, server_side=True)
s.serve_forever()
PYEOF
if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then ufw allow 80/tcp; ufw allow 443/tcp; fi
nohup python3 -m http.server 80 >/dev/null 2>&1 &
nohup python3 tls.py >/dev/null 2>&1 &
sleep 2; ss -ltnp | grep -E ':(80|443) ' && echo "TEST SERVER RUNNING"
