@echo off
cd /d "%~dp0"
echo.
echo  Stopping the RU-PROBE monitor (it finishes its evidence file first; up to 90 seconds) ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0phase2c-monitor.ps1" -Stop
echo.
pause
