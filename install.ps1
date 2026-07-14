# SocialAgent installer engine (Windows).
#
# Two ways in:
#   * The Setup.exe wizard (Inno) calls this with -NonInteractive and the
#     choices the user made on the wizard pages.
#   * Run by hand / re-run after a Docker restart with no args - it prompts.
# Idempotent: every step checks before acting, so re-running continues safely.
#
# EVERYTHING IS LOGGED to C:\SocialAgent\install-log.txt. The wizard closes the
# console when this exits, so the log is the only way to see what happened -
# never remove it.
#
# Exit codes:  0 = done   1 = failed (see log)   3010 = restart Windows, re-run
#
# Steps:
#   1) model choice (local AI models vs cloud API key)
#   2) Docker Desktop (winget) + engine up
#   3) Chrome (winget) - the agent drives the user's REAL Chrome
#   4) app files -> C:\SocialAgent + .env
#   5) browser helper: firewall, autostart, run
#   6) desktop shortcuts (BEFORE the slow pull, so a pull failure still leaves
#      the user their Update/Uninstall tools)
#   7) registry login + pull + start
# SECURITY: the access token is passed by FILE, never on the command line -
# Start-Transcript records the full command line in its header, which leaked a
# real key into install-log.txt (a file users are asked to send to support).
param(
    [ValidateSet('', 'local', 'cloud')] [string]$ModelMode = '',
    [string]$TokenFile = '',
    [switch]$NoShortcuts,
    [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'
$InstallDir = 'C:\SocialAgent'
$KitDir = Split-Path -Parent $MyInvocation.MyCommand.Path

New-Item -ItemType Directory -Force $InstallDir | Out-Null
$LogPath = Join-Path $InstallDir 'install-log.txt'
try { Start-Transcript -Path $LogPath -Force | Out-Null } catch { }

function Say($t)  { Write-Host $t -ForegroundColor Cyan }
function Ok($t)   { Write-Host ("  OK - " + $t) -ForegroundColor Green }
function Warn($t) { Write-Host ("  ! " + $t) -ForegroundColor Yellow }

# Native programs (docker, winget) write progress to stderr. Under
# $ErrorActionPreference='Stop' PowerShell 5.1 can turn that into a TERMINATING
# error and kill the script mid-way with no message - which is exactly why the
# first real install died silently after starting the helper. So: run native
# commands with EAP=Continue and judge them by their EXIT CODE only.
function Invoke-Native {
    param([string]$What, [scriptblock]$Cmd, [switch]$Tolerate)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Cmd } finally { $ErrorActionPreference = $prev }
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        if ($Tolerate) { Warn ($What + " reported exit code " + $code + " - continuing"); return }
        throw ($What + " failed (exit code " + $code + "). See " + $LogPath)
    }
}

