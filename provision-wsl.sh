#!/usr/bin/env bash
# provision-wsl.sh - Linux side of the WSL2 + DDEV setup automation.
# Implements FR-05..FR-18 of wsl-ddev-setup-prd.md (repository root).
#
# Supported distros (PRD): Debian >= 12, Fedora >= 42. The script detects the
# running distro from /etc/os-release and adapts (apt on Debian, dnf on Fedora).
#
# Run inside WSL (or chained by wsl-setup.ps1):
#     bash provision-wsl.sh [--upgrade] [--skip-ca-import]
#                           [--with-zsh-completions] [--pause N]
#
# Unattended after ONE sudo password prompt (timestamp kept alive).
# Fail fast on the first failed step (set -euo pipefail).
set -euo pipefail

# USER may be unset in minimal/non-login invocation contexts (e.g. wsl -e bash);
# resolve it once so set -u cannot abort later tasks (FR-09/FR-11).
USER="${USER:-$(id -un)}"

# ---------------------------------------------------------------- flags ----
UPGRADE=0
SKIP_CA=0
WITH_COMPLETIONS=0
PAUSE=5
while [[ $# -gt 0 ]]; do
    case "$1" in
        --upgrade)              UPGRADE=1 ;;
        --skip-ca-import)       SKIP_CA=1 ;;
        --with-zsh-completions) WITH_COMPLETIONS=1 ;;
        --pause)                PAUSE="${2:?--pause needs a value}"; shift ;;
        *) echo "[ABORT] Unknown flag: $1" >&2; exit 2 ;;
    esac
    shift
done

# ------------------------------------------------- presentation (FR-17) ----
TOTAL=13
CURRENT=0
task_start() { # $1 FR id, $2 title, $3 description
    CURRENT=$((CURRENT + 1))
    echo ""
    echo "=================================================================="
    echo "[$CURRENT/$TOTAL] $1 - $2"
    echo "------------------------------------------------------------------"
    echo "$3"
}
task_end() { echo "--- done ---"; sleep "$PAUSE"; }

ok()   { echo "  [OK]   $*"; }
chg()  { echo "  [CHG]  $*"; }
skip() { echo "  [SKIP] $*"; }
warn() { echo "  [WARN] $*"; }

# --------------------------------- sudo keepalive (one prompt, kept alive) -
SUDO_KEEPALIVE_PID=""
cleanup() { [[ -n "${SUDO_KEEPALIVE_PID}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true; }
trap cleanup EXIT
sudo -v
keep_sudo_alive() { while true; do sudo -n true 2>/dev/null || return; sleep 55; done; }
keep_sudo_alive &
SUDO_KEEPALIVE_PID=$!

# ---------------------- package-manager abstraction (PRD, declared) --------
# Set after FR-05 detects ID_LC: apt on Debian, dnf on Fedora.
pm_update() {
    if [[ "$ID_LC" == "fedora" ]]; then
        sudo dnf -q makecache
    else
        sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq
    fi
}
pm_upgrade() {
    if [[ "$ID_LC" == "fedora" ]]; then
        sudo dnf -q -y upgrade
    else
        sudo env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
    fi
}
pm_installed() {
    if [[ "$ID_LC" == "fedora" ]]; then
        rpm -q "$1" >/dev/null 2>&1
    else
        dpkg -s "$1" >/dev/null 2>&1
    fi
}
pm_install() {
    if [[ "$ID_LC" == "fedora" ]]; then
        sudo dnf -q -y install "$@"
    else
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
    fi
}
pm_remove() {
    if [[ "$ID_LC" == "fedora" ]]; then
        sudo dnf -q -y remove "$@"
    else
        sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq "$@"
    fi
}

# ============================================================ FR-05 ========
task_start "FR-05" "Inventory & preflight" \
    "Detect distro/systemd; report what is already installed. Nothing is reinstalled."

if [[ ! -r /etc/os-release ]]; then
    echo "[ABORT] /etc/os-release not readable - unsupported distro" >&2
    exit 1
fi
. /etc/os-release
ID_LC="${ID,,}"
if [[ -z "${VERSION_ID:-}" ]]; then
    echo "[ABORT] VERSION_ID missing in /etc/os-release (testing/sid?) - unsupported" >&2
    exit 1
fi
case "$ID_LC" in
    debian)
        [[ "${VERSION_ID%%.*}" -ge 12 ]] || { echo "[ABORT] Debian >= 12 required, found $VERSION_ID" >&2; exit 1; }
        if [[ -z "${VERSION_CODENAME:-}" ]]; then
            echo "[ABORT] VERSION_CODENAME missing - required on Debian for the Docker apt source" >&2
            exit 1
        fi
        ;;
    fedora)
        [[ "${VERSION_ID%%.*}" -ge 42 ]] || { echo "[ABORT] Fedora >= 42 required, found $VERSION_ID" >&2; exit 1; }
        ;;
    *)
        echo "[ABORT] Unsupported distro: $ID (supported: Debian >= 12, Fedora >= 42)" >&2
        exit 1
        ;;
