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

A one-shot automation that:
- applies the exact Windows-side configuration from wslddev.md (`.wslconfig`),
- fully provisions the Linux side inside WSL2 (Docker CE, DDEV, mkcert, Portainer),
- prints what it changes at every step, and
- ends with a clear status report instead of creating any project.

### Target Users

- The repository owner, on this machine and on future fresh machines.
- Anyone following wslddev.md as the setup reference.

### Scope

In Scope:
- Windows: preflight info, `.wslconfig` generation and application
- Linux: `/etc/wsl.conf`, package cleanup per Docker docs, Docker CE, DDEV,
  mkcert (+ CA import to Windows), Portainer
- Per-task verbose logging with a 5-second pause
- Final status report (docker, ddev, Portainer, containers)

Out of Scope:
- Installing or enabling WSL2 on Windows (done manually, per user decision)
- Project migration with rsync
- Creating any project (no Laravel smoke test)
- Rollback/uninstall path
- Passwordless sudo

## 2. Use Cases

### UC-01 - Apply Windows Configuration
User runs the PowerShell script once. It prints preflight info (Windows build,
WSL version, distro list), writes `.wslconfig` exactly as documented, and stops
WSL so the new config applies on next start.

### UC-02 - Provision Linux
User opens the WSL distro and runs the bash script once. After a single sudo
password prompt it runs unattended: every task prints what it changes, followed
by a 5-second pause. If `wsl.conf` requires a WSL restart, the script exits with
instructions and continues on rerun.

### UC-03 - Read the Status Report
User reads the final output block: whether docker, ddev, and Portainer are
active, and a list of all existing containers.

## 3. Product Rules

- `.wslconfig` content matches wslddev.md exactly: processors=6, memory=10GB,
  swap=4GB, nestedVirtualization=true, networkingMode=Mirrored, autoProxy=false,
  sparseVhd=true.
- The Docker apt repository is chosen from the detected distro (`/etc/os-release`),
  never hardcoded.
- Every task prints what it is about to change before changing it; a 5-second
  pause follows each task.
- Scripts are idempotent: safe to run again at any point without duplication or
  corruption.
- Unattended after the single sudo prompt.
- Fail fast: the first failed step aborts the script with a clear message.
- No project is created; the run ends at the status report.
- An existing `.wslconfig` or `/etc/wsl.conf` is backed up before being overwritten.
- If Docker Desktop is detected on Windows, the user is warned before proceeding
  (Docker docs require removing it before Docker CE).

## 4. Requirements

### FR-01 - Windows Preflight
The PowerShell script prints the Windows build, `wsl --version`, and `wsl -l -v`,
and warns when the build/WSL version does not support Mirrored networking or
systemd, or when physical RAM is below the documented `memory=10GB`.

### FR-02 - Write .wslconfig
The PowerShell script writes `%UserProfile%\.wslconfig` with the exact documented
content, shows the written file, and runs `wsl --shutdown` so it applies on next
start.

### FR-03 - Linux Preflight and wsl.conf
The bash script verifies the distro is supported (Debian/Ubuntu), writes
`/etc/wsl.conf` per wslddev.md, and applies it. If systemd is not yet active,
the script writes the config, prints restart instructions (`wsl --shutdown` from
PowerShell), and exits; on rerun it continues.

### FR-04 - Cleanup Conflicting Packages
Before Docker installation, conflicting packages are removed per the official
Docker docs (docker.io, docker-compose, docker-compose-v2, docker-doc,
podman-docker, containerd, runc, and related), skipping packages that are not
installed.

### FR-05 - Install Docker
The script adds Docker's official apt repository for the detected distro,
installs docker-ce, docker-ce-cli, containerd.io, docker-buildx-plugin,
docker-compose-plugin, adds the user to the docker group, and enables and
starts the docker service.

### FR-06 - Verify Docker
`docker run hello-world` succeeds without sudo.

### FR-07 - Install DDEV
DDEV is installed via the official install script; `ddev -v` prints a version.

### FR-08 - Install mkcert
The mkcert binary and libnss3-tools are installed; `mkcert -install` succeeds.

### FR-09 - Import CA to Windows (default: on)
The mkcert root CA is exported from WSL and imported into the Windows Trusted
Root store so browsers on Windows show no TLS warning. This step is skippable
via script flag.

### FR-10 - Install Portainer
The Portainer volume and container are created per wslddev.md and the container
is verified running.

### FR-11 - Verbose Execution
Each task prints a header, what it does, and the changes it made; the script
pauses 5 seconds between tasks.

### FR-12 - Final Status Report
The script ends with a status block: docker daemon active state, `ddev -v`,
Portainer container state, and `docker ps -a` listing all containers, each
status item marked PASS/FAIL.

## 5. Acceptance Criteria

- `.wslconfig` exists with exactly the documented values and is in effect after
  WSL restarts.
- `/etc/wsl.conf` matches the documented content; systemd is active after the
  applied restart.
- The terminal log shows every change and a 5-second pause between tasks.
- `docker run hello-world` succeeds without sudo.
- `ddev -v` prints a version.
- Portainer container is running; `https://localhost:9443` responds.
- Final output lists all containers via `docker ps -a` with PASS/FAIL per status
  item.
- Running either script again produces no errors and no duplicated state.
- With Docker Desktop present, the warning appears before any installation step.
- When CA import is enabled, the mkcert root CA is present in the Windows
  Trusted Root store.

## 6. Risk Management

| Risk | Impact | Mitigation |
|---------------------|--------|--------------------------------------|
| Windows/WSL version too old for Mirrored/systemd | High | Preflight check with explicit warning |
| `memory=10GB` exceeds physical RAM | Medium | Preflight warning (non-blocking) |
| Docker Desktop installed on Windows | High | Preflight detection + warning per Docker docs |
| Unsupported distro or codename | Medium | Distro auto-detection, abort on unknown |
| Network/GPG failure mid-install | Medium | Fail fast; idempotent rerun |
| User not in docker group | High | usermod during install + group verification |
| Long runtime from pauses/logging | Low | Pause duration configurable |
