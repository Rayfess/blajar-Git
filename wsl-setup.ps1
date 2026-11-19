<#
wsl-setup.ps1 - Windows side of the WSL2 + DDEV setup automation.
Implements FR-01..FR-04 of wsl-ddev-setup-prd.md (repository root).
Supported distro (PRD): Debian >= 12 ONLY; exactly ONE WSL
distro may be installed (single-distro rule, FR-02 Branch 1).

Run elevated:
    powershell -ExecutionPolicy Bypass -File wsl-setup.ps1

Optional switches (forwarded to provision-wsl.sh in Branch 1):
    -NoUpgrade            -> --no-upgrade            (skip the default base upgrade, FR-07)
    -SkipCaImport         -> --skip-ca-import        (FR-15)
    -Log <file>           -> --log <file>            (full transcript, forensics)
    -Pause <seconds>      -> --pause <seconds>       (FR-17, default 5)
#>
[CmdletBinding()]
param(
    [switch]$NoUpgrade,
    [switch]$SkipCaImport,
    [string]$Log,
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
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor DarkGray
    Write-Host ("[STAGE {0}/{1}] {2}" -f $script:StageIndex, $script:StageTotal, $Name) -ForegroundColor Cyan
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
    if (-not $distro -or ($distroList -notcontains $distro)) {
        # Stale default distro (verified real-run bug): the registry
        # DefaultDistribution GUID can point to an unregistered distro after
        # unregister/reinstall cycles - 'wsl -d <stale>' then fails with
        # WSL_E_DISTRO_NOT_FOUND while the real distro works fine. Heal it.
        Write-WarnLine "Default distribution '$distro' is stale/unregistered - healing: wsl --set-default <first registered distro>"
        Invoke-Wsl "--set-default $($distroList[0])"
        $distro = $distroList[0]
    }
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
hostAddressLoopback=true
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
    if ($NoUpgrade) { $flags += '--no-upgrade' }
    if ($SkipCaImport) { $flags += '--skip-ca-import' }
    if ($Log) { $flags += @('--log', (Convert-To-LinuxPath $Log)) }
    if ($Pause -ne 5) { $flags += @('--pause', "$Pause") }

    Write-Host ""
    Write-Info "Windows phase complete. The Linux phase runs inside Debian - containment: nothing executes across the boundary."
    # Default-user gate: a distro without a completed first launch runs as root.
    # The native, documented flow applies (learn.microsoft.com/windows/wsl:
    # "Once you have installed WSL, you will need to create a user account and
    # password for your newly installed Linux distribution") - the first launch
    # of the distro opens its own setup and asks for the UNIX username and
    # password. The automation does NOT create users or touch credentials
    # non-interactively; it guides the user to the native flow.
    $defaultUser = (Invoke-Wsl "-d $distro -e id -un" | Clean-WslOutput | Select-Object -First 1)
    $firstLaunchNote = ""
    if (-not $defaultUser -or $defaultUser -eq 'root') {
        $firstLaunchNote = "  1. Launch the distro:  wsl -d $distro   (or Start menu -> Debian)"
        $firstLaunchNote2 = "     -> create your UNIX username and password when the distro asks (native setup)"
    }
    Write-Stage "Guide: continue inside Debian (manual handoff - containment)"
    Write-Host ""
    if ($firstLaunchNote) {
        Write-Host $firstLaunchNote -ForegroundColor Yellow
        Write-Host $firstLaunchNote2 -ForegroundColor Yellow
        Write-Host ""
    }
    Write-Host "  2. Copy the provisioner into the Linux filesystem:" -ForegroundColor White
    Write-Host "     cp $linuxScript ~/" -ForegroundColor Green
    $flagStr = ($flags -join ' ')
    if ($flagStr) {
        Write-Host "  3. Run it (flags carried over from this run):" -ForegroundColor White
        Write-Host "     bash ~/provision-wsl.sh $flagStr" -ForegroundColor Green
    } else {
        Write-Host "  3. Run it:" -ForegroundColor White
        Write-Host "     bash ~/provision-wsl.sh" -ForegroundColor Green
    }
    Write-Host "  4. After RESULT: PASS, optional cleanup:" -ForegroundColor White
    Write-Host "     rm ~/provision-wsl.sh" -ForegroundColor Green
    Write-Host ""
    Write-Info "Everything from here runs inside Debian - credentials typed natively, no cross-boundary execution."
    Complete-Stage "prepared - handoff to Debian is manual (containment)"
    exit 0
}
elseif ($featureEnabled) {
    # ---- Branch 3: feature present, no distro -> install Debian directly --
    $script:StageTotal = 3
    Write-Stage "FR-02 Branch 3: WSL feature enabled, no distro installed"
    Write-Info "Debian-only automation (PRD): installing Debian, no distro picker."
    # Distro download fallback (real-run WININET_E_CONNECTION_RESET): retry
    # with backoff, then --web-download — bypasses the Store CDN (documented
    # fix per learn.microsoft.com/windows/wsl/install).
    $installed = $false
    foreach ($mode in @('', '--web-download')) {
        $wd = if ($mode) { " $mode" } else { '' }
        Write-Info "Attempt: wsl --install -d Debian --no-launch$wd"
        Invoke-Wsl "--install -d Debian --no-launch$wd"
        if ($LASTEXITCODE -eq 0) { $installed = $true; break }
        Write-WarnLine "attempt failed (exit $LASTEXITCODE)$(if (-not $mode) { ' - next attempt: --web-download (bypasses Store CDN)' })"
        Start-Sleep -Seconds 5
    }
    if (-not $installed) {
        Write-FailLine "distro install failed after all attempts - check network/proxy/VPN, then rerun; or manually: wsl --install -d Debian --web-download"
        Complete-Stage "blocked: distro download failed (connection reset after retries)"
        exit 1
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
    # Distro download fallback (real-run WININET_E_CONNECTION_RESET): retry
    # with backoff, then --web-download — bypasses the Store CDN (documented
    # fix per learn.microsoft.com/windows/wsl/install).
    $installed = $false
    foreach ($mode in @('', '--web-download')) {
        $wd = if ($mode) { " $mode" } else { '' }
        Write-Info "Attempt: wsl --install -d Debian --no-launch$wd"
        Invoke-Wsl "--install -d Debian --no-launch$wd"
        if ($LASTEXITCODE -eq 0) { $installed = $true; break }
        Write-WarnLine "attempt failed (exit $LASTEXITCODE)$(if (-not $mode) { ' - next attempt: --web-download (bypasses Store CDN)' })"
        Start-Sleep -Seconds 5
    }
    if (-not $installed) {
        Write-FailLine "distro install failed after all attempts - check network/proxy/VPN, then rerun; or manually: wsl --install -d Debian --web-download"
        Complete-Stage "blocked: distro download failed (connection reset after retries)"
        exit 1
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