esac
ok "Distro: $PRETTY_NAME"
if [[ -n "${VERSION_CODENAME:-}" ]]; then ok "Codename: $VERSION_CODENAME"; fi

SYSTEMD_ACTIVE=0
if [[ "$(ps -p 1 -o comm=)" == "systemd" ]]; then
    SYSTEMD_ACTIVE=1
fi
if [[ "$SYSTEMD_ACTIVE" == "1" ]]; then ok "systemd: active"; else warn "systemd: NOT active (FR-06 will gate)"; fi

inv() { # label, binary, [version args...]
    local label="$1" binname="$2"; shift 2
    if c="$(command -v "$binname" 2>/dev/null)"; then
        local v
        v=$("$binname" "${@:---version}" 2>/dev/null | head -n1 || true)
        ok "$label: $c ${v:+[$v]}"
    else
        skip "$label: not installed"
    fi
}
inv docker docker --version
inv ddev   ddev -v
inv git    git --version
inv node   node --version
inv npm    npm --version
inv bun    bun --version
inv zsh    zsh --version
inv curl   curl --version
if command -v mkcert >/dev/null 2>&1; then ok "mkcert: $(command -v mkcert)"; else skip "mkcert: not installed"; fi
if command -v docker >/dev/null 2>&1; then
    PT=$(sudo docker ps -a --filter name=portainer --format '{{.State}}' 2>/dev/null || true)
    if [[ -n "$PT" ]]; then ok "portainer container: $PT"; else skip "portainer container: not present"; fi
fi
task_end

# ============================================================ FR-06 ========
task_start "FR-06" "/etc/wsl.conf" \
    "Write the documented wsl.conf (systemd, interop appendWindowsPath=false, automount metadata)."
WCONF="/etc/wsl.conf"
WCONF_CONTENT='[boot]
systemd=true

[interop]
enabled=true
appendWindowsPath=false

[network]
generateHosts=true
generateResolvConf=true

[automount]
enabled=true
options="metadata,umask=22"'
NEEDS_WRITE=1
if sudo test -f "$WCONF"; then
    if sudo grep -q 'managed by provision-wsl.sh' "$WCONF"; then
        ok "/etc/wsl.conf already managed by this script"
        NEEDS_WRITE=0
    elif sudo diff -q "$WCONF" <(printf '%s\n' "$WCONF_CONTENT") >/dev/null 2>&1; then
        ok "/etc/wsl.conf already matches the documented content"
        NEEDS_WRITE=0
    else
        sudo cp "$WCONF" "$WCONF.bak-$(date +%Y%m%d-%H%M%S)"
        chg "backed up existing /etc/wsl.conf"
    fi
fi
if [[ "$NEEDS_WRITE" == "1" ]]; then
    {
        printf '# managed by provision-wsl.sh (wslddev.md doc-exact)\n'
        printf '%s\n' "$WCONF_CONTENT"
    } | sudo tee "$WCONF" >/dev/null
    chg "wrote /etc/wsl.conf"
fi
if [[ "$SYSTEMD_ACTIVE" != "1" ]]; then
    echo ""
    echo "[RESTART REQUIRED] systemd is not active yet."
    echo "  1. From PowerShell run:  wsl --shutdown"
    echo "  2. Close this WSL window, then reopen WSL."
    echo "  3. Run this script again - provisioning continues."
    exit 0
fi
ok "systemd active - config in effect"
task_end

# ============================================================ FR-07 ========
task_start "FR-07" "Package index" \
    "Index refresh every run (apt-get update / dnf makecache); full upgrade only with --upgrade."
pm_update
ok "package index refreshed ($ID_LC)"
if [[ "$UPGRADE" == "1" ]]; then
    pm_upgrade
    ok "full package upgrade complete"
else
    skip "full upgrade (pass --upgrade to enable)"
fi
task_end

# ============================================================ FR-08 ========
task_start "FR-08" "Development tools" \
    "Install only what is missing: curl, git, zsh, C toolchain, Node.js LTS + npm (NodeSource), bun (official installer). Names mapped per distro (PRD)."
