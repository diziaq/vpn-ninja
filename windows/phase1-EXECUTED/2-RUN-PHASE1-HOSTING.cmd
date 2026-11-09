@echo off
cd /d "%~dp0"
echo.
echo  RU-PROBE Phase 1: hosting providers. Takes 5-10 minutes. Do not close this window.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0phase1-hosting.ps1"
echo.
echo  Finished. The evidence folder opens now.
echo  Send back the newest file named EVIDENCE-phase1-hosting-....txt
echo.
if exist "%~dp0evidence" start "" explorer "%~dp0evidence"
pause
