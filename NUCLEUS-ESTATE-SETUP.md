# Set up a machine for the FULL Nucleus estate

`bootstrap.ps1` + `nucleus/scripts/dev-setup.ps1` set up **one repo**: the nucleus production
build. This file is for setting up **everything** — nucleus, the ~26 apps in `nucleus-prototypes`,
the design system, and the decisions repo — on a fresh Windows 11 PC.

**How to use it:** open Claude Code in an empty folder on the new machine and paste this whole
file in as the prompt. Everything below is addressed to it.

---

You are setting up a fresh Windows 11 PC to do Nucleus development the way it is done on my current
machine. Work through the phases in order. **Stop and hand control back to me for every interactive
sign-in** — don't try to automate a browser login.

## What the estate actually is

Three repo families, all Next.js 15 / TypeScript / Prisma / Postgres:

- `C:\dev\nucleus` — the production ERP (operator console on port 3200, its own Postgres on **5440**).
- `C:\dev\nucleus-prototypes` — ~26 prototype and live apps in one repo (ibdp-results, dp-sow-tracker,
  recruitment, hris, route-planning, cafeteria-checkin, front-desk, event-management, roster-gateway…).
  Each app has its own Postgres container on its own port (5434–5451) via its own `docker-compose.yml`.
- `C:\dev\nucleus-erp-decisions` — the decisions/spec source of truth (docs only, nothing to build).

Plus `C:\dev\fountainhead-design-system` — the shared DS, consumed by every app as a **private git
npm dependency**, pinned estate-wide to one version.

## Ground rules — read before doing anything

