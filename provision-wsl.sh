#!/usr/bin/env bash
# provision-wsl.sh - Linux side of the WSL2 + DDEV setup automation.
# Implements FR-05..FR-18 of docs/wsl-ddev-setup-prd.md.
#
# Supported distro (PRD): Debian >= 12 ONLY. The script verifies the running
# distro from /etc/os-release and aborts on anything else.
#
# Run inside WSL (see wsl-setup.ps1's printed handoff guide):
#     bash provision-wsl.sh [--no-upgrade] [--skip-ca-import] [--log F] [--pause N]
#
# Unattended after ONE sudo password prompt (timestamp kept alive).
# Fail fast on the first failed step (set -euo pipefail).
set -euo pipefail

# USER may be unset in minimal/non-login invocation contexts (e.g. wsl -e bash);
# resolve it once so set -u cannot abort later tasks (FR-09/FR-11).
USER="${USER:-$(id -un)}"

# Windows-PATH scrub: wsl.conf's appendWindowsPath=false only applies to the
# NEXT session (it is written in FR-06 and applied by FR-18's wsl --shutdown).
# During THIS run the Windows PATH is still appended, so Windows node/npm/code
# resolve first and poison tool detection - real-run bug #10: nvm's installer
# listed C:\Users\...\AppData\Roaming\npm globals and a Windows `node` could
# satisfy the "already installed" check. Every interop call in this script
# (certutil.exe, wsl.exe) uses an absolute /mnt/c/... path, so dropping the
# /mnt/* entries is safe.
if [[ "$PATH" == */mnt/* ]]; then
    PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -v -e '^/mnt/' -e '^$' | paste -sd:)"
    export PATH
fi

# ---- output colors: one distinct color per message type, consistent with the
# ---- Windows phase (pwsh). Defined FIRST - the flag parser and root guard
# below use C_FAIL, and set -u would abort on an unknown flag if they were not
# defined yet (audit #1). Enabled only on a real terminal (-t 1); piped or
# captured output (tests, logs) stays plain so assertions never break.
if [[ -t 1 ]]; then
    C_STAGE=$'\e[1;36m'    # process/stage header      - bold cyan
    C_OK=$'\e[0;32m'       # success                   - green
    C_CHG=$'\e[0;35m'      # change made               - magenta
    C_ABSENT=$'\e[0;34m'   # pending (not installed)   - blue
    C_SANITIZE=$'\e[0;93m' # docs sanitizer loop       - bright yellow
    C_SKIP=$'\e[0;90m'     # skipped (already present) - gray
    C_WARN=$'\e[0;33m'     # warning                   - yellow
    C_FAIL=$'\e[1;31m'     # error/abort               - bold red
    C_BAR=$'\e[0;90m'      # progress/footer structure - gray
    C_RESET=$'\e[0m'
else
    C_STAGE=''; C_OK=''; C_CHG=''; C_ABSENT=''; C_SANITIZE=''; C_SKIP=''; C_WARN=''; C_FAIL=''; C_BAR=''; C_RESET=''
fi

# ---------------------------------------------------------------- flags ----
UPGRADE=1
SKIP_CA=0
LOG_FILE=""
PAUSE=5
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-upgrade)           UPGRADE=0 ;;
        --skip-ca-import)       SKIP_CA=1 ;;
        --log)                  LOG_FILE="${2:?--log needs a file path}"; shift ;;
        --pause)                PAUSE="${2:?--pause needs a value}"; shift ;;
        *) echo "${C_FAIL}[ABORT] Unknown flag: $1${C_RESET}" >&2; exit 2 ;;
    esac
    shift
done

# --------------------------------------------- root guard (best practice) --
# Everything here must run as the normal WSL user: tool installs (bun, zsh
# plugins) must land in YOUR home, and 'usermod -aG docker' must target YOUR
# user. The script elevates via sudo only where required.
if [[ $EUID -eq 0 ]]; then
    echo "${C_FAIL}[ABORT] Running as root is not supported. Run as your normal WSL user.${C_RESET}" >&2
    echo "        (Installs would land in /root and 'usermod' would target the wrong user.)" >&2
    echo "${C_FAIL}        Debian without a completed first launch defaults to root.${C_RESET}" >&2
    echo "        run wsl-setup.ps1 (its default-user gate creates the UNIX user)," >&2
    echo "        or create one manually: useradd -m -G sudo -s /bin/bash <name>" >&2
    exit 1
fi

# --------------------------------------------- configuration & references --
# PIN RULE (uniform): every *_REF / *_VERSION below holds the LITERAL upstream
# git tag exactly as the releases page shows it - never add or strip a 'v'
# prefix here. Tag conventions differ per repo (noted per line); every pinned
# release URL is HEAD-checked by the verify-all battery (check 3; see
# docs/verification-loop.md - the suite lives in %TEMP%\wsl-tests), so a wrong
# prefix fails the battery instead of a real run (real-run bug #8 class).
NVM_VERSION="v0.40.3"   # pinned nvm release (tags v-prefixed); verify before bumping:
                        # https://github.com/nvm-sh/nvm/releases
                        # Node.js itself tracks current LTS via 'nvm install --lts'
MKCERT_VERSION="v1.4.4"   # pinned upstream release (tags v-prefixed); verify before bumping:
                          # https://github.com/FiloSottile/mkcert/releases
# zsh stack v2: plugins are antidote-managed (pinned via branch:/pin: annotations
# in ~/.zsh_plugins*.txt below); binaries come from pinned GitHub releases (.deb
# or tarball - never an install script). Pinning is a supply-chain control; all
# refs below were resolved via git ls-remote / the GitHub releases API. Bumping
# a pin is a deliberate script edit.
ANTIDOTE_REF="v2.3.0"                  # github.com/mattmc3/antidote (tags v-prefixed)
ZSH_SMARTCACHE_SHA="54aba13a6824e212992fd754c598c9e9acd259a3"   # github.com/QuarticCat/zsh-smartcache (no tags upstream -> antidote pin: full SHA)
FZF_TAB_REF="v1.3.0"                   # github.com/Aloxaf/fzf-tab (tags v-prefixed)
ZSH_AUTOSUGGESTIONS_REF="v0.7.1"       # github.com/zsh-users/zsh-autosuggestions (tags ARE v-prefixed)
ZSH_COMPLETIONS_REF="0.36.0"           # github.com/zsh-users/zsh-completions (tags are NOT v-prefixed)
ZSH_PATINA_VERSION="1.12.0"            # github.com/michel-kraemer/zsh-patina (tag has NO v-prefix - real-run bug #8; .deb: zsh-patina_<ver>_<arch>.deb; binary supports --version - verified on first real run)
ATUIN_VERSION="v18.24.8"               # github.com/atuinsh/atuin (tags v-prefixed; tarball asset: atuin-<target>.tar.gz - no version in the asset NAME)
ZOXIDE_VERSION="v0.10.0"               # github.com/ajeetdsouza/zoxide (tags v-prefixed; .deb asset: zoxide_<ver-without-v>-1_<arch>.deb - the '-1' is the upstream Debian revision, part of the asset name; not in bookworm repos)
# Source references (official docs, kept for traceability - PRD "no version rot"):
#   Docker CE install : https://docs.docker.com/engine/install/debian/
#   DDEV              : https://docs.ddev.com/ (install script: ddev.com/install.sh)
#   bun               : https://bun.sh/docs/installation (its installer needs unzip)
#   nvm (Node.js)     : https://github.com/nvm-sh/nvm (pinned release above)
#   mkcert            : https://github.com/FiloSottile/mkcert
#   Portainer CE      : https://docs.portainer.io/start/install-ce/server/docker
#   zsh stack         : https://github.com/mattmc3/antidote + plugins (see pins above);
#                       load-order docs: Aloxaf/fzf-tab README (post-compinit, pre-widget-plugins)

# ------------------------------------------------- presentation (FR-17) ----
TOTAL=13   # task count (FR-05..FR-18) - bump when adding a task or the % breaks
BAR_W=26   # progress bar width in chars - mirrored in wsl-setup.ps1, keep in sync
CURRENT=0
RUN_START_TS=$SECONDS
TASK_START_TS=0
TASK_CHG=0
# --log F: tee the entire transcript to a file (post-mortem forensics). Started
# AFTER the color decision so a colored console keeps its colors.
if [[ -n "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "transcript logging enabled: $LOG_FILE"
fi
fmt_time(){ local s="$1"; printf '%dm%02ds' $(( s / 60 )) $(( s % 60 )); }
progress_bar(){ local done_n="$1"; local filled=$(( BAR_W * done_n / TOTAL )); \
  printf '%*s' "$filled" '' | tr ' ' '#'; printf '%*s' "$(( BAR_W - filled ))" '' | tr ' ' '-'; }
task_start() { # $1 FR id, $2 title, $3 description
    CURRENT=$((CURRENT + 1))
    TASK_START_TS=$SECONDS
    TASK_CHG=0
    echo ""
    echo "${C_STAGE}==================================================================${C_RESET}"
    echo "${C_STAGE}[$CURRENT/$TOTAL] $1 - $2${C_RESET}"
    echo "${C_STAGE}------------------------------------------------------------------${C_RESET}"
    echo "$3"
}
task_end() {
    local took=$(( SECONDS - TASK_START_TS ))
    local elapsed=$(( SECONDS - RUN_START_TS ))
    local pct=$(( CURRENT * 100 / TOTAL ))
    if [[ $TASK_CHG -eq 0 ]]; then
        echo "${C_BAR}--- stage completed: nothing to do (all present) | took $(fmt_time "$took") | [$(progress_bar "$CURRENT")] ${pct}% | run elapsed $(fmt_time "$elapsed") ---${C_RESET}"
    else
        echo "${C_BAR}--- stage completed: $TASK_CHG change(s) | took $(fmt_time "$took") | [$(progress_bar "$CURRENT")] ${pct}% | run elapsed $(fmt_time "$elapsed") ---${C_RESET}"
    fi
    sleep "$PAUSE"
}

ok()   { echo "  ${C_OK}[OK]${C_RESET}   $*"; }
chg()  { echo "  ${C_CHG}[CHG]${C_RESET}  $*"; TASK_CHG=$((TASK_CHG + 1)); }
skip() { echo "  ${C_SKIP}[SKIP]${C_RESET} $*"; }
warn() { echo "  ${C_WARN}[WARN]${C_RESET} $*"; }
die()  { echo "  ${C_FAIL}[ABORT]${C_RESET} $*" >&2; exit 1; }
ab()   { echo "  ${C_ABSENT}[ABSENT]${C_RESET} $*"; }
san()  { echo "  ${C_SANITIZE}[SANITIZE]${C_RESET} $*"; }

# --------------------------------- sudo keepalive (one prompt, kept alive) -
SUDO_KEEPALIVE_PID=""
cleanup() { [[ -n "${SUDO_KEEPALIVE_PID}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true; }
trap cleanup EXIT
sudo -v
keep_sudo_alive() { while true; do sudo -n true 2>/dev/null || return; sleep 55; done; }
keep_sudo_alive &
SUDO_KEEPALIVE_PID=$!

# ---------------------- package manager (Debian-only: apt) ------------------
# ============================================================ FR-05 ========
task_start "FR-05" "Inventory & preflight" \
    "Detect distro/systemd; report what is already installed. Nothing is reinstalled."

if [[ ! -r /etc/os-release ]]; then
    die "/etc/os-release not readable - unsupported distro"
fi
. /etc/os-release
ID_LC="${ID,,}"
if [[ -z "${VERSION_ID:-}" ]]; then
    die "VERSION_ID missing in /etc/os-release (testing/sid?) - unsupported"
fi
case "$ID_LC" in
    debian)
        [[ "${VERSION_ID%%.*}" -ge 12 ]] || die "Debian >= 12 required, found $VERSION_ID"
        if [[ -z "${VERSION_CODENAME:-}" ]]; then
            die "VERSION_CODENAME missing - required on Debian for the Docker apt source"
        fi
        ;;
    *)
        die "Unsupported distro: $ID (this automation is Debian-only, >= 12)"
        ;;
esac
ok "Distro: $PRETTY_NAME"
if [[ -n "${VERSION_CODENAME:-}" ]]; then ok "Codename: $VERSION_CODENAME"; fi

SYSTEMD_ACTIVE=0
if [[ "$(ps -p 1 -o comm=)" == "systemd" ]]; then
    SYSTEMD_ACTIVE=1
fi
if [[ "$SYSTEMD_ACTIVE" == "1" ]]; then ok "systemd: active"; else warn "systemd: NOT active (FR-06 will gate)"; fi

inv() { # label, binary, [version args...] - 3rd+ args passed to the binary; stage hint below
    local label="$1" binname="$2"; shift 2
    if c="$(command -v "$binname" 2>/dev/null)"; then
        local v
        v=$("$binname" "${@:---version}" 2>/dev/null | head -n1 || true)
        ok "$label: $c ${v:+[$v]}"
    else
        ab "$label: not installed (queued for installation in ${INV_STAGE:-FR-08+})"
    fi
}
# --- docker helpers (shared: FR-05 inventory, FR-11 install, FR-12+ usage) ---
run_docker() {
    # NOTE: 'id -nG "$USER"' reads the group DATABASE - which usermod already
    # updated - while the CURRENT session's process groups (what the socket
    # permission actually follows) only refresh on a new login. Check the
    # session groups instead, then fall back to sg when not yet applied.
    if id -nG 2>/dev/null | grep -qw docker; then
        docker "$@"
    else
        # %q quoting survives one sg -c shell evaluation for the CURRENT simple
        # argument shapes (paths, flags, image names). Keep run_docker args free
        # of newlines/'=' -complex values; extend quoting deliberately if needed.
        sg docker -c "$(printf '%q ' docker "$@")"
    fi
}
# Exact-name matching: docker's 'name=' filter is a SUBSTRING match, which can
# hit unrelated containers (e.g. 'my-portainer-test'). Match names precisely.
portainer_exists() {
    run_docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx portainer
}
portainer_state() {
    run_docker ps -a --format '{{.Names}} {{.State}}' 2>/dev/null | awk '$1 == "portainer" { print $2 }'
}
inv docker docker --version
inv ddev   ddev -v
inv git    git --version
# node/npm come from nvm (~/.nvm) - load it in-session to report versions
if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    . "$HOME/.nvm/nvm.sh" >/dev/null 2>&1 || true
    if command -v node >/dev/null 2>&1; then
        ok "node: $(node --version) (npm $(npm --version)) via nvm"
    else
        ab "node: nvm present but no Node version installed yet (FR-08 installs LTS)"
    fi
else
    ab "node/npm: not installed (nvm is the install path)"
fi
inv zsh    zsh --version
inv curl   curl --version
inv fzf    fzf --version
# zsh stack v2 binaries: atuin lives outside PATH (~/.atuin/bin) until a session
# adds it - check the file too, same pattern as bun below
if c="$(command -v atuin 2>/dev/null)" || [[ -x "$HOME/.atuin/bin/atuin" ]]; then
    ATUIN_BIN="${c:-$HOME/.atuin/bin/atuin}"
    ok "atuin: $ATUIN_BIN [$("$ATUIN_BIN" --version 2>/dev/null | head -n1)]"
else
    ab "atuin: not installed (queued for installation in FR-09)"
fi
INV_STAGE="FR-09"
inv zoxide     zoxide --version
inv zsh-patina zsh-patina --version
INV_STAGE=""
# bun lives outside PATH (~/.bun/bin) until a session adds it - check the file too
if c="$(command -v bun 2>/dev/null)" || [[ -x "$HOME/.bun/bin/bun" ]]; then
    BUN_BIN="${c:-$HOME/.bun/bin/bun}"
    ok "bun: $BUN_BIN [$("$BUN_BIN" --version)]"
else
    ab "bun: not installed (queued for installation in FR-08)"
fi
INV_STAGE="FR-14"
inv mkcert mkcert --version
INV_STAGE=""
if command -v docker >/dev/null 2>&1; then
    PT="$(portainer_state 2>/dev/null || true)"
    if [[ -n "$PT" ]]; then ok "portainer container: $PT"; else ab "portainer container: not present (created in FR-16)"; fi
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
    # NOTE: this gate exits BEFORE task_end by design - the run stops here (no
    # completion footer), so first-run output intentionally differs from reruns.
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
task_start "FR-07" "Package index + base upgrade" \
    "apt-get update every run; full base upgrade by default (--no-upgrade skips it - speed-first rerun)."
sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq
ok "package index refreshed (apt)"
if [[ "$UPGRADE" == "1" ]]; then
    sudo env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
    ok "full base upgrade complete (security currency)"
else
    skip "full base upgrade skipped (--no-upgrade)"
fi
task_end

# ============================================================ FR-08 ========
task_start "FR-08" "Development tools" \
    "Install only what is missing: curl, git, zsh, fzf, unzip, xz-utils, build-essential, Node.js LTS + npm (via pinned nvm), bun (official installer)."
BASE_PKGS=(curl git zsh ca-certificates unzip xz-utils build-essential fzf)   # unzip: bun installer; xz-utils: nvm node tarballs; fzf: fzf-tab backend (FR-09)
MISSING_PKGS=()
for p in "${BASE_PKGS[@]}"; do
    if ! dpkg -s "$p" >/dev/null 2>&1; then MISSING_PKGS+=("$p"); fi
done
if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${MISSING_PKGS[@]}"
    chg "installed: ${MISSING_PKGS[*]}"
else
    skip "base packages all present"
fi
if [[ -s "$HOME/.nvm/nvm.sh" ]] && . "$HOME/.nvm/nvm.sh" && command -v node >/dev/null 2>&1; then
    # nvm.sh present AND a Node version actually installed - an interrupted run
    # can leave nvm.sh behind without Node; fall through and install in that case
    skip "node/npm already present via nvm ($(node --version))"
elif command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && [[ "$(command -v node)" != /mnt/* ]]; then
    # genuine LINUX system node (a Windows node resolving under /mnt/* must
    # never satisfy this - it would skip the nvm install path entirely)
    skip "node/npm already present ($(node --version))"
else
    if command -v node >/dev/null 2>&1 && [[ "$(command -v node)" == /mnt/* ]]; then
        warn "node on PATH is the Windows one ($(command -v node)) - ignored; installing Linux Node via nvm"
    fi
    NVM_INSTALLER="$(mktemp)"
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" -o "$NVM_INSTALLER"   # inspectable before running
    # PROFILE=/dev/null is nvm's documented switch to skip rc-file appends -
    # without it the installer pollutes ~/.bashrc (real-run bug #10); zsh
    # wiring is done in FR-09's managed block instead.
    PROFILE=/dev/null bash "$NVM_INSTALLER"
    rm -f "$NVM_INSTALLER"
    . "$HOME/.nvm/nvm.sh"          # load nvm in this session (zsh wiring is FR-09)
    nvm install --lts              # current LTS Node + bundled npm (official nvm flow)
    chg "Node.js LTS installed via nvm: $(node --version) (npm $(npm --version)) (nvm $(nvm --version))"
fi
if [[ -x "$HOME/.bun/bin/bun" ]] || command -v bun >/dev/null 2>&1; then
    skip "bun already present"
else
    BUN_INSTALLER="$(mktemp)"
    curl -fsSL https://bun.sh/install -o "$BUN_INSTALLER"   # inspectable before running
    bash "$BUN_INSTALLER"
    rm -f "$BUN_INSTALLER"
    chg "bun installed: $("$HOME/.bun/bin/bun" --version)"
fi
task_end

# ============================================================ FR-09 ========
task_start "FR-09" "Shell setup (zsh)" \
    "No framework by policy. antidote-managed plugins (pinned via branch:/pin:), zsh-patina syntax highlighting (.deb), fzf-tab, smartcache, atuin, zoxide. Managed block in ~/.zshrc: fpath group -> compinit -> main group -> evals. Replaces the v1 plugin stack automatically."
ARCH="$(dpkg --print-architecture)"   # amd64 / arm64 - matches .deb asset naming

# --- antidote (plugin manager; pinned tag clone, per antidote README) ---
ANTIDOTE_OK=0
if [[ -d "$HOME/.antidote/.git" ]]; then
    CLONED_REF="$(git -C "$HOME/.antidote" describe --tags --exact-match 2>/dev/null || echo '?')"
    if [[ "$CLONED_REF" == "$ANTIDOTE_REF" ]]; then
        skip "antidote already cloned ($CLONED_REF)"
        ANTIDOTE_OK=1
    else
        # pin bump: the on-disk clone no longer matches - re-clone (audit #13)
        warn "antidote cloned at $CLONED_REF but the pin is $ANTIDOTE_REF - re-cloning"
        rm -rf "$HOME/.antidote"
    fi
fi
if [[ "$ANTIDOTE_OK" == "0" ]]; then
    git -c advice.detachedHead=false clone --depth=1 -q --branch "$ANTIDOTE_REF" https://github.com/mattmc3/antidote.git "$HOME/.antidote"
    chg "antidote cloned (ref: $ANTIDOTE_REF)"
fi

# --- zsh-patina (syntax highlighter daemon; .deb -> dpkg-managed, uninstallable) ---
if dpkg -s zsh-patina >/dev/null 2>&1; then
    skip "zsh-patina already installed"
else
    PATINA_DEB="$(mktemp)"
    # NOTE: patina's release tags carry NO 'v' prefix (download/1.12.0/... not /v1.12.0/) - real-run bug #8
    curl -fsSL "https://github.com/michel-kraemer/zsh-patina/releases/download/${ZSH_PATINA_VERSION}/zsh-patina_${ZSH_PATINA_VERSION}_${ARCH}.deb" -o "$PATINA_DEB"
    sudo dpkg -i "$PATINA_DEB"
    rm -f "$PATINA_DEB"
    chg "zsh-patina installed (.deb v${ZSH_PATINA_VERSION}: $(zsh-patina --version 2>/dev/null || echo '?'))"
fi

# --- zoxide (smarter cd; not in bookworm repos -> pinned .deb) ---
if dpkg -s zoxide >/dev/null 2>&1; then
    skip "zoxide already installed"
else
    ZOXIDE_DEB="$(mktemp)"
    # tag from the pin var; asset name uses the bare version (${ZOXIDE_VERSION#v}) + the '-1' Debian revision
    curl -fsSL "https://github.com/ajeetdsouza/zoxide/releases/download/${ZOXIDE_VERSION}/zoxide_${ZOXIDE_VERSION#v}-1_${ARCH}.deb" -o "$ZOXIDE_DEB"
    sudo dpkg -i "$ZOXIDE_DEB"
    rm -f "$ZOXIDE_DEB"
    chg "zoxide installed (.deb v${ZOXIDE_VERSION}: $(zoxide --version 2>/dev/null || echo '?'))"
fi

# --- atuin (Rust shell history; pinned release tarball, downloaded to file -
#     never piped into a shell, matching the nvm/bun pattern) ---
ATUIN_TARGET="$(uname -m)-unknown-linux-gnu"   # x86_64 / aarch64
if [[ -x "$HOME/.atuin/bin/atuin" ]]; then
    skip "atuin already present"
else
    ATUIN_TGZ="$(mktemp)"
    curl -fsSL "https://github.com/atuinsh/atuin/releases/download/${ATUIN_VERSION}/atuin-${ATUIN_TARGET}.tar.gz" -o "$ATUIN_TGZ"
    ATUIN_TMP="$(mktemp -d)"
    tar -xzf "$ATUIN_TGZ" -C "$ATUIN_TMP"
    mkdir -p "$HOME/.atuin/bin"
    ATUIN_BIN_SRC="$(find "$ATUIN_TMP" -name atuin -type f -print -quit)"
    [[ -n "$ATUIN_BIN_SRC" ]] || die "atuin binary not found inside the release tarball (upstream layout changed? verify ATUIN_VERSION)"
    install -m 755 "$ATUIN_BIN_SRC" "$HOME/.atuin/bin/atuin"
    rm -rf "$ATUIN_TMP" "$ATUIN_TGZ"
    chg "atuin installed ($("$HOME/.atuin/bin/atuin" --version 2>/dev/null || echo '?'))"
fi

# --- antidote plugin files (script-owned; rewritten only when content differs) ---
# Pinning note (deliberate): bundles use branch:<tag> because antidote's own
# man page (antidote-bundle(1)) says "Use branch: for tags or branches" and
# git clone --branch accepts tags. A missing ref fails the antidote pre-warm
# below loudly - there is no silent fallback to latest.
# Two bundle files, because load order is contractual:
#   1. .zsh_plugins_fpath.txt - BEFORE compinit: zsh-completions registers fpath.
#   2. .zsh_plugins.txt       - AFTER compinit: fzf-tab must load post-compinit and
#     before widget-wrapping plugins (zsh-autosuggestions), per its README.
# smartcache is first in the main file so `smartcache eval` calls below find it.
write_owned() { # path, content - no [CHG] churn on rerun when content is identical
    local f="$1" content="$2"
    if [[ -f "$f" && "$(cat "$f")" == "$content" ]]; then
        skip "$(basename "$f") unchanged"
    else
        printf '%s\n' "$content" > "$f"
        chg "wrote $(basename "$f")"
    fi
}
write_owned "$HOME/.zsh_plugins_fpath.txt" \
"zsh-users/zsh-completions branch:${ZSH_COMPLETIONS_REF} path:src kind:fpath"
write_owned "$HOME/.zsh_plugins.txt" \
"QuarticCat/zsh-smartcache pin:${ZSH_SMARTCACHE_SHA}
Aloxaf/fzf-tab branch:${FZF_TAB_REF}
zsh-users/zsh-autosuggestions branch:${ZSH_AUTOSUGGESTIONS_REF}"

# --- ~/.zshrc: managed block, replaced wholesale when the stack changes ---
# Content outside the >>>/<<< zcode-managed markers (user edits) is preserved.
# The v1 block (old clones + zsh-syntax-highlighting) is migrated off by this.
ZRC="$HOME/.zshrc"
NEW_BLOCK="$(cat <<'ZCODE_BLOCK_EOF'
# >>> zcode-managed (provision-wsl.sh) >>>
# 1. PATH & history
export PATH="$HOME/.local/bin:$HOME/.atuin/bin:$HOME/.bun/bin:$PATH"
HISTFILE="${ZDOTDIR:-$HOME}/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS HIST_FIND_NO_DUPS SHARE_HISTORY EXTENDED_HISTORY AUTO_CD

# 2. nvm (Node LTS from FR-08)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# 3. antidote - fpath group first (zsh-completions registers BEFORE compinit)
source "${ZDOTDIR:-$HOME}/.antidote/antidote.zsh"
antidote load "${ZDOTDIR:-$HOME}/.zsh_plugins_fpath.txt"

autoload -Uz compinit
# compinit -C: cached, skips the security audit (compaudit) - deliberate speed tradeoff
compinit -C

# 4. antidote - main plugins AFTER compinit (fzf-tab order requirement, see its README)
antidote load

# 5. fzf-tab styling (README-recommended zstyles)
zstyle ':completion:*' menu no
[[ -n "$LS_COLORS" ]] && zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -la --color=always $realpath'

# 6. Navigation: AUTO_CD (setopt above) + rationalise-dot widget + zoxide
rationalise-dot() {
  if [[ $LBUFFER == *.. ]]; then
    LBUFFER+=/..
  else
    LBUFFER+=.
  fi
}
zle -N rationalise-dot
bindkey . rationalise-dot
bindkey -M isearch . self-insert
smartcache eval zoxide init zsh

# 7. History: native prefix search (Up/Down) + atuin (Ctrl-R only)
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
[[ -n "${terminfo[kcuu1]}" ]] && bindkey "${terminfo[kcuu1]}" up-line-or-beginning-search
[[ -n "${terminfo[kcud1]}" ]] && bindkey "${terminfo[kcud1]}" down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search
smartcache eval atuin init zsh --disable-up-arrow

# 8. Syntax highlighting - zsh-patina (replaces zsh-syntax-highlighting), activated last.
# NOT routed through smartcache: it handles command output unquoted
# (eval $output, printf '%s' $output >| $cache), which word-splits patina's
# multi-line activate script - a cache refresh then leaves NO highlighting
# (real-run bug #9). patina's activate eval is cheap by design (the Rust
# daemon does the work), so caching it buys nothing.
command -v zsh-patina >/dev/null 2>&1 && eval "$(zsh-patina activate)"
# <<< zcode-managed <<<
ZCODE_BLOCK_EOF
)"
if grep -q '^# >>> zcode-managed' "$ZRC" 2>/dev/null; then
    OLD_BLOCK="$(sed -n '/^# >>> zcode-managed/,/^# <<< zcode-managed/p' "$ZRC")"
    if [[ "$OLD_BLOCK" == "$NEW_BLOCK" ]]; then
        skip ".zshrc managed block unchanged"
    else
        cp "$ZRC" "$ZRC.bak-$(date +%Y%m%d-%H%M%S)"
        sed -i '/^# >>> zcode-managed/,/^# <<< zcode-managed/d' "$ZRC"
        [[ -n "$(tail -c1 "$ZRC")" ]] && echo >> "$ZRC"   # block must start on its own line
        printf '%s\n' "$NEW_BLOCK" >> "$ZRC"
        chg "replaced .zshrc managed block (v1 stack migrated off; previous file backed up)"
    fi
else
    if [[ -f "$ZRC" ]]; then
        cp "$ZRC" "$ZRC.bak-$(date +%Y%m%d-%H%M%S)"
        chg "backed up existing .zshrc"
        [[ -n "$(tail -c1 "$ZRC")" ]] && echo >> "$ZRC"   # block must start on its own line
    fi
    printf '%s\n' "$NEW_BLOCK" >> "$ZRC"
    chg "appended managed block to ~/.zshrc"
fi

# --- migrate off the v1 stack (old clones are replaced by antidote management) ---
for d in "$HOME/.zsh/plugins/zsh-autosuggestions" "$HOME/.zsh/plugins/zsh-completions" "$HOME/.zsh/plugins/zsh-syntax-highlighting"; do
    if [[ -e "$d" ]]; then
        rm -rf "$d"
        chg "removed v1 stack clone: $(basename "$d")"
    fi
done
if rmdir "$HOME/.zsh/plugins" "$HOME/.zsh" 2>/dev/null; then
    chg "removed empty ~/.zsh tree"
fi

# --- pre-warm antidote (clones the pinned plugins, builds the static load file)
# so the startup measurement below reflects steady state, not first-run downloads ---
if [[ -f "$HOME/.antidote/antidote.zsh" ]]; then
    if zsh -c 'source "$HOME/.antidote/antidote.zsh"; antidote load' >/dev/null 2>&1; then
        ok "antidote plugins loaded (pre-warm)"
    else
        warn "antidote pre-warm had errors - check the refs in ~/.zsh_plugins*.txt"
    fi
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
    "Official Docker docs (verbatim): run the removal loop unconditionally; apt tolerates absent packages ('not installed, so not removed')."
CONFLICTS=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)
for p in "${CONFLICTS[@]}"; do
    if dpkg -s "$p" >/dev/null 2>&1; then
        sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y -qq "$p"
        chg "removed conflicting package: $p"
    else
        san "$p: absent - nothing to remove (docs loop ran regardless)"
    fi
done
task_end

# ============================================================ FR-11 ========
task_start "FR-11" "Docker CE" \
    "Official deb822 apt repository keyed by VERSION_CODENAME, docker group, enable + start service."
if command -v docker >/dev/null 2>&1; then
    ok "docker already installed: $(docker --version)"
else
    REPO="https://download.docker.com/linux/$ID_LC"
    sudo install -m 0755 -d /etc/apt/keyrings
    GPG_TMP="$(mktemp)"
    curl -fsSL "$REPO/gpg" -o "$GPG_TMP"   # download as user (least privilege)
    sudo install -m 0644 "$GPG_TMP" /etc/apt/keyrings/docker.asc
    rm -f "$GPG_TMP"
    sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: $REPO
Suites: $VERSION_CODENAME
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
    chg "added apt source /etc/apt/sources.list.d/docker.sources ($ID_LC / $VERSION_CODENAME)"
    sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    chg "installed Docker CE + buildx + compose plugin (apt)"
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
    DDEV_INSTALLER="$(mktemp)"
    curl -fsSL https://ddev.com/install.sh -o "$DDEV_INSTALLER"   # inspectable before running
    bash "$DDEV_INSTALLER"
    rm -f "$DDEV_INSTALLER"
    chg "ddev installed: $(ddev -v)"
fi
task_end

# ============================================================ FR-14 ========
task_start "FR-14" "mkcert" \
    "Local CA for *.ddev.site HTTPS; distro NSS tools (libnss3-tools / nss-tools); mkcert -install."
NSS_PKG="libnss3-tools"
if ! dpkg -s "$NSS_PKG" >/dev/null 2>&1; then
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$NSS_PKG"
    chg "installed $NSS_PKG"
fi
if command -v mkcert >/dev/null 2>&1; then
    ok "mkcert already installed ($(command -v mkcert))"
else
    case "$(uname -m)" in
        x86_64)  MKCERT_ARCH="amd64" ;;
        aarch64) MKCERT_ARCH="arm64" ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac
    MKCERT_URL="https://github.com/FiloSottile/mkcert/releases/download/${MKCERT_VERSION}/mkcert-${MKCERT_VERSION}-linux-${MKCERT_ARCH}"
    MKCERT_BIN="$(mktemp)"
    curl -fsSL "$MKCERT_URL" -o "$MKCERT_BIN"   # pinned version, downloaded as user
    sudo install -m 0755 "$MKCERT_BIN" /usr/local/bin/mkcert
    rm -f "$MKCERT_BIN"
    chg "mkcert $MKCERT_VERSION installed to /usr/local/bin/mkcert (arch: $MKCERT_ARCH)"
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
        if [[ -z "$WIN_USER" ]]; then
            warn "could not resolve Windows username - import manually from $(mkcert -CAROOT)/rootCA.pem"
        else
            DEST="/mnt/c/Users/${WIN_USER}/AppData/Local/Temp/mkcert-rootCA.pem"
            cp "$(mkcert -CAROOT)/rootCA.pem" "$DEST"
            if "$CERTUTIL" -user -store Root 2>/dev/null | grep -qi 'mkcert'; then
                rm -f "$DEST"
                skip "mkcert root CA already trusted in Windows current-user store"
            elif "$CERTUTIL" -user -addstore Root "$(wslpath -w "$DEST")" >/dev/null 2>&1; then
                rm -f "$DEST"
                chg "mkcert root CA imported to Windows (current-user Trusted Root)"
            else
                warn "certutil import failed - staged copy kept for manual import: $DEST"
            fi
        fi
    fi
fi
task_end

# ============================================================ FR-16 ========
task_start "FR-16" "Portainer" \
    "GUI for Docker on https://127.0.0.1:9443 (container name: portainer, restart=always). Serves a mkcert-signed TLS cert for localhost/127.0.0.1 via --sslcert/--sslkey (CA trusted on Windows via FR-15) - no browser warning. HTTP fallback on port 9000. Certs live in a persistent dir - /tmp is wiped on VM boot."
TLS_DIR="$HOME/.local/share/portainer-tls"   # persistent ext4 - /tmp is wiped on VM boot (Debian tmpfiles.d)
mkdir -p "$TLS_DIR" && chmod 700 "$TLS_DIR" 2>/dev/null || true   # chmod may no-op on Windows ACL emulation (Git Bash)
CERT_OK=0
if command -v mkcert >/dev/null 2>&1 && [[ -f "$(mkcert -CAROOT)/rootCA.pem" ]]; then
    if [[ -f "$TLS_DIR/portainer.crt" && -f "$TLS_DIR/portainer.key" ]]; then
        skip "mkcert-signed cert already present in $TLS_DIR (delete the pair to force regeneration)"
        CERT_OK=1
    else
        mkcert -cert-file "$TLS_DIR/portainer.crt" -key-file "$TLS_DIR/portainer.key" localhost 127.0.0.1
        chmod 600 "$TLS_DIR/portainer.key"
        CERT_OK=1
        chg "generated mkcert-signed TLS cert for localhost/127.0.0.1 in $TLS_DIR (persistent; CA trusted on Windows via FR-15)"
    fi
fi
# Post-set verification: permissions must be 700 dir / 600 key (provable on
# real Debian; Git Bash emulates chmod, so the sim proves the flow, not ACLs)
if [[ "$CERT_OK" == "1" ]]; then
    DIR_PERM="$(stat -c '%a' "$TLS_DIR" 2>/dev/null || echo '?')"
    KEY_PERM="$(stat -c '%a' "$TLS_DIR/portainer.key" 2>/dev/null || echo '?')"
    if [[ "$DIR_PERM" == "700" && "$KEY_PERM" == "600" ]]; then
        ok "cert permissions verified: dir $DIR_PERM, key $KEY_PERM"
    else
        warn "cert permissions unexpected: dir $DIR_PERM, key $KEY_PERM (expected 700/600)"
    fi
fi
rm -rf /tmp/portainer.crt /tmp/portainer.key   # cleanup /tmp leftovers (auto-created dirs from the pre-fix bug; remove after the first clean real run)
CERT_MOUNTS=""
CERT_FLAGS=""
if [[ "$CERT_OK" == "1" ]]; then
    CERT_MOUNTS="-v $TLS_DIR/portainer.crt:/data/tls/portainer.crt -v $TLS_DIR/portainer.key:/data/tls/portainer.key"
    # Portainer only loads the pair via CLI flags (api/internal/ssl/ssl.go: certSupplied
    # = certPath!="" && keyPath!=""); a bare /data/tls mount is never read, and without
    # the flags it keeps serving its own self-signed cert on 9443.
    CERT_FLAGS="--sslcert /data/tls/portainer.crt --sslkey /data/tls/portainer.key"
fi
create_portainer() {   # single home for the exact run invocation (fresh-create and recreate paths share it)
    run_docker run -d -p 127.0.0.1:9443:9443 --name portainer --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        $CERT_MOUNTS \
        portainer/portainer-ce:latest \
        $CERT_FLAGS >/dev/null
}
if portainer_exists; then
    # Heal checks first (audit #8: LAN exposure auto-recreates now, matching the
    # PRD promise instead of just warning). Do NOT wipe portainer_data: with the
    # flags supplied, Portainer copies the pair over the datastore's self-signed
    # one on boot.
    RECREATE=0
    RECREATE_WHY=""
    if [[ "$CERT_OK" == "1" ]] && ! run_docker inspect portainer --format '{{json .Mounts}}' 2>/dev/null | grep -q portainer.crt; then
        RECREATE=1; RECREATE_WHY="cert mount missing"
    elif [[ "$CERT_OK" == "1" ]] && ! run_docker inspect portainer --format '{{json .Config.Cmd}}' 2>/dev/null | grep -q sslcert; then
        RECREATE=1; RECREATE_WHY="--sslcert/--sslkey missing (a bare mount is not read by Portainer)"
    fi
    if run_docker port portainer 2>/dev/null | grep -q '0.0.0.0:9443'; then
        RECREATE=1; RECREATE_WHY="${RECREATE_WHY:+$RECREATE_WHY; }LAN-exposed (0.0.0.0:9443)"
    fi
    if [[ "$RECREATE" == "1" ]]; then
        warn "existing portainer container needs recreation ($RECREATE_WHY)"
        run_docker rm -f portainer >/dev/null
        run_docker volume create portainer_data >/dev/null
        create_portainer
        chg "portainer recreated (loopback-only: 127.0.0.1:9443, mkcert TLS applied via --sslcert/--sslkey)"
    else
        PSTATE="$(portainer_state)"
        if [[ "$PSTATE" == "running" ]]; then
            ok "portainer container already running"
        else
            run_docker start portainer >/dev/null
            chg "portainer container started"
        fi
    fi
else
    run_docker volume create portainer_data >/dev/null
    create_portainer
    chg "portainer container created (loopback-only: 127.0.0.1:9443, not reachable from LAN)${CERT_OK:+ - mkcert TLS applied via --sslcert/--sslkey}"
fi
task_end

# ============================================================ FR-18 ========
task_start "FR-18" "Final status report" \
    "Definition of done: status of docker, ddev, Portainer + all containers. No project is created."
FAIL=0
status() { # name, 0=pass|1=fail, detail
    if [[ "$2" == "0" ]]; then echo "  ${C_OK}[PASS]${C_RESET} $1: $3"; else echo "  ${C_FAIL}[FAIL]${C_RESET} $1: $3"; FAIL=1; fi
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
# zsh stack v2 (FR-09): manager + plugins + binaries all present
STACK_MISSING=""
command -v zsh >/dev/null 2>&1                     || STACK_MISSING="${STACK_MISSING} zsh"
[[ -f "$HOME/.antidote/antidote.zsh" ]]            || STACK_MISSING="${STACK_MISSING} antidote"
command -v zsh-patina >/dev/null 2>&1              || STACK_MISSING="${STACK_MISSING} patina"
command -v zoxide >/dev/null 2>&1                  || STACK_MISSING="${STACK_MISSING} zoxide"
[[ -x "$HOME/.atuin/bin/atuin" ]]                  || STACK_MISSING="${STACK_MISSING} atuin"
command -v fzf >/dev/null 2>&1                     || STACK_MISSING="${STACK_MISSING} fzf"
[[ -f "$HOME/.zsh_plugins.txt" ]]                  || STACK_MISSING="${STACK_MISSING} plugins-file"
if [[ -z "$STACK_MISSING" ]]; then
    status "zsh stack (antidote/patina/atuin/zoxide/fzf)" 0 "all present"
else
    status "zsh stack (antidote/patina/atuin/zoxide/fzf)" 1 "missing:${STACK_MISSING}"
fi
# Served-cert check: the portainer listener must serve the mkcert-signed cert,
# NOT Portainer's own self-signed one (real-run bug class). Runs only on a
# real machine (interop present); the sandbox has no listener, so it skips.
if [[ -x /mnt/c/Windows/System32/wsl.exe ]]; then
    SERVED_ISSUER=""
    for _ in 1 2 3; do   # bounded grace: Portainer needs seconds to bind after create/start
        SERVED_ISSUER="$(timeout 5 openssl s_client -connect 127.0.0.1:9443 </dev/null 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null || true)"
        [[ "$SERVED_ISSUER" == *"mkcert"* ]] && break
        sleep 2
    done
    if [[ "$SERVED_ISSUER" == *"mkcert"* ]]; then
        status "portainer serving mkcert-signed TLS" 0 "$SERVED_ISSUER"
    else
        status "portainer serving mkcert-signed TLS" 1 "issuer: ${SERVED_ISSUER:-none} (self-signed? recreate FR-16)"
    fi
else
    skip "portainer serving mkcert-signed TLS: no interop (sandbox)"
fi
if [[ "$SKIP_CA" == "1" ]]; then
    echo "  ${C_SKIP}[SKIP]${C_RESET} mkcert CA trusted on Windows: skipped (--skip-ca-import)"
else
    CERTUTIL="/mnt/c/Windows/System32/certutil.exe"
    CA_TRUSTED=0; CA_DETAIL="certutil.exe not reachable (no interop)"
    if [[ -x "$CERTUTIL" ]]; then
        if "$CERTUTIL" -user -store Root 2>/dev/null | grep -qi 'mkcert'; then
            CA_TRUSTED=1; CA_DETAIL="found in current-user Trusted Root"
        else
            CA_DETAIL="NOT found in Windows store - browser will warn on https://127.0.0.1:9443 and *.ddev.site"
        fi
    fi
    status "mkcert CA trusted on Windows" "$CA_TRUSTED" "$CA_DETAIL"
fi
PSTATE=$(portainer_state || true)
PORT_OK=0
if [[ "$PSTATE" == "running" ]]; then
    for _ in 1 2 3; do   # bounded grace: a fresh container may not accept connections yet
        if curl -k -fsS https://127.0.0.1:9443 >/dev/null 2>&1 || curl -k -fsS https://localhost:9443 >/dev/null 2>&1; then
            PORT_OK=1; break
        fi
        sleep 2
    done
fi
if [[ "$PORT_OK" == "1" ]]; then
    status "portainer" 0 "running; https://127.0.0.1:9443 responds (loopback-only)"
else
    status "portainer" 1 "state=${PSTATE:-unknown}"
fi
# NOTE: the old WSL_SETUP_CAP_WARNING env-forwarded check was removed - after
# the manual-handoff containment change an env var set in the elevated Windows
# session cannot reach the separately-launched Debian shell (dead path); the
# capability warning now stays in wsl-setup.ps1's printed handoff guide.
echo ""
echo "  All containers (docker ps -a):"
run_docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' | sed 's/^/    /'
echo ""
echo "  total run runtime: $(fmt_time "$SECONDS")"
if [[ "$FAIL" == "0" ]]; then
    echo "${C_OK}RESULT: PASS - environment ready (no project created, per definition of done)${C_RESET}"
else
    echo "${C_FAIL}RESULT: FAIL - see [FAIL] items above${C_RESET}"
fi
echo ""
echo "${C_STAGE}[RESTART]${C_RESET} Applying configuration - restarting WSL now."
echo "${C_STAGE}         This terminal will close as the VM restarts. Reopen with 'wsl -d Debian'.${C_RESET}"
sleep 2
/mnt/c/Windows/System32/wsl.exe --shutdown 2>/dev/null || true
exit "$FAIL"
