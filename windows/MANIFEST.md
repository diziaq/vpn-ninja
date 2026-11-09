# Windows packages for the Russian PC: manifest

| Folder | Zip that ran on the Russian PC | Status | Evidence |
|---|---|---|---|
| `phase0-EXECUTED/` | `ru-probe-phase0.zip` | quick check EXECUTED 2026-11-05; full audit and heartbeat not run (the phase2c monitor covers the heartbeat) | `phase0-EXECUTED/RESULTS/`, `../evidence/` |
| `phase1-EXECUTED/` | `ru-probe-phase1.zip` | EXECUTED 2026-11-05 | `phase1-EXECUTED/RESULTS/`, `../evidence/` |
| `phase2a-EXECUTED/` | `ru-probe-phase2a.zip` | EXECUTED 2026-11-05 for server A | `phase2a-EXECUTED/RESULTS/`, `../evidence/` |
| `phase2b2c-EXECUTED/` | `ru-probe-phase2b2c.zip` (package version 3.1, sha256 9957af3b...0d1e) | EXECUTED 2026-11-08/09 for server A: Phase 2b PASS (4/5 variants), monitor 12 h PASS (100 %). phase2b-tunnel.ps1 v1.0 + phase2c-monitor.ps1 v1.1, Xray 26.10.31. | `phase2b2c-EXECUTED/RESULTS/`, `../evidence/` |

## Rules

- Each executed folder holds the files that ran, an `EXECUTION-RECORD.md` and the returned evidence in
  `RESULTS/`. **Do not edit executed packages**; copy to a new `phaseX-READY-NOT-RUN/` folder, bump the
  script version, and rename it to `-EXECUTED` once its evidence is in.
- In git these are **redacted copies**: real server addresses, hostnames and the Russian PC's location are
  replaced by placeholders (`<SERVER_A_IP>`, ...). The exact files and the zips as delivered are in
  `.private/archive/vpn-russia-materials/windows/` (local only, not in git). A package that needs a real
  value (for example `servers.txt`) gets it filled in from `.private/servers.md` when the zip is built.
- Zips and binaries are never committed. Build a zip with `tools/build-ru-probe.sh <folder>`: it adds
  `bin/xray.exe` from the pinned, checksum-verified Xray release and writes `dist/ru-probe-<name>.zip`.
- Raw run folders (`runs/`: xray logs, CSV, console logs) stay in `.private/`; only evidence files are
  committed.
