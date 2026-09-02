# Nucleus - machine bootstrap (shareable layer)

The one-time, machine-level toolchain installer for Nucleus dev work. Safe to share with anyone
joining the team: it contains **no secrets** and installs only standard tooling. (Project setup -
deps, DB, run - lives in the `nucleus` repo under `docs/ONBOARDING.md` + `scripts/dev-setup.ps1`.)

## Do it yourself
1. Install **Git for Windows** and **Claude Code** by hand (the only two you can't script).
2. `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`  — once, if scripts are blocked.
3. `.\bootstrap.ps1`  — approve the UAC prompt. Installs the toolchain + WSL2, then **reboot**.
4. `gh auth login` (and `railway login` if you deploy), then launch **Docker Desktop** and accept its license.
5. `gh repo clone vardan-kabra/nucleus C:\dev\nucleus` -> `cd C:\dev\nucleus` -> `.\scripts\dev-setup.ps1`.

`bootstrap.ps1 -Full` additionally installs the estate's **optional** tooling — ffmpeg +
faster-whisper (the feedback-extraction skill) and k6 (the Tier-0 load profiles). Off by default:
nobody joining the team needs either, and faster-whisper is a heavy install.

## Moving state off an old machine — `carry-over.ps1`
`bootstrap.ps1` installs software; **`carry-over.ps1` moves the state no installer can supply** —
every real `.env`, Claude Code's saved memory (`~/.claude/projects/<slug>/memory/`),
`~/.claude/settings.json`, and optionally `~/.ssh`. Export on the old machine, import on the new one:

```powershell
.\carry-over.ps1 -Export -IncludeSsh              # preview; -Apply -To <dir> to collect
.\carry-over.ps1 -Import -From <dir>              # preview; -Apply to restore
```

**Preview is the default on both sides** — nothing moves without `-Apply`. The bundle is not
encrypted and holds live secrets, so `-Apply` refuses to write it anywhere inside a git work tree;
move it on an encrypted disk and delete it afterwards. Run it **after** the repos are cloned: it
skips an `.env` whose repo is missing rather than scattering files into empty folders.

## Setting up the WHOLE estate, not just the `nucleus` repo
The two scripts above set up **one** repo. For a machine that also needs `nucleus-prototypes`
(~26 apps), the design system and the decisions repo — i.e. a full replacement for my own machine —
hand [`NUCLEUS-ESTATE-SETUP.md`](NUCLEUS-ESTATE-SETUP.md) to Claude Code instead. It drives these
same scripts, then covers the rest: exact clone paths, per-app Postgres containers, the carry-over
items no installer can supply (`.env` files, Claude memory, connector auth, droplet SSH keys), and
the traps this estate has already hit.

## ...or let Claude Code drive it
Open Claude Code in an empty folder and paste:

> Set up this machine for Nucleus development. Run `bootstrap.ps1` to install the toolchain
> (Node, Python, Docker + WSL2, VS Code, gh, DB GUIs), then walk me through `gh auth login` and
> accepting the Docker Desktop license. Then clone `vardan-kabra/nucleus` into `C:\dev\nucleus` and
> run `scripts/dev-setup.ps1` to install deps, bring up Postgres, migrate, and start the dev server.
> Explain each step and stop for the interactive bits.

**Why hybrid (script + Claude), not one or the other:** the script is deterministic, fast, and
identical on every machine for the mechanical toolchain install; Claude Code handles what a blind
script can't - the interactive `gh auth login`, the Docker license, the WSL first-run, and
diagnosing/explaining when something's off. Pure-script can't do the interactive steps; pure-Claude
is non-deterministic and costs tokens to re-derive a setup we already know exactly.
