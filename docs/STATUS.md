# STATUS (as of 2026-11-09)

Real addresses, hostnames and the camouflage site are placeholders here; real values: `.private/servers.md`.

## Gates

| Gate | Question | Result | Evidence |
|---|---|---|---|
| 0.1 | Employer allows working from Russia and tests on RU-PC? | **OPEN** (user's action) | none |
| G0 | RU-PC usable and representative? | **PASS (provisional)**: tools run, regular RU ISP, filtering visible (Instagram/YouTube/X timeout, LinkedIn TLS fail), no proxy/inspection. Overnight uptime later proven by the 12 h monitor (no gaps). | `evidence/EVIDENCE-phase0-quick-20261105-210922.txt`, line checks in phase1 evidence |
| G1 | Two or more hosters reachable? | **PASS**: Time4VPS (LT) and BuyVM (LU) full 2 MB downloads. Vultr partial (Frankfurt freeze at 15 957 bytes, Amsterdam unstable, Stockholm/Warsaw OK). Hetzner, OVH, Linode fully blocked. HostHatch/Leaseweb inconclusive (bad test URLs). | `evidence/EVIDENCE-phase1-hosting-20261105-214320.txt` |
| 2a (server A) | Is <SERVER_A_IP> usable from RU? | **PASS**: ports 22/80/443 open 3/3; HTTP, HTTPS no-SNI and HTTPS SNI each 3/3 full 8 MB, 10-21 Mbit/s, no freeze. | `evidence/EVIDENCE-phase2a-ipcheck-20261105-232638.txt` |
| G2 | VPN protocols survive from RU (both servers, + monitor)? | **SERVER A: PASS** (2026-11-08/09). Phase 2b: 4/5 variants, Vision 3/3. Monitor (D-18): 12 h 02 m, 289 cycles, both links 289/289 OK (100 %), office line 100 %, no gaps (keep-awake worked), evening 2 h 50 m covered, no errors; median 1 MB speed Vision 7.2 / XHTTP 11.1 Mbit/s. Keys rotated afterwards (D-19). **Open: server B** (D-17). | `evidence/EVIDENCE-phase2b-tunnel-20261108-195210.txt`, `evidence/EVIDENCE-phase2c-monitor-20261108-200950.txt` |
| G3 | Works on 2+ real home ISPs (friends)? | NOT STARTED | - |
| G4 | Work laptop needs a router? | NOT DECIDED. Known: GlobalProtect portal `<EMPLOYER_GP_PORTAL>` (<EMPLOYER_GP_PORTAL_IP>, the employer's company AS, DE) answers HTTPS from RU (prelogin HTTP 200). GP tunnel (IPsec UDP 4501) untested. AWS Client VPN is OpenVPN-based (OpenVPN blocked in RU since Feb 2026); its endpoint/proto not yet known. AWS EC2/S3 in 6 regions reachable from RU-PC without throttling. | phase0 quick evidence |
| G5 | Router stack + twin pass? | NOT STARTED: router not available in Georgia (see D-07). | - |

## Server A (Time4VPS, <SERVER_A_IP>)

- Ubuntu 24.04.5 after `apt-get upgrade` + reboot on 2026-11-08; IPv6 also present (<SERVER_A_IPV6>).
- SSH key-only login verified again 2026-11-08 (`sshd -T`: permitrootlogin without-password,
  passwordauthentication no, kbdinteractiveauthentication no). Root password set by the user for the
  Time4VPS emergency console (stored in the password manager).
- Phase 2a test web server stopped 2026-11-08 (ports 80/443/8443 were free before setup).
- **`setup-server.sh` DONE** (v1.1 failed at Xray start: config permission; v1.2 completed 2026-11-08,
  run timestamp 20261107-215823 UTC). Xray 26.10.31 runs as user `xray`, listens on 443 (Vision)
  and 8443 (XHTTP); ufw allows 22/443/8443 (v4+v6); fail2ban active; unattended upgrades on; BBR.
  Evidence: `evidence/EVIDENCE-phase2b-server-20261107-215823.txt` (header shows "v24.04.5 LTS":
  version-variable bug, fixed in v1.3).
- **Reality camouflage site: <CAMOUFLAGE_A>** (<CAMOUFLAGE_A_IP>, same /24).
- **Keys rotated 2026-11-09** (`server/rotate-keys.sh` v1.0): old links (client ID `...fe0c`) were on a third-party
  machine and are now dead; new client ID ends `...4831`. Evidence: `evidence/EVIDENCE-rotate-keys-20261109-055215.txt`.
  Links in `/root/vpn-links.txt` and the user's password manager.
- Management from the work Mac: it is employer-managed (MDM) and GlobalProtect must be
  disconnected (menu bar) for direct SSH; do not disable the GP network extension.
  The agent's guard blocks remote shells; the user runs server commands (LESSONS L17).

## Server B

Not purchased. Candidates: BuyVM Luxembourg (KVM Slice 1 GB $3.50/mo; refund only within 3 days
and only for card/PayPal; often out of stock; do not take the Cloudzy alternative) or Vultr
Stockholm (hourly; IP lottery: test with Phase 2a, destroy and recreate if frozen).

## Router

Decision: two GL-MT3000 (Beryl AX) only. Not available in Georgia; user arrives in Russia in
~3 weeks; plan is to order to Russia for delivery by arrival and to prepare a complete router kit
in advance (see `docs/NEXT-STEPS.md` item 7 and `docs/router-arrival-check.html`).

## Known issues and lessons

All problems met so far, their fixes and the rules they left: `docs/LESSONS.md`.
