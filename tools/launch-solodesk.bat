@echo off
setlocal
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0launch-solodesk.ps1"
if errorlevel 1 (
    echo.
    echo SoloDesk exited with an error.
    pause
)
