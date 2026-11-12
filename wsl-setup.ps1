<#
wsl-setup.ps1 - Windows side of the WSL2 + DDEV setup automation.
Implements FR-01..FR-04 of wsl-ddev-setup-prd.md (repository root).
Supported distros (PRD): Debian >= 12, Fedora >= 42; exactly ONE WSL
distro may be installed (single-distro rule, FR-02 Branch 1).

Run elevated:
    powershell -ExecutionPolicy Bypass -File wsl-setup.ps1

Optional switches (forwarded to provision-wsl.sh in Branch 1):
    -Upgrade              -> --upgrade               (apt upgrade, FR-07)
    -SkipCaImport         -> --skip-ca-import        (FR-15)
    -WithZshCompletions   -> --with-zsh-completions  (FR-09 opt-in)
    -Pause <seconds>      -> --pause <seconds>       (FR-17, default 5)
#>
[CmdletBinding()]
param(
    [switch]$Upgrade,
    [switch]$SkipCaImport,
    [switch]$WithZshCompletions,
    [int]$Pause = 5
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Title) {
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}
function Write-Info([string]$Msg)  { Write-Host "  $Msg" }
function Write-WarnLine([string]$Msg) { Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-FailLine([string]$Msg) { Write-Host "  [FAIL] $Msg" -ForegroundColor Red }

function Convert-To-LinuxPath([string]$WinPath) {
    $drive = $WinPath.Substring(0, 1).ToLower()
    $rest = $WinPath.Substring(2) -replace '\\', '/'
    return "/mnt/$drive$rest"
}

function Clean-WslOutput($Lines) {
    # wsl.exe emits UTF-16LE; PowerShell 5.1 decodes it with stray NUL chars.
    return @($Lines | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ -ne '' })
}

function Get-DefaultDistro {
    $lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    if (-not (Test-Path $lxss)) { return $null }
    $root = Get-ItemProperty -Path $lxss -ErrorAction SilentlyContinue
    if (-not $root -or -not $root.DefaultDistribution) { return $null }
    $guid = '{' + ($root.DefaultDistribution -replace '[{}]', '') + '}'
    $sub = Get-ItemProperty -Path (Join-Path $lxss $guid) -ErrorAction SilentlyContinue
    if ($sub) { return $sub.DistributionName }
    return $null
}

# ---------------------------------------------------------------------------
# FR-01 - Windows preflight
# ---------------------------------------------------------------------------
Write-Step "FR-01 Windows preflight"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-FailLine "Not elevated. Run as Administrator:"
    Write-Host '    powershell -ExecutionPolicy Bypass -File wsl-setup.ps1' -ForegroundColor Red
    exit 1
}
Write-Info "Elevated: yes"

if (-not $PSScriptRoot) {
    Write-FailLine "Run with -File (a script path is required), not pasted into a console."
    exit 1
}

$cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$build = [int]$cv.CurrentBuild
Write-Info ("Windows build: {0} ({1})" -f $build, $cv.DisplayVersion)

$wslVersionLine = $null
try {
    $v = (& wsl.exe --version 2>$null)
    if ($LASTEXITCODE -eq 0) { $wslVersionLine = Clean-WslOutput $v | Select-Object -First 1 }
} catch { }
if ($wslVersionLine) { Write-Info "WSL: $wslVersionLine" }
else { Write-Info "WSL: version unavailable (old/inbox WSL or not installed)" }

$distroList = @()
try {
    $raw = (& wsl.exe --list --quiet 2>$null)
    if ($LASTEXITCODE -eq 0) { $distroList = Clean-WslOutput $raw }
} catch { }
if ($distroList.Count -gt 0) { Write-Info ("Distros: " + ($distroList -join ', ')) }
else { Write-Info "Distros: none installed" }

