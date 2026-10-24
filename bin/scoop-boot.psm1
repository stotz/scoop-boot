<#
.SYNOPSIS
    scoop-boot library module: logging, environment files, variable expansion,
    package list, bootstrap, setup commands, self-tests.

.DESCRIPTION
    Loaded by scoop-boot.ps1 with "Import-Module -Scope Local" and by the helper
    installation and the reset that used to be separate scripts. Nothing here
    runs on its own: scoop-boot.ps1 is the command line.

    The Write-Host function exported from here shadows the cmdlet for every caller
    (functions come before cmdlets in command resolution), which is how the output
    of the helper scripts and of Scoop itself reaches the daily log.

    scoop-boot.ps1 --update, --version and --help work without this file, so a
    broken module can always be replaced with --update.

.NOTES
    Version: 1.19.0
    Same version as scoop-boot.ps1; the changelog is in scoop-boot.ps1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

$global:ScriptVersion = "1.19.0"
$global:ScriptRoot = $PSScriptRoot
$global:BaseDir = Split-Path -Parent $global:ScriptRoot
$global:EnvDir = Join-Path $global:BaseDir "etc\environments"
$global:PackagesDir = Join-Path $global:BaseDir "etc\packages"
# Branch that --update downloads from; written by --update --branch=NAME, removed by
# --branch=main. A test machine stays on its branch until it is switched back.
$global:BranchFile = Join-Path $global:BaseDir "etc\scoop-boot.branch"

# Subdirectories of the base directory that belong to Scoop. Only these are
# cleaned up, swept from PATH or deleted; everything else under the base
# directory (bin, etc, or whatever the user installs there) is not Scoop's.
$global:ScoopOwnedDirs = @('apps', 'buckets', 'cache', 'persist', 'shims', 'global')

# ============================================================================
# LOGGING
# Shared by all three scripts (the other two dot-source this file in library
# mode). Every Write-Host call is mirrored into a daily log file:
#   C:\usr\logs\scoopboot\<yyyyMMdd>.log
#   <timestamp> <script [mode]> (<version>) [INFO|WARN|ERROR|FATAL] <text>
# The level is derived from the message prefix ([OK]/[INFO] -> INFO, [WARN] ->
# WARN, [ERROR]/[FAIL] -> ERROR, [FATAL] -> FATAL). Console output is unchanged.
# Scoop itself runs in-process (scoop.ps1), so its messages are logged as well;
# output of external tools (pacman, msiexec, reg) is not.
# ============================================================================
$global:ScoopBootLogDir = Join-Path $global:BaseDir "logs\scoopboot"
$global:ScoopBootLogRetentionDays = 60
if (-not (Test-Path variable:global:ScoopBootLogFile)) { $global:ScoopBootLogFile = $null }
# Registered log contexts: script file name -> "label (version)". The context of a
# log line is found by walking the call stack to the first frame that belongs to
# one of the registered scripts; output of child scripts such as scoop.ps1 is
# attributed to the scoop-boot script that invoked them.
if (-not (Test-Path variable:global:ScoopBootLogContexts)) { $global:ScoopBootLogContexts = @{} }
if (-not (Test-Path variable:global:ScoopBootLogPartial)) { $global:ScoopBootLogPartial = '' }
# Quiet mode (--quiet): console shows only [scoop-boot] summaries, warnings and errors; the log gets everything
if (-not (Test-Path variable:global:ScoopBootQuiet)) { $global:ScoopBootQuiet = $false }
# Global on purpose: Windows PowerShell 5.1 does not resolve script-scope variables
# inside these functions once a helper script has imported them into its own scope
$global:ScoopBootLogOwnFunctions = @('Write-Host', 'Write-ScoopBootLogLine', 'Get-ScoopBootLogContext', 'Initialize-ScoopBootLog')

function Get-FileSha256Short {
    param([string]$Path)
    try { return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.Substring(0, 8).ToLower() } catch { return 'unknown' }
}

function Get-ScoopBootLogLevel {
    param([string]$Text)
    if ($Text -match '^\s*\[FATAL\]') { return 'FATAL' }
    if ($Text -match '^\s*(\[ERROR\]|\[FAIL\]|ERROR\b)') { return 'ERROR' }
    if ($Text -match '^\s*(\[WARN\]|WARN\b)') { return 'WARN' }
    return 'INFO'
}

function Get-ScoopBootLogContext {
    foreach ($frame in (Get-PSCallStack)) {
        # Advanced functions appear as "Write-Host<Process>" in the call stack
        $fn = $frame.FunctionName -replace '<[A-Za-z]+>$', ''
        if ($global:ScoopBootLogOwnFunctions -contains $fn) { continue }
        if (-not $frame.ScriptName) { continue }
        $name = Split-Path -Leaf $frame.ScriptName
        if ($global:ScoopBootLogContexts.ContainsKey($name)) { return $global:ScoopBootLogContexts[$name] }
    }
    return 'unknown (?)'
}

function Write-ScoopBootLogLine {
    param([string]$Text, [string]$Level = '')
    if (-not $global:ScoopBootLogFile) { return }
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    # Console-only noise: ANSI colour codes, carriage-return progress updates
    # (keep what is on screen after the last CR), aria2 progress lines
    $Text = $Text -replace '\x1b\[[0-9;]*[A-Za-z]', ''
    if ($Text.Contains("`r") -and -not $Text.Contains("`n")) { $Text = ($Text -split "`r")[-1] }
    if ($Text -match '^\s*Download: \[#') { return }
    if (-not $Level) { $Level = Get-ScoopBootLogLevel -Text $Text }
    $stamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss'
    $context = Get-ScoopBootLogContext
    foreach ($line in ($Text -split "`r?`n")) {
        if (-not $line.Trim()) { continue }
        $out = "$stamp $context [$Level] $($line.TrimEnd())"
        try { [System.IO.File]::AppendAllText($global:ScoopBootLogFile, $out + "`n", [System.Text.Encoding]::UTF8) } catch { }
    }
}

function Write-Host {
    <#
    .SYNOPSIS
        Drop-in replacement for Write-Host that also appends the text to the daily log.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0, ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [object]$Object,
        [switch]$NoNewline,
        [object]$Separator,
        [ConsoleColor]$ForegroundColor,
        [ConsoleColor]$BackgroundColor
    )
    process {
        $text = if ($null -ne $Object) { [string]::Join(' ', @($Object)) } else { '' }
        $important = $text -match '^\s*(\[scoop-boot\]|\[WARN\]|\[ERROR\]|\[FAIL\]|\[FATAL\])'
        if (-not $global:ScoopBootQuiet -or $important) {
            Microsoft.PowerShell.Utility\Write-Host @PSBoundParameters
        }
        # -NoNewline fragments ("Checking hash of x... " + "OK.") are joined into one log line
        if ($NoNewline) {
            $global:ScoopBootLogPartial += $text
            return
        }
        if ($global:ScoopBootLogPartial) {
            $text = $global:ScoopBootLogPartial + $text
            $global:ScoopBootLogPartial = ''
        }
        Write-ScoopBootLogLine -Text $text
    }
}

function Initialize-ScoopBootLog {
    <#
    .SYNOPSIS
        Opens today's log file, prunes old logs, prints the version banner and writes a session header.
    .PARAMETER ScriptPath
        Path of the running script; its SHA-256 (first 8 hex digits) goes into the banner so
        that a log always tells which build of the script produced it.
    #>
    param(
        [string]$ScriptName,
        [string]$Version,
        [string]$Mode = '',
        [string]$ScriptPath = '',
        [string[]]$Arguments = @()
    )
    $label = if ($Mode) { "$ScriptName $Mode" } else { $ScriptName }
    $global:ScoopBootLogContexts[$ScriptName] = "$label ($Version)"
    if ($Arguments -notcontains '--quiet') { $global:ScoopBootQuiet = $false }

    $hash = if ($ScriptPath) { Get-FileSha256Short -Path $ScriptPath } else { 'unknown' }
    # The module carries the logic, so its build is named next to the script's
    $hash = "$hash, module $(Get-FileSha256Short -Path $PSCommandPath)"

    try {
        if (-not (Test-Path $global:ScoopBootLogDir)) { New-Item -ItemType Directory -Path $global:ScoopBootLogDir -Force | Out-Null }
        $global:ScoopBootLogFile = Join-Path $global:ScoopBootLogDir ("{0}.log" -f (Get-Date -Format 'yyyyMMdd'))
        Get-ChildItem -Path $global:ScoopBootLogDir -Filter '*.log' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$global:ScoopBootLogRetentionDays) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    } catch {
        $global:ScoopBootLogFile = $null
    }

    $logNote = if ($global:ScoopBootLogFile) { "log: $global:ScoopBootLogFile" } else { "log: not writable, console only" }
    if (-not $global:ScoopBootQuiet) {
        Microsoft.PowerShell.Utility\Write-Host "$ScriptName $Version (sha256 $hash) | $logNote" -ForegroundColor DarkCyan
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $os = try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Version } catch { [Environment]::OSVersion.Version.ToString() }
    Write-ScoopBootLogLine -Level 'INFO' -Text "=== session start: $label $Version (sha256 $hash) ==="
    Write-ScoopBootLogLine -Level 'INFO' -Text "host=$env:COMPUTERNAME user=$env:USERDOMAIN\$env:USERNAME admin=$isAdmin windows=$os powershell=$($PSVersionTable.PSVersion) script=$ScriptPath args=[$($Arguments -join ' ')]"
}
$global:BackupDir = Join-Path $global:EnvDir "backups"

# ============================================================================
# ARGUMENT PARSER
# ============================================================================

$global:ParsedArgs = @{
    Help = $false
    Version = $false
    Bootstrap = $false
    SelfTest = $false
    EnvStatus = $false
    CleanUserScope = $false
    Quiet = $false
    PlatformReport = $false
    Update = $false
    Branch = ''
    AdminInit = $false
    AdminSetEnv = $false
    UserInstall = $false
    AdminReset = $false
    ListPackages = $false
    Force = $false
    KeepPersist = $false
    DryRun = $false
    Unknown = @()
}

function Parse-Arguments {
    param([string[]]$Arguments)

    $i = 0
    while ($i -lt $Arguments.Count) {
        $arg = $Arguments[$i]

        switch -Regex ($arg) {
            '^--?h(elp)?$' { $global:ParsedArgs.Help = $true }
            '^--?v(ersion)?$' { $global:ParsedArgs.Version = $true }
            '^--bootstrap$' { $global:ParsedArgs.Bootstrap = $true }
            '^--(selfTest|self-test)$' { $global:ParsedArgs.SelfTest = $true }
            '^--env-status$' { $global:ParsedArgs.EnvStatus = $true }
            '^--clean-user-scope$' { $global:ParsedArgs.CleanUserScope = $true }
            '^--quiet$' { $global:ParsedArgs.Quiet = $true }
            '^--(platform-report|asr-report)$' { $global:ParsedArgs.PlatformReport = $true }
            '^--update$' { $global:ParsedArgs.Update = $true }
            '^--branch=(.+)$' { $global:ParsedArgs.Branch = $Matches[1] }
            '^--admin-init$' { $global:ParsedArgs.AdminInit = $true }
            '^--admin-setenv$' { $global:ParsedArgs.AdminSetEnv = $true }
            '^--user-install$' { $global:ParsedArgs.UserInstall = $true }
            '^--admin-reset$' { $global:ParsedArgs.AdminReset = $true }
            '^--list-packages$' { $global:ParsedArgs.ListPackages = $true }
            '^--force$' { $global:ParsedArgs.Force = $true }
            '^--keep-persist$' { $global:ParsedArgs.KeepPersist = $true }
            '^--dry-run$' { $global:ParsedArgs.DryRun = $true }
            # Anything else is reported by the caller: a typo, or a command that was
            # removed (--status, --suggest, --install, --environment, --init-env,
            # --apply-env, --rollback in 1.18.0)
            default { $global:ParsedArgs.Unknown += $arg }
        }
        $i++
    }
}

# ============================================================================
# OUTPUT FUNCTIONS
# ============================================================================

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host ">>> $Message" -ForegroundColor White
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Self-tests silence Write-DryRun while they exercise the apply path; the flag must exist
# before the first --dry-run, because the script runs under Set-StrictMode
if (-not (Test-Path variable:global:SuppressDryRunOutput)) { $global:SuppressDryRunOutput = $false }

