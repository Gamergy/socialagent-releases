@echo off
rem One-click SocialAgent update: double-click to move to the newest published
rem version. Keep this file in the folder that holds docker-compose.client.yml,
rem .env and update.ps1. Reversible any time via "Rollback SocialAgent.cmd".
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\update.ps1" latest
echo.
pause
