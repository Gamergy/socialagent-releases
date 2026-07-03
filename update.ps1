# SocialAgent update / rollback (Windows). Deliberate + reversible: pins an
# exact version, saves the previous one, recreates the stack. NOT auto-update.
#
#   .\update.ps1 latest    # update to the newest published version
#   .\update.ps1 0.2.0     # update to an exact version
#   .\update.ps1 rollback  # revert to the previously-running version
#
# "latest" reads the public version manifest (VERSION_MANIFEST_URL in .env) -
# the same source the in-app "update available" banner uses.
# Run from the folder that holds docker-compose.client.yml and .env.
param([Parameter(Position = 0)][string]$Target)
$ErrorActionPreference = 'Stop'
$Compose = 'docker-compose.client.yml'
$EnvFile = '.env'
if (-not (Test-Path $Compose))  { Write-Error "Run this from the folder with $Compose"; exit 1 }
if (-not (Test-Path $EnvFile))  { Write-Error "No .env found - copy .env.client.example to .env first."; exit 1 }

function Get-Val($k) {
    $m = Select-String -Path $EnvFile -Pattern "^$k=" | Select-Object -First 1
    if ($m) { return ($m.Line -replace "^$k=", '') } else { return '' }
}
function Set-Val($k, $v) {
    $lines = @(Get-Content $EnvFile)
    if ($lines -match "^$k=") { $lines = $lines -replace "^$k=.*", "$k=$v" } else { $lines += "$k=$v" }
    # ascii: utf8 here writes a BOM (PS 5.1) that breaks update.sh's key lookup
    Set-Content $EnvFile $lines -Encoding ascii
}

$cur = Get-Val 'SOCIALAGENT_VERSION'

if ($Target -eq 'latest') {
    $url = Get-Val 'VERSION_MANIFEST_URL'
    if (-not $url) { Write-Error "VERSION_MANIFEST_URL is not set in .env - run .\update.ps1 <version> instead."; exit 1 }
    try {
        # Parse explicitly: raw.githubusercontent.com serves JSON as text/plain.
        $raw = (Invoke-WebRequest -Uri $url -TimeoutSec 20 -UseBasicParsing).Content
        if ($raw -is [byte[]]) { $raw = [Text.Encoding]::UTF8.GetString($raw) }
        $m = $raw.Trim([char]0xFEFF).Trim() | ConvertFrom-Json
    }
    catch { Write-Error "Couldn't read the version list ($url). Check your internet connection and try again."; exit 1 }
    $Target = "$($m.latest)".Trim()
    if (-not $Target) { Write-Error "The version list at $url has no 'latest' entry."; exit 1 }
    $newer = $true
    try { $newer = ([version]$Target -gt [version]$cur) } catch {}
    if (-not $newer) { Write-Host "Already up to date - running $cur (newest published: $Target)."; exit 0 }
    Write-Host "Newest published version: $Target"
}

$isRollback = ($Target -eq 'rollback')
if ($isRollback) {
    $Target = Get-Val 'SOCIALAGENT_PREV_VERSION'
    if (-not $Target) { Write-Error 'No previous version recorded - nothing to roll back to.'; exit 1 }
    Write-Host "Rolling back: $cur -> $Target"
}
elseif (-not $Target) {
    Write-Host "Usage: .\update.ps1 <version> | rollback"
    Write-Host "Currently running: $cur"; exit 1
}
else { Write-Host "Updating: $cur -> $Target" }

if (-not $isRollback -and $cur) { Set-Val 'SOCIALAGENT_PREV_VERSION' $cur }
Set-Val 'SOCIALAGENT_VERSION' $Target

docker compose --env-file $EnvFile -f $Compose pull
docker compose --env-file $EnvFile -f $Compose up -d
Write-Host "Now running $Target.  Roll back any time with: .\update.ps1 rollback"
