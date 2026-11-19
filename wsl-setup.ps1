<#
wsl-setup.ps1 - Windows side of the WSL2 + DDEV setup automation.
Implements FR-01..FR-04 of wsl-ddev-setup-prd.md (repository root).
Supported distro (PRD): Debian >= 12 ONLY; exactly ONE WSL
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
function Write-Info([string]$Msg)  { Write-Host "  $Msg" -ForegroundColor White }
function Write-Ok([string]$Msg)    { Write-Host "  [OK] $Msg" -ForegroundColor Green }
function Write-WarnLine([string]$Msg) { Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-FailLine([string]$Msg) { Write-Host "  [FAIL] $Msg" -ForegroundColor Red }

# --- run/stage progress tracking (UX feedback) ---
$script:RunStart = Get-Date
$script:StageTotal = 4   # Branch 1: preflight -> decision -> config -> chain; gates use 3
$script:StageIndex = 0
$script:StageSw = $null
function Write-Stage([string]$Name) {
    $script:StageIndex++
    $script:StageSw = [System.Diagnostics.Stopwatch]::StartNew()
    $pct = [int](($script:StageIndex - 1) * 100 / $script:StageTotal)
    $filled = [int](26 * ($script:StageIndex - 1) / $script:StageTotal)
    $bar = ('#' * $filled) + ('-' * (26 - $filled))
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor DarkGray
    Write-Host ("[STAGE {0}/{1}] {2}" -f $script:StageIndex, $script:StageTotal, $Name) -ForegroundColor Cyan
    Write-Host ("  progress [{0}] {1}% | started {2}" -f $bar, $pct, (Get-Date -Format 'HH:mm:ss')) -ForegroundColor DarkGray
    Write-Host "------------------------------------------------------------------" -ForegroundColor DarkGray
}
function Complete-Stage([string]$Note) {
    $script:StageSw.Stop()
    $pct = [int]($script:StageIndex * 100 / $script:StageTotal)
    $filled = [int](26 * $script:StageIndex / $script:StageTotal)
    $bar = ('#' * $filled) + ('-' * (26 - $filled))
    $totalElapsed = [int]((Get-Date) - $script:RunStart).TotalSeconds
    Write-Host ("  --- stage completed: {0} | took {1:n1}s | [{2}] {3}% | run elapsed {4}s ---" -f $Note, $script:StageSw.Elapsed.TotalSeconds, $bar, $pct, $totalElapsed) -ForegroundColor DarkGray
}

function Invoke-Wsl([string]$Arguments) {
    # PS 5.1 quirk (real-run erlog.txt case): with $ErrorActionPreference='Stop',
    # stderr lines from native commands become terminating errors even when
    # redirected. Merge streams via cmd and run with 'Continue' so native
    # warnings (e.g. the experimental Sparse VHD notice) never kill the run.
    $eap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & cmd.exe /c "wsl.exe $Arguments 2>&1" }
    finally { $ErrorActionPreference = $eap }
}

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
Write-Stage "FR-01 Windows preflight"

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
$v = Invoke-Wsl '--version'
if ($LASTEXITCODE -eq 0) { $wslVersionLine = Clean-WslOutput $v | Select-Object -First 1 }
if ($wslVersionLine) { Write-Info "WSL: $wslVersionLine" }
else { Write-Info "WSL: version unavailable (old/inbox WSL or not installed)" }

$distroList = @()
$raw = Invoke-Wsl '--list --quiet'
if ($LASTEXITCODE -eq 0) { $distroList = Clean-WslOutput $raw }
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
    if ($distro -notmatch 'Debian') {
        # Debian-only (PRD): abort instead of provisioning the wrong distro.
        Write-FailLine "This automation is Debian-only. Installed distro: '$distro'."
        Write-Info "Switch:  wsl --unregister '$distro'   then   wsl --install -d Debian   and rerun."
        exit 1
    }
    Write-Stage ("FR-02 Branch 1: distro '{0}' validated (Debian)" -f $distro)
    Complete-Stage "single-distro rule satisfied"

    # FR-03 - write .wslconfig (doc-exact, wslddev.md lines 36-48)
    $marker = '# managed by wsl-setup.ps1 (wsl-ddev-setup-prd.md) - doc-exact values from wslddev.md'
    $config = @"