try {
    Write-Host ""
    Write-Host "=== SocialAgent installer ===" -ForegroundColor Cyan
    Write-Host ("log: " + $LogPath)
    Write-Host ""

    if (-not (Test-Path (Join-Path $KitDir 'docker-compose.client.yml'))) {
        throw "docker-compose.client.yml not found next to this script ($KitDir)."
    }

    # -- 1. The one setup question -------------------------------------------
    if (-not $ModelMode -and -not $NonInteractive) {
        Say "How should the agent think?"
        Write-Host "  [1] Local AI models  - free + private, ~8 GB download, best with a GPU"
        Write-Host "  [2] Cloud API key    - Claude (Anthropic) or OpenAI key, no big download"
        $choice = Read-Host "Choose 1 or 2 (default 1)"
        $ModelMode = if ($choice -eq '2') { 'cloud' } else { 'local' }
    }
    if (-not $ModelMode) { $ModelMode = 'local' }
    $useLocal = ($ModelMode -ne 'cloud')
    if ($useLocal) { Ok "local models - they download on first start (takes a while)" }
    else { Ok "cloud key - paste your Claude/OpenAI key in the app's first screen" }

    # Access token: read from the file the wizard wrote, then delete it at once.
    $ghcrToken = ''
    if ($TokenFile -and (Test-Path $TokenFile)) {
        $ghcrToken = (Get-Content $TokenFile -Raw).Trim()
        Remove-Item $TokenFile -Force -ErrorAction SilentlyContinue
    }
    if (-not $ghcrToken -and -not $NonInteractive) {
        $ghcrToken = (Read-Host "Paste your APP DOWNLOAD token (GitHub, starts with ghp_). Enter to skip").Trim()
    }
    # Guard the mistake that actually happened: an AI API key pasted here. It
    # can never work (it is not a registry credential) and it must not be sent
    # to a registry at all. Fail loudly, and NEVER echo the value.
    if ($ghcrToken -and ($ghcrToken -like 'sk-*' -or $ghcrToken -like '*api03*')) {
        throw ("That looks like a Claude/OpenAI API KEY, not the app download token. " +
               "They are different: the download token comes from GitHub and starts with 'ghp_'. " +
               "Your Claude/OpenAI key is entered INSIDE the app, on its first screen. " +
               "IMPORTANT: treat the key you just pasted as exposed - revoke it and issue a new one.")
    }

    # -- 2. Docker Desktop ----------------------------------------------------
    Say "Checking Docker Desktop..."
    $dockerExe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    $dockerCli = Get-Command docker -ErrorAction SilentlyContinue
    if (-not (Test-Path $dockerExe) -and -not $dockerCli) {
        Warn "Docker Desktop not found - installing it (this is the big one)"
        Invoke-Native "wsl --update" { wsl --update } -Tolerate
        Invoke-Native "Docker Desktop install" {
            winget install -e --id Docker.DockerDesktop --accept-source-agreements --accept-package-agreements
        } -Tolerate
        Write-Host ""
        Warn "Docker is installed, but Windows must RESTART before it can run."
        Warn "Restart the PC, then run SocialAgent-Setup.exe again - it continues from here."
        exit 3010
    }
    Ok "Docker Desktop is installed"

    $engineUp = $false
    try { docker info *>$null; if ($?) { $engineUp = $true } } catch { }
    if (-not $engineUp) {
        Say "Starting Docker Desktop (accept its welcome screen if one appears)..."
        if (Test-Path $dockerExe) { Start-Process -FilePath $dockerExe | Out-Null }
        $deadline = (Get-Date).AddMinutes(5)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
            try { docker info *>$null; if ($?) { $engineUp = $true; break } } catch { }
        }
    }
    if (-not $engineUp) {
        throw "Docker's engine did not start within 5 minutes. Open Docker Desktop, wait until it says 'Engine running', then run Setup again."
    }
    Ok "Docker engine is running"

    # -- 3. Chrome ------------------------------------------------------------
    # The agent drives the user's REAL Chrome for social logins, so this matters.
    # winget can fail here (its source 404'd on a real client) - so VERIFY the
    # install afterwards instead of assuming, and fall back to the official
    # installer. Never claim "Chrome installed" without seeing chrome.exe.
    # NOTE %ProgramFiles% is a LIE inside a 32-bit process (it resolves to
    # "...(x86)"), which made this miss a perfectly good Chrome. Use
    # %ProgramW6432% (always the real 64-bit Program Files), hardcoded paths,
    # and finally the registry - belt, braces and a spare belt.
    function Find-Chrome {
        $paths = @(
            "$env:ProgramW6432\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
            "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
            'C:\Program Files\Google\Chrome\Application\chrome.exe',
            'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe'
        )
        $hit = $paths | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
        if ($hit) { return $hit }
        foreach ($key in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\chrome.exe'
        )) {
            try {
                $p = (Get-ItemProperty -Path $key -ErrorAction Stop).'(default)'
                if ($p -and (Test-Path $p)) { return $p }
            } catch { }
        }
        return $null
    }
    Say "Checking Google Chrome..."
    if (Find-Chrome) {
        Ok "Chrome found"
    } else {
        Warn "Chrome not found - installing via winget"
        Invoke-Native "Chrome install (winget)" {
            winget install -e --id Google.Chrome --accept-source-agreements --accept-package-agreements
        } -Tolerate
        if (-not (Find-Chrome)) {
            Warn "winget could not install Chrome - downloading it from Google directly"
            try {
                $chromeSetup = Join-Path $env:TEMP 'chrome_installer.exe'
                Invoke-WebRequest -Uri 'https://dl.google.com/chrome/install/latest/chrome_installer.exe' `
                                  -OutFile $chromeSetup -UseBasicParsing
                Start-Process -FilePath $chromeSetup -ArgumentList '/silent', '/install' -Wait
                Remove-Item $chromeSetup -Force -ErrorAction SilentlyContinue
            } catch {
                Warn ("direct Chrome download failed: " + $_.Exception.Message)
            }
        }
        if (Find-Chrome) {
            Ok "Chrome installed"
        } else {
            # Not fatal: the app still installs and runs (chat, email). Only the
            # social-account logins need Chrome, so say exactly that.
            Warn "COULD NOT INSTALL CHROME. The app will still work, but connecting"
            Warn "Instagram/X/LinkedIn/TikTok needs it. Install Chrome from"
            Warn "https://www.google.com/chrome and then re-run this Setup."
        }
    }

    # -- 4. App files + .env --------------------------------------------------
    # The wizard extracts straight into C:\SocialAgent, so KitDir already IS
    # InstallDir - only copy when run from a separate unzipped folder.
    if ((Resolve-Path $KitDir).Path -ne (Resolve-Path $InstallDir).Path) {
        Say "Installing app files to $InstallDir..."
        Copy-Item -Path (Join-Path $KitDir '*') -Destination $InstallDir -Recurse -Force -Exclude '.env'
    }
    $envPath = Join-Path $InstallDir '.env'
    if (Test-Path $envPath) {
        Ok ".env already exists - keeping your settings"
        $helperToken = (Select-String -Path $envPath -Pattern '^HELPER_TOKEN=' |
                        Select-Object -First 1).Line -replace '^HELPER_TOKEN=', ''
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

    # -- 5. Browser helper ----------------------------------------------------
    Say "Installing the browser helper..."
    $helperSrc = Join-Path $InstallDir 'SocialAgentHelper.exe'
    if (-not (Test-Path $helperSrc)) { throw "SocialAgentHelper.exe is missing from $InstallDir." }
    $appData = Join-Path $env:APPDATA 'SocialAgent'
    New-Item -ItemType Directory -Force $appData | Out-Null
    # Write the helper's config into the INSTALL DIR, not %APPDATA%.
    #
    # This script is ELEVATED, so %APPDATA% is whatever profile the elevation
    # resolved to. The helper runs as the NORMAL user and reads *their*
    # %APPDATA% - if the two differ, the helper finds no config, generates a
    # fresh random token, and then never matches the token in .env: the worker's
    # calls are rejected and connect reports "helper unavailable" forever. (Same
    # elevation trap that made the desktop shortcuts vanish.)
    # C:\SocialAgent is machine-wide and readable by both. install_dir also lets
    # the helper run docker compose in the right folder for local models.
    $helperCfg = ('{"token": "' + $helperToken + '", "port": 8765, "install_dir": "' +
                  $InstallDir.Replace('\', '\\') + '"}')
    Set-Content (Join-Path $InstallDir 'helper.json') $helperCfg -Encoding ascii
    # Legacy location, kept in step so an already-running old helper still works.
    Set-Content (Join-Path $appData 'helper.json') $helperCfg -Encoding ascii
    Invoke-Native "firewall rule (delete old)" {
        netsh advfirewall firewall delete rule name="SocialAgent Helper"
    } -Tolerate
    Invoke-Native "firewall rule (add)" {
        netsh advfirewall firewall add rule name="SocialAgent Helper" dir=in action=allow program="$helperSrc" profile=any
    } -Tolerate
    Get-Process SocialAgentHelper -ErrorAction SilentlyContinue |
        Stop-Process -Force -ErrorAction SilentlyContinue
    $ws = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) 'SocialAgent Helper.lnk'))
    $lnk.TargetPath = $helperSrc
    $lnk.Save()

    # Start the helper as the NORMAL user, not as administrator. This script is
    # elevated, and a child would inherit that - the helper would then launch
    # the user's Chrome elevated, which Chrome hates and which writes login
    # profiles into the wrong place. Launching via explorer.exe (which runs at
    # the user's normal level) hands the process back down to them.
    try { Start-Process 'explorer.exe' -ArgumentList "`"$helperSrc`"" | Out-Null } catch { }
    $helperUp = $false
    for ($i = 0; $i -lt 30; $i++) {   # 15s - explorer hand-off can be slow
        Start-Sleep -Milliseconds 500
        try {
            $probe = New-Object Net.Sockets.TcpClient
            $probe.Connect('127.0.0.1', 8765)
            $probe.Close()
            $helperUp = $true
            break
        } catch { }
    }
    if (-not $helperUp) {
        # Only fall back if the process really isn't there. Blindly starting a
        # second one gave us TWO helpers fighting over port 8765, with requests
        # delivered to one at random.
        if (Get-Process SocialAgentHelper -ErrorAction SilentlyContinue) {
            Warn "helper process is up but hasn't opened its port yet - leaving it alone"
        } else {
            Warn "helper did not start via the normal-user launch - starting it directly"
            Start-Process -FilePath $helperSrc -WindowStyle Hidden | Out-Null
        }
    }
    Ok "helper running (starts automatically with Windows)"

    # -- 6. Shortcuts (before the slow pull, on purpose) ----------------------
    $desktop = [Environment]::GetFolderPath('Desktop')
    Set-Content (Join-Path $desktop 'SocialAgent.url') @(
        '[InternetShortcut]', 'URL=http://localhost:5174'
    ) -Encoding ascii
    if (-not $NoShortcuts) {
        Say "Creating shortcuts..."
        foreach ($pair in @(
            @('Update SocialAgent',    'Update SocialAgent.cmd'),
            @('Rollback SocialAgent',  'Rollback SocialAgent.cmd'),
            @('Uninstall SocialAgent', 'Uninstall SocialAgent.cmd')
        )) {
            $l = $ws.CreateShortcut((Join-Path $desktop ($pair[0] + '.lnk')))
            $l.TargetPath = Join-Path $InstallDir $pair[1]
            $l.WorkingDirectory = $InstallDir
            $l.Save()
        }
    }
    Ok "desktop shortcuts created"

    # -- 7. Registry login + pull + start -------------------------------------
    Set-Location $InstallDir
    if ($ghcrToken) {
        Say "Signing in to the app registry..."
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $ghcrToken | docker login ghcr.io -u Gamergy --password-stdin
        $loginCode = $LASTEXITCODE
        $ErrorActionPreference = $prev
        if ($loginCode -ne 0) {
            throw "Sign-in to the app registry failed. Check the access token you pasted (it must have 'read:packages')."
        }
        Ok "signed in"
        # Save the token next to the stack so UPDATES can sign in on their own.
        # docker login stores its credential per-user, and this installer is
        # elevated while "Update SocialAgent" is not - so the update would
        # otherwise hit "error from registry: denied" and never recover.
        # (Same file the uninstaller deletes; goes away with the app.)
        Set-Content (Join-Path $InstallDir '.registry-token') $ghcrToken -Encoding ascii
    } else {
        Warn "no access token given - this only works if the app images are public"
    }

    Say "Downloading SocialAgent (several minutes on a first install)..."
    Invoke-Native "Downloading the app" {
        docker compose --env-file .env -f docker-compose.client.yml pull
    }
    Say "Starting SocialAgent..."
    Invoke-Native "Starting the app" {
        docker compose --env-file .env -f docker-compose.client.yml up -d
    }
    Ok "app is running"

    Write-Host ""
    Write-Host "=== Install complete ===" -ForegroundColor Green
    if ($useLocal) {
        Write-Host "The AI models (~8 GB) are downloading in the background."
        Write-Host "The agent can answer once they finish."
    } else {
        Write-Host "Paste your Claude or OpenAI API key in the app's first screen."
    }
    Start-Process 'http://localhost:5174'
    if (-not $NonInteractive) { Read-Host "Press Enter to close" }
    exit 0
}
catch {
    Write-Host ""
    Write-Host "=== SETUP FAILED ===" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host ("Full details: " + $LogPath)
    if (-not $NonInteractive) { Read-Host "Press Enter to close" }
    exit 1
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}
