# SocialAgent one-click installer (Windows).
#
# Run via "Install SocialAgent.cmd" (elevates itself). Safe to RE-RUN at any
# point - every step checks before acting, so if Docker needs a restart you
# just run the installer again afterwards and it continues where it left off.
#
# What it does:
#   1) asks the one setup question (local AI models vs cloud API key)
#   2) installs WSL2/Docker Desktop and Chrome if missing (winget)
#   3) copies the app files to C:\SocialAgent and writes .env
#   4) installs + starts the browser helper (drives your real Chrome)
#   5) logs into the image registry, pulls and starts the app
#   6) desktop shortcuts: SocialAgent, Update, Rollback, Uninstall
$ErrorActionPreference = 'Stop'
$InstallDir = 'C:\SocialAgent'
$KitDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Say($t)  { Write-Host $t -ForegroundColor Cyan }
function Ok($t)   { Write-Host ("  OK - " + $t) -ForegroundColor Green }
function Warn($t) { Write-Host ("  ! " + $t) -ForegroundColor Yellow }

Write-Host ""
Write-Host "=== SocialAgent installer ===" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path (Join-Path $KitDir 'docker-compose.client.yml'))) {
    Write-Error "Run this from the unzipped SocialAgent folder (docker-compose.client.yml not found)."
    exit 1
}

# -- 1. The one setup question -----------------------------------------------
Say "How should the agent think?"
Write-Host "  [1] Local AI models  - free + private, ~8 GB download, best with a GPU"
Write-Host "  [2] Cloud API key    - Claude (Anthropic) or OpenAI key, no big download,"
Write-Host "                         right choice for laptops without a gaming GPU"
$modelChoice = Read-Host "Choose 1 or 2 (default 1)"
$useLocal = ($modelChoice -ne '2')
if ($useLocal) { Ok "local models - they download on first start (takes a while)" }
else { Ok "cloud key - you'll paste your Claude/OpenAI key in the app's first screen" }

# Registry token (needed only while the app images are private).
$ghcrToken = Read-Host "Paste your SocialAgent access token (Enter to skip if images are public)"

# -- 2. Docker Desktop -------------------------------------------------------
Say "Checking Docker Desktop..."
$dockerExe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
$dockerCli = Get-Command docker -ErrorAction SilentlyContinue
if (-not (Test-Path $dockerExe) -and -not $dockerCli) {
    Warn "Docker Desktop not found - installing (this is the big one, be patient)"
    try { wsl --update } catch { Warn "wsl --update did not run cleanly - continuing" }
    winget install -e --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements
    Ok "Docker Desktop installed"
    Write-Host ""
    Warn "Windows usually needs a RESTART after the first Docker install."
    Warn "Restart the PC, then run this installer again - it continues from here."
    Read-Host "Press Enter to close"
    exit 0
}
Ok "Docker Desktop is installed"

# Make sure the engine is actually running.
$engineUp = $false
try { docker info *>$null; if ($?) { $engineUp = $true } } catch {}
if (-not $engineUp) {
    Say "Starting Docker Desktop (accept its welcome dialog if one appears)..."
    Start-Process -FilePath $dockerExe | Out-Null
    $deadline = (Get-Date).AddMinutes(5)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        try { docker info *>$null; if ($?) { $engineUp = $true; break } } catch {}
    }
}
if (-not $engineUp) {
    Write-Error "Docker's engine did not come up. Open Docker Desktop, wait for 'Engine running', then run this installer again."
    exit 1
}
Ok "Docker engine is running"

# -- 3. Chrome (the agent drives your real Chrome) --------------------------
Say "Checking Google Chrome..."
$chromePaths = @(
    (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe')
)
$chrome = $chromePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) {
    Warn "Chrome not found - installing"
    winget install -e --id Google.Chrome --accept-source-agreements --accept-package-agreements
    Ok "Chrome installed"
} else { Ok "Chrome found" }

