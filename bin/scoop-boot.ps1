<#
.SYNOPSIS
    Bootstrap script for portable Windows development environments using Scoop package manager.

.DESCRIPTION
    scoop-boot.ps1 v1.17.0 - Portable Windows Development Environment Bootstrap

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
    Version: 1.17.0
    Author: System Administrator
    Requires: PowerShell 5.1 or higher

    Changes in v1.17.0:
    - --platform-report replaces --asr-report (kept as alias): the Defender/ASR
      part as before, plus the user profile (FSLogix profile container: policy,
      container path, fill level, redirections.xml exclusions), TMP in process,
      User and Machine scope, the developer caches inside the profile with their
      sizes, and FSLogix container errors. A Findings block at the end names
      what the platform team has to change (ASR rule 01443614 without exclusion
      for C:\usr, blocks on developer files, container without developer-cache
      exclusions, container over 80 percent, SetTempToLocalPath, a User-scope
      TMP override); with findings the exit code is 1. Report file
      logs\scoopboot\platform-report-<date>.txt. Read-only, works without
      elevation except for the Defender rule and exclusion lists
    - Template: the cache section describes FSLogix correctly (the container is
      attached, not copied; the costs are the size limit and network I/O)

    Changes in v1.16.0:
    - The library moved to bin\scoop-boot.psm1 (logging, environment files,
      package list, bootstrap, setup commands, self-tests). scoop-boot.ps1 is
      the command line: it imports the module into its own scope (nothing leaks
      into the calling shell) and dispatches. The helper scripts import the
      module instead of dot-sourcing this file; the library mode
      ($global:ScoopBootLibraryOnly) is gone
    - Rescue path: --update, --version and --help run without the module. A
      module that does not load prints the error and the way out (--update);
      every other command stops there
    - --update also delivers bin\scoop-boot.psm1; self-test 37 scans both files
      for uninitialised globals, self-test 38 compares the script's version with
      the module's
    - --bootstrap passes -RunAsAdmin to the Scoop installer when the shell is
      elevated (the installer refuses otherwise)
    - Stage 2: the installation (Set-DevelopmentEnvironment, Install-ScoopTools,
      Show-PackageList) and the reset (Invoke-ScoopReset) are module functions;
      scoop-complete-install.ps1 and scoop-complete-reset.ps1 are gone, --update
      moves leftover copies to the backup directory. These functions keep the
      shell defaults they were written for (no strict mode, Continue) until
      they get tests. The log context carries the command
      ("scoop-boot.ps1 --user-install (1.16.0)")
    - --user-install --force skips the question in an elevated shell (an account
      that is a local administrator and has elevated shells only)
    - Window title shows the progress of --user-install, --bootstrap and
      --admin-reset ("scoop-boot [12/74] kotlin", "scoop-boot [72/74] gcc",
      "scoop-boot reset apps"); the counter runs over the packages and the four
      post-install stages; the previous title is restored at the end
    - --admin-init fills in hostname, user name, file name and creation date in
      the header of the environment files it creates. The system template keeps
      CUSTOM above CORE PATHS (a PATH+= in CUSTOM landed in front of bin and shims)
    - --admin-reset prints the image path of processes it leaves running

    Changes in v1.15.0:
    - One version for all three scripts: scoop-complete-install.ps1 (was 2.11.0)
      and scoop-complete-reset.ps1 (was 2.6.0) carry 1.15.0 from now on
    - Variable expansion resolves NAME=value definitions of the .env files first,
      wherever the line stands (USR=C:\usr at the bottom, $USR above it works on a
      fresh machine and in --dry-run); $$ is a literal $; self-tests 34 to 36.
      The system template defines the base directories on top and uses $USR
    - --admin-reset [--force] [--keep-persist] runs scoop-complete-reset.ps1 with
      an admin check first; --list-packages runs the install script's -ListPackages;
      the two helper scripts no longer appear in the user documentation; --self-test accepted next to --selfTest; help text
      grouped by purpose, --rollback no longer listed (it does nothing)
    - --update keeps the newest five backups\scripts-* directories (they
      accumulated before, and the reset's retention tripped over them)
    - FIX --admin-setenv, --user-install, --admin-reset, --list-packages ran the
      helper scripts under this script's $ErrorActionPreference = Stop; a
      manifest's Write-Error (Wireshark post_install) aborted Phase 2 at package
      39 of 62. The entry points now run them with Continue
    - FIX "-NAME" (unset) aborted --apply-env under Set-StrictMode: the parsed
      operation had no Value key. Self-test 39
    - FIX --dry-run failed under Set-StrictMode ("$global:SuppressDryRunOutput
      cannot be retrieved") unless --selfTest had run in the same session; the
      flag is now initialised. Self-test 37 checks every $global: name
    - --branch=NAME is remembered in etc\scoop-boot.branch; --update and
      --admin-init without the switch use it (--branch=main forgets it). Before,
      --admin-init on a test machine silently downloaded main over the branch
    - --bootstrap resumes when the Scoop core exists: the installer is skipped,
      the essential tools are still checked (a run stopped by endpoint security
      at 7z.exe can be repeated once the binary is allowed or pinned). Its
      standalone "Next steps" name the setup commands
    - FIX --bootstrap: the official installer refused to run ("Scoop is already
      installed") because it found the scoop wrapper in bin\ on the PATH; bin\ and
      shims\ are removed from the process PATH while the installer runs. Only
      visible since --admin-init delivers the wrapper before Scoop exists
    - FIX --bootstrap took the scoop wrapper in bin\ for an installed Scoop
      (Get-Command scoop); after a reset that would have skipped the Scoop
      install. Now checks apps\scoop\current\bin\scoop.ps1
    - FIX self-test 8: user names with a dot (urs.stotz) failed the file name
      pattern; the files themselves always worked
    - Setup entry points: --admin-init (directories, --update, environment files
      from the templates, Notepad), --admin-setenv (Phase 1) and --user-install
      (Phase 2) call scoop-complete-install.ps1; the Quick Setup no longer names it
    - Package lists: etc\packages\default.txt (delivered) or etc\packages\<host>.txt
      (yours, replaces default.txt). Library functions Get-PackageListFile,
      Read-PackageList, Get-ManifestAppName; self-tests 31 to 33
    - --update also delivers etc\packages\default.txt, warns when the local copy
      was edited (hash recorded in default.txt.sha256); --branch=NAME downloads
      from a branch for testing

    Changes in v1.14.2:
    - Write-Warning prints "[WARN]" instead of "[!]": the log level detection and
      the --quiet filter only know [WARN], so warnings were logged as INFO and
      hidden by the wrapper

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

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Validate PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5 -or
    ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Host "ERROR: PowerShell 5.1 or higher required" -ForegroundColor Red
    Write-Host "Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# MODULE
# ============================================================================
# The library lives in scoop-boot.psm1 next to this file. It is imported into this
# script's scope only (-Scope Local): the Write-Host override and the other
# functions are visible to this script and to the helper scripts it calls, and
# gone when it ends, so nothing leaks into the calling shell.
#
# Rescue path: --update, --version and --help must work when the module does not
# load (syntax error after a bad download, file missing), otherwise a broken
# module could never be replaced. The few things --update needs are defined here
# as fallbacks when the import fails; the module's versions win when it loads.

$global:ScriptVersion = "1.17.0"
$global:BaseDir = Split-Path -Parent $PSScriptRoot
$global:BranchFile = Join-Path $global:BaseDir "etc\scoop-boot.branch"
if (-not (Test-Path variable:global:ScoopBootQuiet)) { $global:ScoopBootQuiet = $false }

$script:ModulePath = Join-Path $PSScriptRoot 'scoop-boot.psm1'
$script:ModuleLoaded = $false
$script:ModuleError = ''
try {
    Import-Module $script:ModulePath -Scope Local -Force -DisableNameChecking -ErrorAction Stop
    $script:ModuleLoaded = $true
} catch {
    $script:ModuleError = $_.Exception.Message
}

if (-not $script:ModuleLoaded) {
    function Write-Section { param([string]$Title) Microsoft.PowerShell.Utility\Write-Host "`n=== $Title ===" -ForegroundColor Cyan }
    function Write-Info { param([string]$Message) Microsoft.PowerShell.Utility\Write-Host ">>> $Message" -ForegroundColor Cyan }
    function Write-Success { param([string]$Message) Microsoft.PowerShell.Utility\Write-Host "[OK] $Message" -ForegroundColor Green }
    function Write-Warning { param([string]$Message) Microsoft.PowerShell.Utility\Write-Host "[WARN] $Message" -ForegroundColor Yellow }
    function Write-ErrorMsg { param([string]$Message) Microsoft.PowerShell.Utility\Write-Host "[ERROR] $Message" -ForegroundColor Red }
    function Get-FileSha256Short { param([string]$Path) try { return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.Substring(0, 8).ToLower() } catch { return 'unknown' } }
    function Get-Hostname { return [System.Net.Dns]::GetHostName().ToLower() }
}

# ============================================================================
# COMMANDS THAT MUST WORK WITHOUT THE MODULE (update) AND THEIR CALLERS
# ============================================================================

function Get-UpdateBranch {
    <#
    .SYNOPSIS
        Resolves the branch for downloads: an explicit --branch=NAME wins and is
        remembered in etc\scoop-boot.branch (removed again for main); without it the
        remembered branch is used; without that, main.
    #>
    param(
        [string]$Requested = ''
    )
    if ($Requested) {
        if ($Requested -eq 'main') {
            if (Test-Path $global:BranchFile) {
                Remove-Item $global:BranchFile -Force
                Write-Info "Back on main; $global:BranchFile removed"
            }
        } else {
            $dir = Split-Path -Parent $global:BranchFile
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Set-Content -Path $global:BranchFile -Value $Requested -Encoding ASCII
        }
        return $Requested
    }
    if (Test-Path $global:BranchFile) {
        $saved = (Get-Content $global:BranchFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($saved -and $saved.Trim()) { return $saved.Trim() }
    }
    return 'main'
}

function Invoke-AdminInit {
    <#
    .SYNOPSIS
        Setup step 1 (Administrator): directories, scripts, environment files.
    .DESCRIPTION
        Creates C:\usr\bin, C:\usr\etc\environments, C:\usr\etc\packages, C:\tmp,
        C:\devl and C:\data, runs --update (scripts, scoop wrapper, package list),
        writes system.<host>.<user>.env and user.<host>.<user>.env from the templates
        when they do not exist yet, and opens the system file in Notepad. Running it
        again changes nothing that already exists.
    #>
    param(
        [string]$Branch = ''
    )
    Write-Section "Setup 1: Initialize"
    if (-not (Test-AdminRights)) {
        Write-ErrorMsg "--admin-init needs an elevated shell (Run as Administrator)"
        return $false
    }
    # C:\devl (repositories) and C:\data (data, optional tool caches) are not used by
    # scoop-boot; they are the conventional places the environment file refers to.
    foreach ($dir in @((Join-Path $global:BaseDir 'bin'), $global:EnvDir, $global:PackagesDir, 'C:\tmp', 'C:\devl', 'C:\data')) {
        if (Test-Path $dir) {
            Write-Host "[OK] Directory exists: $dir" -ForegroundColor Gray
        } else {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Success "Directory created: $dir"
        }
    }

    if (-not (Invoke-SelfUpdate -Branch $Branch)) { return $false }
    $Branch = Get-UpdateBranch

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $base = "https://raw.githubusercontent.com/stotz/scoop-boot/$Branch"
    $envName = "{0}.{1}.env" -f (Get-Hostname), (Get-Username)
    $systemFile = Join-Path $global:EnvDir "system.$envName"
    foreach ($scope in @('system', 'user')) {
        $target = Join-Path $global:EnvDir "$scope.$envName"
        if (Test-Path $target) {
            Write-Host "[OK] Environment file exists, kept: $target" -ForegroundColor Gray
            continue
        }
        try {
            $templateUri = "$base/etc/environments/$scope.hostname.username.env"
            $template = (Invoke-WebRequest -Uri $templateUri -UseBasicParsing).Content
            # The template header carries placeholders; the file gets this machine's values
            $content = $template -replace '<hostname>', (Get-Hostname) -replace '<username>', (Get-Username)
            $content = $content -replace "(?m)^# File: $scope\.hostname\.username\.env\s*$", "# File: $scope.$envName"
            $content = $content -replace '(?m)^# Created: .*$', "# Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm') by scoop-boot.ps1 --admin-init ($Branch)"
            # UTF-8 without BOM, line endings as in the repository (LF)
            [IO.File]::WriteAllText($target, $content, (New-Object Text.UTF8Encoding($false)))
            Write-Success "Environment file created from template: $target"
        } catch {
            Write-ErrorMsg "Download failed: $base/etc/environments/$scope.hostname.username.env ($($_.Exception.Message))"
            return $false
        }
    }

    Write-Host ""
    Write-Info "Review paths and tool versions in the system file, save, then run: scoop-boot.ps1 --admin-setenv"
    # Full path on purpose: once Git is installed, its usr\bin holds an extensionless
    # script named "notepad" that PowerShell would hand to ShellExecute.
    Start-Process -FilePath "$env:SystemRoot\System32\notepad.exe" -ArgumentList "`"$systemFile`""
    return $true
}


function Invoke-SelfUpdate {
    <#
    .SYNOPSIS
        Downloads the current scoop-boot scripts and the scoop wrapper from GitHub into bin\.
    .DESCRIPTION
        Replaced: scoop-boot.ps1, scoop-boot.psm1 and the scoop wrapper (scoop.ps1, scoop.cmd, scoop)
        under bin\, and etc\packages\default.txt. The environment files and any
        etc\packages\<host>.txt belong to the user and are never touched. Previous
        versions go to backups\scripts-<timestamp>\. A locally edited default.txt is
        reported before it is replaced (its hash is recorded in default.txt.sha256).
    .PARAMETER Branch
        Git branch to download from, for testing a branch on one machine:
        --update --branch=feature/xyz. Remembered in etc\scoop-boot.branch until
        --update --branch=main; without the switch the remembered branch, else main.
    #>
    param(
        [string]$Branch = ''
    )
    Write-Section "scoop-boot Update"
    $Branch = Get-UpdateBranch -Requested $Branch
    $base = "https://raw.githubusercontent.com/stotz/scoop-boot/$Branch"
    if ($Branch -ne 'main') { Write-Warning "Downloading from branch '$Branch', not from main (remembered in $global:BranchFile; back with --update --branch=main)" }
    $files = @('bin/scoop-boot.ps1', 'bin/scoop-boot.psm1', 'bin/scoop.ps1', 'bin/scoop.cmd', 'bin/scoop', 'etc/packages/default.txt')
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
        # default.txt: warn when the local copy differs from the version last delivered
        $hashFile = "$target.sha256"
        if ($rel -eq 'etc/packages/default.txt' -and (Test-Path $target) -and (Test-Path $hashFile)) {
            $delivered = (Get-Content $hashFile -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($delivered -and $delivered.Trim() -ne $oldHash) {
                Write-Warning "$name was edited locally; the edited copy is in $backupDir"
                Write-Warning "Keep local changes in etc\packages\$(Get-Hostname).txt instead, it replaces default.txt and is never updated"
            }
        }
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        Copy-Item $download $target -Force
        if ($rel -eq 'etc/packages/default.txt') { Set-Content -Path $hashFile -Value $newHash -Encoding ASCII }
        Write-Success "$name updated: $oldHash -> $newHash$(if ($newVer) { " ($newVer)" })"
        $changed++
    }
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    # Files of earlier releases that no longer exist: moved to the backup directory
    foreach ($rel in @('bin/scoop-complete-install.ps1', 'bin/scoop-complete-reset.ps1')) {
        $obsolete = Join-Path $global:BaseDir ($rel -replace '/', '\')
        if (Test-Path $obsolete) {
            if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
            Move-Item $obsolete (Join-Path $backupDir (Split-Path -Leaf $rel)) -Force
            Write-Success "$(Split-Path -Leaf $rel) removed (part of scoop-boot.psm1 since 1.16.0); copy in $backupDir"
            $changed++
        }
    }
    # Keep the newest five scripts-* backups; the reset prunes its own snapshots the same way
    Get-ChildItem -Path (Join-Path $global:BaseDir 'backups') -Directory -Filter 'scripts-*' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $backupDir } | Sort-Object Name -Descending | Select-Object -Skip 4 |
        ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    if ($changed -eq 0) {
        Write-Info "Everything is current"
    } else {
        Write-Info "$changed file(s) updated; previous versions in $backupDir"
        Write-Info "Environment files under etc\environments and host package lists were not touched"
    }
    return $true
}


# ============================================================================
# MAIN EXECUTION
# ============================================================================

if ($args -contains '--quiet') { $global:ScoopBootQuiet = $true }
$rescueOnly = @($args | Where-Object { $_ -match '^--(update|version|v|help|h|branch=.+)$' -or $_ -match '^-[vh]$' }).Count -eq @($args).Count -and @($args).Count -gt 0

if (-not $script:ModuleLoaded) {
    # Rescue mode: no logging, no banner from the module, only the commands that
    # can put a working module back
    Microsoft.PowerShell.Utility\Write-Host "scoop-boot.ps1 $global:ScriptVersion (sha256 $(Get-FileSha256Short -Path $PSCommandPath)) | module not loaded" -ForegroundColor DarkCyan
    Microsoft.PowerShell.Utility\Write-Host "[ERROR] $script:ModulePath did not load: $script:ModuleError" -ForegroundColor Red
    if (-not $rescueOnly) {
        Microsoft.PowerShell.Utility\Write-Host "        Only --update, --version and --help work until the module is replaced. Run: scoop-boot.ps1 --update" -ForegroundColor Yellow
        exit 1
    }
    if ($args -contains '--version' -or $args -contains '-v') { Microsoft.PowerShell.Utility\Write-Host "scoop-boot.ps1 version $global:ScriptVersion"; exit 0 }
    if ($args -contains '--help' -or $args -contains '-h') {
        Microsoft.PowerShell.Utility\Write-Host "Usage: scoop-boot.ps1 --update [--branch=NAME]   (replaces bin\scoop-boot.psm1 and the scripts; full help once the module loads)"
        exit 0
    }
    $branch = ''
    foreach ($a in $args) { if ($a -match '^--branch=(.+)$') { $branch = $Matches[1] } }
    if (Invoke-SelfUpdate -Branch $branch) { exit 0 } else { exit 1 }
}

# The command goes into the log context ("scoop-boot.ps1 --user-install (1.16.0)")
$logMode = @($args | Where-Object { $_ -match '^--' -and $_ -notmatch '^--(quiet|dry-run|force|keep-persist|branch=)' } | Select-Object -First 1)
Initialize-ScoopBootLog -ScriptName 'scoop-boot.ps1' -Version $global:ScriptVersion -Mode "$logMode" -ScriptPath $PSCommandPath -Arguments $args

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
    $savedTitle = Get-ScoopBootTitle
    try {
        $success = Invoke-Bootstrap
    } finally {
        Restore-ScoopBootTitle -Saved $savedTitle
    }
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
    if (Invoke-ApplyEnv -DryRun $global:ParsedArgs.DryRun -Rollback $global:ParsedArgs.Rollback) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.CleanUserScope) {
    $null = Invoke-CleanUserScope -DryRun $global:ParsedArgs.DryRun
    exit 0
}

if ($global:ParsedArgs.PlatformReport) {
    # exit 1 when the report lists findings, so the command can gate a setup
    if (Invoke-PlatformReport) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.Update) {
    if (Invoke-SelfUpdate -Branch $global:ParsedArgs.Branch) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.AdminInit) {
    if (Invoke-AdminInit -Branch $global:ParsedArgs.Branch) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.AdminSetEnv) {
    if (Invoke-AdminSetEnv) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.UserInstall) {
    if (Invoke-UserInstall -Force $global:ParsedArgs.Force) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.ListPackages) {
    if (Invoke-ListPackages) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.AdminReset) {
    if (Invoke-AdminReset -Force $global:ParsedArgs.Force -KeepPersist $global:ParsedArgs.KeepPersist) { exit 0 } else { exit 1 }
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