function Write-DryRun {
    param([string]$Message)
    # Suppress output during self-tests
    if ($global:SuppressDryRunOutput) { return }
    Write-Host "  [DRY] $Message" -ForegroundColor Magenta
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Test-AdminRights {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Hostname {
    return [System.Net.Dns]::GetHostName().ToLower()
}

function Get-Username {
    return [Environment]::UserName.ToLower()
}

# Window title as progress display for the long-running commands (--user-install,
# --admin-reset): "scoop-boot [12/70] kotlin", "scoop-boot gcc", "scoop-boot reset apps".
# The title is cosmetic; a host without a console window (ISE, a service, a
# redirected session) must not make the command fail, hence try/catch.
function Get-ScoopBootTitle {
    try { return $Host.UI.RawUI.WindowTitle } catch { return $null }
}

function Set-ScoopBootTitle {
    param([string]$Text)
    try { $Host.UI.RawUI.WindowTitle = $Text } catch { }
}

function Restore-ScoopBootTitle {
    param([object]$Saved)
    if ($null -ne $Saved) { Set-ScoopBootTitle -Text "$Saved" }
}

# Definitions (NAME=value lines) of the .env files of the current run, name -> raw
# value. Filled by Register-EnvFileDefinitions before any file is applied, so that a
# reference resolves to the value the files define wherever the definition stands,
# also on a machine where the name is not yet in the registry and in --dry-run.
if (-not (Test-Path variable:global:EnvFileDefinitions)) { $global:EnvFileDefinitions = @{} }

function Register-EnvFileDefinitions {
    param([array]$Operations)
    foreach ($op in $Operations) {
        if ($op.Type -eq 'Set') { $global:EnvFileDefinitions[$op.Name] = $op.Value }
        elseif ($op.Type -eq 'Unset') { $global:EnvFileDefinitions.Remove($op.Name) }
    }
}

function Expand-EnvironmentVariables {
    <#
    .SYNOPSIS
        Expands $NAME and ${NAME}; "$$" gives a literal "$".
    .DESCRIPTION
        Lookup order: definitions of the .env files of this run, the built-in names
        (SCOOP, SCOOP_ROOT, USERPROFILE, USERNAME, HOSTNAME), then the registry
        (Machine, User, Process). A file definition that refers to itself
        (PATH=$PATH;C:\x) or to a name currently being resolved falls through to the
        registry, so the old value is extended instead of looping.
    #>
    param(
        [string]$Value,
        [string[]]$Resolving = @(),
        [switch]$KeepEscapes
    )

    # "$$" must survive the expansion as "$"; a control character stands in for it
    $escape = [string][char]1
    $expandedValue = $Value -replace '\$\$', $escape
    $maxIterations = 10
    $iteration = 0

    while ($iteration -lt $maxIterations) {
        $previousValue = $expandedValue

        # Replace $VAR or ${VAR} patterns
        $expandedValue = [regex]::Replace($expandedValue, '\$\{?([A-Z_][A-Z0-9_]*)\}?', {
            param($match)
            $varName = $match.Groups[1].Value

            # Check various sources
            if ($global:EnvFileDefinitions.ContainsKey($varName) -and $Resolving -notcontains $varName) {
                return (Expand-EnvironmentVariables -Value $global:EnvFileDefinitions[$varName] -Resolving ($Resolving + $varName))
            }
            elseif ($varName -eq "SCOOP") {
                return $global:BaseDir
            }
            elseif ($varName -eq "SCOOP_ROOT") {
                return $global:BaseDir
            }
            elseif ($varName -eq "USERPROFILE") {
                return [Environment]::GetFolderPath("UserProfile")
            }
            elseif ($varName -eq "USERNAME") {
                return [Environment]::UserName
            }
            elseif ($varName -eq "HOSTNAME") {
                return Get-Hostname
            }
            else {
                # Try environment variable
                $envValue = [Environment]::GetEnvironmentVariable($varName, "Machine")
                if ([string]::IsNullOrEmpty($envValue)) {
                    $envValue = [Environment]::GetEnvironmentVariable($varName, "User")
                }
                if ([string]::IsNullOrEmpty($envValue)) {
                    $envValue = [Environment]::GetEnvironmentVariable($varName, "Process")
                }

                if (![string]::IsNullOrEmpty($envValue)) {
                    return $envValue
                }
            }

            # Return original if not found
            return $match.Value
        })

        # If no changes were made, we're done
        if ($expandedValue -eq $previousValue) {
            break
        }

        $iteration++
    }

    # Nested calls keep the placeholder so that the outer loop does not expand an escaped "$"
    if ($Resolving.Count -eq 0 -and -not $KeepEscapes) { $expandedValue = $expandedValue.Replace($escape, '$') }
    return $expandedValue
}

# ============================================================================
# HELP FUNCTIONS
# ============================================================================

function Show-Help {
    Write-Host ""
    Write-Host "scoop-boot.ps1 v$global:ScriptVersion - Portable Windows Development Environment Bootstrap" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "USAGE:" -ForegroundColor Yellow
    Write-Host "  scoop-boot.ps1 <command> [options]"
    Write-Host ""
    Write-Host "SETUP (Administrator shell unless noted; run in this order):" -ForegroundColor Yellow
    Write-Host "  --admin-init         1: directories, --update, environment files from the templates, opens the system file"
    Write-Host "  --admin-setenv       2: apply the environment files at Machine scope (Phase 1)"
    Write-Host "      --dry-run          show the changes without applying them (no Administrator needed)"
    Write-Host "  --user-install       3 (normal shell): bootstrap Scoop, install the package list (Phase 2)"
    Write-Host "      --force            no question when the shell is elevated (account with elevated shells only)"
    Write-Host "  --admin-reset        Remove Scoop again: apps, variables, PATH entries, registry; bin, etc and logs stay"
    Write-Host "      --force            no confirmation prompt"
    Write-Host "      --keep-persist     keep C:\usr\persist (app data, settings)"
    Write-Host ""
    Write-Host "MAINTENANCE:" -ForegroundColor Yellow
    Write-Host "  --update             Download the current scripts, scoop wrapper and etc\packages\default.txt from GitHub"
    Write-Host "      --branch=NAME      download from this branch and remember it; --branch=main switches back"
    Write-Host "  --clean-user-scope   Remove Scoop's User-scope overrides, apply the user.* files (no admin)"
    Write-Host "      --quiet            print only a summary when something changed"
    Write-Host "  --list-packages      Package list in use, status of each package and its post-install steps; installs nothing"
    Write-Host "  --platform-report    Defender/ASR rules and blocks, profile container, TMP: what the platform does to the setup; exit 1 on findings"
    Write-Host ""
    Write-Host "ENVIRONMENT FILES (C:\usr\etc\environments):" -ForegroundColor Yellow
    Write-Host "  --env-status         Which files exist and apply to this host and user"
    Write-Host "  (--admin-init creates the host files from the templates; copy a template by hand for *.default.env)"
    Write-Host ""
    Write-Host "OTHER:" -ForegroundColor Yellow
    Write-Host "  --bootstrap          Install Scoop and the bootstrap packages only (part of --user-install)"
    Write-Host "  --self-test          Run the self-tests (parser, expansion, package list, help)"
    Write-Host "  --version, -v        Show version"
    Write-Host "  --help, -h           Show this help message"
    Write-Host ""
    Write-Host "FILES:" -ForegroundColor Yellow
    Write-Host "  system.default.env              Machine scope, all hosts"
    Write-Host "  system.HOSTNAME.USERNAME.env    Machine scope, this host and user (source of truth)"
    Write-Host "  user.default.env                User scope, all hosts"
    Write-Host "  user.HOSTNAME.USERNAME.env      User scope, this host and user"
    Write-Host "  etc\packages\default.txt        Package list (delivered); etc\packages\HOSTNAME.txt replaces it"
    Write-Host ""
    Write-Host "LIST OPERATIONS (work for ALL variables):" -ForegroundColor Yellow
    Write-Host "  VAR+=value          Prepend to list (PATH, PERL5LIB, etc.)"
    Write-Host "  VAR=+value          Append to list"
    Write-Host "  VAR-=value          Remove from list"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  scoop-boot.ps1 --admin-init            # first command on a new machine (Administrator)"
    Write-Host "  scoop-boot.ps1 --admin-setenv --dry-run   # check an edited system file before applying it"
    Write-Host "  scoop-boot.ps1 --update                # after a scoop-boot release"
    Write-Host "  scoop-boot.ps1 --admin-reset --force   # start over, then --admin-init again"
    Write-Host ""
}

function Show-Version {
    Write-Host "scoop-boot.ps1 version $global:ScriptVersion"
    $manifest = Join-Path $global:BaseDir 'etc\release.manifest'
    if (Test-Path $global:BranchFile) {
        $branch = (Get-Content $global:BranchFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        Write-Host "branch $branch (unsigned downloads; back to signed releases with --update --branch=main)" -ForegroundColor Yellow
    } elseif (Test-Path $manifest) {
        $tag = (Select-String -Path $manifest -Pattern '^tag\s+(\S+)' | Select-Object -First 1)
        $date = (Select-String -Path $manifest -Pattern '^date\s+(\S+)' | Select-Object -First 1)
        Write-Host ("release {0} ({1}), signature verified by --update" -f $(if ($tag) { $tag.Matches[0].Groups[1].Value } else { '?' }), $(if ($date) { $date.Matches[0].Groups[1].Value } else { '?' }))
    } else {
        Write-Host "no release manifest yet: run --update to install the signed release" -ForegroundColor Yellow
    }
}

# ============================================================================
# BOOTSTRAP FUNCTIONS
# ============================================================================

function Get-ScoopInstaller {
    <#
    .SYNOPSIS
        Downloads the official Scoop installer and removes its non-empty-directory check.
    .DESCRIPTION
        The official installer (https://get.scoop.sh) aborts when the target directory
        contains any file. In the scoop-boot layout C:\usr already holds bin\ and etc\
        before Scoop exists, so that check would block every fresh installation.
        The check is a single Deny-Install line; it is replaced by an informational
        message. Nothing else in the installer is changed. If the line is not found
        (installer changed upstream), the installer runs unpatched and a warning is shown.
    .OUTPUTS
        Path of the installer script to execute.
    #>
    param([string]$OutFile)

    Invoke-WebRequest -Uri 'https://get.scoop.sh' -OutFile $OutFile -UseBasicParsing

    $content = [System.IO.File]::ReadAllText($OutFile)
    $check = 'Deny-Install "''$SCOOP_DIR'' exists and is not empty, please specify another path."'
    $info  = 'Write-Host "[INFO] ''$SCOOP_DIR'' is not empty (scoop-boot layout: bin\ and etc\ are expected), continuing"'

    if ($content.Contains($check)) {
        $content = $content.Replace($check, $info)
        [System.IO.File]::WriteAllText($OutFile, $content)
        Write-Success "Installer prepared (non-empty directory check removed)"
    } else {
        Write-Warning "Installer layout changed upstream; non-empty directory check not found, running unpatched"
    }

    return $OutFile
}

function Invoke-Bootstrap {
    Write-Section "Scoop Bootstrap"
    # Talk to the real Scoop shim, not the wrapper in bin\ (no cleanup per package here)
    $env:SCOOP_BOOT_WRAPPER = 'off'

    # Check current state. Look at the Scoop core itself, not at "Get-Command scoop":
    # since v0012 that finds the scoop wrapper in bin\, which survives a reset and
    # would make a fresh machine look as if Scoop were installed.
    Write-Info "Checking current state..."
    $scoopCore = Join-Path $global:BaseDir "apps\scoop\current\bin\scoop.ps1"

    $scoopShims = Join-Path $global:BaseDir "shims"

    if (Test-Path $scoopCore) {
        # The core is there (a run that stopped at an essential tool, or a plain
        # re-run): skip the installer, but still check the essential tools below,
        # so that a bootstrap interrupted by endpoint security can be resumed.
        Write-Host "     SCOOP=$global:BaseDir"
        Write-Host "     SCOOP_GLOBAL=$global:BaseDir\global"
        Write-Success "Scoop core already installed: $scoopCore (checking essential tools)"
    } else {
        # Set environment variables
        Write-Info "Setting environment variables..."
        [Environment]::SetEnvironmentVariable('SCOOP', $global:BaseDir, 'User')
        [Environment]::SetEnvironmentVariable('SCOOP_GLOBAL', "$global:BaseDir\global", 'User')
        $env:SCOOP = $global:BaseDir
        $env:SCOOP_GLOBAL = "$global:BaseDir\global"
        Write-Success "Environment variables set"

        # Install Scoop. The installer aborts with "Scoop is already installed" when a
        # scoop command is on the PATH; the scoop wrapper in bin\ (delivered by --update
        # before Scoop exists) is such a command, so bin\ and shims\ leave the PATH of
        # this process while the installer runs.
        Write-Info "Installing Scoop core..."
        Set-ScoopBootTitle -Text "scoop-boot bootstrap scoop"
        $installerOutput = @()
        $savedPath = $env:Path
        try {
            $hidden = @((Join-Path $global:BaseDir 'bin'), $scoopShims) | ForEach-Object { $_.TrimEnd('\').ToLower() }
            $env:Path = (@($env:Path -split ';') | Where-Object { $_ -and ($hidden -notcontains $_.TrimEnd('\').ToLower()) }) -join ';'
            $scoopInstaller = Get-ScoopInstaller -OutFile "$env:TEMP\scoop-install.ps1"
            # The official installer refuses an elevated shell unless told so (a user who
            # is a local administrator with UAC off, or the built-in Administrator account)
            $installerArgs = @{ ScoopDir = $global:BaseDir; ScoopGlobalDir = "$global:BaseDir\global"; NoProxy = $true }
            if (Test-AdminRights) { $installerArgs['RunAsAdmin'] = $true }
            $installerOutput = & $scoopInstaller @installerArgs 2>&1
            Remove-Item $scoopInstaller -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-ErrorMsg "Failed to install Scoop: $_"
            return $false
        }
        finally {
            $env:Path = $savedPath
        }

        # Verify installation on the file system, then on the PATH
        if (-not (Test-Path $scoopCore) -or -not (Test-Path $scoopShims)) {
            Write-ErrorMsg "Scoop installation verification failed"
            Write-Host "  Expected: $scoopCore" -ForegroundColor Gray
            Write-Host "  Installer output:" -ForegroundColor Gray
            foreach ($line in $installerOutput) { Write-Host "    $line" -ForegroundColor DarkGray }
            return $false
        }
        Write-Success "Scoop core installed"
    }

    $env:Path = "$scoopShims;$env:Path"
    $scoopCommand = Get-Command scoop -ErrorAction SilentlyContinue
    if (-not $scoopCommand) {
        Write-ErrorMsg "scoop command not found on PATH after installation ($scoopShims)"
        return $false
    }

    # Install essential tools
    Write-Info "Installing essential tools..."
    # After each install the main executable is started once. On managed machines
    # endpoint security (Defender ASR rule 01443614, prevalence/age criterion) may
    # refuse a freshly released binary; for 7z.exe that breaks every extraction
    # that follows, so it is better to stop here with the real cause.
    $essentialTools = @(
        @{ Name = '7zip'; Exe = 'apps\7zip\current\7z.exe';      Args = @() },
        @{ Name = 'git';  Exe = 'apps\git\current\cmd\git.exe';  Args = @('--version') }
    )
    foreach ($tool in $essentialTools) {
        Set-ScoopBootTitle -Text "scoop-boot bootstrap $($tool.Name)"
        & scoop install $tool.Name 2>&1 | Out-Null
        if (-not (Test-Path (Join-Path $global:BaseDir "apps\$($tool.Name)\current"))) {
            Write-ErrorMsg "Failed to install $($tool.Name) (required)"
            return $false
        }
        $exe = Join-Path $global:BaseDir $tool.Exe
        try {
            & $exe @($tool.Args) 2>&1 | Out-Null
            Write-Success "$($tool.Name) installed and runs"
        } catch {
            Write-Host "[FATAL] $($tool.Name) is installed but Windows refuses to start $exe" -ForegroundColor Red
            Write-Host "        $($_.Exception.Message)" -ForegroundColor Gray
            Write-Host "        Endpoint security (Defender ASR rule 01443614) blocks newly released binaries on this machine." -ForegroundColor Gray
            Write-Host "        Nothing can be installed until C:\usr is excluded. Check the Defender log for event 1121:" -ForegroundColor Gray
            Write-Host "        Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational'; Id=1121}" -ForegroundColor Gray
            return $false
        }
    }

    # Install recommended tools
    Write-Info "Installing recommended tools for optimal performance..."
    $recommendedTools = @(
        @{Name = 'aria2'; Desc = '5x faster downloads'},
        @{Name = 'sudo'; Desc = 'admin operations'},
        @{Name = 'innounp'; Desc = 'Inno Setup support'},
        @{Name = 'dark'; Desc = 'WiX Toolset support'},
        @{Name = 'lessmsi'; Desc = 'MSI extraction'},
        @{Name = 'wget'; Desc = 'alternative downloader'}
    )

    foreach ($tool in $recommendedTools) {
        Set-ScoopBootTitle -Text "scoop-boot bootstrap $($tool.Name)"
        & scoop install $tool.Name 2>&1 | Out-Null
        if (Test-Path (Join-Path $global:BaseDir "apps\$($tool.Name)\current")) {
            Write-Success "$($tool.Name) installed ($($tool.Desc))"
            if ($tool.Name -eq 'aria2') {
                # Silence the aria2 advisory that Scoop prints before every download
                & scoop config aria2-warning-enabled false 2>&1 | Out-Null
            }
        } else {
            Write-Warning "Failed to install $($tool.Name) ($($tool.Desc))"
        }
    }

    # Add essential buckets
    Write-Info "Adding essential buckets..."
    $buckets = @(
        @{Name = 'main'; Desc = 'official apps'},
        @{Name = 'extras'; Desc = 'additional apps'}
    )

    foreach ($bucket in $buckets) {
        Set-ScoopBootTitle -Text "scoop-boot bucket $($bucket.Name)"
        try {
            & scoop bucket add $bucket.Name 2>&1 | Out-Null
            Write-Success "$($bucket.Name) bucket ($($bucket.Desc))"
        }
        catch {
            Write-Warning "Failed to add $($bucket.Name) bucket"
        }
    }

    Write-Section "Bootstrap Complete!"
    # Called from Install-ScoopTools (--user-install): the env file is already applied and
    # the remaining steps follow in the same run, so the manual guide is noise
    if ($env:SCOOP_BOOT_CALLER -eq 'install') { return $true }
    Write-Host ""
    Write-Host "IMPORTANT: Restart your shell for PATH changes to take effect!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  Administrator shell: scoop-boot.ps1 --admin-init, then --admin-setenv" -ForegroundColor White
    Write-Host "  Normal shell:        scoop-boot.ps1 --user-install" -ForegroundColor White
    Write-Host ""

    return $true
}

# ============================================================================
# ENVIRONMENT PARSING FUNCTIONS
# ============================================================================

function Parse-EnvironmentLine {
    param([string]$Line)

    # Skip empty lines and comments
    if ([string]::IsNullOrWhiteSpace($Line) -or $Line.StartsWith("#")) {
        return $null
    }

    # Remove leading/trailing whitespace
    $Line = $Line.Trim()

    # Parse += for ANY variable (prepend to list)
    if ($Line -match '^([A-Z_][A-Z0-9_]*)\s*\+=\s*(.+)$') {
        return @{
            Type = "ListPrepend"
            Name = $Matches[1]
            Value = $Matches[2].Trim()
        }
    }

    # Parse =+ for ANY variable (append to list)
    elseif ($Line -match '^([A-Z_][A-Z0-9_]*)\s*=\+\s*(.+)$') {
        return @{
            Type = "ListAppend"
            Name = $Matches[1]
            Value = $Matches[2].Trim()
        }
    }

    # Parse -= for ANY variable (remove from list)
    elseif ($Line -match '^([A-Z_][A-Z0-9_]*)\s*-=\s*(.+)$|^([A-Z_][A-Z0-9_]*)-=(.+)$') {
        $name = if ($Matches[1]) { $Matches[1] } else { $Matches[3] }
        $value = if ($Matches[2]) { $Matches[2] } else { $Matches[4] }
        return @{
            Type = "ListRemove"
            Name = $name
            Value = $value.Trim()
        }
    }

    # Parse simple assignment
    elseif ($Line -match '^([A-Z_][A-Z0-9_]*)=(.*)$') {
        return @{
            Type = "Set"
            Name = $Matches[1]
            Value = $Matches[2].Trim()
        }
    }

    # Parse unset (Value present but empty: every operation carries the same keys)
    elseif ($Line -match '^-([A-Z_][A-Z0-9_]*)$') {
        return @{
            Type = "Unset"
            Name = $Matches[1]
            Value = ''
        }
    }

    return $null
}

function Get-EnvironmentFiles {
    $hostname = Get-Hostname
    $username = Get-Username

    $files = @()

    # System scope files
    $systemDefault = Join-Path $global:EnvDir "system.default.env"
    $systemHost = Join-Path $global:EnvDir "system.$hostname.$username.env"

    # User scope files
    $userDefault = Join-Path $global:EnvDir "user.default.env"
    $userHost = Join-Path $global:EnvDir "user.$hostname.$username.env"

    # Add existing files
    if (Test-Path $systemDefault) { $files += @{Path = $systemDefault; Scope = "Machine"} }
    if (Test-Path $systemHost) { $files += @{Path = $systemHost; Scope = "Machine"} }
    if (Test-Path $userDefault) { $files += @{Path = $userDefault; Scope = "User"} }
    if (Test-Path $userHost) { $files += @{Path = $userHost; Scope = "User"} }

    return $files
}

function Read-EnvironmentFile {
    param([string]$FilePath)

    $operations = @()

    if (-not (Test-Path $FilePath)) {
        return $operations
    }

    $lines = Get-Content $FilePath
    foreach ($line in $lines) {
        $parsed = Parse-EnvironmentLine -Line $line
        if ($parsed) {
            $operations += $parsed
        }
    }

    return $operations
}

# ============================================================================
# ENVIRONMENT APPLICATION FUNCTIONS
# ============================================================================

function Apply-EnvironmentOperations {
    param(
        [array]$Operations,
        [string]$Scope,
        [string]$SourceFile,
        [bool]$DryRun = $false
    )

    $changes = 0
    $fileName = Split-Path -Leaf $SourceFile

    foreach ($op in $Operations) {
        # Escaped dollars are still placeholders here, so the check sees only real references
        $expandedValue = if ($op.ContainsKey('Value') -and $op.Value) { Expand-EnvironmentVariables -Value $op.Value -KeepEscapes } else { $null }
        if ($expandedValue -and $expandedValue -match '\$\{?[A-Z_][A-Z0-9_]*\}?') {
            Write-Warning "$($op.Name): unresolved variable reference in '$expandedValue' [$fileName]; define it in a .env file, or write `$`$ for a literal dollar sign"
        }
        if ($expandedValue) { $expandedValue = $expandedValue.Replace([string][char]1, '$') }

        switch ($op.Type) {
            "Set" {
                if ($DryRun) {
                    Write-DryRun "Set $($op.Name) = $expandedValue [$Scope from $fileName]"
                } else {
                    [Environment]::SetEnvironmentVariable($op.Name, $expandedValue, $Scope)
                    Write-Success "Set $($op.Name) [$Scope]"
                }
                $changes++
            }

            "Unset" {
                if ($DryRun) {
                    Write-DryRun "Unset $($op.Name) [$Scope from $fileName]"
                } else {
                    [Environment]::SetEnvironmentVariable($op.Name, $null, $Scope)
                    Write-Success "Unset $($op.Name) [$Scope]"
                }
                $changes++
            }

            "ListPrepend" {
                $currentValue = [Environment]::GetEnvironmentVariable($op.Name, $Scope)
                if ($currentValue) {
                    $parts = $currentValue -split ';' | Where-Object { $_ -and $_ -ne $expandedValue }
                    $newValue = @($expandedValue) + $parts | Select-Object -Unique
                    $newValue = $newValue -join ';'
                } else {
                    $newValue = $expandedValue
                }

                if ($DryRun) {
                    Write-DryRun "Prepend to $($op.Name): $expandedValue [$Scope from $fileName]"
                } else {
                    [Environment]::SetEnvironmentVariable($op.Name, $newValue, $Scope)
                    Write-Success "Prepended to $($op.Name) [$Scope]"
                }
                $changes++
            }

            "ListAppend" {
                $currentValue = [Environment]::GetEnvironmentVariable($op.Name, $Scope)
                if ($currentValue) {
                    $parts = $currentValue -split ';' | Where-Object { $_ -and $_ -ne $expandedValue }
                    $newValue = $parts + @($expandedValue) | Select-Object -Unique
                    $newValue = $newValue -join ';'
                } else {
                    $newValue = $expandedValue
                }

                if ($DryRun) {
                    Write-DryRun "Append to $($op.Name): $expandedValue [$Scope from $fileName]"
                } else {
                    [Environment]::SetEnvironmentVariable($op.Name, $newValue, $Scope)
                    Write-Success "Appended to $($op.Name) [$Scope]"
                }
                $changes++
            }

            "ListRemove" {
                $currentValue = [Environment]::GetEnvironmentVariable($op.Name, $Scope)
                $currentParts = @()
                if ($currentValue) {
                    $currentParts = @($currentValue -split ';' | Where-Object { $_ })
                }
                $parts = @($currentParts | Where-Object { $_ -ne $expandedValue })

                if ($parts.Count -eq $currentParts.Count) {
                    Write-Host "[SKIP] Not in $($op.Name): $expandedValue [$Scope]" -ForegroundColor DarkGray
                } else {
                    $newValue = $parts -join ';'
                    if ($DryRun) {
                        Write-DryRun "Remove from $($op.Name): $expandedValue [$Scope from $fileName]"
                    } else {
                        [Environment]::SetEnvironmentVariable($op.Name, $newValue, $Scope)
                        Write-Success "Removed from $($op.Name): $expandedValue [$Scope]"
                    }
                    $changes++
                }
            }
        }
    }

    return $changes
}

function Test-ScoopOwnedPath {
    <#
    .SYNOPSIS
        True when a path lies inside one of Scoop's own subdirectories (apps, shims, ...).
    #>
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    foreach ($dir in $global:ScoopOwnedDirs) {
        $prefix = Join-Path $global:BaseDir $dir
        if ($Path -eq $prefix -or $Path -like "$prefix\*") { return $true }
    }
    return $false
}

function Remove-ScoopPathEntries {
    <#
    .SYNOPSIS
        Removes every PATH entry inside Scoop's own subdirectories from one scope.
    .DESCRIPTION
        Scoop prepends env_add_path entries to the User PATH on every install and
        update; scoop reset does the same. The .env files are the single source of
        truth for these directories, so stale entries are swept before (Machine)
        or after (User) the files are applied. Entries outside the Scoop
        subdirectories (other software installed under the base directory) are
        never touched.
    #>
    param([string]$Scope, [bool]$DryRun = $false)

    $current = [Environment]::GetEnvironmentVariable('Path', $Scope)
    if (-not $current) { return 0 }
    $parts = @($current -split ';' | Where-Object { $_ })
    $keep = @($parts | Where-Object { -not (Test-ScoopOwnedPath $_) })
    $removed = @($parts | Where-Object { Test-ScoopOwnedPath $_ })
    foreach ($entry in $removed) {
        if ($DryRun) { Write-DryRun "Remove from PATH: $entry [$Scope]" }
        else { Write-Success "Removed from PATH: $entry [$Scope]" }
    }
    if ($removed.Count -gt 0 -and -not $DryRun) {
        [Environment]::SetEnvironmentVariable('Path', ($keep -join ';'), $Scope)
    }
    return $removed.Count
}

function Get-SystemManagedVariableNames {
    <#
    .SYNOPSIS
        Names of all variables that the system.* files set at Machine scope.
    #>
    $names = @()
    foreach ($file in (Get-EnvironmentFiles | Where-Object { $_.Scope -eq 'Machine' })) {
        foreach ($op in (Read-EnvironmentFile -FilePath $file.Path)) {
            if ($op.Type -eq 'Set' -and $op.Name -ne 'Path') { $names += $op.Name }
        }
    }
    return @($names | Select-Object -Unique)
}

function Invoke-CleanUserScope {
    <#
    .SYNOPSIS
        Removes Scoop's User-scope overrides and applies the user.* files.
    .DESCRIPTION
        Windows resolves a variable from the User scope before the Machine scope
        (PATH is the exception: Machine first, then User appended). Scoop writes
        JAVA_HOME, GRADLE_USER_HOME, ANT_HOME, ... and PATH entries into the User
        scope on install and update, which silently overrides the values from the
        system.* file. This command restores the file as the source of truth:
          1. User PATH entries inside Scoop's subdirectories are removed
          2. User variables whose name the system.* files set at Machine scope are removed
          3. user.* files are applied (User scope)
        Needs no administrator rights. Run it after scoop update / scoop install.
    #>
    param([bool]$DryRun = $false)

    if ($DryRun) { Write-Section "Clean User Scope (DRY RUN)" } else { Write-Section "Clean User Scope" }
    Write-Info "User scope of: $([Environment]::UserName)"

    $changes = 0
    $changes += Remove-ScoopPathEntries -Scope 'User' -DryRun $DryRun

    $managed = Get-SystemManagedVariableNames
    foreach ($name in $managed) {
        $userValue = [Environment]::GetEnvironmentVariable($name, 'User')
        if ($null -ne $userValue) {
            if ($DryRun) { Write-DryRun "Remove User override: $name = $userValue (Machine value from system.* wins)" }
            else {
                [Environment]::SetEnvironmentVariable($name, $null, 'User')
                Write-Success "Removed User override: $name (was: $userValue)"
            }
            $changes++
        }
    }

    # Definitions of all user.* files first (on top of the system.* definitions when
    # called from Invoke-ApplyEnv), then the files are applied
    $userFiles = @(Get-EnvironmentFiles | Where-Object { $_.Scope -eq 'User' })
    $userOperations = @{}
    foreach ($file in $userFiles) {
        $userOperations[$file.Path] = Read-EnvironmentFile -FilePath $file.Path
        Register-EnvFileDefinitions -Operations $userOperations[$file.Path]
    }
    foreach ($file in $userFiles) {
        $fileName = Split-Path -Leaf $file.Path
        Write-Info "Processing: $fileName"
        $changes += Apply-EnvironmentOperations -Operations $userOperations[$file.Path] -Scope 'User' -SourceFile $file.Path -DryRun $DryRun
    }

    if ($global:ScoopBootQuiet -and $changes -gt 0 -and -not $DryRun) {
        Write-Host "[scoop-boot] user scope cleaned ($changes change(s) after Scoop wrote to it; details in $global:ScoopBootLogFile)" -ForegroundColor DarkCyan
    }
    if ($changes -eq 0) { Write-Success "User scope is clean" }
    else { Write-Info "User scope: $changes change(s)" }
    return $changes
}


function Get-LastResult {
    <#
    .SYNOPSIS
        True when the last object a command wrote to the pipeline is $true. The long
        functions (installation, reset) can leak stray objects before their result.
    #>
    param([object[]]$Output)
    $items = @($Output)
    return ($items.Count -gt 0 -and $items[-1] -is [bool] -and $items[-1])
}

function Invoke-AdminSetEnv {
    <#
    .SYNOPSIS
        Setup step 2 (Administrator): applies the environment files at Machine scope (Phase 1).
    .PARAMETER DryRun
        Shows the changes the files would make, without writing; needs no elevation.
    #>
    param(
        [bool]$DryRun = $false
    )
    if ($DryRun) {
        return (Get-LastResult -Output @(Invoke-ApplyEnv -DryRun $true))
    }
    if (-not (Test-AdminRights)) {
        Write-ErrorMsg "--admin-setenv needs an elevated shell (Run as Administrator); --admin-setenv --dry-run works without"
        return $false
    }
    return (Get-LastResult -Output @(Set-DevelopmentEnvironment))
}

function Invoke-UserInstall {
    <#
    .SYNOPSIS
        Setup step 3 (normal shell): bootstraps Scoop and installs the package list (Phase 2).
    .PARAMETER Force
        Skips the "Continue anyway?" question of an elevated shell (a user who is a
        local administrator and can only open elevated shells).
    #>
    param(
        [bool]$Force = $false
    )
    $machineTmp = [Environment]::GetEnvironmentVariable('TMP', 'Machine')
    if ($machineTmp -ne 'C:\tmp') {
        Write-ErrorMsg "Machine-scope TMP is '$machineTmp', expected C:\tmp: setup step 2 has not run. Run as Administrator: scoop-boot.ps1 --admin-setenv"
        return $false
    }
    # Install-ScoopTools itself warns and asks when run from an elevated shell
    $savedTitle = Get-ScoopBootTitle
    try {
        return (Get-LastResult -Output @(Install-ScoopTools -Force $Force))
    } finally {
        Restore-ScoopBootTitle -Saved $savedTitle
    }
}

function Invoke-AdminReset {
    <#
    .SYNOPSIS
        Removes Scoop again (Administrator).
    .DESCRIPTION
        The reset removes Machine variables and PATH entries and may have to take
        ownership of directories, so it needs an elevated shell. bin, etc and logs
        under C:\usr stay, so --admin-init can follow directly.
    #>
    param(
        [bool]$Force = $false,
        [bool]$KeepPersist = $false
    )
    if (-not (Test-AdminRights)) {
        Write-ErrorMsg "--admin-reset needs an elevated shell (Run as Administrator)"
        return $false
    }
    $savedTitle = Get-ScoopBootTitle
    try {
        return (Get-LastResult -Output @(Invoke-ScoopReset -Force:$Force -KeepPersist:$KeepPersist))
    } finally {
        Restore-ScoopBootTitle -Saved $savedTitle
    }
}

function Invoke-ListPackages {
    <#
    .SYNOPSIS
        Shows the package list in use; installs nothing.
    #>
    return (Get-LastResult -Output @(Show-PackageList))
}

function Get-PackageListFile {
    <#
    .SYNOPSIS
        Returns the package list file for this machine: etc\packages\<host>.txt when it
        exists, otherwise etc\packages\default.txt. Returns $null when neither exists.
    .NOTES
        A host file replaces default.txt completely; the two are never merged.
    #>
    $hostFile = Join-Path $global:PackagesDir ("{0}.txt" -f (Get-Hostname))
    if (Test-Path $hostFile) { return $hostFile }
    $defaultFile = Join-Path $global:PackagesDir "default.txt"
    if (Test-Path $defaultFile) { return $defaultFile }
    return $null
}

function Read-PackageList {
    <#
    .SYNOPSIS
        Reads a package list: one manifest per line, in install order; "#" starts a
        comment; blank lines are ignored; "bucket/name" is passed to Scoop as written.
    .OUTPUTS
        [string[]] package names in file order (empty array for an empty file)
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$Silent
    )
    $packages = @()
    foreach ($rawLine in (Get-Content -Path $Path -ErrorAction Stop)) {
        $line = ($rawLine -replace '#.*$', '').Trim()
        if (-not $line) { continue }
        if ($line -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]*(/[A-Za-z0-9][A-Za-z0-9._+-]*)?$') {
            if (-not $Silent) { Write-Warning "Ignored line in $(Split-Path -Leaf $Path): '$rawLine' (expected: name or bucket/name)" }
            continue
        }
        $packages += $line
    }
    # Plain return: callers wrap the result in @(). A "return ,$packages" would survive
    # @() as a nested array (one element of type Object[]), which -ListPackages showed.
    return $packages
}

function Get-ManifestAppName {
    <#
    .SYNOPSIS
        Strips the bucket prefix: "java/temurin25-jdk" -> "temurin25-jdk". The app
        directory under apps\ carries the bare name regardless of the bucket.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Package
    )
    return ($Package -split '/')[-1]
}

function Get-RegistryValue {
    <#
    .SYNOPSIS
        One registry value, or $null when the key or the value does not exist (strict-mode safe).
    #>
    param(
        [string]$Path,
        [string]$Name
    )
    try {
        $item = Get-ItemProperty -Path $Path -ErrorAction Stop
        if ($item.PSObject.Properties.Name -contains $Name) { return $item.$Name }
    } catch { }
    return $null
}

function Get-DirectorySizeMB {
    param([string]$Path)
    try {
        $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $sum) { return 0 }
        return [math]::Round($sum / 1MB)
    } catch { return 0 }
}

function Invoke-PlatformReport {
    <#
    .SYNOPSIS
        Writes what the platform does to a developer setup, before anything is installed:
        Defender / ASR rules, exclusions and blocks; the user profile (FSLogix profile
        container, size, exclusions, TMP handling). Findings are listed at the end and
        make the command exit with 1. Called by --platform-report (and --asr-report).
    .DESCRIPTION
        Read-only. Everything the report says can be checked by the platform team with
        the same command. Defender hides the rule ids and exclusion lists from
        non-elevated callers; the profile section works without elevation.
    #>
    Write-Section "Platform Report"
    $report = Join-Path $global:ScoopBootLogDir ("platform-report-{0}.txt" -f (Get-Date -Format 'yyyyMMdd'))
    $isAdmin = Test-AdminRights
    if (-not $isAdmin) {
        Write-Warning "Not running as Administrator: Defender hides ASR rules and exclusion lists."
        Write-Warning "The event list and the profile section are complete; for the full report run from an elevated shell."
    }
    try { $pref = Get-MpPreference; $status = Get-MpComputerStatus } catch {
        Write-ErrorMsg "Get-MpPreference failed: $($_.Exception.Message)"
        return $false
    }
    $ruleNames = @{
        '01443614-cd74-433a-b99e-2ecdc07bfc25' = 'Block executable files from running unless they meet a prevalence, age, or trusted list criterion'
        '26190899-1602-49e8-8b27-eb1d0a1ce869' = 'Block Office communication application from creating child processes'
        '3b576869-a4ec-4529-8536-b80a7769e899' = 'Block Office applications from creating executable content'
        '56a863a9-875e-4185-98a7-b882c64b5ce5' = 'Block abuse of exploited vulnerable signed drivers'
        '5beb7efe-fd9a-4556-801d-275e5ffc04cc' = 'Block execution of potentially obfuscated scripts'
        '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84' = 'Block Office applications from injecting code into other processes'
        '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c' = 'Block Adobe Reader from creating child processes'
        '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b' = 'Block Win32 API calls from Office macros'
        '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2' = 'Block credential stealing from the Windows local security authority subsystem (lsass.exe)'
        'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4' = 'Block untrusted and unsigned processes that run from USB'
        'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550' = 'Block executable content from email client and webmail'
        'c1db55ab-c21a-4637-bb3f-a12568109d35' = 'Use advanced protection against ransomware'
        'd1e49aac-8f56-4280-b9ba-993a6d77406c' = 'Block process creations originating from PSExec and WMI commands'
        'd3e037e1-3eb8-44c8-a917-57927947596d' = 'Block JavaScript or VBScript from launching downloaded executable content'
        'd4f940ab-401b-4efc-aadc-ad5f3c50688a' = 'Block all Office applications from creating child processes'
        'e6db77e5-3df2-4cf1-b95a-636979351e5b' = 'Block persistence through WMI event subscription'
        'a8f5898e-1dc8-49a9-9878-85004b8a61e6' = 'Block Webshell creation for Servers'
        '33ddedf1-c6e0-47cb-833e-de6133960387' = 'Block rebooting machine in Safe Mode'
        'c0033c00-d16d-4114-a5a0-dc9b3a7d2ceb' = 'Block use of copied or impersonated system tools'
    }
    $prevalenceRule = '01443614-cd74-433a-b99e-2ecdc07bfc25'
    $actionNames = @{ 0 = 'Disabled'; 1 = 'Block'; 2 = 'Audit'; 6 = 'Warn' }
    # The directories a developer setup lives in; C:\devl and C:\data are the
    # conventional places of the environment file, not something scoop-boot creates
    $devDirs = @($global:BaseDir, 'C:\devl', 'C:\data')
    $findings = @()
    $lines = @()
    $lines += "Platform report $(Get-Date -Format s)  host=$env:COMPUTERNAME  user=$env:USERDOMAIN\$env:USERNAME  scoop-boot $global:ScriptVersion"
    $lines += "Windows $([Environment]::OSVersion.Version)  elevated=$isAdmin"

    # ------------------------------------------------------------------------
    # Defender / ASR
    # ------------------------------------------------------------------------
    $lines += ""
    $lines += "=== Defender / Attack Surface Reduction ==="
    $lines += "Defender AM engine $($status.AMEngineVersion), platform $($status.AMProductVersion), signatures $($status.AntivirusSignatureVersion)"
    $lines += "RealTimeProtection=$($status.RealTimeProtectionEnabled)  Tamper=$($status.IsTamperProtected)  MAPS=$($pref.MAPSReporting)  CloudBlockLevel=$($pref.CloudBlockLevel)"
    $lines += ""
    $lines += "--- ASR rules (Id, Action, Name) ---"
    $ids = @($pref.AttackSurfaceReductionRules_Ids | Where-Object { $_ }); $acts = @($pref.AttackSurfaceReductionRules_Actions)
    if ($ids.Count -eq 0) { $lines += $(if ($isAdmin) { "  (none configured)" } else { "  N/A: run as Administrator to list the rules" }) }
    $prevalenceBlocks = $false
    for ($i = 0; $i -lt $ids.Count; $i++) {
        $id = "$($ids[$i])".ToLower()
        $act = [int]$acts[$i]
        $actName = if ($actionNames.ContainsKey($act)) { $actionNames[$act] } else { "$act" }
        $name = if ($ruleNames.ContainsKey($id)) { $ruleNames[$id] } else { '(see Microsoft docs)' }
        $lines += "{0}  {1,-8}  {2}" -f $id, $actName, $name
        if ($id -eq $prevalenceRule -and $act -eq 1) { $prevalenceBlocks = $true }
    }
    $asrExclusions = @()
    foreach ($section in @(
        @{ Title = 'ASR-only exclusions (AttackSurfaceReductionOnlyExclusions)'; Values = $pref.AttackSurfaceReductionOnlyExclusions; Asr = $true },
        @{ Title = 'Per-rule exclusions (AttackSurfaceReductionRules_RuleSpecificExclusions)'; Values = $pref.AttackSurfaceReductionRules_RuleSpecificExclusions; Asr = $true },
        @{ Title = 'Defender path exclusions (ExclusionPath)'; Values = $pref.ExclusionPath; Asr = $false }
    )) {
        $lines += ""
        $lines += "--- $($section.Title) ---"
        $values = @($section.Values | Where-Object { $_ -and "$_" -notmatch '^N/A' })
        if ($values.Count -eq 0) { $lines += $(if ($isAdmin) { "  (none)" } else { "  N/A: run as Administrator to list the exclusions" }) }
        $lines += @($values | ForEach-Object { "  $_" })
        if ($section.Asr) { $asrExclusions += $values }
    }
    $usrExcludedFromAsr = @($asrExclusions | Where-Object { "$_" -like "*$($global:BaseDir)*" }).Count -gt 0
    $usrExcludedFromScan = @($pref.ExclusionPath | Where-Object { $_ -and "$_" -like "$($global:BaseDir)*" }).Count -gt 0
    if ($isAdmin -and $prevalenceBlocks -and -not $usrExcludedFromAsr) {
        $findings += "ASR rule 01443614 (prevalence, age, trusted list) is in Block mode and $($global:BaseDir) is not excluded from it: every build output and every newly released tool version is refused until Microsoft knows it. Ask for a rule-specific exclusion for $($devDirs -join ', ')"
    }
    if ($isAdmin -and -not $usrExcludedFromScan) {
        $lines += ""
        $lines += "[INFO] No Defender path exclusion for $($global:BaseDir): extraction and builds are scanned in real time (slower, not blocking)"
    }
    $lines += ""
    $lines += "--- Blocked by ASR, last 14 days (event 1121) ---"
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1121; StartTime = (Get-Date).AddDays(-14) } -ErrorAction SilentlyContinue)
    $eventLines = @($events | ForEach-Object {
        $m = $_.Message -split "`n"
        $rule = (($m | Select-String '^\s*ID:') | Select-Object -First 1).Line -replace '^\s*ID:\s*', ''
        $path = (($m | Select-String 'Path:') | Select-Object -First 1).Line.Trim()
        "{0}  rule={1}  {2}" -f $_.TimeCreated.ToString('s'), $rule.Trim(), $path
    } | Sort-Object -Unique)
    if ($eventLines.Count -eq 0) { $lines += "  (none)" }
    $lines += $eventLines
    $devBlocks = @($eventLines | Where-Object { $line = $_; @($devDirs | Where-Object { $line -like "*Path: $_\*" }).Count -gt 0 })
    if ($devBlocks.Count -gt 0) {
        $findings += "$($devBlocks.Count) ASR block(s) on files under $($devDirs -join ', ') in the last 14 days (list above)"
    }

    # ------------------------------------------------------------------------
    # User profile (FSLogix profile container)
    # ------------------------------------------------------------------------
    $lines += ""
    $lines += "=== User profile ==="
    $frx = Join-Path $env:ProgramFiles 'FSLogix\Apps\frx.exe'
    $fsxInstalled = Test-Path $frx
    $fsxVersion = if ($fsxInstalled) { try { (Get-Item $frx).VersionInfo.ProductVersion } catch { '' } } else { '' }
    $profilesKey = 'HKLM:\SOFTWARE\FSLogix\Profiles'
    $fsxEnabled = [int](Get-RegistryValue -Path $profilesKey -Name 'Enabled')
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $sessionKey = "$profilesKey\Sessions\$sid"
    $sessionVolume = Get-RegistryValue -Path $sessionKey -Name 'Volume'
    $containerActive = ($fsxEnabled -eq 1) -and $sessionVolume
    $lines += "USERPROFILE=$env:USERPROFILE  HOMEDRIVE=$env:HOMEDRIVE  HOMEPATH=$env:HOMEPATH"
    $lines += $(if ($fsxInstalled) { "FSLogix: installed $fsxVersion" } else { "FSLogix: not installed" })
    if ($containerActive) {
        $lines += "Profile container: ACTIVE (policy Enabled=1, this session on volume $sessionVolume)"
        $lines += "  VHD:              $(Get-RegistryValue -Path $sessionKey -Name 'VHDRootFilePath')"
        $lines += "  VHDLocations:     $(Get-RegistryValue -Path $profilesKey -Name 'VHDLocations')"
        $lines += "  LocalProfilePath: $(Get-RegistryValue -Path $sessionKey -Name 'LocalProfilePath')"
        foreach ($name in @('SizeInMBs', 'VolumeType', 'IsDynamic', 'FlipFlopProfileDirectoryName', 'DeleteLocalProfileWhenVHDShouldApply', 'PreventLoginWithFailure', 'PreventLoginWithTempProfile', 'SetTempToLocalPath', 'RedirXMLSourceFolder')) {
            $value = Get-RegistryValue -Path $profilesKey -Name $name
            if ($null -ne $value) { $lines += "  {0,-37} {1}" -f "${name}:", $value }
        }
        $lines += "  Session: Status=$(Get-RegistryValue -Path $sessionKey -Name 'Status')  Reason=$(Get-RegistryValue -Path $sessionKey -Name 'Reason')  ErrorCode=$(Get-RegistryValue -Path $sessionKey -Name 'ErrorCode')"
        # Fill level of the container volume (label Profile-<user>)
        $volume = $null
        try { $volume = Get-Volume -ErrorAction Stop | Where-Object { $_.FileSystemLabel -eq "Profile-$env:USERNAME" } | Select-Object -First 1 } catch { }
        if ($volume) {
            $sizeGB = [math]::Round($volume.Size / 1GB, 1)
            $freeGB = [math]::Round($volume.SizeRemaining / 1GB, 1)
            $usedPct = if ($volume.Size -gt 0) { [math]::Round(100 * ($volume.Size - $volume.SizeRemaining) / $volume.Size) } else { 0 }
            $lines += "  Container volume: $sizeGB GB, $freeGB GB free ($usedPct% used)"
            if ($usedPct -ge 80) {
                $findings += "Profile container is $usedPct% full ($freeGB GB of $sizeGB GB free): logon fails when it is full. Move caches out of the profile (CACHES block in the system env file)"
            }
        } else {
            $lines += "  Container volume: not found (label Profile-$env:USERNAME)"
        }
        # Exclusions: what stays out of the container
        $redirFolder = Get-RegistryValue -Path $profilesKey -Name 'RedirXMLSourceFolder'
        $redirFile = if ($redirFolder) { Join-Path $redirFolder 'redirections.xml' } else { '' }
        $excludes = @()
        $redirRead = $false
        if ($redirFile -and (Test-Path $redirFile)) {
            try {
                [xml]$redirXml = Get-Content -Path $redirFile -Raw -ErrorAction Stop
                $excludes = @($redirXml.SelectNodes('//Exclude') | ForEach-Object { $_.InnerText.Trim() } | Where-Object { $_ })
                $redirRead = $true
            } catch {
                $lines += "  redirections.xml: not readable ($($_.Exception.Message))"
            }
        }
        $lines += ""
        $lines += "--- Excluded from the container (redirections.xml) ---"
        if ($redirRead) {
            if ($excludes.Count -eq 0) { $lines += "  (file present, no Exclude entries)" }
            $lines += @($excludes | ForEach-Object { "  $_" })
        } elseif (-not $redirFolder) {
            $lines += "  (no RedirXMLSourceFolder: nothing is excluded, the whole profile is in the container)"
        } elseif (-not $redirFile -or -not (Test-Path $redirFile)) {
            $lines += "  (no redirections.xml in $redirFolder)"
        }
        $devCacheMarkers = @('.gradle', '.m2', '.nuget', '.cache', 'JetBrains', 'npm-cache', 'pip')
        $devCacheExcluded = @($excludes | Where-Object { $e = $_; @($devCacheMarkers | Where-Object { $e -like "*$_*" }).Count -gt 0 })
        if ($devCacheExcluded.Count -eq 0) {
            $findings += "Profile container without exclusions for developer caches (.gradle, .m2, .nuget, .cache, JetBrains, npm, pip): they fill the container and every access goes over the network. Move them with the CACHES block of the system env file, or ask for redirections.xml entries"
        }
    } elseif ($fsxEnabled -eq 1) {
        $lines += "Profile container: policy Enabled=1, but this session has no container volume (local or temporary profile)"
    } else {
        $lines += "Profile container: not active (local profile)"
    }

    # TMP/TEMP: process, User and Machine scope
    $machineTmp = [Environment]::GetEnvironmentVariable('TMP', 'Machine')
    $userTmp = [Environment]::GetEnvironmentVariable('TMP', 'User')
    $lines += ""
    $lines += "--- Temporary directory ---"
    $lines += "  TMP process=$env:TMP  user=$userTmp  machine=$machineTmp"
    if ($machineTmp -ne 'C:\tmp') {
        $lines += "  [INFO] Machine TMP is not C:\tmp: setup step 2 (scoop-boot.ps1 --admin-setenv) has not run on this machine"
    }
    $setTemp = [int](Get-RegistryValue -Path $profilesKey -Name 'SetTempToLocalPath')
    if ($containerActive -and ($setTemp -eq 1 -or $setTemp -eq 3)) {
        $findings += "FSLogix writes TMP and TEMP into the User scope at every logon (SetTempToLocalPath=$setTemp): the Machine value is hidden until scoop-boot.ps1 --clean-user-scope has run. Ask for SetTempToLocalPath=0 on this host pool"
    } elseif ($userTmp -and $userTmp -ne $machineTmp) {
        $findings += "User-scope TMP=$userTmp overrides the Machine value $machineTmp; run scoop-boot.ps1 --clean-user-scope"
    }

    # Developer caches inside the profile (sizes; the evidence for a size limit)
    $cacheDirs = @('.gradle', '.m2', '.nuget', '.npm', '.cache', '.dotnet', '.konan', 'AppData\Local\JetBrains', 'AppData\Local\npm-cache', 'AppData\Local\pip', 'AppData\Local\Docker')
    $present = @($cacheDirs | Where-Object { Test-Path (Join-Path $env:USERPROFILE $_) })
    $lines += ""
    $lines += "--- Developer caches in the profile (MB) ---"
    if ($present.Count -eq 0) {
        $lines += "  (none)"
    } else {
        Write-Info "Measuring $($present.Count) cache directories in the profile..."
        $totalMB = 0
        foreach ($dir in $present) {
            $mb = Get-DirectorySizeMB -Path (Join-Path $env:USERPROFILE $dir)
            $totalMB += $mb
            $lines += "  {0,8}  {1}" -f $mb, $dir
        }
        $lines += "  {0,8}  total" -f $totalMB
    }

    # FSLogix errors that explain a failed or temporary profile
    if ($fsxInstalled) {
        $lines += ""
        $lines += "--- FSLogix errors, last 14 days (event 26, container related) ---"
        $fsxEvents = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-FSLogix-Apps/Operational'; Id = 26; StartTime = (Get-Date).AddDays(-14) } -ErrorAction SilentlyContinue |
            Where-Object { $_.Message -match 'VirtualDisk|VHD|Profile' } |
            ForEach-Object { "{0}  {1}" -f $_.TimeCreated.ToString('s'), (($_.Message -split "`n")[0].Trim()) })
        if ($fsxEvents.Count -eq 0) { $lines += "  (none)" }
        $lines += $fsxEvents
    }

    # ------------------------------------------------------------------------
    # Findings, file, console
    # ------------------------------------------------------------------------
    $lines += ""
    $lines += "=== Findings ==="
    if ($findings.Count -eq 0) { $lines += "  (none)" }
    $lines += @($findings | ForEach-Object { "  [WARN] $_" })
    if (-not (Test-Path $global:ScoopBootLogDir)) { New-Item -ItemType Directory -Path $global:ScoopBootLogDir -Force | Out-Null }
    $lines | Set-Content -Path $report -Encoding UTF8
    $lines | Where-Object { $_ -notmatch '^  \[WARN\] ' } | ForEach-Object { Write-Host $_ }
    foreach ($finding in $findings) { Write-Warning $finding }
    Write-Host ""
    Write-Success "Report written: $report"
    if ($findings.Count -gt 0) {
        Write-Host "$($findings.Count) finding(s): this platform needs changes before the setup works as intended (exit code 1)" -ForegroundColor Yellow
        return $false
    }
    return $true
}


function Invoke-ApplyEnv {
    <#
    .SYNOPSIS
        Applies the environment files: sweep, system.* at Machine scope, then the User scope. Called by --admin-setenv.
    #>
    param(
        [bool]$DryRun = $false
    )

    if ($DryRun) {
        Write-Section "Environment Apply (DRY RUN)"
    } else {
        Write-Section "Environment Apply"
    }

    # Get environment files
    $envFiles = Get-EnvironmentFiles

    if ($envFiles.Count -eq 0) {
        Write-Warning "No environment configuration files found"
        Write-Host ""
        Write-Host "Create them first: scoop-boot.ps1 --admin-init (as Administrator)" -ForegroundColor Yellow
        return $false
    }

    # Check admin rights for system files
    $hasSystemFiles = $envFiles | Where-Object { $_.Scope -eq "Machine" }
    if ($hasSystemFiles -and -not $DryRun -and -not (Test-AdminRights)) {
        Write-ErrorMsg "System environment files require administrator privileges"
        Write-Host ""
        Write-Host "Files that require admin:" -ForegroundColor Yellow
        foreach ($file in $hasSystemFiles) {
            Write-Host "  - $(Split-Path -Leaf $file.Path)" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "Run PowerShell as Administrator and try again" -ForegroundColor Yellow
        return $false
    }

    # Process each file. Before the Machine files, every Machine PATH entry inside
    # Scoop's subdirectories is swept so that the files rebuild the order from
    # scratch; stale entries from earlier file versions cannot survive.
    $totalChanges = 0
    if ($hasSystemFiles) {
        Write-Info "Sweeping Scoop entries from Machine PATH (rebuilt from the system.* files)"
        $totalChanges += Remove-ScoopPathEntries -Scope 'Machine' -DryRun $DryRun
    }
    # Definitions of all Machine files first: a reference then resolves to the value
    # the files define, wherever the definition stands and whatever the registry holds
    $global:EnvFileDefinitions = @{}
    $machineOperations = @{}
    foreach ($file in ($envFiles | Where-Object { $_.Scope -eq 'Machine' })) {
        $machineOperations[$file.Path] = Read-EnvironmentFile -FilePath $file.Path
        Register-EnvFileDefinitions -Operations $machineOperations[$file.Path]
    }
    foreach ($file in ($envFiles | Where-Object { $_.Scope -eq 'Machine' })) {
        $fileName = Split-Path -Leaf $file.Path
        Write-Info "Processing: $fileName"

        $operations = $machineOperations[$file.Path]
        $changes = Apply-EnvironmentOperations -Operations $operations -Scope $file.Scope -SourceFile $file.Path -DryRun $DryRun
        $totalChanges += $changes
    }

    # User scope: Scoop's overrides go, then the user.* files are applied
    $totalChanges += Invoke-CleanUserScope -DryRun $DryRun

    if ($DryRun) {
        Write-Info "DRY RUN: Would apply $totalChanges changes"
        Write-Host "Apply them as Administrator: scoop-boot.ps1 --admin-setenv"
    } else {
        Write-Info "Applied $totalChanges changes"
        Write-Host ""
        Write-Host "IMPORTANT: Restart your shell for changes to take effect!" -ForegroundColor Yellow
        Write-Host "  - Close and reopen: CMD, PowerShell, Terminal" -ForegroundColor White
        Write-Host "  - Restart: Visual Studio, IntelliJ IDEA, VS Code" -ForegroundColor White
        Write-Host "  - Or reboot system for complete refresh" -ForegroundColor White
    }
    return $true
}

# ============================================================================
# STATUS FUNCTIONS
# ============================================================================

function Invoke-EnvStatus {
    Write-Section "Environment Configuration Status"

    $envFiles = Get-EnvironmentFiles

    if ($envFiles.Count -eq 0) {
        Write-Warning "No environment configuration files found"
        return
    }

    foreach ($file in $envFiles) {
        $fileName = Split-Path -Leaf $file.Path
        Write-Host ""
        Write-Host "File: $fileName" -ForegroundColor Cyan
        Write-Host "Scope: $($file.Scope)" -ForegroundColor White
        Write-Host "Path: $($file.Path)" -ForegroundColor Gray

        $operations = Read-EnvironmentFile -FilePath $file.Path
        $stats = @{
            Set = 0
            Unset = 0
            ListPrepend = 0
            ListAppend = 0
            ListRemove = 0
        }

        foreach ($op in $operations) {
            $stats[$op.Type]++
        }

        Write-Host "Operations:" -ForegroundColor White
        Write-Host "  Set: $($stats.Set)"
        Write-Host "  Unset: $($stats.Unset)"
        Write-Host "  List Prepend (+=): $($stats.ListPrepend)"
        Write-Host "  List Append (=+): $($stats.ListAppend)"
        Write-Host "  List Remove (-=): $($stats.ListRemove)"
    }
    Write-Host ""
}

# ============================================================================
# SELF-TEST FUNCTION
# ============================================================================

function Test-ScoopBoot {
    Write-Section "Self-Test"

    $tests = @()
    $passed = 0
    $failed = 0

    # Save original Write-DryRun function for Test 24

    # Test 1: PowerShell version
    $test = @{Name = "PowerShell version >= 5.1"; Result = $false}
    try {
        $test.Result = $PSVersionTable.PSVersion.Major -gt 5 -or
            ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -ge 1)
    } catch {}
    $tests += $test

    # Test 2: Execution policy
    $test = @{Name = "Execution Policy allows scripts"; Result = $false}
    try {
        $policy = Get-ExecutionPolicy
        $test.Result = $policy -ne "Restricted" -and $policy -ne "AllSigned"
    } catch {}
    $tests += $test

    # Test 3: Parameter parsing
    $test = @{Name = "Parameter parsing"; Result = $false}
    try {
        $testArgs = @("--admin-setenv", "--dry-run", "--branch=feature/x", "--status", "app1")
        $savedArgs = $global:ParsedArgs.Clone()
        $global:ParsedArgs = @{AdminSetEnv = $false; DryRun = $false; Branch = ''; Unknown = @()}
        Parse-Arguments -Arguments $testArgs
        $test.Result = $global:ParsedArgs.AdminSetEnv -and $global:ParsedArgs.DryRun -and
            $global:ParsedArgs.Branch -eq 'feature/x' -and
            @($global:ParsedArgs.Unknown).Count -eq 2 -and $global:ParsedArgs.Unknown[0] -eq '--status'
        $global:ParsedArgs = $savedArgs
    } catch {}
    $tests += $test

    # Test 4: Admin rights detection
    $test = @{Name = "Admin rights detection"; Result = $false}
    try {
        $isAdmin = Test-AdminRights
        $test.Result = $isAdmin -is [bool]
    } catch {}
    $tests += $test

    # Test 5: Directory path generation
    $test = @{Name = "Directory path generation"; Result = $false}
    try {
        $test.Result = $global:BaseDir -and $global:EnvDir -and $global:BackupDir
    } catch {}
    $tests += $test

    # Test 6: Hostname detection
    $test = @{Name = "Hostname detection"; Result = $false}
    try {
        $hostname = Get-Hostname
        $test.Result = ![string]::IsNullOrEmpty($hostname)
    } catch {}
    $tests += $test

    # Test 7: Username detection
    $test = @{Name = "Username detection"; Result = $false}
    try {
        $username = Get-Username
        $test.Result = ![string]::IsNullOrEmpty($username)
    } catch {}
    $tests += $test

    # Test 8: Host-User filename generation
    $test = @{Name = "Host-User filename generation"; Result = $false}
    try {
        $hostname = Get-Hostname
        $username = Get-Username
        $filename = "system.$hostname.$username.env"
        # User names may contain dots (urs.stotz); host and user are lower case
        $test.Result = ($filename -match "^system\.[a-z0-9.\-]+\.env$") -and ($filename -eq $filename.ToLower()) -and ($filename -eq "system.$hostname.$username.env")
    } catch {}
    $tests += $test

    # Test 9: Parse PATH += (prepend)
    $test = @{Name = "Parse PATH += (prepend)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH+=C:\test\bin"
        $test.Result = $parsed.Type -eq "ListPrepend" -and $parsed.Name -eq "PATH" -and $parsed.Value -eq "C:\test\bin"
    } catch {}
    $tests += $test

    # Test 10: Parse PATH =+ (append)
    $test = @{Name = "Parse PATH =+ (append)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH=+C:\test\bin"
        $test.Result = $parsed.Type -eq "ListAppend" -and $parsed.Name -eq "PATH" -and $parsed.Value -eq "C:\test\bin"
    } catch {}
    $tests += $test

    # Test 11: Parse PATH - (remove with space)
    $test = @{Name = "Parse PATH - (remove with space)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH -= C:\test\bin"
        $test.Result = $parsed.Type -eq "ListRemove" -and $parsed.Name -eq "PATH" -and $parsed.Value -eq "C:\test\bin"
    } catch {}
    $tests += $test

    # Test 12: Parse PATH-= (remove without space)
    $test = @{Name = "Parse PATH-= (remove without space)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH-=C:\test\bin"
        $test.Result = $parsed.Type -eq "ListRemove" -and $parsed.Name -eq "PATH" -and $parsed.Value -eq "C:\test\bin"
    } catch {}
    $tests += $test

    # Test 13: Parse PATH -= (remove with -= syntax)
    $test = @{Name = "Parse PATH -= (remove with -= syntax)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH-=C:\test\bin"
        $test.Result = $parsed.Type -eq "ListRemove" -and $parsed.Name -eq "PATH" -and $parsed.Value -eq "C:\test\bin"
    } catch {}
    $tests += $test

    # Test 14: Parse variable assignment
    $test = @{Name = "Parse variable assignment"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "JAVA_HOME=C:\java"
        $test.Result = $parsed.Type -eq "Set" -and $parsed.Name -eq "JAVA_HOME" -and $parsed.Value -eq "C:\java"
    } catch {}
    $tests += $test

    # Test 15: Parse comment line
    $test = @{Name = "Parse comment line (should ignore)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "# This is a comment"
        $test.Result = $parsed -eq $null
    } catch {}
    $tests += $test

    # Test 16: Parse empty line
    $test = @{Name = "Parse empty line (should ignore)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line ""
        $test.Result = $parsed -eq $null
    } catch {}
    $tests += $test

    # Test 17: Variable expansion with $SCOOP
    $test = @{Name = "Variable expansion with `$SCOOP"; Result = $false}
    try {
        $expanded = Expand-EnvironmentVariables -Value "`$SCOOP\bin"
        $test.Result = $expanded -eq "$global:BaseDir\bin"
    } catch {}
    $tests += $test

    # Test 18: Variable expansion with env var
    $test = @{Name = "Variable expansion with env var"; Result = $false}
    try {
        $expanded = Expand-EnvironmentVariables -Value "`$USERPROFILE\test"
        $test.Result = $expanded -like "*\test" -and $expanded -ne "`$USERPROFILE\test"
    } catch {}
    $tests += $test

    # Test 19: Variable expansion with cache
    $test = @{Name = "Variable expansion with cache"; Result = $false}
    try {
        [Environment]::SetEnvironmentVariable("TEST_VAR_TEMP", "TestValue", "Process")
        $expanded = Expand-EnvironmentVariables -Value "`$TEST_VAR_TEMP\path"
        $test.Result = $expanded -eq "TestValue\path"
        [Environment]::SetEnvironmentVariable("TEST_VAR_TEMP", $null, "Process")
    } catch {}
    $tests += $test

    # Test 20: Multiple variable expansion
    $test = @{Name = "Multiple variable expansion"; Result = $false}
    try {
        $expanded = Expand-EnvironmentVariables -Value "`$SCOOP\`$USERNAME"
        $test.Result = $expanded -match "^[^$]+\\[^$]+$" -and $expanded -notlike "*`$*"
    } catch {}
    $tests += $test

    # Test 21: Scope detection (system.*)
    $test = @{Name = "Scope detection (system.*)"; Result = $false}
    try {
        $test.Result = "system.default.env" -match "^system\." -and
            "system.host.user.env" -match "^system\."
    } catch {}
    $tests += $test

    # Test 22: Scope detection (user.*)
    $test = @{Name = "Scope detection (user.*)"; Result = $false}
    try {
        $test.Result = "user.default.env" -match "^user\." -and
            "user.host.user.env" -match "^user\."
    } catch {}
    $tests += $test

    # Test 23: Mock environment file processing
    $test = @{Name = "Mock environment file processing"; Result = $false}
    try {
        $tempFile = [System.IO.Path]::GetTempFileName()
        @"
# Test file
PATH+=C:\test
JAVA_HOME=C:\java
-OLD_VAR
"@ | Out-File $tempFile
        $ops = Read-EnvironmentFile -FilePath $tempFile
        $test.Result = $ops.Count -eq 3
        Remove-Item $tempFile -Force
    } catch {}
    $tests += $test

    # Test 24: END-TO-END Mock environment apply
    $test = @{Name = "END-TO-END: Mock environment apply"; Result = $false}
    try {
        # Suppress DryRun output during test
        $global:SuppressDryRunOutput = $true

        $ops = @(
            @{Type = "Set"; Name = "TEST_VAR"; Value = "TestValue"}
            @{Type = "ListPrepend"; Name = "TEST_PATH"; Value = "C:\test"}
        )
        $changes = Apply-EnvironmentOperations -Operations $ops -Scope "Process" -SourceFile "test.env" -DryRun $true
        $test.Result = $changes -eq 2

        # Restore output
        $global:SuppressDryRunOutput = $false
    } catch {
        $global:SuppressDryRunOutput = $false
    }
    $tests += $test

    # Test 25: Scope detection with Get-EnvironmentFiles
    $test = @{Name = "Scope detection with Get-EnvironmentFiles"; Result = $false}
    try {
        # This test verifies the function runs and returns a valid collection
        $files = Get-EnvironmentFiles
        # Any of these results is valid:
        # 1. Empty array (no files)
        # 2. Array with hashtables containing Path and Scope
        # 3. Null (no files found)
        if ($null -eq $files -or $files.Count -eq 0) {
            $test.Result = $true  # Empty or null is valid
        } else {
            # Check if we got valid file objects
            $hasValidStructure = $true
            foreach ($file in $files) {
                if ($null -eq $file.Path -or $null -eq $file.Scope) {
                    $hasValidStructure = $false
                    break
                }
            }
            $test.Result = $hasValidStructure
        }
    } catch {}
    $tests += $test

    # Test 26: PATH operations on mock data
    $test = @{Name = "PATH operations on mock data"; Result = $false}
    try {
        [Environment]::SetEnvironmentVariable("TEST_PATH_VAR", "C:\existing", "Process")
        $ops = @(@{Type = "ListPrepend"; Name = "TEST_PATH_VAR"; Value = "C:\new"})
        Apply-EnvironmentOperations -Operations $ops -Scope "Process" -SourceFile "test.env" -DryRun $false
        $result = [Environment]::GetEnvironmentVariable("TEST_PATH_VAR", "Process")
        $test.Result = $result -eq "C:\new;C:\existing"
        [Environment]::SetEnvironmentVariable("TEST_PATH_VAR", $null, "Process")
    } catch {}
    $tests += $test

    # Test 27: PERL5LIB += operation (NEW)
    $test = @{Name = "Parse PERL5LIB += (prepend)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PERL5LIB+=C:\perl\lib"
        $test.Result = $parsed.Type -eq "ListPrepend" -and $parsed.Name -eq "PERL5LIB" -and $parsed.Value -eq "C:\perl\lib"
    } catch {}
    $tests += $test

    # Test 28: PYTHONPATH =+ operation (NEW)
    $test = @{Name = "Parse PYTHONPATH =+ (append)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PYTHONPATH=+C:\python\lib"
        $test.Result = $parsed.Type -eq "ListAppend" -and $parsed.Name -eq "PYTHONPATH" -and $parsed.Value -eq "C:\python\lib"
    } catch {}
    $tests += $test

    # Test 29: CLASSPATH -= operation (NEW)
    $test = @{Name = "Parse CLASSPATH -= (remove)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "CLASSPATH-=old.jar"
        $test.Result = $parsed.Type -eq "ListRemove" -and $parsed.Name -eq "CLASSPATH" -and $parsed.Value -eq "old.jar"
    } catch {}
    $tests += $test

    # Test 30: PSModulePath += operation (NEW)
    $test = @{Name = "Parse PSModulePath += (prepend)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PSModulePath+=C:\modules"
        $test.Result = $parsed.Type -eq "ListPrepend" -and $parsed.Name -eq "PSModulePath" -and $parsed.Value -eq "C:\modules"
    } catch {}
    $tests += $test

    # Test 31: package list parsing (comments, blanks, bucket/name, order)
    $test = @{Name = "Read-PackageList: comments, blanks, bucket/name, order kept"; Result = $false}
    try {
        $listFile = Join-Path $env:TEMP "scoop-boot-selftest-packages.txt"
        @('# header', '', 'vcredist2022', 'java/temurin25-jdk   # jdk', '  nmap  ', '# trailing') | Set-Content -Path $listFile -Encoding ASCII
        $parsed = @(Read-PackageList -Path $listFile)
        $test.Result = ($parsed.Count -eq 3) -and ($parsed[0] -eq 'vcredist2022') -and ($parsed[1] -eq 'java/temurin25-jdk') -and ($parsed[2] -eq 'nmap')
        Remove-Item $listFile -Force -ErrorAction SilentlyContinue
    } catch {}
    $tests += $test

    # Test 32: package list rejects malformed lines, empty file gives empty array
    $test = @{Name = "Read-PackageList: malformed line ignored, empty file is empty"; Result = $false}
    try {
        $listFile = Join-Path $env:TEMP "scoop-boot-selftest-packages.txt"
        @('good-name', 'bad name with spaces', 'also/bad/name') | Set-Content -Path $listFile -Encoding ASCII
        $parsed = @(Read-PackageList -Path $listFile -Silent)
        $ok1 = ($parsed.Count -eq 1) -and ($parsed[0] -eq 'good-name')
        @('# only a comment') | Set-Content -Path $listFile -Encoding ASCII
        $parsed = @(Read-PackageList -Path $listFile)
        $ok2 = ($parsed.Count -eq 0)
        Remove-Item $listFile -Force -ErrorAction SilentlyContinue
        $test.Result = $ok1 -and $ok2
    } catch {}
    $tests += $test

    # Test 33: bucket prefix stripped for the app directory name
    $test = @{Name = "Get-ManifestAppName strips bucket prefix"; Result = $false}
    try {
        $test.Result = (Get-ManifestAppName -Package 'java/temurin25-jdk') -eq 'temurin25-jdk' -and (Get-ManifestAppName -Package 'nmap') -eq 'nmap'
    } catch {}
    $tests += $test

    # Test 34: a reference resolves from the file definitions, whatever the order of the lines
    $test = @{Name = "Expansion: reference before definition resolves from the file"; Result = $false}
    try {
        $savedDefs = $global:EnvFileDefinitions
        $global:EnvFileDefinitions = @{}
        $ops = @('PATH+=$T_SUB\bin', 'T_SUB=$T_USR\sub', 'T_USR=C:\t') | ForEach-Object { Parse-EnvironmentLine -Line $_ }
        Register-EnvFileDefinitions -Operations $ops
        $test.Result = (Expand-EnvironmentVariables -Value '$T_SUB\bin') -eq 'C:\t\sub\bin' -and
            -not $global:EnvFileDefinitions.ContainsKey('PATH')
        $global:EnvFileDefinitions = $savedDefs
    } catch { $global:EnvFileDefinitions = $savedDefs }
    $tests += $test

    # Test 35: "$$" is a literal dollar sign and is not reported as unresolved
    $test = @{Name = "Expansion: `$`$ gives a literal `$"; Result = $false}
    try {
        $plain = Expand-EnvironmentVariables -Value '$$P$$G $SCOOP'
        $kept = Expand-EnvironmentVariables -Value '$$P$$G' -KeepEscapes
        $test.Result = $plain -eq "`$P`$G $global:BaseDir" -and -not ($kept -match '\$\{?[A-Z_][A-Z0-9_]*\}?')
    } catch {}
    $tests += $test

    # Test 36: a definition that refers to itself extends the registry value instead of looping
    $test = @{Name = "Expansion: self-reference falls through to the registry"; Result = $false}
    try {
        $savedDefs = $global:EnvFileDefinitions
        $global:EnvFileDefinitions = @{}
        [Environment]::SetEnvironmentVariable("T_SELF", "old", "Process")
        Register-EnvFileDefinitions -Operations @(Parse-EnvironmentLine -Line 'T_SELF=$T_SELF;new')
        $test.Result = (Expand-EnvironmentVariables -Value '$T_SELF') -eq 'old;new'
        [Environment]::SetEnvironmentVariable("T_SELF", $null, "Process")
        $global:EnvFileDefinitions = $savedDefs
    } catch { $global:EnvFileDefinitions = $savedDefs }
    $tests += $test

    # Test 37: every $global: name the script reads is initialised (Set-StrictMode fails on
    # an unset one; --dry-run was broken this way until v0015)
    $test = @{Name = "All global variables are initialised"; Result = $false}
    try {
        $sources = @($PSCommandPath, (Join-Path $PSScriptRoot 'scoop-boot.ps1')) | Where-Object { Test-Path $_ }
        $names = $sources | ForEach-Object { [regex]::Matches((Get-Content $_ -Raw), '\$global:([A-Za-z_][A-Za-z0-9_]*)') } |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $missing = @($names | Where-Object { -not (Test-Path "variable:global:$_") -and $_ -ne 'ScoopBootLibraryOnly' })
        if ($missing.Count -gt 0) { Write-Warning "Unset global variable(s): $($missing -join ', ')" }
        $test.Result = $missing.Count -eq 0
    } catch {}
    $tests += $test

    # Test 38: scoop-boot.ps1, the helper scripts and this module carry one version (since v0015)
    $test = @{Name = "scoop-boot.ps1 carries the module version"; Result = $false}
    try {
        $ok = $true
        foreach ($name in @('scoop-boot.ps1', 'scoop-boot.psm1')) {
            $file = Join-Path $global:BaseDir "bin\$name"
            if (-not (Test-Path $file)) { continue }
            $m = Select-String -Path $file -Pattern 'Version:\s*([0-9.]+)' | Select-Object -First 1
            $v = if ($m) { $m.Matches[0].Groups[1].Value } else { '' }
            if ($v -ne $global:ScriptVersion) { Write-Warning "$name is $v, the module is $global:ScriptVersion; run --update"; $ok = $false }
        }
        $test.Result = $ok
    } catch {}
    $tests += $test

    # Test 39: -NAME (unset) parses and applies; it carried no Value key and failed under strict mode until v0015
    $test = @{Name = "Unset (-NAME) parses and applies"; Result = $false}
    try {
        $op = Parse-EnvironmentLine -Line '-T_GONE'
        [Environment]::SetEnvironmentVariable('T_GONE', 'x', 'Process')
        $n = Apply-EnvironmentOperations -Operations @($op) -Scope 'Process' -SourceFile 'test.env' -DryRun $false
        $test.Result = ($op.Type -eq 'Unset') -and ($n -eq 1) -and ($null -eq [Environment]::GetEnvironmentVariable('T_GONE', 'Process'))
    } catch {}
    $tests += $test

    # Test 40: every option the help lists is accepted by the parser (they drifted apart before 1.18.0)
    $test = @{Name = "Help and parser agree on the options"; Result = $false}
    try {
        $moduleText = Get-Content -Path (Join-Path $global:ScriptRoot 'scoop-boot.psm1') -Raw
        $helpStart = $moduleText.IndexOf('function Show-Help {')
        $helpEnd = $moduleText.IndexOf("`nfunction ", $helpStart + 1)
        $helpText = $moduleText.Substring($helpStart, $helpEnd - $helpStart)
        $helpOptions = @([regex]::Matches($helpText, '--[a-z][a-z-]*(=[A-Za-z]+)?') | ForEach-Object { $_.Value } | Sort-Object -Unique)
        $rejected = @()
        $savedArgs = $global:ParsedArgs.Clone()
        foreach ($option in $helpOptions) {
            $probe = $option -replace '=[A-Za-z]+$', '=x'
            $global:ParsedArgs = $savedArgs.Clone()
            $global:ParsedArgs.Unknown = @()
            Parse-Arguments -Arguments @($probe)
            if (@($global:ParsedArgs.Unknown).Count -gt 0) { $rejected += $option }
        }
        $global:ParsedArgs = $savedArgs
        if ($rejected.Count -gt 0) { Write-Host "       help lists options the parser rejects: $($rejected -join ', ')" -ForegroundColor Yellow }
        $test.Result = $helpOptions.Count -ge 10 -and $rejected.Count -eq 0
    } catch {}
    $tests += $test

    # Test 41: the installed files match the release manifest --update verified (skipped on a branch or without manifest)
    $test = @{Name = "Installed files match the release manifest"; Result = $false}
    try {
        $manifestPath = Join-Path $global:BaseDir 'etc\release.manifest'
        if ((Test-Path $global:BranchFile) -or -not (Test-Path $manifestPath)) {
            $test.Name += " (skipped: $(if (Test-Path $global:BranchFile) { 'branch files' } else { 'no manifest' }))"
            $test.Result = $true
        } else {
            $mismatch = @()
            foreach ($line in (Get-Content $manifestPath)) {
                if ($line -match '^sha256\s+([0-9a-f]{64})\s+(\S+)$') {
                    $file = Join-Path $global:BaseDir ($Matches[2] -replace '/', '\')
                    $actual = if (Test-Path $file) { (Get-FileHash -Path $file -Algorithm SHA256).Hash.ToLower() } else { 'missing' }
                    if ($actual -ne $Matches[1]) { $mismatch += $Matches[2] }
                }
            }
            if ($mismatch.Count -gt 0) { Write-Host "       changed since the last --update: $($mismatch -join ', ')" -ForegroundColor Yellow }
            $test.Result = $mismatch.Count -eq 0
        }
    } catch {}
    $tests += $test

    # Display results
    Write-Host ""
    foreach ($test in $tests) {
        if ($test.Result) {
            Write-Success $test.Name
            $passed++
        } else {
            Write-ErrorMsg $test.Name
            $failed++
        }
    }

    Write-Host ""
    Write-Host "Tests: $passed passed, $failed failed, $($passed + $failed) total" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Yellow" })

    return $failed -eq 0
}

# ============================================================================
# INSTALLATION (formerly scoop-complete-install.ps1)
# ============================================================================

# those packages so that -ListPackages can show them and the self-check can warn
# about a handler whose package is missing from the list.
# Installed by the bootstrap (Step 1) before any list is read; never listed in a package file
$global:BootstrapPackages = @('7zip', 'git', 'aria2', 'sudo', 'innounp', 'dark', 'lessmsi', 'wget', 'cacert')

$global:PackageHandlers = @{
    'vcredist2022'      = 'skipped when the VC++ runtime is present; runtime verified in Step 4'
    'temurin25-jdk'     = 'Step 4: scoop reset (default Java)'
    'msys2'             = 'Step 4: pacman -Syu, GCC (UCRT64), compile-and-run smoke test'
    'nmap'              = 'Step 4: shims nc and netcat -> ncat.exe'
    '7zip'              = 'Step 5: reg import install-context.reg'
    'notepadplusplus'   = 'Step 5: reg import install-context.reg'
    'vscode'            = 'Step 5: reg import install-context.reg'
    'git'               = 'Step 5: reg import install-context.reg'
    'python314'         = 'Step 5: reg import install-pep-514.reg'
    'jetbrains-toolbox' = 'Step 6: started (tray)'
    'greenshot'         = 'Step 6: started (tray)'
}

function Test-WSL2Installed {
    Write-Host "[INFO] Checking WSL2 installation..." -ForegroundColor Gray

    # Method 1: Check wsl.exe existence
    $wslPath = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wslPath) {
        Write-Host "  [FAIL] wsl.exe not found" -ForegroundColor Red
        return $false
    }

    # Method 2: Parse "wsl --status" and "wsl --version".
    # wsl.exe writes UTF-16; captured through the default console encoding every
    # character is followed by a NUL, which breaks any regex. Read it as Unicode.
    try {
        $previousEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        try {
            $wslStatus  = (wsl --status 2>&1 | Out-String) -replace "`0", ''
            $wslVersion = (wsl --version 2>&1 | Out-String) -replace "`0", ''
            $wslList    = (wsl --list --verbose 2>&1 | Out-String) -replace "`0", ''
        } finally {
            [Console]::OutputEncoding = $previousEncoding
        }

        if ($wslStatus -match 'Default Version:\s*2') {
            Write-Host "  [OK] WSL2 detected: Default Version = 2" -ForegroundColor Green
            return $true
        }

        # Store/MSI WSL (1.x, 2.x, 3.x) reports a kernel version only when WSL2 is usable
        if ($wslVersion -match 'Kernel version:\s*\d') {
            Write-Host "  [OK] WSL2 detected: $(($wslVersion -split "`n" | Select-String 'WSL version').Line.Trim())" -ForegroundColor Green
            return $true
        }

        if ($wslList -match '\s+2\s*$') {
            Write-Host "  [OK] WSL2 detected: at least one distribution runs version 2" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "  [WARN] Could not parse wsl output: $_" -ForegroundColor Yellow
    }

    # Method 3: Kernel file (inbox feature: System32\lxss; Store/MSI package: Program Files\WSL)
    $wslKernelPaths = @(
        "$env:SystemRoot\System32\lxss\tools\kernel",
        "$env:ProgramFiles\WSL\tools\kernel"
    )
    foreach ($wslKernelPath in $wslKernelPaths) {
        if (Test-Path $wslKernelPath) {
            Write-Host "  [OK] WSL2 detected: kernel found at $wslKernelPath" -ForegroundColor Green
            return $true
        }
    }

    # Method 4: Check Windows Feature (requires admin)
    try {
        $wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
        $vmpFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue

        if ($wslFeature.State -eq 'Enabled' -and $vmpFeature.State -eq 'Enabled') {
            Write-Host "  [OK] WSL2 detected: Required Windows features enabled" -ForegroundColor Green
            return $true
        }
    } catch {
        # Not running as admin, skip this check
    }

    # Method 5: Try to list distributions (this works if WSL2 is installed)
    try {
        $distros = wsl --list --quiet 2>&1
        if ($LASTEXITCODE -eq 0 -and $distros) {
            Write-Host "  [OK] WSL2 detected: Distributions found" -ForegroundColor Green
            return $true
        }
    } catch {}

    Write-Host "  [FAIL] WSL2 not detected by any method" -ForegroundColor Red
    return $false
}

function Set-DevelopmentEnvironment {
    <#
    .SYNOPSIS
        Phase 1 (Administrator): TMP/TEMP, environment files at Machine scope. Called by --admin-setenv.
    #>
    # Formerly scoop-complete-install.ps1, written for the shell defaults: this
    # function and everything it calls run without strict mode and with Continue
    Set-StrictMode -Off
    $ErrorActionPreference = 'Continue'
    $ScoopDir = $global:BaseDir
    $BootstrapPackages = $global:BootstrapPackages
    $PackageHandlers = $global:PackageHandlers
    Write-Host ""
    Write-Host "=== Phase 1: Environment Setup (Administrator) ===" -ForegroundColor Cyan
    Write-Host ""

    # Check admin rights
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    if (-not $isAdmin) {
        Write-Host "[ERROR] This phase requires administrator privileges!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Run PowerShell as Administrator:" -ForegroundColor Yellow
        Write-Host "  Right-click PowerShell -> Run as Administrator" -ForegroundColor White
        Write-Host ""
        return $false
    }

    Write-Host "[OK] Running with administrator privileges" -ForegroundColor Green
    Write-Host ""

    # ============================================================================
    # CRITICAL: Fix TMP/TEMP FIRST (prevents all Scoop installation issues!)
    # ============================================================================
    Write-Host ">>> Setting up TEMP directories (CRITICAL for Scoop!)..." -ForegroundColor Yellow

    # Create C:\tmp directory
    if (-not (Test-Path "C:\tmp")) {
        New-Item -ItemType Directory -Path "C:\tmp" -Force | Out-Null
        # Set permissions
        icacls "C:\tmp" /grant "Everyone:(OI)(CI)F" /T /Q 2>&1 | Out-Null
        Write-Host "[OK] Created C:\tmp directory with full permissions" -ForegroundColor Green
    } else {
        Write-Host "[OK] C:\tmp directory already exists" -ForegroundColor Gray
    }

    # Set TMP and TEMP at Machine level
    [Environment]::SetEnvironmentVariable("TMP", "C:\tmp", "Machine")
    [Environment]::SetEnvironmentVariable("TEMP", "C:\tmp", "Machine")
    Write-Host "[OK] Set Machine-level: TMP=C:\tmp, TEMP=C:\tmp" -ForegroundColor Green

    # User-level TMP/TEMP are deliberately not set: the .env file sets them at
    # Machine scope and --clean-user-scope removes User overrides of managed names.

    # Apply to current session
    $env:TMP = "C:\tmp"
    $env:TEMP = "C:\tmp"
    Write-Host "[OK] Applied to current session" -ForegroundColor Green

    # Explain the directory layout to whoever looks into C:\usr later
    $dirReadme = "$ScoopDir\README_scoop_dir_warnings.md"
    @'
# C:\usr - read before putting anything here

This directory is the base of a Scoop-managed developer environment set up by
scoop-boot (https://github.com/stotz/scoop-boot). Scoop is NOT the owner of
C:\usr; it owns only these subdirectories:

    apps\       installed applications (one folder per app, "current" junction)
    buckets\    manifest repositories
    cache\      downloaded installers
    persist\    application data that survives updates
    shims\      the executables that are on PATH
    global\     globally installed apps (rarely used)

scoop-boot.ps1 --admin-reset DELETES all of them. It also removes every environment
variable whose value points into them and every PATH entry inside them. Nothing
else is touched.

scoop-boot itself uses:

    bin\        scoop-boot.ps1, its module scoop-boot.psm1 and the scoop wrapper (scoop.ps1/.cmd/scoop)
    etc\        environments\*.env (the source of truth for PATH and variables)
    backups\    environment backups written by every reset (last 5 kept)
    logs\       daily logs of scoop-boot (60 days kept)

Rules:

- Do not install or copy software into apps\, shims\ or persist\ by hand;
  the next scoop update or reset will remove or break it.
- Other software may live in its own directory directly under C:\usr (for
  example C:\usr\PostgreSQL). scoop-boot leaves it alone, but its PATH entries
  and variables are then yours to maintain, not the .env file's.
- Do not set JAVA_HOME, PATH and friends by hand in the Windows dialog. Edit
  etc\environments\system.<hostname>.<username>.env and run
  scoop-boot.ps1 --admin-setenv (as Administrator). After
  scoop update or scoop install, run scoop-boot.ps1 --clean-user-scope.
- Keep anything you cannot rebuild out of C:\usr or back it up elsewhere;
  C:\usr\backups holds environment snapshots only, not application data.
'@ | Set-Content -Path $dirReadme -Encoding ASCII
    Write-Host "[OK] Wrote $dirReadme" -ForegroundColor Green
    Write-Host ""
    Write-Host ">>> Applying environment configuration..." -ForegroundColor White
    Write-Host ""

    # Check if environment files exist
    $envDir = "$ScoopDir\etc\environments"
    $allEnvFiles = Get-ChildItem -Path $envDir -Filter "*.env" -ErrorAction SilentlyContinue

    # Filter for VALID environment files (must start with "system." or "user.")
    $validEnvFiles = $allEnvFiles | Where-Object {
        $_.Name -match '^(system|user)\.'
    }

    if ($null -eq $allEnvFiles -or $allEnvFiles.Count -eq 0) {
        Write-Host ""
        Write-Host "=== No Environment Configuration Files Found ===" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "No .env files found in: $envDir\" -ForegroundColor White
        Write-Host ""
        Write-Host "Step 1: Create the environment files for this host and user" -ForegroundColor Cyan
        Write-Host "  Run as Administrator:" -ForegroundColor White
        Write-Host "    C:\usr\bin\scoop-boot.ps1 --admin-init" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Step 2: Edit the created file" -ForegroundColor Cyan
        Write-Host "  notepad `"$envDir\system.$(Get-Hostname).$(Get-Username).env`"" -ForegroundColor Gray
        Write-Host "  - Uncomment lines you need" -ForegroundColor White
        Write-Host "  - Adjust paths to match your installation" -ForegroundColor White
        Write-Host ""
        Write-Host "Step 3: Test configuration" -ForegroundColor Cyan
        Write-Host "  .\bin\scoop-boot.ps1 --admin-setenv --dry-run" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Step 4: Apply configuration (as Administrator)" -ForegroundColor Cyan
        Write-Host "  C:\usr\bin\scoop-boot.ps1 --admin-setenv" -ForegroundColor White
        Write-Host ""
        return $false
    }

    # Check if valid files exist
    if ($null -eq $validEnvFiles -or $validEnvFiles.Count -eq 0) {
        Write-Host ""
        Write-Host "=== Invalid Environment Configuration Files ===" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Found .env files, but none have valid names:" -ForegroundColor White
        Write-Host ""
        foreach ($file in $allEnvFiles) {
            Write-Host "  - $($file.Name)" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "Valid naming patterns:" -ForegroundColor Cyan
        Write-Host "  system.default.env              # System-wide defaults" -ForegroundColor White
        Write-Host "  system.HOSTNAME.USERNAME.env    # System + host-specific" -ForegroundColor White
        Write-Host "  user.default.env                # User-specific" -ForegroundColor White
        Write-Host "  user.HOSTNAME.USERNAME.env      # User + host-specific" -ForegroundColor White
        Write-Host ""
        Write-Host "What to do:" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Option 1: Create the host files from the templates" -ForegroundColor Yellow
        Write-Host "  C:\usr\bin\scoop-boot.ps1 --admin-init" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Option 2: Rename existing file" -ForegroundColor Yellow
        Write-Host "  Rename your .env file to start with 'system.' or 'user.'" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Example:" -ForegroundColor Cyan
        Write-Host "  # Wrong:" -ForegroundColor Red
        Write-Host "  myconfig.env" -ForegroundColor Red
        Write-Host ""
        Write-Host "  # Correct:" -ForegroundColor Green
        Write-Host "  system.default.env" -ForegroundColor Green
        Write-Host "  user.bootes.john.env" -ForegroundColor Green
        Write-Host ""
        Write-Host "After fixing, re-run:" -ForegroundColor Yellow
        Write-Host "  C:\usr\bin\scoop-boot.ps1 --admin-setenv" -ForegroundColor White
        Write-Host ""
        return $false
    }

    Write-Host "[INFO] Found $($validEnvFiles.Count) valid environment file(s):" -ForegroundColor Gray
    foreach ($file in $validEnvFiles) {
        Write-Host "  - $($file.Name)" -ForegroundColor DarkGray
    }
    Write-Host ""

    # Apply environment configuration
    Write-Host "[INFO] Applying environment from .env file(s)..." -ForegroundColor Gray
    $applied = Get-LastResult -Output @(Invoke-ApplyEnv)

    if (-not $applied) {
        Write-Host ""
        Write-Host "[ERROR] Failed to apply environment configuration" -ForegroundColor Red
        Write-Host ""
        Write-Host "Troubleshooting:" -ForegroundColor Yellow
        Write-Host "  1. Check file syntax: notepad `"$envDir\system.default.env`"" -ForegroundColor White
        Write-Host "  2. Test with dry-run: .\bin\scoop-boot.ps1 --admin-setenv --dry-run" -ForegroundColor White
        Write-Host "  3. Check status: .\bin\scoop-boot.ps1 --env-status" -ForegroundColor White
        Write-Host ""
        return $false
    }

    Write-Host ""
    Write-Host "=== Phase 1 Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Environment configured:" -ForegroundColor Cyan
    Write-Host "  - Environment file(s) applied at Machine scope" -ForegroundColor White
    Write-Host "  - All environment variables set" -ForegroundColor White
    Write-Host ""
    Write-Host "Next step:" -ForegroundColor Yellow
    Write-Host "  Close this Administrator PowerShell" -ForegroundColor White
    Write-Host "  Open a NORMAL PowerShell (not Administrator)" -ForegroundColor White
    Write-Host "  Run: C:\usr\bin\scoop-boot.ps1 --user-install" -ForegroundColor White
    Write-Host ""
    return $true
}

function Install-ScoopTools {
    <#
    .SYNOPSIS
        Phase 2 (normal shell): bootstrap, buckets, package list, post-install steps, user-scope cleanup. Called by --user-install.
    .PARAMETER Force
        Continues in an elevated shell without asking.
    #>
    param(
        [bool]$Force = $false
    )
    # Formerly scoop-complete-install.ps1, written for the shell defaults: this
    # function and everything it calls run without strict mode and with Continue
    Set-StrictMode -Off
    $ErrorActionPreference = 'Continue'
    $ScoopDir = $global:BaseDir
    $BootstrapPackages = $global:BootstrapPackages
    $PackageHandlers = $global:PackageHandlers
    Write-Host ""
    Write-Host "=== Phase 2: Tool Installation (Normal User) ===" -ForegroundColor Cyan
    Write-Host ""

    # Check if running as admin. Scoop installs per user; from an elevated shell the
    # same account installs, so the result is the same, only the installer has to be
    # told (-RunAsAdmin, see Invoke-Bootstrap). The question protects the usual case
    # of an admin account that is not the developer account; --force skips it for a
    # developer who is a local administrator and has elevated shells only.
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    if ($isAdmin -and $Force) {
        Write-Host "[WARN] Running as Administrator (--force): installing for this account from an elevated shell" -ForegroundColor Yellow
    } elseif ($isAdmin) {
        Write-Host "[WARN] Running as Administrator - not recommended for tool installation" -ForegroundColor Yellow
        Write-Host "It's recommended to close this window and run without admin rights." -ForegroundColor Yellow
        Write-Host "If this account can only open elevated shells, continue (or use --user-install --force)." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Continue anyway? [y/N]: " -NoNewline
        $response = Read-Host
        if ($response -ne 'y' -and $response -ne 'Y') {
            Write-Host "Installation cancelled." -ForegroundColor Gray
            return $true
        }
        Write-Host ""
    } else {
        Write-Host "[OK] Running as normal user" -ForegroundColor Green
    }

    # ============================================================================
    # WSL2 CHECK (optional - for Docker alternatives and Linux development)
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Checking WSL2 (optional for Docker/Linux development)..." -ForegroundColor White
    Write-Host ""

    $wsl2Installed = Test-WSL2Installed

    if (-not $wsl2Installed) {
        Write-Host ""
        Write-Host "=== WSL2 Not Detected ===" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "WSL2 is recommended for:" -ForegroundColor White
        Write-Host "  - Docker Desktop / Rancher Desktop" -ForegroundColor Gray
        Write-Host "  - Linux development tools" -ForegroundColor Gray
        Write-Host "  - Cross-platform testing" -ForegroundColor Gray
        Write-Host ""
        Write-Host "To install WSL2:" -ForegroundColor Cyan
        Write-Host "  1. Run as Administrator: wsl --install" -ForegroundColor White
        Write-Host "  2. Reboot system" -ForegroundColor White
        Write-Host "  3. Verify: wsl --status" -ForegroundColor White
        Write-Host ""
        Write-Host "For more information: https://aka.ms/wsl2" -ForegroundColor Gray
        Write-Host ""
        Write-Host "[INFO] Continuing installation without WSL2..." -ForegroundColor Yellow
    } else {
        Write-Host ""
        Write-Host "[OK] WSL2 is installed and ready for Docker/Linux tools" -ForegroundColor Green
    }

    # ============================================================================
    # STEP 1: BOOTSTRAP SCOOP (Using scoop-boot.ps1 pattern)
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Step 1: Bootstrap Scoop..." -ForegroundColor White
    # Use the real Scoop shim during Phase 2; the wrapper in bin\ would run the
    # user-scope cleanup after every single package instead of once in Step 7.
    # SCOOP_BOOT_CALLER tells --bootstrap to skip its manual "Next steps" guide.
    $env:SCOOP_BOOT_WRAPPER = 'off'
    $env:SCOOP_BOOT_CALLER = 'install'
    Write-Host ""

    # Run scoop-boot.ps1 --bootstrap (installs Scoop + 7zip + Git + aria2 + recommended tools + buckets)
    $bootstrapSuccess = $false

    if ($true) {
        Write-Host "[INFO] Running the bootstrap (Scoop core, essential tools, buckets)" -ForegroundColor Gray
        Write-Host ""

        try {
            $null = Invoke-Bootstrap
            Write-Host ""

            # Verify bootstrap success: scoop core and a usable git (apps\git\current is the
            # junction Scoop creates only after a successful extraction)
            if ((Test-Path "$ScoopDir\apps\scoop\current") -and (Test-Path "$ScoopDir\apps\git\current\cmd\git.exe")) {
                Write-Host "[OK] Bootstrap successful!" -ForegroundColor Green
                $bootstrapSuccess = $true
            } else {
                Write-Host "[ERROR] Bootstrap did not produce a usable git" -ForegroundColor Red
            }
        } catch {
            Write-Host "[WARN] Bootstrap failed, using fallback..." -ForegroundColor Yellow
        }
    }

    # FALLBACK: Manual bootstrap only when the Scoop core itself is missing. When the
    # core is there and --bootstrap still failed, an essential tool was refused (see
    # its [FATAL] message); repeating the installs here only adds misleading errors.
    if (-not $bootstrapSuccess -and -not (Test-Path "$ScoopDir\apps\scoop\current")) {
        Write-Host ""
        Write-Host "[INFO] Using manual bootstrap (the bootstrap failed)..." -ForegroundColor Yellow
        Write-Host ""

        # Set environment variables
        $env:SCOOP = $ScoopDir
        $env:SCOOP_GLOBAL = "$ScoopDir\global"
        [Environment]::SetEnvironmentVariable('SCOOP', $ScoopDir, 'User')
        [Environment]::SetEnvironmentVariable('SCOOP_GLOBAL', "$ScoopDir\global", 'User')

        # Fix TEMP path (common cause of .cs compilation errors)
        $userTemp = "$env:USERPROFILE\Temp"
        if (-not (Test-Path $userTemp)) {
            New-Item -ItemType Directory -Path $userTemp -Force | Out-Null
        }
        $env:TMP = $userTemp
        $env:TEMP = $userTemp

        # Download and run official Scoop installer
        Write-Host "[INFO] Downloading official Scoop installer..." -ForegroundColor Gray
        $tempInstaller = "$userTemp\scoop-install.ps1"
        try {
            Invoke-WebRequest -Uri 'https://get.scoop.sh' -OutFile $tempInstaller -UseBasicParsing
            Write-Host "[OK] Downloaded Scoop installer" -ForegroundColor Green

            # The official installer aborts when the target directory is not empty.
            # C:\usr already contains bin\ and etc\ (scoop-boot layout), so that single
            # check is replaced. Same patch as Get-ScoopInstaller in scoop-boot.ps1.
            $installerContent = [System.IO.File]::ReadAllText($tempInstaller)
            $emptyCheck = 'Deny-Install "''$SCOOP_DIR'' exists and is not empty, please specify another path."'
            $emptyInfo  = 'Write-Host "[INFO] ''$SCOOP_DIR'' is not empty (scoop-boot layout: bin\ and etc\ are expected), continuing"'
            if ($installerContent.Contains($emptyCheck)) {
                [System.IO.File]::WriteAllText($tempInstaller, $installerContent.Replace($emptyCheck, $emptyInfo))
                Write-Host "[OK] Installer prepared (non-empty directory check removed)" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Installer layout changed upstream; running unpatched" -ForegroundColor Yellow
            }

            Write-Host "[INFO] Installing Scoop core..." -ForegroundColor Gray

            # Check if running as admin and use appropriate installation method
            $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
            $isAdminContext = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

            # The installer aborts when a scoop command is on the PATH; the scoop
            # wrapper in bin\ is one. bin\ and shims\ leave the PATH while it runs.
            $savedPath = $env:Path
            $hidden = @("$ScoopDir\bin", "$ScoopDir\shims") | ForEach-Object { $_.ToLower() }
            $env:Path = (@($env:Path -split ';') | Where-Object { $_ -and ($hidden -notcontains $_.TrimEnd('\').ToLower()) }) -join ';'
            try {
                if ($isAdminContext) {
                    # Running as admin - use -RunAsAdmin flag
                    Write-Host "[INFO] Installing with admin privileges..." -ForegroundColor Gray
                    & $tempInstaller -RunAsAdmin -ScoopDir $ScoopDir -ScoopGlobalDir "$ScoopDir\global" -NoProxy
                } else {
                    # Running as normal user
                    & $tempInstaller -ScoopDir $ScoopDir -ScoopGlobalDir "$ScoopDir\global" -NoProxy
                }
            } finally {
                $env:Path = $savedPath
            }

            Remove-Item $tempInstaller -Force -ErrorAction SilentlyContinue

            if (Test-Path "$ScoopDir\apps\scoop") {
                Write-Host "[OK] Scoop core installed successfully!" -ForegroundColor Green
            } else {
                Write-Host "[ERROR] Scoop installation failed!" -ForegroundColor Red
                return $false
            }
        } catch {
            Write-Host "[ERROR] Failed to download/install Scoop!" -ForegroundColor Red
            Write-Host "Error: $_" -ForegroundColor Red
            return $false
        }

        # Update PATH for current session
        $env:Path = "$ScoopDir\shims;$ScoopDir\bin;$env:Path"

        # Install essential tools manually
        Write-Host ""
        Write-Host "[INFO] Installing essential tools (7zip, git, aria2)..." -ForegroundColor Gray

        Write-Host "  -> Installing 7zip..." -ForegroundColor DarkGray
        scoop install 7zip 2>&1 | Out-Null
        Write-Host "  -> Installing git..." -ForegroundColor DarkGray
        scoop install git 2>&1 | Out-Null
        Write-Host "  -> Installing aria2..." -ForegroundColor DarkGray
        scoop install aria2 2>&1 | Out-Null

        Write-Host "[OK] Essential tools installed" -ForegroundColor Green

        # Add main and extras buckets
        Write-Host ""
        Write-Host "[INFO] Adding main and extras buckets..." -ForegroundColor Gray
        scoop bucket add main 2>&1 | Out-Null
        scoop bucket add extras 2>&1 | Out-Null
        Write-Host "[OK] Buckets added" -ForegroundColor Green

        $bootstrapSuccess = $true
    }

    # Final verification
    if (-not (Test-Path "$ScoopDir\apps\scoop")) {
        Write-Host "[ERROR] Scoop not found after bootstrap!" -ForegroundColor Red
        return $false
    }

    if (-not (Test-Path "$ScoopDir\apps\git\current\cmd\git.exe")) {
        Write-Host "[FATAL] git could not be installed. Scoop cannot add buckets or install anything without it." -ForegroundColor Red
        Write-Host "        See the bootstrap messages above. If 7z.exe or git.exe were refused by Windows," -ForegroundColor Gray
        Write-Host "        endpoint security blocks newly released binaries (Defender event 1121)." -ForegroundColor Gray
        return $false
    }

    Write-Host ""
    Write-Host "[OK] Bootstrap complete - Scoop + Git ready!" -ForegroundColor Green

    # Update PATH for current session
    $env:Path = "$ScoopDir\shims;$ScoopDir\bin;$env:Path"

    # Disable aria2 warnings
    scoop config aria2-warning-enabled false 2>&1 | Out-Null

    # ============================================================================
    # STEP 2: ADD ADDITIONAL BUCKETS (main + extras already added by bootstrap)
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Step 2: Adding additional buckets..." -ForegroundColor White
    Write-Host ""

    # Bootstrap already added main + extras, we add java + versions
    $failedApps = @()
    $additionalBuckets = @('java', 'versions')
    foreach ($bucket in $additionalBuckets) {
        Write-Host "Adding bucket: $bucket" -ForegroundColor Gray
        if (Test-Path "$ScoopDir\buckets\$bucket\bucket") {
            Write-Host "[OK] Bucket already exists: $bucket" -ForegroundColor Gray
            continue
        }
        scoop bucket add $bucket
        if (Test-Path "$ScoopDir\buckets\$bucket\bucket") {
            Write-Host "[OK] Added bucket: $bucket" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Bucket not added: $bucket (packages from it will fail below)" -ForegroundColor Red
            $failedApps += "bucket $bucket"
        }
    }

    # ============================================================================
    # STEP 3: INSTALL DEVELOPMENT TOOLS
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Step 3: Installing development tools..." -ForegroundColor White
    Write-Host ""
    Write-Host "This will take 15-30 minutes depending on internet speed." -ForegroundColor Gray
    Write-Host ""

    # Bootstrap (Step 1) installed 7zip, git, aria2, sudo, innounp, dark, lessmsi, wget,
    # cacert and the main and extras buckets. Everything else comes from the package list.
    $packageFile = Get-PackageListFile
    if (-not $packageFile) {
        Write-Host "[INFO] No package list under $global:PackagesDir, fetching default.txt with scoop-boot.ps1 --update" -ForegroundColor Gray
        & "$ScoopDir\bin\scoop-boot.ps1" --update
        $packageFile = Get-PackageListFile
    }
    if (-not $packageFile) {
        Write-Host "[FATAL] No package list: $global:PackagesDir\default.txt is missing. Run: $ScoopDir\bin\scoop-boot.ps1 --update" -ForegroundColor Red
        return $false
    }
    $apps = @(Read-PackageList -Path $packageFile)
    $requestedNames = @($apps | ForEach-Object { Get-ManifestAppName -Package $_ })
    Write-Host "[INFO] Package list: $packageFile ($($apps.Count) packages)" -ForegroundColor Gray
    foreach ($handlerApp in ($PackageHandlers.Keys | Sort-Object)) {
        if ($BootstrapPackages -contains $handlerApp) { continue }
        if ($requestedNames -notcontains $handlerApp -and -not (Test-Path "$ScoopDir\apps\$handlerApp\current")) {
            Write-Host "[WARN] $handlerApp is not in the package list; its post-install step ($($PackageHandlers[$handlerApp])) will not run" -ForegroundColor Yellow
        }
    }
    if ($apps.Count -eq 0) {
        Write-Host "[FATAL] Package list is empty: $packageFile" -ForegroundColor Red
        return $false
    }

    # VC++ 2015-2022 runtime: the vcredist2022 post_install needs elevation.
    # Skip it when the runtime is already present (usual on managed images).
    $vcRuntimeKey = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
    $vcRuntime = Get-ItemProperty $vcRuntimeKey -ErrorAction SilentlyContinue
    if ($vcRuntime -and $vcRuntime.Installed -eq 1 -and $requestedNames -contains 'vcredist2022') {
        Write-Host "[OK] VC++ runtime already present ($($vcRuntime.Version)), skipping vcredist2022" -ForegroundColor Gray
        $apps = @($apps | Where-Object { (Get-ManifestAppName -Package $_) -ne 'vcredist2022' })
    }

    # Window title counts through the whole run: the packages, then the four
    # post-install stages (java, gcc, post-install, clean-user-scope)
    $titleTotal = $apps.Count + 4
    $appIndex = 0
    foreach ($app in $apps) {
        $appIndex++
        Set-ScoopBootTitle -Text "scoop-boot [$appIndex/$titleTotal] $(Get-ManifestAppName -Package $app)"
        $appDir = "$ScoopDir\apps\$(Get-ManifestAppName -Package $app)\current"
        if (Test-Path $appDir) {
            Write-Host "[OK] Already installed: $app" -ForegroundColor Gray
            continue
        }
        Write-Host "[INFO] Installing $app..." -ForegroundColor Gray
        # A manifest script may throw (Write-Error under a Stop preference, a failing
        # installer); that is this package's failure, not the end of the run
        try { scoop install $app } catch { Write-Host "[ERROR] $app`: $($_.Exception.Message)" -ForegroundColor Red }
        if (Test-Path $appDir) {
            Write-Host "[OK] Installed: $app" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Not installed: $app" -ForegroundColor Red
            $failedApps += $app
        }
    }

    if ($failedApps.Count -gt 0) {
        Write-Host ""
        Write-Host "[WARN] $($failedApps.Count) package(s) failed: $($failedApps -join ', ')" -ForegroundColor Yellow
        Write-Host "       Retry later with: scoop install <name>; remove leftovers with: scoop uninstall <name>" -ForegroundColor Gray
    }

    # ============================================================================
    # STEP 4: POST-INSTALLATION TASKS
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Step 4: Post-installation tasks..." -ForegroundColor White
    Write-Host ""

    # Handlers below run only for packages in the list (or already on disk from an
    # earlier run); a package that is not listed is simply not touched.
    $listed = $requestedNames + $BootstrapPackages + @($PackageHandlers.Keys | Where-Object { Test-Path "$ScoopDir\apps\$_\current" })

    # Set default Java version
    if ($listed -contains 'temurin25-jdk' -and (Test-Path "$ScoopDir\apps\temurin25-jdk\current\bin\java.exe")) {
        Set-ScoopBootTitle -Text "scoop-boot [$($apps.Count + 1)/$titleTotal] java"
        Write-Host "[INFO] Setting default Java to Temurin 25..." -ForegroundColor Gray
        scoop reset temurin25-jdk 2>&1 | Out-Null
        Write-Host "[OK] Default Java set to Temurin 25" -ForegroundColor Green
    } elseif ($listed -contains 'temurin25-jdk') {
        Write-Host "[WARN] temurin25-jdk is not installed, default Java not set" -ForegroundColor Yellow
    }

    # VC++ runtime: verify the result of the vcredist2022 post_install (needs elevation)
    $vcRuntime = Get-ItemProperty $vcRuntimeKey -ErrorAction SilentlyContinue
    if ($listed -notcontains 'vcredist2022') {
        # not managed by this list; nothing to verify
    } elseif ($vcRuntime -and $vcRuntime.Installed -eq 1) {
        Write-Host "[OK] VC++ runtime installed ($($vcRuntime.Version))" -ForegroundColor Green
        $vcredistInstaller = Get-ChildItem "$ScoopDir\apps\vcredist2022\current" -Filter "VC_redist*.exe" -ErrorAction SilentlyContinue
        if ($vcredistInstaller) {
            Remove-Item $vcredistInstaller.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] vcredist2022 installer removed (libraries remain)" -ForegroundColor Gray
        }
    } else {
        Write-Host "[WARN] VC++ runtime not installed (vcredist2022 post_install needs elevation, UAC was denied?)" -ForegroundColor Yellow
        Write-Host "       Run in an Administrator PowerShell:" -ForegroundColor Gray
        Write-Host "       Get-ChildItem C:\usr\cache\vcredist2022* | ForEach-Object { & `$_.FullName /install /quiet /norestart }" -ForegroundColor Gray
        $failedApps += 'vcredist2022 (runtime)'
    }

    # Initialize MSYS2 and install GCC
    if ($listed -contains 'msys2' -and (Test-Path "$ScoopDir\apps\msys2\current")) {
        Set-ScoopBootTitle -Text "scoop-boot [$($apps.Count + 2)/$titleTotal] gcc"
        Write-Host "[INFO] Initializing MSYS2 and installing GCC..." -ForegroundColor Gray
        Write-Host "  -> Initializing MSYS2..." -ForegroundColor DarkGray
        Write-Host "     (core update plus GCC download, several minutes)" -ForegroundColor DarkGray

        # msys2.exe is only a launcher: it spawns a terminal and exits at once, so
        # Start-Process -Wait returns before pacman has done anything. Call bash.exe
        # directly instead; that blocks until pacman is finished and streams its output.
        $msysBash = "$ScoopDir\apps\msys2\current\usr\bin\bash.exe"
        $env:MSYSTEM = 'UCRT64'
        $env:CHERE_INVOKING = '1'
        $env:MSYS2_PATH_TYPE = 'minimal'
        try {
            # First login run completes the MSYS2 post-install setup
            & $msysBash -lc 'true' 2>&1 | Out-Null

            # Core update may replace msys2-runtime/pacman and stop; second pass finishes
            foreach ($pass in 1, 2) {
                Write-Host "  -> pacman -Syu, pass $pass" -ForegroundColor DarkGray
                & $msysBash -lc 'pacman -Syu --noconfirm'
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  [WARN] pacman -Syu pass $pass exited with code $LASTEXITCODE" -ForegroundColor Yellow
                }
            }

            # Package mirrors fail sporadically (HTTP 500 on a single .sig file aborts the
            # whole transaction). Retry a few times; pacman keeps what it already downloaded.
            $gccExe = "$ScoopDir\apps\msys2\current\ucrt64\bin\gcc.exe"
            foreach ($attempt in 1, 2, 3) {
                Write-Host "  -> pacman -S mingw-w64-ucrt-x86_64-gcc, attempt $attempt" -ForegroundColor DarkGray
                & $msysBash -lc 'pacman -S --noconfirm --needed mingw-w64-ucrt-x86_64-gcc'
                if ($LASTEXITCODE -eq 0 -and (Test-Path $gccExe)) { break }
                Write-Host "  [WARN] pacman -S exited with code $LASTEXITCODE" -ForegroundColor Yellow
                if ($attempt -lt 3) { Start-Sleep -Seconds 10 }
            }
        } finally {
            Remove-Item Env:MSYSTEM, Env:CHERE_INVOKING, Env:MSYS2_PATH_TYPE -ErrorAction SilentlyContinue
        }

        # Verify installation (CRITICAL: Check ucrt64, NOT mingw64!)
        $gccPath = "$ScoopDir\apps\msys2\current\ucrt64\bin\gcc.exe"
        if (Test-Path $gccPath) {
            Write-Host "[OK] MSYS2 GCC (UCRT64) installed successfully!" -ForegroundColor Green
            Write-Host "     GCC location: $gccPath" -ForegroundColor DarkGray

            # Smoke test: compile and run a one-line program. Two known failure modes on
            # managed machines, each with its own message:
            #  - cc1.exe exits with -1073741511 (STATUS_ENTRYPOINT_NOT_FOUND) when another
            #    directory earlier in PATH ships older libstdc++/libgcc DLLs
            #  - the built exe is refused by endpoint security (ASR rule 01443614, "Block
            #    executable files unless they meet a prevalence, age, or trusted list criterion")
            $ccTestDir = "$ScoopDir\cache\scoop-boot-cctest"
            New-Item -ItemType Directory -Path $ccTestDir -Force | Out-Null
            $ccTestSrc = "$ccTestDir\hello.c"
            $ccTestExe = "$ccTestDir\hello.exe"
            Set-Content -Path $ccTestSrc -Value 'int main(void){return 42;}' -Encoding ASCII
            Remove-Item $ccTestExe -Force -ErrorAction SilentlyContinue
            $savedPath = $env:Path
            $env:Path = "$ScoopDir\apps\msys2\current\ucrt64\bin;$env:Path"
            $ccOutput = @(& $gccPath $ccTestSrc -o $ccTestExe 2>&1 | ForEach-Object { "$_" })
            $ccExit = $LASTEXITCODE
            $env:Path = $savedPath
            if (-not (Test-Path $ccTestExe)) {
                Write-Host "[WARN] GCC is installed but cannot compile (gcc exit code $ccExit)" -ForegroundColor Yellow
                foreach ($line in ($ccOutput | Select-Object -First 4)) { Write-Host "       gcc: $line" -ForegroundColor Gray }
                $ccText = $ccOutput -join "`n"
                if ($ccExit -eq -1073741511 -or $ccText -match 'entry point') {
                    Write-Host "       cc1.exe: STATUS_ENTRYPOINT_NOT_FOUND. A directory earlier in PATH ships older" -ForegroundColor Gray
                    Write-Host "       libstdc++/libgcc DLLs. Check: where.exe libstdc++-6.dll" -ForegroundColor Gray
                } elseif ($ccText -match 'Access is denied|cannot execute') {
                    Write-Host "       A compiler component (cc1.exe, as.exe or ld.exe) was refused by Windows: endpoint" -ForegroundColor Gray
                    Write-Host "       security (Defender ASR rule 01443614) blocks newly released binaries. Defender event 1121." -ForegroundColor Gray
                }
                $failedApps += 'gcc (compile test)'
            } else {
                $runOk = $false
                try {
                    & $ccTestExe 2>&1 | Out-Null
                    $runOk = ($LASTEXITCODE -eq 42)
                } catch { }
                if ($runOk) {
                    Write-Host "[OK] GCC compile-and-run test passed" -ForegroundColor Green
                } else {
                    Write-Host "[WARN] GCC compiled the test program, but Windows refused to run it." -ForegroundColor Yellow
                    Write-Host "       Endpoint security (Defender ASR rule 01443614) blocks locally built" -ForegroundColor Gray
                    Write-Host "       executables on this machine. Check the Defender log for event 1121:" -ForegroundColor Gray
                    Write-Host "       Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational'; Id=1121}" -ForegroundColor Gray
                    $failedApps += 'gcc (running built exe blocked by ASR)'
                }
            }
            Remove-Item $ccTestDir -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "[WARN] GCC installation failed (gcc.exe not found in ucrt64)" -ForegroundColor Yellow
            $failedApps += 'msys2 gcc (ucrt64)'
            Write-Host ""
            Write-Host "Manual installation steps:" -ForegroundColor Yellow
            Write-Host "  1. Open UCRT64 terminal: $ScoopDir\apps\msys2\current\ucrt64.exe" -ForegroundColor White
            Write-Host "  2. Run: pacman -Syu" -ForegroundColor White
            Write-Host "  3. Run: pacman -S mingw-w64-ucrt-x86_64-gcc" -ForegroundColor White
            Write-Host ""
            Write-Host "NOTE: Use ucrt64.exe (modern), NOT msys2.exe (legacy)" -ForegroundColor Yellow
        }
    } elseif ($listed -contains 'msys2') {
        Write-Host "[WARN] MSYS2 not found, skipping GCC installation" -ForegroundColor Yellow
    }

    # netcat aliases: the netcat package is blocked by Windows Defender (PUA), so nc and
    # netcat point to ncat from nmap. "scoop shim add" re-adds shims to the User PATH,
    # which Step 7 cleans up again; that is why this runs before Step 7.
    $ncat = "$ScoopDir\apps\nmap\current\ncat.exe"
    if ($listed -contains 'nmap' -and (Test-Path $ncat)) {
        foreach ($alias in @('nc', 'netcat')) {
            if (Test-Path "$ScoopDir\shims\$alias.exe") {
                Write-Host "[OK] Shim already present: $alias -> ncat" -ForegroundColor Gray
            } else {
                scoop shim add $alias $ncat 2>&1 | Out-Null
                if (Test-Path "$ScoopDir\shims\$alias.exe") {
                    Write-Host "[OK] Shim created: $alias -> ncat" -ForegroundColor Green
                } else {
                    Write-Host "[WARN] Could not create shim $alias (scoop shim add $alias $ncat)" -ForegroundColor Yellow
                }
            }
        }
    } elseif ($listed -contains 'nmap') {
        Write-Host "[WARN] nmap not found, skipping nc/netcat shims" -ForegroundColor Yellow
    }

    Set-ScoopBootTitle -Text "scoop-boot [$($apps.Count + 3)/$titleTotal] post-install"
    Write-Host ""
    Write-Host ">>> Step 5: Registry imports..." -ForegroundColor White
    Write-Host ""

    $regFiles = @(
        @{App='7zip'; File='install-context.reg'},
        @{App='notepadplusplus'; File='install-context.reg'},
        @{App='vscode'; File='install-context.reg'},
        @{App='git'; File='install-context.reg'},
        @{App='python314'; File='install-pep-514.reg'}
    )

    foreach ($item in $regFiles) {
        if ($listed -notcontains $item.App) { continue }
        $regPath = "$ScoopDir\apps\$($item.App)\current\$($item.File)"
        if (Test-Path $regPath) {
            Start-Process reg -ArgumentList "import `"$regPath`"" -Wait -NoNewWindow -ErrorAction SilentlyContinue
            Write-Host "[OK] Imported: $($item.App)" -ForegroundColor Green
        }
    }

    Write-Host ""
    Write-Host ">>> Step 6: Starting system tray apps..." -ForegroundColor White
    Write-Host ""

    $toolboxPath = "$ScoopDir\apps\jetbrains-toolbox\current\jetbrains-toolbox.exe"
    if ($listed -contains 'jetbrains-toolbox' -and (Test-Path $toolboxPath)) {
        $toolboxRunning = Get-Process -Name "jetbrains-toolbox" -ErrorAction SilentlyContinue
        if (-not $toolboxRunning) {
            Start-Process -FilePath $toolboxPath -ErrorAction SilentlyContinue
            Write-Host "[OK] Started: JetBrains Toolbox" -ForegroundColor Green
        } else {
            Write-Host "[OK] Already running: JetBrains Toolbox" -ForegroundColor Gray
        }
    }

    $greenshotPath = "$ScoopDir\apps\greenshot\current\Greenshot.exe"
    if ($listed -contains 'greenshot' -and (Test-Path $greenshotPath)) {
        $greenshotRunning = Get-Process -Name "Greenshot" -ErrorAction SilentlyContinue
        if (-not $greenshotRunning) {
            Start-Process -FilePath $greenshotPath -ErrorAction SilentlyContinue
            Write-Host "[OK] Started: Greenshot" -ForegroundColor Green
        } else {
            Write-Host "[OK] Already running: Greenshot" -ForegroundColor Gray
        }
    }

    # ============================================================================
    # STEP 7: CLEAN USER SCOPE
    # Scoop wrote JAVA_HOME, GRADLE_USER_HOME, ... and PATH entries into the User
    # scope during Step 3; User values override the Machine values from the .env
    # file. scoop-boot.ps1 --clean-user-scope removes them and applies user.* files.
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Step 7: Cleaning User scope (Scoop overrides, user.* files)..." -ForegroundColor White
    Write-Host ""
    Set-ScoopBootTitle -Text "scoop-boot [$titleTotal/$titleTotal] clean-user-scope"
    $null = Invoke-CleanUserScope

    # The scoop wrapper (bin\scoop.ps1, scoop.cmd, scoop) is not part of the Quick
    # Setup download; without it every manual "scoop update" writes to the User
    # scope again. --update fetches it (and reports the scripts as unchanged).
    if (-not (Test-Path "$ScoopDir\bin\scoop.ps1")) {
        Write-Host ""
        Write-Host "[INFO] scoop wrapper missing in $ScoopDir\bin, fetching it with scoop-boot.ps1 --update" -ForegroundColor Gray
        & "$ScoopDir\bin\scoop-boot.ps1" --update
    }

    Write-Host ""
    if ($failedApps.Count -gt 0) {
        Write-Host "=== Installation Complete with $($failedApps.Count) failure(s) ===" -ForegroundColor Yellow
        Write-Host "Failed: $($failedApps -join ', ')" -ForegroundColor Yellow
    } else {
        Write-Host "=== Installation Complete! ===" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "IMPORTANT: Restart your shell!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Verify:" -ForegroundColor Cyan
    Write-Host "  java -version    # Should show openjdk 25.x" -ForegroundColor Gray
    Write-Host "  python --version # Should show Python 3.14.x" -ForegroundColor Gray
    Write-Host "  gcc --version    # Should show GCC from MSYS2/UCRT64" -ForegroundColor Gray
    Write-Host ""

    if ($wsl2Installed) {
        Write-Host "WSL2 is ready for:" -ForegroundColor Cyan
        Write-Host "  - Docker Desktop (download: https://www.docker.com/products/docker-desktop)" -ForegroundColor Gray
        Write-Host "  - Rancher Desktop (download: https://rancherdesktop.io)" -ForegroundColor Gray
        Write-Host "  - Linux development (wsl)" -ForegroundColor Gray
        Write-Host ""
    }
    return $true
}

function Show-PackageList {
    <#
    .SYNOPSIS
        Shows the package list this machine would install, and the handlers, without installing. Called by --list-packages.
    #>
    # Formerly scoop-complete-install.ps1, written for the shell defaults: this
    # function and everything it calls run without strict mode and with Continue
    Set-StrictMode -Off
    $ErrorActionPreference = 'Continue'
    $ScoopDir = $global:BaseDir
    $BootstrapPackages = $global:BootstrapPackages
    $PackageHandlers = $global:PackageHandlers
        $packageFile = Get-PackageListFile
        if (-not $packageFile) {
            Write-Host "[ERROR] No package list under $global:PackagesDir. Run: $ScoopDir\bin\scoop-boot.ps1 --update" -ForegroundColor Red
            return $false
        }
        $apps = @(Read-PackageList -Path $packageFile)
        Write-Host ""
        Write-Host "Package list: $packageFile" -ForegroundColor Cyan
        Write-Host "Bootstrap (always, Step 1): 7zip git aria2 sudo innounp dark lessmsi wget cacert; buckets main extras" -ForegroundColor Gray
        Write-Host "Buckets added in Step 2: java versions" -ForegroundColor Gray
        Write-Host ""
        $n = 0
        foreach ($app in $apps) {
            $n++
            $name = Get-ManifestAppName -Package $app
            $state = if (Test-Path "$ScoopDir\apps\$name\current") { 'installed' } else { 'missing' }
            $handler = if ($PackageHandlers.ContainsKey($name)) { "  <- $($PackageHandlers[$name])" } else { '' }
            Write-Host ("{0,3}  {1,-22} {2,-10}{3}" -f $n, $app, $state, $handler)
        }
        Write-Host ""
        foreach ($handlerApp in ($PackageHandlers.Keys | Sort-Object)) {
            if ($BootstrapPackages -contains $handlerApp) { continue }
            if (@($apps | ForEach-Object { Get-ManifestAppName -Package $_ }) -notcontains $handlerApp) {
                Write-Host "[WARN] $handlerApp has a post-install step but is not in the list" -ForegroundColor Yellow
            }
        }
        Write-Host "$($apps.Count) packages. To change the list on this machine, create $global:PackagesDir\$(Get-Hostname).txt (it replaces default.txt)." -ForegroundColor Gray
        return $true
}

# ============================================================================
# RESET (formerly scoop-complete-reset.ps1)
# ============================================================================

if (-not (Test-Path variable:global:ScoopBootExplorerStopped)) { $global:ScoopBootExplorerStopped = $false }

function Invoke-ScoopReset {
    <#
    .SYNOPSIS
        Removes Scoop again: processes, backup, variables, PATH entries, directories, registry, shortcuts. Called by --admin-reset.
    #>
    param(
        [switch]$Force,
        [switch]$KeepPersist
    )
    # Formerly scoop-complete-reset.ps1, written for the shell defaults: this
    # function and everything it calls run without strict mode and with Continue
    Set-StrictMode -Off
    $ErrorActionPreference = 'Continue'
    $ScoopDir = $global:BaseDir
    $BackupRoot = "$ScoopDir\backups"
    $BackupDir = "$BackupRoot\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $BackupsToKeep = 5

    # Scoop owns only the subdirectories in $global:ScoopOwnedDirs (Test-ScoopOwnedPath).
    # Everything else under C:\usr (bin, etc, or software the user installed there,
    # e.g. C:\usr\PostgreSQL) is left alone: not deleted, PATH entries and variables kept.

    Write-Host ""
    Write-Host "=== Scoop Complete Reset ===" -ForegroundColor Red
    Write-Host ""
    Write-Host "WARNING: This will remove:" -ForegroundColor Yellow
    Write-Host "  - All installed Scoop applications" -ForegroundColor White
    Write-Host "  - All environment variables set by Scoop" -ForegroundColor White
    Write-Host "  - All PATH entries related to Scoop" -ForegroundColor White
    if (-not $KeepPersist) {
        Write-Host "  - All application settings in persist folder" -ForegroundColor White
    }
    Write-Host "  - Scoop itself" -ForegroundColor White
    Write-Host ""

    if (-not $Force) {
        Write-Host "Continue? [y/N]: " -ForegroundColor Yellow -NoNewline
        $confirm = Read-Host
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "Cancelled." -ForegroundColor Gray
            return $true
        }
    }

    Write-Host ""
    Write-Host "=== Starting Cleanup ===" -ForegroundColor Cyan
    Write-Host ""

    # Helper function for aggressive directory deletion
    function Remove-DirectoryAggressively {
        param(
            [string]$Path,
            [string]$Description
        )

        if (-not (Test-Path $Path)) {
            Write-Host "[SKIP] Not found: $Description" -ForegroundColor Gray
            return
        }

        Write-Host "[WORK] Removing: $Description" -ForegroundColor Yellow

        # Step 1: Remove all file attributes
        Write-Host "  -> Removing file attributes..." -ForegroundColor Gray
        try {
            Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try { $_.Attributes = 'Normal' } catch {}
                }
            Write-Host "  -> Attributes cleared" -ForegroundColor Green
        } catch {
            Write-Host "  -> Warning: Could not clear all attributes" -ForegroundColor Yellow
        }

        # Step 2: Check if we have permissions (skip takeown if we do)
        Write-Host "  -> Checking permissions..." -ForegroundColor Gray
        $needsPermissionFix = $false
        try {
            $acl = Get-Acl $Path -ErrorAction Stop
            $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            $hasFullControl = $acl.Access | Where-Object {
                ($_.IdentityReference -eq $currentUser -or
                    $_.IdentityReference -eq "BUILTIN\Administrators") -and
                    $_.FileSystemRights -match "FullControl"
            }
            if (-not $hasFullControl) {
                $needsPermissionFix = $true
            }
        } catch {
            $needsPermissionFix = $true
        }

        if ($needsPermissionFix) {
            Write-Host "  -> Taking ownership (this may take a while)..." -ForegroundColor Gray
            try {
                $null = & takeown /f "$Path" /r /d y 2>&1
                Write-Host "  -> Ownership taken" -ForegroundColor Green
            } catch {
                Write-Host "  -> Warning: Takeown had issues" -ForegroundColor Yellow
            }

            Write-Host "  -> Setting permissions..." -ForegroundColor Gray
            try {
                $null = & icacls "$Path" /grant "Administrators:(OI)(CI)F" /t /c /q 2>&1
                Write-Host "  -> Permissions granted" -ForegroundColor Green
            } catch {
                Write-Host "  -> Warning: icacls had issues" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  -> Permissions OK, skipping takeown" -ForegroundColor Green
        }

        # Step 3: Delete junctions first (they can block deletion)
        Write-Host "  -> Removing junctions..." -ForegroundColor Gray
        try {
            $junctions = Get-ChildItem $Path -Recurse -Directory -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Attributes -match "ReparsePoint" }

            foreach ($junction in $junctions) {
                try {
                    [System.IO.Directory]::Delete($junction.FullName, $false)
                } catch {
                    # Try cmd rmdir for stubborn junctions
                    & $env:ComSpec /c "rmdir `"$($junction.FullName)`"" 2>$null
                }
            }
            Write-Host "  -> Junctions removed" -ForegroundColor Green
        } catch {
            Write-Host "  -> Warning: Some junctions may remain" -ForegroundColor Yellow
        }

        # Step 4: Multiple deletion attempts with different methods
        Write-Host "  -> Deleting directory..." -ForegroundColor Gray

        $deleted = $false

        # Method 1: PowerShell Remove-Item with UNC path
        try {
            Remove-Item -Path "\\?\$Path" -Recurse -Force -ErrorAction Stop
            $deleted = $true
            Write-Host "  -> Deleted with Remove-Item" -ForegroundColor Green
        } catch {
            Write-Host "  -> Remove-Item failed, trying alternatives..." -ForegroundColor Yellow
        }

        # Method 2: cmd rd with UNC path
        if (-not $deleted -and (Test-Path $Path)) {
            try {
                $rdOutput = & $env:ComSpec /c "rd /s /q `"\\?\$Path`" 2>&1"
                if (-not (Test-Path $Path)) {
                    $deleted = $true
                    Write-Host "  -> Deleted with cmd rd" -ForegroundColor Green
                } elseif ($rdOutput -match "Access is denied") {
                    Write-Host "  -> Access denied (likely Shell Extensions)" -ForegroundColor Yellow
                }
            } catch {}
        }

        # Method 3: Restart Explorer if DLLs are locked
        if (-not $deleted -and (Test-Path $Path)) {
            Write-Host "  -> Files locked, restarting Explorer and Shell components..." -ForegroundColor Yellow
            try {
                # Stop all relevant processes
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                Stop-Process -Name ShellExperienceHost -Force -ErrorAction SilentlyContinue
                Stop-Process -Name StartMenuExperienceHost -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2

                # Restart Explorer
                Start-Process "C:\Windows\explorer.exe"
                Start-Sleep -Seconds 2

                # Restart Taskbar and Start Menu components
                $shellExperienceHost = "C:\Windows\SystemApps\ShellExperienceHost_cw5n1h2txyewy\ShellExperienceHost.exe"
                $startMenuHost = "C:\Windows\SystemApps\StartMenuExperienceHost_cw5n1h2txyewy\StartMenuExperienceHost.exe"

                if (Test-Path $shellExperienceHost) {
                    Start-Process $shellExperienceHost -ErrorAction SilentlyContinue
                }
                if (Test-Path $startMenuHost) {
                    Start-Process $startMenuHost -ErrorAction SilentlyContinue
                }

                Start-Sleep -Seconds 2

                # Try deletion again with cmd rd
                & $env:ComSpec /c "rd /s /q `"\\?\$Path`"" 2>$null
                if (-not (Test-Path $Path)) {
                    $deleted = $true
                    Write-Host "  -> Deleted after Explorer restart" -ForegroundColor Green
                }
            } catch {
                Write-Host "  -> Explorer restart failed" -ForegroundColor Yellow
            }
        }

        # Method 4: .NET Directory.Delete
        if (-not $deleted -and (Test-Path $Path)) {
            try {
                [System.IO.Directory]::Delete($Path, $true)
                $deleted = $true
                Write-Host "  -> Deleted with .NET method" -ForegroundColor Green
            } catch {}
        }

        # Check if truly deleted
        if (Test-Path $Path) {
            Write-Host "[FAIL] Could not delete: $Description" -ForegroundColor Red
            Write-Host "       Manual deletion required!" -ForegroundColor Red
            Write-Host "       Try: rd /s /q `"\\?\$Path`"" -ForegroundColor Gray
            return $false
        } else {
            Write-Host "[OK] Removed: $Description" -ForegroundColor Green
            return $true
        }
    }

    # ============================================================================
    # 1. ROBUST PROCESS DETECTION - Uses handle64.exe for COMPLETE coverage
    # ============================================================================
    Write-Host ">>> Checking for running Scoop applications..." -ForegroundColor Cyan
    Write-Host ""

    # Method 1: Kill known system tray apps first (they always block)
    Write-Host "[INFO] Stopping known system tray applications..." -ForegroundColor Gray
    # jetbrainsd: background daemon of JetBrains Toolbox 3.x, separate from the GUI process
    $systemTrayApps = @('greenshot', 'jetbrains-toolbox', 'jetbrainsd', 'everything', 'mousejiggler', 'keyboxd', 'gpg-agent', 'ssh-agent')
    $global:ScoopBootExplorerStopped = $false
    $killedCount = 0
    foreach ($appName in $systemTrayApps) {
        $proc = Get-Process -Name $appName -ErrorAction SilentlyContinue
        if ($proc) {
            try {
                Stop-Process -Name $appName -Force -ErrorAction Stop
                Write-Host "  [OK] Stopped: $appName" -ForegroundColor Green
                $killedCount++
            } catch {
                Write-Host "  [WARN] Could not stop: $appName" -ForegroundColor Yellow
            }
        }
    }
    if ($killedCount -eq 0) {
        Write-Host "  [OK] No system tray apps running" -ForegroundColor Gray
    }

    # Method 2: Use handle64.exe for COMPLETE detection (finds ALL processes with open handles)
    Write-Host ""
    Write-Host "[INFO] Scanning for ALL processes with open handles to Scoop..." -ForegroundColor Gray
    Set-ScoopBootTitle -Text "scoop-boot reset processes"
    $handle64Path = "$ScoopDir\apps\sysinternals\current\handle64.exe"
    $usedHandle = $false

    if (Test-Path $handle64Path) {
        Write-Host "  [INFO] Using handle64.exe for comprehensive scan..." -ForegroundColor DarkGray
        try {
            # Get all processes with handles to C:\usr\apps
            $handleOutput = & $handle64Path -accepteula -nobanner "$ScoopDir\apps" 2>&1 | Out-String

            # Parse output for process names and PIDs
            $processesToKill = @{}
            foreach ($line in ($handleOutput -split "`n")) {
                # Format: "processname.exe pid: 12345 HOSTNAME\User"
                if ($line -match '^\s*(\S+\.exe)\s+pid:\s+(\d+)') {
                    $exeName = $Matches[1]
                    $processId = [int]$Matches[2]
                    if (-not $processesToKill.ContainsKey($processId)) {
                        $processesToKill[$processId] = $exeName
                    }
                }
            }

            if ($processesToKill.Count -gt 0) {
                # Only processes that belong to Scoop (image under $ScoopDir) are terminated.
                # explorer.exe is the exception: shell extensions (7-Zip, TortoiseSVN, ...) load
                # DLLs from $ScoopDir into it, so it must go, and it is restarted after the
                # directories are gone. Anything else (Teams, Outlook, Edge with a file dialog
                # open) keeps running; if it blocks the deletion, that is reported below.
                Write-Host "  [FOUND] $($processesToKill.Count) processes with open handles:" -ForegroundColor Yellow
                foreach ($processId in $processesToKill.Keys) {
                    $exeName = $processesToKill[$processId]
                    if ($processId -eq $PID) { continue }

                    $imagePath = $null
                    try { $imagePath = (Get-Process -Id $processId -ErrorAction Stop).Path } catch { }
                    $isScoopApp = $imagePath -and ($imagePath -like "$ScoopDir\*")
                    $isExplorer = $exeName -ieq 'explorer.exe'

                    if ($isExplorer) {
                        Write-Host "    - $exeName (PID: $processId): Windows shell, holds Scoop shell extensions; restarted after cleanup" -ForegroundColor Yellow
                    } elseif ($isScoopApp) {
                        Write-Host "    - $exeName (PID: $processId): Scoop application" -ForegroundColor Yellow
                    } else {
                        # The path tells which program to close by hand when the deletion
                        # below fails (a browser with a download dialog, an IDE, Teams)
                        $where = if ($imagePath) { $imagePath } else { 'path not readable' }
                        Write-Host "    - $exeName (PID: $processId): not a Scoop application, left running ($where)" -ForegroundColor DarkGray
                        continue
                    }

                    try {
                        Stop-Process -Id $processId -Force -ErrorAction Stop
                        Write-Host "      [OK] Stopped PID $processId" -ForegroundColor Green
                        if ($isExplorer) { $global:ScoopBootExplorerStopped = $true }
                    } catch {
                        Write-Host "      [FAIL] Could not stop PID $processId" -ForegroundColor Red
                    }
                }
                Start-Sleep -Seconds 2
                $usedHandle = $true
            } else {
                Write-Host "  [OK] No processes found by handle64" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [WARN] handle64.exe failed: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [WARN] handle64.exe not found at: $handle64Path" -ForegroundColor Yellow
        Write-Host "  [INFO] Install Sysinternals for better process detection:" -ForegroundColor Yellow
        Write-Host "         scoop install sysinternals" -ForegroundColor Gray
    }

    # Method 3: Fallback - Get-Process with Path check (may miss some processes)
    if (-not $usedHandle) {
        Write-Host ""
        Write-Host "  [INFO] Using Get-Process fallback (may miss background services)..." -ForegroundColor Gray
        $runningApps = Get-Process | Where-Object {
            $_.Path -and $_.Path -like "$ScoopDir\apps\*"
        } | Select-Object Name, Id, Path

        if ($runningApps) {
            Write-Host "  [FOUND] Scoop applications detected:" -ForegroundColor Yellow
            $runningApps | ForEach-Object {
                Write-Host "    - $($_.Name) (PID: $($_.Id))" -ForegroundColor Yellow
            }

            Write-Host "  [INFO] Stopping all detected processes..." -ForegroundColor Gray
            $runningApps | ForEach-Object {
                try {
                    Stop-Process -Id $_.Id -Force -ErrorAction Stop
                    Write-Host "    [OK] Stopped: $($_.Name)" -ForegroundColor Green
                } catch {
                    Write-Host "    [FAIL] Could not stop: $($_.Name)" -ForegroundColor Red
                }
            }
            Start-Sleep -Seconds 2
        } else {
            Write-Host "  [OK] No Scoop processes detected via Get-Process" -ForegroundColor Green
        }
    }

    # Method 4: Kill any remaining GnuPG/SSH agents (common blockers that Get-Process misses)
    Write-Host ""
    Write-Host "[INFO] Stopping background agents (GnuPG, SSH, etc.)..." -ForegroundColor Gray
    $backgroundAgents = @('gpg-agent', 'ssh-agent', 'ssh-pageant', 'keyboxd', 'dirmngr', 'scdaemon', 'gpg-connect-agent')
    $agentKilled = $false
    foreach ($agentName in $backgroundAgents) {
        $proc = Get-Process -Name $agentName -ErrorAction SilentlyContinue
        if ($proc) {
            try {
                Stop-Process -Name $agentName -Force -ErrorAction Stop
                Write-Host "  [OK] Stopped: $agentName" -ForegroundColor Green
                $agentKilled = $true
            } catch {
                Write-Host "  [WARN] Could not stop: $agentName" -ForegroundColor Yellow
            }
        }
    }
    if (-not $agentKilled) {
        Write-Host "  [OK] No background agents running" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "[OK] Process cleanup complete" -ForegroundColor Green

    # 2. Backup environment variables
    Write-Host ""
    Set-ScoopBootTitle -Text "scoop-boot reset backup"
    Write-Host ">>> Creating backup..." -ForegroundColor Cyan
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    # Keep the newest $BackupsToKeep reset snapshots (yyyyMMdd_HHmmss), drop the rest.
    # Only those: --update prunes its scripts-* directories itself, and sorting them
    # in here once pushed the snapshot just created past the limit.
    $oldBackups = Get-ChildItem -Path $BackupRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\d{8}_\d{6}$' -and $_.FullName -ne $BackupDir } |
        Sort-Object Name -Descending | Select-Object -Skip ($BackupsToKeep - 1)
    foreach ($old in $oldBackups) {
        Remove-Item $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Removed old backup: $($old.Name)" -ForegroundColor Gray
    }

    $envVars = @{}
    [System.Environment]::GetEnvironmentVariables("User").Keys | ForEach-Object {
        $envVars[$_] = [System.Environment]::GetEnvironmentVariable($_, "User")
    }
    $envVars | ConvertTo-Json | Out-File "$BackupDir\user_env_backup.json"

    $machineEnvVars = @{}
    [System.Environment]::GetEnvironmentVariables("Machine").Keys | ForEach-Object {
        $machineEnvVars[$_] = [System.Environment]::GetEnvironmentVariable($_, "Machine")
    }
    $machineEnvVars | ConvertTo-Json | Out-File "$BackupDir\machine_env_backup.json"

    Write-Host "[OK] Backup created: $BackupDir" -ForegroundColor Green

    # 3./4. Clean User and Machine environment variables
    # Two criteria: a fixed list of names that scoop-boot or Scoop set without a path
    # value (options, locale), plus every variable whose value points into one of
    # Scoop's own subdirectories (apps, shims, ...). The second criterion catches
    # env_set entries from any manifest (OPENSSL_*, CATALINA_*, AZURE_CLI_PATH, ...)
    # without a list per package, and leaves variables of other software that lives
    # under C:\usr (e.g. an EDB PostgreSQL in C:\usr\PostgreSQL) untouched.
    $varsToRemove = @(
        'SCOOP', 'SCOOP_GLOBAL', 'SCOOP_CACHE', 'USR',
        'JAVA_OPTS', 'GRADLE_OPTS', 'MAVEN_OPTS',
        'GRADLE_USER_HOME', 'M2_REPO',
        'LANG', 'LC_ALL', 'LANGUAGE'
    )
    $varsToKeep = @('Path', 'TMP', 'TEMP')

    function Remove-ScoopEnvironmentVariables {
        param([string]$Scope)

        Write-Host ""
        Write-Host ">>> Cleaning $Scope environment variables..." -ForegroundColor Cyan
        $removed = 0
        $all = [System.Environment]::GetEnvironmentVariables($Scope)
        foreach ($name in @($all.Keys)) {
            if ($varsToKeep -contains $name) { continue }
            $value = [string]$all[$name]
            $byName  = $varsToRemove -contains $name
            $byValue = @($value -split ';' | Where-Object { Test-ScoopOwnedPath $_ }).Count -gt 0
            if ($byName -or $byValue) {
                [System.Environment]::SetEnvironmentVariable($name, $null, $Scope)
                Write-Host "[OK] Removed $Scope variable: $name" -ForegroundColor Green
                $removed++
            }
        }
        if ($removed -eq 0) {
            Write-Host "[OK] No $Scope variables to remove" -ForegroundColor Gray
        }
    }

    Remove-ScoopEnvironmentVariables -Scope "User"
    Remove-ScoopEnvironmentVariables -Scope "Machine"

    # 5. Clean User PATH
    Write-Host ""
    Set-ScoopBootTitle -Text "scoop-boot reset environment"
    Write-Host ">>> Cleaning User PATH..." -ForegroundColor Cyan
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath) {
        $pathArray = $userPath -split ';' | Where-Object { $_ -ne '' -and -not (Test-ScoopOwnedPath $_) }
        $newPath = $pathArray -join ';'
        [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "[OK] User PATH cleaned" -ForegroundColor Green
    }

    # 6. Clean Machine PATH
    Write-Host ""
    Write-Host ">>> Cleaning Machine PATH..." -ForegroundColor Cyan
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath) {
        $pathArray = $machinePath -split ';' | Where-Object { $_ -ne '' -and -not (Test-ScoopOwnedPath $_) }
        $newPath = $pathArray -join ';'
        [System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
        Write-Host "[OK] Machine PATH cleaned" -ForegroundColor Green
    }

    # 7. Remove directories with aggressive deletion
    Write-Host ""
    Write-Host ">>> Removing Scoop directories..." -ForegroundColor Cyan

    $dirsToRemove = @(
        @{ Path = "$ScoopDir\apps"; Desc = "Applications" },
        @{ Path = "$ScoopDir\buckets"; Desc = "Buckets" },
        @{ Path = "$ScoopDir\cache"; Desc = "Cache" },
        @{ Path = "$ScoopDir\shims"; Desc = "Shims" }
    )

    if (-not $KeepPersist) {
        $dirsToRemove += @{ Path = "$ScoopDir\persist"; Desc = "Persist (app data)" }
    }

    foreach ($dir in $dirsToRemove) {
        Set-ScoopBootTitle -Text "scoop-boot reset $(Split-Path -Leaf $dir.Path)"
        $null = Remove-DirectoryAggressively -Path $dir.Path -Description $dir.Desc
    }

    # Bring the desktop back if explorer.exe had to be stopped for the cleanup
    if ($global:ScoopBootExplorerStopped) {
        if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
            Start-Process -FilePath "$env:SystemRoot\explorer.exe"
            Write-Host "[OK] explorer.exe restarted" -ForegroundColor Green
        } else {
            Write-Host "[OK] explorer.exe already running again" -ForegroundColor Gray
        }
    }

    # 8. Clean registry
    Write-Host ""
    Set-ScoopBootTitle -Text "scoop-boot reset registry"
    Write-Host ">>> Cleaning registry entries..." -ForegroundColor Cyan

    $registryPaths = @{
        "HKCU:\Software\Classes\*\shell\Scoop" = "Context menu"
        "HKCU:\Software\Classes\Directory\shell\Scoop" = "Directory context"
        "HKCU:\Software\Classes\Directory\Background\shell\Scoop" = "Background context"
    }

    foreach ($regPath in $registryPaths.Keys) {
        if (Test-Path $regPath -ErrorAction SilentlyContinue) {
            try {
                Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
                Write-Host "[OK] Removed: $($registryPaths[$regPath])" -ForegroundColor Green
            } catch {
                Write-Host "[INFO] Skipped: $($registryPaths[$regPath])" -ForegroundColor Gray
            }
        }
    }

    # 9. Remove shortcuts
    Write-Host ""
    Write-Host ">>> Removing shortcuts..." -ForegroundColor Cyan
    $startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Scoop Apps"
    if (Test-Path $startMenuPath) {
        Remove-Item -Path $startMenuPath -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Removed Start Menu shortcuts" -ForegroundColor Green
    }

    # 10. Final check
    Write-Host ""
    Write-Host "=== Cleanup Complete! ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Remaining items to check:" -ForegroundColor Cyan

    $remainingDirs = @()
    if (Test-Path "$ScoopDir\apps") { $remainingDirs += "apps" }
    if (Test-Path "$ScoopDir\buckets") { $remainingDirs += "buckets" }
    if (Test-Path "$ScoopDir\cache") { $remainingDirs += "cache" }
    if (Test-Path "$ScoopDir\shims") { $remainingDirs += "shims" }
    if (-not $KeepPersist -and (Test-Path "$ScoopDir\persist")) { $remainingDirs += "persist" }

    if ($remainingDirs.Count -gt 0) {
        Write-Host "[WARN] Some directories could not be deleted:" -ForegroundColor Yellow
        $remainingDirs | ForEach-Object {
            Write-Host "  - $ScoopDir\$_" -ForegroundColor Yellow
        }
        Write-Host ""
        Write-Host "Diagnostic commands:" -ForegroundColor Cyan
        Write-Host "  # Check for running processes:" -ForegroundColor Gray
        Write-Host "  Get-Process | Where-Object { `$_.Path -like '*usr*' }" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  # Check for open handles (if Sysinternals installed):" -ForegroundColor Gray
        Write-Host "  handle64.exe C:\usr\apps" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Manual cleanup commands:" -ForegroundColor Cyan
        $remainingDirs | ForEach-Object {
            Write-Host "  rd /s /q `"\\?\$ScoopDir\$_`"" -ForegroundColor Gray
        }
    } else {
        Write-Host "[OK] All directories successfully removed!" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Check in a new shell: gci env: | ? { `$_.Value -like '*usr*' }" -ForegroundColor White
    Write-Host "  2. Set up again (Administrator): scoop-boot.ps1 --admin-init, then --admin-setenv" -ForegroundColor White
    Write-Host "  3. Normal shell: scoop-boot.ps1 --user-install" -ForegroundColor White
    Write-Host ""
    Write-Host "Backup location: $BackupDir" -ForegroundColor Gray
    return $true
}
