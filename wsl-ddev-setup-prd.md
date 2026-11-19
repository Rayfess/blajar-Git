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
- Windows: enable the WSL feature, install Debian directly (no distro picker),
  apply the exact documented `.wslconfig`, and chain into Linux provisioning
- Linux: provision everything inside WSL2 (dev tools, zsh shell, Docker CE, DDEV,
  mkcert, Portainer), printing what it changes at every step
- both automations check what already exists before installing anything, and end
  with a clear status report instead of creating any project.

### Target Users

- The repository owner, on this machine and on future fresh machines.
- Anyone following wslddev.md as the setup reference.

### Scope

In Scope:
- Windows: WSL feature enablement, Debian installation via decision tree,
  `.wslconfig` generation, printed handoff guide into the Linux phase
- Linux: `/etc/wsl.conf`, package index refresh (+ optional upgrade), development
  tools, zsh with essential plugins, Docker CE, DDEV, mkcert (+ CA import to
  Windows), Portainer
- Skip-if-installed behavior with version status output
- Per-task verbose logging with a 5-second pause
- Final status report (docker, ddev, Portainer, containers)

Out of Scope:
- Fedora, Ubuntu, and all distros other than Debian >= 12 (declared deliberately)
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
- Interactive where the OS requires it: elevation prompt, native first-launch
  user creation (in the Debian terminal)

### provision-wsl.sh (Linux / WSL)
- Executable: bash inside the WSL distro
- Invoked from inside Debian, after the user copies it from the automounted
  repo path into the Linux filesystem (containment: the script runs from the
  Linux filesystem, not from the Windows mount):
  `cp /mnt/<repo-path>/provision-wsl.sh ~/ && bash ~/provision-wsl.sh`
- The exact copy/run commands are printed by wsl-setup.ps1 at handoff
- Unattended after the single sudo password prompt
- Flags: `--no-upgrade` (skip the default full base upgrade), `--skip-ca-import`,
  `--log <file>` (full transcript for forensics), `--pause <seconds>` (default 5)

## 3. Use Cases

### UC-01 - Run Windows Setup
User runs wsl-setup.ps1 elevated. The script follows the distro decision tree
(FR-02) and either: continues into Linux provisioning, installs the WSL feature
and asks for a restart, or installs Debian directly and hands off to first
launch.

### UC-02 - Provision Linux
Runs chained from UC-01 or manually. After one sudo prompt it is unattended:
prints an inventory of what is already installed, then installs only what is
missing (apt, Debian).

### UC-03 - Read the Status Report
User reads the final output block: whether docker, ddev, and Portainer are
active, and a list of all existing containers.

## 4. Product Rules

- `.wslconfig` content matches wslddev.md as deliberately adjusted by the owner:
  processors=6, memory=10GB, swap=1GB (storage-saving adjustment of the
  doc-exact swap=4GB), nestedVirtualization=true, networkingMode=Mirrored,
  autoProxy=false, sparseVhd=true.
- Supported distro, declared deliberately: **Debian >= 12** only (long support,
  server-like role). Fedora, Ubuntu, and everything else is out of scope.
- **Single-distro rule**: exactly one WSL distro may be installed on the machine.
  wsl-setup.ps1 refuses to provision with more than one and lists them with
  removal instructions (`wsl --unregister <name>`).
- The Linux script never trusts the Windows side for distro facts: it detects the
  running distro from `/etc/os-release` and aborts on anything but Debian. The
  Docker repository is the official deb822 apt source keyed by the detected
  VERSION_CODENAME, never hardcoded.
- Package manager: apt (Debian-only). mkcert release naming maps from `uname -m`
  (x86_64 -> amd64, aarch64 -> arm64).
- Every task prints a header, what it does, and the changes it made; a 5-second
  pause follows each task.
- Idempotent and skip-if-installed: existing components are reported with their
  version, never reinstalled.
- An existing `.wslconfig`, `/etc/wsl.conf`, or `~/.zshrc` is backed up only when
  its content differs and the file was not generated by this automation (marker
  comment). Script-managed `.zshrc` changes are appended as a marker-delimited
  block and never clobber user content.