BASE_PKGS=(curl git zsh ca-certificates)
if [[ "$ID_LC" == "fedora" ]]; then
    BASE_PKGS+=(gcc gcc-c++ make)   # build-essential equivalent (PRD mapping)
else
    BASE_PKGS+=(build-essential)
fi
MISSING_PKGS=()
for p in "${BASE_PKGS[@]}"; do
    if ! pm_installed "$p"; then MISSING_PKGS+=("$p"); fi
done
if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    pm_install "${MISSING_PKGS[@]}"
    chg "installed: ${MISSING_PKGS[*]}"
else
    skip "base packages all present"
fi
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    skip "node/npm already present ($(node --version))"
else
    if [[ "$ID_LC" == "fedora" ]]; then
        curl -fsSL https://rpm.nodesource.com/setup_22.x | sudo bash -
    else
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    fi
    pm_install nodejs
    chg "Node.js LTS installed: $(node --version) (npm $(npm --version))"
fi
if [[ -x "$HOME/.bun/bin/bun" ]] || command -v bun >/dev/null 2>&1; then
    skip "bun already present"
else
    curl -fsSL https://bun.sh/install | bash
    chg "bun installed: $("$HOME/.bun/bin/bun" --version)"
fi
task_end

# ============================================================ FR-09 ========
task_start "FR-09" "Shell setup (zsh)" \
    "No framework by policy. Clone autosuggestions + syntax-highlighting, managed block in ~/.zshrc (syntax-highlighting sourced last per its docs)."
ZPLUG="$HOME/.zsh/plugins"
mkdir -p "$ZPLUG"
clone_plugin() { # url, dir
    local url="$1" dir="$2"
    if [[ -d "$dir/.git" ]]; then
        skip "plugin $(basename "$dir") already cloned"
    else
        git clone --depth=1 -q "$url" "$dir"
        chg "cloned $(basename "$dir")"
    fi
}
clone_plugin https://github.com/zsh-users/zsh-autosuggestions.git "$ZPLUG/zsh-autosuggestions"
clone_plugin https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZPLUG/zsh-syntax-highlighting"
if [[ "$WITH_COMPLETIONS" == "1" ]]; then
    clone_plugin https://github.com/zsh-users/zsh-completions.git "$ZPLUG/zsh-completions"
fi

ZRC="$HOME/.zshrc"
if grep -q '# >>> zcode-managed' "$ZRC" 2>/dev/null; then
    skip ".zshrc already has the managed block"
else
    if [[ -f "$ZRC" ]]; then
        cp "$ZRC" "$ZRC.bak-$(date +%Y%m%d-%H%M%S)"
        chg "backed up existing .zshrc"
    fi
    {
        echo '# >>> zcode-managed (provision-wsl.sh) >>>'
        echo 'export PATH="$HOME/.bun/bin:$PATH"'
        echo 'autoload -Uz compinit'
        if [[ "$WITH_COMPLETIONS" == "1" ]]; then
            echo 'fpath=(~/.zsh/plugins/zsh-completions/src $fpath)'
        fi
        echo 'compinit -C'
        echo '[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh'
        echo '[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
        echo '# <<< zcode-managed <<<'
    } >> "$ZRC"
    chg "appended managed block to ~/.zshrc"
fi

ZSH_PATH="$(command -v zsh)"
if [[ "$(getent passwd "$USER" | cut -d: -f7)" == "$ZSH_PATH" ]]; then
    ok "default shell already zsh"
else
    sudo chsh -s "$ZSH_PATH" "$USER"
    chg "default shell -> zsh (applies to newly opened sessions)"
fi

TIMEFORMAT='%3R'
STARTUP_S=$( { time zsh -i -c exit >/dev/null 2>&1; } 2>&1 || true )
STARTUP_MS=$(awk -v s="$STARTUP_S" 'BEGIN{printf "%d", s*1000}')
ok "interactive zsh startup: ${STARTUP_MS} ms (soft target < 150 ms; first run builds the completion cache)"
task_end

# ============================================================ FR-10 ========
task_start "FR-10" "Cleanup conflicting providers" \
    "Debian: Docker docs conflicting packages. Fedora: only the podman-docker shim (podman itself is left untouched, PRD)."
if [[ "$ID_LC" == "fedora" ]]; then
    if pm_installed podman-docker; then
        pm_remove podman-docker
        chg "removed podman-docker shim (it shadows /usr/bin/docker)"
    else
        skip "podman-docker shim not installed"
    fi
    if rpm -q podman >/dev/null 2>&1; then
        warn "podman is present (Fedora default) - left untouched; Docker CE coexists with it"
    fi
