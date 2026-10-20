<#
.SYNOPSIS
    Bootstrap script for portable Windows development environments using Scoop package manager.

.DESCRIPTION
    scoop-boot.ps1 v1.14.1 - Portable Windows Development Environment Bootstrap

    Features:
    - Order-independent parameter parsing
    - Dynamic Git version detection
    - Meta-environment system (User/System scope control)
    - Environment configuration with GitHub template download
    - List operations (+=, =+, -=) for ALL environment variables
    - Flexible application installation
    - Comprehensive self-testing (30 tests)
    - ASCII-only output for console compatibility

.PARAMETER (Dynamic)
    This script uses custom parameter parsing to support order-independent arguments.
    All parameters can be specified in any order.

.NOTES
    Version: 1.14.1
    Author: System Administrator
    Requires: PowerShell 5.1 or higher

    Changes in v1.14.1:
    - FIX: log attribution after a child script returned. Get-PSCallStack reports
      the Write-Host override as "Write-Host<Process>", so it was not skipped and
      its ScriptName (scoop-boot.ps1) won once that context existed
    - FIX: --asr-report without Administrator printed a phantom rule line and
      Defender's "N/A" strings; now says what needs elevation and keeps the events
    - --bootstrap skips its "Next steps" guide when SCOOP_BOOT_CALLER=install
    - sliksvn dropped from the templates (TortoiseSVN provides the same svn.exe)

    Changes in v1.14.0:
    - NEW: --asr-report writes Defender/ASR rules, exclusions and the ASR blocks
      of the last 14 days to logs\scoopboot\asr-report-<date>.txt
    - NEW: --update downloads the current scripts and the scoop wrapper from
      GitHub into bin\ (previous versions kept in backups\scripts-<timestamp>)
    - NEW: --quiet for --clean-user-scope (used by the scoop wrapper): console
      shows a one-line summary only when something changed
    - scoop wrapper (bin\scoop.ps1, scoop.cmd, scoop): runs --clean-user-scope
      after state-changing Scoop commands; "scoop upgrade" = update, update -a,
      cleanup -a, clean user scope

    Changes in v1.13.1:
    - Logging: context (script, mode, version) is resolved from the call stack,
      so output of child scripts (scoop.ps1, the Scoop installer) is attributed
      to the invoking scoop-boot script instead of an empty "()".
    - Logging: ANSI colour codes stripped, -NoNewline fragments joined into one
      line, carriage-return progress bars reduced to their final state, aria2
      progress lines dropped

    Changes in v1.13.0:
    - Logging: every Write-Host is mirrored to C:\usr\logs\scoopboot\<yyyyMMdd>.log
      with timestamp, script, version and level; session header with host, user,
      admin, Windows and PowerShell version, script hash and arguments; logs older
      than 60 days are pruned. The other two scripts dot-source this file in
      library mode ($global:ScoopBootLibraryOnly) and share the same log.
    - Version banner with the script's SHA-256 (first 8 digits) on every start
    - Bootstrap: 7z.exe and git.exe are started once right after their install;
      "Access is denied" (endpoint security blocking a new release) is reported
      as FATAL with the cause, instead of 60 follow-up extraction errors

    Changes in v1.12.0:
    - NEW: --clean-user-scope. Scoop writes JAVA_HOME, GRADLE_USER_HOME, ANT_HOME,
      ... and PATH entries into the User scope on every install/update; User
      values override Machine values, so the system.* file was silently defeated.
      The command removes User PATH entries inside Scoop's subdirectories and
      User variables whose name the system.* files set, then applies user.* files.
      No admin needed; run after scoop update / scoop install.
    - --apply-env sweeps Scoop entries from the Machine PATH before applying the
      system.* files (the manual PATH-= cleanup block is no longer needed for
      Scoop directories) and runs --clean-user-scope afterwards.
    - Scoop's subdirectories are apps, buckets, cache, persist, shims, global;
      nothing else under the base directory is treated as Scoop's.
    - WARN on unresolved $VAR references instead of writing the literal text

    Changes in v1.11.1:
    - Bootstrap: 7zip before git (git depends on 7zip; avoids the duplicate install)
    - Bootstrap: aria2 warning disabled right after aria2 is installed, not after bootstrap
    - Bootstrap: each essential/recommended tool is verified via apps\<tool>\current

    Changes in v1.11.0:
    - FIX: Bootstrap failed on every fresh machine because the official Scoop
      installer refuses a non-empty target directory, and C:\usr already
      contains bin\ and etc\ in the scoop-boot layout. The downloaded
      installer is now patched at that single check (Get-ScoopInstaller).
    - Installer output is captured and shown when the installation fails
    - Bootstrap verification checks apps\scoop\current and the shims directory
      instead of only Get-Command
    - ListRemove (VAR-=value) only writes and reports when the value was
      actually present; the change counter no longer counts no-ops

    Changes in v1.10.0:
    - List operations (+=, =+, -=) now work for ALL variables (not just PATH)
    - Added support for PERL5LIB, PYTHONPATH, CLASSPATH, PSModulePath, etc.
    - Extended self-tests to cover new list operations
    - Fixed processing stop issue with non-PATH list operations

.EXAMPLE
    .\scoop-boot.ps1 --bootstrap
    Installs Scoop and essential tools

.EXAMPLE
    .\scoop-boot.ps1 --init-env=system.bootes.user.env
    Creates environment configuration file

.EXAMPLE
    .\scoop-boot.ps1 --apply-env --dry-run
    Shows what changes would be applied

.EXAMPLE
    .\scoop-boot.ps1 --selfTest
    Runs comprehensive self-tests (30 tests)
#>

