# MILESTONE — WSL2 + DDEV Setup Automation

Context-preservation document for this project: where it started, where it
stands now, what was learned the hard way, and how any future session (human
or AI) can resume without losing the thread.

Read order for context recovery: [readme.md](readme.md) (install guide) →
[wsl-ddev-setup-prd.md](wsl-ddev-setup-prd.md) (requirements contract) →
**this document** → the two scripts.

---

## 1. Project Overview

A one-command installer for a full Linux development environment on WSL2:

- `wsl-setup.ps1` (Windows): preflight → decision tree → enables WSL features,
  installs Debian, writes `.wslconfig`, guides the native first launch, and
  hands off via a printed guide - the provisioning script is copied into the
  Linux filesystem and run from there (containment, Nov 20 decision).
- `provision-wsl.sh` (Debian, 13 tasks): inventory → wsl.conf → apt → dev
  tools (curl/git/zsh/unzip/build-essential) → nvm + Node LTS → zsh stack
  (autosuggestions/completions/syntax-highlighting/AUTO_CD) → Docker CE →
  DDEV → mkcert → CA import → Portainer (loopback) → PASS/FAIL status report.

Scope decisions: **Debian-only**, single-distro rule, native first launch
(no non-interactive user creation), skip-if-installed idempotency, file-based
password delivery, TTY-gated colored output. Full contract:
[wsl-ddev-setup-prd.md](wsl-ddev-setup-prd.md).

## 2. Status Snapshot (2026-11-20)

- All work committed and pushed through `f7f5144` (scheduled 20 Nov 09:10).
- Offline sandbox suite: **23/23 PASS** (5 scenarios incl. negative + gate).
- PowerShell component tests: **17/17 PASS**.
- **PENDING: the first real end-to-end installation run** — every real-run
  bug found so far (see §5) has a fix in place, but the fixed chain has not
  yet been proven end-to-end on the actual machine.
- Scheduled commit queue: 18 Nov ×3, 19 Nov ×3, 20 Nov ×2 (contribution
  graph lights up per scheduled date).

## 3. Evolution Timeline

| Phase | Date (approx) | What happened |
|-------|----------------|---------------|
| P0 | pre-session | `wslddev.md` — the original manual procedure this project automates |
| P1 | Nov 13 | PRD written (v1 → decision-tree/flags → zsh stack), 3 commits |
| P2 | Nov 14 | Both automation scripts implemented (Debian/Fedora support, single-distro rule) |
| P3 | Nov 14–16 | Security hardening (download-to-file, pinned refs, loopback Portainer, root guard), Debian-only + native OOBE revert, color-coded UX |
| P4 | Nov 16–17 | Offline sandbox test suite built (`tests/` later moved out of repo); real-run debugging began (erlog.txt) |
| P5 | Nov 17–18 | Real-run bug fixes (see §5), nvm migration, completions default + AUTO_CD, revert of the default-user gate back to native first launch |
| P6 | Nov 18–20 | Scheduled commit queue filled (3+3+2); password delivery hardened per microsoft/WSL#42094 |
| P7 | **pending** | First real end-to-end run + live verifiers |

## 4. Real-Run Bug Ledger

Bugs found only by actually running the automation (or analyzing its output):