[wsl2]
processors=6
memory=10GB
swap=1GB

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

    Write-Stage "FR-03 apply .wslconfig (wsl --shutdown)"
    Write-WarnLine "wsl --shutdown stops ALL running WSL distros and sessions - save work in open WSL terminals first."
    Start-Sleep -Seconds 3
    Invoke-Wsl '--shutdown'
    Write-Info "WSL shut down - next start uses the new .wslconfig"
    Complete-Stage "config applied - WSL shut down"

    if ($capWarn) {
        # Forward FR-04 warning to the Linux final report (documented WSLENV mechanism).
        # Append to the user's existing WSLENV instead of overwriting it.
        $env:WSL_SETUP_CAP_WARNING = '1'
        $env:WSLENV = if ($env:WSLENV) { "$($env:WSLENV):WSL_SETUP_CAP_WARNING" } else { 'WSL_SETUP_CAP_WARNING' }
    }

    $linuxScript = Convert-To-LinuxPath (Join-Path $PSScriptRoot 'provision-wsl.sh')
    $flags = @()
    if ($Upgrade) { $flags += '--upgrade' }
    if ($SkipCaImport) { $flags += '--skip-ca-import' }
    if ($WithZshCompletions) { $flags += '--with-zsh-completions' }
    if ($Pause -ne 5) { $flags += @('--pause', "$Pause") }

    Write-Host ""
    Write-Info "Chaining into Linux provisioning. After ONE sudo password prompt it runs unattended."
    # Default-user gate: a distro without a completed first launch runs as root.
    # Best practice (verified): create the UNIX user non-interactively here with
    # credentials chosen by the user in PowerShell - the root account stays
    # password-locked (WSL '-u root' ignores Linux passwords, so a root password
    # would provide no protection while a public default would be a known
    # credential). Then chain as the new user - no manual Debian launch.
    $defaultUser = (Invoke-Wsl "-d $distro -e id -un" | Clean-WslOutput | Select-Object -First 1)
    if (-not $defaultUser -or $defaultUser -eq 'root') {
        Write-WarnLine "Debian default user is root (first launch not completed) - creating your UNIX user now."
        do {
            $unixUser = (Read-Host "Choose a UNIX username (lowercase, no spaces)").Trim()
        } until ($unixUser -match '^[a-z_][a-z0-9_-]{0,31}$' -and $unixUser -ne 'root')
        do {
            $sec = Read-Host "Choose a password (min 6 chars - used for sudo during provisioning)" -AsSecureString
            $sec2 = Read-Host "Confirm password" -AsSecureString
            $b1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
            $b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec2)
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b1)
            $plain2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b2)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b1)
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2)
        if ($plain.Length -lt 6 -or $plain -cne $plain2 -or $plain -notmatch '^[\x20-\x7E]+$') {
            Write-WarnLine "password invalid: min 6 chars, both entries must match, printable ASCII only - try again."
        }
    } until ($plain.Length -ge 6 -and $plain -ceq $plain2 -and $plain -match '^[\x20-\x7E]+$')
        Write-Info "Creating UNIX user '$unixUser' (home, sudo group, bash)..."
        # (password must stay printable ASCII - it crosses stdin via ASCII encoding)
        Invoke-Wsl "-d $distro -u root -- useradd -m -G sudo -s /bin/bash $unixUser"
        if ($LASTEXITCODE -ne 0) {
            Write-FailLine "useradd failed (exit $LASTEXITCODE) - username may already exist."
            Complete-Stage "blocked: user creation failed"
            exit 1
        }
        # Password delivery (real-run bug fixed): piping into `cmd /c "wsl ...
        # chpasswd"` lost stdin, so chpasswd exited 0 WITHOUT setting anything
        # and sudo later rejected every attempt. Write the credential to a temp
        # file (UTF-8, no BOM) and pipe it straight into wsl.exe - no cmd layer.
        $credFile = Join-Path $env:TEMP ('wsl-cred-' + [guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($credFile, "$unixUser`:$plain`n")
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        Get-Content $credFile | & wsl.exe -d $distro -u root -- chpasswd 2>&1
        $ErrorActionPreference = $eap
        Remove-Item $credFile -ErrorAction SilentlyContinue
        # Positive verification: sudo -S must accept the password and echo the
        # user. This is the safety net that would have caught the erlog bug.
        $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        $sudoCheck = ("$plain" | & wsl.exe -d $distro -e sudo -S -k id -un 2>&1 | Clean-WslOutput | Select-Object -Last 1)
        $ErrorActionPreference = $eap
        if ($sudoCheck -ne $unixUser) {
            Write-FailLine "password verification failed - sudo did not accept it (got: '$sudoCheck')."
            Write-Info "reset manually if needed: wsl -d $distro -u root -- bash -c `"passwd $unixUser`""
            Complete-Stage "blocked: password verification failed"
            exit 1
        }
        Write-Ok "password verified - sudo accepts it."
        Write-Ok "UNIX user '$unixUser' created with your password."
        Invoke-Wsl "--manage $distro --set-default-user $unixUser"
        if ($LASTEXITCODE -ne 0) {
            # Fallback: registry DefaultUid (works on any WSL version)
            $uidLine = (Invoke-Wsl "-d $distro -u root -- id -u $unixUser" | Clean-WslOutput | Select-Object -First 1)
            $guid = $null
            foreach ($k in (Get-ChildItem 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue)) {
                $n = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).DistributionName
                if ($n -eq $distro) { $guid = $k.PSPath; break }
            }
            if ($guid -and $uidLine) {
                Set-ItemProperty -Path $guid -Name DefaultUid -Value ([int]$uidLine)
                Write-Info "Default user set via registry (fallback)."
            } else {
                Write-WarnLine "could not set default user automatically - run: wsl --manage $distro --set-default-user $unixUser"
            }
        }
        $defaultUser = $unixUser
        Invoke-Wsl "-t $distro"   # terminate the distro so the next launch reads the new default user
    }
    Write-Ok "Default WSL user: $defaultUser"
    Write-Stage ("Chain: wsl -d {0} -e bash {1}" -f $distro, $linuxScript)
    Invoke-Wsl "-d $distro -e bash $linuxScript $($flags -join ' ')"
    if ($LASTEXITCODE -eq 0) {
        Complete-Stage "Linux provisioning finished - RESULT: PASS above"
    } else {
        Write-FailLine "Linux provisioning FAILED (exit $LASTEXITCODE) - read the [ABORT]/[FAIL] lines above, fix, then rerun."
        Complete-Stage "provisioning failed - see error above"
    }
    exit $LASTEXITCODE
}
elseif ($featureEnabled) {
    # ---- Branch 3: feature present, no distro -> install Debian directly --
    $script:StageTotal = 3
    Write-Stage "FR-02 Branch 3: WSL feature enabled, no distro installed"
    Write-Info "Debian-only automation (PRD): installing Debian, no distro picker."
    Write-Info "Installing: wsl --install -d Debian --no-launch"
    Invoke-Wsl '--install -d Debian --no-launch'
    if ($LASTEXITCODE -ne 0) {
        Write-WarnLine "--no-launch not supported here; running plain wsl --install -d Debian"
        Invoke-Wsl '--install -d Debian'
    }
    Complete-Stage "Debian installed - rerun to create your UNIX user and chain"
    Write-Host ""
    Write-Host "[NEXT STEP]" -ForegroundColor Yellow
    Write-Host "  1. Run this script again (same command)."
    Write-Host "  2. It will ask for your UNIX username and password (in PowerShell),"
    Write-Host "     then chain into provisioning automatically. No manual Debian launch."
    exit 0
}
else {
    # ---- Branch 2: feature absent -> enable + restart gate ---------------
    $script:StageTotal = 3
    Write-Stage "FR-02 Branch 2: WSL feature not enabled, no distro installed"
    Write-Info "Running: wsl --install -d Debian --no-launch - one command, two effects:"
    Write-Info "  1. enables Windows features (Microsoft-Windows-Subsystem-Linux + VirtualMachinePlatform) -> RESTART required, first-time only"
    Write-Info "  2. unpacks the Debian distro -> the distro itself never needs a restart"
    Invoke-Wsl '--install -d Debian --no-launch'
    if ($LASTEXITCODE -ne 0) {
        Write-WarnLine "--no-launch not supported here; running plain wsl --install -d Debian"
        Invoke-Wsl '--install -d Debian'
    }
    Complete-Stage "WSL feature installed - restart required, then rerun"
    Write-Host ""
    Write-Host "[RESTART REQUIRED]" -ForegroundColor Yellow
    Write-Host "  This restart is for the Windows features only (first-time activation) -"
    Write-Host "  the Debian distro itself never needs one."
    Write-Host "  1. Restart Windows to finish enabling the WSL features."
    Write-Host "  2. Run this script again (same command) - the distro is already unpacked,"
    Write-Host "     so it goes straight to the default-user gate, then provisioning."
    exit 0
}
