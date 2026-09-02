# Backlog — nucleus-onboarding

_Last updated: 02-Sep-2026 — the repo grew from "machine toolchain installer" into the full
setup layer: whole-estate setup prompt, cross-machine state migration, and a rewritten
bilingual guide. Everything is on `main`; nothing is parked on a branch._

**Picking this up cold:** `git fetch origin && git checkout main` in a fresh clone of
`github.com/vardan-kabra/nucleus-onboarding`. There is **no worktree and no unmerged branch**
to go looking for — all three PRs merged and their remote branches are deleted.
`main` tip at close-out: `40d5346`.

---

## Shipped 02-Sep-2026

- [x] **`NUCLEUS-ESTATE-SETUP.md`** — new. A prompt pasted straight into Claude Code on a new
  machine to set up the **whole** estate (`nucleus` + the ~26 apps in `nucleus-prototypes` + the
  design system + the decisions repo). `bootstrap.ps1` and `nucleus/scripts/dev-setup.ps1` only
  ever covered the `nucleus` repo; this is the missing layer above them. PR #1, merge `de9ad799`.
- [x] **`bootstrap.ps1` — `@railway/cli` added, and a new opt-in `-Full`.** Railway CLI was
  genuinely missing and every deployed app lives there. `-Full` adds `Gyan.FFmpeg` +
  `faster-whisper` (feedback-extraction skill) and `GrafanaLabs.k6` (Tier-0 load profiles), off by
  default because a joining teammate needs none of it. **k6's winget id is `GrafanaLabs.k6`, not
  `k6.k6`** — confirmed with `winget search`. PR #1, merge `de9ad799`.
- [x] **`carry-over.ps1`** — new. Moves the state no installer can supply: every real `.env` under
  `-DevRoot`, `~/.claude/projects/<slug>/memory/**`, `~/.claude/settings.json`, and `~/.ssh` behind
  an opt-in `-IncludeSsh`. **Preview is the default on both `-Export` and `-Import`; `-Apply` does
  the work.** PR #2, merge `babbc2b9`.
- [x] **`index.html` — rewritten to explain *why*, not just *what*.** Added, in both languages: what
  Nucleus actually is; "you cannot break anything"; a new **step 0, accept your GitHub
  invitations**; clone-don't-download-a-ZIP; why `C:\dev\nucleus` exactly; why the GitHub login must
  precede install; and a pointer to `NUCLEUS-ESTATE-SETUP.md`. Steps renumbered 0–5.
  PR #3, merge `40d5346e`.

**Verification actually run (not "verified"):** both `.ps1` files parse clean under PowerShell 7
**and** 5.1, are pure ASCII with no BOM. `carry-over.ps1` round-tripped on this machine — export
then import-preview reported all **110 files "identical, skip"** (a true inverse); an edited `.env`
restored with the local copy preserved as `.env.pre-carryover`, counts **restored 1 / skipped 109**;
the git-work-tree guard refused and created nothing; **exit code 0 on every success path**.
`index.html` checked in a browser: **43 English spans against 43 Gujarati**, no English block
without a Gujarati twin, and the Gujarati view renders **zero empty blocks**.

**Not run:** `bootstrap.ps1` end-to-end with these changes — it installs system-wide and needs UAC,
so the new machine is its first real execution. If `-Full` misbehaves there, the likely suspect is
`python -m pip` not resolving in the elevated session's refreshed PATH; everything else in that
block is winget, already proven in this script.

## Open

- [ ] **[awaiting-you] (P1) Chinki must accept 5 invitations — they expire ~09-Sep-2026.**
  `chhapiachinkimypc` was invited with **write** to `nucleus-onboarding`, `nucleus-prototypes`,
  `fountainhead-design-system`, `nucleus`, `nucleus-erp-decisions` on 02-Sep. `claude-global-config`
  was deliberately **not** granted (VK's personal working rules; nothing needs it).
- [ ] **[awaiting-you] (P1) Run the carry-over export before the old machine is retired.**
  `.\carry-over.ps1 -Export -IncludeSsh -Apply -To <encrypted disk>`. The `~/.claude/.../memory/`
  folders (109 files at close-out) exist in **no git repo** — they are the one piece of machine
  state with no second source. Delete the bundle afterwards; it holds live DB URLs and an
  unencrypted private key.
- [ ] **[awaiting-you] (P2) Does the machine-written Gujarati need a native-speaker read before
  this page goes beyond one joiner?** The Gujarati in the *new* `index.html` sections (what-you're-
  setting-up, invitations, ZIP-vs-clone, estate pointer) is mine, not a native speaker's; the
  pre-existing translations presumably were reviewed. VK to decide who reads it.
- [ ] **[awaiting-you] (P2) Three collaborator invitations elsewhere in the estate have silently
  expired** and those people have no access today: `pradipkalsariya-byte` → `nucleus` and
  `nucleus-erp-decisions` (sent 05-Aug-2026); `sonalshah-fountainheadschools` →
  `nucleus-erp-decisions` (sent 22-Jun-2026). Re-invite with
  `gh api -X PUT repos/vardan-kabra/<repo>/collaborators/<user> -f permission=push` if they are
  still meant to have it.
- [ ] **[awaiting-you] (P3) The orientation artifact is private and only VK can share it.**
  https://claude.ai/code/artifact/6c3f7a5f-5a03-49b7-ac49-e2a21906659d — share from the page's own
  share menu. The recipient is on a personal Gmail account outside the Workspace, so an
  "anyone with the link" scope is likely needed. **Prefer pointing people at `index.html` in this
  repo instead** — bilingual, versioned, no account required.
- [ ] **[deferred] (P3) One unattributed pending email invitation sits on `nucleus-onboarding`**
  (id `331373893`, created 02-Sep-2026 06:42 UTC). The API returns `invitee: null` **and**
  `email: null`, so it cannot be attributed — deliberately left alone rather than revoked, in case
  it was meant for someone other than Chinki. It self-expires ~09-Sep-2026.

## Hazards found here — don't rediscover these

- **A native command's exit code becomes the script's exit code.** `carry-over.ps1`'s git-work-tree
  guard calls `git rev-parse`, which exits **128** outside a work tree — the answer the guard wants
  — and the whole script then exited 128 after a completely successful run. Any `&&` chain around it
  would read that as failure. `$ErrorActionPreference = 'Stop'` does not catch it (cmdlet errors
  only). Fix: `$global:LASTEXITCODE = 0` after the probe, and `exit 0` on success paths.
- **Claude Code memory is keyed off the project's absolute path** (`C:\dev\nucleus-prototypes` →
  `C--dev-nucleus-prototypes`). Cloning to a "tidier" folder on a new machine silently orphans every
  saved memory file — nothing errors. Clone to identical paths. Same reason
  `nucleus-prototypes/.claude/launch.json` works: it hardcodes absolute `C:\dev\...` paths.
- **Next.js standalone builds copy `.env` into `.next/`.** A naive `.env` sweep collects that
  generated copy — a stale secret restored into a stale build. `carry-over.ps1` excludes
  `.next|.turbo|dist|build|out|coverage`; anything else sweeping for env files should too.
- **A restored SSH private key is rejected by Windows OpenSSH** (`UNPROTECTED PRIVATE KEY FILE`) —
  a copied file inherits the destination folder's ACL. The failure surfaces at the far end, on a
  droplet, looking nothing like a permissions problem. `carry-over.ps1` re-locks with `icacls`.
- **An email-based GitHub invitation is unattributable via the API** — both `invitee` and `email`
  come back `null`. Invite by username whenever possible; those stay verifiable.
