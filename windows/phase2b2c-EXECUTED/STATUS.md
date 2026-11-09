# Phase 2b + 2c package (version 3.1): EXECUTED 2026-11-08/09 (see EXECUTION-RECORD.md)

Delivered as `windows/zips/ru-probe-phase2b2c.zip` (sha256 9957af3bc9d033c8f60ad061b26e1eae594a8413d935a4ef1fda0fca91800d1e).
Files here are the exact zip contents (CRLF). Instructions: `README-V3.txt` (English), `README-RU.txt` (Russian).
Supersedes v3 (`ru-probe-v3.zip`, never run): v3 had monitor v1.0, which never wrote its evidence file.

| File | Version | Status | Tested how |
|---|---|---|---|
| `bin/xray.exe` | Xray 26.10.31 (same as server A) | bundled | official `Xray-windows-64.zip`, SHA-256 matched the release `.dgst` (zip 2e04a999...7a6a); xray.exe sha256 d5b55819...2a7e. Only xray.exe + licence bundled (geo files not used by our configs). |
| `phase2b-tunnel.ps1` | 1.0 | NOT RUN on RU-PC | byte-identical to the phase2b package (parsed with pwsh 7.4; end-to-end on Linux earlier). Skips its GitHub download because bin\xray.exe exists. |
| `phase2c-monitor.ps1` | 1.1 | NOT RUN on RU-PC | 2026-11-08 in Docker (pwsh 7.4.6 linux-arm64, Xray 26.10.31 Reality server with Vision :443 + XHTTP :8443): parse OK; cycles and console line; second start refused (exit 2, message with PID); `-Stop` graceful (final evidence, lock removed, no xray left); kill -9 then restart (stale lock taken over, 2 orphan xray killed, old file kept as RUNNING, new file); xray client killed (restarted, counted); server down (x marks); links.txt edited (reloaded to 1 link). Bugs fixed during the test: evidence never written in v1.0 ($e/$E name clash); blocked-site check failed on HTTP 400 (now any HTTP answer = reached). |

Not testable here (Windows only): keep-awake (SetThreadExecutionState), taskkill fallback, Windows file-share
semantics of the lock (PID + start-time check is the primary guard and was tested), PowerShell 5.1 specifics,
antivirus reaction to the bundled xray.exe.

Monitor verdict per link (D-18): PASS = at least 3 h line-adjusted, at least 1 h in 19:00-23:00 local, >= 97 % OK, no outage >= 1 h.