- Shell setup policy, declared deliberately: no framework (Oh My Zsh is rejected
  for its startup cost). Plugins are git-cloned `--depth=1` at pinned upstream
  release tags (supply-chain control; fallback to latest if the tag is missing)
  and sourced directly; `zsh-syntax-highlighting` is sourced last, as its
  documentation requires. `zsh-completions` is included by default via
  fpath-before-compinit (near-zero startup cost; the project's documented
  cost applies to the oh-my-zsh plugin mechanism, which we do not use).
- The Linux script is unattended after one sudo prompt (sudo timestamp kept
  alive); the Windows script is interactive only where the OS requires it
  (elevation, native first-launch user creation).
- Fail fast on the Linux side: the first failed step aborts with a clear message.
  Windows-side gates (restart, first launch) exit with resume instructions
  instead; every gate is resumable by rerunning wsl-setup.ps1.
- No project is created; the run ends at the status report.
- Version policy, declared deliberately: DDEV, Docker CE, and the Portainer
  image track latest stable; the mkcert binary, the nvm release, and the zsh
  plugin tags are pinned (supply-chain control); Node.js itself tracks the
  current LTS via `nvm install --lts`. Remote installer scripts are downloaded
  to a file first (inspectable) instead of piped straight into a shell.
- Credentials policy (native/documented flow, per
  learn.microsoft.com/windows/wsl): the UNIX user and password are created by
  the user during the distro's own first launch — typed natively in Debian,
  never through PowerShell, never hardcoded in this repository. The root
  account stays password-locked: WSL's `-u root` ignores Linux passwords, so
  a root password would provide no protection while a public default would be
  a known credential.
- PowerShell 5.1 native-stderr quirk (learned from the first real run):
  every wsl.exe call merges stderr into stdout via `cmd /c ... 2>&1` and runs
  with ErrorActionPreference 'Continue', so native warnings (e.g. the
  experimental Sparse VHD notice) can never terminate the run.
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
  validates the distro is Debian (aborts otherwise), writes `.wslconfig`
  (FR-03), then ends with a printed guide for the manual handoff — the
  Windows phase stops here (containment). The guide covers: the native
  first launch (when the distro still defaults to root, its own setup asks
  for the UNIX username and password — the documented flow per
  learn.microsoft.com/windows/wsl), copying the provisioner from the
  automounted repo path into the Linux filesystem, running it from `~`, and
  optional cleanup. Credentials are typed natively in Debian and never pass
  through PowerShell. Rerunning wsl-setup.ps1 after provisioning is harmless
  (idempotent guidance).
- Branch 2 - distro absent, WSL feature absent: run `wsl --install -d Debian`
  (Debian-only applies to every branch), print restart feedback, exit. The
  restart is for the Windows feature activation only (first-time); the Debian
  distro itself never requires one. Distro download: retry with backoff, then
  `--web-download` fallback — bypasses the Store CDN when
  `WININET_E_CONNECTION_RESET` hits (documented fix per
  learn.microsoft.com/windows/wsl/install). Rerunning after restart lands in
  Branch 1, whose guide covers the native first launch.
- Branch 3 - distro absent, WSL feature present: install Debian directly
  (`wsl --install -d Debian`, no distro picker) with the same download
  retry + `--web-download` fallback, then exit. Rerunning lands
  in Branch 1, whose guide covers the native first launch.

### FR-03 - Write .wslconfig
Writes `%UserProfile%\.wslconfig` with the exact documented content, shows the
written file, warns that `wsl --shutdown` stops all running WSL sessions, and
runs `wsl --shutdown` so it applies on next start.

### FR-04 - Capability Warning
If the Windows build or WSL version does not support Mirrored networking or
systemd, warns loudly and records a FAIL for the final report (forwarded via
WSLENV, appended - never overwriting an existing WSLENV); still writes the
documented config.

## 6. Requirements — Linux (provision-wsl.sh)

### FR-05 - Inventory and Preflight
Aborts when run as root (tool installs and group changes must target the real
user). Detects distro, version, and codename from `/etc/os-release`; aborts on
anything but Debian >= 12; a missing VERSION_CODENAME aborts (it is required
for the Docker apt source). Checks systemd state; prints an inventory of what
is already installed with versions: docker, ddev, mkcert, portainer container,
git, node/npm, bun, zsh, curl. Nothing is reinstalled if present.