# -- 4. App files + .env -----------------------------------------------------
Say "Installing app files to $InstallDir..."
New-Item -ItemType Directory -Force $InstallDir | Out-Null
Copy-Item -Path (Join-Path $KitDir '*') -Destination $InstallDir -Recurse -Force -Exclude '.env'
$envPath = Join-Path $InstallDir '.env'
if (Test-Path $envPath) {
    Ok ".env already exists - keeping your settings (re-run detected)"
    $helperToken = (Select-String -Path $envPath -Pattern '^HELPER_TOKEN=' | Select-Object -First 1).Line -replace '^HELPER_TOKEN=', ''
} else {
    $helperToken = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
    $envLines = Get-Content (Join-Path $InstallDir '.env.client.example')
    $envLines = $envLines -replace '^HELPER_TOKEN=.*', ("HELPER_TOKEN=" + $helperToken)
    if (-not $useLocal) {
        $envLines = $envLines -replace '^COMPOSE_PROFILES=.*', 'COMPOSE_PROFILES='
        $envLines = $envLines -replace '^LOCAL_MODELS=.*', 'LOCAL_MODELS=0'
    }
    Set-Content $envPath $envLines -Encoding ascii
    Ok ".env written"
}

# -- 5. Browser helper (native service driving your real Chrome) ------------
Say "Installing the browser helper..."
$helperSrc = Join-Path $InstallDir 'SocialAgentHelper.exe'
if (-not (Test-Path $helperSrc)) {
    Write-Error "SocialAgentHelper.exe missing from the install kit - re-download the kit."
    exit 1
}
$appData = Join-Path $env:APPDATA 'SocialAgent'
New-Item -ItemType Directory -Force $appData | Out-Null
Set-Content (Join-Path $appData 'helper.json') ('{"token": "' + $helperToken + '", "port": 8765}') -Encoding ascii
# Allow the Docker network to reach the helper through Windows Firewall.
netsh advfirewall firewall delete rule name="SocialAgent Helper" *>$null
netsh advfirewall firewall add rule name="SocialAgent Helper" dir=in action=allow program="$helperSrc" profile=any | Out-Null
# Start at login + start now (idempotent: kill an old instance first).
Get-Process SocialAgentHelper -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$ws = New-Object -ComObject WScript.Shell
$startup = [Environment]::GetFolderPath('Startup')
$lnk = $ws.CreateShortcut((Join-Path $startup 'SocialAgent Helper.lnk'))
$lnk.TargetPath = $helperSrc
$lnk.Save()
Start-Process -FilePath $helperSrc -WindowStyle Hidden | Out-Null
Ok "helper running (starts automatically with Windows)"

# -- 6. Registry login + start the app --------------------------------------
Set-Location $InstallDir
if ($ghcrToken) {
    Say "Logging in to the app registry..."
    $ghcrToken | docker login ghcr.io -u Gamergy --password-stdin
    Ok "registry login"
}
Say "Downloading and starting SocialAgent (first run takes a few minutes)..."
docker compose --env-file .env -f docker-compose.client.yml pull
docker compose --env-file .env -f docker-compose.client.yml up -d
Ok "app is starting"

# -- 7. Shortcuts ------------------------------------------------------------
Say "Creating shortcuts..."
$desktop = [Environment]::GetFolderPath('Desktop')
Set-Content (Join-Path $desktop 'SocialAgent.url') @(
    '[InternetShortcut]', 'URL=http://localhost:5174'
) -Encoding ascii
foreach ($pair in @(
    @('Update SocialAgent',   'Update SocialAgent.cmd'),
    @('Rollback SocialAgent', 'Rollback SocialAgent.cmd'),
    @('Uninstall SocialAgent','Uninstall SocialAgent.cmd')
)) {
    $l = $ws.CreateShortcut((Join-Path $desktop ($pair[0] + '.lnk')))
    $l.TargetPath = Join-Path $InstallDir $pair[1]
    $l.WorkingDirectory = $InstallDir
    $l.Save()
}
Ok "desktop shortcuts created"

# -- Done --------------------------------------------------------------------
Write-Host ""
Write-Host "=== Install complete ===" -ForegroundColor Green
if ($useLocal) {
    Write-Host "The AI models (~8 GB) download in the background on this first start."
    Write-Host "The agent can answer once they finish."
} else {
    Write-Host "Paste your Claude or OpenAI API key in the app's first screen."
}
Write-Host "Opening the dashboard - if the page is blank, give it a minute and refresh."
Start-Process 'http://localhost:5174'
Read-Host "Press Enter to close"
