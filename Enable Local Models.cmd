@echo off
rem Turns on local AI models for an install that skipped them. Keep this file
rem in the folder that holds docker-compose.client.yml and .env. The model
rem download itself happens in the dashboard (Settings - Local AI models).
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\enable-local-models.ps1"
echo.
pause
