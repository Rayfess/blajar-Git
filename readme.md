<a id="readme-top"></a>

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![project_license][license-shield]][license-url]

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
    </li>
    <li>
      <a href="#wsl2--ddev-setup-automation">WSL2 + DDEV Setup Automation</a>
      <ul>
        <li><a href="#how-it-works">How It Works</a></li>
        <li><a href="#verification">Verification</a></li>
        <li><a href="#troubleshooting">Troubleshooting</a></li>
        <li><a href="#project-files">Project Files</a></li>
        <li><a href="#uninstall">Uninstall</a></li>
      </ul>
    </li>
    <li>
        <a href="#prerequisites">Prerequisites</a>
        <ul>
          <li>
              <a href="#installation">Installation</a>
           </li>
        </ul>
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
  </ol>
</details>

## About The Project

In this project were introducing the basic and to advanced guide to use github and git commands effectively

## WSL2 + DDEV Setup Automation

This repository ships a one-command installer for a full Linux development
environment on WSL2 (Debian-only) with Docker CE, DDEV, Portainer, mkcert HTTPS
for `*.ddev.site`, and a zsh shell — replacing the manual procedure in
[wslddev.md](wslddev.md). Requirements and acceptance criteria live in
[wsl-ddev-setup-prd.md](wsl-ddev-setup-prd.md); project history, decisions,
and the real-run bug ledger in [MILESTONE.md](MILESTONE.md).

### Quick Start

1. Open **PowerShell as Administrator** (Win+X → Terminal (Admin))
2. Run the installer:

   ```pwsh
   cd D:\path\to\blajar-Git
   powershell -ExecutionPolicy Bypass -File wsl-setup.ps1
   ```

3. The script routes itself (decision tree):
   - WSL feature missing → installs it → **restart Windows** → run again
   - Feature present, no distro → installs **Debian** → run again →
     first launch in the Debian terminal (native user setup) → copy & run
     the provisioner from `~` (commands printed by the installer)
   - Debian installed → writes `.wslconfig` → prints the handoff guide
     (containment: the Linux phase runs inside Debian)

4. Enter the **sudo password once**; provisioning runs unattended
   (13 tasks, 5-second pause each) and ends with a PASS/FAIL status report.

### How It Works

```text
[PowerShell - Admin]  wsl-setup.ps1
  │
  ├─ A. WSL features missing ──► wsl --install -d Debian
  │      ⛔ STOP: restart Windows (first-time feature activation) → rerun
  │
  ├─ B. Features ok, no distro ──► wsl --install -d Debian
  │      ⛔ STOP: first launch in Debian (create your UNIX user) → rerun
  │
  └─ C. Debian ready ──► write .wslconfig ──► wsl --shutdown
         ⛔ HANDOFF: print the exact Debian-phase commands → exit

═══════ containment boundary — everything below runs INSIDE Debian ═══════
[Debian terminal]  (user follows the printed guide)
  1. first launch (native user setup)            ← only if path C said so
  2. cp /mnt/d/.../provision-wsl.sh ~/
  3. bash ~/provision-wsl.sh --upgrade           ← flags carried over
       └─ 13 tasks: inventory → wsl.conf → apt → tools → zsh → Docker
          → DDEV → mkcert → CA → Portainer → PASS/FAIL report
  4. one sudo password prompt, then unattended
```

Windows automation runs in Windows; Linux automation runs in Linux. The
installer never executes anything across the boundary — it only prepares and
prints the exact commands.

### Optional Flags

| Flag | Effect |
|------|--------|
| `-NoUpgrade` | skip the default full base upgrade (speed-first rerun) |
| `-SkipCaImport` | skip importing the mkcert CA into Windows |
| `-Log <file>` | tee the full provisioning transcript to a file (forensics) |
| `-Pause <seconds>` | change the per-task pause (default 5) |

### Notes

- **Debian-only** and **single-distro**: extra or non-Debian distros abort with
  fix-it instructions (`wsl --unregister <name>`).
- Manual steps by design: the Windows restart (first-time feature activation),
  the native Debian first launch (create your UNIX user there), and
  uninstalling Docker Desktop if present (warned by the script).
- Portainer is bound to loopback only: `https://127.0.0.1:9443`.
- Every task prints what it changes; nothing is installed twice (reruns are safe).
- After PASS: `cd ~/projects/<project> && ddev start`, Portainer at
  `https://127.0.0.1:9443`, and new WSL sessions open in zsh.
