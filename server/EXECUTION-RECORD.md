# Server scripts: execution record

| Script | Status on server A (<SERVER_A_IP>) |
|---|---|
| `test-web-start.sh` | EXECUTED 2026-11-05 (pasted as a command block; equivalent content). Needed for Phase 2a. |
| `test-web-stop.sh` | EXECUTED 2026-11-08 (equivalent pkill command); ports 80/443/8443 confirmed free. |
| `ssh-hardening-fix.sh` | EXECUTED 2026-11-06, verified: `sshd -T` -> passwordauthentication no, kbdinteractiveauthentication no, permitrootlogin without-password; clean external test -> `Permission denied (publickey)`. |
| `setup-server.sh` | v1.1 run 2026-11-08: FAILED at Xray start (config.json permission denied; installer now uses user `xray`). v1.2 run 2026-11-08: COMPLETED, evidence `evidence/EVIDENCE-phase2b-server-20261107-215823.txt`. v1.3 (evidence header version fix only) not run on A; use it for server B. Do not rerun with FORCE on A. |
