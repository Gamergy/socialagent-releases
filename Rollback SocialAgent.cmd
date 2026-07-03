@echo off
rem One-click rollback: double-click to go back to the previously-running
rem SocialAgent version (the one you were on before the last update).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\update.ps1" rollback
echo.
pause
