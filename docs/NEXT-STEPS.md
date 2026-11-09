# NEXT STEPS (ordered; respect the gates). As of 2026-11-09.

Arrival in Russia around 2026-11-29. Done so far: phases 0, 1, 2a, server A setup, 2b, 2c monitor
(G2 for server A PASS), key rotation. History of finished items: `git log` and `docs/STATUS.md`.
Items marked **BUILD** need new code; follow `CLAUDE.md` (conventions, privacy, test before shipping).

## 1. Server B (unblocked by D-17)

- Buy BuyVM Luxembourg (KVM Slice 1 GB, ~$3.50/mo; refund only within 3 days, card/PayPal; often out of
  stock; do not take the Cloudzy alternative), else Vultr Stockholm (hourly; destroy and recreate if its
  address freezes in 2a). Register from normal Georgian internet, no VPN (D-14).
- Phase 2a for B: `server/test-web-start.sh` on B; new package `windows/phase2a-b-READY-NOT-RUN/` copied from
  `phase2a-EXECUTED` with `servers.txt` = `B <ip> <note>` (real IP filled in at build time from
  `.private/servers.md`; never committed).
- If PASS: `setup-server.sh` v1.3 on B, then Phase 2b + monitor with B's links (package copied from
  `phase2b2c-EXECUTED`; consider monitor v1.2 first, item 2).
- Accept (G2 complete): at least one Vision variant passes on B; monitor >= 3 h incl. evening >= 97 % on B.

## 2. BUILD: monitor v1.2 (before the next Russian-PC session)

- Every 6th cycle (~15 min) add a large download (default 20 MB) per link, reported separately (OK count,
  median Mbit/s): the 1 MB check under-reads speed (TCP ramp-up) and cannot show a stall that only hits big
  transfers. Keep the per-cycle verdict on the small checks.
- Optional: rotate the fingerprint per cycle (chrome/firefox/safari) to catch fingerprint-specific blocks.
- Test in Docker as for v1.1 (see `docs/LESSONS.md`, "Testing Windows scripts on a Mac").

## 3. BUILD: per-client IDs (`server/manage-clients.sh`) before any link leaves our devices (D-19)

- add/list/remove a named client UUID in the Xray config (both inbounds), validate with `xray run -test`,
  restart, verify, print that client's links; keep `clients.tsv` (name, created, expires) in `/root`.
- Testers (Russian PC, friends) get their own client; revoke it after the test instead of rotating everyone.

## 4. Friends (G3)

- Friend instructions in Russian: Hiddify (or Happ / v2RayTun), import link, test list, 30 min video,
  home Wi-Fi + mobile + evening, report ISP/operator/city/whitelist mode.
- Accept: passes on 2+ different home ISPs (ideally the one at the future address).

## 5. AmneziaWG 3.1 for phones; OpenVPN probe (G4)

- AmneziaWG: AmneziaVPN app on a personal device adds server A by SSH and installs **only AmneziaWG**
  (never its Xray container: port 443 conflict). Docker publishes the UDP port and bypasses ufw; confirm
  reachability. Test on friends' phones (the Russian PC cannot: no admin).
- OpenVPN probe (decides G4 for AWS Client VPN): temporary OpenVPN server on server B (UDP 1194 + a TCP port),
  OpenVPN Connect on a friend's phone in Russia, 10 minutes, then remove.
- G4 decision: if AWS VPN (OpenVPN) is blocked or GlobalProtect unstable -> router required (expected).

## 6. BUILD: router kit (pilot unit in Georgia, D-20)

- Pilot: when the Georgian unit arrives, arrival check, then the Router setup tab of `docs/index.html`, steps 1-7; record
  every deviation and replace the guide's UNVERIFIED notes with tested steps. Then build the script below on it.

- `router/` for GL-MT3000 on official OpenWrt 25.12.x: sysupgrade image(s) + recovery notes (U-Boot web
  recovery) + checksums downloaded in advance; offline copies of sing-box, Podkop, travelmate, luci apps.
- `setup-router.sh`: LAN 10.77.0.1/24, SSIDs WORK (full tunnel) and DIRECT, WPA2/WPA3 mixed, 2.4 + 5 GHz,
  non-DFS channels 36-48, 80 MHz, MSS clamping, Podkop URLTest over the Vision links of A and B (URLTest does
  not take XHTTP), DNS via tunnel, travelmate, admin password, no cloud management.
- Twin test before arrival: sing-box (Podkop's engine) on the Russian PC with the router's outbound settings,
  reusing the phase2b harness. Accept: passes like phase 2b.
- Verify Podkop compatibility with OpenWrt 25.12.x (apk package manager).
- Day-1 guide; the hardware check is the Router arrival check tab of `docs/index.html`.

## 7. Purchases and dates

- One GL-MT3000 bought in Georgia (pilot, D-20). In Russia 2 more from different sellers (MAIN Global; CN only as
  SPARE): order **~2026-11-13 to 11-15** from sellers on
  major Russian marketplaces (listings show ~14-day cross-border delivery); check pickup-point storage days and
  extension; arrival check per the Router arrival check tab of `docs/index.html`.
- Own domain for self-steal (~$10/yr, Cloudflare Registrar or similar, non-.ru, privacy; DNS-only record):
  after server B; longevity upgrade, not urgent (neighbour camouflage passed from Russia).
  **BUILD** `server/setup-selfsteal.sh` then (Caddy on a local port, Reality dest/serverNames -> own domain,
  same keys, validate, evidence) and re-run 2b.
- Amnezia Premium: 7-14 days before departure.
- Server A: decide long-term billing before the 30-day money-back ends (~2026-12-05).

## 8. Before departure and Day 1

- Final Russian-PC test; monitor left running there; apps on phone and personal laptop with VLESS + AWG +
  Premium; secrets backed up (incl. `~/.ssh/vpn_servers` and its passphrase) in the password manager.
- Day 1: a foreign SIM may have no data/SMS for up to 24 h; phone/laptop via apps; first evening router setup.
- Employer approval (plan step 0.1) is the user's to obtain; nothing here is designed to hide the location.
