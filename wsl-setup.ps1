<#
Run elevated:
    powershell -ExecutionPolicy Bypass -File wsl-setup.ps1

Optional switches:
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
    # bar width 26 mirrors provision-wsl.sh's BAR_W - keep the two in sync
    $barW = 26
    $script:StageSw.Stop()
    $pct = [int]($script:StageIndex * 100 / $script:StageTotal)
    $filled = [int]($barW * $script:StageIndex / $script:StageTotal)
    $bar = ('#' * $filled) + ('-' * ($barW - $filled))
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
    # Normalize first: a relative -Log path would otherwise produce garbage like
    # '/mnt/l...' from Substring(2) - resolve to an absolute path before slicing.
    $full = [IO.Path]::GetFullPath($WinPath)
    $drive = $full.Substring(0, 1).ToLower()
    $rest = $full.Substring(2) -replace '\\', '/'
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

function Install-DebianDistro {
    # Shared by Branch 2 and Branch 3 (was duplicated verbatim). Distro download
    # fallback (real-run WININET_E_CONNECTION_RESET): retry with backoff, then
    # --web-download — bypasses the Store CDN (learn.microsoft.com/windows/wsl/install).
    $installed = $false
    foreach ($mode in @('', '--web-download')) {
        $wd = if ($mode) { " $mode" } else { '' }
        Write-Info "Attempt: wsl --install -d Debian --no-launch$wd"
        Invoke-Wsl "--install -d Debian --no-launch$wd"
        if ($LASTEXITCODE -eq 0) { $installed = $true; break }
        Write-WarnLine "attempt failed (exit $LASTEXITCODE)$(if (-not $mode) { ' - next attempt: --web-download (bypasses Store CDN)' })"
        Start-Sleep -Seconds 5
    }
    return $installed
}

# ---------------------------------------------------------------------------
# Windows preflight
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

