RU-PROBE: PHASE 1, HOSTING PROVIDERS
====================================

WHAT THIS CHECKS
Which hosting providers this Russian line can reach without blocking or the
"freeze after ~16 KB" throttling, BEFORE we rent any server. For each provider
it downloads the first 2 MB of a public test file from their network.
It also repeats a few line checks (UDP DNS, open ports, HTTPS inspection).
Read-only: installs nothing, changes no settings, no admin rights needed.
Data used: up to about 80 MB in total. Time: 5-10 minutes.

HOW TO RUN (same as Phase 0)
1. Copy ru-probe-phase1.zip to the Windows PC.
2. Right-click the zip > Properties > tick "Unblock" if shown > OK.
3. Right-click > Extract All... > Extract. Any location works.
4. Open the ru-probe folder and double-click  2-RUN-PHASE1-HOSTING.cmd
   ("Do you want to run this file?" -> Run;
    "Windows protected your PC" -> More info -> Run anyway)
5. When it finishes the evidence folder opens. Send back the newest file:
      EVIDENCE-phase1-hosting-<date>-<time>.txt

If double-click is blocked: open the ru-probe folder, type  powershell  in the
File Explorer address bar, press Enter, and run:
   powershell -NoProfile -ExecutionPolicy Bypass -File .\phase1-hosting.ps1

HOW TO READ THE RESULT (for the curious)
  OK          2 MB arrived: provider network reachable without throttling
  SLOW        data flows but under 1 MB in 20 seconds
  FREEZE      stalls after a few KB: typical Russian throttling of that network
  BLOCKED     no connection, reset or TLS failure
  UNSTABLE    failed once, worked on retry
  URL-BROKEN  the test file moved; says nothing about blocking
The list of providers is in providers.txt; do not edit unless asked.

EVIDENCE RULE (unchanged)
One file per run in the evidence folder, written even on failure or Ctrl+C.
Public IP masked, computer name replaced by a short code, no passwords.
Raw data stays in the runs folder; send it only if asked.
