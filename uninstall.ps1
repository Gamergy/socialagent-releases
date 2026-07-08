# SocialAgent uninstaller - removes EVERYTHING: containers, all data volumes
# (agent memory, saved logins, settings), downloaded AI models, app images,
# the browser helper, shortcuts, and the install folder. Docker Desktop and
# Chrome are left alone (they are general-purpose programs).
# Run via "Uninstall SocialAgent.cmd" (which copies this file to TEMP first so
# the install folder can delete itself).
param([string]$InstallDir = 'C:\SocialAgent')
$ErrorActionPreference = 'Continue'

Write-Host ""
Write-Host "=== SocialAgent uninstaller ===" -ForegroundColor Cyan
Write-Host "This removes SocialAgent COMPLETELY from this PC:"
Write-Host "  - the app, its containers and downloaded AI models"
Write-Host "  - the agent's memory and settings"
Write-Host "  - saved social/email logins"
$sure = Read-Host "Type YES to continue"
if ($sure -ne 'YES') { Write-Host "Cancelled - nothing was removed."; exit 0 }

# 1. Browser helper: process, autostart, firewall, profiles/config.
Write-Host "Removing the browser helper..."
Get-Process SocialAgentHelper -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path ([Environment]::GetFolderPath('Startup')) 'SocialAgent Helper.lnk')
netsh advfirewall firewall delete rule name="SocialAgent Helper" *>$null
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $env:APPDATA 'SocialAgent')

# 2. Containers + volumes (--profile "*" catches the optional local-models
#    services too; -v removes the volumes = models, memory, keys, logins).
if (Test-Path (Join-Path $InstallDir 'docker-compose.client.yml')) {
    Write-Host "Removing containers and data..."
    Set-Location $InstallDir
    docker compose --profile "*" --env-file .env -f docker-compose.client.yml down -v --rmi all 2>$null
}

# 3. Any SocialAgent images from older versions (updates keep one spare for
#    rollback; uninstall sweeps every tag) + the Ollama engine image.
Write-Host "Removing app images..."
docker images --format "{{.Repository}}:{{.Tag}}" 2>$null |
    Where-Object { $_ -match "socialagent-|ollama/ollama" } |
    ForEach-Object { docker rmi $_ 2>$null | Out-Null }

# 4. Shortcuts.
Write-Host "Removing shortcuts..."
$desktop = [Environment]::GetFolderPath('Desktop')
foreach ($n in @('SocialAgent.url', 'Update SocialAgent.lnk',
                 'Rollback SocialAgent.lnk', 'Uninstall SocialAgent.lnk')) {
    Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $desktop $n)
}

# 5. The install folder itself (we are running from TEMP, so this works).
Write-Host "Removing $InstallDir..."
Set-Location $env:TEMP
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $InstallDir

Write-Host ""
Write-Host "=== SocialAgent has been removed ===" -ForegroundColor Green
Write-Host "(Docker Desktop and Chrome were left installed.)"
Read-Host "Press Enter to close"
