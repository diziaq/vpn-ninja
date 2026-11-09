# Phase 1 package: EXECUTED

Machine: RU-PC. Delivered as `windows/zips/ru-probe-phase1.zip`, run via `2-RUN-PHASE1-HOSTING.cmd`.

| Script | Version | Status | Run | Result file |
|---|---|---|---|---|
| `phase1-hosting.ps1` | 1.0 | **EXECUTED** | 2026-11-05 21:43 local (16:43 UTC), 2.6 min, COMPLETED, no errors | `RESULTS/EVIDENCE-phase1-hosting-20261105-214320.txt` |

Integrity: the evidence records `providers.txt` sha256 prefix `9a1568d3d8171773`; the `providers.txt` in this
folder has the same hash, so this is exactly the list that was executed.

Result summary: Gate G1 PASS (Time4VPS LT and BuyVM LU full 2 MB). Vultr partial (Frankfurt froze at
15 957 bytes twice, Amsterdam froze once then OK, Stockholm and Warsaw OK). Hetzner, OVH, Linode blocked
(no TCP connect). HostHatch test URL returns a 12 KB page, Leaseweb 404, DigitalOcean DNS fail
(test URLs broken, inconclusive). Yandex mirror 27.7 Mbit/s, Cloudflare 28 Mbit/s. Line checks:
UDP 53 OK to 1.1.1.1/8.8.8.8/77.88.8.8, TCP 22/80/443/2053/8080/8443 open, no HTTPS inspection.
