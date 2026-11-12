# PRD — WSL2 + DDEV Setup Automation

## 1. Product Context

### Problem

Setting up the WSL2 + DDEV development environment (wslddev.md) is a long manual
procedure spread across Windows and Linux. Following it by hand is error-prone and
the document has known gaps: missing `sudo` on one install command, a Docker
repository hardcoded to Debian, no docker group membership for the user, `mkcert`
used before it is installed, and no handling for restarts or re-runs. Several
documented config options are also silently ignored on unsupported Windows/WSL
versions.

### Goal

A pair of automations that take a possibly bare Windows machine to a ready
development environment:
- Windows: enable the WSL feature, install a distro (user picks from the supported
  list), apply the exact documented `.wslconfig`, and chain into Linux provisioning
- Linux: provision everything inside WSL2 (dev tools, zsh shell, Docker CE, DDEV,
  mkcert, Portainer), printing what it changes at every step
- both automations check what already exists before installing anything, and end
  with a clear status report instead of creating any project.

### Target Users

- The repository owner, on this machine and on future fresh machines.
- Anyone following wslddev.md as the setup reference.

### Scope

In Scope:
- Windows: WSL feature enablement, distro installation via decision tree,
  `.wslconfig` generation, chaining into Linux provisioning
- Linux: `/etc/wsl.conf`, package index refresh (+ optional upgrade), development
  tools, zsh with essential plugins, Docker CE, DDEV, mkcert (+ CA import to
  Windows), Portainer
- Skip-if-installed behavior with version status output
- Per-task verbose logging with a 5-second pause
- Final status report (docker, ddev, Portainer, containers)

Out of Scope:
- Ubuntu and all distros other than Debian and Fedora (declared deliberately)
- Running with more than one WSL distro installed
- Project migration with rsync
- Creating any project (no Laravel smoke test)
- Rollback/uninstall path
- Passwordless sudo

## 2. Deliverables and Interface

Two automations:

### wsl-setup.ps1 (Windows)
- Executable: Windows PowerShell 5.1 (`powershell.exe`, built into Windows —
  no extra install needed)
- Run elevated as Administrator: `powershell -ExecutionPolicy Bypass -File wsl-setup.ps1`
- Location: repository root
- Interactive where the OS requires it: elevation prompt, distro selection,
  first-launch user creation

### provision-wsl.sh (Linux / WSL)
- Executable: bash inside the WSL distro
- Invoked two ways:
  - chained automatically by wsl-setup.ps1:
    `wsl -d <distro> -e bash <repo-path>/provision-wsl.sh`
  - manually from inside WSL: `bash provision-wsl.sh`
- Unattended after the single sudo password prompt
- Flags: `--upgrade` (also run a full package upgrade), `--skip-ca-import`,
  `--with-zsh-completions` (opt-in zsh-completions plugin),
  `--pause <seconds>` (default 5)

## 3. Use Cases

### UC-01 - Run Windows Setup
User runs wsl-setup.ps1 elevated. The script follows the distro decision tree
(FR-02) and either: continues into Linux provisioning, installs the WSL feature
and asks for a restart, or offers the supported distro list for the user to pick.

### UC-02 - Provision Linux
Runs chained from UC-01 or manually. After one sudo prompt it is unattended:
prints an inventory of what is already installed, then installs only what is
missing, adapting to the distro it is actually running in (apt on Debian, dnf on
Fedora).

### UC-03 - Read the Status Report
User reads the final output block: whether docker, ddev, and Portainer are
active, and a list of all existing containers.

## 4. Product Rules

- `.wslconfig` content matches wslddev.md exactly: processors=6, memory=10GB,
  swap=4GB, nestedVirtualization=true, networkingMode=Mirrored, autoProxy=false,
  sparseVhd=true.