# FR-04 - capability warnings (forwarded to the Linux final report via WSLENV)
$capWarn = $false
if ($build -lt 22621) {
    Write-WarnLine "Windows build < 22621 (Win11 22H2): networkingMode=Mirrored and nestedVirtualization are NOT supported; documented .wslconfig values will be silently ignored by WSL."
    $capWarn = $true
}
if ($wslVersionLine -and ($wslVersionLine -match '(\d+\.\d+(\.\d+)?)')) {
    $wslVer = [version]$Matches[1]
    if ($wslVer -lt [version]'2.0.0') {
        Write-WarnLine ("WSL version {0} < 2.0: systemd, autoProxy and sparseVhd are not supported." -f $wslVer)
        $capWarn = $true
    }
}

$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Write-Info ("Physical RAM: {0} GB" -f $ramGB)
if ($ramGB -lt 10) {
    Write-WarnLine "RAM is below the documented memory=10GB; WSL may fail to boot with that reservation. Edit .wslconfig after this run if needed."
}

$ddExe = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
$ddReg = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like '*Docker Desktop*' }
if ((Test-Path $ddExe) -or $ddReg) {
    Write-WarnLine "Docker Desktop detected: Docker docs require removing it before installing Docker CE inside WSL."
}

try {
    $featWsl = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux).State
    $featVmp = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State
} catch {
    $featWsl = 'Unknown'
    $featVmp = 'Unknown'
}
Write-Info ("WSL feature: {0} | VirtualMachinePlatform: {1}" -f $featWsl, $featVmp)
$featureEnabled = (($featWsl -eq 'Enabled') -and ($featVmp -eq 'Enabled'))

