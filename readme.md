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

#### Powershell Setup

1. Create $PROFILE Files For Powershell

   ```pwsh
   New-Item -Path $PROFILE -Type File -Force
   ```

2. On $PROFILE Files Copy This

   ```pwsh
   #GitAcc
   function gacc1 {
    git config --global user.name "your-github-username"
    git config --global user.email "your-github-email"
    Write-Host "✓ Using Account 1" -ForegroundColor Green
   }


    # Optional if you want 2 account in your workspace
    # function gacc2 {
    # git config --global user.name "your-github-username"
    # git config --global user.email "your-github-email"
    # Write-Host "✓ Using Account 1" -ForegroundColor Green
    # }

    # try to test it, shorthand for git config user.name/email
    function gashow {
    Write-Host "Git Config:" -ForegroundColor Cyan
    Write-Host "Name: $(git config user.name)"
    Write-Host "Email: $(git config user.email)"
    }
   ```

#### SSH Setup

1. Make SSH Config File

   ```bash
   mkdir -p ~/.ssh
   nano ~/.ssh/config
   ```

2. While on Nano Paste This

   ```bash
   # ~/.ssh/config on Nano
   # Generate SSH keys for each account
   ssh-keygen -t ed25519 -C "account1@email.com" -f ~/.ssh/id_ed25519_acc1

   #optional if want to make 2 account on github
   # ssh-keygen -t ed25519 -C "account2@email.com" -f ~/.ssh/id_ed25519_acc2

   # Add to SSH config (~/.ssh/config)
   Host github-acc1
       HostName github.com
       User git
       IdentityFile ~/.ssh/id_ed25519_acc1

   Host github-acc2
       HostName github.com
       User git
       IdentityFile ~/.ssh/id_ed25519_acc2
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
   [user]
   	name = example
   	email = 632486264+username@users.noreply.github.com
   [credential]
   	helper = store
   [init]
   	defaultBranch = main
   [alias]
   alias.st=status
   alias.ll=log --graph --oneline
   alias.last=log -1 HEAD --stat
   alias.cm=commit -m
   alias.rv=remote -v
   alias.co=checkout
   alias.br=branch -a
   alias.cam=commit --amend -m
   alias.cob=checkout -b
   alias.fap=fetch --all --prune
   alias.brd=branch -D
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
