@echo off
cd /d "%~dp0"
echo.
echo  RU-PROBE Phase 2a: check the new server's IP. About 3-5 minutes per server.
echo  Make sure servers.txt has the real IP and the test command runs on the server.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0phase2a-ipcheck.ps1"
echo.
echo  Finished. The evidence folder opens now.
echo  Send back the newest file named EVIDENCE-phase2a-ipcheck-....txt
echo.
if exist "%~dp0evidence" start "" explorer "%~dp0evidence"
pause