- If a task FAILs, rerun the script (idempotent) and paste the output for analysis.
- The Windows restart is needed only once, for enabling the WSL features —
  installing a distro never requires one. (`wsl --shutdown` after writing
  `.wslconfig` is not a reboot; it just restarts the WSL VM to apply the config.)

### Verification

`RESULT: PASS` at the end of provisioning is the installer's own success
signal. Deeper, read-only checks — run inside Debian:

```bash
ddev -v                          # DDEV version
docker ps                        # daemon reachable, containers listed
ls ~/.zsh/plugins                # autosuggestions, completions, syntax-highlighting
grep -c zcode-managed ~/.zshrc   # managed block present (1 = ok)
```

… and from Windows (Portainer reachable — no TLS warning: the cert on 9443 is
mkcert-signed and the CA is trusted on Windows; config in place):

```powershell
Get-Content $env:UserProfile\.wslconfig
curl.exe -fsS https://127.0.0.1:9443      # no -k needed - cert is trusted
```

Default distro sanity (after unregister/reinstall cycles):

```powershell
wsl -l -v                     # exact registered names + states
wsl --shutdown                # reset WSL state
wsl --set-default Debian      # fix stale default (verified community order)
```

CA trust (mkcert ↔ Windows browser) — the mkcert-signed cert only helps if
the CA is in the Windows store, and the served cert is the mkcert-signed one
(the provisioning report now checks this). Verify both ends:

```bash
# inside Debian: which cert is served, and signed by whom?
docker inspect portainer --format '{{json .Mounts}}'
openssl s_client -connect 127.0.0.1:9443 </dev/null 2>/dev/null |
  openssl x509 -noout -issuer -ext subjectAltName
```

```powershell
certutil -user -store Root | findstr /i mkcert   # CA in Windows store?
```

Then the padlock test: `https://127.0.0.1:9443` and
`https://<project>.ddev.site` — no warning means the Linux-made CA is trusted
by the Windows browser.

Default distro sanity (after unregister/reinstall cycles — verified cause of
`WSL_E_DISTRO_NOT_FOUND`):

```powershell
wsl -l -v                     # exact registered names + states
wsl --shutdown                # reset WSL state
wsl --set-default Debian      # fix stale default (verified community order)
```

Then restart Windows Terminal — its WSL profiles regenerate from the current
registrations (a stale cached profile gives the same DISTRO_NOT_FOUND).

