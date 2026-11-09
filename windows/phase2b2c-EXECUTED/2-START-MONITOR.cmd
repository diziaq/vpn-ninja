@echo off
cd /d "%~dp0"
title RU-PROBE MONITOR
echo.
echo  RU-PROBE monitor: checks the VPN links every 2.5 minutes until you stop it.
echo  Leave this window open. Leave Remote Desktop with the X button, do NOT sign out.
echo  To stop: double-click 3-STOP-MONITOR.cmd (or press Ctrl+C here).
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0phase2c-monitor.ps1"
echo.
echo  The monitor has ended. Send back ALL files named EVIDENCE-phase2c-monitor-....txt
echo  You can start it again at any time with 2-START-MONITOR.cmd (it writes a new file).
echo.
if exist "%~dp0evidence" start "" explorer "%~dp0evidence"
pause
