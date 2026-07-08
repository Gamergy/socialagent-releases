@echo off
rem SocialAgent installer - double-click me. Elevates to admin (needed to
rem install Docker/Chrome and open the helper's firewall rule), then runs
rem install.ps1 from this folder. Safe to run again after a restart.
cd /d "%~dp0"
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator permission...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c cd /d \"%~dp0\" && powershell -NoProfile -ExecutionPolicy Bypass -File \".\install.ps1\"' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File ".\install.ps1"