else
    CONFLICTS=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)
    TO_REMOVE=()
    for p in "${CONFLICTS[@]}"; do
        if pm_installed "$p"; then TO_REMOVE+=("$p"); fi
    done
    if [[ ${#TO_REMOVE[@]} -gt 0 ]]; then
        pm_remove "${TO_REMOVE[@]}"
        chg "removed: ${TO_REMOVE[*]}"
    else
        skip "no conflicting packages installed"
    fi
fi
task_end

# ============================================================ FR-11 ========
task_start "FR-11" "Docker CE" \
    "Official distro-matched repository (Debian: deb822 apt source; Fedora: docker-ce.repo via dnf config-manager), docker group, enable + start service."
if command -v docker >/dev/null 2>&1; then
    ok "docker already installed: $(docker --version)"
else
    if [[ "$ID_LC" == "fedora" ]]; then
        REPO_URL="https://download.docker.com/linux/fedora/docker-ce.repo"
        pm_install dnf-plugins-core
        if ! sudo dnf config-manager addrepo --from-repofile="$REPO_URL" 2>/dev/null; then
            sudo dnf config-manager --add-repo="$REPO_URL"   # dnf4 fallback
        fi
        chg "added Docker repo (dnf): $REPO_URL"
        pm_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        chg "installed Docker CE + buildx + compose plugin (dnf)"
    else
        REPO="https://download.docker.com/linux/$ID_LC"
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL "$REPO/gpg" -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc
        sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: $REPO
Suites: $VERSION_CODENAME
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
        chg "added apt source /etc/apt/sources.list.d/docker.sources ($ID_LC / $VERSION_CODENAME)"
        pm_update
        pm_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        chg "installed Docker CE + buildx + compose plugin (apt)"
    fi
fi
if id -nG "$USER" | grep -qw docker; then
    ok "user already in docker group"
else
    sudo usermod -aG docker "$USER"
    chg "user added to docker group (new sessions; this session uses sg docker)"
fi
sudo systemctl enable --now docker >/dev/null 2>&1 || sudo systemctl restart docker >/dev/null
ok "docker service: $(sudo systemctl is-active docker)"
task_end

# ============================================================ FR-12 ========
task_start "FR-12" "Docker verification" \
    "docker run hello-world without sudo (group applied in-session via sg docker)."
run_docker() {
    if id -nG "$USER" | grep -qw docker; then
        docker "$@"
    else
        sg docker -c "$(printf '%q ' docker "$@")"
    fi
}
if sudo docker image inspect hello-world >/dev/null 2>&1; then
    skip "hello-world image already present (verified previously)"
else
    run_docker pull hello-world >/dev/null
    run_docker run hello-world | sed 's/^/    /'
    ok "hello-world ran without sudo"
fi
task_end

# ============================================================ FR-13 ========
task_start "FR-13" "DDEV" \
    "Official install script, latest stable (declared latest policy)."
if command -v ddev >/dev/null 2>&1; then
    ok "ddev already installed: $(ddev -v)"
else
    curl -fsSL https://ddev.com/install.sh | bash
    chg "ddev installed: $(ddev -v)"
fi
task_end

# ============================================================ FR-14 ========
task_start "FR-14" "mkcert" \
    "Local CA for *.ddev.site HTTPS; distro NSS tools (libnss3-tools / nss-tools); mkcert -install."
NSS_PKG="libnss3-tools"
if [[ "$ID_LC" == "fedora" ]]; then NSS_PKG="nss-tools"; fi
if ! pm_installed "$NSS_PKG"; then
    pm_install "$NSS_PKG"
    chg "installed $NSS_PKG"
fi
if command -v mkcert >/dev/null 2>&1; then
    ok "mkcert already installed ($(command -v mkcert))"
else
    case "$(uname -m)" in
        x86_64)  MKCERT_ARCH="amd64" ;;
        aarch64) MKCERT_ARCH="arm64" ;;
        *) echo "[ABORT] Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
    esac
    MKCERT_TAG=$(curl -fsSL https://api.github.com/repos/FiloSottile/mkcert/releases/latest \
        | grep -m1 '"tag_name"' | cut -d'"' -f4)
    sudo curl -fsSL "https://github.com/FiloSottile/mkcert/releases/download/${MKCERT_TAG}/mkcert-${MKCERT_TAG}-linux-${MKCERT_ARCH}" \
        -o /usr/local/bin/mkcert
    sudo chmod +x /usr/local/bin/mkcert
    chg "mkcert $MKCERT_TAG installed to /usr/local/bin/mkcert (arch: $MKCERT_ARCH)"
