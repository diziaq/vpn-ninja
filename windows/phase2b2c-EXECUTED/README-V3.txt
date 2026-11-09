RU-PROBE v3.1: VPN TUNNEL TEST + MONITOR (everything included, nothing to install)
=================================================================================

The Xray client (official release v26.10.31, bin\xray.exe) is included.
Nothing is installed, no admin rights needed, nothing is downloaded.

PREPARE
  1. Right-click the zip > Properties > tick "Unblock" if shown > OK.
     Then right-click > Extract All. You get a folder ru-probe.
  2. Check that ru-probe\bin\xray.exe exists (antivirus sometimes deletes it; if so, tell us).
  3. Open ru-probe\links.txt in Notepad, paste the vless:// lines at the end, save.

STEP 1 (about 15 min): double-click 1-RUN-TUNNEL-TEST.cmd. Wait for "Finished".

STEP 2 (best late afternoon): double-click 2-START-MONITOR.cmd
  One short line every 2.5 minutes:  + OK   ~ partly   x failed   line = office internet
  Keep it running at least 3 hours including the evening (19:00-23:00).
  Leave Remote Desktop with the X button. Do NOT sign out.

STOP: double-click 3-STOP-MONITOR.cmd (or Ctrl+C in the monitor window).
  Window closed or PC restarted? Start 2-START-MONITOR.cmd again: new file, no harm.
  It never runs twice; if one is running it says so and how to stop it.

SEND BACK every file in ru-probe\evidence (no keys inside).
  After testing, delete the vless:// lines from links.txt.
