@echo off
cd /d "%~dp0"
echo.
echo  RU-PROBE quick check. Takes 2-4 minutes. Do not close this window.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0phase0-quick.ps1"
echo.
echo  Finished. The evidence folder opens now.
echo  Send back the newest file named EVIDENCE-phase0-quick-....txt
echo.
if exist "%~dp0evidence" start "" explorer "%~dp0evidence"
pause
