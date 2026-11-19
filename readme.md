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
[wsl-ddev-setup-prd.md](wsl-ddev-setup-prd.md).

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
     choose your UNIX username/password **in PowerShell** (no manual Debian
     launch) → provisioning chains automatically
   - Debian installed → writes `.wslconfig` → chains Linux provisioning
     automatically

4. Enter the **sudo password once**; provisioning runs unattended
   (13 tasks, 5-second pause each) and ends with a PASS/FAIL status report.

### Optional Flags

| Flag | Effect |
|------|--------|
| `-Upgrade` | full `apt upgrade` during provisioning |
| `-SkipCaImport` | skip importing the mkcert CA into Windows |
| `-WithZshCompletions` | install the opt-in zsh-completions plugin |
| `-Pause <seconds>` | change the per-task pause (default 5) |

### Notes

- **Debian-only** and **single-distro**: extra or non-Debian distros abort with
  fix-it instructions (`wsl --unregister <name>`).
- Manual steps by design: the Windows restart (first-time feature activation)
  and uninstalling Docker Desktop if present (warned by the script). The UNIX
  user is created automatically — you only choose its username and password
  when prompted in PowerShell.
- Portainer is bound to loopback only: `https://127.0.0.1:9443`.
- Every task prints what it changes; nothing is installed twice (reruns are safe).
- After PASS: `cd ~/projects/<project> && ddev start`, Portainer at
  `https://127.0.0.1:9443`, and new WSL sessions open in zsh.
- If a task FAILs, rerun the script (idempotent) and paste the output for analysis.
- The Windows restart is needed only once, for enabling the WSL features —
  installing a distro never requires one. (`wsl --shutdown` after writing
  `.wslconfig` is not a reboot; it just restarts the WSL VM to apply the config.)

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