- Supported distros, declared deliberately: **Debian >= 12** (long support,
  server-like role) and **Fedora >= 42** (fresh desktop-dev toolchain, ~13-month
  lifecycle — a yearly distro upgrade is the user's declared obligation).
  Ubuntu and everything else is out of scope.
- **Single-distro rule**: exactly one WSL distro may be installed on the machine.
  wsl-setup.ps1 refuses to provision with more than one and lists them with
  removal instructions (`wsl --unregister <name>`).
- The Linux script never trusts the Windows side for distro facts: it detects the
  running distro from `/etc/os-release` and adapts. The Docker repository matches
  the detected distro (deb822 apt source on Debian, docker-ce.repo via
  dnf config-manager on Fedora), never hardcoded.
- Package-manager abstraction, declared deliberately: apt on Debian, dnf on
  Fedora, with an explicit package-name mapping (build-essential ->
  gcc/gcc-c++/make, libnss3-tools -> nss-tools, architecture from `uname -m`
  mapped to mkcert release naming).
- Every task prints a header, what it does, and the changes it made; a 5-second
  pause follows each task.
- Idempotent and skip-if-installed: existing components are reported with their
  version, never reinstalled.
- An existing `.wslconfig`, `/etc/wsl.conf`, or `~/.zshrc` is backed up only when
  its content differs and the file was not generated by this automation (marker
  comment). Script-managed `.zshrc` changes are appended as a marker-delimited
  block and never clobber user content.
- Shell setup policy, declared deliberately: no framework (Oh My Zsh is rejected
  for its startup cost). Plugins are git-cloned `--depth=1` and sourced directly;
  `zsh-syntax-highlighting` is sourced last, as its documentation requires.
  `zsh-completions` is opt-in because its own documentation flags compinit
  startup cost.
- The Linux script is unattended after one sudo prompt (sudo timestamp kept
  alive); the Windows script is interactive only where the OS requires it
  (elevation, distro choice, first-launch user creation).
- Fail fast on the Linux side: the first failed step aborts with a clear message.
  Windows-side gates (restart, first launch) exit with resume instructions
  instead; every gate is resumable by rerunning wsl-setup.ps1.
- No project is created; the run ends at the status report.
- "Latest" policy, declared deliberately: DDEV, Docker CE, and the Portainer
  image use latest stable, no version pinning.
- Consequence of `appendWindowsPath=false`, declared deliberately: Windows
  executables (`code`, `explorer.exe`, ...) are not on the WSL PATH, per wslddev.md.
- If the Windows build or WSL version does not support Mirrored networking or
  systemd, the documented config is still written (doc-exact decision) with a
  loud warning and a FAIL entry in the final report.

## 5. Requirements — Windows (wsl-setup.ps1)

### FR-01 - Windows Preflight
Aborts with a clear message if not elevated. Prints the Windows build,
`wsl --version`, `wsl -l -v`, WSL feature state, and physical RAM (warns if
below the documented `memory=10GB`). Warns if Docker Desktop is installed
(Docker docs require removing it before Docker CE).

### FR-02 - Distro Decision Tree
- Branch 1 - distro installed: enforces the single-distro rule (aborts with
  the list of registered distros and removal instructions if more than one),
  writes `.wslconfig` (FR-03), then chains into Linux provisioning by invoking
  provision-wsl.sh in the distro.
- Branch 2 - distro absent, WSL feature absent: run `wsl --install`, print
  restart feedback, exit. Rerunning after restart lands in Branch 3.
- Branch 3 - distro absent, WSL feature present: run `wsl --list --online`,
  display a numbered list **filtered to supported distros only (Debian,
  Fedora)**, install the user's selection (`wsl --install -d <distro>`), then
  exit with first-launch instructions (the distro's first launch interactively
  creates the UNIX user). Rerunning lands in Branch 1.

### FR-03 - Write .wslconfig
Writes `%UserProfile%\.wslconfig` with the exact documented content, shows the
written file, and runs `wsl --shutdown` so it applies on next start.

### FR-04 - Capability Warning
If the Windows build or WSL version does not support Mirrored networking or
systemd, warns loudly and records a FAIL for the final report (forwarded via
WSLENV); still writes the documented config.

## 6. Requirements — Linux (provision-wsl.sh)

### FR-05 - Inventory and Preflight
Detects distro, version, and codename from `/etc/os-release`; aborts if outside
the supported matrix (Debian >= 12, Fedora >= 42) or unknown; a missing
VERSION_CODENAME only aborts on Debian (it is required there for the Docker apt
source). Checks systemd state; prints an inventory of what is already installed
with versions: docker, ddev, mkcert, portainer container, git, node/npm, bun,
zsh, curl. Nothing is reinstalled if present.

### FR-06 - wsl.conf
Writes `/etc/wsl.conf` per wslddev.md (backup rule as in Product Rules). If
systemd is not yet active, exits with restart instructions (`wsl --shutdown`
from PowerShell); on rerun it continues.

### FR-07 - Package Index
Refreshes the package index every run (`apt-get update` on Debian, `dnf
makecache` on Fedora). Runs a full upgrade only with the `--upgrade` flag.

### FR-08 - Development Tools
Installs only items missing from the tool list defined at the top of the script.
Default list: curl, git, zsh, a C toolchain (build-essential on Debian; gcc,
gcc-c++, make on Fedora), Node.js LTS with npm (NodeSource deb/rpm setup script
per distro), bun (via its official installer). Prints versions after installation.

### FR-09 - Shell Setup (zsh)
Clones `zsh-users/zsh-autosuggestions` and `zsh-users/zsh-syntax-highlighting`
(`git clone --depth=1`) into `~/.zsh/plugins/` (skip if present), and appends a
marker-delimited block to `~/.zshrc` that sources them directly —
`zsh-syntax-highlighting` sourced last per its documentation, with a cached
`compinit`. Sets zsh as the default shell (`sudo chsh`). With
`--with-zsh-completions`, also clones `zsh-users/zsh-completions` and adds its
`src` directory to `fpath` before compinit. Skips everything if the marker block
already exists. Prints measured interactive startup time (`time zsh -i -c exit`);
soft target: under 150 ms. The change applies to newly opened sessions.

### FR-10 - Cleanup Conflicting Providers
Debian: removes conflicting packages per the official Docker docs (docker.io,
docker-compose, docker-compose-v2, docker-doc, podman-docker, containerd, runc),
skipping packages that are not installed. Fedora: removes only the
`podman-docker` shim (it shadows `/usr/bin/docker`); podman itself is left
untouched with a warning (it coexists with Docker CE).

### FR-11 - Install Docker
If installed: prints version and continues. Otherwise: adds Docker's official
repository for the detected distro — deb822 apt source keyed by VERSION_CODENAME
on Debian; docker-ce.repo via dnf config-manager on Fedora — then installs
docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin,
docker-compose-plugin, adds the user to the docker group, and enables and
starts the docker service.

### FR-12 - Docker Verification
`docker run hello-world` succeeds without sudo (group applied within the
session via `sg docker`).

### FR-13 - DDEV
If installed: prints version and continues. Otherwise: installs via the
official install script. Verifies `ddev -v` prints a version.

### FR-14 - mkcert
If installed: prints version and continues. Otherwise: installs the distro's
NSS tools (libnss3-tools on Debian, nss-tools on Fedora) and the mkcert binary
(architecture from `uname -m`, mapped to the release naming amd64/arm64).
Runs `mkcert -install`.

### FR-15 - Import CA to Windows (default on; skip with `--skip-ca-import`)
Exports the mkcert root CA and imports it into the Windows current-user
Trusted Root store via certutil.exe through WSL interop, and into the Firefox
NSS store. Skips silently if the CA is already trusted.

### FR-16 - Portainer
If the container exists: starts it if stopped, otherwise reports running.
Otherwise: creates the volume and container per wslddev.md.

### FR-17 - Verbose Execution
Each task prints a header, what it does, and the changes it made; the script
pauses 5 seconds between tasks (configurable via `--pause`).

### FR-18 - Final Status Report
The script ends with a status block: docker daemon active state, `ddev -v`
("active" means the version prints and the docker daemon is reachable — ddev
has no daemon of its own), Portainer container state plus
`https://localhost:9443` responding (`curl -k`), and `docker ps -a` listing
all containers. Each status item is marked PASS/FAIL; the script exits
non-zero if any item fails.

## 7. Acceptance Criteria

- From bare Windows (no WSL feature): wsl-setup.ps1 installs the feature, prints
  restart feedback, and rerunning after restart reaches Branch 3.
- From Branch 3: the user picks a distro from the **filtered** online list
  (Debian/Fedora only); after first launch, rerunning chains into Linux
  provisioning without further prompts.
- With more than one distro registered, Branch 1 aborts with the full list and
  `wsl --unregister` instructions (single-distro rule).
- From Branch 1: `.wslconfig` exists with exactly the documented values, and
  `wslinfo --networking-mode` reports `mirrored` (on WSL versions supporting
  it); byte-equality with the template is the fallback check.
- The Linux run prints the inventory first; already-installed components are
  reported with versions and skipped, not reinstalled.
- On Fedora, provisioning uses dnf with the Fedora package names and the
  docker-ce.repo; on Debian it uses apt with the deb822 source keyed by the
  detected codename. Neither hardcodes the other's identifiers.
- After provisioning: curl, git, node, npm, bun, zsh, docker, ddev, mkcert all
  report versions; hello-world ran without sudo; Portainer is running; the
  mkcert root CA is trusted in the Windows current-user store and Firefox NSS.
- A newly opened WSL session starts in zsh with autosuggestions working and
  syntax highlighting active; the managed `.zshrc` block is the only change to
  the file; measured startup time is printed and under the 150 ms soft target.
- `zsh-completions` is installed only when `--with-zsh-completions` is passed.
- The final block lists all containers via `docker ps -a`, each status item
  PASS/FAIL, and the script exits non-zero on any FAIL.
- Running either script again produces no errors and no duplicated state
  (including the Portainer container name and the `.zshrc` marker block).
- `--upgrade` triggers a full package upgrade; without it, only the index
  refresh runs.

## 8. Risk Management

| Risk | Impact | Mitigation |
|---------------------|--------|--------------------------------------|
| Windows/WSL version too old for Mirrored/systemd | High | FR-04 warning + FAIL in final report |
| `memory=10GB` exceeds physical RAM | Medium | Preflight warning (non-blocking) |
| Docker Desktop installed on Windows | High | Preflight detection + warning per Docker docs |
| First distro launch is interactive (UNIX user creation) | Medium | Script exits with instructions; rerun resumes (Branch 1) |
| Unsupported distro chosen or installed | Medium | Abort on unknown; supported: Debian >= 12, Fedora >= 42; Branch 3 list filtered |
| More than one distro registered | Medium | Single-distro rule: abort with list + `wsl --unregister` instructions |
| Fedora short lifecycle (~13 months) | Medium | Yearly distro upgrade is the user's declared obligation; preflight prints detected distro/version |
| `podman-docker` shim shadows `/usr/bin/docker` (Fedora) | Low | Shim removed; podman itself left untouched with warning |
| `curl \| bash` / git-clone supply-chain trust (ddev installer, NodeSource, bun, zsh plugins) | Medium | Official GitHub orgs and domains only; declared deliberate |
| Network/GPG failure mid-install | Medium | Fail fast; idempotent rerun |
| User not in docker group | High | usermod during install; `sg docker` for in-session verification |
| Shell startup slowdown from plugins/frameworks | Medium | No-framework policy; syntax-highlighting sourced last; startup time measured against soft target |
| Long runtime from pauses/logging | Low | `--pause` configurable |