Any check that fails maps to a stage in [How It Works](#how-it-works) — rerun
the installer for that stage (everything already done is skipped).

Browser note: **Chrome/Edge read the Windows store** — with the CA already
verified there, no manual import is needed (restart the browser if it still
warns). **Firefox uses its own NSS store** — see the next section.

### Troubleshooting

| Symptom | Fix |
|---------|-----|
| `[ABORT] Running as root is not supported` | First launch not completed — follow the printed first-launch steps, then rerun the installer |
| `[FAIL] password verification failed - sudo did not accept it` | Rerun the installer — it offers an in-place password reset for the existing user |
| `permission denied ... docker.sock` at FR-12 | Fixed in the current script — pull the latest `provision-wsl.sh` and rerun |
| Portainer `not a directory` mount error after a WSL restart | Fixed in the current script (certs moved out of `/tmp` to a persistent dir) — rerun the installer; it auto-recreates the container with the certs |
| `WININET_E_CONNECTION_RESET` when downloading the Debian distro | Transient CDN reset — the installer retries, then falls back to `--web-download` (bypasses the Store CDN); also check VPN/proxy. Rerun the installer |
| Browser warning on `https://127.0.0.1:9443` | Diagnose first: `openssl s_client -connect 127.0.0.1:9443 ... -noout -issuer` (see Verification) — issuer = Portainer self-signed → rerun the installer (auto-recreates with the mkcert cert); issuer = your mkcert CA → restart Chrome/Edge (store refresh) |
| CA missing from Windows store (`certutil -user -store Root` shows no mkcert) | Rerun the installer — FR-15 imports it (idempotent) |
| `WSL_E_DISTRO_NOT_FOUND` in the installer or the Windows Terminal Debian profile | Stale default distro / stale WT profile after unregister+reinstall — verified fix order: `wsl --shutdown` → `wsl --set-default Debian` → `wsl -l -v` → restart Windows Terminal (profiles regenerate). The fixed installer also auto-heals a stale default. Note: `wsl --unregister <name>` deletes that distro's filesystem |
| Firefox still warns | Firefox uses its own NSS store — the Windows import doesn't apply; use Chrome/Edge or import rootCA.pem into Firefox |
| Portainer missing | Installed unless `-NoPortainer`; start manually: `docker start portainer` |
| A task FAILs mid-run | Rerun the installer (idempotent — completed stages are skipped) and paste the output |
| Terminal closes at the end of provisioning | By design — the script restarts WSL to apply configuration; reopen with `wsl -d Debian` |

Full real-run bug ledger: [MILESTONE.md](MILESTONE.md) §4.

### mkcert — project-wide local TLS authority

Flow reference: Randy Fay's [DDEV on WSL2 From Scratch](https://www.youtube.com/watch?v=g8cONkiLOdM)
(the video this project's research started from).

### mkcert — project-wide local TLS authority

[Upstream README](https://github.com/FiloSottile/mkcert) (59.9k stars) defines
mkcert as *"a simple zero-config tool to make locally trusted development
certificates with any names you'd like"*. It is **not tied to Portainer** — it
is the project-wide local TLS authority:

- **DDEV** — the primary consumer in this project: DDEV generates its
  per-project SSL certificates via mkcert, so `*.ddev.site` is trusted
  ([docs.ddev.com — Configuring Browsers](https://docs.ddev.com/en/stable/users/install/configuring-browsers)).
  Installed and registered in FR-14, CA trusted on Windows in FR-15.
- **Portainer** — one consumer of a generated certificate (FR-16): the
  self-signed warning on `https://127.0.0.1:9443` is fixed by mounting a
  mkcert-signed cert for `localhost 127.0.0.1`.
- **Any future local service** — follow the same pattern.

#### Reusable pattern — trusted TLS for any local service

Prerequisites: FR-14 (mkcert installed) and FR-15 (CA trusted on Windows)
already ran — both happen before any service stage.

```bash
# 1. Issue a cert for the service's loopback names (CA = the trusted one)
mkcert -cert-file <service>.crt -key-file <service>.key localhost 127.0.0.1
chmod 600 <service>.key

# 2. Configure the service to use the cert + key
#    (each service has its own mechanism — see its documentation)

# 3. Restart the service so it reads the cert

# 4. Verify from Windows: no warning, because the CA is already trusted
curl.exe -k https://127.0.0.1:<port>   # -k optional once CA is trusted
```

Constraints: loopback names only (`localhost`, `127.0.0.1`) — for anything
publicly reachable use a real CA instead. Node.js does not read the system
store: set `NODE_EXTRA_CA_CERTS` to the `rootCA.pem` path if a Node dev server
needs the cert. mkcert is for development machines only, per upstream.

### Firefox — import CA manually (verified steps)

Firefox uses its own NSS store — the Windows `certutil` import doesn't apply
(Chrome/Edge read the Windows store, so they need no manual import). Official
steps ([support.mozilla.org](https://support.mozilla.org/en-US/kb/using-certificate-manager-firefox)):

1. Get the CA file out of Debian (one command, inside Debian):

   ```bash
   cp "$(mkcert -CAROOT)/rootCA.pem" /mnt/c/Users/<windows-user>/Desktop/mkcert-rootCA.pem
   ```

2. Firefox → **Settings → Privacy & Security → Certificates → View
   Certificates → Authorities → Import**
3. Select `mkcert-rootCA.pem` from the Desktop, check **"Trust this CA to
   identify websites"**, OK
4. Restart Firefox, then the padlock test: `https://127.0.0.1:9443` — trusted

Alternative: set the Firefox enterprise policy `ImportEnterpriseRoots = true`
to make Firefox trust the OS store (no manual import), per Mozilla's
documentation.

### Project Files

| File | Role |
|------|------|
| `wsl-setup.ps1` | Windows phase: preflight, features, Debian install, `.wslconfig`, handoff guide |
| `provision-wsl.sh` | Debian phase: 13 provisioning tasks + PASS/FAIL report |
| `wsl-ddev-setup-prd.md` | Requirements contract — FR-01..FR-18, policies, risks |
| `MILESTONE.md` | Context ledger — timeline, real-run bug fixes, design decisions |
| `wslddev.md` | The original manual procedure (source of the flow) |

### Uninstall

Everything lives inside the Debian distro — removing the distro removes it all:

```powershell
wsl --unregister Debian
```

Then delete `%UserProfile%\.wslconfig` if you want the config gone too.
Nothing was installed on the Windows side beyond WSL itself.

### Sources

| Tools | Official source | Method |
|-------|-----------------|--------|
| WSL + Debian distro | learn.microsoft.com/windows/wsl | `wsl --install -d Debian` (built into Windows) |
| Docker CE | docs.docker.com/engine/install/debian | deb822 apt repo keyed by the detected codename |
| DDEV | docs.ddev.com | `ddev.com/install.sh` (download-to-file) |
| Node.js + npm | github.com/nvm-sh/nvm | nvm pinned (`v0.40.3`), then `nvm install --lts` |
| bun | bun.sh/docs/installation | `bun.sh/install` (download-to-file; needs unzip) |
| mkcert | github.com/FiloSottile/mkcert | binary release pinned (`v1.4.4`) + libnss3-tools |
| Portainer CE | docs.portainer.io | image `portainer-ce:latest`, loopback `127.0.0.1:9443` |
| zsh plugins | github.com/zsh-users | autosuggestions `0.7.1` + syntax-highlighting `0.8.0` (pinned tags) |

Version policy: DDEV, Docker CE, and Portainer track latest stable; mkcert,
nvm, and the zsh plugin tags are pinned (supply-chain control); Node.js
follows the current LTS via nvm.

## Appendix

### Semantic Commit Messages

Semantic Commits are standardized commit messages that describe what type of change you're making.

Format: `<type>(<scope>): <subject> <des>`

`<scope>` is optional, but recommended for more detailing

#### Semantic Commit Example

```
feat(feature.html): add feature respect
^--^ ^----------^  ^-----------------^
|    |              |
|    |              +-> Description
|    |
|    +--> Scope
|
+---> Type: (e.g., build, chore, ci, docs, feat, fix, perf, refactor, style, test)
```

More Examples:

- `feat`: New feature. e.g,`feat: add user registration`
- `fix`: Bug fix. e.g,`fix: resolve login timeout`
- `docs`: Documentation. e.g,`docs: update API documentation`
- `style`: Cosmetic changes to the code that do not affect its behavior or functionality formatting. e.g,`style: fix code indentation`
- `refactor`: Rewriting existing code to improve effectivly. e.g,`refactor: simplify auth middleware`
- `test`: e.g,`test: add unit tests for utils`
- `chore`: General Maintenance tasks. e.g,`chore: update dependencies`
- `perf`: Performance improvement. e.g,`perf: optimize database queries`
- `ci` CI/CD. e.g,`ci: add github actions workflow`
- `build` Build system. e.g,`build: update webpack configuration`

References:

- https://www.conventionalcommits.org/
- https://seesparkbox.com/foundry/semantic_commit_messages
- http://karma-runner.github.io/1.0/dev/git-commit-msg.html

### Semantic Versioning

Semantic Versioning is a simple rule system for version numbers: MAJOR.MINOR.PATCH

```
v1.2.3
│   │  └── PATCH: Bug fixes, minor changes
│   └───── MINOR: New features (backward compatible)
└───────── MAJOR: Breaking changes
```

#### Example Versioning Production

```
# Release stable version
v1.0.0    # Initial release
v1.0.1    # Hotfix bug critical
v1.1.0    # Adding New Feature
v2.0.0    # Breaking changes (require migration)
```

#### Example Versioning Production

```
# Pre-release versions, Development
v1.1.0-alpha.1    # Testing internal
v1.1.0-beta.1     # Testing with limited user
v1.1.0-rc.1       # Release candidate
```

#### Branch Structure

```
main/production    → v1.2.3 (stable releases)
develop            → v1.3.0-alpha.1 (development)
feature/auth-jwt   → from development
hotfix/critical-bug → from main
```

## Prerequisites

1. **Git Installed**
2. **Having an Github Account**
3. **Code Editor**

### Installation

#### SSH Setup

   ```bash
    ssh-keygen -t ed25519 -C "emailacc@github.com"
    
    # Start ssh-agent
    eval "$(ssh-agent -s)"

    # Add your key to agent
    ssh-add ~/.ssh/id_ed25519

    # copy your public key and paste it to keys github
    cat ~/.ssh/id_ed25519.pub
   ```

  Check if it works out
  ```bash
  # Check if its still HTTPS 
  git remote -v

  # Change URL remote to SSH Format (Change 'name' with your Github username)
  git remote set-url origin git@github.com:name/repo.git

  # verification if it has changed
  git remote -v
  ```

#### Git Config Setup

1. Open your .gitconfig file on your computer

   On UNIX (MacOs or Linux)

   ```bash
   ~/.gitconfig // On UNIX
   ```

   On Windows

   ```pwsh
   %USERPROFILE%\.gitconfig // On Windows
   ```

2. Paste this to the config like so

   ```bash
    [init]
        defaultBranch = main
    [alias]
        ll = log --graph --oneline
        st = status
        cm = commit -m
        rv = remote -v
        co = checkout
        br = branch -a
        cam = commit --amend -m
        cob = checkout -b
        fap = fetch --all --prune
        brd = branch -D
    [credential "helperselector"]
        selected = manager-core
    [core]
        autocrlf = input
        fileMode = false
        ignorecase = false
   ```

3. Check if its been paste correctly

   ```bash
   git config --global -l
   ```

### Frequently Commands

Clone a Repository

```bash
git clone gacc:owner-repo/repo-name.git
```

Checking Branch including remote branch

```bash
git br
```

Checking Updated from Remote

```bash
git fap
```

Deleting branch

```bash
git brd "name-branch"
```

Push to Remote branch to Github

```bash
git push -u "name-branch"
```

Overwrite push changes to Remote

```bash
git push origin dev --force-with-lease
```

Reset branch to be the same as Targeted Branch

```bash
git reset --hard "name-branch"
```

Coming Back to this `Hash` Safely

```bash
git reset --soft f374fahgs
```

Coming Back to this `Hash` Overwrite / Leaving ondoing Workspace

```bash
git reset --hard f374fahgs
```

Create a branch and switch to that branch

```bash
git cob "name-branch"
```

Amend commit message nor code

```bash
git cam "the message of amend commit"
```

Amend commit message nor code, with history

```bash
git revert "hash-commit"
```

Delete Branch and Push to Remote to snyc

```bash
git push -u origin --delete "name-branch"
```

Abort while merging

```bash
git merge --abort
```

undo git reset --soft

```bash
git reset --soft ORIG_HEAD
```

undo git reset and git reset --hard

```bash
# first method
git reset --hard ORIG_HEAD

# second method, if the first one failed
git reflog
# Seek commit before reset hard, then:
git reset --hard HEAD@{n}
# Or
git reset --hard <commit-hash>
```

Rebase

```bash
git checkout feat.new-feature
git rebase dev
git checkout dev
git reset --hard feat.new-feature
git push --force-with-lease origin dev
```

Rebase Interactive

```bash
# rebase interactive for 3 last commit before HEAD
git rebase -i HEAD~3

# rebase all commit from the start
git rebase -i --root

# if there was conflict
git add .
git rebase --continue

git rebase --abort # or if want to abort
```

Git Stash

```bash
# --u for include untracked
# --a for all (include ignored)
git stash save "name"

git stash list

git stash pop # to pop up the stashed stuff
```

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".
Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b dev/example`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin dev/example`)
5. Open a Pull Request

## License

Distributed under the project_license. See `LICENSE.txt` for more information.

<a href="https://github.com/Rayfess/blajar-Git/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=Rayfess/blajar-Git" alt="contrib.rocks image" />
</a>

[contributors-shield]: https://img.shields.io/github/contributors/Rayfess/blajar-Git.svg?style=for-the-badge
[contributors-url]: https://github.com/Rayfess/blajar-Git/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/Rayfess/blajar-Git.svg?style=for-the-badge
[forks-url]: https://github.com/Rayfess/blajar-Git/network/members
[stars-shield]: https://img.shields.io/github/stars/Rayfess/blajar-Git.svg?style=for-the-badge
[stars-url]: https://github.com/Rayfess/blajar-Git/stargazers
[issues-shield]: https://img.shields.io/github/issues/Rayfess/blajar-Git.svg?style=for-the-badge
[issues-url]: https://github.com/Rayfess/blajar-Git/issues
[license-shield]: https://img.shields.io/github/license/Rayfess/blajar-Git.svg?style=for-the-badge
[license-url]: https://github.com/Rayfess/blajar-Git/blob/master/LICENSE.txt
