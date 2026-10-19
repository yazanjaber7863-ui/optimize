@echo off
rem One-click Optimize setup for a fresh Windows install. With no clicking it:
rem   - installs all your apps from the Install tab
rem   - applies the My Setup tweaks (a restore point is made first)
rem   - removes the Windows bloat apps picked under Remove Windows Apps
rem Double-click it from the Optimize folder and say Yes to the admin prompt.
cd /d "%~dp0"
title Optimize - full setup
echo Building Optimize...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Compile.ps1"
if errorlevel 1 (
    echo Build failed.
    pause
    exit /b 1
)
echo Running the full setup. This can take 30+ minutes, leave this window open.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0winutil.ps1" -Preset FullSetup
echo.
echo Done. Restart the PC to finish.
pause
