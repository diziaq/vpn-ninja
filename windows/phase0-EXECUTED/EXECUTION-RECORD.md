# Phase 0 package: EXECUTED (partially)

Machine: RU-PC (Windows 11 Pro build 26200, office in <RU-PC town>, ISP <RU-PC ASN> <RU-PC ISP>), normal user, no admin.
Delivered as `windows/zips/ru-probe-phase0.zip`, run via `1-RUN-QUICK-CHECK.cmd`.

| Script | Version | Status | Run | Result file |
|---|---|---|---|---|
| `phase0-quick.ps1` | 1.0 | **EXECUTED** | 2026-11-05 21:09 local (16:09 UTC), 1.0 min, COMPLETED, no errors | `RESULTS/EVIDENCE-phase0-quick-20261105-210922.txt` |
| `phase0-audit.ps1` | 1.1 | NOT RUN (deep check postponed by user; its line checks were folded into phase1) | - | - |
| `heartbeat.ps1` | 1.1 | NOT RUN (needed before the 24 h soak; may be replaced by the planned soak script) | - | - |

`services.txt` in this folder is the executed version: GlobalProtect portal line filled in,
AWS line left as placeholder (skipped).

Result summary: tools run; regular Russian ISP egress; filtering visible (Instagram, YouTube, X time out,
LinkedIn TLS fail; controls and Russian sites OK); AWS EC2/S3 reachable in 6/6 regions, no 16 KB stall on
1 MB CloudFront and two S3 listings; aws.amazon.com timed out; GlobalProtect prelogin HTTP 200.
Note: the OS caption in the evidence is in Russian because Windows localizes it ("Microsoft Windows 11 Pro"); raw evidence files are kept unchanged.
