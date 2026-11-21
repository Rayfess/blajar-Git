# Verify-and-fix loop — protocol

The suite lives **ephemerally** in `%TEMP%\wsl-tests` (deliberately out of the
repo; re-create it from `MILESTONE.md` §6 if Temp is wiped). This document
preserves the protocol and the battery's contract. The repo keeps
documentation only — the automation scripts and `readme.md` at the root,
everything else under `docs/`.

## The loop protocol

```
1. cd %TEMP%\wsl-tests  &&  bash verify-all.sh
2. all PASS  -> done.
   any FAIL  -> fix the smallest cause of ONE signature, then go to 1.
3. stop conditions:
   - all checks PASS                       -> report success
   - the SAME "SIGNATURE:" line appears in 3 CONSECUTIVE iterations
                                           -> STOP; report the problem verbatim
                                              to the user (3-strike rule)
   - 6 iterations elapsed without a pass   -> STOP; report state
4. never git-commit inside the loop — leave every green state uncommitted
   for human review (protects the scheduled-commits workflow).
```

A "fix" must keep all previously passing checks green — a new failing
signature counts as a different iteration input, not progress.

## The battery — `verify-all.sh`

| # | Check | What it catches |
|---|-------|-----------------|
| 1 | `syntax` | `bash -n` on provision-wsl.sh, run-sim-tests.sh, verify-install.sh |
| 2 | `sim` | full sandbox suite (incl. PowerShell component tests) |
| 3 | `pin-urls` | every pinned `releases/download` URL HEAD-checked → 200 — the patina `v1.12.0`-vs-`1.12.0` tag-prefix bug class; offline = WARN, not FAIL |
| 4 | `pin-consistency` | hardcoded version literals in URL templates, literal tags in antidote bundle annotations, unpaired `zcode-managed` markers |
| 5 | `v1-remnants` | leftover references to the removed v1 plugin stack |
| 6 | `doc-lint` | docs contradicting the script (removed flags, stale flows, duplicated statements) |
| 7 | `hygiene` | stray dirs, TODO/FIXME markers |

First full run: PASS 7/7 in 4 fix iterations (see MILESTONE §6); the second
consecutive run passed with zero edits — idempotent.

Known limitation: the sandbox rewrites an enumerated list of absolute paths
(`/etc/...`, `/usr/local/...`) into the sandbox; a brand-new absolute path in
provision-wsl.sh would escape it silently. When adding new system paths to
the provisioner, extend the rewrite list in `run-sim-tests.sh` (~lines 37-41)
in the same change.

## Sandbox sim suite — `run-sim-tests.sh`

Runs the real `provision-wsl.sh` inside a stubbed sandbox (fake
sudo/apt/docker/curl/dpkg/git; `/etc`, `/usr/local`, `$HOME` redirected into a
temp dir). Nothing on the real system is touched. Five scenarios: fresh
install, rerun idempotency, escape hatches, non-Debian abort, systemd gate.

## Live checks — `verify-install.sh` / `verify-install.ps1`

Read-only checks run on the real machine after provisioning (inside Debian /
on Windows respectively): versions, default shell, zsh stack presence,
`.zshrc` marker, startup-time soft target, `.wslconfig`, Portainer reachability.

## PowerShell component tests — `ps-component-tests.ps1`

Component assertions on `wsl-setup.ps1` logic; driven by the sim suite
automatically when `powershell` is available.