| # | Symptom / bug | Root cause | Fix |
|---|---------------|------------|-----|
| 1 | Branch 2 installed **Ubuntu**, violating Debian-only | `wsl --install` without `-d` defaults to Ubuntu | `-d Debian` in every install call |
| 2 | Script **crashed** on WSL's Sparse-VHD stderr warning | PS 5.1 + `$ErrorActionPreference='Stop'` turns native stderr into terminating errors even when redirected | `Invoke-Wsl` helper: stderr merged via `cmd /c ... 2>&1`, EAP `Continue` |
| 3 | `USER: unbound variable` crash | `set -u` + minimal non-login environment | `USER="${USER:-$(id -un)}"` at script top |
| 4 | **sudo rejected the password** the user had just chosen (FR-12 paste) | Piped stdin into `wsl.exe chpasswd` is discarded — microsoft/WSL[#42094](https://github.com/microsoft/WSL/issues/42094), [#12523](https://github.com/microsoft/WSL/issues/12523) | Canonical in-VM pattern: `wsl -u root -- bash -c "echo 'user:pass' \| chpasswd"` (echo runs inside the VM; no Windows stdin) |
| 5 | Second stdin attempt (temp file + `Get-Content \| wsl.exe`) **still** empty | Same #42094 class — wsl.exe stdin passthrough unreliable through PS pipes | Same fix as #4; plus **positive gate-time verification**: `sudo -S -k id -un` must echo the username before chaining, otherwise FAIL with reset instructions |
| 6 | `permission denied ... docker.sock` at FR-12 | `id -nG "$USER"` reads the group **database** (already updated by usermod), not the **session's** effective groups | `run_docker` checks `id -nG` (session), falls back to `sg docker` |
| 7 | `WSL_E_DISTRO_NOT_FOUND` in the installer AND the Windows Terminal Debian profile, while `wsl -d Debian` works | Stale distro name after unregister/reinstall cycles: the registry `DefaultDistribution` GUID (read by `Get-DefaultDistro`) and the cached WT profile pointed at an unregistered name | Branch 1 auto-heals: validates the default against registered distros, runs `wsl --set-default <first registered>`; user-side verified order: `wsl --shutdown` → `wsl --set-default Debian` → `wsl -l -v` → restart Windows Terminal |

## 5. Design Decision Ledger

| Decision | Rationale |
|----------|-----------|
| Debian-only, single-distro rule | Long-support target; multi-distro complexity rejected |
| Native first launch over pwsh-created user | Reverted to the documented flow (learn.microsoft.com/windows/wsl) — credentials typed natively in Debian, never through PowerShell; the pwsh gate caused two stdin-delivery bugs |
| Root stays password-locked | `wsl -u root` ignores Linux passwords → a root password provides no protection; the OOBE user + sudo is the real boundary |
| Firefox = own NSS store (Windows import doesn't apply) | CA trusted in Windows covers Chrome/Edge only; Firefox needs manual rootCA import or the ImportEnterpriseRoots policy — documented in readme Verification/Troubleshooting |
| nvm pinned `v0.40.3`, `nvm install --lts` | Replaces NodeSource; Node tracks current LTS without touching the script |
| mkcert = project-wide local TLS authority (not Portainer-scoped) | DDEV itself generates SSL certs via mkcert (docs.ddev.com "Configuring Browsers") — DDEV is the primary consumer; Portainer consumes one generated cert (FR-16). Reusable pattern for future local services documented in readme. libnss3-tools = NSS store Linux-side only (Firefox/Chromium), NOT a WSL2→Windows bridge (mkcert repo: Firefox support "macOS and Linux only") |
| zsh-completions default (pinned `0.34.0`) | fpath-before-compinit integration has near-zero startup cost; the documented cost applies to the oh-my-zsh mechanism (not used) |
| `AUTO_CD`, no framework, syntax-highlighting last | User preference + plugin docs |
| swap=1GB (owner-adjusted from doc-exact 4GB) | Storage-saving adjustment, declared in PRD |
| TTY-gated colors (`-t 1`) | Piped/captured output (tests, logs) stays plain so assertions never break |
| Skip-if-installed everywhere | Rerun-safe; partial failures resume without reinstalling |
| Scheduled future-dated commits | Contribution-graph queue (18/19/20 Nov) — established user workflow |
| Flag surface trimmed to 4 | YAGNI: `--shell`/`--no-portainer` removed (never used); kept `--no-upgrade`/`--skip-ca-import`/`--log`/`--pause` |
| Manual handoff over auto-chain (containment) | Windows phase ends with a printed guide; the provisioning script is copied into the Linux filesystem and run from there — no cross-boundary execution (Nov 20 decision) |
| Flag surface trimmed to 4 | YAGNI: `--shell`/`--no-portainer` removed (never used); kept `--no-upgrade`/`--skip-ca-import`/`--log`/`--pause` |
| Persistent cert dir `$HOME/.local/share/portainer-tls` | `/tmp` bind-mounts broke after VM boot (Debian tmpfiles wipes `/tmp` → dockerd auto-created dirs → "not a directory"); certs now survive restarts |

## 6. Validation Status

- Offline sandbox suite (`run-sim-tests.sh`, 5 scenarios): **23/23 PASS** —
  fresh, rerun/idempotency, escape-hatches (`--no-upgrade --skip-ca-import`),
  non-Debian abort, systemd restart gate.
- PowerShell component tests: **17/17 PASS** (UTF-16 cleaning, path mapping,
  single-distro, Debian-only validation, FR-04 thresholds, WSLENV append,
  `.wslconfig` keys).
- Limitation: the interactive pwsh gate and the real installer are **not
  covered by the sandbox** — only the next real run can close that gap.

## 7. Local Machine State (WSL)

- **Debian** distro installed (Branch 3, Nov 16); first launch **not**
  completed → default user still root → on rerun, Branch 1 prints the
  first-launch instructions.
- **`nann`** user created (home, sudo group) with a password that was never
  successfully set — the default-user gate's reset/creation flow resolves
  this on the next run.
- **Ubuntu** was installed by the Branch 2 bug (#1 in §4) — unregister it if
  still present: `wsl --unregister Ubuntu`.
- `.wslconfig` written with swap=1GB (owner-adjusted); feature states enabled.

## 8. Pending / Next Steps

1. **Real end-to-end run**: `wsl --unregister Ubuntu` (if present) →
   `wsl-setup.ps1` (Admin) → complete the native first launch when instructed
   → provisioning chains automatically → check `RESULT: PASS`.
2. Run `tests/verify-install.sh` inside Debian + `tests/verify-install.ps1`
   on Windows for the acceptance-criteria sweep.
3. **Ephemeral artifact warning**: the offline test suite lives in
   `%TEMP%\wsl-tests` (moved out of the repo by design) — Temp is wiped by
   Windows periodically. Re-create it from this document's §6 description or
   re-add `tests/` to the repo if it will be maintained.
4. Open (non-blocking): none — all raised requests are implemented.

## 9. File Map

| File | Role |
|------|------|
| `wsl-setup.ps1` | Windows preparer: preflight, decision tree, `.wslconfig`, first-launch guidance, chain |
| `provision-wsl.sh` | Debian provisioner: 13 tasks, flag surface, PASS/FAIL report |
| `wsl-ddev-setup-prd.md` | Requirements contract (FR-01..FR-18, policies, risks) |
| `readme.md` | User-facing install guide + Sources table |
| `wslddev.md` | Original manual procedure (source of truth for the flow) |
| `git-scheduled-commits.md` | Scheduled/backdated commit technique doc |
| `%TEMP%\wsl-tests\` | Offline test suite (ephemeral — see §8.3) |

## 10. Scheduled Commit Queue

| Date | Commits |
|------|---------|
| 18 Nov | session-groups fix · default-user preflight · restart attribution (09:00/05/10) |
| 19 Nov | Sources readme · nvm migration · password delivery + gate verification (09:00/05/10) |
| 20 Nov | completions default + AUTO_CD (09:00) · flag redesign landed (09:05) · native-flow revert (09:10) · this MILESTONE.md (09:15) · history integrity notes (09:20) |

## 11. History Integrity Notes (audit 2026-11-17)

- **Object integrity**: `git fsck --no-dangling` clean — no corruption.
- **Future-dated commits**: 12 commits (18–20 Nov) use author date =
  commit date, both future-dated by design (contribution-graph queue).
  Implication: author dates for those entries reflect the *scheduled* day,
  not the real work moment; date-based filters (`git log --since`) and
  forensic "when was this written" readings must account for that.
- **Feature split across commits**: the Nov-17 flag redesign landed as two
  scheduled commits — `0309695` (completions default + AUTO_CD, 15 lines in
  provision) and `7f6cf73` (remaining flag surface, 42 lines). Verified via
  `git show <commit> --stat` — messages match content in both. Lesson: a
  commit message can legitimately describe only part of a feature when the
  rest lands in a sibling commit; verify with `git show --stat`, not by
  message alone.
- **Versioning**: the repo carried no tags until `v0.1.0` (this audit date),
  which marks the stable point: sandbox suite 23/23, component tests 17/17,
  Debian-only installer complete. Future releases follow semver from here.
