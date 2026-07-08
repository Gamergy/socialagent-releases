@echo off
rem SocialAgent uninstaller - double-click me. Copies the uninstall script to
rem TEMP first (so the app folder can delete itself), elevating for the
rem firewall-rule and Docker cleanup.
cd /d "%~dp0"
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator permission...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"%~f0\"' -Verb RunAs"
    exit /b
)
copy /y "%~dp0uninstall.ps1" "%TEMP%\socialagent-uninstall.ps1" >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%TEMP%\socialagent-uninstall.ps1" -InstallDir "%~dp0."
