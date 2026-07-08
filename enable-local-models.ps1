# Turns ON the local AI models for a SocialAgent install that skipped them
# (cloud-API-key installs). Activates the "local-models" compose profile and
# starts the model engine; the actual ~8 GB model download is then done from
# the dashboard: Settings -> Local AI models -> Download.
# Run from the folder that holds docker-compose.client.yml and .env.
$ErrorActionPreference = 'Stop'
$Compose = 'docker-compose.client.yml'
$EnvFile = '.env'
if (-not (Test-Path $Compose)) { Write-Error "Run this from the folder with $Compose"; exit 1 }
if (-not (Test-Path $EnvFile)) { Write-Error "No .env found - copy .env.client.example to .env first."; exit 1 }

function Set-Val($k, $v) {
    $lines = @(Get-Content $EnvFile)
    if ($lines -match "^$k=") { $lines = $lines -replace "^$k=.*", "$k=$v" } else { $lines += "$k=$v" }
    # ascii: a BOM here breaks update.sh's key lookup (see update.ps1)
    Set-Content $EnvFile $lines -Encoding ascii
}

Set-Val 'COMPOSE_PROFILES' 'local-models'
Set-Val 'LOCAL_MODELS' '1'

docker compose --env-file $EnvFile -f $Compose up -d
Write-Host ""
Write-Host "Local model engine is starting."
Write-Host "Now open the dashboard -> Settings -> Local AI models -> Download."