fi
if [[ ! -f "$(mkcert -CAROOT)/rootCA.pem" ]]; then
    mkcert -install
    chg "mkcert -install (system trust store + NSS)"
else
    ok "mkcert CA already installed ($(mkcert -CAROOT))"
fi
task_end

# ============================================================ FR-15 ========
task_start "FR-15" "Import CA to Windows" \
    "Windows current-user Trusted Root via certutil.exe (WSL interop) so the Windows browser trusts *.ddev.site."
if [[ "$SKIP_CA" == "1" ]]; then
    skip "CA import skipped (--skip-ca-import)"
else
    CERTUTIL="/mnt/c/Windows/System32/certutil.exe"
    if [[ ! -x "$CERTUTIL" ]]; then
        warn "certutil.exe not reachable (interop disabled?) - import manually: $(mkcert -CAROOT)/rootCA.pem"
    else
        WIN_USER=$(/mnt/c/Windows/System32/cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
        DEST="/mnt/c/Users/${WIN_USER}/AppData/Local/Temp/mkcert-rootCA.pem"
        cp "$(mkcert -CAROOT)/rootCA.pem" "$DEST"
        if "$CERTUTIL" -user -store Root 2>/dev/null | grep -qi 'mkcert'; then
            skip "mkcert root CA already trusted in Windows current-user store"
        elif "$CERTUTIL" -user -addstore Root "$(wslpath -w "$DEST")" >/dev/null 2>&1; then
            chg "mkcert root CA imported to Windows (current-user Trusted Root)"
        else
            warn "certutil import failed - import manually from $(mkcert -CAROOT)/rootCA.pem"
        fi
    fi
fi
task_end

# ============================================================ FR-16 ========
task_start "FR-16" "Portainer" \
    "GUI for Docker on https://localhost:9443 (container name: portainer, restart=always)."
if run_docker ps -a --filter name=portainer --format '{{.Names}}' 2>/dev/null | grep -qx portainer; then
    PSTATE=$(run_docker ps -a --filter name=portainer --format '{{.State}}')
    if [[ "$PSTATE" == "running" ]]; then
        ok "portainer container already running"
    else
        run_docker start portainer >/dev/null
        chg "portainer container started"
    fi
else
    run_docker volume create portainer_data >/dev/null
    run_docker run -d -p 9443:9443 --name portainer --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data portainer/portainer-ce:latest >/dev/null
    chg "portainer container created (image: portainer/portainer-ce:latest)"
fi
task_end

# ============================================================ FR-18 ========
task_start "FR-18" "Final status report" \
    "Definition of done: status of docker, ddev, Portainer + all containers. No project is created."
FAIL=0
status() { # name, 0=pass|1=fail, detail
    if [[ "$2" == "0" ]]; then echo "  [PASS] $1: $3"; else echo "  [FAIL] $1: $3"; FAIL=1; fi
}
DOCKER_STATE=$(sudo systemctl is-active docker 2>/dev/null || true)
if [[ "$DOCKER_STATE" == "active" ]]; then
    status "docker daemon" 0 "active"
else
    status "docker daemon" 1 "${DOCKER_STATE:-unknown}"
fi
DDEV_V=$(ddev -v 2>/dev/null | head -n1 || true)
if [[ -n "$DDEV_V" ]] && run_docker info >/dev/null 2>&1; then
    status "ddev" 0 "$DDEV_V (docker reachable)"
else
    status "ddev" 1 "not installed or docker unreachable"
fi
PSTATE=$(run_docker ps -a --filter name=portainer --format '{{.State}}' 2>/dev/null || true)
if [[ "$PSTATE" == "running" ]] && curl -k -fsS https://localhost:9443 >/dev/null 2>&1; then
    status "portainer" 0 "running; https://localhost:9443 responds"
else
    status "portainer" 1 "state=${PSTATE:-unknown}"
fi
if [[ "${WSL_SETUP_CAP_WARNING:-}" == "1" ]]; then
    status "windows capability (Mirrored/systemd)" 1 \
        "unsupported on this Windows/WSL build - documented .wslconfig values may be ignored"
fi
echo ""
echo "  All containers (docker ps -a):"
run_docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | sed 's/^/    /'
echo ""
if [[ "$FAIL" == "0" ]]; then
    echo "RESULT: PASS - environment ready (no project created, per definition of done)"
else
    echo "RESULT: FAIL - see [FAIL] items above"
fi
exit "$FAIL"
