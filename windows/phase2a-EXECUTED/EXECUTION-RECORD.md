# Phase 2a package: EXECUTED for server A

Machine: RU-PC. Delivered as `windows/zips/ru-probe-phase2a.zip` with `servers.txt` pre-filled
(`A <SERVER_A_IP> Time4VPS-Lithuania`), run via `3-RUN-SERVER-CHECK.cmd`.
Server side: the temporary test web server (equivalent of `server/test-web-start.sh`) was running on server A.

| Script | Version | Status | Run | Result file |
|---|---|---|---|---|
| `phase2a-ipcheck.ps1` | 1.0 | **EXECUTED** | 2026-11-05 23:26 local (18:26 UTC), 1.7 min, COMPLETED, no errors | `RESULTS/EVIDENCE-phase2a-ipcheck-20261105-232638.txt` |

Result summary: server A PASS. TCP 22/80/443 open 3/3. HTTP, HTTPS without SNI and HTTPS with SNI:
each 3/3 full 8 MB downloads, 10-21 Mbit/s, ~60 ms connect, no freeze.
Reuse for server B: add a line `B <ip> <note>` to `servers.txt`.
`server-test-command.txt` here is the original delivered text; prefer `server/test-web-start.sh`
(fixed: no auto-linked domain, no trailing stop command).
