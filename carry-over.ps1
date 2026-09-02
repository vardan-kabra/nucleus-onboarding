#requires -Version 5.1
<#
  carry-over.ps1 - move the things a fresh machine CANNOT install: Claude Code memory,
  Claude settings, every real .env, and (opt-in) your SSH keys.

  bootstrap.ps1 installs software. This moves state. Run it twice, once on each machine:

    OLD machine:   .\carry-over.ps1 -Export                          # preview, writes nothing
                   .\carry-over.ps1 -Export -Apply -To D:\carry      # actually collects
    ...move the bundle across (see SECURITY below)...
    NEW machine:   .\carry-over.ps1 -Import -From D:\carry           # preview, writes nothing
                   .\carry-over.ps1 -Import -From D:\carry -Apply    # actually restores

  PREVIEW IS THE DEFAULT, on both sides, deliberately: the safe mode is the one you get by
  typing less. Nothing is read from or written to disk in anger without -Apply.

  WHAT IT CARRIES
    - ~/.claude/settings.json                 model/effort defaults, hooks, permissions
    - ~/.claude/projects/<slug>/memory/**     saved memory + MEMORY.md, per project
    - <DevRoot>/**/.env*                      real env files only; *.example / *.template
                                              are in git already and are skipped
    - ~/.ssh/**                               ONLY with -IncludeSsh (private keys)

  WHAT IT DELIBERATELY DOES NOT CARRY
    - Claude session transcripts (large, and stale the moment you land)
    - ~/.claude/CLAUDE.md, skills/, agents/   claude-global-config's install.ps1 deploys these
    - Claude / GitHub / Railway credentials   sign in on the new machine instead
    - node_modules, .git, and .claude/worktrees (transient checkouts)

  MEMORY IS PATH-KEYED. Claude Code stores memory under a slug derived from the project's
  absolute path (C:\dev\nucleus-prototypes -> C--dev-nucleus-prototypes). Restore onto a
  machine that clones to different paths and the memory is still on disk but is never
  loaded. Keep -DevRoot identical on both sides.

  SECURITY. The bundle holds live database URLs, OAuth secrets and - with -IncludeSsh -
  an unencrypted private key. It is not encrypted. Move it on an encrypted disk or through
  a password manager, never over chat or email, and delete it once the new machine is up.
  -Apply refuses to write a bundle anywhere inside a git work tree, so it cannot be
  committed by accident.
#>

param(
    # Collect from this machine.
    [switch]$Export,
    # Restore onto this machine.
    [switch]$Import,
    # The bundle directory: where -Export writes, where -Import reads.
    [Alias('To','From')]
    [string]$Path = "$env:USERPROFILE\Desktop\nucleus-carry-over",
    # Root the repos live under. Must be the SAME on both machines - see MEMORY IS PATH-KEYED.
    [string]$DevRoot = 'C:\dev',
    # Include ~/.ssh. Off by default: private keys.
    [switch]$IncludeSsh,
    # Actually read/write. Without it you get a preview.
    [switch]$Apply,
    # List every file instead of the first few per group.
    [switch]$Detailed,
    # Import: also restore an .env whose repo is not cloned yet, and overwrite ~/.ssh files.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

if ($Export -eq $Import) { throw 'Pass exactly one of -Export or -Import.' }

$ClaudeHome = Join-Path $env:USERPROFILE '.claude'
$SshHome    = Join-Path $env:USERPROFILE '.ssh'

function Show-Plan($rows, $verb) {
    if (-not $rows) { Write-Host '  (nothing found)' -ForegroundColor Yellow; return }
    $rows | Group-Object Group | ForEach-Object {
        $kb = [math]::Round((($_.Group | Measure-Object Bytes -Sum).Sum / 1KB), 1)
        Write-Host ("  {0,-26} {1,4} file(s)  {2,8} KB" -f $_.Name, $_.Count, $kb)
        # Anything the user must act on is always shown; the bulk is capped so a 100-file
        # memory folder cannot bury a "repo not cloned yet" line nobody then reads.
        # 'new' and 'identical, skip' are the two routine outcomes and are the bulk of any run;
        # everything else (DIFFERS, SKIPPED, kept) is a decision for the operator and is never hidden.
        $routine = @('', 'new', 'identical, skip')
        $shown = 0
        foreach ($r in $_.Group) {
            $interesting = $routine -notcontains $r.Note
            if (-not $Detailed -and -not $interesting -and $shown -ge 6) { continue }
            $note = ''
            if ($r.Note) { $note = "   <- $($r.Note)" }
            Write-Host ("      {0}{1}" -f $r.Rel, $note) -ForegroundColor DarkGray
            $shown++
        }
        $hidden = $_.Count - $shown
        if ($hidden -gt 0) { Write-Host "      ... and $hidden more (-Detailed to list)" -ForegroundColor DarkGray }
    }
    $total = [math]::Round((($rows | Measure-Object Bytes -Sum).Sum / 1KB), 1)
    Write-Host ("  {0} {1} file(s), {2} KB total" -f $verb, $rows.Count, $total) -ForegroundColor Cyan
}

function New-Row($src, $rel, $group, $note) {
    $len = 0
    if (Test-Path -LiteralPath $src -PathType Leaf) { $len = (Get-Item -LiteralPath $src).Length }
    [pscustomobject]@{ Source = $src; Rel = $rel; Group = $group; Bytes = $len; Note = $note }
}

# --------------------------------------------------------------------------- EXPORT
if ($Export) {
    Write-Host "`n=== Collecting from this machine ===" -ForegroundColor Green
    $rows = @()

    $settings = Join-Path $ClaudeHome 'settings.json'
    if (Test-Path -LiteralPath $settings) {
        $rows += New-Row $settings 'claude\settings.json' 'Claude settings' ''
    }

    $projects = Join-Path $ClaudeHome 'projects'
    if (Test-Path -LiteralPath $projects) {
        foreach ($proj in Get-ChildItem -LiteralPath $projects -Directory) {
            $mem = Join-Path $proj.FullName 'memory'
            if (-not (Test-Path -LiteralPath $mem)) { continue }
            foreach ($f in Get-ChildItem -LiteralPath $mem -Recurse -File) {
                $tail = $f.FullName.Substring($mem.Length).TrimStart('\')
                $rows += New-Row $f.FullName "claude\projects\$($proj.Name)\memory\$tail" 'Claude memory' ''
            }
        }
    }

    if (Test-Path -LiteralPath $DevRoot) {
        # -Depth 4 reaches <DevRoot>\<repo>\<app>\.env without walking whole trees.
        $envFiles = Get-ChildItem -LiteralPath $DevRoot -Filter '.env*' -File -Recurse -Depth 4 -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -notmatch '\\node_modules\\' -and
                $_.FullName -notmatch '\\\.git\\' -and
                $_.FullName -notmatch '\\\.claude\\worktrees\\' -and
                # Build output copies .env into itself (Next.js standalone does). That copy is
                # generated, not source - carrying it restores a stale secret into a stale build.
                $_.FullName -notmatch '\\(\.next|\.turbo|dist|build|out|coverage)\\' -and
                $_.Name -notlike '*.example' -and $_.Name -notlike '*.template' -and $_.Name -notlike '*.sample'
            }
        foreach ($f in $envFiles) {
            $tail = $f.FullName.Substring($DevRoot.Length).TrimStart('\')
            $rows += New-Row $f.FullName "dev\$tail" 'Env files' ''
        }
    } else {
        Write-Host "  NOTE: -DevRoot '$DevRoot' does not exist; no .env collected." -ForegroundColor Yellow
    }

    if ($IncludeSsh -and (Test-Path -LiteralPath $SshHome)) {
        foreach ($f in Get-ChildItem -LiteralPath $SshHome -File -Force) {
            $rows += New-Row $f.FullName "ssh\$($f.Name)" 'SSH keys' ''
        }
    } elseif (-not $IncludeSsh) {
        Write-Host '  NOTE: SSH keys skipped. Add -IncludeSsh to carry them (droplet access).' -ForegroundColor Yellow
    }

    Show-Plan $rows 'Would collect'

    if (-not $Apply) {
        Write-Host "`nPREVIEW - nothing was written. Re-run with -Apply to collect into:" -ForegroundColor Yellow
        Write-Host "  $Path`n"
        exit 0
    }

    # A bundle inside a git work tree is one 'git add -A' away from committed secrets.
    $probe = $Path
    while ($probe -and -not (Test-Path -LiteralPath $probe)) { $probe = Split-Path -Parent $probe }
    if ($probe) {
        Push-Location $probe
        $inRepo = (git rev-parse --is-inside-work-tree 2>$null)
        Pop-Location
        # git exits 128 outside a work tree, which is the ANSWER here, not a failure - but it
        # would otherwise become the script's own exit code and fail any '&&' chain around it.
        $global:LASTEXITCODE = 0
        if ($inRepo -eq 'true') {
            throw "Refusing to write the bundle into a git work tree ($probe). It holds live secrets. Pick a path outside any repo."
        }
    }

    foreach ($r in $rows) {
        $dst = Join-Path $Path $r.Rel
        $dir = Split-Path -Parent $dst
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $r.Source -Destination $dst -Force
    }

    $manifest = @(
        "Nucleus carry-over bundle",
        "created : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "machine : $env:COMPUTERNAME",
        "user    : $env:USERNAME",
        "DevRoot : $DevRoot   <- the NEW machine must use this same root",
        "ssh     : $(if ($IncludeSsh) { 'included' } else { 'not included' })",
        "files   : $($rows.Count)",
        "",
        "Restore with:  .\carry-over.ps1 -Import -From <this folder> -DevRoot $DevRoot -Apply",
        "",
        "CONTAINS LIVE SECRETS. Delete this bundle once the new machine is up."
    )
    Set-Content -LiteralPath (Join-Path $Path 'MANIFEST.txt') -Value $manifest -Encoding ASCII

    Write-Host "`nWrote bundle to: $Path" -ForegroundColor Green
    Write-Host 'CONTAINS LIVE SECRETS - move it on an encrypted disk, and delete it when done.' -ForegroundColor Red
    exit 0
}

# --------------------------------------------------------------------------- IMPORT
Write-Host "`n=== Restoring onto this machine ===" -ForegroundColor Green
if (-not (Test-Path -LiteralPath $Path)) { throw "Bundle not found: $Path" }

$rows = @()
foreach ($f in Get-ChildItem -LiteralPath $Path -Recurse -File -Force) {
    $rel = $f.FullName.Substring($Path.Length).TrimStart('\')
    if ($rel -eq 'MANIFEST.txt') { continue }

    $seg = $rel.Split('\')[0]
    $tail = $rel.Substring($seg.Length).TrimStart('\')
    switch ($seg) {
        'claude' { $dst = Join-Path $ClaudeHome $tail; $group = 'Claude state' }
        'dev'    { $dst = Join-Path $DevRoot   $tail; $group = 'Env files' }
        'ssh'    { $dst = Join-Path $SshHome   $tail; $group = 'SSH keys' }
        default  { continue }
    }

    $note = 'new'
    if (Test-Path -LiteralPath $dst) {
        if ((Get-FileHash -LiteralPath $dst).Hash -eq (Get-FileHash -LiteralPath $f.FullName).Hash) {
            $note = 'identical, skip'
        } elseif ($seg -eq 'ssh' -and -not $Force) {
            $note = 'EXISTS and differs - kept, pass -Force to replace'
        } else {
            $note = 'DIFFERS - existing backed up to .pre-carryover'
        }
    } elseif ($seg -eq 'dev') {
        # An .env restored beside a repo that was never cloned just creates a stray folder.
        $repoDir = Join-Path $DevRoot $tail.Split('\')[0]
        if (-not (Test-Path -LiteralPath $repoDir)) {
            $note = 'repo not cloned yet - SKIPPED (clone it, then re-run)'
            if ($Force) { $note = 'repo not cloned - restoring anyway (-Force)' }
        }
    }

    $row = New-Row $f.FullName $rel $group $note
    $row | Add-Member -NotePropertyName Dest -NotePropertyValue $dst
    $rows += $row
}

Show-Plan $rows 'Would restore'

if (-not $Apply) {
    Write-Host "`nPREVIEW - nothing was written. Re-run with -Apply to restore." -ForegroundColor Yellow
    exit 0
}

$done = 0; $skipped = 0
foreach ($r in $rows) {
    if ($r.Note -like 'identical*' -or $r.Note -like '*SKIPPED*' -or $r.Note -like '*kept, pass -Force*') {
        $skipped++
        continue
    }
    $dir = Split-Path -Parent $r.Dest
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    if (Test-Path -LiteralPath $r.Dest) { Copy-Item -LiteralPath $r.Dest -Destination "$($r.Dest).pre-carryover" -Force }
    Copy-Item -LiteralPath $r.Source -Destination $r.Dest -Force
    $done++
}

# Windows OpenSSH refuses a private key any other account can read ("UNPROTECTED PRIVATE KEY
# FILE"), and a copied file inherits the destination folder's ACL. Lock them down here or the
# first ssh to a droplet fails for a reason that looks nothing like a permissions problem.
$restoredKeys = $rows | Where-Object { $_.Group -eq 'SSH keys' -and $_.Rel -notlike '*.pub' -and $_.Rel -notlike '*known_hosts*' }
foreach ($k in $restoredKeys) {
    if (-not (Test-Path -LiteralPath $k.Dest)) { continue }
    icacls $k.Dest /inheritance:r /grant:r "$($env:USERNAME):(R)" | Out-Null
    Write-Host "  locked down $($k.Dest)" -ForegroundColor DarkGray
}

Write-Host "`nRestored $done file(s); skipped $skipped." -ForegroundColor Green
Write-Host 'Anything replaced was backed up alongside it as <file>.pre-carryover.'
Write-Host 'Now delete the bundle - it still holds live secrets.' -ForegroundColor Red
exit 0