# ============================================================================
# INIT & VALIDATION
# ============================================================================

param ()  # Required for custom parsing - no positional parameters

# Library mode: scoop-complete-install.ps1 and scoop-complete-reset.ps1 dot-source
# this file with $global:ScoopBootLibraryOnly = $true to get the logging functions.
# In that case nothing below the function definitions runs, and the strict mode /
# error preference of this script must not leak into the caller.
$script:LibraryOnly = (Test-Path variable:global:ScoopBootLibraryOnly) -and $global:ScoopBootLibraryOnly
if (-not $script:LibraryOnly) {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"
}

# Validate PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5 -or
    ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Host "ERROR: PowerShell 5.1 or higher required" -ForegroundColor Red
    Write-Host "Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

$global:ScriptVersion = "1.14.1"
$global:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:BaseDir = Split-Path -Parent $global:ScriptRoot
$global:EnvDir = Join-Path $global:BaseDir "etc\environments"

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
$script:ScoopBootLogOwnFunctions = @('Write-Host', 'Write-ScoopBootLogLine', 'Get-ScoopBootLogContext', 'Initialize-ScoopBootLog')

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
        if ($script:ScoopBootLogOwnFunctions -contains $fn) { continue }
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
$global:TemplateUrl = "https://raw.githubusercontent.com/stotz/scoop-boot/refs/heads/main/etc/environments/template-default.env"

# ============================================================================
# ARGUMENT PARSER
# ============================================================================

