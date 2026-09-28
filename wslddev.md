# Documentation of DDEV WSL2 Integration

setup linux envirovment using wsl and integrate it with ddev containerization of docker

## Table of Contents

- [1. Introduction](#1-introduction)
- [2. Getting Started](#2-getting-started)
  - [2.1 Configuration](#21-configuration)
    - [A. Configuration on Windows](#a-configuration-on-windows)
    - [B. Configuration on Linux](#b-configuration-on-linux)
    - [C. Additionals](#c-additionals)
- [3. Installation](#3-installation)
- [4. Usage](#4-usage)

## 1. Introduction

This Setup (full development on linux + docker, Windows for UI purposes) is the absolute industry standart for Developers. Majority of seniors developers, even tools documentation recommend users to migrate native Windows toolchains to Linux Environment

"We recommend using WSL".

## 2. Getting Started

## 2.1 Configuration

### A. Configuration on Windows

do Win + R and run this to find config file

```pwsh
.wslconfig
```

Paste this

```pwsh
[wsl2]
processors=6
memory=10GB
swap=4GB

nestedVirtualization=true
networkingMode=Mirrored
autoProxy=false

[experimental]
sparseVhd=true
```

### B. Configuration on Linux

find or create the config file

```bash
sudo nano /etc/wsl.conf
```

Paste this

```bash
[boot]
systemd=true

[interop]
enabled=true
appendWindowsPath=false

[network]
generateHosts=true
generateResolvConf=true

[automount]
enabled=true
options="metadata,umask=22"

```

### C. Additionals

Migrate Projects from Windows to WSL

```bash
cd ~/projects/your-migrate-project
rsync -av --progress --exclude='node_modules' --exclude='dist' /mnt/c/Users/nameUser/path/to/yourprojects/ ./
npm i
```
Add SSL Cerficate using mkcert

```bash
mkcert -install
```

## 3. Installation

Init update upgrade checkup and basic tools on linux wsl2

```bash
sudo apt update && sudo apt upgrade && apt install curl -y
```

Important Init installment for docker

```bash
# starts uninstalling conflicting packages for docker
sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc docker-buildx podman-docker containerd runc | cut -f1)

# Add Docker's official GPG key:
sudo apt update
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
```

Installing docker packages

```bash
sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Check docker is it installed properly

```bash
sudo docker run hello-world
```

Install DDEV with script

```bash
curl -fsSL https://ddev.com/install.sh | bash

# check the version
ddev -v
```

Install Portainer for GUI

```bash
# Install Portainer on WSL2
docker volume create portainer_data
docker run -d -p 9443:9443 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:latest
```

## 4. Usage

Stop Docker services

```bash
# 1. Stopping daemon Docker that's running
sudo systemctl stop docker

# 2. Stopping auto restart daemon
sudo systemctl stop docker.socket
```

See Active Container

```bash
ddev describe
```

Starts DDEV development

```bash
sudo systemctl start docker

cd ~/projects/project-name
ddev start

# starts creating container for laravel development
ddev config --project-type=laravel --docroot=public

# install laravel via composer
ddev composer create-project laravel/laravel

```
