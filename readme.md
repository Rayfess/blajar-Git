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
    </li>
    <li><a href="#usage">Usage</a></li>
    <li><a href="#contributing">Contributing</a></li>
    <li><a href="#license">License</a></li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->

## About The Project

In this project were introducing the basic and to advanced guide to use github and git commands effectively

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- PREQUISTIES -->

## Prerequisites

- Installing Git
- Having an Github Account
- Code Editor

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

    #Alias
    Set-Alias g git
    function glog { git log --graph --oneline}
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

#### Verify It and Test Your Connection

```bash
ssh -T git@github-acc1
ssh -T git@github-acc2
```

## Usage

#### Clone a Repository

```bash
g clone gacc2:Rayfess/blajar-Git.git
```

#### `glog` is Shortcut for `git log`

```bash
glog
```

#### `g` is Shortcut for `github`

```bash
g -nextcommand
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

## Frequently Usage

### Checking Branch including remote branch

```bash
g branch -a
```

### Checking Updated from Remote

```bash
g fetch --all --prune
```

### Deleting Branch

```bash
g branch -D "name-branch"
```

### Push to Remote Branch to Github

```bash
g push -u "name-branch"
```

### Amend commit message nor code

```bash
g commit -amend
```

### Creating branch and change it to

```bash
g checkout -b "name-branch"
```

### Reset branch

```bash
g reset --hard "name-branch"
```

### Amend commit message nor code, with history

```bash
g revert "hash-commit"
```

### Push Delete to the origin remote

```bash
g push -u origin --delete "name-branch"
```

### Abort while merging

```bash
g merge --abort
```

### Clonning but with ssh account

```bash
g clone gacc#:owner-repo/repo.git
```

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- CONTRIBUTING -->

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please fork the repo and create a pull request. You can also simply open an issue with the tag "enhancement".
Don't forget to give the project a star! Thanks again!

1. Fork the Project
2. Create your Feature Branch (`git checkout -b dev/example`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin dev/example`)
5. Open a Pull Request

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- LICENSE -->

## License

Distributed under the project_license. See `LICENSE.txt` for more information.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

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