# ---------------------------------------------------------------------------
# FR-02 - distro decision tree
# ---------------------------------------------------------------------------
if ($distroList.Count -gt 0) {
    # ---- Branch 1: distro installed -> write config + chain provisioning -
    if ($distroList.Count -gt 1) {
        # Single-distro rule (PRD): exactly one WSL distro may be installed.
        Write-FailLine "Single-distro rule: exactly one WSL distro may be installed. Found:"
        $distroList | ForEach-Object { Write-Host "    - $_" }
        Write-Info "Remove the unwanted ones (this deletes their filesystem):  wsl --unregister <name>"
        exit 1
    }
    $distro = Get-DefaultDistro
    if (-not $distro) { $distro = $distroList[0] }
    Write-Step ("FR-02 Branch 1: distro '{0}' installed" -f $distro)

    # FR-03 - write .wslconfig (doc-exact, wslddev.md lines 36-48)
    $marker = '# managed by wsl-setup.ps1 (wsl-ddev-setup-prd.md) - doc-exact values from wslddev.md'
    $config = @"
[wsl2]
processors=6
memory=10GB
swap=4GB

nestedVirtualization=true
networkingMode=Mirrored
autoProxy=false

[experimental]
sparseVhd=true
"@
    $wslconfigPath = Join-Path $env:UserProfile '.wslconfig'
    $existing = $null
    if (Test-Path $wslconfigPath) { $existing = Get-Content $wslconfigPath -Raw }
    $isOurs = ($existing -and $existing.Contains('managed by wsl-setup.ps1'))
    if ($existing -and (-not $isOurs) -and ($existing.Trim() -ne $config.Trim())) {
        $bak = "$wslconfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $wslconfigPath $bak
        Write-Info "Backed up existing .wslconfig -> $bak"
    }
    Set-Content -Path $wslconfigPath -Value ($marker + "`r`n`r`n" + $config + "`r`n") -Encoding ASCII
    Write-Info "Wrote $wslconfigPath :"
    Get-Content $wslconfigPath | ForEach-Object { Write-Host "    $_" }

    Write-Step "FR-03 apply: wsl --shutdown"
    & wsl.exe --shutdown 2>$null
    Write-Info "WSL shut down - next start uses the new .wslconfig"

    if ($capWarn) {
        # Forward FR-04 warning to the Linux final report (documented WSLENV mechanism).
        $env:WSL_SETUP_CAP_WARNING = '1'
        $env:WSLENV = 'WSL_SETUP_CAP_WARNING'
    }

    $linuxScript = Convert-To-LinuxPath (Join-Path $PSScriptRoot 'provision-wsl.sh')
    $flags = @()
    if ($Upgrade) { $flags += '--upgrade' }
    if ($SkipCaImport) { $flags += '--skip-ca-import' }
    if ($WithZshCompletions) { $flags += '--with-zsh-completions' }
    if ($Pause -ne 5) { $flags += @('--pause', "$Pause") }

    Write-Host ""
    Write-Info "Chaining into Linux provisioning. After ONE sudo password prompt it runs unattended."
    Write-Step ("Chain: wsl -d {0} -e bash {1} {2}" -f $distro, $linuxScript, ($flags -join ' '))
    & wsl.exe -d $distro -e bash $linuxScript @flags
    exit $LASTEXITCODE
}
elseif ($featureEnabled) {
    # ---- Branch 3: feature present, no distro -> pick + install ----------
    Write-Step "FR-02 Branch 3: WSL feature enabled, no distro installed"

    $online = @()
    try {
        $raw = (& wsl.exe --list --online 2>$null)
        if ($LASTEXITCODE -eq 0) { $online = Clean-WslOutput $raw }
    } catch { }

    $names = @()
    $sepSeen = $false
    foreach ($line in $online) {
        if (-not $sepSeen) {
            if ($line -match '^-{3,}') { $sepSeen = $true }
            continue
        }
        $tok = ($line.Trim() -split '\s+')[0]
        if ($tok -and $tok -ne 'NAME') { $names += $tok }
    }
    # Supported distros only (PRD): Debian and Fedora
    $names = @($names | Where-Object { $_ -match '^(Debian|Fedora)' })
    if ($names.Count -eq 0) {
        Write-FailLine "No supported distros (Debian/Fedora) found in 'wsl --list --online'. Check connectivity, update Windows/WSL, or install one manually, then rerun."
        exit 1
    }
    for ($i = 0; $i -lt $names.Count; $i++) {
        Write-Host ("  [{0}] {1}" -f ($i + 1), $names[$i])
    }
    $pick = Read-Host "Pick a distro by number (1-$($names.Count))"
    $idx = 0
    if (-not [int]::TryParse($pick, [ref]$idx) -or $idx -lt 1 -or $idx -gt $names.Count) {
        Write-FailLine "Invalid selection: '$pick'"
        exit 1
    }
    $selection = $names[$idx - 1]
    Write-Info "Installing: wsl --install -d $selection --no-launch"
    & wsl.exe --install -d $selection --no-launch 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-WarnLine "--no-launch not supported here; running plain wsl --install -d $selection"
        & wsl.exe --install -d $selection
    }
    Write-Host ""
    Write-Host "[FIRST LAUNCH REQUIRED]" -ForegroundColor Yellow
    Write-Host "  1. Open the distro first launch:  wsl -d $selection   (or Start menu -> $selection)"
    Write-Host "  2. Create your UNIX username and password when prompted."
    Write-Host "  3. Run this script again - it will write .wslconfig and chain into provisioning."
    exit 0
}
else {
    # ---- Branch 2: feature absent -> enable + restart gate ---------------
    Write-Step "FR-02 Branch 2: WSL feature not enabled, no distro installed"
    Write-Info "Running: wsl --install --no-launch (enables WSL + VirtualMachinePlatform features)"
    & wsl.exe --install --no-launch 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-WarnLine "--no-launch not supported here; running plain wsl --install"
        & wsl.exe --install
    }
    Write-Host ""
    Write-Host "[RESTART REQUIRED]" -ForegroundColor Yellow
    Write-Host "  1. Restart Windows to finish enabling the WSL features."
    Write-Host "  2. Run this script again (same command) - it will offer the distro list."
    exit 0
}