$global:ParsedArgs = @{
    Help = $false
    Version = $false
    Bootstrap = $false
    Status = $false
    SelfTest = $false
    Suggest = $false
    Environment = $false
    EnvStatus = $false
    InitEnv = $null
    ApplyEnv = $false
    CleanUserScope = $false
    Quiet = $false
    AsrReport = $false
    Update = $false
    DryRun = $false
    Rollback = $false
    Install = @()
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
            '^--status$' { $global:ParsedArgs.Status = $true }
            '^--selfTest$' { $global:ParsedArgs.SelfTest = $true }
            '^--suggest$' { $global:ParsedArgs.Suggest = $true }
            '^--environment$' { $global:ParsedArgs.Environment = $true }
            '^--env-status$' { $global:ParsedArgs.EnvStatus = $true }
            '^--init-env=(.+)$' { $global:ParsedArgs.InitEnv = $Matches[1] }
            '^--init-env$' {
                if ($i + 1 -lt $Arguments.Count -and $Arguments[$i + 1] -notmatch '^--') {
                    $i++
                    $global:ParsedArgs.InitEnv = $Arguments[$i]
                } else {
                    $global:ParsedArgs.InitEnv = ""
                }
            }
            '^--apply-env$' { $global:ParsedArgs.ApplyEnv = $true }
            '^--clean-user-scope$' { $global:ParsedArgs.CleanUserScope = $true }
            '^--quiet$' { $global:ParsedArgs.Quiet = $true }
            '^--asr-report$' { $global:ParsedArgs.AsrReport = $true }
            '^--update$' { $global:ParsedArgs.Update = $true }
            '^--dry-run$' { $global:ParsedArgs.DryRun = $true }
            '^--rollback$' { $global:ParsedArgs.Rollback = $true }
            '^--install$' {
                while ($i + 1 -lt $Arguments.Count -and $Arguments[$i + 1] -notmatch '^--') {
                    $i++
                    $global:ParsedArgs.Install += $Arguments[$i]
                }
            }
            default {
                if ($arg -notmatch '^--') {
                    $global:ParsedArgs.Install += $arg
                }
            }
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
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

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

function Expand-EnvironmentVariables {
    param([string]$Value)

    $expandedValue = $Value
    $maxIterations = 10
    $iteration = 0

    while ($iteration -lt $maxIterations) {
        $previousValue = $expandedValue

        # Replace $VAR or ${VAR} patterns
        $expandedValue = [regex]::Replace($expandedValue, '\$\{?([A-Z_][A-Z0-9_]*)\}?', {
            param($match)
            $varName = $match.Groups[1].Value

            # Check various sources
            if ($varName -eq "SCOOP") {
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
    Write-Host "  .\scoop-boot.ps1 [options] [apps...]"
    Write-Host ""
    Write-Host "OPTIONS:" -ForegroundColor Yellow
    Write-Host "  --help, -h           Show this help message"
    Write-Host "  --version, -v        Show version"
    Write-Host "  --bootstrap          Install Scoop and essential tools"
    Write-Host "  --status             Show current environment status"
    Write-Host "  --selfTest           Run comprehensive self-tests"
    Write-Host "  --suggest            Show suggested applications"
    Write-Host "  --environment        Show environment variables"
    Write-Host "  --env-status         Show environment configuration status"
    Write-Host "  --init-env=FILE      Create environment configuration file"
    Write-Host "  --apply-env          Apply environment configuration (system.* needs admin)"
    Write-Host "  --clean-user-scope   Remove Scoop's User-scope overrides, apply user.* files (no admin)"
    Write-Host "  --asr-report         Write Defender/ASR configuration and recent blocks to the log directory"
    Write-Host "  --update             Download the current scoop-boot scripts and scoop wrapper from GitHub"
    Write-Host "  --quiet              With --clean-user-scope: print only a summary when something changed"
    Write-Host "  --dry-run            Show what would be changed"
    Write-Host "  --rollback           Rollback to previous configuration"
    Write-Host "  --install APP...     Install applications"
    Write-Host ""
    Write-Host "ENVIRONMENT FILES:" -ForegroundColor Yellow
    Write-Host "  system.default.env              System-wide defaults"
    Write-Host "  system.HOSTNAME.USERNAME.env    System-wide host-user specific"
    Write-Host "  user.default.env                User defaults"
    Write-Host "  user.HOSTNAME.USERNAME.env      User host-user specific"
    Write-Host ""
    Write-Host "LIST OPERATIONS (work for ALL variables):" -ForegroundColor Yellow
    Write-Host "  VAR+=value          Prepend to list (PATH, PERL5LIB, etc.)"
    Write-Host "  VAR=+value          Append to list"
    Write-Host "  VAR-=value          Remove from list"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    Write-Host "  .\scoop-boot.ps1 --bootstrap"
    Write-Host "  .\scoop-boot.ps1 --init-env=user.default.env"
    Write-Host "  .\scoop-boot.ps1 --apply-env --dry-run"
    Write-Host "  .\scoop-boot.ps1 --install git nodejs python"
    Write-Host ""
}

function Show-Version {
    Write-Host "scoop-boot.ps1 version $global:ScriptVersion"
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

    # Check current state
    Write-Info "Checking current state..."
    $scoopCommand = Get-Command scoop -ErrorAction SilentlyContinue

    if ($scoopCommand) {
        Write-Host "     SCOOP=$global:BaseDir"
        Write-Host "     SCOOP_GLOBAL=$global:BaseDir\global"
        Write-Warning "Scoop is already installed at: $($scoopCommand.Source)"
        Write-Host ""
        Write-Host "To reinstall, use:" -ForegroundColor Yellow
        Write-Host "  Uninstall Scoop first, then run --bootstrap again" -ForegroundColor White
        Write-Host ""
        Write-Host "To update Scoop, use:" -ForegroundColor Yellow
        Write-Host "  scoop update" -ForegroundColor White
        return $true
    }

    # Set environment variables
    Write-Info "Setting environment variables..."
    [Environment]::SetEnvironmentVariable('SCOOP', $global:BaseDir, 'User')
    [Environment]::SetEnvironmentVariable('SCOOP_GLOBAL', "$global:BaseDir\global", 'User')
    $env:SCOOP = $global:BaseDir
    $env:SCOOP_GLOBAL = "$global:BaseDir\global"
    Write-Success "Environment variables set"

    # Install Scoop
    Write-Info "Installing Scoop core..."
    $installerOutput = @()
    try {
        $scoopInstaller = Get-ScoopInstaller -OutFile "$env:TEMP\scoop-install.ps1"
        $installerOutput = & $scoopInstaller -ScoopDir $global:BaseDir -ScoopGlobalDir "$global:BaseDir\global" -NoProxy 2>&1
        Remove-Item $scoopInstaller -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-ErrorMsg "Failed to install Scoop: $_"
        return $false
    }

    # Verify installation on the file system, then on the PATH
    $scoopCore  = Join-Path $global:BaseDir "apps\scoop\current\bin\scoop.ps1"
    $scoopShims = Join-Path $global:BaseDir "shims"
    if (-not (Test-Path $scoopCore) -or -not (Test-Path $scoopShims)) {
        Write-ErrorMsg "Scoop installation verification failed"
        Write-Host "  Expected: $scoopCore" -ForegroundColor Gray
        Write-Host "  Installer output:" -ForegroundColor Gray
        foreach ($line in $installerOutput) { Write-Host "    $line" -ForegroundColor DarkGray }
        return $false
    }
    Write-Success "Scoop core installed"

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
        try {
            & scoop bucket add $bucket.Name 2>&1 | Out-Null
            Write-Success "$($bucket.Name) bucket ($($bucket.Desc))"
        }
        catch {
            Write-Warning "Failed to add $($bucket.Name) bucket"
        }
    }

    Write-Section "Bootstrap Complete!"
    # Called from scoop-complete-install.ps1: the env file is already applied and
    # the remaining steps follow in the same run, so the manual guide is noise
    if ($env:SCOOP_BOOT_CALLER -eq 'install') { return $true }
    Write-Host ""
    Write-Host "IMPORTANT: Restart your shell for PATH changes to take effect!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Close and reopen your terminal"
    Write-Host ""
    Write-Host "2. Create environment configuration:" -ForegroundColor Cyan
    Write-Host "   .\bin\scoop-boot.ps1 --init-env=user.default.env" -ForegroundColor White
    Write-Host "   .\bin\scoop-boot.ps1 --init-env=user.$(Get-Hostname).$(Get-Username).env" -ForegroundColor White
    Write-Host "   .\bin\scoop-boot.ps1 --init-env=system.default.env" -ForegroundColor White
    Write-Host "   .\bin\scoop-boot.ps1 --init-env=system.$(Get-Hostname).$(Get-Username).env" -ForegroundColor White
    Write-Host ""
    Write-Host "3. Edit the configuration file in:" -ForegroundColor Cyan
    Write-Host "   $global:EnvDir\" -ForegroundColor White
    Write-Host ""
    Write-Host "4. Apply configuration:" -ForegroundColor Cyan
    Write-Host "   .\bin\scoop-boot.ps1 --apply-env" -ForegroundColor White
    Write-Host ""
    Write-Host "5. Install applications:" -ForegroundColor Cyan
    Write-Host "   .\bin\scoop-boot.ps1 --install git nodejs python" -ForegroundColor White
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

    # Parse unset
    elseif ($Line -match '^-([A-Z_][A-Z0-9_]*)$') {
        return @{
            Type = "Unset"
            Name = $Matches[1]
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
        $expandedValue = if ($op.Value) { Expand-EnvironmentVariables -Value $op.Value } else { $null }
        if ($expandedValue -and $expandedValue -match '\$\{?[A-Z_][A-Z0-9_]*\}?') {
            Write-Warning "$($op.Name): unresolved variable reference in '$expandedValue' [$fileName]; define it earlier in the file or write the value out"
        }

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

    foreach ($file in (Get-EnvironmentFiles | Where-Object { $_.Scope -eq 'User' })) {
        $fileName = Split-Path -Leaf $file.Path
        Write-Info "Processing: $fileName"
        $operations = Read-EnvironmentFile -FilePath $file.Path
        $changes += Apply-EnvironmentOperations -Operations $operations -Scope 'User' -SourceFile $file.Path -DryRun $DryRun
    }

    if ($global:ScoopBootQuiet -and $changes -gt 0 -and -not $DryRun) {
        Write-Host "[scoop-boot] user scope cleaned ($changes change(s) after Scoop wrote to it; details in $global:ScoopBootLogFile)" -ForegroundColor DarkCyan
    }
    if ($changes -eq 0) { Write-Success "User scope is clean" }
    else { Write-Info "User scope: $changes change(s)" }
    return $changes
}

function Invoke-AsrReport {
    <#
    .SYNOPSIS
        Writes the Defender / Attack Surface Reduction configuration and the ASR blocks
        of the last 14 days to a report file, for tickets with the security team.
    #>
    Write-Section "ASR Report"
    $report = Join-Path $global:ScoopBootLogDir ("asr-report-{0}.txt" -f (Get-Date -Format 'yyyyMMdd'))
    # Defender hides rule ids and exclusion lists from non-elevated callers
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Warning "Not running as Administrator: Defender hides ASR rules and exclusion lists."
        Write-Warning "The event list below is complete; for the full report run from an elevated shell."
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
    $actionNames = @{ 0 = 'Disabled'; 1 = 'Block'; 2 = 'Audit'; 6 = 'Warn' }
    $lines = @()
    $lines += "ASR report $(Get-Date -Format s)  host=$env:COMPUTERNAME  user=$env:USERDOMAIN\$env:USERNAME  scoop-boot $global:ScriptVersion"
    $lines += "Defender AM engine $($status.AMEngineVersion), platform $($status.AMProductVersion), signatures $($status.AntivirusSignatureVersion)"
    $lines += "RealTimeProtection=$($status.RealTimeProtectionEnabled)  Tamper=$($status.IsTamperProtected)  MAPS=$($pref.MAPSReporting)  CloudBlockLevel=$($pref.CloudBlockLevel)"
    $lines += ""
    $lines += "--- ASR rules (Id, Action, Name) ---"
    $ids = @($pref.AttackSurfaceReductionRules_Ids | Where-Object { $_ }); $acts = @($pref.AttackSurfaceReductionRules_Actions)
    if ($ids.Count -eq 0) { $lines += $(if ($isAdmin) { "  (none configured)" } else { "  N/A: run as Administrator to list the rules" }) }
    for ($i = 0; $i -lt $ids.Count; $i++) {
        $id = "$($ids[$i])".ToLower()
        $act = [int]$acts[$i]
        $actName = if ($actionNames.ContainsKey($act)) { $actionNames[$act] } else { "$act" }
        $name = if ($ruleNames.ContainsKey($id)) { $ruleNames[$id] } else { '(see Microsoft docs)' }
        $lines += "{0}  {1,-8}  {2}" -f $id, $actName, $name
    }
    foreach ($section in @(
        @{ Title = 'ASR-only exclusions (AttackSurfaceReductionOnlyExclusions)'; Values = $pref.AttackSurfaceReductionOnlyExclusions },
        @{ Title = 'Per-rule exclusions (AttackSurfaceReductionRules_RuleSpecificExclusions)'; Values = $pref.AttackSurfaceReductionRules_RuleSpecificExclusions },
        @{ Title = 'Defender path exclusions (ExclusionPath)'; Values = $pref.ExclusionPath }
    )) {
        $lines += ""
        $lines += "--- $($section.Title) ---"
        $values = @($section.Values | Where-Object { $_ -and "$_" -notmatch '^N/A' })
        if ($values.Count -eq 0) { $lines += $(if ($isAdmin) { "  (none)" } else { "  N/A: run as Administrator to list the exclusions" }) }
        $lines += @($values | ForEach-Object { "  $_" })
    }
    $lines += ""
    $lines += "--- Blocked by ASR, last 14 days (event 1121) ---"
    $events = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1121; StartTime = (Get-Date).AddDays(-14) } -ErrorAction SilentlyContinue
    $lines += @($events | ForEach-Object {
        $m = $_.Message -split "`n"
        $rule = (($m | Select-String '^\s*ID:') | Select-Object -First 1).Line -replace '^\s*ID:\s*', ''
        $path = (($m | Select-String 'Path:') | Select-Object -First 1).Line.Trim()
        "{0}  rule={1}  {2}" -f $_.TimeCreated.ToString('s'), $rule.Trim(), $path
    } | Sort-Object -Unique)
    if (-not (Test-Path $global:ScoopBootLogDir)) { New-Item -ItemType Directory -Path $global:ScoopBootLogDir -Force | Out-Null }
    $lines | Set-Content -Path $report -Encoding UTF8
    $lines | ForEach-Object { Write-Host $_ }
    Write-Host ""
    Write-Success "Report written: $report"
    return $true
}

function Invoke-SelfUpdate {
    <#
    .SYNOPSIS
        Downloads the current scoop-boot scripts and the scoop wrapper from GitHub into bin\.
    .DESCRIPTION
        Only files under bin\ are replaced: the three scripts and the scoop wrapper
        (scoop.ps1, scoop.cmd, scoop). The environment files under etc\ belong to the
        user and are never touched. Previous versions go to backups\scripts-<timestamp>\.
    #>
    Write-Section "scoop-boot Update"
    $base = 'https://raw.githubusercontent.com/stotz/scoop-boot/main'
    $files = @('bin/scoop-boot.ps1', 'bin/scoop-complete-install.ps1', 'bin/scoop-complete-reset.ps1', 'bin/scoop.ps1', 'bin/scoop.cmd', 'bin/scoop')
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $global:BaseDir "backups\scripts-$stamp"
    $temp = Join-Path $env:TEMP "scoop-boot-update-$stamp"
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    $changed = 0
    foreach ($rel in $files) {
        $name = Split-Path -Leaf $rel
        $target = Join-Path $global:BaseDir ($rel -replace '/', '\')
        $download = Join-Path $temp $name
        try {
            Invoke-WebRequest -Uri "$base/$rel" -OutFile $download -UseBasicParsing
        } catch {
            Write-ErrorMsg "Download failed: $base/$rel ($($_.Exception.Message))"
            continue
        }
        $newHash = Get-FileSha256Short -Path $download
        $oldHash = if (Test-Path $target) { Get-FileSha256Short -Path $target } else { 'none' }
        $newVer = (Select-String -Path $download -Pattern 'Version:\s*([0-9.]+)' | Select-Object -First 1)
        $newVer = if ($newVer) { $newVer.Matches[0].Groups[1].Value } else { '' }
        if ($newHash -eq $oldHash) {
            Write-Host "[OK] $name unchanged ($oldHash$(if ($newVer) { ", $newVer" }))" -ForegroundColor Gray
            continue
        }
        if (Test-Path $target) {
            if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
            Copy-Item $target (Join-Path $backupDir $name) -Force
        }
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        Copy-Item $download $target -Force
        Write-Success "$name updated: $oldHash -> $newHash$(if ($newVer) { " ($newVer)" })"
        $changed++
    }
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    if ($changed -eq 0) {
        Write-Info "Everything is current"
    } else {
        Write-Info "$changed file(s) updated; previous versions in $backupDir"
        Write-Info "Environment files under etc\environments were not touched"
    }
    return $true
}

function Invoke-ApplyEnv {
    param(
        [bool]$DryRun = $false,
        [bool]$Rollback = $false
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
        Write-Host "Create a configuration file first:" -ForegroundColor Yellow
        Write-Host "  .\bin\scoop-boot.ps1 --init-env=user.default.env" -ForegroundColor White
        return
    }

    # Check admin rights for system files
    $hasSystemFiles = $envFiles | Where-Object { $_.Scope -eq "Machine" }
    if ($hasSystemFiles -and -not (Test-AdminRights)) {
        Write-ErrorMsg "System environment files require administrator privileges"
        Write-Host ""
        Write-Host "Files that require admin:" -ForegroundColor Yellow
        foreach ($file in $hasSystemFiles) {
            Write-Host "  - $(Split-Path -Leaf $file.Path)" -ForegroundColor White
        }
        Write-Host ""
        Write-Host "Run PowerShell as Administrator and try again" -ForegroundColor Yellow
        return
    }

    # Process each file. Before the Machine files, every Machine PATH entry inside
    # Scoop's subdirectories is swept so that the files rebuild the order from
    # scratch; stale entries from earlier file versions cannot survive.
    $totalChanges = 0
    if ($hasSystemFiles) {
        Write-Info "Sweeping Scoop entries from Machine PATH (rebuilt from the system.* files)"
        $totalChanges += Remove-ScoopPathEntries -Scope 'Machine' -DryRun $DryRun
    }
    foreach ($file in ($envFiles | Where-Object { $_.Scope -eq 'Machine' })) {
        $fileName = Split-Path -Leaf $file.Path
        Write-Info "Processing: $fileName"

        $operations = Read-EnvironmentFile -FilePath $file.Path
        $changes = Apply-EnvironmentOperations -Operations $operations -Scope $file.Scope -SourceFile $file.Path -DryRun $DryRun
        $totalChanges += $changes
    }

    # User scope: Scoop's overrides go, then the user.* files are applied
    $totalChanges += Invoke-CleanUserScope -DryRun $DryRun

    if ($DryRun) {
        Write-Info "DRY RUN: Would apply $totalChanges changes"
        Write-Host "Run without --dry-run to apply changes"
    } else {
        Write-Info "Applied $totalChanges changes"
        Write-Host ""
        Write-Host "IMPORTANT: Restart your shell for changes to take effect!" -ForegroundColor Yellow
        Write-Host "  - Close and reopen: CMD, PowerShell, Terminal" -ForegroundColor White
        Write-Host "  - Restart: Visual Studio, IntelliJ IDEA, VS Code" -ForegroundColor White
        Write-Host "  - Or reboot system for complete refresh" -ForegroundColor White
    }
}

# ============================================================================
# INIT ENVIRONMENT FUNCTIONS
# ============================================================================

function Invoke-InitEnv {
    param([string]$FileName)

    Write-Section "Initialize Environment Configuration"

    # Validate filename
    if ([string]::IsNullOrWhiteSpace($FileName)) {
        Write-ErrorMsg "No filename specified"
        Write-Host ""
        Write-Host "Specify a configuration file:" -ForegroundColor Yellow
        Write-Host "  --init-env=user.default.env" -ForegroundColor White
        Write-Host "  --init-env=user.$(Get-Hostname).$(Get-Username).env" -ForegroundColor White
        Write-Host "  --init-env=system.default.env" -ForegroundColor White
        Write-Host "  --init-env=system.$(Get-Hostname).$(Get-Username).env" -ForegroundColor White
        return $false
    }

    # Normalize filename to lowercase
    $FileName = $FileName.ToLower()

    # Ensure directory exists
    if (-not (Test-Path $global:EnvDir)) {
        New-Item -ItemType Directory -Path $global:EnvDir -Force | Out-Null
    }

    # Full path
    $filePath = Join-Path $global:EnvDir $FileName

    # Check if file exists
    if (Test-Path $filePath) {
        Write-Warning "File already exists: $filePath"
        Write-Host "Edit the existing file or delete it first"
        return $false
    }

    # Determine scope
    $scope = if ($FileName -match '^system\.') { "Machine" } else { "User" }

    # Download or use embedded template
    Write-Info "Creating template..."
    $templateContent = Get-EnvironmentTemplate -Scope $scope

    # Write to file
    $templateContent | Out-File -FilePath $filePath -Encoding UTF8
    Write-Success "Created: $filePath"

    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Edit the configuration file:" -ForegroundColor White
    Write-Host "   notepad `"$filePath`"" -ForegroundColor White
    Write-Host ""
    Write-Host "2. Test what changes would be applied:" -ForegroundColor White
    Write-Host "   .\bin\scoop-boot.ps1 --apply-env --dry-run" -ForegroundColor White
    Write-Host ""
    Write-Host "3. Apply the configuration:" -ForegroundColor White
    if ($scope -eq "Machine") {
        Write-Host "   # Run as Administrator!" -ForegroundColor Yellow
    }
    Write-Host "   .\bin\scoop-boot.ps1 --apply-env" -ForegroundColor White

    return $true
}

function Get-EnvironmentTemplate {
    param([string]$Scope)

    # Try to download from GitHub
    try {
        Write-Info "Downloading template from GitHub..."
        $template = Invoke-WebRequest -Uri $global:TemplateUrl -UseBasicParsing
        return $template.Content
    }
    catch {
        Write-Warning "Could not download template, using embedded version"
    }

    # Embedded template
    $hostname = Get-Hostname
    $username = Get-Username
    $date = Get-Date -Format "yyyy-MM-dd"

    return @"
# ============================================================================
# Environment Configuration Template
# File: $(if ($Scope -eq 'Machine') { 'system' } else { 'user' }).$hostname.$username.env
# ============================================================================
# Created: $date
# Scope: $Scope $(if ($Scope -eq 'Machine') { '(requires admin)' } else { '' })
# SCOOP: $global:BaseDir
# Hostname: $hostname
# Username: $username
# ============================================================================
# SYNTAX:
#   VAR=value           Set variable
#   VAR+=value          Prepend to list (works for ALL variables)
#   VAR=+value          Append to list (works for ALL variables)
#   VAR-=value          Remove from list (works for ALL variables)
#   -VAR                Unset variable
#   # Comment           Lines starting with # are ignored
#
# LIST VARIABLES:
#   PATH, PERL5LIB, PYTHONPATH, CLASSPATH, PSModulePath, PATHEXT, etc.
#   All use semicolon (;) as separator
#
# VARIABLE EXPANSION:
#   `$SCOOP              Expands to Scoop directory
#   `$USERPROFILE        Expands to user profile directory
#   `$JAVA_HOME          Expands to any environment variable
# ============================================================================

# ============================================================================
# PATH MANAGEMENT
# ============================================================================

# Remove old/duplicate entries first (cleanup)
#PATH-=C:\old\path\to\remove

# Core paths (highest priority - added last)
PATH+=`$SCOOP\bin
PATH+=`$SCOOP\shims

# ============================================================================
# DEVELOPMENT TOOLS
# ============================================================================

# --- Java Development ---
#JAVA_HOME=`$SCOOP\apps\temurin25-jdk\current
#PATH+=`$JAVA_HOME\bin
#JAVA_OPTS=-Xmx2g -Xms512m -XX:+UseG1GC
#CLASSPATH=.
#CLASSPATH+=`$JAVA_HOME\lib\tools.jar

# --- Python Development ---
#PYTHON_HOME=`$SCOOP\apps\python314\current
#PATH+=`$PYTHON_HOME
#PATH+=`$PYTHON_HOME\Scripts
#PYTHONPATH=`$PYTHON_HOME\Lib\site-packages
#PYTHONPATH+=`$USERPROFILE\python\libs

# --- Perl Development ---
#PERL_HOME=`$SCOOP\apps\perl\current
#PATH+=`$PERL_HOME\perl\bin
#PATH+=`$PERL_HOME\perl\site\bin
#PERL5LIB=`$PERL_HOME\perl\lib
#PERL5LIB+=`$PERL_HOME\perl\site\lib
#PERL5LIB+=`$USERPROFILE\perl5\lib

# --- Node.js Development ---
#NODE_HOME=`$SCOOP\apps\nodejs\current
#PATH+=`$NODE_HOME
#NODE_PATH=`$NODE_HOME\node_modules
#NPM_CONFIG_PREFIX=`$SCOOP\persist\nodejs

# --- Go Development ---
#GOROOT=`$SCOOP\apps\go\current
#GOPATH=`$USERPROFILE\go
#PATH+=`$GOROOT\bin
#PATH+=`$GOPATH\bin

# --- Rust Development ---
#CARGO_HOME=`$USERPROFILE\.cargo
#RUSTUP_HOME=`$USERPROFILE\.rustup
#PATH+=`$CARGO_HOME\bin

# --- Ruby Development ---
#RUBY_HOME=`$SCOOP\apps\ruby\current
#PATH+=`$RUBY_HOME\bin
#GEM_HOME=`$USERPROFILE\.gem

# ============================================================================
# BUILD TOOLS
# ============================================================================

# --- Maven ---
#MAVEN_HOME=`$SCOOP\apps\maven\current
#PATH+=`$MAVEN_HOME\bin
#M2_HOME=`$MAVEN_HOME
#MAVEN_OPTS=-Xmx1024m

# --- Gradle ---
#GRADLE_HOME=`$SCOOP\apps\gradle\current
#PATH+=`$GRADLE_HOME\bin
#GRADLE_USER_HOME=`$USERPROFILE\.gradle

# --- CMake ---
#CMAKE_HOME=`$SCOOP\apps\cmake\current
#PATH+=`$CMAKE_HOME\bin

# ============================================================================
# MSYS2/MinGW (if needed)
# ============================================================================
# Place early for low priority (specific tools override)

#MSYS2_HOME=`$SCOOP\apps\msys2\current
#PATH+=`$MSYS2_HOME\usr\bin
#PATH+=`$MSYS2_HOME\mingw64\bin

# ============================================================================
# VERSION CONTROL
# ============================================================================

#GIT_HOME=`$SCOOP\apps\git\current
#PATH+=`$GIT_HOME\cmd
#GIT_SSH=`$SCOOP\apps\openssh\current\ssh.exe

#SVN_HOME=`$SCOOP\apps\tortoisesvn\current
#PATH+=`$SVN_HOME\bin

# ============================================================================
# LOCALE & ENCODING
# ============================================================================

#LANG=en_US.UTF-8
#LC_ALL=en_US.UTF-8

# ============================================================================
# POWERSHELL MODULES
# ============================================================================

#PSModulePath+=`$USERPROFILE\Documents\PowerShell\Modules
#PSModulePath+=`$SCOOP\modules

# ============================================================================
# NOTES
# ============================================================================
# 1. Uncomment lines you need
# 2. Adjust paths to match your Scoop installations
# 3. Use += to add to PATH and other list variables
# 4. Use -= to remove old entries
# 5. Order matters: later entries have higher priority in PATH
"@
}

# ============================================================================
# STATUS FUNCTIONS
# ============================================================================

function Show-Status {
    Write-Section "Scoop Boot Status"

    Write-Host ""
    Write-Host "Environment:" -ForegroundColor Yellow
    Write-Host "  SCOOP: $(if ($env:SCOOP) { $env:SCOOP } else { 'Not set' })"
    Write-Host "  SCOOP_GLOBAL: $(if ($env:SCOOP_GLOBAL) { $env:SCOOP_GLOBAL } else { 'Not set' })"
    Write-Host ""

    Write-Host "Scoop:" -ForegroundColor Yellow
    $scoopCommand = Get-Command scoop -ErrorAction SilentlyContinue
    if ($scoopCommand) {
        Write-Host "  Status: Installed"
        Write-Host "  Location: $($scoopCommand.Source)"

        # Get Scoop apps
        try {
            $apps = & scoop list 2>$null
            if ($apps) {
                $appCount = ($apps | Measure-Object).Count - 1  # Subtract header
                Write-Host "  Apps: $appCount installed"
            }
        } catch {}
    } else {
        Write-Host "  Status: Not installed"
        Write-Host "  Run: .\bin\scoop-boot.ps1 --bootstrap"
    }
    Write-Host ""

    Write-Host "Configuration:" -ForegroundColor Yellow
    $envFiles = Get-EnvironmentFiles
    if ($envFiles.Count -gt 0) {
        Write-Host "  Files found: $($envFiles.Count)"
        foreach ($file in $envFiles) {
            $fileName = Split-Path -Leaf $file.Path
            Write-Host "    - $fileName (Scope: $($file.Scope))"
        }
    } else {
        Write-Host "  No configuration files"
        Write-Host "  Run: .\bin\scoop-boot.ps1 --init-env=user.default.env"
    }
    Write-Host ""
}

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
    $script:OriginalWriteDryRun = ${function:Write-DryRun}

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
        $testArgs = @("--install", "app1", "app2", "--dry-run")
        $savedArgs = $global:ParsedArgs.Clone()
        $global:ParsedArgs = @{Install = @(); DryRun = $false}
        Parse-Arguments -Arguments $testArgs
        $test.Result = $global:ParsedArgs.Install.Count -eq 2 -and $global:ParsedArgs.DryRun -eq $true
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
        $test.Result = $filename -match "^system\.[a-z0-9\-]+\.[a-z0-9\-]+\.env$"
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
# SUGGEST & ENVIRONMENT FUNCTIONS
# ============================================================================

function Show-Suggest {
    Write-Section "Suggested Applications"

    Write-Host ""
    Write-Host "Essential Development Tools:" -ForegroundColor Yellow
    Write-Host "  git          - Version control"
    Write-Host "  nodejs       - JavaScript runtime"
    Write-Host "  python       - Python programming"
    Write-Host "  openjdk      - Java development kit"
    Write-Host "  go           - Go programming language"
    Write-Host "  rust         - Rust programming language"
    Write-Host ""

    Write-Host "Editors & IDEs:" -ForegroundColor Yellow
    Write-Host "  vscode       - Visual Studio Code"
    Write-Host "  neovim       - Advanced text editor"
    Write-Host "  notepadplusplus - Text editor"
    Write-Host ""

    Write-Host "Build Tools:" -ForegroundColor Yellow
    Write-Host "  maven        - Java build tool"
    Write-Host "  gradle       - Build automation"
    Write-Host "  cmake        - Cross-platform build"
    Write-Host "  make         - GNU Make"
    Write-Host ""

    Write-Host "Databases:" -ForegroundColor Yellow
    Write-Host "  postgresql   - PostgreSQL database"
    Write-Host "  mysql        - MySQL database"
    Write-Host "  mongodb      - NoSQL database"
    Write-Host "  redis        - In-memory data store"
    Write-Host ""

    Write-Host "Install example:" -ForegroundColor Cyan
    Write-Host "  .\bin\scoop-boot.ps1 --install git nodejs python vscode" -ForegroundColor White
    Write-Host ""
}

function Show-Environment {
    Write-Section "Current Environment Variables"

    $vars = @(
        "SCOOP", "SCOOP_GLOBAL",
        "PATH",
        "JAVA_HOME", "JAVA_OPTS", "CLASSPATH",
        "PYTHON_HOME", "PYTHONPATH",
        "PERL_HOME", "PERL5LIB",
        "NODE_HOME", "NODE_PATH", "NPM_CONFIG_PREFIX",
        "GOROOT", "GOPATH",
        "CARGO_HOME", "RUSTUP_HOME",
        "RUBY_HOME", "GEM_HOME",
        "MAVEN_HOME", "M2_HOME", "GRADLE_HOME",
        "CMAKE_HOME", "MAKE_HOME",
        "GIT_HOME", "SVN_HOME",
        "MSYS2_HOME",
        "PSModulePath"
    )

    Write-Host ""
    foreach ($var in $vars) {
        $value = [Environment]::GetEnvironmentVariable($var, "Machine")
        if ([string]::IsNullOrEmpty($value)) {
            $value = [Environment]::GetEnvironmentVariable($var, "User")
        }
        if ([string]::IsNullOrEmpty($value)) {
            $value = [Environment]::GetEnvironmentVariable($var, "Process")
        }

        if (![string]::IsNullOrEmpty($value)) {
            Write-Host "$var`:" -ForegroundColor Yellow
            if ($var -eq "PATH" -or $var -like "*PATH*" -or $var -like "*LIB*") {
                $paths = $value -split ';'
                foreach ($path in $paths) {
                    if (![string]::IsNullOrEmpty($path)) {
                        Write-Host "  $path" -ForegroundColor Gray
                    }
                }
            } else {
                Write-Host "  $value" -ForegroundColor White
            }
            Write-Host ""
        }
    }
}

# ============================================================================
# INSTALL FUNCTION
# ============================================================================

function Invoke-Install {
    param([string[]]$Apps)

    Write-Section "Install Applications"

    if ($Apps.Count -eq 0) {
        Write-Warning "No applications specified"
        Write-Host ""
        Write-Host "Example:" -ForegroundColor Yellow
        Write-Host "  .\bin\scoop-boot.ps1 --install git nodejs python" -ForegroundColor White
        return
    }

    # Check if Scoop is installed
    $scoopCommand = Get-Command scoop -ErrorAction SilentlyContinue
    if (-not $scoopCommand) {
        Write-ErrorMsg "Scoop is not installed"
        Write-Host ""
        Write-Host "Install Scoop first:" -ForegroundColor Yellow
        Write-Host "  .\bin\scoop-boot.ps1 --bootstrap" -ForegroundColor White
        return
    }

    Write-Info "Installing $($Apps.Count) application(s)..."
    Write-Host ""

    foreach ($app in $Apps) {
        Write-Host "Installing: $app" -ForegroundColor White
        try {
            & scoop install $app
            Write-Success "Installed: $app"
        }
        catch {
            Write-ErrorMsg "Failed to install: $app"
        }
        Write-Host ""
    }

    Write-Info "Installation complete"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Library mode: the caller only wanted the functions
if ($script:LibraryOnly) { return }

if ($args -contains '--quiet') { $global:ScoopBootQuiet = $true }
Initialize-ScoopBootLog -ScriptName 'scoop-boot.ps1' -Version $global:ScriptVersion -ScriptPath $PSCommandPath -Arguments $args

# Parse arguments
Parse-Arguments -Arguments $args

# Handle commands
if ($global:ParsedArgs.Help) {
    Show-Help
    exit 0
}

if ($global:ParsedArgs.Version) {
    Show-Version
    exit 0
}

if ($global:ParsedArgs.Bootstrap) {
    $success = Invoke-Bootstrap
    exit $(if ($success) { 0 } else { 1 })
}

if ($global:ParsedArgs.Status) {
    Show-Status
    exit 0
}

if ($global:ParsedArgs.SelfTest) {
    $success = Test-ScoopBoot
    exit $(if ($success) { 0 } else { 1 })
}

if ($global:ParsedArgs.Suggest) {
    Show-Suggest
    exit 0
}

if ($global:ParsedArgs.Environment) {
    Show-Environment
    exit 0
}

if ($global:ParsedArgs.EnvStatus) {
    Invoke-EnvStatus
    exit 0
}

if ($null -ne $global:ParsedArgs.InitEnv) {
    $success = Invoke-InitEnv -FileName $global:ParsedArgs.InitEnv
    exit $(if ($success) { 0 } else { 1 })
}

if ($global:ParsedArgs.ApplyEnv) {
    Invoke-ApplyEnv -DryRun $global:ParsedArgs.DryRun -Rollback $global:ParsedArgs.Rollback
    exit 0
}

if ($global:ParsedArgs.CleanUserScope) {
    $null = Invoke-CleanUserScope -DryRun $global:ParsedArgs.DryRun
    exit 0
}

if ($global:ParsedArgs.AsrReport) {
    if (Invoke-AsrReport) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.Update) {
    if (Invoke-SelfUpdate) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.Install.Count -gt 0) {
    Invoke-Install -Apps $global:ParsedArgs.Install
    exit 0
}

# If no command specified, show status
if ($args.Count -eq 0) {
    Show-Status
    exit 0
}

Write-ErrorMsg "No valid command specified"
Show-Help
exit 1