1. **Clone to the EXACT paths below. Do not "tidy" them.** Three things break silently otherwise:
   `nucleus-prototypes/.claude/launch.json` hardcodes absolute `C:\dev\nucleus-prototypes\…` paths
   for the dev-server launcher; many scripts assume `C:\dev\`; and Claude Code's per-project memory
   lives in a directory keyed off the path slug (`~/.claude/projects/C--dev-nucleus-prototypes/`),
   so a different path silently orphans ~95 saved memory files.
2. **Never install a database onto Windows.** Every Postgres runs in Docker. DBeaver is the GUI.
3. **Use the scripts that already exist** — don't hand-roll installs they already cover.
4. Windows PowerShell 5.1 is NOT PowerShell 7. `&&` is a parse error in 5.1 and bare `npx` often
   fails there. `bootstrap.ps1` installs PowerShell 7; use `pwsh` for everything afterwards.

---

## Phase 0 — by hand (the only two you can't script)

- **Git for Windows** — https://git-scm.com/download/win
- **Claude Code** — https://claude.com/claude-code (then `/login`)

If scripts are blocked, run once: `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`

## Phase 1 — machine toolchain

```powershell
git clone https://github.com/vardan-kabra/nucleus-onboarding.git C:\dev\nucleus-onboarding
cd C:\dev\nucleus-onboarding
.\bootstrap.ps1 -Full
```

Approve the UAC prompt, then **reboot when it finishes**.

It installs via winget — **Node.js LTS · Python 3.13 · Docker Desktop + WSL2 · VS Code · GitHub CLI ·
PowerShell 7 · Windows Terminal · DBeaver · MongoDB Compass** — plus the global npm tools
`typescript ts-node nodemon @railway/cli`. `-Full` adds **ffmpeg**, **faster-whisper** (the
feedback-extraction skill) and **k6** (Tier-0 load profiles); drop the flag if I say I don't need those.

Two things bootstrap deliberately does not install, both optional — ask me before adding either:

- **`psql` on PATH** — needed only by `node tools/check-raw-sql-constraints.mjs --db <app>`, which
  spawns `psql` directly and skips loudly without it. DBeaver does not provide it, and the
  PostgreSQL winget package installs a *server*, which violates ground rule 2 — so install the
  client tools only, with the server component deselected, or tell me it's being skipped.
- **VS Code extensions**: `dbaeumer.vscode-eslint esbenp.prettier-vscode Prisma.prisma
  bradlc.vscode-tailwindcss ms-azuretools.vscode-docker eamodio.gitlens GitHub.vscode-pull-request-github`

Java and the Android SDK are **not** needed locally — the campus-displays TV APK builds in GitHub
Actions. No SQL Server, no .NET, no Angular anywhere in this repo family.

## Phase 2 — sign-ins (interactive — hand these to me)

```powershell
gh auth login
railway login
```

`gh auth login` → github.com → HTTPS → login with a web browser. Then launch **Docker Desktop** once
and accept its licence. `wsl --status` must report `Default Version: 2`.

**`gh auth login` must succeed BEFORE any `npm install`** — the design system is a private git
dependency and npm install fails on it otherwise.

## Phase 3 — clone the repos (exact paths)

```powershell
gh repo clone vardan-kabra/nucleus                     C:\dev\nucleus
gh repo clone vardan-kabra/nucleus-prototypes          C:\dev\nucleus-prototypes
gh repo clone vardan-kabra/nucleus-erp-decisions       C:\dev\nucleus-erp-decisions
gh repo clone vardan-kabra/fountainhead-design-system  C:\dev\fountainhead-design-system
gh repo clone vardan-kabra/claude-global-config        C:\dev\claude-global-config
```

Optional, only if I ask: `fountainhead-web`, `indian-payroll`, `browser-games`, `fwgs_trackers`.

Then deploy my global Claude config — it installs `~/.claude/CLAUDE.md` and my agents, and junctions
`~/.claude/skills` to the repo so global skills stay versioned:

```powershell
cd C:\dev\claude-global-config
.\install.ps1
```

## Phase 4 — project setup

**Nucleus (production repo)** — one script does all of it:

```powershell
cd C:\dev\nucleus
.\scripts\dev-setup.ps1
```

It installs deps, generates both Prisma clients, starts Postgres on **5440**, migrates both schemas,
runs the §12 acceptance gate, and installs the sibling repos. Then `npm run dev` → http://localhost:3200.

**nucleus-prototypes** — there is no root package.json; each app installs independently. Do **not**
install all 26. Set up these three, then stop and check with me:

| app | dev port | why this one |
|---|---|---|
| `ibdp-results` | 3100 | design-system pace-setter, live real data |
| `recruitment` | 4400 | most active app; the only real-Postgres test lane (`tests-db/`) |
| `hris` | 4300 | payroll / Tier-0 surface |

Per app:

```powershell
cd C:\dev\nucleus-prototypes\<app>
npm install
npm run db:up
npm run prisma:generate
npm run db:migrate
npm run seed
npm run dev
```

Read each app's `package.json` first — the migrate script is variously `db:migrate`, `prisma:migrate`
or `db:deploy`, and not every app has a `seed`.

## Phase 5 — the things that CANNOT be installed (I have to supply them)

List these back to me as a checklist and wait. Don't guess at values.

1. **`.env` files.** Every real `.env` is gitignored — the repo carries only `.env.example`, one per
   app. Sources: `railway variables` per service for deployed apps, my old machine for local-only
   ones. **Never paste a secret value into the chat** — write it straight to the file.
2. **Claude Code memory** — `~/.claude/projects/C--dev-nucleus-prototypes/memory/` (~95 files plus
   `MEMORY.md`). It lives in no git repo. Copy the whole folder from the old machine, and the sibling
   project folders too. This is why the clone paths must match exactly.
3. **`~/.claude/settings.json`** — model/effort defaults, permissions, hooks. Copy it across.
4. **MCP connectors / plugins** re-authorise per machine (Gmail, Drive, Calendar, GitHub…), via
   claude.ai connector settings or `/mcp` in an interactive session. Cannot be scripted.
5. **SSH keys for the DigitalOcean droplets** — the roster gateway and the HRIS punch relay. Copy
   `~/.ssh` from the old machine, or I'll add a fresh key to both droplets.
6. **Git identity**: `git config --global user.name` / `user.email`, plus `init.defaultBranch main`,
   `core.autocrlf true`, `pull.rebase false`.

## Phase 6 — verify, and show me the actual output

Don't tell me it works — show it. Run these and paste the real results:

```powershell
node -v ; npm -v ; python --version ; docker --version ; gh --version ; railway --version ; pwsh -v
```

```powershell
cd C:\dev\nucleus-prototypes
node tools\check-ds-version.mjs
node tools\check-auth-domains.mjs
node tools\check-fh-classes.mjs
node tools\check-canonical-host.mjs
node tools\check-raw-sql-constraints.mjs
```

Then boot **one** app, open it in the browser preview, and screenshot it. Then run `npm test` and
`npm run typecheck` in `recruitment` and show the output.

Finish with a table — tool / version / OK-or-not — and a separate list of anything still owed from
Phase 5.

---

## Known traps (all of these have bitten before — don't rediscover them)

- **`npm install` succeeds but Prisma/vitest are broken** → npm 11+ blocks package install scripts by
  default. Run `npm approve-scripts --all`. (`nucleus`'s dev-setup.ps1 already does this.)
- **`npm install` fails on `@fountainhead/design-system`** → not signed into GitHub. `gh auth login` first.
- **`Cannot find module '.../dist/*.mjs'` from a dependency, not your own code** → that one package
  extracted badly. `Remove-Item -Recurse -Force node_modules\<pkg>` then `npm install` again — do not
  wipe all of node_modules.
- **`next build` failing with cascading module errors** → on my current machine that is Windows
  AppLocker blocking `next/swc`, not a real defect. If it happens here, verify via a Docker build
  before believing it.
- **Port collisions already in the repo**: `health-sickbay` and `recruitment` both use dev port
  **4400** — run one at a time. The Postgres containers for `health-sickbay` and `career-counselling`
  both claim host port **5442**; the loser can show "Up (healthy)" with no port binding at all.
- **Nucleus Postgres is 5440, not 5432**; the operator console is 3200.
- **A DB test that times out on the very first run** is cold-start slowness — re-run it warm.
- Everything deploys with `prisma migrate deploy`. **Never run `prisma db push`** — it silently drops
  the raw-SQL partial indexes and CHECK constraints that five invariants across three apps depend on,
  and reports nothing while doing it.
- Read `C:\dev\nucleus-prototypes\CLAUDE.md` end to end before changing anything. It carries the
  estate-wide rules — design-system lockstep, the auth domain allowlist, the canonical-host bounce,
  branch/PR hygiene — and names the mechanical check that enforces each one.
