#requires -Version 5.1
<#
  bootstrap.ps1 - one-time MACHINE setup for Nucleus dev work (Windows 11).

  INSTALL BY HAND FIRST (the only two you can't script):
    - Git for Windows   https://git-scm.com/download/win
    - Claude Code       https://claude.com/claude-code

  Then, in PowerShell:
    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned   # once, if scripts are blocked
    .\bootstrap.ps1                                        # approve the UAC prompt
    .\bootstrap.ps1 -Full                                  # ...plus the optional extras below

  Idempotent - safe to re-run (winget skips already-installed packages).
  Installs the toolchain + WSL2 + global npm tools, then verifies.
  It does NOT: log you into GitHub or Railway, accept the Docker license, or clone repos -
  those are interactive/per-project (see nucleus/docs/ONBOARDING.md).

  -Full additionally installs the estate's OPTIONAL tooling. Off by default because a
  teammate joining the team needs none of it, and faster-whisper is a heavy install:
    - ffmpeg + faster-whisper : the feedback-extraction skill (transcribes review sessions
                                on CPU, offline). Whisper's model downloads on first RUN.
    - k6                      : the load/stress profiles the rollout gate requires before a
                                Tier-0 (money/identity) surface goes in front of real users.
#>

param(
    # Also install the optional extras documented above.
    [switch]$Full
)

$ErrorActionPreference = 'Stop'

# --- Self-elevate: winget needs admin for the MSIX (WSL) + Docker installs ---
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
          ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
    Write-Host 'Elevating (approve the UAC prompt)...' -ForegroundColor Yellow
    # Forward -Full across the elevation, or it is silently dropped and the extras never install.
    $argv = @('-NoProfile','-File',"`"$PSCommandPath`"")
    if ($Full) { $argv += '-Full' }
    Start-Process powershell -Verb RunAs -ArgumentList $argv
    return
}

function Install-Pkg([string]$id) {
    Write-Host "  -> $id" -ForegroundColor Cyan
    winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
}

Write-Host "`n=== Toolchain (winget) ===" -ForegroundColor Green
'OpenJS.NodeJS.LTS',
'Python.Python.3.13',
'Microsoft.VisualStudioCode',
'GitHub.cli',
'Microsoft.PowerShell',
'Microsoft.WindowsTerminal',
'Docker.DockerDesktop',
'DBeaver.DBeaver.Community',
'MongoDB.Compass.Full' | ForEach-Object { Install-Pkg $_ }

Write-Host "`n=== WSL2 (Docker's backend) ===" -ForegroundColor Green
# The inbox `wsl --install --no-distribution` stub is ignored until this modern component exists,
# and the WSL MSIX needs winget already-elevated (we are). No distro needed - Docker brings its own.
Install-Pkg 'Microsoft.WSL'
wsl --set-default-version 2 2>$null

Write-Host "`n=== Global npm tools ===" -ForegroundColor Green
# Refresh PATH so the just-installed npm resolves in this session.
$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
            [Environment]::GetEnvironmentVariable('Path','User')
# @railway/cli: every deployed app in the estate lives on Railway, and reading a live service's
# variables or deployed commit is a CLI-only job.
npm install -g typescript ts-node nodemon @railway/cli

if ($Full) {
    Write-Host "`n=== Optional extras (-Full) ===" -ForegroundColor Green
    Install-Pkg 'Gyan.FFmpeg'      # feedback-extraction: frame/audio prep
    Install-Pkg 'GrafanaLabs.k6'   # Tier-0 load + stress profiles
    # python -m pip, not bare pip: the launcher resolves through the PATH refreshed just above.
    python -m pip install --upgrade faster-whisper
}

Write-Host "`n=== Verify ===" -ForegroundColor Green
foreach ($c in 'node -v','npm -v','python --version','git --version','gh --version','docker --version','code -v','railway --version') {
    $name = ($c -split ' ')[0]
    try { $v = (cmd /c $c 2>$null | Select-Object -First 1) } catch { $v = 'NOT FOUND' }
    '{0,-10} {1}' -f $name, $v | Write-Host
}
'wsl:       ' + (wsl --status 2>$null | Select-Object -First 1) | Write-Host

Write-Host "`n=== Next (manual, once) ===" -ForegroundColor Yellow
Write-Host '  1. REBOOT (finishes WSL2 + Docker''s service).'
Write-Host '  2. Launch Docker Desktop once and ACCEPT its license (cannot be scripted).'
Write-Host '  3. gh auth login   (GitHub.com -> HTTPS -> Login with a web browser).'
Write-Host '     ...this must succeed BEFORE any npm install - the design system is a private git dep.'
Write-Host '  4. railway login   (only if you deploy).'
Write-Host '  5. gh repo clone vardan-kabra/nucleus C:\dev\nucleus'
Write-Host '  6. cd C:\dev\nucleus ; .\scripts\dev-setup.ps1   (see docs/ONBOARDING.md)'
Write-Host ''
Write-Host '  Setting up the WHOLE estate (nucleus + nucleus-prototypes + the rest), not just'
Write-Host '  the nucleus repo? Hand NUCLEUS-ESTATE-SETUP.md in this folder to Claude Code.'
Write-Host ''
Read-Host 'Done. Press Enter to close'
