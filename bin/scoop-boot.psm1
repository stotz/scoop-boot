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
    Version: 1.24.0
    Same version as scoop-boot.ps1; the changelog is in scoop-boot.ps1.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

$global:ScriptVersion = "1.24.0"
$global:ScriptRoot = $PSScriptRoot
$global:BaseDir = Split-Path -Parent $global:ScriptRoot
$global:EnvDir = Join-Path $global:BaseDir "etc\environments"
$global:PackagesDir = Join-Path $global:BaseDir "etc\packages"
# Delivered profiles (profiles.conf and one directory per profile) that --profile
# composes into this machine's package lists and environment files
$global:ProfilesDir = Join-Path $global:BaseDir "etc\profiles"
# Full path for the "run this next" hints: bin\ is on the PATH only after
# --admin-setenv and a new shell, and not at all after a reset
$global:ScoopBootScript = Join-Path $global:ScriptRoot "scoop-boot.ps1"
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

    $isAdmin = Test-AdminRights
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
    Export = $null
    Import = ''
    Update = $false
    Branch = ''
    AdminInit = $false
    AdminSetEnv = $false
    UserInstall = $false
    AdminReset = $false
    ListPackages = $false
    Force = $false
    KeepPersist = $false
    Replace = $false
    DryRun = $false
    WslInstall = $false
    WslSetup = $false
    Distro = 'Debian'
    NoClaude = $false
    Profile = ''
    ListProfiles = $false
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
            '^--export$' { $global:ParsedArgs.Export = '' }
            '^--export=(.+)$' { $global:ParsedArgs.Export = $Matches[1] }
            '^--import=(.+)$' { $global:ParsedArgs.Import = $Matches[1] }
            '^--update$' { $global:ParsedArgs.Update = $true }
            '^--branch=(.+)$' { $global:ParsedArgs.Branch = $Matches[1] }
            '^--admin-init$' { $global:ParsedArgs.AdminInit = $true }
            '^--admin-setenv$' { $global:ParsedArgs.AdminSetEnv = $true }
            '^--user-install$' { $global:ParsedArgs.UserInstall = $true }
            '^--admin-reset$' { $global:ParsedArgs.AdminReset = $true }
            '^--list-packages$' { $global:ParsedArgs.ListPackages = $true }
            '^--force$' { $global:ParsedArgs.Force = $true }
            '^--keep-persist$' { $global:ParsedArgs.KeepPersist = $true }
            '^--replace$' { $global:ParsedArgs.Replace = $true }
            '^--dry-run$' { $global:ParsedArgs.DryRun = $true }
            '^--wsl-install$' { $global:ParsedArgs.WslInstall = $true }
            '^--wsl-setup$' { $global:ParsedArgs.WslSetup = $true }
            '^--distro=(.+)$' { $global:ParsedArgs.Distro = $Matches[1] }
            '^--no-claude$' { $global:ParsedArgs.NoClaude = $true }
            '^--profile=(.+)$' { $global:ParsedArgs.Profile = $Matches[1] }
            '^--list-profiles$' { $global:ParsedArgs.ListProfiles = $true }
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
    # Fake mode: the setup commands run end to end without an elevated shell
    if (Test-ScoopBootFake) { return $true }
    # No Windows principal outside Windows (the self-tests run on Linux too)
    if (-not (Test-Path variable:IsWindows) -or $IsWindows) {
        $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    return $false
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

# etc\scoop-boot.conf: "DIR=<path>" lines, the directories --admin-init creates when
# they are missing. scoop-boot itself needs only $global:BaseDir (where bin\ lives);
# these directories are the conventions of the environment file (TMP, DEVL_ROOT,
# DATA). Without the file the defaults are tmp, devl and data on the drive of
# BaseDir. --update never touches the file.
function Get-ScoopBootConfigDefaultText {
    $drive = [IO.Path]::GetPathRoot($global:BaseDir)
    $lines = @(
        '# scoop-boot configuration (read by --admin-init and --platform-report; never touched by --update)',
        '# DIR: directories created when missing, one per line, absolute path without spaces.',
        '# TMP, DEVL_ROOT and DATA in the environment file should point to these.',
        '# PROFILE: the profiles this machine was set up with (written by --profile and --admin-init).'
    )
    foreach ($name in @('tmp', 'devl', 'data')) { $lines += "DIR=$(Join-Path $drive $name)" }
    return ($lines -join "`n") + "`n"
}

function Get-ScoopBootConfig {
    <#
    .SYNOPSIS
        Reads etc\scoop-boot.conf: Path, Exists, Dirs (valid DIR lines), Invalid (rejected lines).
    #>
    $path = Join-Path $global:BaseDir 'etc\scoop-boot.conf'
    $config = @{ Path = $path; Exists = (Test-Path $path); Dirs = @(); Invalid = @(); Profile = '' }
    if (-not $config.Exists) {
        $drive = [IO.Path]::GetPathRoot($global:BaseDir)
        $config.Dirs = @(@('tmp', 'devl', 'data') | ForEach-Object { Join-Path $drive $_ })
        return $config
    }
    foreach ($op in @(Read-EnvironmentFile -FilePath $path)) {
        if ($op.Type -ne 'Set') { continue }
        if ($op.Name -eq 'PROFILE') { $config.Profile = "$($op.Value)".Trim(); continue }
        if ($op.Name -ne 'DIR') { continue }
        $value = "$($op.Value)".Trim()
        # Absolute, no spaces: Scoop and several installers fail on paths with spaces
        if ($value -match '^[A-Za-z]:\\[^\s]*$') { $config.Dirs += $value.TrimEnd('\') } else { $config.Invalid += $value }
    }
    return $config
}

function Get-EnvFileMachineValue {
    <#
    .SYNOPSIS
        The value a name would get from the system.* files (expanded), or $null when no file defines it.
    #>
    param([string]$Name)
    $files = @(Get-EnvironmentFiles | Where-Object { $_.Scope -eq 'Machine' })
    if ($files.Count -eq 0) { return $null }
    $global:EnvFileDefinitions = @{}
    foreach ($file in $files) { Register-EnvFileDefinitions -Operations @(Read-EnvironmentFile -FilePath $file.Path) }
    if (-not $global:EnvFileDefinitions.ContainsKey($Name)) { return $null }
    return (Expand-EnvironmentVariables -Value $global:EnvFileDefinitions[$Name])
}

# Definitions (NAME=value lines) of the .env files of the current run, name -> raw
# value. Filled by Register-EnvFileDefinitions before any file is applied, so that a
# reference resolves to the value the files define wherever the definition stands,
# also on a machine where the name is not yet in the registry and in --dry-run.
if (-not (Test-Path variable:global:EnvFileDefinitions)) { $global:EnvFileDefinitions = @{} }

# Dry run: writes go to this simulated store instead of the registry, reads look
# here first, so that a prepend after a sweep sees the swept PATH and the net
# effect can be compared with the registry at the end. $null = no dry run active.
if (-not (Test-Path variable:global:EnvDryRunState)) { $global:EnvDryRunState = $null }

function Get-EnvValue {
    <#
    .SYNOPSIS
        Value of an environment variable in a scope; during a dry run the simulated value when one exists.
    #>
    param([string]$Name, [string]$Scope)
    if ($global:EnvDryRunState -and $global:EnvDryRunState.ContainsKey($Scope) -and $global:EnvDryRunState[$Scope].ContainsKey($Name)) {
        return $global:EnvDryRunState[$Scope][$Name]
    }
    return (Get-RegistryEnvironmentVariable -Name $Name -Scope $Scope)
}

function Set-EnvValue {
    <#
    .SYNOPSIS
        Writes a variable ($null removes it): to the registry, or during a dry run to the simulated store only.
    #>
    param([string]$Name, [object]$Value, [string]$Scope, [bool]$DryRun = $false)
    if ($DryRun) {
        if ($global:EnvDryRunState) {
            if (-not $global:EnvDryRunState.ContainsKey($Scope)) { $global:EnvDryRunState[$Scope] = @{} }
            $global:EnvDryRunState[$Scope][$Name] = $Value
        }
        return
    }
    Set-RegistryEnvironmentVariable -Name $Name -Value $Value -Scope $Scope
}

function Get-EnvDryRunDiff {
    <#
    .SYNOPSIS
        Compares the simulated store of one scope with the registry: what a real run would change.
    .DESCRIPTION
        Returns objects with Name, Kind (new, removed, changed, unchanged), Old, New and
        for list variables (PATH and friends) Added, Removed, OrderChanged.
    #>
    param([string]$Scope)
    $result = @()
    if (-not $global:EnvDryRunState -or -not $global:EnvDryRunState.ContainsKey($Scope)) { return $result }
    foreach ($name in ($global:EnvDryRunState[$Scope].Keys | Sort-Object)) {
        $new = $global:EnvDryRunState[$Scope][$name]
        $old = Get-RegistryEnvironmentVariable -Name $name -Scope $Scope
        $item = [pscustomobject]@{ Name = $name; Kind = 'unchanged'; Old = $old; New = $new; Added = @(); Removed = @(); OrderChanged = $false }
        if ($null -eq $old -and $null -eq $new) { continue }
        elseif ($null -eq $old) { $item.Kind = 'new' }
        elseif ($null -eq $new) { $item.Kind = 'removed' }
        elseif ($old -ne $new) {
            $item.Kind = 'changed'
            if ($name -ieq 'Path' -or $old.Contains(';') -or $new.Contains(';')) {
                $oldParts = @($old -split ';' | Where-Object { $_ })
                $newParts = @($new -split ';' | Where-Object { $_ })
                $item.Added = @($newParts | Where-Object { $oldParts -notcontains $_ })
                $item.Removed = @($oldParts | Where-Object { $newParts -notcontains $_ })
                $common = @($newParts | Where-Object { $oldParts -contains $_ })
                $commonOld = @($oldParts | Where-Object { $newParts -contains $_ })
                $item.OrderChanged = (($common -join ';') -ne ($commonOld -join ';'))
            }
        }
        $result += $item
    }
    return $result
}

function Write-EnvDryRunSummary {
    <#
    .SYNOPSIS
        Prints the net effect of a dry run per scope: the operations were listed above, this is what the registry would end up with.
    #>
    Write-Host ""
    Write-Host "=== Net effect (what the registry would end up with) ===" -ForegroundColor Cyan
    foreach ($scope in @('Machine', 'User')) {
        $diff = @(Get-EnvDryRunDiff -Scope $scope)
        if ($diff.Count -eq 0) { continue }
        $changed = @($diff | Where-Object { $_.Kind -eq 'changed' })
        $new = @($diff | Where-Object { $_.Kind -eq 'new' })
        $removed = @($diff | Where-Object { $_.Kind -eq 'removed' })
        $same = @($diff | Where-Object { $_.Kind -eq 'unchanged' })
        Write-Host ("{0}: {1} changed, {2} new, {3} removed, {4} unchanged" -f $scope, $changed.Count, $new.Count, $removed.Count, $same.Count) -ForegroundColor White
        foreach ($item in $new) { Write-Host "  + $($item.Name) = $($item.New)" -ForegroundColor Green }
        foreach ($item in $removed) { Write-Host "  - $($item.Name) (was: $($item.Old))" -ForegroundColor Yellow }
        foreach ($item in $changed) {
            if ($item.Added.Count -gt 0 -or $item.Removed.Count -gt 0 -or $item.OrderChanged) {
                Write-Host ("  ~ {0}: +{1} -{2}{3}" -f $item.Name, $item.Added.Count, $item.Removed.Count, $(if ($item.OrderChanged) { ', order changed' } else { '' })) -ForegroundColor Yellow
                foreach ($e in $item.Added) { Write-Host "      + $e" -ForegroundColor Green }
                foreach ($e in $item.Removed) { Write-Host "      - $e" -ForegroundColor Yellow }
            } else {
                Write-Host "  ~ $($item.Name): $($item.Old) -> $($item.New)" -ForegroundColor Yellow
            }
        }
    }
}

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
                $envValue = Get-RegistryEnvironmentVariable -Name $varName -Scope 'Machine'
                if ([string]::IsNullOrEmpty($envValue)) {
                    $envValue = Get-RegistryEnvironmentVariable -Name $varName -Scope 'User'
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
    Write-Host "  --admin-init         1: directories, --update, package list and environment files from the profiles, opens the system file"
    Write-Host "      --profile=NAMES    profiles for this machine (default: PROFILE in etc\scoop-boot.conf, else devel)"
    Write-Host "  --admin-setenv       2: apply the environment files at Machine scope (Phase 1)"
    Write-Host "      --dry-run          show the net effect without applying anything (no Administrator needed)"
    Write-Host "  --user-install       3 (normal shell): bootstrap Scoop, install the package list (Phase 2)"
    Write-Host "      --force            no question when the shell is elevated (account with elevated shells only)"
    Write-Host "  --admin-reset        Remove Scoop again: apps, variables, PATH entries, registry; bin, etc and logs stay"
    Write-Host "      --force            no confirmation prompt"
    Write-Host "      --keep-persist     keep $global:BaseDir\persist (app data, settings)"
    Write-Host ""
    Write-Host "WSL (optional, after the setup):" -ForegroundColor Yellow
    Write-Host "  --wsl-install        Administrator: WSL and the Debian distribution, not started; a restart may follow"
    Write-Host "      --distro=NAME      another distribution than Debian (list: wsl -l -o)"
    Write-Host "      --dry-run          show the wsl.exe commands, run nothing"
    Write-Host "  --wsl-setup          Normal shell: apt packages of etc\packages\debian.txt and Claude Code inside the distribution"
    Write-Host "      --no-claude        leave out Claude Code"
    Write-Host "      --dry-run          apt-get resolves every package in simulation mode, nothing is installed"
    Write-Host ""
    Write-Host "MAINTENANCE:" -ForegroundColor Yellow
    Write-Host "  --update             Install the current signed release: scripts, scoop wrapper, package lists, profiles, etc\wsl (etc\release.files)"
    Write-Host "      --branch=NAME      download from this branch and remember it; --branch=main switches back"
    Write-Host "  --clean-user-scope   Remove Scoop's User-scope overrides, apply the user.* files (no admin)"
    Write-Host "      --quiet            print only a summary when something changed"
    Write-Host "  --list-packages      Package list in use, status of each package and its post-install steps; installs nothing"
    Write-Host "  --profile=NAMES      Compose etc\packages\HOSTNAME.txt and the environment files from profiles: devel, devops, or java,c++,python"
    Write-Host "      --dry-run          show the files, write nothing"
    Write-Host "      --force            replace existing host files (the old ones are kept as .bak)"
    Write-Host "  --list-profiles      The profiles etc\profiles delivers, single and virtual, with their packages"
    Write-Host "  --platform-report    Defender/ASR rules and blocks, profile container, TMP: what the platform does to the setup; exit 1 on findings"
    Write-Host "  --export[=NAME]      Write the installed packages and buckets to etc\exports\NAME.txt (default: hostname)"
    Write-Host "  --import=NAME|FILE   Add the packages of an export that this machine's list lacks to etc\packages\HOSTNAME.txt"
    Write-Host "      --dry-run          show what would be added, write nothing"
    Write-Host "      --replace          write etc\packages\HOSTNAME.txt from the export alone (clone the old machine's list)"
    Write-Host ""
    Write-Host "ENVIRONMENT FILES ($global:EnvDir):" -ForegroundColor Yellow
    Write-Host "  --env-status         Which files exist and apply to this host and user"
    Write-Host "  (--admin-init creates the host files from the templates; copy a template by hand for *.default.env)"
    Write-Host ""
    Write-Host "OTHER:" -ForegroundColor Yellow
    Write-Host "  --bootstrap          Install Scoop and the bootstrap packages only (part of --user-install)"
    Write-Host "  --self-test          Run the self-tests (parser, expansion, package list, import, export, dry run, help, static check)"
    Write-Host "  --version, -v        Show version"
    Write-Host "  --help, -h           Show this help message"
    Write-Host ""
    Write-Host "FILES:" -ForegroundColor Yellow
    Write-Host "  system.default.env              Machine scope, all hosts"
    Write-Host "  system.HOSTNAME.USERNAME.env    Machine scope, this host and user (source of truth)"
    Write-Host "  user.default.env                User scope, all hosts"
    Write-Host "  user.HOSTNAME.USERNAME.env      User scope, this host and user"
    Write-Host "  etc\packages\default.txt        Package list of the devel profile (delivered); etc\packages\HOSTNAME.txt replaces it"
    Write-Host "  etc\packages\debian.txt         apt packages of the devel profile for --wsl-setup; HOSTNAME.debian.txt replaces it"
    Write-Host "  etc\profiles\                   profiles.conf and one directory per profile (packages.txt, system.env, user.env, debian.txt)"
    Write-Host "  etc\scoop-boot.conf             DIR=<path> lines: directories --admin-init creates (tmp, devl, data); PROFILE=NAMES"
    Write-Host "  etc\exports\NAME.txt            Package export of a machine (--export), input for --import=NAME"
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
# FAKE MODE (SCOOPBOOT_FAKE=1)
# No Scoop, no registry, no processes: the setup commands run end to end against
# a simulated Scoop in the same directory layout (apps\<name>\current with the
# JSON files Scoop writes, shims\, buckets\) and a registry kept in
# etc\fake\registry.json. tools/test.ps1 and the CI run --admin-init,
# --admin-setenv, --user-install, --export, --import, --clean-user-scope and
# --admin-reset this way on every platform. Nothing real is installed or written
# outside the Scoop root. Set the variable in the shell: $env:SCOOPBOOT_FAKE = '1'.
# ============================================================================

function Test-ScoopBootFake {
    return ($env:SCOOPBOOT_FAKE -eq '1')
}

function Get-FakeRegistryPath {
    return (Join-Path $global:BaseDir 'etc\fake\registry.json')
}

function Read-FakeRegistry {
    <#
    .SYNOPSIS
        The simulated registry: a hashtable with Machine and User hashtables (names case-insensitive, as in Windows).
    #>
    $store = @{ Machine = @{}; User = @{} }
    $path = Get-FakeRegistryPath
    if (-not (Test-Path $path)) { return $store }
    try {
        $json = Get-Content -Path $path -Raw | ConvertFrom-Json
        foreach ($scope in @('Machine', 'User')) {
            if ($json.PSObject.Properties.Name -contains $scope -and $json.$scope) {
                foreach ($property in $json.$scope.PSObject.Properties) { $store[$scope][$property.Name] = "$($property.Value)" }
            }
        }
    } catch { }
    return $store
}

function Write-FakeRegistry {
    param([hashtable]$Store)
    $path = Get-FakeRegistryPath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $ordered = [ordered]@{}
    foreach ($scope in @('Machine', 'User')) {
        $values = [ordered]@{}
        foreach ($name in ($Store[$scope].Keys | Sort-Object)) { $values[$name] = $Store[$scope][$name] }
        $ordered[$scope] = $values
    }
    [IO.File]::WriteAllText($path, (($ordered | ConvertTo-Json -Depth 4) + "`n"), (New-Object Text.UTF8Encoding($false)))
}

function Get-RegistryEnvironmentVariable {
    <#
    .SYNOPSIS
        A Machine or User environment variable from the registry, or from the simulated registry in fake mode; Process reads this process.
    #>
    param([string]$Name, [string]$Scope)
    if ($Scope -eq 'Process' -or -not (Test-ScoopBootFake)) { return [Environment]::GetEnvironmentVariable($Name, $Scope) }
    $store = Read-FakeRegistry
    if ($store[$Scope].ContainsKey($Name)) { return $store[$Scope][$Name] }
    return $null
}

function Set-RegistryEnvironmentVariable {
    <#
    .SYNOPSIS
        Writes a Machine or User variable ($null removes it) to the registry, or to the simulated registry in fake mode.
    #>
    param([string]$Name, [object]$Value, [string]$Scope)
    if ($Scope -eq 'Process' -or -not (Test-ScoopBootFake)) {
        # A PowerShell $null reaches .NET as an empty string on pwsh 7.6, which leaves
        # the variable in place (empty) instead of removing it; NullString is a real null
        $raw = if ($null -eq $Value -or "$Value" -eq '') { [NullString]::Value } else { [string]$Value }
        [Environment]::SetEnvironmentVariable($Name, $raw, $Scope)
        return
    }
    $store = Read-FakeRegistry
    if ($null -eq $Value -or "$Value" -eq '') { $store[$Scope].Remove($Name) } else { $store[$Scope][$Name] = [string]$Value }
    Write-FakeRegistry -Store $store
}

function Get-RegistryEnvironmentVariables {
    <#
    .SYNOPSIS
        All variables of a scope as a hashtable (a copy; the registry or the simulated one).
    #>
    param([string]$Scope)
    $result = @{}
    if ($Scope -eq 'Process' -or -not (Test-ScoopBootFake)) {
        $all = [Environment]::GetEnvironmentVariables($Scope)
        foreach ($key in $all.Keys) { $result["$key"] = "$($all[$key])" }
        return $result
    }
    $store = Read-FakeRegistry
    foreach ($key in $store[$Scope].Keys) { $result[$key] = $store[$Scope][$key] }
    return $result
}

function Add-FakeUserPathEntry {
    # What Scoop does on install, reset and shim add: the directory lands in front of the User PATH
    param([string]$Entry)
    $current = Get-RegistryEnvironmentVariable -Name 'Path' -Scope 'User'
    $parts = @(if ($current) { $current -split ';' | Where-Object { $_ } } else { @() })
    if ($parts -notcontains $Entry) { $parts = @($Entry) + $parts }
    Set-RegistryEnvironmentVariable -Name 'Path' -Value ($parts -join ';') -Scope 'User'
}

function Remove-FakeUserPathEntry {
    param([string]$Entry)
    $current = Get-RegistryEnvironmentVariable -Name 'Path' -Scope 'User'
    if (-not $current) { return }
    $parts = @($current -split ';' | Where-Object { $_ -and $_ -ne $Entry })
    Set-RegistryEnvironmentVariable -Name 'Path' -Value $(if ($parts.Count -gt 0) { $parts -join ';' } else { $null }) -Scope 'User'
}

function New-FakeScoopCore {
    <#
    .SYNOPSIS
        What the Scoop installer leaves behind, simulated: apps\scoop\current\bin\scoop.ps1 and shims\scoop.ps1 (+ scoop for a POSIX shell), both forwarding to Invoke-FakeScoop.
    #>
    $root = $global:BaseDir
    $core = Join-Path $root 'apps\scoop\current\bin'
    $shims = Join-Path $root 'shims'
    foreach ($dir in @($core, $shims)) { if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null } }
    $module = Join-Path $global:ScriptRoot 'scoop-boot.psm1'
    $shim = @(
        '# scoop-boot fake Scoop (SCOOPBOOT_FAKE=1): forwards to Invoke-FakeScoop of the module',
        "Import-Module '$module' -DisableNameChecking -Force",
        'exit (Invoke-FakeScoop @args)'
    ) -join "`n"
    foreach ($file in @((Join-Path $core 'scoop.ps1'), (Join-Path $shims 'scoop.ps1'))) { [IO.File]::WriteAllText($file, $shim + "`n", (New-Object Text.UTF8Encoding($false))) }
    [IO.File]::WriteAllText((Join-Path $shims 'scoop'), "#!/bin/sh`nexec pwsh -NoProfile -File `"`$(dirname `"`$0`")/scoop.ps1`" `"`$@`"`n", (New-Object Text.UTF8Encoding($false)))
    Write-Host "[FAKE] Scoop core simulated: $core\scoop.ps1" -ForegroundColor DarkCyan
}

function Invoke-FakeScoop {
    <#
    .SYNOPSIS
        A Scoop that installs nothing: the commands scoop-boot and its tests use, with
        Scoop's side effects on disk and in the (simulated) User scope. Returns the exit code.
    .DESCRIPTION
        install: apps\<name>\current with scoop-install.json and scoop-manifest.json,
        shims\<name>.exe, the directory and shims\ in front of the User PATH, and
        the User variables Scoop's manifests set (JAVA_HOME for a JDK, GRADLE_USER_HOME,
        KOTLIN_HOME, ANT_HOME). uninstall, reset, list, bucket add/list/rm, shim add,
        hold, unhold, update, cleanup, cache, config, status, prefix, which, export
        print what Scoop prints and keep the state consistent.
    #>
    $root = $global:BaseDir
    $arguments = @($args | ForEach-Object { "$_" })
    $command = if ($arguments.Count -gt 0) { $arguments[0].ToLower() } else { '' }
    $rest = @($arguments | Select-Object -Skip 1)
    $appsDir = Join-Path $root 'apps'
    $shimsDir = Join-Path $root 'shims'
    $bucketsDir = Join-Path $root 'buckets'
    $envSet = @{ 'temurin25-jdk' = @{ JAVA_HOME = 'apps\temurin25-jdk\current' }; 'temurin21-jdk' = @{ JAVA_HOME = 'apps\temurin21-jdk\current' }
                 'temurin17-jdk' = @{ JAVA_HOME = 'apps\temurin17-jdk\current' }; 'temurin11-jdk' = @{ JAVA_HOME = 'apps\temurin11-jdk\current' }
                 'gradle' = @{ GRADLE_USER_HOME = 'apps\gradle\current\.gradle' }; 'kotlin' = @{ KOTLIN_HOME = 'apps\kotlin\current' }; 'ant' = @{ ANT_HOME = 'apps\ant\current' } }
    $markers = @{ 'git' = @('cmd\git.exe'); '7zip' = @('7z.exe'); 'temurin25-jdk' = @('bin\java.exe'); 'msys2' = @('msys2_shell.cmd'); 'nmap' = @('ncat.exe'); 'sysinternals' = @('handle64.exe') }
    switch ($command) {
        'install' {
            foreach ($package in $rest) {
                if ($package -like '-*') { continue }
                $name = Get-ManifestAppName -Package $package
                $bucket = if ($package -match '^([^/]+)/') { $Matches[1] } else { 'main' }
                $current = Join-Path (Join-Path $appsDir $name) 'current'
                if (Test-Path $current) { Write-Host "WARN  '$name' ($((Get-Content (Join-Path $current 'scoop-manifest.json') -Raw | ConvertFrom-Json).version)) is already installed."; continue }
                if (-not (Test-Path $bucketsDir)) { New-Item -ItemType Directory -Path $bucketsDir -Force | Out-Null }
                New-Item -ItemType Directory -Path $current -Force | Out-Null
                [IO.File]::WriteAllText((Join-Path $current 'scoop-install.json'), "{`n    `"bucket`":  `"$bucket`",`n    `"architecture`":  `"64bit`"`n}`n")
                [IO.File]::WriteAllText((Join-Path $current 'scoop-manifest.json'), "{`n    `"version`":  `"1.0.0`",`n    `"description`":  `"fake $name`"`n}`n")
                foreach ($marker in @($markers[$name])) {
                    if (-not $marker) { continue }
                    $file = Join-Path $current $marker
                    $dir = Split-Path -Parent $file
                    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                    [IO.File]::WriteAllText($file, '')
                }
                if (-not (Test-Path $shimsDir)) { New-Item -ItemType Directory -Path $shimsDir -Force | Out-Null }
                [IO.File]::WriteAllText((Join-Path $shimsDir "$name.exe"), '')
                Write-Host "Installing '$name' (1.0.0) [64bit] from the '$bucket' bucket"
                Write-Host "Linking $current => $(Join-Path (Join-Path $appsDir $name) '1.0.0')"
                Write-Host "Creating shim for '$name'."
                # Registry values as Scoop writes them on Windows: backslashes under the root
                if (-not ((Get-RegistryEnvironmentVariable -Name 'Path' -Scope 'User') -split ';' -contains "$root\shims")) { Write-Host "Adding $root\shims to your path."; Add-FakeUserPathEntry -Entry "$root\shims" }
                Add-FakeUserPathEntry -Entry "$root\apps\$name\current"
                if ($envSet.ContainsKey($name)) {
                    foreach ($variable in $envSet[$name].Keys) {
                        Set-RegistryEnvironmentVariable -Name $variable -Value "$root\$($envSet[$name][$variable])" -Scope 'User'
                        Write-Host "Environment variable '$variable' set to '$root\$($envSet[$name][$variable])'"
                    }
                }
                Write-Host "'$name' (1.0.0) was installed successfully!"
            }
            return 0
        }
        'uninstall' {
            foreach ($package in $rest) {
                if ($package -like '-*') { continue }
                $name = Get-ManifestAppName -Package $package
                $appDir = Join-Path $appsDir $name
                if (-not (Test-Path $appDir)) { Write-Host "ERROR '$name' isn't installed."; continue }
                Write-Host "Uninstalling '$name' (1.0.0)."
                Remove-Item -Path $appDir -Recurse -Force
                Remove-Item -Path (Join-Path $shimsDir "$name.exe") -Force -ErrorAction SilentlyContinue
                Remove-FakeUserPathEntry -Entry "$root\apps\$name\current"
                if ($envSet.ContainsKey($name)) { foreach ($variable in $envSet[$name].Keys) { Set-RegistryEnvironmentVariable -Name $variable -Value $null -Scope 'User' } }
                Write-Host "'$name' was uninstalled."
            }
            return 0
        }
        'reset' {
            foreach ($package in $rest) {
                $name = Get-ManifestAppName -Package $package
                $current = Join-Path (Join-Path $appsDir $name) 'current'
                if (-not (Test-Path $current)) { Write-Host "ERROR '$name' isn't installed."; continue }
                Write-Host "Resetting $name (1.0.0)."
                Add-FakeUserPathEntry -Entry "$root\apps\$name\current"
                if ($envSet.ContainsKey($name)) { foreach ($variable in $envSet[$name].Keys) { Set-RegistryEnvironmentVariable -Name $variable -Value "$root\$($envSet[$name][$variable])" -Scope 'User' } }
            }
            return 0
        }
        'list' {
            Write-Host "Installed apps:"
            Write-Host ""
            Write-Host "Name   Version Source Updated"
            Write-Host "----   ------- ------ -------"
            foreach ($app in @(Get-InstalledScoopPackages)) { Write-Host ("{0,-22} {1,-8} {2}" -f $app.Name, $app.Version, $app.Bucket) }
            return 0
        }
        'bucket' {
            $sub = if ($rest.Count -gt 0) { $rest[0].ToLower() } else { 'list' }
            if ($sub -eq 'add') {
                $name = $rest[1]
                $url = if ($rest.Count -gt 2) { $rest[2] } else { "https://github.com/ScoopInstaller/$name" }
                $dir = Join-Path $bucketsDir $name
                if (Test-Path $dir) { Write-Host "WARN  The '$name' bucket already exists. To add this bucket again, first remove it by running 'scoop bucket rm $name'."; return 0 }
                New-Item -ItemType Directory -Path (Join-Path $dir 'bucket') -Force | Out-Null
                New-Item -ItemType Directory -Path (Join-Path $dir '.git') -Force | Out-Null
                [IO.File]::WriteAllText((Join-Path (Join-Path $dir '.git') 'config'), "[remote `"origin`"]`n`turl = $url`n")
                Write-Host "Checking repo... OK."
                Write-Host "The $name bucket was added successfully."
                return 0
            }
            if ($sub -eq 'rm') { Remove-Item -Path (Join-Path $bucketsDir $rest[1]) -Recurse -Force -ErrorAction SilentlyContinue; return 0 }
            foreach ($bucket in @(Get-ScoopBuckets)) { Write-Host ("{0,-10} {1}" -f $bucket.Name, $bucket.Url) }
            return 0
        }
        'shim' {
            if ($rest.Count -ge 3 -and $rest[0] -eq 'add') {
                if (-not (Test-Path $shimsDir)) { New-Item -ItemType Directory -Path $shimsDir -Force | Out-Null }
                [IO.File]::WriteAllText((Join-Path $shimsDir "$($rest[1]).exe"), '')
                Add-FakeUserPathEntry -Entry "$root\shims"
                Write-Host "Adding local shim $($rest[1])..."
            }
            return 0
        }
        'prefix' { Write-Host (Join-Path (Join-Path $appsDir (Get-ManifestAppName -Package $rest[0])) 'current'); return 0 }
        'which' { Write-Host (Join-Path $shimsDir "$($rest[0]).exe"); return 0 }
        'hold' { foreach ($p in $rest) { Write-Host "$p is now held and can not be updated anymore." }; return 0 }
        'unhold' { foreach ($p in $rest) { Write-Host "$p is no longer held and can be updated again." }; return 0 }
        'update' { Write-Host "Updating Scoop..."; Write-Host "Scoop was updated successfully!"; return 0 }
        'cleanup' { Write-Host "Everything is shiny now!"; return 0 }
        'cache' { Write-Host "Deleted: 0 files, 0 bytes"; return 0 }
        'config' { Write-Host "'$($rest[0])' has been set to '$($rest[1])'"; return 0 }
        'status' { Write-Host "Scoop is up to date."; Write-Host "Everything is ok!"; return 0 }
        'export' { foreach ($app in @(Get-InstalledScoopPackages)) { Write-Host "$($app.Name) $($app.Version) [$($app.Bucket)]" }; return 0 }
        '--version' { Write-Host "Current Scoop version:"; Write-Host "fake (scoop-boot SCOOPBOOT_FAKE=1)"; return 0 }
        default { Write-Host "[FAKE] scoop $($arguments -join ' '): not simulated, nothing done" -ForegroundColor DarkCyan; return 0 }
    }
}

# In fake mode every "scoop ..." call inside the module resolves to this function
# instead of the shim on the PATH; outside fake mode the function does not exist
if (Test-ScoopBootFake) {
    function scoop { $null = Invoke-FakeScoop @args }
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
        Set-RegistryEnvironmentVariable -Name 'SCOOP' -Value $global:BaseDir -Scope 'User'
        Set-RegistryEnvironmentVariable -Name 'SCOOP_GLOBAL' -Value "$global:BaseDir\global" -Scope 'User'
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
        if (Test-ScoopBootFake) { New-FakeScoopCore }
        else { try {
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
        } }

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
            if (Test-ScoopBootFake) { Write-Success "$($tool.Name) installed (fake, not started)" } else {
            & $exe @($tool.Args) 2>&1 | Out-Null
            Write-Success "$($tool.Name) installed and runs"
            }
        } catch {
            Write-Host "[FATAL] $($tool.Name) is installed but Windows refuses to start $exe" -ForegroundColor Red
            Write-Host "        $($_.Exception.Message)" -ForegroundColor Gray
            Write-Host "        Endpoint security (Defender ASR rule 01443614) blocks newly released binaries on this machine." -ForegroundColor Gray
            Write-Host "        Nothing can be installed until $global:BaseDir is excluded. Check the Defender log for event 1121:" -ForegroundColor Gray
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
    Write-Host "  Administrator shell: $global:ScoopBootScript --admin-init, then --admin-setenv" -ForegroundColor White
    Write-Host "  Normal shell:        $global:ScoopBootScript --user-install" -ForegroundColor White
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
                Set-EnvValue -Name $op.Name -Value $expandedValue -Scope $Scope -DryRun $DryRun
                if ($DryRun) { Write-DryRun "Set $($op.Name) = $expandedValue [$Scope from $fileName]" }
                else { Write-Success "Set $($op.Name) [$Scope]" }
                $changes++
            }

            "Unset" {
                Set-EnvValue -Name $op.Name -Value $null -Scope $Scope -DryRun $DryRun
                if ($DryRun) { Write-DryRun "Unset $($op.Name) [$Scope from $fileName]" }
                else { Write-Success "Unset $($op.Name) [$Scope]" }
                $changes++
            }

            "ListPrepend" {
                $currentValue = Get-EnvValue -Name $op.Name -Scope $Scope
                if ($currentValue) {
                    $parts = $currentValue -split ';' | Where-Object { $_ -and $_ -ne $expandedValue }
                    $newValue = @($expandedValue) + $parts | Select-Object -Unique
                    $newValue = $newValue -join ';'
                } else {
                    $newValue = $expandedValue
                }

                Set-EnvValue -Name $op.Name -Value $newValue -Scope $Scope -DryRun $DryRun
                if ($DryRun) { Write-DryRun "Prepend to $($op.Name): $expandedValue [$Scope from $fileName]" }
                else { Write-Success "Prepended to $($op.Name) [$Scope]" }
                $changes++
            }

            "ListAppend" {
                $currentValue = Get-EnvValue -Name $op.Name -Scope $Scope
                if ($currentValue) {
                    $parts = $currentValue -split ';' | Where-Object { $_ -and $_ -ne $expandedValue }
                    $newValue = $parts + @($expandedValue) | Select-Object -Unique
                    $newValue = $newValue -join ';'
                } else {
                    $newValue = $expandedValue
                }

                Set-EnvValue -Name $op.Name -Value $newValue -Scope $Scope -DryRun $DryRun
                if ($DryRun) { Write-DryRun "Append to $($op.Name): $expandedValue [$Scope from $fileName]" }
                else { Write-Success "Appended to $($op.Name) [$Scope]" }
                $changes++
            }

            "ListRemove" {
                $currentValue = Get-EnvValue -Name $op.Name -Scope $Scope
                $currentParts = @()
                if ($currentValue) {
                    $currentParts = @($currentValue -split ';' | Where-Object { $_ })
                }
                $parts = @($currentParts | Where-Object { $_ -ne $expandedValue })

                if ($parts.Count -eq $currentParts.Count) {
                    Write-Host "[SKIP] Not in $($op.Name): $expandedValue [$Scope]" -ForegroundColor DarkGray
                } else {
                    $newValue = $parts -join ';'
                    Set-EnvValue -Name $op.Name -Value $newValue -Scope $Scope -DryRun $DryRun
                    if ($DryRun) { Write-DryRun "Remove from $($op.Name): $expandedValue [$Scope from $fileName]" }
                    else { Write-Success "Removed from $($op.Name): $expandedValue [$Scope]" }
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
    # Compared with backslashes on both sides: a registry value written with forward
    # slashes (or a Join-Path on a Linux runner in fake mode) still counts
    $normalized = $Path -replace '/', '\'
    foreach ($dir in $global:ScoopOwnedDirs) {
        $prefix = (Join-Path $global:BaseDir $dir) -replace '/', '\'
        if ($normalized -eq $prefix -or $normalized -like "$prefix\*") { return $true }
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

    $current = Get-EnvValue -Name 'Path' -Scope $Scope
    if (-not $current) { return 0 }
    $parts = @($current -split ';' | Where-Object { $_ })
    $keep = @($parts | Where-Object { -not (Test-ScoopOwnedPath $_) })
    $removed = @($parts | Where-Object { Test-ScoopOwnedPath $_ })
    foreach ($entry in $removed) {
        if ($DryRun) { Write-DryRun "Remove from PATH: $entry [$Scope]" }
        else { Write-Success "Removed from PATH: $entry [$Scope]" }
    }
    if ($removed.Count -gt 0) {
        Set-EnvValue -Name 'Path' -Value ($keep -join ';') -Scope $Scope -DryRun $DryRun
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

    # A dry run on its own simulates too; inside Invoke-ApplyEnv the store is already active
    $ownsDryRunState = $DryRun -and -not $global:EnvDryRunState
    if ($ownsDryRunState) { $global:EnvDryRunState = @{ Machine = @{}; User = @{} } }

    $changes = 0
    $changes += Remove-ScoopPathEntries -Scope 'User' -DryRun $DryRun

    $managed = Get-SystemManagedVariableNames
    foreach ($name in $managed) {
        $userValue = Get-EnvValue -Name $name -Scope 'User'
        if ($null -ne $userValue) {
            Set-EnvValue -Name $name -Value $null -Scope 'User' -DryRun $DryRun
            if ($DryRun) { Write-DryRun "Remove User override: $name = $userValue (Machine value from system.* wins)" }
            else { Write-Success "Removed User override: $name (was: $userValue)" }
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
    if ($ownsDryRunState) {
        Write-EnvDryRunSummary
        $global:EnvDryRunState = $null
    }
    return $changes
}


function New-RunResult {
    <#
    .SYNOPSIS
        The result object of a command: Command, Ok, and whatever the command reports (Installed, Failed, Remaining, ...).
    #>
    param([string]$Command, [bool]$Ok, [hashtable]$Data = @{})
    $result = [pscustomobject]@{ PSTypeName = 'ScoopBoot.Result'; Command = $Command; Ok = $Ok }
    foreach ($key in $Data.Keys) { $result | Add-Member -NotePropertyName $key -NotePropertyValue $Data[$key] }
    return $result
}

function Get-RunResult {
    <#
    .SYNOPSIS
        The result object a command returned. The long functions (installation, reset)
        leak stray objects into the pipeline before their result; the typed object is
        picked out, and a run without one counts as failed.
    #>
    param([object[]]$Output)
    $results = @($Output | Where-Object { $_ -is [pscustomobject] -and $_.PSObject.TypeNames -contains 'ScoopBoot.Result' })
    if ($results.Count -gt 0) { return $results[-1] }
    return (New-RunResult -Command 'unknown' -Ok $false -Data @{ Reason = 'the command returned no result' })
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
        return (Get-RunResult -Output @(Invoke-ApplyEnv -DryRun $true)).Ok
    }
    if (-not (Test-AdminRights)) {
        Write-ErrorMsg "--admin-setenv needs an elevated shell (Run as Administrator); --admin-setenv --dry-run works without"
        return $false
    }
    return (Get-RunResult -Output @(Set-DevelopmentEnvironment)).Ok
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
    # The environment file decides what TMP is; if it defines one, it must be applied
    # (Scoop and several installers fail on long or redirected temp paths)
    $expectedTmp = Get-EnvFileMachineValue -Name 'TMP'
    $machineTmp = Get-RegistryEnvironmentVariable -Name 'TMP' -Scope 'Machine'
    if ($expectedTmp -and $machineTmp -ne $expectedTmp) {
        Write-ErrorMsg "Machine-scope TMP is '$machineTmp', the environment file defines '$expectedTmp': setup step 2 has not run. Run as Administrator: $global:ScoopBootScript --admin-setenv"
        return $false
    }
    # Install-ScoopTools itself warns and asks when run from an elevated shell.
    # SCOOP_BOOT_WRAPPER=off and SCOOP_BOOT_CALLER are set for the run and must not
    # outlive it: the script runs in the caller's shell, and with the variable still
    # set every later "scoop install" there would skip the user-scope cleanup (found
    # by the fake end-to-end test, 31.10.)
    $savedTitle = Get-ScoopBootTitle
    $savedWrapper = $env:SCOOP_BOOT_WRAPPER
    $savedCaller = $env:SCOOP_BOOT_CALLER
    try {
        return (Get-RunResult -Output @(Install-ScoopTools -Force $Force)).Ok
    } finally {
        Restore-ScoopBootTitle -Saved $savedTitle
        if ($null -eq $savedWrapper) { Remove-Item Env:SCOOP_BOOT_WRAPPER -ErrorAction SilentlyContinue } else { $env:SCOOP_BOOT_WRAPPER = $savedWrapper }
        if ($null -eq $savedCaller) { Remove-Item Env:SCOOP_BOOT_CALLER -ErrorAction SilentlyContinue } else { $env:SCOOP_BOOT_CALLER = $savedCaller }
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
        return (Get-RunResult -Output @(Invoke-ScoopReset -Force:$Force -KeepPersist:$KeepPersist)).Ok
    } finally {
        Restore-ScoopBootTitle -Saved $savedTitle
    }
}

function Invoke-ListPackages {
    <#
    .SYNOPSIS
        Shows the package list in use; installs nothing.
    #>
    return (Get-RunResult -Output @(Show-PackageList)).Ok
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
    # The directories a developer setup lives in: the Scoop root and the DIR entries
    # of etc\scoop-boot.conf (tmp, devl, data by default)
    $devDirs = @($global:BaseDir) + @((Get-ScoopBootConfig).Dirs)
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
    $machineTmp = Get-RegistryEnvironmentVariable -Name 'TMP' -Scope 'Machine'
    $userTmp = Get-RegistryEnvironmentVariable -Name 'TMP' -Scope 'User'
    $lines += ""
    $lines += "--- Temporary directory ---"
    $lines += "  TMP process=$env:TMP  user=$userTmp  machine=$machineTmp"
    $expectedTmp = Get-EnvFileMachineValue -Name 'TMP'
    if ($expectedTmp -and $machineTmp -ne $expectedTmp) {
        $lines += "  [INFO] Machine TMP is '$machineTmp', the environment file defines '$expectedTmp': setup step 2 (scoop-boot.ps1 --admin-setenv) has not run on this machine"
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
        $global:EnvDryRunState = @{ Machine = @{}; User = @{} }
    } else {
        Write-Section "Environment Apply"
    }

    # Get environment files
    $envFiles = Get-EnvironmentFiles

    if ($envFiles.Count -eq 0) {
        Write-Warning "No environment configuration files found"
        Write-Host ""
        Write-Host "Create them first: $global:ScoopBootScript --admin-init (as Administrator)" -ForegroundColor Yellow
        return (New-RunResult -Command 'apply-env' -Ok $false)
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
        return (New-RunResult -Command 'apply-env' -Ok $false)
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
        Write-Info "DRY RUN: $totalChanges operations"
        Write-EnvDryRunSummary
        $global:EnvDryRunState = $null
        Write-Host ""
        Write-Host "Apply them as Administrator: $global:ScoopBootScript --admin-setenv"
    } else {
        Write-Info "Applied $totalChanges changes"
        Write-Host ""
        Write-Host "IMPORTANT: Restart your shell for changes to take effect!" -ForegroundColor Yellow
        Write-Host "  - Close and reopen: CMD, PowerShell, Terminal" -ForegroundColor White
        Write-Host "  - Restart: Visual Studio, IntelliJ IDEA, VS Code" -ForegroundColor White
        Write-Host "  - Or reboot system for complete refresh" -ForegroundColor White
    }
    return (New-RunResult -Command 'apply-env' -Ok $true -Data @{ Operations = $totalChanges; DryRun = $DryRun })
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

function Get-UnassignedVariableReads {
    <#
    .SYNOPSIS
        Static check: variables a function reads but never assigns (parameters, foreach
        variables, -OutVariable and the like count as assignments). Self-test 48.
    .DESCRIPTION
        Walks the AST of a script or module. For every function the set of assigned
        names is collected (its own parameters and assignments plus, for a nested
        function, those of the enclosing function, which it sees through dynamic
        scoping). A read of a local name outside that set is reported, except for the
        automatic variables. Globals, script-scope and drive-qualified names ($env:) are
        not checked. One line per function and name; empty output means clean.
    #>
    param([string]$Path)
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    if ($errors) { throw "parse error in $Path`: $($errors[0].Message)" }
    $automatic = @('_', 'PSItem', 'null', 'true', 'false', 'args', 'input', 'this', 'PSBoundParameters', 'PSScriptRoot', 'PSCommandPath',
        'MyInvocation', 'Error', 'PID', 'HOME', 'PWD', 'Host', 'PSVersionTable', 'ExecutionContext', 'LASTEXITCODE', 'Matches',
        'IsWindows', 'IsLinux', 'IsMacOS', 'PSCulture', 'PSEdition', 'ErrorActionPreference', 'WarningPreference', 'VerbosePreference',
        'ProgressPreference', 'InformationPreference', 'ConfirmPreference', 'foreach', 'switch', 'StackTrace', 'OutputEncoding',
        'PROFILE', 'ShellId', 'PSDefaultParameterValues')
    $fileName = Split-Path -Leaf $Path
    $assignedOf = @{}
    $functions = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
    foreach ($f in $functions) {
        $assigned = @{}
        $paramLists = @($f.Parameters)
        if ($f.Body.ParamBlock) { $paramLists += @($f.Body.ParamBlock.Parameters) }
        foreach ($p in $paramLists) { if ($p) { $assigned[$p.Name.VariablePath.UserPath] = $true } }
        foreach ($a in $f.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true)) {
            foreach ($v in $a.Left.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) { $assigned[$v.VariablePath.UserPath] = $true }
        }
        foreach ($fe in $f.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.ForEachStatementAst] }, $true)) { $assigned[$fe.Variable.VariablePath.UserPath] = $true }
        foreach ($pb in $f.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.ParamBlockAst] }, $true)) {
            foreach ($p in $pb.Parameters) { $assigned[$p.Name.VariablePath.UserPath] = $true }
        }
        foreach ($nf in $f.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
            foreach ($p in @($nf.Parameters)) { if ($p) { $assigned[$p.Name.VariablePath.UserPath] = $true } }
        }
        foreach ($cp in $f.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandParameterAst] }, $true)) {
            if ($cp.ParameterName -in @('PipelineVariable', 'OutVariable', 'ErrorVariable', 'WarningVariable', 'pv', 'ov', 'ev') -and $cp.Argument) { $assigned[$cp.Argument.Value] = $true }
        }
        $assignedOf[$f] = $assigned
    }
    $result = @()
    foreach ($f in $functions) {
        $assigned = $assignedOf[$f]
        # A nested function sees the variables of the function that defines it
        $outer = $f.Parent
        while ($outer) {
            if ($outer -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $assignedOf.ContainsKey($outer)) {
                foreach ($k in $assignedOf[$outer].Keys) { $assigned[$k] = $true }
            }
            $outer = $outer.Parent
        }
        $seen = @{}
        foreach ($r in $f.Body.FindAll({ param($n) $n -is [System.Management.Automation.Language.VariableExpressionAst] }, $true)) {
            $vp = $r.VariablePath
            if ($vp.IsGlobal -or $vp.IsScript -or $vp.DriveName) { continue }
            $name = $vp.UserPath
            if ($automatic -contains $name -or $assigned.ContainsKey($name) -or $seen.ContainsKey($name)) { continue }
            $seen[$name] = $true
            $result += [pscustomobject]@{ File = $fileName; Function = $f.Name; Variable = $name; Line = $r.Extent.StartLineNumber }
        }
    }
    return $result
}

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
        [Environment]::SetEnvironmentVariable("TEST_VAR_TEMP", [NullString]::Value, "Process")
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
        $null = Apply-EnvironmentOperations -Operations $ops -Scope "Process" -SourceFile "test.env" -DryRun $false
        $result = [Environment]::GetEnvironmentVariable("TEST_PATH_VAR", "Process")
        $test.Result = $result -eq "C:\new;C:\existing"
        [Environment]::SetEnvironmentVariable("TEST_PATH_VAR", [NullString]::Value, "Process")
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
        $listFile = Join-Path ([IO.Path]::GetTempPath()) "scoop-boot-selftest-packages.txt"
        @('# header', '', 'vcredist2022', 'java/temurin25-jdk   # jdk', '  nmap  ', '# trailing') | Set-Content -Path $listFile -Encoding ASCII
        $parsed = @(Read-PackageList -Path $listFile)
        $test.Result = ($parsed.Count -eq 3) -and ($parsed[0] -eq 'vcredist2022') -and ($parsed[1] -eq 'java/temurin25-jdk') -and ($parsed[2] -eq 'nmap')
        Remove-Item $listFile -Force -ErrorAction SilentlyContinue
    } catch {}
    $tests += $test

    # Test 32: package list rejects malformed lines, empty file gives empty array
    $test = @{Name = "Read-PackageList: malformed line ignored, empty file is empty"; Result = $false}
    try {
        $listFile = Join-Path ([IO.Path]::GetTempPath()) "scoop-boot-selftest-packages.txt"
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
        [Environment]::SetEnvironmentVariable("T_SELF", [NullString]::Value, "Process")
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
        # A git working tree is not an installation: its files may differ from the last
        # release, and bin\scoop.cmd is checked out with CRLF while the manifest has the blob
        $isRepo = Test-Path (Join-Path $global:BaseDir '.git')
        if ($isRepo -or (Test-Path $global:BranchFile) -or -not (Test-Path $manifestPath)) {
            $test.Name += " (skipped: $(if ($isRepo) { 'git working tree' } elseif (Test-Path $global:BranchFile) { 'branch files' } else { 'no manifest' }))"
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

    # Test 42: etc\scoop-boot.conf: defaults without the file, DIR lines with and without errors
    $test = @{Name = "scoop-boot.conf: defaults, DIR lines, rejected lines"; Result = $false}
    try {
        $savedBase = $global:BaseDir
        $tempBase = Join-Path ([IO.Path]::GetTempPath()) "scoop-boot-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -ItemType Directory -Path (Join-Path $tempBase 'etc') -Force | Out-Null
        $global:BaseDir = $tempBase
        $defaults = Get-ScoopBootConfig
        $drive = [IO.Path]::GetPathRoot($tempBase)
        $ok1 = (-not $defaults.Exists) -and ($defaults.Dirs.Count -eq 3) -and ($defaults.Dirs[0] -eq (Join-Path $drive 'tmp'))
        "# test`nDIR=D:\dev\tmp`nDIR=D:\dev\data\`nDIR=C:\with space\x`nDIR=relative\path`nOTHER=C:\ignored" | Set-Content -Path (Join-Path $tempBase 'etc\scoop-boot.conf') -Encoding ASCII
        $read = Get-ScoopBootConfig
        $ok2 = $read.Exists -and ($read.Dirs.Count -eq 2) -and ($read.Dirs[0] -eq 'D:\dev\tmp') -and ($read.Dirs[1] -eq 'D:\dev\data') -and ($read.Invalid.Count -eq 2)
        $test.Result = $ok1 -and $ok2
    } catch {} finally {
        $global:BaseDir = $savedBase
        if ($tempBase) { Remove-Item $tempBase -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $tests += $test

    # Test 43: Get-EnvFileMachineValue expands the definition of the system.* files; $null without one
    $test = @{Name = "Env file value for the TMP check (expanded, null without definition)"; Result = $false}
    try {
        $savedEnvDir = $global:EnvDir
        $tempEnv = Join-Path ([IO.Path]::GetTempPath()) "scoop-boot-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -ItemType Directory -Path $tempEnv -Force | Out-Null
        $global:EnvDir = $tempEnv
        $none = Get-EnvFileMachineValue -Name 'TMP'
        "USR=D:\dev`nTMP=`$USR\tmp`nTEMP=`$TMP" | Set-Content -Path (Join-Path $tempEnv 'system.default.env') -Encoding ASCII
        $tmp = Get-EnvFileMachineValue -Name 'TMP'
        $temp = Get-EnvFileMachineValue -Name 'TEMP'
        $other = Get-EnvFileMachineValue -Name 'NOT_DEFINED_HERE'
        $test.Result = ($null -eq $none) -and ($tmp -eq 'D:\dev\tmp') -and ($temp -eq 'D:\dev\tmp') -and ($null -eq $other)
    } catch {} finally {
        $global:EnvDir = $savedEnvDir
        if ($tempEnv) { Remove-Item $tempEnv -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $tests += $test

    # Test 44: handler table: every handler names an existing function and a package of default.txt (or is Optional)
    $test = @{Name = "Handler table: functions exist, packages are in default.txt"; Result = $false}
    try {
        $defaultList = Join-Path $global:PackagesDir 'default.txt'
        $listed = if (Test-Path $defaultList) { @(Read-PackageList -Path $defaultList -Silent | ForEach-Object { Get-ManifestAppName -Package $_ }) } else { @() }
        $problems = @()
        foreach ($entry in $global:PackageHandlers) {
            if (-not (Get-Command $entry.Handler -ErrorAction SilentlyContinue)) { $problems += "$($entry.Name): no function $($entry.Handler)" }
            if (-not $entry.Description) { $problems += "$($entry.Name): no description" }
            $optional = $entry.ContainsKey('Optional') -and $entry.Optional
            if ($listed.Count -gt 0 -and -not $optional -and $listed -notcontains $entry.Name -and $global:BootstrapPackages -notcontains $entry.Name) { $problems += "$($entry.Name): not in default.txt" }
        }
        if ($problems.Count -gt 0) { Write-Host "       $($problems -join '; ')" -ForegroundColor Yellow }
        $test.Result = ($global:PackageHandlers.Count -ge 5) -and ($problems.Count -eq 0) -and ($null -ne (Get-PackageHandler -Name 'msys2')) -and ($null -eq (Get-PackageHandler -Name 'nope'))
    } catch {}
    $tests += $test

    # Test 45: import plan: missing packages, bucket lines, host file from default.txt, second import empty
    $test = @{Name = "Import plan: missing packages, buckets, host file, idempotent"; Result = $false}
    try {
        $savedPackagesDir = $global:PackagesDir; $savedBase = $global:BaseDir
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) "scoop-boot-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'etc\packages') -Force | Out-Null
        $global:BaseDir = $tempRoot; $global:PackagesDir = Join-Path $tempRoot 'etc\packages'
        "# default`nalpha`nextras/beta`n" | Set-Content -Path (Join-Path $global:PackagesDir 'default.txt') -Encoding ASCII
        $exportFile = Join-Path $tempRoot 'old.txt'
        "# export`n# bucket foo https://example.org/foo`n# bucket java https://example.org/java`nalpha  # 1.0`nextras/beta`ngamma  # 2.0, held`nfoo/delta`njava/epsilon`n7zip`n" | Set-Content -Path $exportFile -Encoding ASCII
        $plan = Get-ImportPlan -ExportPath $exportFile
        $ok1 = ($plan.Imported.Count -eq 6) -and ($plan.Missing.Count -eq 3) -and ($plan.Missing[0] -eq 'gamma') -and ($plan.Missing[1] -eq 'foo/delta') -and ($plan.Missing[2] -eq 'java/epsilon')
        $ok2 = ($plan.Buckets.Count -eq 1) -and ($plan.Buckets[0].Name -eq 'foo') -and $plan.CreateFromDefault
        $savedSuppress = $global:ScoopBootQuiet
        $null = Invoke-Import -Source $exportFile *> $null
        $hostFile = Join-Path $global:PackagesDir ("{0}.txt" -f (Get-Hostname))
        $hostText = Get-Content -Path $hostFile -Raw
        $ok3 = (Test-Path $hostFile) -and ($hostText -match '(?m)^alpha$') -and ($hostText -match '(?m)^# import .* from old \(3 of 6 packages were missing\)$') -and ($hostText -match '(?m)^# bucket foo https://example.org/foo$') -and ($hostText -match '(?m)^foo/delta$')
        $plan2 = Get-ImportPlan -ExportPath $exportFile
        $ok4 = ($plan2.Missing.Count -eq 0) -and (-not $plan2.CreateFromDefault)
        $buckets = @(Read-PackageListBuckets -Path $hostFile)
        $ok5 = ($buckets.Count -eq 1) -and ($buckets[0].Url -eq 'https://example.org/foo')
        $test.Result = $ok1 -and $ok2 -and $ok3 -and $ok4 -and $ok5
    } catch {} finally {
        $global:PackagesDir = $savedPackagesDir; $global:BaseDir = $savedBase
        if ($tempRoot) { Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $tests += $test

    # Test 46: dry-run net effect: the simulated store never touches the registry and the diff names the changes
    $test = @{Name = "Dry run: simulated store, net effect (new, removed, changed, PATH order)"; Result = $false}
    try {
        [Environment]::SetEnvironmentVariable('SB_T_LIST', 'C:\a;C:\b;C:\c', 'Process')
        [Environment]::SetEnvironmentVariable('SB_T_SAME', 'x', 'Process')
        [Environment]::SetEnvironmentVariable('SB_T_GONE', 'y', 'Process')
        $global:EnvDryRunState = @{ Process = @{} }
        Set-EnvValue -Name 'SB_T_LIST' -Value 'C:\c;C:\a;C:\d' -Scope 'Process' -DryRun $true
        Set-EnvValue -Name 'SB_T_SAME' -Value 'x' -Scope 'Process' -DryRun $true
        Set-EnvValue -Name 'SB_T_GONE' -Value $null -Scope 'Process' -DryRun $true
        Set-EnvValue -Name 'SB_T_NEW' -Value 'n' -Scope 'Process' -DryRun $true
        $untouched = ([Environment]::GetEnvironmentVariable('SB_T_LIST', 'Process') -eq 'C:\a;C:\b;C:\c') -and ($null -eq [Environment]::GetEnvironmentVariable('SB_T_NEW', 'Process'))
        $simulated = (Get-EnvValue -Name 'SB_T_LIST' -Scope 'Process') -eq 'C:\c;C:\a;C:\d'
        $diff = @(Get-EnvDryRunDiff -Scope 'Process')
        $byName = @{}; foreach ($d in $diff) { $byName[$d.Name] = $d }
        $list = $byName['SB_T_LIST']
        $test.Result = $untouched -and $simulated -and ($byName['SB_T_NEW'].Kind -eq 'new') -and ($byName['SB_T_GONE'].Kind -eq 'removed') -and ($byName['SB_T_SAME'].Kind -eq 'unchanged') -and
            ($list.Kind -eq 'changed') -and ($list.Added -join ',') -eq 'C:\d' -and ($list.Removed -join ',') -eq 'C:\b' -and $list.OrderChanged
    } catch {} finally {
        $global:EnvDryRunState = $null
        foreach ($n in 'SB_T_LIST', 'SB_T_SAME', 'SB_T_GONE', 'SB_T_NEW') { [Environment]::SetEnvironmentVariable($n, [NullString]::Value, 'Process') }
    }
    $tests += $test

    # Test 47: export reads scoop-install.json / scoop-manifest.json (and the old names), skips bootstrap packages and scoop itself
    $test = @{Name = "Export: packages from apps\*\current, buckets from .git\config"; Result = $false}
    try {
        $savedBase = $global:BaseDir
        $tempRoot = Join-Path ([IO.Path]::GetTempPath()) "scoop-boot-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        foreach ($app in @(@{ n = 'temurin11-jdk'; b = 'java'; v = '11.0.32-101'; h = $false; new = $true }, @{ n = 'vscode'; b = 'extras'; v = '1.143.1'; h = $true; new = $true }, @{ n = 'jq'; b = 'main'; v = '1.8.2'; h = $false; new = $false }, @{ n = '7zip'; b = 'main'; v = '26.05'; h = $false; new = $true }, @{ n = 'scoop'; b = ''; v = 'x'; h = $false; new = $true })) {
            $d = Join-Path $tempRoot "apps\$($app.n)\current"
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            $install = @{ bucket = $app.b; architecture = '64bit' }
            if ($app.h) { $install.hold = $true }
            $installName = if ($app.new) { 'scoop-install.json' } else { 'install.json' }
            $manifestName = if ($app.new) { 'scoop-manifest.json' } else { 'manifest.json' }
            ($install | ConvertTo-Json) | Set-Content -Path (Join-Path $d $installName) -Encoding ASCII
            (@{ version = $app.v } | ConvertTo-Json) | Set-Content -Path (Join-Path $d $manifestName) -Encoding ASCII
        }
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'buckets\extras\.git') -Force | Out-Null
        "[remote `"origin`"]`n`turl = https://github.com/ScoopInstaller/Extras`n" | Set-Content -Path (Join-Path $tempRoot 'buckets\extras\.git\config') -Encoding ASCII
        $global:BaseDir = $tempRoot
        $packages = @(Get-InstalledScoopPackages)
        $byName = @{}; foreach ($pk in $packages) { $byName[$pk.Name] = $pk }
        $ok1 = ($packages.Count -eq 4) -and ($byName['vscode'].Bucket -eq 'extras') -and $byName['vscode'].Held -and ($byName['jq'].Version -eq '1.8.2') -and ($byName['temurin11-jdk'].Version -eq '11.0.32-101') -and -not $byName.ContainsKey('scoop')
        $buckets = @(Get-ScoopBuckets)
        $ok2 = ($buckets.Count -eq 1) -and ($buckets[0].Url -eq 'https://github.com/ScoopInstaller/Extras')
        $null = Invoke-Export -Name 'unit' *> $null
        $exported = @(Read-PackageList -Path (Join-Path $tempRoot 'etc\exports\unit.txt') -Silent)
        $ok3 = ($exported.Count -eq 3) -and ($exported -contains 'java/temurin11-jdk') -and ($exported -contains 'extras/vscode') -and ($exported -contains 'jq') -and ($exported -notcontains '7zip')
        $test.Result = $ok1 -and $ok2 -and $ok3
    } catch {} finally {
        $global:BaseDir = $savedBase
        if ($tempRoot) { Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $tests += $test

    # Test 48: no function reads a variable it never assigns (the static side of strict
    # mode; Install and Reset run under version 1, where such a read is an error)
    $test = @{Name = "Static: no function reads a variable it never assigns"; Result = $false}
    try {
        $reads = @()
        foreach ($file in @('scoop-boot.ps1', 'scoop-boot.psm1')) {
            $reads += @(Get-UnassignedVariableReads -Path (Join-Path $global:ScriptRoot $file))
        }
        foreach ($r in $reads) { Write-Warning "$($r.File):$($r.Line) $($r.Function) reads `$$($r.Variable) without assigning it" }
        $test.Result = ($reads.Count -eq 0)
    } catch {}
    $tests += $test

    # Test 49: WSL options parse (--wsl-install, --wsl-setup, --distro=NAME, --no-claude)
    $test = @{Name = "WSL options parse"; Result = $false}
    try {
        $savedArgs = $global:ParsedArgs.Clone()
        $global:ParsedArgs = @{WslInstall = $false; WslSetup = $false; Distro = 'Debian'; NoClaude = $false; DryRun = $false; Unknown = @()}
        Parse-Arguments -Arguments @('--wsl-install', '--wsl-setup', '--distro=Ubuntu-24.04', '--no-claude', '--dry-run')
        $test.Result = $global:ParsedArgs.WslInstall -and $global:ParsedArgs.WslSetup -and
            $global:ParsedArgs.Distro -eq 'Ubuntu-24.04' -and $global:ParsedArgs.NoClaude -and
            $global:ParsedArgs.DryRun -and @($global:ParsedArgs.Unknown).Count -eq 0
        $global:ParsedArgs = $savedArgs
    } catch {}
    $tests += $test

    # Test 50: Windows path to WSL path (drive letter lower case, no drive letter: $null)
    $test = @{Name = "Windows path to WSL path"; Result = $false}
    try {
        $test.Result = ((ConvertTo-WslPath -Path 'C:\usr\etc\wsl\debian-setup.sh') -eq '/mnt/c/usr/etc/wsl/debian-setup.sh') -and
            ((ConvertTo-WslPath -Path 'D:\') -eq '/mnt/d') -and
            ($null -eq (ConvertTo-WslPath -Path '\\server\share\x'))
    } catch {}
    $tests += $test

    # Test 51: Debian package list: comments, blanks and duplicates dropped; the delivered list is valid
    $test = @{Name = "Debian package list"; Result = $false}
    try {
        $tmp = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tmp -Value @('git', '# comment', '  jq  # tool', '', 'git') -Encoding ASCII
        $parsed = @(Read-DebianPackageList -Path $tmp)
        Remove-Item $tmp -Force
        $ok = ($parsed.Count -eq 2) -and ($parsed[0] -eq 'git') -and ($parsed[1] -eq 'jq')
        $delivered = Join-Path $global:BaseDir 'etc\packages\debian.txt'
        if (Test-Path $delivered) {
            $names = @(Read-DebianPackageList -Path $delivered)
            $bad = @($names | Where-Object { $_ -notmatch '^[a-z0-9][a-z0-9+.-]+$' })
            if ($bad.Count -gt 0) { Write-Warning "debian.txt: not an apt package name: $($bad -join ', ')" }
            $ok = $ok -and ($names.Count -gt 0) -and ($bad.Count -eq 0)
        }
        $test.Result = $ok
    } catch {}
    $tests += $test

    # Test 52: wsl --list --quiet text: names kept, blank lines and messages dropped
    $test = @{Name = "WSL distribution list"; Result = $false}
    try {
        $two = @(ConvertFrom-WslList -Text "Debian`r`nUbuntu-24.04`r`n`r`n")
        $none = @(ConvertFrom-WslList -Text "Windows Subsystem for Linux has no installed distributions.`r`n")
        $test.Result = ($two.Count -eq 2) -and ($two[0] -eq 'Debian') -and ($none.Count -eq 0)
    } catch {}
    $tests += $test

    # Test 53: profile catalog: profiles.conf parses, base first, every directory and virtual member present
    $test = @{Name = "Profile catalog: profiles.conf, directories, virtual members"; Result = $false}
    try {
        $catalog = Get-ProfileCatalog
        if ($catalog.Errors.Count -gt 0) { Write-Host "       $($catalog.Errors -join '; ')" -ForegroundColor Yellow }
        $test.Result = ($catalog.Errors.Count -eq 0) -and ($catalog.Singles.Count -ge 10) -and
            ($catalog.Singles[0].Name -eq 'base') -and ($catalog.VirtualOrder -contains 'devel') -and ($catalog.VirtualOrder -contains 'devops')
    } catch {}
    $tests += $test

    # Test 54: Resolve-Profiles on a small catalog: virtual expansion, catalog order, implicit base, unknown name, cycle
    $test = @{Name = "Resolve-Profiles: virtual profiles, order, base, unknown, cycle"; Result = $false}
    $tempProfiles = Join-Path ([IO.Path]::GetTempPath()) "scoop-boot-profiles-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    try {
        foreach ($name in @('base', 'b', 'a', 'c++')) {
            New-Item -ItemType Directory -Path (Join-Path $tempProfiles $name) -Force | Out-Null
            Set-Content -Path (Join-Path (Join-Path $tempProfiles $name) 'packages.txt') -Value "# $name`n$name-tool`nshared" -Encoding ASCII
        }
        Set-Content -Path (Join-Path (Join-Path $tempProfiles 'a') 'system.env') -Value "A_HOME=`$USR\apps\a`nPATH+=`$A_HOME\bin`n# bucket extra https://example.invalid/extra" -Encoding ASCII
        Set-Content -Path (Join-Path (Join-Path $tempProfiles 'b') 'system.env') -Value "B_HOME=`$USR\apps\b`nPATH+=`$B_HOME\bin" -Encoding ASCII
        Set-Content -Path (Join-Path (Join-Path $tempProfiles 'base') 'system.env') -Value "USR=C:\usr`nLANG=C" -Encoding ASCII
        Set-Content -Path (Join-Path (Join-Path $tempProfiles 'base') 'debian.txt') -Value "curl" -Encoding ASCII
        Set-Content -Path (Join-Path $tempProfiles 'system.footer.env') -Value "PATH+=`$USR\shims`nPATH+=`$USR\bin" -Encoding ASCII
        Set-Content -Path (Join-Path $tempProfiles 'profiles.conf') -Value @(
            '# test catalog', 'profile base  the base', 'profile b     second', 'profile a     first by name, later in order', 'profile c++   plus in the name',
            'x=a', 'y = x, b', 'loop1=loop2', 'loop2=loop1', 'all=y,c++') -Encoding ASCII
        $catalog = Get-ProfileCatalog -Dir $tempProfiles
        $y = Resolve-Profiles -Names 'y' -Catalog $catalog
        $ab = Resolve-Profiles -Names 'a,b' -Catalog $catalog
        $all = Resolve-Profiles -Names ' all ' -Catalog $catalog
        $bad = Resolve-Profiles -Names 'a,nosuch' -Catalog $catalog
        $loop = Resolve-Profiles -Names 'loop1' -Catalog $catalog
        $none = Resolve-Profiles -Names '' -Catalog $catalog
        $test.Result = ($catalog.Errors.Count -eq 0) -and
            (($y.Names -join ',') -eq 'base,b,a') -and ($y.Errors.Count -eq 0) -and
            (($ab.Names -join ',') -eq 'base,b,a') -and
            (($all.Names -join ',') -eq 'base,b,a,c++') -and
            ($bad.Errors.Count -eq 1) -and ($bad.Errors[0] -like "*unknown profile 'nosuch'*") -and
            ($loop.Errors.Count -ge 1) -and ($loop.Errors[0] -like '*circle*') -and
            ($none.Errors.Count -eq 1)
        if (-not $test.Result) { Write-Host "       y=$($y.Names -join ',') ab=$($ab.Names -join ',') all=$($all.Names -join ',') bad=$($bad.Errors -join ';') loop=$($loop.Errors -join ';')" -ForegroundColor Yellow }
    } catch { Write-Host "       $($_.Exception.Message)" -ForegroundColor Yellow }
    $tests += $test

    # Test 55: composition on the same catalog: duplicates left out, bucket line once, sections in order, footer last, USR replaced
    $test = @{Name = "Profile composition: package list, bucket lines, environment, footer"; Result = $false}
    try {
        $catalog = Get-ProfileCatalog -Dir $tempProfiles
        $names = (Resolve-Profiles -Names 'all' -Catalog $catalog).Names
        $pk = New-ProfilePackageListText -Profiles $names -File 'packages.txt' -FileName 'h.txt' -Command 'test' -Dir $tempProfiles
        $deb = New-ProfilePackageListText -Profiles $names -File 'debian.txt' -FileName 'h.debian.txt' -Command 'test' -Dir $tempProfiles
        $sys = New-ProfileEnvironmentText -Profiles $names -Scope system -HostName 'h' -UserName 'u' -Root 'D:\scoop' -Command 'test' -Dir $tempProfiles
        $usr = New-ProfileEnvironmentText -Profiles $names -Scope user -HostName 'h' -UserName 'u' -Root 'D:\scoop' -Command 'test' -Dir $tempProfiles
        $pkLines = @($pk.Text -split "`n")
        $sysOps = @($sys.Text -split "`n" | Where-Object { $_ -and -not $_.StartsWith('#') })
        $test.Result = (($pk.Packages -join ',') -eq 'base-tool,shared,b-tool,a-tool,c++-tool') -and
            ($pk.Duplicates.Count -eq 3) -and
            (@($pkLines | Where-Object { $_ -match '^# bucket extra ' }).Count -eq 0) -and
            (($deb.Packages -join ',') -eq 'curl') -and
            (($sysOps -join ',') -eq 'USR=D:\scoop,LANG=C,B_HOME=$USR\apps\b,PATH+=$B_HOME\bin,A_HOME=$USR\apps\a,PATH+=$A_HOME\bin,PATH+=$USR\shims,PATH+=$USR\bin') -and
            ($sys.Operations -eq 8) -and ($sys.Text -match '(?m)^# File: system\.h\.u\.env$') -and ($sys.Text -match '(?m)^# Profiles: base, b, a, c\+\+$') -and
            ($null -eq $usr) -and
            ($pk.Text.IndexOf('# ---- profile b ----') -lt $pk.Text.IndexOf('# ---- profile a ----'))
        if (-not $test.Result) { Write-Host "       packages=$($pk.Packages -join ',') dup=$($pk.Duplicates.Count) ops=$($sysOps -join ',')" -ForegroundColor Yellow }
        # bucket lines live in packages.txt, not system.env: check that one from a package fragment is kept once
        Add-Content -Path (Join-Path (Join-Path $tempProfiles 'a') 'packages.txt') -Value '# bucket extra https://example.invalid/extra' -Encoding ASCII
        Add-Content -Path (Join-Path (Join-Path $tempProfiles 'b') 'packages.txt') -Value '# bucket extra https://example.invalid/extra' -Encoding ASCII
        $pk = New-ProfilePackageListText -Profiles $names -File 'packages.txt' -FileName 'h.txt' -Command 'test' -Dir $tempProfiles
        $test.Result = $test.Result -and (@($pk.Text -split "`n" | Where-Object { $_ -match '^# bucket extra ' }).Count -eq 1) -and (@(Read-PackageListBuckets -Path (Join-Path (Join-Path $tempProfiles 'a') 'packages.txt')).Count -eq 1)
    } catch { Write-Host "       $($_.Exception.Message)" -ForegroundColor Yellow }
    $tests += $test

    # Test 56: Invoke-Profile in a scratch root: dry run writes nothing; files and PROFILE= written; kept without -Force; -Force keeps .bak
    $test = @{Name = "Invoke-Profile: dry run, write, kept, --force with .bak, PROFILE in scoop-boot.conf"; Result = $false}
    $savedRoot = @{ BaseDir = $global:BaseDir; PackagesDir = $global:PackagesDir; EnvDir = $global:EnvDir; ProfilesDir = $global:ProfilesDir }
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) "scoop-boot-profile-root-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    try {
        New-Item -ItemType Directory -Path (Join-Path $tempRoot 'etc') -Force | Out-Null
        Copy-Item -Path $tempProfiles -Destination (Join-Path $tempRoot 'etc\profiles') -Recurse
        $global:BaseDir = $tempRoot
        $global:PackagesDir = Join-Path $tempRoot 'etc\packages'
        $global:EnvDir = Join-Path $tempRoot 'etc\environments'
        $global:ProfilesDir = Join-Path $tempRoot 'etc\profiles'
        $hostName = Get-Hostname
        $userName = Get-Username
        $listFile = Join-Path $global:PackagesDir "$hostName.txt"
        $sysFile = Join-Path $global:EnvDir "system.$hostName.$userName.env"
        $dry = Invoke-Profile -Names 'y' -DryRun $true 6> $null
        $dryClean = -not (Test-Path $listFile) -and -not (Test-Path $sysFile) -and -not (Test-Path (Join-Path $tempRoot 'etc\scoop-boot.conf'))
        $first = Invoke-Profile -Names 'y' 6> $null
        $config = Get-ScoopBootConfig
        $firstOk = (Test-Path $listFile) -and (Test-Path $sysFile) -and (Test-Path (Join-Path $global:PackagesDir "$hostName.debian.txt")) -and
            ($config.Profile -eq 'y') -and ((Get-Content $sysFile -Raw) -match '(?m)^# Profiles: base, b, a$')
        $kept = Invoke-Profile -Names 'a' 6> $null
        $keptOk = ((Get-Content $sysFile -Raw) -match '(?m)^# Profiles: base, b, a$') -and -not (Test-Path "$sysFile.bak")
        $keepExisting = Invoke-Profile -Names 'a' -KeepExisting $true 6> $null
        $forced = Invoke-Profile -Names 'a' -Force $true 6> $null
        $forcedOk = ((Get-Content $sysFile -Raw) -match '(?m)^# Profiles: base, a$') -and (Test-Path "$sysFile.bak") -and
            ((Get-ScoopBootConfig).Profile -eq 'a') -and (@(Get-Content (Join-Path $tempRoot 'etc\scoop-boot.conf') | Where-Object { $_ -match '^PROFILE=' }).Count -eq 1)
        $unknown = Invoke-Profile -Names 'nosuch' 6> $null
        $test.Result = $dry -and $dryClean -and $first -and $firstOk -and (-not $kept) -and $keptOk -and $keepExisting -and $forced -and $forcedOk -and (-not $unknown)
        if (-not $test.Result) { Write-Host "       dry=$dry/$dryClean first=$first/$firstOk kept=$kept/$keptOk keepExisting=$keepExisting forced=$forced/$forcedOk unknown=$unknown" -ForegroundColor Yellow }
    } catch { Write-Host "       $($_.Exception.Message)" -ForegroundColor Yellow }
    finally {
        $global:BaseDir = $savedRoot.BaseDir; $global:PackagesDir = $savedRoot.PackagesDir; $global:EnvDir = $savedRoot.EnvDir; $global:ProfilesDir = $savedRoot.ProfilesDir
        Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $tempProfiles -Recurse -Force -ErrorAction SilentlyContinue
    }
    $tests += $test

    # Test 57: the delivered profiles: devel is default.txt and debian.txt, names valid, c++ behind perl and Git, bin last
    $test = @{Name = "Delivered profiles: devel equals default.txt and debian.txt, PATH order"; Result = $false}
    try {
        $names = (Resolve-Profiles -Names 'devel').Names
        $pk = New-ProfilePackageListText -Profiles $names -File 'packages.txt' -FileName 'default.txt' -Command 'test'
        $deb = New-ProfilePackageListText -Profiles $names -File 'debian.txt' -FileName 'debian.txt' -Command 'test'
        $delivered = @(Read-PackageList -Path (Join-Path $global:PackagesDir 'default.txt') -Silent)
        $deliveredDebian = @(Read-DebianPackageList -Path (Join-Path $global:PackagesDir 'debian.txt'))
        $sameScoop = (($pk.Packages | Sort-Object) -join ',') -eq (($delivered | Sort-Object) -join ',')
        $sameDebian = (($deb.Packages | Sort-Object) -join ',') -eq (($deliveredDebian | Sort-Object) -join ',')
        $badDebian = @($deb.Packages | Where-Object { $_ -notmatch '^[a-z0-9][a-z0-9+.-]+$' })
        $sys = New-ProfileEnvironmentText -Profiles $names -Scope system -HostName 'h' -UserName 'u' -Root 'C:\usr' -Command 'test'
        $paths = @($sys.Text -split "`n" | Where-Object { $_ -match '^PATH' })
        $ucrt = [array]::IndexOf($paths, 'PATH+=$MSYS2_HOME\ucrt64\bin')
        $perl = [array]::IndexOf($paths, 'PATH+=$PERL_HOME\perl\bin')
        $git = [array]::IndexOf($paths, 'PATH+=$GIT_HOME\mingw64\bin')
        $orderOk = ($ucrt -gt $perl) -and ($perl -gt $git) -and ($git -ge 0) -and ($paths[-1] -eq 'PATH+=$USR\bin') -and ($paths[-2] -eq 'PATH+=$USR\shims')
        $devops = (Resolve-Profiles -Names 'devops').Names
        $devopsOk = ($devops -contains 'base') -and ($devops -notcontains 'java') -and ($devops -contains 'python')
        $test.Result = $sameScoop -and $sameDebian -and ($badDebian.Count -eq 0) -and ($pk.Duplicates.Count -eq 0) -and ($deb.Duplicates.Count -eq 0) -and $orderOk -and $devopsOk
        if (-not $test.Result) {
            Write-Host "       scoop same=$sameScoop (profile $($pk.Packages.Count), default.txt $($delivered.Count)) debian same=$sameDebian order=$orderOk ucrt=$ucrt perl=$perl git=$git dup=$($pk.Duplicates -join ',')" -ForegroundColor Yellow
            Write-Host "       only in profiles: $(($pk.Packages | Where-Object { $delivered -notcontains $_ }) -join ' '); only in default.txt: $(($delivered | Where-Object { $pk.Packages -notcontains $_ }) -join ' ')" -ForegroundColor Yellow
        }
    } catch { Write-Host "       $($_.Exception.Message)" -ForegroundColor Yellow }
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
# EXPORT / IMPORT: carry the installed packages of one machine into the package
# list of another. Nothing is read from "scoop list" or "scoop bucket list": both
# are formatted tables that truncate long names ("temurin11..."); the files Scoop
# writes under apps\ and buckets\ carry the full data.
# ============================================================================

function Get-InstalledScoopPackages {
    <#
    .SYNOPSIS
        The packages Scoop has installed, from apps\<name>\current\scoop-install.json: Name, Bucket, Version, Held.
    .NOTES
        Scoop renamed install.json and manifest.json to scoop-install.json and
        scoop-manifest.json; both names are accepted, the new one first.
    #>
    $result = @()
    $appsDir = Join-Path $global:BaseDir 'apps'
    if (-not (Test-Path $appsDir)) { return $result }
    foreach ($dir in (Get-ChildItem -Path $appsDir -Directory | Sort-Object Name)) {
        if ($dir.Name -eq 'scoop') { continue }
        $installJson = @('scoop-install.json', 'install.json') | ForEach-Object { Join-Path $dir.FullName "current\$_" } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (-not $installJson) { continue }
        $bucket = ''; $held = $false; $version = ''
        try {
            $install = Get-Content -Path $installJson -Raw | ConvertFrom-Json
            if ($install.PSObject.Properties.Name -contains 'bucket' -and $install.bucket) { $bucket = "$($install.bucket)" }
            if ($install.PSObject.Properties.Name -contains 'hold' -and $install.hold) { $held = $true }
        } catch { }
        $manifestJson = @('scoop-manifest.json', 'manifest.json') | ForEach-Object { Join-Path $dir.FullName "current\$_" } | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($manifestJson) {
            try { $version = "$((Get-Content -Path $manifestJson -Raw | ConvertFrom-Json).version)" } catch { }
        }
        $result += [pscustomobject]@{ Name = $dir.Name; Bucket = $bucket; Version = $version; Held = $held }
    }
    return $result
}

function Get-ScoopBuckets {
    <#
    .SYNOPSIS
        The buckets under buckets\: Name and the git remote URL from .git\config.
    #>
    $result = @()
    $bucketsDir = Join-Path $global:BaseDir 'buckets'
    if (-not (Test-Path $bucketsDir)) { return $result }
    foreach ($dir in (Get-ChildItem -Path $bucketsDir -Directory | Sort-Object Name)) {
        $url = ''
        $gitConfig = Join-Path $dir.FullName '.git\config'
        if (Test-Path $gitConfig) {
            $line = Get-Content -Path $gitConfig | Where-Object { $_ -match '^\s*url\s*=\s*(\S+)' } | Select-Object -First 1
            if ($line -and $line -match '^\s*url\s*=\s*(\S+)') { $url = $Matches[1] }
        }
        $result += [pscustomobject]@{ Name = $dir.Name; Url = $url }
    }
    return $result
}

function Read-PackageListBuckets {
    <#
    .SYNOPSIS
        "# bucket NAME URL" lines of a package list or export file: buckets to add before the packages.
    #>
    param([string]$Path)
    $result = @()
    if (-not (Test-Path $Path)) { return $result }
    foreach ($line in (Get-Content -Path $Path)) {
        if ($line -match '^\s*#\s*bucket\s+([A-Za-z0-9._-]+)\s+(\S+)\s*$') { $result += [pscustomobject]@{ Name = $Matches[1]; Url = $Matches[2] } }
    }
    return $result
}

function Invoke-Export {
    <#
    .SYNOPSIS
        Writes the installed packages and the buckets of this machine to etc\exports\NAME.txt, in package list format. Called by --export.
    #>
    param([string]$Name = '')
    if (-not $Name) { $Name = Get-Hostname }
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { Write-ErrorMsg "Export name must be a plain name (letters, digits, . _ -): '$Name'"; return $false }
    Write-Section "Export: $Name"
    $packages = @(Get-InstalledScoopPackages)
    if ($packages.Count -eq 0) { Write-ErrorMsg "No Scoop packages under $global:BaseDir\apps"; return $false }
    $buckets = @(Get-ScoopBuckets)
    $exportDir = Join-Path $global:BaseDir 'etc\exports'
    if (-not (Test-Path $exportDir)) { New-Item -ItemType Directory -Path $exportDir -Force | Out-Null }
    $target = Join-Path $exportDir "$Name.txt"
    $lines = @(
        "# scoop-boot export: host $(Get-Hostname), user $(Get-Username), $(Get-Date -Format 'yyyy-MM-dd HH:mm'), scoop-boot $global:ScriptVersion",
        "# Package list format: one package per line, bucket/name for packages outside main.",
        "# On another machine: copy this file to etc\exports\ there and run",
        "#   scoop-boot.ps1 --import=$Name   (adds what its package list lacks; --user-install installs it)",
        "# Bootstrap packages ($($global:BootstrapPackages -join ', ')) are not listed: --user-install installs them first."
    )
    foreach ($bucket in $buckets) { $lines += "# bucket $($bucket.Name) $($bucket.Url)" }
    $lines += ''
    $skipped = 0
    foreach ($package in $packages) {
        if ($global:BootstrapPackages -contains $package.Name) { $skipped++; continue }
        $entry = if ($package.Bucket -and $package.Bucket -ne 'main') { "$($package.Bucket)/$($package.Name)" } else { $package.Name }
        $note = @()
        if ($package.Version) { $note += $package.Version }
        if ($package.Held) { $note += 'held' }
        $lines += if ($note.Count -gt 0) { "{0,-40} # {1}" -f $entry, ($note -join ', ') } else { $entry }
    }
    [IO.File]::WriteAllText($target, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    Write-Success "Exported $($packages.Count - $skipped) packages and $($buckets.Count) buckets: $target"
    Write-Info "Copy the file to etc\exports\ on the other machine, then: <root>\bin\scoop-boot.ps1 --import=$Name"
    return $true
}

function Get-ImportPlan {
    <#
    .SYNOPSIS
        What --import would add: packages missing from the effective list, buckets missing on this machine, the target file.
    #>
    param([string]$ExportPath)
    $imported = @(Read-PackageList -Path $ExportPath)
    $importedBuckets = @(Read-PackageListBuckets -Path $ExportPath)
    $hostFile = Join-Path $global:PackagesDir ("{0}.txt" -f (Get-Hostname))
    $defaultFile = Join-Path $global:PackagesDir 'default.txt'
    $effective = Get-PackageListFile
    $present = @()
    if ($effective) { $present = @(Read-PackageList -Path $effective -Silent | ForEach-Object { Get-ManifestAppName -Package $_ }) }
    $present += $global:BootstrapPackages
    $missing = @($imported | Where-Object { $present -notcontains (Get-ManifestAppName -Package $_) })
    # Buckets Scoop adds by itself when a known bucket/name is installed need no line;
    # others are written as "# bucket" lines that Step 2 of --user-install adds
    $known = @('main', 'extras', 'versions', 'java', 'nerd-fonts', 'nirsoft', 'php', 'games', 'sysinternals', 'nonportable')
    $existingBuckets = @(Get-ScoopBuckets | ForEach-Object { $_.Name })
    $neededBucketNames = @($missing | Where-Object { $_ -match '/' } | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique)
    $buckets = @($importedBuckets | Where-Object { $neededBucketNames -contains $_.Name -and $known -notcontains $_.Name -and $existingBuckets -notcontains $_.Name })
    return [pscustomobject]@{
        Source = $ExportPath; Imported = $imported; Missing = $missing; Buckets = $buckets
        Target = $hostFile; CreateFromDefault = (-not (Test-Path $hostFile)) -and (Test-Path $defaultFile)
    }
}

function Invoke-Import {
    <#
    .SYNOPSIS
        Adds the packages of an export file that this machine's package list lacks to etc\packages\<host>.txt. Called by --import.
    .DESCRIPTION
        The host file is created from default.txt when it does not exist. Packages
        that are already listed are not added again, so a second import is harmless.
        With -Replace the host file is written from the export alone: the machine
        gets exactly the old machine's list, default.txt no longer counts. Nothing
        is installed or uninstalled either way: --list-packages shows the lines,
        --user-install installs them, the next --admin-reset removes what is not listed.
    #>
    param([string]$Source, [bool]$DryRun = $false, [bool]$Replace = $false)
    $path = $Source
    if (-not (Test-Path $path)) {
        $candidate = Join-Path $global:BaseDir "etc\exports\$Source"
        if (Test-Path $candidate) { $path = $candidate }
        elseif (Test-Path "$candidate.txt") { $path = "$candidate.txt" }
    }
    if (-not (Test-Path $path)) { Write-ErrorMsg "Export not found: '$Source' (a file, or a name under $global:BaseDir\etc\exports)"; return $false }
    Write-Section "Import: $(Split-Path -Leaf $path)$(if ($Replace) { ' (replace)' })$(if ($DryRun) { ' (DRY RUN)' })"
    $plan = Get-ImportPlan -ExportPath $path
    if ($Replace) {
        $exportName = [IO.Path]::GetFileNameWithoutExtension($path)
        $known = @('main', 'extras', 'versions', 'java', 'nerd-fonts', 'nirsoft', 'php', 'games', 'sysinternals', 'nonportable')
        $bucketLines = @(Read-PackageListBuckets -Path $path | Where-Object { $known -notcontains $_.Name } | ForEach-Object { "# bucket $($_.Name) $($_.Url)" })
        Write-Info "$($plan.Imported.Count) packages in the export; the host list will contain exactly these"
        if (Test-Path $plan.Target) {
            $current = @(Read-PackageList -Path $plan.Target -Silent)
            $dropped = @($current | Where-Object { $plan.Imported -notcontains $_ })
            foreach ($d in $dropped) { Write-Host "  - $d (no longer listed)" -ForegroundColor Yellow }
        }
        foreach ($m in $plan.Missing) { Write-Host "  + $m" -ForegroundColor White }
        if ($DryRun) { Write-Info "DRY RUN: nothing written; target would be $($plan.Target)"; return $true }
        if (Test-Path $plan.Target) {
            $backup = "$($plan.Target).$(Get-Date -Format 'yyyyMMdd_HHmmss').bak"
            Copy-Item $plan.Target $backup -Force
            Write-Host "[OK] Previous list kept as $backup" -ForegroundColor Gray
        }
        $lines = @("# $(Split-Path -Leaf $plan.Target): package list of this host, written by --import=$exportName --replace on $(Get-Date -Format 'yyyy-MM-dd HH:mm').", "# It replaces default.txt on this machine and is never touched by --update.", "")
        $lines += $bucketLines
        $lines += $plan.Imported
        [IO.File]::WriteAllText($plan.Target, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
        Write-Success "Wrote $($plan.Target) with $($plan.Imported.Count) packages"
        Write-Info "Next: $global:ScoopBootScript --list-packages to review, then --user-install to install them"
        return $true
    }
    Write-Info "$($plan.Imported.Count) packages in the export, $($plan.Missing.Count) not in this machine's list"
    foreach ($b in $plan.Buckets) { Write-Host "  bucket $($b.Name) $($b.Url)" -ForegroundColor Gray }
    foreach ($m in $plan.Missing) { Write-Host "  $m" -ForegroundColor White }
    if ($plan.Missing.Count -eq 0) { Write-Success "Nothing to import; the list already has everything"; return $true }
    if ($DryRun) { Write-Info "DRY RUN: nothing written; target would be $($plan.Target)"; return $true }
    if ($plan.CreateFromDefault) {
        $defaultFile = Join-Path $global:PackagesDir 'default.txt'
        $header = "# $(Split-Path -Leaf $plan.Target): package list of this host, created from default.txt by --import on $(Get-Date -Format 'yyyy-MM-dd HH:mm').`n# It replaces default.txt on this machine and is never touched by --update.`n`n"
        [IO.File]::WriteAllText($plan.Target, $header + (Get-Content -Path $defaultFile -Raw), (New-Object Text.UTF8Encoding($false)))
        Write-Success "Created $($plan.Target) from default.txt"
    } elseif (-not (Test-Path $plan.Target)) {
        [IO.File]::WriteAllText($plan.Target, "# $(Split-Path -Leaf $plan.Target): package list of this host`n", (New-Object Text.UTF8Encoding($false)))
        Write-Success "Created $($plan.Target)"
    }
    $block = @("", "# import $(Get-Date -Format 'yyyy-MM-dd HH:mm') from $([IO.Path]::GetFileNameWithoutExtension($path)) ($($plan.Missing.Count) of $($plan.Imported.Count) packages were missing)")
    foreach ($b in $plan.Buckets) { $block += "# bucket $($b.Name) $($b.Url)" }
    $block += $plan.Missing
    $existing = Get-Content -Path $plan.Target -Raw
    if ($existing -and -not $existing.EndsWith("`n")) { $existing += "`n" }
    if ($existing.EndsWith("`n`n")) { $block = @($block | Select-Object -Skip 1) }
    [IO.File]::WriteAllText($plan.Target, $existing + (($block -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
    Write-Success "Added $($plan.Missing.Count) packages to $($plan.Target)"
    Write-Info "Next: $global:ScoopBootScript --list-packages to review, then --user-install to install them"
    return $true
}

# ============================================================================
# INSTALLATION (formerly scoop-complete-install.ps1)
# ============================================================================

# those packages so that -ListPackages can show them and the self-check can warn
# about a handler whose package is missing from the list.
# Installed by the bootstrap (Step 1) before any list is read; never listed in a package file
$global:BootstrapPackages = @('7zip', 'git', 'aria2', 'sudo', 'innounp', 'dark', 'lessmsi', 'wget', 'cacert')

# ----------------------------------------------------------------------------
# Post-install handlers: one entry per package that needs more than "scoop install".
# Step 4 of --user-install runs them in this order for every package that is in the
# list or already on disk; --list-packages shows the Description next to the package.
# A handler receives the Scoop root and the package name and returns the failures it
# wants reported (strings), nothing when all went well. Optional = $true: the package
# may be absent from default.txt without a warning (post-install for an opt-in tool).
# ----------------------------------------------------------------------------
$global:PackageHandlers = @(
    @{ Name = 'temurin25-jdk';     Handler = 'Invoke-JavaDefaultHandler'; Description = 'scoop reset (default Java)' }
    @{ Name = 'vcredist2022';      Handler = 'Invoke-VcRuntimeHandler';   Description = 'skipped when the VC++ runtime is present; runtime verified' }
    @{ Name = 'msys2';             Handler = 'Invoke-GccHandler';         Description = 'pacman -Syu, GCC (UCRT64), compile-and-run smoke test' }
    @{ Name = 'nmap';              Handler = 'Invoke-NcatShimHandler';    Description = 'shims nc and netcat -> ncat.exe' }
    @{ Name = '7zip';              Handler = 'Invoke-RegImportHandler';   Description = 'reg import install-context.reg';  Arguments = @{ File = 'install-context.reg' } }
    @{ Name = 'notepadplusplus';   Handler = 'Invoke-RegImportHandler';   Description = 'reg import install-context.reg';  Arguments = @{ File = 'install-context.reg' } }
    @{ Name = 'vscode';            Handler = 'Invoke-RegImportHandler';   Description = 'reg import install-context.reg';  Arguments = @{ File = 'install-context.reg' } }
    @{ Name = 'git';               Handler = 'Invoke-RegImportHandler';   Description = 'reg import install-context.reg';  Arguments = @{ File = 'install-context.reg' } }
    @{ Name = 'python314';         Handler = 'Invoke-RegImportHandler';   Description = 'reg import install-pep-514.reg';  Arguments = @{ File = 'install-pep-514.reg' } }
    @{ Name = 'jetbrains-toolbox'; Handler = 'Invoke-TrayAppHandler';     Description = 'started (tray)';                   Arguments = @{ Exe = 'jetbrains-toolbox.exe'; Process = 'jetbrains-toolbox'; Title = 'JetBrains Toolbox' } }
    @{ Name = 'greenshot';         Handler = 'Invoke-TrayAppHandler';     Description = 'started (tray)';                   Arguments = @{ Exe = 'Greenshot.exe'; Process = 'Greenshot'; Title = 'Greenshot' } }
)
$global:VcRuntimeKey = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'

function New-HandlerFailure {
    <#
    .SYNOPSIS
        A failure a handler reports; typed, so that stray pipeline output of the tools it runs (pacman, scoop) is told apart and dropped.
    #>
    param([string]$Text)
    return [pscustomobject]@{ PSTypeName = 'ScoopBoot.Failure'; Text = $Text }
}

function Get-PackageHandler {
    <#
    .SYNOPSIS
        The handler entry of a package, or $null.
    #>
    param([string]$Name)
    foreach ($entry in $global:PackageHandlers) { if ($entry.Name -eq $Name) { return $entry } }
    return $null
}

function Invoke-JavaDefaultHandler {
    param([string]$ScoopDir, [string]$Package, [hashtable]$Arguments)
    if (-not (Test-Path "$ScoopDir\apps\$Package\current\bin\java.exe")) {
        Write-Host "[WARN] $Package is not installed, default Java not set" -ForegroundColor Yellow
        return @()
    }
    Write-Host "[INFO] Setting default Java to $Package..." -ForegroundColor Gray
    scoop reset $Package 2>&1 | Out-Null
    Write-Host "[OK] Default Java set to $Package" -ForegroundColor Green
    return @()
}

function Invoke-VcRuntimeHandler {
    # Verifies the result of the vcredist2022 post_install (needs elevation); the
    # install itself is skipped in Step 3 when the runtime is already present
    param([string]$ScoopDir, [string]$Package, [hashtable]$Arguments)
    $vcRuntime = Get-ItemProperty $global:VcRuntimeKey -ErrorAction SilentlyContinue
    if ($vcRuntime -and $vcRuntime.Installed -eq 1) {
        Write-Host "[OK] VC++ runtime installed ($($vcRuntime.Version))" -ForegroundColor Green
        $vcredistInstaller = Get-ChildItem "$ScoopDir\apps\vcredist2022\current" -Filter "VC_redist*.exe" -ErrorAction SilentlyContinue
        if ($vcredistInstaller) {
            Remove-Item $vcredistInstaller.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] vcredist2022 installer removed (libraries remain)" -ForegroundColor Gray
        }
        return @()
    }
    Write-Host "[WARN] VC++ runtime not installed (vcredist2022 post_install needs elevation, UAC was denied?)" -ForegroundColor Yellow
    Write-Host "       Run in an Administrator PowerShell:" -ForegroundColor Gray
    Write-Host "       Get-ChildItem $ScoopDir\cache\vcredist2022* | ForEach-Object { & `$_.FullName /install /quiet /norestart }" -ForegroundColor Gray
    return (New-HandlerFailure 'vcredist2022 (runtime)')
}

function Invoke-GccHandler {
    param([string]$ScoopDir, [string]$Package, [hashtable]$Arguments)
    $failed = @()
    if (-not (Test-Path "$ScoopDir\apps\msys2\current")) {
        Write-Host "[WARN] MSYS2 not found, skipping GCC installation" -ForegroundColor Yellow
        return $failed
    }
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
            $failed += New-HandlerFailure 'gcc (compile test)'
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
                $failed += New-HandlerFailure 'gcc (running built exe blocked by ASR)'
            }
        }
        Remove-Item $ccTestDir -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "[WARN] GCC installation failed (gcc.exe not found in ucrt64)" -ForegroundColor Yellow
        $failed += New-HandlerFailure 'msys2 gcc (ucrt64)'
        Write-Host ""
        Write-Host "Manual installation steps:" -ForegroundColor Yellow
        Write-Host "  1. Open UCRT64 terminal: $ScoopDir\apps\msys2\current\ucrt64.exe" -ForegroundColor White
        Write-Host "  2. Run: pacman -Syu" -ForegroundColor White
        Write-Host "  3. Run: pacman -S mingw-w64-ucrt-x86_64-gcc" -ForegroundColor White
        Write-Host ""
        Write-Host "NOTE: Use ucrt64.exe (modern), NOT msys2.exe (legacy)" -ForegroundColor Yellow
    }
    return $failed
}

function Invoke-NcatShimHandler {
    # netcat aliases: the netcat package is blocked by Windows Defender (PUA), so nc and
    # netcat point to ncat from nmap. "scoop shim add" re-adds shims to the User PATH,
    # which Step 5 cleans up again; that is why handlers run before Step 5.
    param([string]$ScoopDir, [string]$Package, [hashtable]$Arguments)
    $ncat = "$ScoopDir\apps\nmap\current\ncat.exe"
    if (-not (Test-Path $ncat)) {
        Write-Host "[WARN] nmap not found, skipping nc/netcat shims" -ForegroundColor Yellow
        return @()
    }
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
    return @()
}

function Invoke-RegImportHandler {
    param([string]$ScoopDir, [string]$Package, [hashtable]$Arguments)
    $regPath = "$ScoopDir\apps\$Package\current\$($Arguments.File)"
    if (Test-Path $regPath) {
        Start-Process reg -ArgumentList "import `"$regPath`"" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        Write-Host "[OK] Imported: $Package ($($Arguments.File))" -ForegroundColor Green
    } else {
        Write-Host "[SKIP] $Package has no $($Arguments.File)" -ForegroundColor DarkGray
    }
    return @()
}

function Invoke-TrayAppHandler {
    param([string]$ScoopDir, [string]$Package, [hashtable]$Arguments)
    $exePath = "$ScoopDir\apps\$Package\current\$($Arguments.Exe)"
    if (-not (Test-Path $exePath)) { return @() }
    if (Get-Process -Name $Arguments.Process -ErrorAction SilentlyContinue) {
        Write-Host "[OK] Already running: $($Arguments.Title)" -ForegroundColor Gray
    } else {
        Start-Process -FilePath $exePath -ErrorAction SilentlyContinue
        Write-Host "[OK] Started: $($Arguments.Title)" -ForegroundColor Green
    }
    return @()
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

# ============================================================================
# WSL: the Debian distribution next to the Scoop tools (--wsl-install, --wsl-setup)
# ============================================================================

function ConvertTo-WslPath {
    <#
    .SYNOPSIS
        Windows path to the path WSL mounts it under: C:\usr\etc -> /mnt/c/usr/etc.
    .DESCRIPTION
        A string conversion, no wslpath call, so it runs in the self-tests on every
        platform. The drive letter becomes lower case, backslashes become slashes. A
        path without drive letter (UNC, relative) returns $null: WSL does not mount it
        under /mnt.
    #>
    param([string]$Path)
    if ($Path -match '^([A-Za-z]):[\\/]?(.*)$') {
        $rest = $Matches[2] -replace '\\', '/'
        return ("/mnt/$($Matches[1].ToLower())/$rest").TrimEnd('/')
    }
    return $null
}

function Get-DebianPackageListFile {
    <#
    .SYNOPSIS
        The apt package list in use: etc\packages\<host>.debian.txt when it exists,
        otherwise the delivered etc\packages\debian.txt.
    #>
    $dir = Join-Path $global:BaseDir 'etc\packages'
    $hostFile = Join-Path $dir "$(Get-Hostname).debian.txt"
    if (Test-Path $hostFile) { return $hostFile }
    return (Join-Path $dir 'debian.txt')
}

function Read-DebianPackageList {
    <#
    .SYNOPSIS
        Package names of an apt list: comments and blank lines removed, duplicates
        dropped, order kept. The same rules as etc\wsl\debian-setup.sh.
    #>
    param([string]$Path)
    $seen = @{}
    $names = @()
    foreach ($line in @(Get-Content -Path $Path -ErrorAction Stop)) {
        $name = ($line -replace '#.*$', '') -replace '\s', ''
        if ($name -and -not $seen.ContainsKey($name)) {
            $seen[$name] = $true
            $names += $name
        }
    }
    return $names
}

function ConvertFrom-WslList {
    <#
    .SYNOPSIS
        Distribution names from the text of "wsl --list --quiet": one per line. Blank
        lines and messages (they contain spaces, a distribution name does not, e.g.
        "Windows Subsystem for Linux has no installed distributions.") are dropped.
    #>
    param([string]$Text)
    $names = @()
    foreach ($line in ($Text -split "`r?`n")) {
        $t = $line.Trim()
        if ($t -and $t -notmatch '\s') { $names += $t }
    }
    return $names
}

function Get-WslDistributions {
    <#
    .SYNOPSIS
        Names of the installed WSL distributions; empty when wsl.exe is missing.
        wsl.exe writes UTF-16 (see Test-WSL2Installed), read it as Unicode.
    #>
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { return @() }
    $previousEncoding = [Console]::OutputEncoding
    $raw = ''
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        # Windows PowerShell 5.1 turns the first stderr line of a native command into a
        # terminating error when it is redirected under a Stop preference; without a
        # distribution wsl.exe writes its message there. Caught: no names is the answer.
        $raw = (wsl.exe --list --quiet 2>&1 | Out-String) -replace "`0", ''
    } catch {
        $raw = "$($_.Exception.Message)"
    } finally {
        [Console]::OutputEncoding = $previousEncoding
    }
    return @(ConvertFrom-WslList -Text $raw)
}

function Invoke-WslInstall {
    <#
    .SYNOPSIS
        WSL and a distribution (default Debian), installed but not started (--wsl-install).
    .DESCRIPTION
        Administrator. Without a usable WSL 2: wsl --install --no-distribution; a
        restart of Windows may follow, then --wsl-install again. With WSL and without
        the distribution: wsl --install -d <name> --no-launch. The first start (Linux
        user name and password) is left to the user: wsl -d <name>. --dry-run prints
        the commands, runs none and needs no Administrator.
        On an Azure Virtual Desktop WSL 2 needs a VM size with nested virtualization.
    #>
    param(
        [string]$Distro = 'Debian',
        [bool]$DryRun = $false
    )
    Write-Section "WSL: $Distro"
    if (-not $DryRun -and -not (Test-AdminRights)) {
        Write-ErrorMsg "--wsl-install needs an Administrator shell (--dry-run works without)"
        return $false
    }

    if (-not (Test-WSL2Installed)) {
        if ($DryRun) {
            Write-DryRun "wsl.exe --install --no-distribution   (restart Windows, then --wsl-install again)"
            Write-DryRun "wsl.exe --install -d $Distro --no-launch"
            return $true
        }
        # Out-Host: inside a function the output would become part of the return value
        & wsl.exe --install --no-distribution | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorMsg "wsl --install failed (exit $LASTEXITCODE); on an AVD the VM size must support nested virtualization"
            return $false
        }
        Write-Warning "WSL installed: restart Windows, then run scoop-boot.ps1 --wsl-install again for $Distro"
        return $true
    }

    if (@(Get-WslDistributions) -contains $Distro) {
        Write-Success "$Distro is installed (wsl -d $Distro); next: scoop-boot.ps1 --wsl-setup"
        return $true
    }
    if ($DryRun) {
        Write-DryRun "wsl.exe --install -d $Distro --no-launch"
        return $true
    }
    & wsl.exe --install -d $Distro --no-launch | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorMsg "wsl --install -d $Distro failed (exit $LASTEXITCODE)"
        return $false
    }
    Write-Success "$Distro installed. First start (Linux user and password): wsl -d $Distro; then: scoop-boot.ps1 --wsl-setup"
    return $true
}

function Invoke-WslSetup {
    <#
    .SYNOPSIS
        Runs etc\wsl\debian-setup.sh inside the distribution (--wsl-setup).
    .DESCRIPTION
        Normal shell. The script and the package list are read from the Scoop root
        under /mnt/<drive>; nothing is copied into the distribution. apt-get runs
        through sudo inside Debian, which asks for the Linux password. --dry-run is
        passed on: apt-get resolves every package in simulation mode and nothing is
        installed. Without the distribution, --dry-run prints the plan.
        On an existing distribution (also Ubuntu, --distro=NAME) it only adds: missing
        packages with apt-get --no-remove, no upgrade, no autoremove; files already
        in ~/.local/bin and an existing claude are left as they are.
    #>
    param(
        [string]$Distro = 'Debian',
        [bool]$DryRun = $false,
        [bool]$NoClaude = $false
    )
    Write-Section "WSL setup: $Distro"
    $setupScript = Join-Path $global:BaseDir 'etc\wsl\debian-setup.sh'
    $listFile = Get-DebianPackageListFile
    foreach ($f in @($setupScript, $listFile)) {
        if (-not (Test-Path $f)) {
            Write-ErrorMsg "$f is missing (scoop-boot.ps1 --update delivers it)"
            return $false
        }
    }
    $packages = @(Read-DebianPackageList -Path $listFile)
    Write-Info "Package list $listFile ($($packages.Count) packages)"

    $wslScript = ConvertTo-WslPath -Path $setupScript
    $wslList = ConvertTo-WslPath -Path $listFile
    if (-not $wslScript -or -not $wslList) {
        Write-ErrorMsg "$global:BaseDir has no drive letter; WSL cannot read it under /mnt"
        return $false
    }
    $shArgs = @($wslScript, '--packages', $wslList)
    if ($DryRun) { $shArgs += '--dry-run' }
    if ($NoClaude) { $shArgs += '--no-claude' }

    $installed = @(Get-WslDistributions)
    if (-not ($installed -contains $Distro)) {
        if ($installed.Count -gt 0) {
            Write-Warning "$Distro is not installed; installed: $($installed -join ', '). For one of them: --wsl-setup --distro=NAME"
        }
        if ($DryRun) {
            Write-DryRun "$Distro is not installed: scoop-boot.ps1 --wsl-install first"
            Write-DryRun "wsl.exe -d $Distro -- bash $($shArgs -join ' ')"
            return $true
        }
        Write-ErrorMsg "$Distro is not installed: run scoop-boot.ps1 --wsl-install (Administrator) first"
        return $false
    }

    # Out-Host: inside a function the output would become part of the return value
    & wsl.exe -d $Distro -- bash @shArgs | Out-Host
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        Write-ErrorMsg "debian-setup.sh ended with exit $code"
        return $false
    }
    return $true
}

# ============================================================================
# PROFILES: composing this machine's files from etc\profiles (--profile)
# ============================================================================

$global:ProfileFragmentFiles = @('packages.txt', 'system.env', 'user.env', 'debian.txt')

function Get-ProfileCatalog {
    <#
    .SYNOPSIS
        Reads etc\profiles\profiles.conf: Singles (in catalog order: Name, Description,
        Dir), Virtual (name -> member names), VirtualOrder, Errors.
    .DESCRIPTION
        "profile NAME description" lines are the single profiles, in the order --profile
        composes them; "NAME=a,b,c" lines are virtual profiles. Every single profile
        needs a directory with at least one of packages.txt, system.env, user.env,
        debian.txt; every member of a virtual profile must be known. Problems are
        collected in Errors, the catalog is still returned.
    #>
    param([string]$Dir = $global:ProfilesDir)
    $catalog = @{ Path = (Join-Path $Dir 'profiles.conf'); Singles = @(); Virtual = @{}; VirtualOrder = @(); Errors = @() }
    if (-not (Test-Path $catalog.Path)) {
        $catalog.Errors += "$($catalog.Path) is missing (scoop-boot.ps1 --update delivers it)"
        return $catalog
    }
    $n = 0
    foreach ($raw in @(Get-Content -Path $catalog.Path)) {
        $n++
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }
        if ($line -match '^profile\s+([a-z0-9][a-z0-9+_-]*)(\s+(.*))?$') {
            $name = $Matches[1]
            $description = if ($Matches.Count -gt 3) { $Matches[3].Trim() } else { '' }
            if (@($catalog.Singles | Where-Object { $_.Name -eq $name }).Count -gt 0) { $catalog.Errors += "line ${n}: profile '$name' is listed twice"; continue }
            $catalog.Singles += [pscustomobject]@{ Name = $name; Description = $description; Dir = (Join-Path $Dir $name) }
            continue
        }
        if ($line -match '^([a-z0-9][a-z0-9+_-]*)\s*=\s*(.+)$') {
            $name = $Matches[1]
            $members = @($Matches[2] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            if ($catalog.Virtual.ContainsKey($name)) { $catalog.Errors += "line ${n}: virtual profile '$name' is defined twice"; continue }
            $catalog.Virtual[$name] = $members
            $catalog.VirtualOrder += $name
            continue
        }
        $catalog.Errors += "line ${n}: not a profile line: '$raw'"
    }
    if ($catalog.Singles.Count -eq 0 -or $catalog.Singles[0].Name -ne 'base') { $catalog.Errors += "the first profile line must be 'base'; it is always composed first" }
    foreach ($single in $catalog.Singles) {
        if ($catalog.Virtual.ContainsKey($single.Name)) { $catalog.Errors += "'$($single.Name)' is both a single and a virtual profile" }
        if (-not (Test-Path $single.Dir)) { $catalog.Errors += "profile '$($single.Name)': directory $($single.Dir) is missing"; continue }
        $present = @($global:ProfileFragmentFiles | Where-Object { Test-Path (Join-Path $single.Dir $_) })
        if ($present.Count -eq 0) { $catalog.Errors += "profile '$($single.Name)': none of $($global:ProfileFragmentFiles -join ', ') in $($single.Dir)" }
    }
    foreach ($virtual in $catalog.VirtualOrder) {
        foreach ($member in $catalog.Virtual[$virtual]) {
            if (-not $catalog.Virtual.ContainsKey($member) -and @($catalog.Singles | Where-Object { $_.Name -eq $member }).Count -eq 0) {
                $catalog.Errors += "virtual profile '$virtual' names an unknown profile '$member'"
            }
        }
    }
    return $catalog
}

function Resolve-Profiles {
    <#
    .SYNOPSIS
        Expands "NAME,NAME,..." (single or virtual profiles, any order) to the single
        profiles in catalog order, base always first. Returns Names and Errors.
    #>
    param(
        [string]$Names,
        [hashtable]$Catalog = $null
    )
    if ($null -eq $Catalog) { $Catalog = Get-ProfileCatalog }
    $result = @{ Names = @(); Errors = @($Catalog.Errors) }
    $requested = @("$Names" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($requested.Count -eq 0) { $result.Errors += "no profile named (--profile=NAME,NAME,...; scoop-boot.ps1 --list-profiles shows them)"; return $result }
    $selected = @{}
    function Select-ProfileMember {
        param([string]$Name, [string[]]$Trail)
        if ($Trail -contains $Name) { $result.Errors += "virtual profiles refer to each other in a circle: $(($Trail + $Name) -join ' -> ')"; return }
        if ($Catalog.Virtual.ContainsKey($Name)) {
            foreach ($member in $Catalog.Virtual[$Name]) { Select-ProfileMember -Name $member -Trail ($Trail + $Name) }
            return
        }
        if (@($Catalog.Singles | Where-Object { $_.Name -eq $Name }).Count -gt 0) { $selected[$Name] = $true; return }
        $result.Errors += "unknown profile '$Name' (scoop-boot.ps1 --list-profiles shows the names)"
    }
    foreach ($name in $requested) { Select-ProfileMember -Name $name -Trail @() }
    $selected['base'] = $true
    $result.Names = @($Catalog.Singles | Where-Object { $selected.ContainsKey($_.Name) } | ForEach-Object { $_.Name })
    return $result
}

function Get-ProfileFragmentText {
    <#
    .SYNOPSIS
        Content of one fragment file of a profile (packages.txt, system.env, user.env,
        debian.txt), LF line endings, no BOM; $null when the profile has no such file.
    #>
    param([string]$Name, [string]$File, [string]$Dir = $global:ProfilesDir)
    $path = Join-Path (Join-Path $Dir $Name) $File
    if (-not (Test-Path $path)) { return $null }
    $text = [IO.File]::ReadAllText($path, (New-Object Text.UTF8Encoding($false)))
    return ($text -replace "`r`n", "`n").TrimStart([char]0xFEFF).TrimEnd("`n")
}

function New-ProfilePackageListText {
    <#
    .SYNOPSIS
        The package list (packages.txt) or apt list (debian.txt) composed from the
        profiles: header, "# bucket" lines, then one section per profile. A package
        that an earlier profile already lists is left out (Duplicates names them).
    .OUTPUTS
        $null when no profile has the file; otherwise Text, Packages (in order), Duplicates.
    #>
    param(
        [string[]]$Profiles,
        [string]$File = 'packages.txt',
        [string]$FileName,
        [string]$Command,
        [string]$Dir = $global:ProfilesDir
    )
    $sections = @()
    foreach ($profile in $Profiles) {
        $text = Get-ProfileFragmentText -Name $profile -File $File -Dir $Dir
        if ($null -ne $text) { $sections += [pscustomobject]@{ Name = $profile; Text = $text } }
    }
    if ($sections.Count -eq 0) { return $null }
    $what = if ($File -eq 'debian.txt') { 'apt package list for --wsl-setup (replaces debian.txt)' } else { 'package list (replaces default.txt)' }
    $lines = @(
        "# ${FileName}: $what of this host, composed by $Command on $(Get-Date -Format 'yyyy-MM-dd HH:mm').",
        "# Profiles: $($Profiles -join ', ')",
        "# Edit freely, --update never touches this file. To compose it again from other profiles:",
        "# scoop-boot.ps1 --profile=NAMES --force (the old file is kept as .bak).",
        ''
    )
    $seen = @{}
    $packages = @()
    $duplicates = @()
    $buckets = @()
    foreach ($section in $sections) {
        foreach ($line in ($section.Text -split "`n")) {
            if ($line -match '^\s*#\s*bucket\s+([A-Za-z0-9._-]+)\s+(\S+)\s*$') {
                if ($buckets -notcontains $Matches[1]) { $buckets += $Matches[1]; $lines += $line.Trim() }
            }
        }
    }
    if ($buckets.Count -gt 0) { $lines += '' }
    foreach ($section in $sections) {
        $lines += "# ---- profile $($section.Name) ----"
        foreach ($line in ($section.Text -split "`n")) {
            if ($line -match '^\s*#\s*bucket\s+') { continue }
            $name = ($line -replace '#.*$', '').Trim()
            if ($name) {
                $key = $name.ToLower()
                if ($seen.ContainsKey($key)) { $duplicates += "$name (already in $($seen[$key]))"; continue }
                $seen[$key] = $section.Name
                $packages += $name
            }
            $lines += $line
        }
        $lines += ''
    }
    return [pscustomobject]@{ Text = (($lines -join "`n").TrimEnd("`n") + "`n"); Packages = $packages; Duplicates = $duplicates }
}

function New-ProfileEnvironmentText {
    <#
    .SYNOPSIS
        The system.<host>.<user>.env or user.<host>.<user>.env composed from the
        profiles: header, one section per profile that has the fragment, and for the
        Machine scope etc\profiles\system.footer.env (CUSTOM, CORE PATHS, caches).
        USR is set to the Scoop root of this machine.
    .OUTPUTS
        $null when no profile has the fragment; otherwise Text and Operations (count of
        non-comment lines).
    #>
    param(
        [string[]]$Profiles,
        [ValidateSet('system', 'user')][string]$Scope,
        [string]$HostName,
        [string]$UserName,
        [string]$Root,
        [string]$Command,
        [string]$Dir = $global:ProfilesDir
    )
    $sections = @()
    foreach ($profile in $Profiles) {
        $text = Get-ProfileFragmentText -Name $profile -File "$Scope.env" -Dir $Dir
        if ($null -ne $text) { $sections += [pscustomobject]@{ Name = $profile; Text = $text } }
    }
    if ($sections.Count -eq 0) { return $null }
    $fileName = "$Scope.$HostName.$UserName.env"
    $title = if ($Scope -eq 'system') { 'System Environment Configuration' } else { 'User Environment Configuration' }
    $scopeLine = if ($Scope -eq 'system') { 'Scope: Machine (requires admin); applied by scoop-boot.ps1 --admin-setenv' } else { 'Scope: User (no admin needed); applied by --clean-user-scope, --admin-setenv, --user-install and the scoop wrapper' }
    $lines = @(
        '# ============================================================================',
        "# $title",
        "# File: $fileName",
        "# Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm') by $Command",
        "# Profiles: $($Profiles -join ', ')",
        '# ============================================================================',
        "# $scopeLine",
        "# SCOOP: $Root",
        "# Hostname: $HostName",
        "# Username: $UserName",
        '#',
        '# Composed from etc\profiles. Edit freely, --update never touches this file.',
        '# To compose it again from other profiles: scoop-boot.ps1 --profile=NAMES --force',
        "# (the old file is kept as .bak), then$(if ($Scope -eq 'system') { ' --admin-setenv' } else { ' --clean-user-scope' }).",
        '# ============================================================================'
    )
    foreach ($section in $sections) {
        $lines += ''
        $lines += "# ---------------------------------------------------------------------------- profile $($section.Name)"
        $lines += ($section.Text -split "`n")
    }
    if ($Scope -eq 'system') {
        $footer = Join-Path $Dir 'system.footer.env'
        if (Test-Path $footer) {
            $lines += ''
            $lines += (([IO.File]::ReadAllText($footer, (New-Object Text.UTF8Encoding($false))) -replace "`r`n", "`n").TrimStart([char]0xFEFF).TrimEnd("`n") -split "`n")
        }
    }
    $text = ($lines -join "`n") + "`n"
    if ($Scope -eq 'system') { $text = $text -replace '(?m)^USR=.*$', "USR=$Root" }
    $operations = @($text -split "`n" | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') }).Count
    return [pscustomobject]@{ Text = $text; Operations = $operations }
}

function Set-ScoopBootConfigProfile {
    <#
    .SYNOPSIS
        Writes PROFILE=NAMES into etc\scoop-boot.conf (replacing an earlier PROFILE line);
        the file is created with its defaults when missing.
    #>
    param([string]$Names)
    $config = Get-ScoopBootConfig
    $text = if ($config.Exists) { [IO.File]::ReadAllText($config.Path) } else { Get-ScoopBootConfigDefaultText }
    $text = $text -replace "`r`n", "`n"
    if ($text -match '(?m)^PROFILE=.*$') {
        $text = $text -replace '(?m)^PROFILE=.*$', "PROFILE=$Names"
    } else {
        if ($text -and -not $text.EndsWith("`n")) { $text += "`n" }
        $text += "PROFILE=$Names`n"
    }
    [IO.File]::WriteAllText($config.Path, $text, (New-Object Text.UTF8Encoding($false)))
}

function Show-Profiles {
    <#
    .SYNOPSIS
        Lists the profiles of etc\profiles with their packages (--list-profiles).
    #>
    $catalog = Get-ProfileCatalog
    Write-Section "Profiles in $global:ProfilesDir"
    foreach ($e in $catalog.Errors) { Write-ErrorMsg $e }
    $config = Get-ScoopBootConfig
    if ($config.Profile) { Write-Host "This machine (etc\scoop-boot.conf): PROFILE=$($config.Profile)" -ForegroundColor Cyan; Write-Host '' }
    foreach ($single in $catalog.Singles) {
        $files = @($global:ProfileFragmentFiles | Where-Object { Test-Path (Join-Path $single.Dir $_) })
        Write-Host ("  {0,-12} {1}" -f $single.Name, $single.Description) -ForegroundColor White
        $packages = @()
        $packagesFile = Join-Path $single.Dir 'packages.txt'
        if (Test-Path $packagesFile) { $packages = @(Read-PackageList -Path $packagesFile -Silent) }
        $debian = @()
        $debianFile = Join-Path $single.Dir 'debian.txt'
        if (Test-Path $debianFile) { $debian = @(Read-DebianPackageList -Path $debianFile) }
        $parts = @()
        if ($packages.Count -gt 0) { $parts += "scoop: $($packages -join ' ')" }
        if ($debian.Count -gt 0) { $parts += "debian: $($debian -join ' ')" }
        if ($files -contains 'system.env') { $parts += 'environment: system' }
        if ($files -contains 'user.env') { $parts += 'environment: user' }
        foreach ($part in $parts) { Write-Host "               $part" -ForegroundColor Gray }
    }
    Write-Host ''
    foreach ($virtual in $catalog.VirtualOrder) {
        $resolved = Resolve-Profiles -Names $virtual -Catalog $catalog
        Write-Host ("  {0,-12} = {1}" -f $virtual, ($catalog.Virtual[$virtual] -join ',')) -ForegroundColor White
        Write-Host "               composes: $($resolved.Names -join ', ')" -ForegroundColor Gray
    }
    Write-Host ''
    Write-Host "Use: scoop-boot.ps1 --profile=NAME,NAME,... (--dry-run shows the files); base is always included" -ForegroundColor Gray
    return ($catalog.Errors.Count -eq 0)
}

function Invoke-Profile {
    <#
    .SYNOPSIS
        Composes this machine's files from profiles (--profile=NAMES): etc\packages\<host>.txt,
        etc\packages\<host>.debian.txt (when a profile has apt packages),
        etc\environments\system.<host>.<user>.env and user.<host>.<user>.env.
    .DESCRIPTION
        An existing file is kept unless -Force (the old one is saved as .bak); with
        -KeepExisting (used by --admin-init) a kept file is not a failure. -DryRun shows
        the files, their packages and environment operations and writes nothing. The
        profile names are recorded as PROFILE= in etc\scoop-boot.conf. Nothing is
        installed or applied: --admin-setenv, --user-install and --wsl-setup follow.
    #>
    param(
        [string]$Names,
        [bool]$DryRun = $false,
        [bool]$Force = $false,
        [bool]$KeepExisting = $false,
        [string]$Command = 'scoop-boot.ps1 --profile'
    )
    Write-Section "Profile: $Names$(if ($DryRun) { ' (DRY RUN)' })"
    $resolved = Resolve-Profiles -Names $Names
    if ($resolved.Errors.Count -gt 0) {
        foreach ($e in $resolved.Errors) { Write-ErrorMsg $e }
        return $false
    }
    $profiles = @($resolved.Names)
    Write-Info "Composed from: $($profiles -join ', ')"
    $hostName = Get-Hostname
    $userName = Get-Username
    $commandText = "$Command=$Names"
    $plan = @()
    $packages = New-ProfilePackageListText -Profiles $profiles -File 'packages.txt' -FileName "$hostName.txt" -Command $commandText
    if ($null -eq $packages) { Write-ErrorMsg "none of the profiles has a packages.txt"; return $false }
    $plan += [pscustomobject]@{ Target = (Join-Path $global:PackagesDir "$hostName.txt"); Text = $packages.Text; What = "$($packages.Packages.Count) packages"; Show = @($packages.Packages -join ' '); Duplicates = $packages.Duplicates }
    $debian = New-ProfilePackageListText -Profiles $profiles -File 'debian.txt' -FileName "$hostName.debian.txt" -Command $commandText
    if ($null -ne $debian) {
        $plan += [pscustomobject]@{ Target = (Join-Path $global:PackagesDir "$hostName.debian.txt"); Text = $debian.Text; What = "$($debian.Packages.Count) apt packages"; Show = @($debian.Packages -join ' '); Duplicates = $debian.Duplicates }
    }
    foreach ($scope in @('system', 'user')) {
        $env = New-ProfileEnvironmentText -Profiles $profiles -Scope $scope -HostName $hostName -UserName $userName -Root $global:BaseDir -Command $commandText
        if ($null -eq $env) { continue }
        $show = @($env.Text -split "`n" | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
        $plan += [pscustomobject]@{ Target = (Join-Path $global:EnvDir "$scope.$hostName.$userName.env"); Text = $env.Text; What = "$($env.Operations) environment lines"; Show = $show; Duplicates = @() }
    }
    $written = 0
    $kept = 0
    foreach ($item in $plan) {
        $exists = Test-Path $item.Target
        foreach ($d in $item.Duplicates) { Write-Host "  (left out: $d)" -ForegroundColor Gray }
        if ($exists -and -not $Force) {
            if ($KeepExisting) {
                Write-Host "[OK] Exists, kept: $($item.Target)" -ForegroundColor Gray
            } else {
                Write-Warning "$($item.Target) exists, kept ($($item.What) not written; --force replaces it and keeps the old file as .bak)"
            }
            $kept++
            continue
        }
        if ($DryRun) {
            Write-DryRun "Write $($item.Target) ($($item.What))$(if ($exists) { ', the existing file saved as .bak' })"
            foreach ($line in $item.Show) { Write-Host "        $line" -ForegroundColor Gray }
            continue
        }
        $dir = Split-Path -Parent $item.Target
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if ($exists) { Copy-Item $item.Target "$($item.Target).bak" -Force }
        [IO.File]::WriteAllText($item.Target, $item.Text, (New-Object Text.UTF8Encoding($false)))
        Write-Success "Written: $($item.Target) ($($item.What))$(if ($exists) { ', previous file kept as .bak' })"
        $written++
    }
    if ($DryRun) {
        Write-Info "DRY RUN: nothing written"
        return $true
    }
    Set-ScoopBootConfigProfile -Names $Names
    Write-Host "[OK] PROFILE=$Names recorded in etc\scoop-boot.conf" -ForegroundColor Gray
    if ($written -gt 0 -and -not $KeepExisting) {
        $script = Join-Path $global:ScriptRoot 'scoop-boot.ps1'
        Write-Info "Next: $script --admin-setenv (Administrator), then --user-install$(if ($null -ne $debian) { ' and --wsl-setup' })"
    }
    if ($KeepExisting) { return $true }
    return ($kept -eq 0)
}

function Set-DevelopmentEnvironment {
    <#
    .SYNOPSIS
        Phase 1 (Administrator): TMP/TEMP, environment files at Machine scope. Called by --admin-setenv.
    #>
    # Strict mode version 1 (undefined variables), see Install-ScoopTools
    Set-StrictMode -Version 1
    $ErrorActionPreference = 'Continue'
    $ScoopDir = $global:BaseDir
    Write-Host ""
    Write-Host "=== Phase 1: Environment Setup (Administrator) ===" -ForegroundColor Cyan
    Write-Host ""

    # Check admin rights (Test-AdminRights: platform-safe, true in fake mode)
    $isAdmin = Test-AdminRights

    if (-not $isAdmin) {
        Write-Host "[ERROR] This phase requires administrator privileges!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Run PowerShell as Administrator:" -ForegroundColor Yellow
        Write-Host "  Right-click PowerShell -> Run as Administrator" -ForegroundColor White
        Write-Host ""
        return (New-RunResult -Command 'admin-setenv' -Ok $false)
    }

    Write-Host "[OK] Running with administrator privileges" -ForegroundColor Green
    Write-Host ""

    # TMP and TEMP come from the environment file (Machine scope); the directory they
    # point to is created after the files are applied, see below. User-level TMP/TEMP
    # are deliberately not set: --clean-user-scope removes User overrides of managed names.

    # Explain the directory layout to whoever looks into the Scoop root later
    $dirReadme = "$ScoopDir\README_scoop_dir_warnings.md"
    @"
# $ScoopDir - read before putting anything here

This directory is the base of a Scoop-managed developer environment set up by
scoop-boot (https://github.com/stotz/scoop-boot). Scoop is NOT the owner of
$ScoopDir; it owns only these subdirectories:

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
- Other software may live in its own directory directly under $ScoopDir (for
  example $ScoopDir\PostgreSQL). scoop-boot leaves it alone, but its PATH entries
  and variables are then yours to maintain, not the .env file's.
- Do not set JAVA_HOME, PATH and friends by hand in the Windows dialog. Edit
  etc\environments\system.<hostname>.<username>.env and run
  scoop-boot.ps1 --admin-setenv (as Administrator). After
  scoop update or scoop install, run scoop-boot.ps1 --clean-user-scope.
- Keep anything you cannot rebuild out of $ScoopDir or back it up elsewhere;
  $ScoopDir\backups holds environment snapshots only, not application data.
"@ | Set-Content -Path $dirReadme -Encoding ASCII
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
        Write-Host "    $ScoopDir\bin\scoop-boot.ps1 --admin-init" -ForegroundColor Gray
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
        Write-Host "  $ScoopDir\bin\scoop-boot.ps1 --admin-setenv" -ForegroundColor White
        Write-Host ""
        return (New-RunResult -Command 'admin-setenv' -Ok $false)
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
        Write-Host "  $ScoopDir\bin\scoop-boot.ps1 --admin-init" -ForegroundColor Gray
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
        Write-Host "  $ScoopDir\bin\scoop-boot.ps1 --admin-setenv" -ForegroundColor White
        Write-Host ""
        return (New-RunResult -Command 'admin-setenv' -Ok $false)
    }

    Write-Host "[INFO] Found $($validEnvFiles.Count) valid environment file(s):" -ForegroundColor Gray
    foreach ($file in $validEnvFiles) {
        Write-Host "  - $($file.Name)" -ForegroundColor DarkGray
    }
    Write-Host ""

    # Apply environment configuration
    Write-Host "[INFO] Applying environment from .env file(s)..." -ForegroundColor Gray
    $applied = (Get-RunResult -Output @(Invoke-ApplyEnv)).Ok

    if (-not $applied) {
        Write-Host ""
        Write-Host "[ERROR] Failed to apply environment configuration" -ForegroundColor Red
        Write-Host ""
        Write-Host "Troubleshooting:" -ForegroundColor Yellow
        Write-Host "  1. Check file syntax: notepad `"$envDir\system.default.env`"" -ForegroundColor White
        Write-Host "  2. Test with dry-run: .\bin\scoop-boot.ps1 --admin-setenv --dry-run" -ForegroundColor White
        Write-Host "  3. Check status: .\bin\scoop-boot.ps1 --env-status" -ForegroundColor White
        Write-Host ""
        return (New-RunResult -Command 'admin-setenv' -Ok $false)
    }

    # The temporary directory the files set at Machine scope must exist and be
    # writable for everyone; the session takes the new value right away
    foreach ($name in @('TMP', 'TEMP')) {
        $value = Get-RegistryEnvironmentVariable -Name $name -Scope 'Machine'
        if (-not $value) { continue }
        if (Test-ScoopBootFake) { Write-Host "[FAKE] $name=$value not created, session not changed" -ForegroundColor DarkCyan; continue }
        if ($value -match '^[A-Za-z]:\\' -and -not (Test-Path $value)) {
            New-Item -ItemType Directory -Path $value -Force | Out-Null
            icacls $value /grant "Everyone:(OI)(CI)F" /T /Q 2>&1 | Out-Null
            Write-Host "[OK] Created $value ($name) with full permissions" -ForegroundColor Green
        }
        Set-Item -Path "Env:$name" -Value $value
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
    Write-Host "  Run: $ScoopDir\bin\scoop-boot.ps1 --user-install" -ForegroundColor White
    Write-Host ""
    return (New-RunResult -Command 'admin-setenv' -Ok $true)
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
    # Strict mode version 1 (undefined variables) for this function and everything it
    # calls; version 2 and up would also refuse .Count on a single object and a missing
    # property on Scoop's JSON, which this code relies on. Continue: a failing Scoop
    # command or installer is this package's failure, not the end of the run.
    Set-StrictMode -Version 1
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
    # Test-AdminRights is platform-safe; in fake mode the shell counts as a normal one.
    $isAdmin = (-not (Test-ScoopBootFake)) -and (Test-AdminRights)

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
            return (New-RunResult -Command 'user-install' -Ok $true -Data @{ Cancelled = $true })
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

    $wsl2Installed = if (Test-ScoopBootFake) { Write-Host "[FAKE] WSL check skipped" -ForegroundColor DarkCyan; $false } else { Test-WSL2Installed }

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
    # user-scope cleanup after every single package instead of once in Step 5.
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
        Set-RegistryEnvironmentVariable -Name 'SCOOP' -Value $ScoopDir -Scope 'User'
        Set-RegistryEnvironmentVariable -Name 'SCOOP_GLOBAL' -Value "$ScoopDir\global" -Scope 'User'

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
                return (New-RunResult -Command 'user-install' -Ok $false)
            }
        } catch {
            Write-Host "[ERROR] Failed to download/install Scoop!" -ForegroundColor Red
            Write-Host "Error: $_" -ForegroundColor Red
            return (New-RunResult -Command 'user-install' -Ok $false)
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
        return (New-RunResult -Command 'user-install' -Ok $false)
    }

    if (-not (Test-Path "$ScoopDir\apps\git\current\cmd\git.exe")) {
        Write-Host "[FATAL] git could not be installed. Scoop cannot add buckets or install anything without it." -ForegroundColor Red
        Write-Host "        See the bootstrap messages above. If 7z.exe or git.exe were refused by Windows," -ForegroundColor Gray
        Write-Host "        endpoint security blocks newly released binaries (Defender event 1121)." -ForegroundColor Gray
        return (New-RunResult -Command 'user-install' -Ok $false)
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

    # Bootstrap already added main + extras, we add java + versions, plus the
    # "# bucket NAME URL" lines of the package list (written by --import)
    $failedApps = @()
    $installedNow = @()
    $alreadyInstalled = @()
    $skippedApps = @()
    $userScopeChanges = 0
    $additionalBuckets = @(@{ Name = 'java'; Url = '' }, @{ Name = 'versions'; Url = '' })
    $listFileForBuckets = Get-PackageListFile
    if ($listFileForBuckets) {
        foreach ($b in @(Read-PackageListBuckets -Path $listFileForBuckets)) { $additionalBuckets += @{ Name = $b.Name; Url = $b.Url } }
    }
    foreach ($bucket in $additionalBuckets) {
        Write-Host "Adding bucket: $($bucket.Name)" -ForegroundColor Gray
        if (Test-Path "$ScoopDir\buckets\$($bucket.Name)\bucket") {
            Write-Host "[OK] Bucket already exists: $($bucket.Name)" -ForegroundColor Gray
            continue
        }
        if ($bucket.Url) { scoop bucket add $bucket.Name $bucket.Url } else { scoop bucket add $bucket.Name }
        if (Test-Path "$ScoopDir\buckets\$($bucket.Name)\bucket") {
            Write-Host "[OK] Added bucket: $($bucket.Name)" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Bucket not added: $($bucket.Name) (packages from it will fail below)" -ForegroundColor Red
            $failedApps += "bucket $($bucket.Name)"
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
        return (New-RunResult -Command 'user-install' -Ok $false)
    }
    $apps = @(Read-PackageList -Path $packageFile)
    $requestedNames = @($apps | ForEach-Object { Get-ManifestAppName -Package $_ })
    Write-Host "[INFO] Package list: $packageFile ($($apps.Count) packages)" -ForegroundColor Gray
    foreach ($entry in $PackageHandlers) {
        if ($BootstrapPackages -contains $entry.Name) { continue }
        if ($requestedNames -notcontains $entry.Name -and -not (Test-Path "$ScoopDir\apps\$($entry.Name)\current")) {
            Write-Host "[WARN] $($entry.Name) is not in the package list; its post-install step ($($entry.Description)) will not run" -ForegroundColor Yellow
        }
    }
    if ($apps.Count -eq 0) {
        Write-Host "[FATAL] Package list is empty: $packageFile" -ForegroundColor Red
        return (New-RunResult -Command 'user-install' -Ok $false)
    }

    # VC++ 2015-2022 runtime: the vcredist2022 post_install needs elevation.
    # Skip it when the runtime is already present (usual on managed images).
    $vcRuntime = Get-ItemProperty $global:VcRuntimeKey -ErrorAction SilentlyContinue
    if ($vcRuntime -and $vcRuntime.Installed -eq 1 -and $requestedNames -contains 'vcredist2022') {
        Write-Host "[OK] VC++ runtime already present ($($vcRuntime.Version)), skipping vcredist2022" -ForegroundColor Gray
        $skippedApps += @($apps | Where-Object { (Get-ManifestAppName -Package $_) -eq 'vcredist2022' })
        $apps = @($apps | Where-Object { (Get-ManifestAppName -Package $_) -ne 'vcredist2022' })
    }

    # Window title counts through the whole run: the packages, then one step per
    # handler and the user-scope cleanup (the exact total is known after Step 3)
    $titleTotal = $apps.Count + @($PackageHandlers | Where-Object { $requestedNames -contains $_.Name }).Count + 1
    $appIndex = 0
    foreach ($app in $apps) {
        $appIndex++
        Set-ScoopBootTitle -Text "scoop-boot [$appIndex/$titleTotal] $(Get-ManifestAppName -Package $app)"
        $appDir = "$ScoopDir\apps\$(Get-ManifestAppName -Package $app)\current"
        if (Test-Path $appDir) {
            Write-Host "[OK] Already installed: $app" -ForegroundColor Gray
            $alreadyInstalled += $app
            continue
        }
        Write-Host "[INFO] Installing $app..." -ForegroundColor Gray
        # A manifest script may throw (Write-Error under a Stop preference, a failing
        # installer); that is this package's failure, not the end of the run
        try { scoop install $app } catch { Write-Host "[ERROR] $app`: $($_.Exception.Message)" -ForegroundColor Red }
        if (Test-Path $appDir) {
            Write-Host "[OK] Installed: $app" -ForegroundColor Green
            $installedNow += $app
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

    # Handlers run only for packages in the list (or already on disk from an earlier
    # run); a package that is not listed is simply not touched. Order = table order.
    $listed = $requestedNames + $BootstrapPackages + @($PackageHandlers | ForEach-Object { $_.Name } | Where-Object { Test-Path "$ScoopDir\apps\$_\current" })
    $handlerIndex = 0
    $handlersToRun = @($PackageHandlers | Where-Object { $listed -contains $_.Name })
    $titleTotal = $apps.Count + $handlersToRun.Count + 1
    foreach ($entry in $handlersToRun) {
        $handlerIndex++
        Set-ScoopBootTitle -Text "scoop-boot [$($apps.Count + $handlerIndex)/$titleTotal] $($entry.Name)"
        $arguments = if ($entry.ContainsKey('Arguments')) { $entry.Arguments } else { @{} }
        if (Test-ScoopBootFake) {
            # The handlers run real programs (pacman, reg.exe, scoop reset, tray apps)
            Write-Host "[FAKE] $($entry.Name): $($entry.Description) skipped" -ForegroundColor DarkCyan
            continue
        }
        try {
            # Only typed failures count; other pipeline output of the handler (stdout of
            # pacman, scoop) is dropped, as it was when the handlers were inline code
            $handlerFailures = @(& $entry.Handler -ScoopDir $ScoopDir -Package $entry.Name -Arguments $arguments |
                Where-Object { $_ -is [pscustomobject] -and $_.PSObject.TypeNames -contains 'ScoopBoot.Failure' } |
                ForEach-Object { $_.Text })
        } catch {
            Write-Host "[ERROR] Handler for $($entry.Name) failed: $($_.Exception.Message)" -ForegroundColor Red
            $handlerFailures = @("$($entry.Name) (handler)")
        }
        $failedApps += $handlerFailures
    }

    # ============================================================================
    # STEP 5: CLEAN USER SCOPE
    # Scoop wrote JAVA_HOME, GRADLE_USER_HOME, ... and PATH entries into the User
    # scope during Step 3; User values override the Machine values from the .env
    # file. scoop-boot.ps1 --clean-user-scope removes them and applies user.* files.
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Step 5: Cleaning User scope (Scoop overrides, user.* files)..." -ForegroundColor White
    Write-Host ""
    Set-ScoopBootTitle -Text "scoop-boot [$titleTotal/$titleTotal] clean-user-scope"
    $userScopeChanges = [int](@(Invoke-CleanUserScope) | Where-Object { $_ -is [int] } | Select-Object -Last 1)

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
    Write-Host "Packages: $($installedNow.Count) installed, $($alreadyInstalled.Count) already installed, $($skippedApps.Count) skipped, $($failedApps.Count) failed; User scope: $userScopeChanges change(s)" -ForegroundColor Gray
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
    return (New-RunResult -Command 'user-install' -Ok ($failedApps.Count -eq 0) -Data @{ Installed = $installedNow; AlreadyInstalled = $alreadyInstalled; Skipped = $skippedApps; Failed = $failedApps; UserScopeChanges = $userScopeChanges })
}

function Show-PackageList {
    <#
    .SYNOPSIS
        Shows the package list this machine would install, and the handlers, without installing. Called by --list-packages.
    #>
    $ScoopDir = $global:BaseDir
    $packageFile = Get-PackageListFile
    if (-not $packageFile) {
        Write-Host "[ERROR] No package list under $global:PackagesDir. Run: $ScoopDir\bin\scoop-boot.ps1 --update" -ForegroundColor Red
        return (New-RunResult -Command 'list-packages' -Ok $false)
    }
    $apps = @(Read-PackageList -Path $packageFile)
    Write-Host ""
    Write-Host "Package list: $packageFile" -ForegroundColor Cyan
    $profileNames = (Get-ScoopBootConfig).Profile
    if ($profileNames) { Write-Host "Profiles: $profileNames (PROFILE in etc\scoop-boot.conf)" -ForegroundColor Gray }
    Write-Host "Bootstrap (always, Step 1): 7zip git aria2 sudo innounp dark lessmsi wget cacert; buckets main extras" -ForegroundColor Gray
    Write-Host "Buckets added in Step 2: java versions$(@(Read-PackageListBuckets -Path $packageFile | ForEach-Object { ' ' + $_.Name }) -join '')" -ForegroundColor Gray
    Write-Host ""
    $n = 0
    foreach ($app in $apps) {
        $n++
        $name = Get-ManifestAppName -Package $app
        $state = if (Test-Path "$ScoopDir\apps\$name\current") { 'installed' } else { 'missing' }
        $entry = Get-PackageHandler -Name $name
        $handler = if ($entry) { "  <- $($entry.Description)" } else { '' }
        Write-Host ("{0,3}  {1,-22} {2,-10}{3}" -f $n, $app, $state, $handler)
    }
    Write-Host ""
    $listedNames = @($apps | ForEach-Object { Get-ManifestAppName -Package $_ })
    foreach ($entry in $global:PackageHandlers) {
        if ($global:BootstrapPackages -contains $entry.Name) { continue }
        if ($listedNames -notcontains $entry.Name) {
            Write-Host "[WARN] $($entry.Name) has a post-install step but is not in the list" -ForegroundColor Yellow
        }
    }
    if ((Split-Path -Leaf $packageFile) -eq 'default.txt') {
        Write-Host "$($apps.Count) packages. This machine uses the delivered list; $global:ScoopBootScript --profile=NAMES composes $global:PackagesDir\$(Get-Hostname).txt, which replaces it." -ForegroundColor Gray
    } else {
        Write-Host "$($apps.Count) packages. This list is this machine's own: edit it, or compose it again with $global:ScoopBootScript --profile=NAMES --force." -ForegroundColor Gray
    }
    return (New-RunResult -Command 'list-packages' -Ok $true -Data @{ Packages = $apps.Count })
}

# ============================================================================
# RESET (formerly scoop-complete-reset.ps1)
# ============================================================================

if (-not (Test-Path variable:global:ScoopBootExplorerStopped)) { $global:ScoopBootExplorerStopped = $false }

function Get-ModuleHolders {
    <#
    .SYNOPSIS
        Processes that have a DLL or exe from under $Path loaded (shell extensions in
        Explorer and in every program with a file dialog, a file manager). No handle scan
        shows loaded modules; this is what keeps apps\tortoisesvn alive after everything
        else is gone. Returns Name, Id, Path per process, this process excluded.
    #>
    param([string]$Path)
    $result = @()
    foreach ($process in @(Get-Process | Where-Object { $_.Id -ne $PID })) {
        $hit = $false
        try {
            foreach ($module in @($process.Modules)) {
                if ($module.FileName -and $module.FileName -like "$Path\*") { $hit = $true; break }
            }
        } catch { }
        if ($hit) { $result += [pscustomobject]@{ Name = $process.Name; Id = $process.Id; Path = $process.Path } }
    }
    return $result
}

function Start-ExplorerWithRegistryEnvironment {
    <#
    .SYNOPSIS
        Starts explorer.exe with an environment block built from the registry (Machine,
        User, the volatile user values), not inherited from this process.
    .DESCRIPTION
        An Explorer started by Windows after the shell was stopped reuses the block of
        the logon, and one started by a script inherits the script's block; both still
        carry the variables the reset removed, and every shell opened from the Start
        menu inherits them (the AVD, 30.10.). Only a block read from the registry now
        gives new shells the cleaned environment without logging off.
    #>
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $env:SystemRoot 'explorer.exe'
    $psi.UseShellExecute = $false
    $psi.EnvironmentVariables.Clear()
    foreach ($scope in @('Machine', 'User')) {
        $vars = [System.Environment]::GetEnvironmentVariables($scope)
        foreach ($key in @($vars.Keys)) {
            if ($key -ieq 'Path') { continue }
            $psi.EnvironmentVariables[$key] = [string]$vars[$key]
        }
    }
    $psi.EnvironmentVariables['Path'] = (@([System.Environment]::GetEnvironmentVariable('Path', 'Machine'), [System.Environment]::GetEnvironmentVariable('Path', 'User')) | Where-Object { $_ }) -join ';'
    # Logon-time values (USERPROFILE, APPDATA, LOCALAPPDATA, USERNAME, LOGONSERVER, ...)
    $volatile = Get-ItemProperty -Path 'HKCU:\Volatile Environment' -ErrorAction SilentlyContinue
    if ($volatile) {
        foreach ($property in $volatile.PSObject.Properties) {
            if ($property.Name -like 'PS*') { continue }
            $psi.EnvironmentVariables[$property.Name] = [string]$property.Value
        }
    }
    foreach ($name in @('USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'USERNAME', 'USERDOMAIN', 'HOMEDRIVE', 'HOMEPATH')) {
        if (-not $psi.EnvironmentVariables.ContainsKey($name)) {
            $value = [System.Environment]::GetEnvironmentVariable($name)
            if ($value) { $psi.EnvironmentVariables[$name] = $value }
        }
    }
    [void][System.Diagnostics.Process]::Start($psi)
}

function Get-ScoopHostedAncestor {
    <#
    .SYNOPSIS
        The nearest ancestor of this process whose image lives in a Scoop directory (a
        Windows Terminal, a mintty), or $null. The reset refuses to run inside one.
    #>
    $processId = $PID
    for ($depth = 0; $depth -lt 8; $depth++) {
        $process = $null
        try { $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction Stop } catch { }
        if (-not $process) { return $null }
        if ($depth -gt 0 -and $process.ExecutablePath -and (Test-ScoopOwnedPath $process.ExecutablePath)) { return $process }
        if (-not $process.ParentProcessId -or $process.ParentProcessId -eq $processId) { return $null }
        $processId = $process.ParentProcessId
    }
    return $null
}

function Invoke-ScoopReset {
    <#
    .SYNOPSIS
        Removes Scoop again: processes, backup, variables, PATH entries, directories, registry, shortcuts. Called by --admin-reset.
    #>
    param(
        [switch]$Force,
        [switch]$KeepPersist
    )
    # Strict mode version 1 (undefined variables), see Install-ScoopTools. Continue:
    # a directory that cannot be deleted is reported, the rest is still cleaned up.
    Set-StrictMode -Version 1
    $ErrorActionPreference = 'Continue'
    $ScoopDir = $global:BaseDir
    $BackupRoot = "$ScoopDir\backups"
    $BackupDir = "$BackupRoot\$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    $BackupsToKeep = 5
    # Programs that are not Scoop's but have DLLs from a Scoop directory loaded; filled
    # by the deletion routine (a nested function, hence script scope), named at the end
    $script:ScoopBootDllHolders = @()

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

    # The shell running this reset must not live in a Scoop directory: a Windows
    # Terminal or a Git Bash (mintty) from apps\ is stopped with the other Scoop
    # processes, its console goes with it, and Windows ends this PowerShell
    # halfway through. Walk the parent chain before anything is touched.
    $hostProcess = Get-ScoopHostedAncestor
    if ($hostProcess) {
        Write-Host "[ERROR] This shell runs inside $($hostProcess.Name) (PID $($hostProcess.ProcessId)) from $($hostProcess.ExecutablePath)" -ForegroundColor Red
        Write-Host "        The reset stops every process in Scoop's directories, that window included, and would end with it." -ForegroundColor Red
        Write-Host "        Start PowerShell from the Start menu (Run as Administrator) and run the reset there." -ForegroundColor Yellow
        return (New-RunResult -Command 'admin-reset' -Ok $false -Data @{ HostedBy = $hostProcess.ExecutablePath })
    }

    if (-not $Force) {
        Write-Host "Continue? [y/N]: " -ForegroundColor Yellow -NoNewline
        $confirm = Read-Host
        if ($confirm -ne 'y' -and $confirm -ne 'Y') {
            Write-Host "Cancelled." -ForegroundColor Gray
            return (New-RunResult -Command 'admin-reset' -Ok $true -Data @{ Cancelled = $true })
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

        if ($needsPermissionFix -and (Test-ScoopBootFake)) {
            Write-Host "  -> [FAKE] takeown and icacls skipped" -ForegroundColor DarkCyan
        } elseif ($needsPermissionFix) {
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

        # Method 1: PowerShell Remove-Item with the long-path prefix (Windows only: on a
        # Linux runner in fake mode the prefix names nothing, and nothing is deleted)
        try {
            $longPath = if ((-not (Test-Path variable:IsWindows)) -or $IsWindows) { "\\?\$Path" } else { $Path }
            Remove-Item -Path $longPath -Recurse -Force -ErrorAction Stop
            if (Test-Path $Path) { throw "still there" }
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

        # Method 3: shell extensions (7-Zip, TortoiseSVN) are DLLs loaded into Explorer,
        # which no handle scan shows. Stop Explorer and the shell hosts and retry; Explorer
        # is started again at the end of the reset, after every directory is gone. Started
        # here, it would load the same DLLs back before the retry (the AVD, 30.10.), and it
        # would inherit this process's environment, which still holds the removed
        # variables, and pass it on to every shell opened from the Start menu.
        if (-not $deleted -and (Test-Path $Path)) {
            Write-Host "  -> Files locked, stopping Explorer and the shell hosts (restarted after the cleanup)..." -ForegroundColor Yellow
            try {
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
                Stop-Process -Name ShellExperienceHost -Force -ErrorAction SilentlyContinue
                Stop-Process -Name StartMenuExperienceHost -Force -ErrorAction SilentlyContinue
                $global:ScoopBootExplorerStopped = $true
                Start-Sleep -Seconds 2

                # Shell extensions load into every program with a file dialog or a file
                # manager, not only into Explorer. Scoop's own processes are stopped; any
                # other program is named, it is the user's to close (FreeCommander from
                # its own directory held apps\tortoisesvn on the AVD, 30.10.)
                foreach ($holder in @(Get-ModuleHolders -Path $Path)) {
                    if ($holder.Name -ieq 'explorer') { continue }
                    if ($holder.Path -and (Test-ScoopOwnedPath $holder.Path)) {
                        try { Stop-Process -Id $holder.Id -Force -ErrorAction Stop; Write-Host "  -> Stopped $($holder.Name) (PID $($holder.Id)), has DLLs from $Path loaded" -ForegroundColor Yellow } catch { }
                    } else {
                        Write-Host "  -> $($holder.Name) (PID $($holder.Id)) has DLLs from $Path loaded, left running: $(if ($holder.Path) { $holder.Path } else { 'path not readable' })" -ForegroundColor Yellow
                        $script:ScoopBootDllHolders += [pscustomobject]@{ Name = $holder.Name; Id = $holder.Id; Path = $holder.Path; Directory = $Path }
                    }
                }

                # An IDE that keeps running (--keep-persist) respawns its terminal bash.exe
                # from apps\git, a shell-extension helper (TSVNCache.exe) comes back with
                # Explorer: stop whatever runs from here now, then try once more
                $respawned = @(Get-Process | Where-Object { $_.Path -and $_.Path -like "$Path\*" -and $_.Id -ne $PID })
                foreach ($r in $respawned) {
                    try { Stop-Process -Id $r.Id -Force -ErrorAction Stop; Write-Host "  -> Stopped $($r.Name) (PID $($r.Id)), started again from $Path" -ForegroundColor Yellow } catch { }
                }
                if ($respawned.Count -gt 0) { Start-Sleep -Seconds 2 }

                # Try deletion again with cmd rd
                & $env:ComSpec /c "rd /s /q `"\\?\$Path`"" 2>$null
                if (-not (Test-Path $Path)) {
                    $deleted = $true
                    Write-Host "  -> Deleted with Explorer stopped" -ForegroundColor Green
                }
            } catch {
                Write-Host "  -> Stopping Explorer failed" -ForegroundColor Yellow
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
    # Fake mode: nothing runs from the simulated installation; the whole process
    # section (handle64, image paths, agents) is Windows-only and skipped
    $nonScoopHolders = @()
    if (Test-ScoopBootFake) { Write-Host "[FAKE] Process check skipped" -ForegroundColor DarkCyan } else {

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
    # Every directory the reset deletes is scanned: apps\, and persist\ unless it is
    # kept. JetBrains Toolbox installs its IDEs under persist\jetbrains-toolbox\apps,
    # so Rider and PyCharm run from persist\ and held it on 29.10.
    $scanDirs = @("$ScoopDir\apps", "$ScoopDir\shims", "$ScoopDir\global")
    if (-not $KeepPersist) { $scanDirs += "$ScoopDir\persist" }
    $scanDirs = @($scanDirs | Where-Object { Test-Path $_ })
    Write-Host ""
    Write-Host "[INFO] Scanning for ALL processes with open handles to Scoop's directories ($(($scanDirs | ForEach-Object { Split-Path -Leaf $_ }) -join ', '))..." -ForegroundColor Gray
    Set-ScoopBootTitle -Text "scoop-boot reset processes"
    # A run that removed the junctions but could not delete apps\ leaves
    # sysinternals\current gone; the versioned directory still has handle64.exe
    $handle64Path = "$ScoopDir\apps\sysinternals\current\handle64.exe"
    if (-not (Test-Path $handle64Path)) {
        $found = Get-ChildItem -Path "$ScoopDir\apps\sysinternals" -Filter 'handle64.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $handle64Path = $found.FullName }
    }
    $usedHandle = $false
    # Processes that are not Scoop's but hold its directories (a cmd whose working
    # directory is under apps\, an IDE with a file open): spared, named at the end
    $nonScoopHolders = @()

    if (Test-Path $handle64Path) {
        Write-Host "  [INFO] Using handle64.exe for comprehensive scan..." -ForegroundColor DarkGray
        # Scan, stop, wait, scan again: the renderer children of a browser die with
        # their parent (stopping them by PID then fails although they are gone), and
        # a crash helper or a restarted app can take new handles after the first
        # pass. Up to three passes; the deletion below reports whatever still holds.
        $maxPasses = 3
        for ($pass = 1; $pass -le $maxPasses; $pass++) {
            try {
                # Get all processes with handles into the directories to be deleted
                $handleOutput = ''
                foreach ($scanDir in $scanDirs) {
                    $handleOutput += (& $handle64Path -accepteula -nobanner $scanDir 2>&1 | Out-String) + "`n"
                }

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

                if ($processesToKill.Count -eq 0) {
                    if ($pass -eq 1) { Write-Host "  [OK] No processes found by handle64" -ForegroundColor Green }
                    else { Write-Host "  [OK] Pass $pass`: nothing holds Scoop's directories any more" -ForegroundColor Green }
                    break
                }

                # Only processes that belong to Scoop (image under $ScoopDir) are terminated.
                # explorer.exe is the exception: shell extensions (7-Zip, TortoiseSVN, ...) load
                # DLLs from $ScoopDir into it, so it must go, and it is restarted after the
                # directories are gone. Anything else (Teams, Outlook, Edge with a file dialog
                # open) keeps running; if it blocks the deletion, that is reported below.
                # Image paths: WMI first (it also answers for the sandboxed renderer
                # processes of Chrome and Firefox, whose restricted tokens make
                # Get-Process fail even for an administrator), then Get-Process. A
                # process whose path stays unknown counts as a Scoop process when a
                # process of the same name provably runs from $ScoopDir: those renderers
                # held apps\ on 22.10. and 24.10. and were spared by mistake.
                $imagePaths = @{}
                foreach ($processId in $processesToKill.Keys) {
                    $imagePath = $null
                    try { $imagePath = (Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction Stop).ExecutablePath } catch { }
                    if (-not $imagePath) { try { $imagePath = (Get-Process -Id $processId -ErrorAction Stop).Path } catch { } }
                    $imagePaths[$processId] = $imagePath
                }
                $scoopExeNames = @($processesToKill.Keys | Where-Object { $imagePaths[$_] -and ($imagePaths[$_] -like "$ScoopDir\*") } | ForEach-Object { $processesToKill[$_].ToLower() } | Sort-Object -Unique)
                $toStop = @()
                $others = @()
                $nonScoopHolders = @()
                foreach ($processId in $processesToKill.Keys) {
                    if ($processId -eq $PID) { continue }
                    $exeName = $processesToKill[$processId]
                    $imagePath = $imagePaths[$processId]
                    $isScoopApp = ($imagePath -and ($imagePath -like "$ScoopDir\*")) -or ((-not $imagePath) -and ($scoopExeNames -contains $exeName.ToLower()))
                    $isExplorer = $exeName -ieq 'explorer.exe'
                    if ($isExplorer -or $isScoopApp) { $toStop += @{ Id = $processId; Exe = $exeName; Path = $imagePath; Explorer = $isExplorer } }
                    else { $others += @{ Id = $processId; Exe = $exeName; Path = $imagePath } }
                }
                $nonScoopHolders = $others

                if ($pass -eq 1) {
                    Write-Host "  [FOUND] $($processesToKill.Count) processes with open handles:" -ForegroundColor Yellow
                    foreach ($o in $others) {
                        # The path tells which program to close by hand when the deletion
                        # below fails (a browser with a download dialog, an IDE, Teams)
                        $where = if ($o.Path) { $o.Path } else { 'path not readable' }
                        Write-Host "    - $($o.Exe) (PID: $($o.Id)): not a Scoop application, left running ($where)" -ForegroundColor DarkGray
                    }
                } elseif ($toStop.Count -eq 0) {
                    Write-Host "  [OK] Pass $pass`: only non-Scoop processes still hold Scoop's directories ($($others.Count), left running)" -ForegroundColor Green
                    break
                } else {
                    Write-Host "  [INFO] Pass $pass`: $($toStop.Count) Scoop process(es) still hold Scoop's directories (children of stopped browsers, restarted apps):" -ForegroundColor Yellow
                }

                foreach ($p in $toStop) {
                    if ($p.Explorer) {
                        Write-Host "    - $($p.Exe) (PID: $($p.Id)): Windows shell, holds Scoop shell extensions; restarted after cleanup" -ForegroundColor Yellow
                    } else {
                        Write-Host "    - $($p.Exe) (PID: $($p.Id)): Scoop application$(if (-not $p.Path) { ' (path not readable, same name as one)' })" -ForegroundColor Yellow
                    }
                    try {
                        Stop-Process -Id $p.Id -Force -ErrorAction Stop
                        Write-Host "      [OK] Stopped PID $($p.Id)" -ForegroundColor Green
                        if ($p.Explorer) { $global:ScoopBootExplorerStopped = $true }
                    } catch {
                        # A renderer dies with its browser before its own turn comes
                        if (Get-Process -Id $p.Id -ErrorAction SilentlyContinue) {
                            Write-Host "      [FAIL] Could not stop PID $($p.Id): $($_.Exception.Message)" -ForegroundColor Red
                        } else {
                            Write-Host "      [OK] Already gone (PID $($p.Id))" -ForegroundColor Gray
                        }
                    }
                }
                Start-Sleep -Seconds 2
                $usedHandle = $true
            } catch {
                Write-Host "  [WARN] handle64.exe failed: $_" -ForegroundColor Yellow
                break
            }
        }
    } else {
        Write-Host "  [WARN] handle64.exe not found at: $handle64Path" -ForegroundColor Yellow
        Write-Host "  [INFO] Install Sysinternals for better process detection:" -ForegroundColor Yellow
        Write-Host "         scoop install sysinternals" -ForegroundColor Gray
    }


    # Method 3: processes whose image lives in a Scoop directory (apps\, and persist\
    # unless kept: the JetBrains IDEs run from there). handle64 lists open file
    # handles only; a program that holds no file at the moment (a Git Bash shell, an
    # idle editor) is invisible to it but keeps its own exe locked, so apps\git
    # stayed behind on 29.10. This check therefore always runs.
    Write-Host ""
    if ($usedHandle) { Write-Host "  [INFO] Processes running from Scoop's directories (by image path)..." -ForegroundColor Gray }
    else { Write-Host "  [INFO] Using Get-Process fallback (may miss background services)..." -ForegroundColor Gray }
    # Up to three passes: an IDE restarts its terminal shell when it is stopped, a
    # launcher restarts its helper; the second pass catches what came back
    for ($pathPass = 1; $pathPass -le 3; $pathPass++) {
        $runningApps = @(Get-Process | Where-Object {
            $_.Path -and $_.Id -ne $PID -and (Test-ScoopOwnedPath $_.Path) -and -not ($KeepPersist -and $_.Path -like "$ScoopDir\persist\*")
        } | Select-Object Name, Id, Path)

        if ($runningApps.Count -eq 0) {
            if ($pathPass -eq 1) { Write-Host "  [OK] No processes running from Scoop's directories" -ForegroundColor Green }
            else { Write-Host "  [OK] Pass $pathPass`: nothing runs from Scoop's directories any more" -ForegroundColor Green }
            break
        }
        if ($pathPass -eq 1) { Write-Host "  [FOUND] Scoop applications detected:" -ForegroundColor Yellow }
        else { Write-Host "  [INFO] Pass $pathPass`: $($runningApps.Count) process(es) started again from Scoop's directories:" -ForegroundColor Yellow }
        $runningApps | ForEach-Object {
            Write-Host "    - $($_.Name) (PID: $($_.Id)): $($_.Path)" -ForegroundColor Yellow
        }

        Write-Host "  [INFO] Stopping all detected processes..." -ForegroundColor Gray
        $runningApps | ForEach-Object {
            # Inside catch, $_ is the error record, hence the copy
            $proc = $_
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
                Write-Host "    [OK] Stopped: $($proc.Name) (PID: $($proc.Id))" -ForegroundColor Green
            } catch {
                if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) {
                    Write-Host "    [FAIL] Could not stop: $($proc.Name) (PID: $($proc.Id)): $($_.Exception.Message)" -ForegroundColor Red
                } else {
                    Write-Host "    [OK] Already gone: $($proc.Name) (PID: $($proc.Id))" -ForegroundColor Gray
                }
            }
        }
        Start-Sleep -Seconds 2
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
    }

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

    $envVars = Get-RegistryEnvironmentVariables -Scope 'User'
    $envVars | ConvertTo-Json | Out-File "$BackupDir\user_env_backup.json"

    $machineEnvVars = Get-RegistryEnvironmentVariables -Scope 'Machine'
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
        $removedNames = @()
        $all = Get-RegistryEnvironmentVariables -Scope $Scope
        foreach ($name in @($all.Keys)) {
            if ($varsToKeep -contains $name) { continue }
            $value = [string]$all[$name]
            $byName  = $varsToRemove -contains $name
            $byValue = @($value -split ';' | Where-Object { Test-ScoopOwnedPath $_ }).Count -gt 0
            if ($byName -or $byValue) {
                Set-RegistryEnvironmentVariable -Name $name -Value $null -Scope $Scope
                Write-Host "[OK] Removed $Scope variable: $name" -ForegroundColor Green
                $removed++
                $removedNames += $name
            }
        }
        if ($removed -eq 0) {
            Write-Host "[OK] No $Scope variables to remove" -ForegroundColor Gray
        }
        return $removedNames
    }

    $removedVariableNames = @()
    $removedVariableNames += @(Remove-ScoopEnvironmentVariables -Scope "User")
    $removedVariableNames += @(Remove-ScoopEnvironmentVariables -Scope "Machine")

    # 5. Clean User PATH
    Write-Host ""
    Set-ScoopBootTitle -Text "scoop-boot reset environment"
    Write-Host ">>> Cleaning User PATH..." -ForegroundColor Cyan
    $userPath = Get-RegistryEnvironmentVariable -Name 'Path' -Scope 'User'
    if ($userPath) {
        $pathArray = $userPath -split ';' | Where-Object { $_ -ne '' -and -not (Test-ScoopOwnedPath $_) }
        $newPath = $pathArray -join ';'
        Set-RegistryEnvironmentVariable -Name 'Path' -Value $newPath -Scope 'User'
        Write-Host "[OK] User PATH cleaned" -ForegroundColor Green
    }

    # 6. Clean Machine PATH
    Write-Host ""
    Write-Host ">>> Cleaning Machine PATH..." -ForegroundColor Cyan
    $machinePath = Get-RegistryEnvironmentVariable -Name 'Path' -Scope 'Machine'
    if ($machinePath) {
        $pathArray = $machinePath -split ';' | Where-Object { $_ -ne '' -and -not (Test-ScoopOwnedPath $_) }
        $newPath = $pathArray -join ';'
        Set-RegistryEnvironmentVariable -Name 'Path' -Value $newPath -Scope 'Machine'
        Write-Host "[OK] Machine PATH cleaned" -ForegroundColor Green
    }

    # 6b. The same for this process: everything the reset starts from here (Explorer
    # after the cleanup, and through it every shell opened from the Start menu)
    # inherits this environment, which until now still carried the removed values
    # (the AVD, 30.10.: registry clean, new shells with the old JAVA_HOME)
    # The same rule as for the registry, because this shell may have inherited values
    # that an earlier run already removed from the registry
    $processAligned = 0
    foreach ($name in @([System.Environment]::GetEnvironmentVariables('Process').Keys)) {
        if ($varsToKeep -contains $name) { continue }
        $value = [string][System.Environment]::GetEnvironmentVariable($name, 'Process')
        $byName  = ($varsToRemove -contains $name) -or ($removedVariableNames -contains $name)
        $byValue = @($value -split ';' | Where-Object { Test-ScoopOwnedPath $_ }).Count -gt 0
        if ($byName -or $byValue) {
            [System.Environment]::SetEnvironmentVariable($name, [NullString]::Value, 'Process')
            $processAligned++
        }
    }
    $env:Path = (@((Get-RegistryEnvironmentVariable -Name 'Path' -Scope 'Machine'), (Get-RegistryEnvironmentVariable -Name 'Path' -Scope 'User')) | Where-Object { $_ }) -join ';'
    Write-Host "[OK] Process environment of this shell aligned ($processAligned variable(s), PATH)" -ForegroundColor Gray

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

    # Explorer and every shell opened from it: a running Explorer keeps the environment
    # block it was started with (the logon's, or an inherited one) and reads the
    # registry again only when WM_SETTINGCHANGE "Environment" arrives. .NET sends that
    # message on every Machine or User write, so a run that removed nothing never sent
    # it and new shells kept values the registry no longer had (the AVD, 30.10.; after
    # the message a new shell was clean without logging off). Stopping Explorer does
    # not help: Windows restarts it at once with the block of the logon.
    Write-Host ""
    Write-Host ">>> Telling Explorer to reload the environment from the registry..." -ForegroundColor Cyan
    if (-not (Test-ScoopBootFake) -and -not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        try {
            Start-ExplorerWithRegistryEnvironment
            Write-Host "[OK] explorer.exe started (environment from the registry)" -ForegroundColor Green
        } catch {
            Start-Process -FilePath "$env:SystemRoot\explorer.exe"
            Write-Host "[WARN] explorer.exe started with this shell's environment ($($_.Exception.Message))" -ForegroundColor Yellow
        }
        Start-Sleep -Seconds 2
    }
    Set-RegistryEnvironmentVariable -Name 'SCOOP_BOOT_ENV_REFRESH' -Value '1' -Scope 'User'
    Set-RegistryEnvironmentVariable -Name 'SCOOP_BOOT_ENV_REFRESH' -Value $null -Scope 'User'
    Write-Host "[OK] Environment change broadcast (WM_SETTINGCHANGE); shells opened from the Start menu see the cleaned values" -ForegroundColor Green

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
        Write-Host "  Get-Process | Where-Object { `$_.Path -like '$ScoopDir\*' }" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  # Check for open handles (if Sysinternals installed):" -ForegroundColor Gray
        Write-Host "  handle64.exe $ScoopDir" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Manual cleanup commands:" -ForegroundColor Cyan
        $remainingDirs | ForEach-Object {
            Write-Host "  rd /s /q `"\\?\$ScoopDir\$_`"" -ForegroundColor Gray
        }
        if ($script:ScoopBootDllHolders.Count -gt 0) {
            Write-Host ""
            Write-Host "DLLs from the remaining directories are loaded in programs that are not Scoop's (shell extensions; left running on purpose); close them, then run the reset again:" -ForegroundColor Yellow
            foreach ($h in $script:ScoopBootDllHolders) {
                Write-Host "  - $($h.Name) (PID: $($h.Id)): $(if ($h.Path) { $h.Path } else { 'path not readable' }) holds $($h.Directory)" -ForegroundColor Yellow
            }
        }
        if ($nonScoopHolders.Count -gt 0) {
            Write-Host ""
            Write-Host "Held by processes that are not Scoop's (left running on purpose); close them or move their working directory, then run the reset again:" -ForegroundColor Yellow
            foreach ($h in $nonScoopHolders) {
                Write-Host "  - $($h.Exe) (PID: $($h.Id)): $(if ($h.Path) { $h.Path } else { 'path not readable' })" -ForegroundColor Yellow
            }
        }
        # Processes that started from the remaining directories after the scan (a
        # terminal respawned by an IDE, a shell-extension helper): named here so that
        # the next run has a target
        $stillRunning = @(if (-not (Test-ScoopBootFake)) { Get-Process | Where-Object { $p = $_.Path; $p -and $_.Id -ne $PID -and @($remainingDirs | Where-Object { $p -like "$ScoopDir\$_\*" }).Count -gt 0 } })
        if ($stillRunning.Count -gt 0) {
            Write-Host ""
            Write-Host "Running from the remaining directories now (started after the scan; close them or run the reset again):" -ForegroundColor Yellow
            foreach ($r in $stillRunning) { Write-Host "  - $($r.Name) (PID: $($r.Id)): $($r.Path)" -ForegroundColor Yellow }
        }
    } else {
        Write-Host "[OK] All directories successfully removed!" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Check in a new shell (must print nothing; $ScoopDir\bin in PATH is scoop-boot's and stays):" -ForegroundColor White
    Write-Host "     gci env: | ? { `$_.Value -match '$([regex]::Escape($ScoopDir))\\($($global:ScoopOwnedDirs -join '|'))' }" -ForegroundColor Gray
    Write-Host "  2. Set up again (Administrator): $global:ScoopBootScript --admin-init, then --admin-setenv" -ForegroundColor White
    Write-Host "  3. Normal shell: $global:ScoopBootScript --user-install" -ForegroundColor White
    Write-Host ""
    Write-Host "Backup location: $BackupDir" -ForegroundColor Gray
    return (New-RunResult -Command 'admin-reset' -Ok ($remainingDirs.Count -eq 0) -Data @{ Remaining = $remainingDirs; Backup = $BackupDir })
}