### FR-06 - wsl.conf
Writes `/etc/wsl.conf` per wslddev.md (backup rule as in Product Rules). If
systemd is not yet active, exits with restart instructions (`wsl --shutdown`
from PowerShell); on rerun it continues.

### FR-07 - Package Index
Refreshes the package index every run (`apt-get update`). A full base upgrade
(`apt-get upgrade`) runs by default; `--no-upgrade` skips it (speed-first
rerun).

### FR-08 - Development Tools
Installs only items missing from the tool list defined at the top of the script.
Default list: curl, git, zsh, unzip (required by bun's installer), xz-utils
(required by nvm's node tarballs), build-essential, Node.js LTS with npm via
nvm (installer downloaded to file; `nvm install --lts`), bun (via its official
installer). Prints versions after installation.

### FR-09 - Shell Setup (zsh)
Clones `zsh-users/zsh-autosuggestions` and `zsh-users/zsh-syntax-highlighting`
(`git clone --depth=1` at pinned upstream release tags) into `~/.zsh/plugins/`
(skip if present), and appends a marker-delimited block to `~/.zshrc` that
sources them directly — `zsh-syntax-highlighting` sourced last per its
documentation, with a cached `compinit` (its skipped security audit is a
documented tradeoff) — plus nvm sourcing so zsh sessions get the Node
installed in FR-08. Sets zsh as the default shell (`sudo chsh`). Clones
`zsh-users/zsh-completions` by default (pinned `0.34.0`), adding its `src`
directory to `fpath` before compinit, and enables AUTO_CD. Skips everything
if the marker
block already exists. Prints measured interactive startup time
(`time zsh -i -c exit`); soft target: under 150 ms. The change applies to
newly opened sessions.

### FR-10 - Cleanup Conflicting Packages
Removes conflicting packages per the official Docker docs (docker.io,
docker-compose, docker-compose-v2, docker-doc, podman-docker, containerd, runc),
running the docs loop unconditionally: absent packages are tolerated by apt
("not installed, so not removed"), so the sanitizer always executes.

### FR-11 - Install Docker
If installed: prints version and continues. Otherwise: adds Docker's official
deb822 apt repository keyed by the detected VERSION_CODENAME, then installs
docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin,
docker-compose-plugin, adds the user to the docker group, and enables and
starts the docker service.

### FR-12 - Docker Verification
`docker run hello-world` succeeds without sudo (group applied within the
session via `sg docker`).

### FR-13 - DDEV
If installed: prints version and continues. Otherwise: downloads the official
installer to a file (inspectable), runs it. Verifies `ddev -v` prints a version.

### FR-14 - mkcert
If installed: prints version and continues. Otherwise: installs libnss3-tools
and the pinned mkcert binary (version pinned in the script; architecture from
`uname -m`, mapped to the release naming amd64/arm64). Runs `mkcert -install`.

### FR-15 - Import CA to Windows (default on; skip with `--skip-ca-import`)
Exports the mkcert root CA and imports it into the Windows current-user
Trusted Root store via certutil.exe through WSL interop, and into the Firefox
NSS store. Skips if already trusted; exits the step cleanly when the Windows
username cannot be resolved; removes the staged CA copy from Windows Temp on
success.

### FR-16 - Portainer
If the container exists: starts it if stopped, otherwise reports running, and
recreates it automatically when it lacks the mkcert TLS cert or is bound to
`0.0.0.0` (LAN-exposed).
Otherwise: creates the volume and container per wslddev.md, bound to loopback
only (`127.0.0.1:9443`) so it is not reachable from the local network, and
serves a mkcert-signed cert for `localhost 127.0.0.1` (generated in this
stage — scoped to Portainer's listener; mkcert itself is the project-wide
TLS authority used by DDEV, see the readme) so the Windows browser shows no
warning. `http://127.0.0.1:9000` remains available as an unencrypted
fallback. Certs live in a persistent dir (`~/.local/share/portainer-tls`) —
never `/tmp`, which Debian tmpfiles wipes on every VM boot.

### FR-17 - Verbose Execution
Each task prints a header, what it does, and the changes it made; the script
pauses 5 seconds between tasks (configurable via `--pause`).

### FR-18 - Final Status Report
The script ends with a status block: docker daemon active state, `ddev -v`
("active" means the version prints and the docker daemon is reachable — ddev
has no daemon of its own), Portainer container state plus
`https://127.0.0.1:9443` responding (`curl -k`), and `docker ps -a` listing
all containers. Each status item is marked PASS/FAIL; the script exits
non-zero if any item fails.
After the report, the script restarts WSL (`wsl.exe --shutdown` via interop)
so all applied configuration takes effect — the terminal closes by design.
After the report, the script restarts WSL (`wsl.exe --shutdown` via interop)
so all applied configuration takes effect — the terminal closes by design.

## 7. Acceptance Criteria

- From bare Windows (no WSL feature): wsl-setup.ps1 installs the feature, prints
  restart feedback, and rerunning after restart reaches Branch 3.
- From Branch 3: Debian is installed directly (no picker); the first launch
  (native setup — create your UNIX user) and the provisioning run are
  completed manually in the Debian terminal, guided by the printed commands.
- With more than one distro registered, Branch 1 aborts with the full list and
  `wsl --unregister` instructions (single-distro rule). With a non-Debian distro
  installed, Branch 1 aborts with a Debian-only message.
- From Branch 1: `.wslconfig` exists with exactly the documented values, and
  `wslinfo --networking-mode` reports `mirrored` (on WSL versions supporting
  it); byte-equality with the template is the fallback check.
- The Linux run prints the inventory first; already-installed components are
  reported with versions and skipped, not reinstalled.
- Provisioning uses apt with the deb822 source keyed by the detected codename;
  a non-Debian distro aborts at FR-05 with a clear message.
- Remote installers (DDEV, bun, nvm) are downloaded to a file before
  execution; the mkcert binary and zsh plugin tags are pinned.
- After provisioning: curl, git, node, npm, bun, zsh, docker, ddev, mkcert all
  report versions; hello-world ran without sudo; Portainer is running and
  reachable only on loopback; the mkcert root CA is trusted in the Windows
  current-user store and Firefox NSS.
- A newly opened WSL session starts in zsh with autosuggestions working and
  syntax highlighting active; the managed `.zshrc` block is the only change to
  the file; measured startup time is printed and under the 150 ms soft target.
- `zsh-completions` is installed by default (pinned tag `0.34.0`), with its
  `src` directory on `fpath` before compinit.
- The final block lists all containers via `docker ps -a`, each status item
  PASS/FAIL, and the script exits non-zero on any FAIL.
- Running either script again produces no errors and no duplicated state
  (including the Portainer container name and the `.zshrc` marker block).
- A full base upgrade runs by default; `--no-upgrade` skips it (speed-first
  rerun).

## 8. Risk Management

| Risk | Impact | Mitigation |
|---------------------|--------|--------------------------------------|
| Windows/WSL version too old for Mirrored/systemd | High | FR-04 warning + FAIL in final report |
| `memory=10GB` exceeds physical RAM | Medium | Preflight warning (non-blocking) |
| Docker Desktop installed on Windows | High | Preflight detection + warning per Docker docs |
| First launch must be completed manually (native OOBE) | Low | Documented distro setup flow; the gate exits with step-by-step instructions and rerun resumes |
| Non-Debian distro chosen or installed | Medium | Abort on unknown; Debian >= 12 only; Branch 3 installs Debian directly; Branch 1 validates Debian |
| More than one distro registered | Medium | Single-distro rule: abort with list + `wsl --unregister` instructions |
| `curl \| bash` supply-chain trust | Medium | Remote installers downloaded to file first; mkcert binary and zsh plugin tags pinned; official domains only |
| Network/GPG failure mid-install | Medium | Fail fast; idempotent rerun |
| Running as root | Medium | EUID guard aborts before any install (installs must land in the real user's home) |
| User not in docker group | High | usermod during install; `sg docker` for in-session verification |
| Shell startup slowdown from plugins/frameworks | Medium | No-framework policy; pinned plugin tags; syntax-highlighting sourced last; startup time measured against soft target |
| Long runtime from pauses/logging | Low | `--pause` configurable |