# capability warnings (forwarded to the Linux final report via WSLENV)
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
# distro decision tree
# ---------------------------------------------------------------------------
if ($distroList.Count -gt 0) {
    # ---- Branch 1: distro installed -> write config + chain provisioning -
    if ($distroList.Count -gt 1) {
        Write-FailLine "Single-distro rule: exactly one WSL distro may be installed. Found:"
        $distroList | ForEach-Object { Write-Host "    - $_" }
        Write-Info "Remove the unwanted ones (this deletes their filesystem):  wsl --unregister <name>"
        exit 1
    }
    $distro = Get-DefaultDistro
    if (-not $distro -or ($distroList -notcontains $distro)) {
        Write-WarnLine "Default distribution '$distro' is stale/unregistered - healing: wsl --set-default <first registered distro>"
        Invoke-Wsl "--set-default $($distroList[0])"
        if ($LASTEXITCODE -ne 0) {
            Write-WarnLine "wsl --set-default failed (exit $LASTEXITCODE) - continuing with '$($distroList[0])', verify with: wsl -l -v"
        }
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

    # write .wslconfig (values per wsl-ddev-setup-prd.md; swap adjusted
    # from the doc-exact 4GB per the declared PRD deviation; hostAddressLoopback
    # is load-bearing for the Windows-side 127.0.0.1 reachability checks)
    $marker = '# managed by wsl-setup.ps1 (wsl-ddev-setup-prd.md) - values per PRD (swap adjusted from wslddev.md doc-exact 4GB)'
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
    $newContent = $marker + "`r`n`r`n" + $config + "`r`n"
    $existing = $null
    if (Test-Path $wslconfigPath) { $existing = Get-Content $wslconfigPath -Raw }
    $isOurs = ($existing -and $existing.Contains('managed by wsl-setup.ps1'))
    if ($existing -eq $newContent) {
        Write-Info ".wslconfig unchanged - skipped"
    } else {
        if ($existing -and (-not $isOurs)) {
            $bak = "$wslconfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Copy-Item $wslconfigPath $bak
            Write-Info "Backed up existing .wslconfig -> $bak"
        }
        Set-Content -Path $wslconfigPath -Value $newContent -Encoding ASCII
        Write-Info "Wrote $wslconfigPath :"
        Get-Content $wslconfigPath | ForEach-Object { Write-Host "    $_" }
    }

    Write-Stage "FR-03 apply .wslconfig (wsl --shutdown)"
    Write-WarnLine "wsl --shutdown stops ALL running WSL distros and sessions - save work in open WSL terminals first."
    Start-Sleep -Seconds 3
    Invoke-Wsl '--shutdown'
    if ($LASTEXITCODE -ne 0) {
        Write-WarnLine "wsl --shutdown returned exit $LASTEXITCODE - if WSL still runs, shut it down manually before continuing."
    }
    Write-Info "WSL shut down - next start uses the new .wslconfig"
    Complete-Stage "config applied - WSL shut down"

    $linuxScript = Convert-To-LinuxPath (Join-Path $PSScriptRoot 'provision-wsl.sh')
    $flags = @()
    if ($NoUpgrade) { $flags += '--no-upgrade' }
    if ($SkipCaImport) { $flags += '--skip-ca-import' }
    if ($Log) { $flags += @('--log', (Convert-To-LinuxPath $Log)) }
    $flags += @('--pause', "$Pause")

    Write-Host ""
    Write-Info "Windows phase complete. The Linux phase runs inside Debian - containment: nothing executes across the boundary."
    $defaultUser = (Invoke-Wsl "-d $distro -e id -un" | Clean-WslOutput | Select-Object -First 1)
    $needsFirstLaunch = (-not $defaultUser -or $defaultUser -eq 'root')
    Write-Stage "Guide: continue inside Debian (manual handoff - containment)"
    Write-Host ""
    $steps = @()
    if ($needsFirstLaunch) {
        # NB: the leading comma keeps each (text, is-command) pair a single element
        $steps += ,@("Launch the distro:  wsl -d $distro   (or Start menu -> Debian) - then create your UNIX username and password when the distro asks (native setup)", $true)
    }
    $steps += ,@("Copy the provisioner into the Linux filesystem:", $false)
    $steps += ,@("cp '$linuxScript' ~/", $true)
    $flagStr = ($flags -join ' ')
    if ($flagStr) {
        $steps += ,@("Run it (flags carried over from this run):", $false)
        $steps += ,@("bash ~/provision-wsl.sh $flagStr", $true)
    } else {
        $steps += ,@("Run it:", $false)
        $steps += ,@("bash ~/provision-wsl.sh", $true)
    }
    $steps += ,@("After RESULT: PASS, optional cleanup:", $false)
    $steps += ,@("rm ~/provision-wsl.sh", $true)
    $n = 0
    foreach ($s in $steps) {
        $n++
        if ($s[1]) { Write-Host "     $($s[0])" -ForegroundColor Green }
        else { Write-Host "  $n. $($s[0])" -ForegroundColor White }
    }
    if ($capWarn) {
        # FR-04 warning stays in THIS session's output: after the containment
        # change an env var cannot reach the separately-launched Debian shell,
        # so WSLENV forwarding was removed (it was a dead path end-to-end).
        Write-Host ""
        Write-WarnLine "Capability warning from preflight applies to this install - review the FR-04 warnings above before provisioning."
    }
    Write-Host ""
    Write-Info "Everything from here runs inside Debian - credentials typed natively, no cross-boundary execution."
    Complete-Stage "prepared - handoff to Debian is manual (containment)"
    exit 0
}
elseif ($featureEnabled) {
    # ---- Branch 3: feature present, no distro -> install Debian directly --
    $script:StageTotal = 2   # gates run two stages (preflight + branch) - not 3 (audit #29)
    Write-Stage "FR-02 Branch 3: WSL feature enabled, no distro installed"
    Write-Info "Debian-only automation (PRD): installing Debian, no distro picker."
    if (-not (Install-DebianDistro)) {
        Write-FailLine "distro install failed after all attempts - check network/proxy/VPN, then rerun; or manually: wsl --install -d Debian --web-download"
        Complete-Stage "blocked: distro download failed (connection reset after retries)"
        exit 1
    }
    Complete-Stage "Debian installed - rerun for the manual first-launch handoff"
    Write-Host ""
    Write-Host "[NEXT STEP]" -ForegroundColor Yellow
    Write-Host "  1. Launch Debian once natively:  wsl -d Debian   - create your UNIX"
    Write-Host "     username and password when the distro asks (the native, documented flow)."
    Write-Host "  2. Run this script again (same command) - Branch 1 prints the manual"
    Write-Host "     handoff guide that walks you through provisioning."
    exit 0
}
else {
    # ---- Branch 2: feature absent -> enable + restart gate ---------------
    $script:StageTotal = 2   # gates run two stages (preflight + branch) - not 3 (audit #29)
    Write-Stage "FR-02 Branch 2: WSL feature not enabled, no distro installed"
    Write-Info "Running: wsl --install -d Debian --no-launch - one command, two effects:"
    Write-Info "  1. enables Windows features (Microsoft-Windows-Subsystem-Linux + VirtualMachinePlatform) -> RESTART required, first-time only"
    Write-Info "  2. unpacks the Debian distro -> the distro itself never needs a restart"
    if (-not (Install-DebianDistro)) {
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
    Write-Host "  2. After the restart, launch Debian once natively (wsl -d Debian) and"
    Write-Host "     create your UNIX username and password when it asks."
    Write-Host "  3. Run this script again (same command) - Branch 1 prints the manual"
    Write-Host "     handoff guide that walks you through provisioning."
    exit 0
}
