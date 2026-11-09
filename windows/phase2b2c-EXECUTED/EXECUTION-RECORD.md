# Execution record: phase2b2c package (version 3.1)

RU-PC (machine hash ebed7270), server A links (client ID ...fe0c, since rotated: D-19).

| Step | Status | Evidence |
|---|---|---|
| 1-RUN-TUNNEL-TEST (phase2b-tunnel.ps1 v1.0) | EXECUTED 2026-11-08 19:52-20:02 local (UTC+5). 4 of 5 variants PASS (Vision chrome/firefox/safari, XHTTP chrome); XHTTP firefox PARTIAL. | `RESULTS/EVIDENCE-phase2b-tunnel-20261108-195210.txt` |
| 2-START-MONITOR (phase2c-monitor.ps1 v1.1), start 1 | 2026-11-08 20:08, one cycle (all OK), then window closed (status left RUNNING, as designed). | `RESULTS/EVIDENCE-phase2c-monitor-20261108-200829.txt` |
| 2-START-MONITOR, start 2 | 2026-11-08 20:09 to 2026-11-09 08:12 (12 h 02 m), stopped with 3-STOP-MONITOR. 289 cycles; both links 289/289 OK; office line 100 %; 0 gaps; keep-awake True; evening 2 h 50 m. VERDICT PASS for both links. | `RESULTS/EVIDENCE-phase2c-monitor-20261108-200950.txt` |

Raw run folders (xray logs, tunnel.csv, console.log; checked: no links or full client IDs) in `RESULTS/runs/`.
Windows-only behaviour confirmed in this run: keep-awake (no gaps over 12 h), 3-STOP-MONITOR graceful stop, restart after a closed window.
