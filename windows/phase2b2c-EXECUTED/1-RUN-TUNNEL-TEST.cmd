@echo off
cd /d "%~dp0"
echo.
echo  RU-PROBE Phase 2b: VPN tunnel test. Takes 10-15 minutes. Do not close this window.
echo  The Xray client is included in the bin folder. Nothing is downloaded or installed.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0phase2b-tunnel.ps1"
echo.
echo  Finished. The evidence folder opens now.
echo  Send back the newest file named EVIDENCE-phase2b-tunnel-....txt
echo.
if exist "%~dp0evidence" start "" explorer "%~dp0evidence"
pause
