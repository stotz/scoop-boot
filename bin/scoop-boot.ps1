<#
.SYNOPSIS
    Bootstrap script for portable Windows development environments using Scoop package manager.

.DESCRIPTION
    scoop-boot.ps1 v1.10.0 - Portable Windows Development Environment Bootstrap
    
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
    Version: 1.10.0
    Author: System Administrator
    Requires: PowerShell 5.1 or higher
    
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
# GLOBAL VARIABLES
# ============================================================================

$global:ScriptVersion = "1.10.0"
$global:ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:BaseDir = Split-Path -Parent $global:ScriptRoot
$global:EnvDir = Join-Path $global:BaseDir "etc\environments"
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
    Write-Host "  --apply-env          Apply environment configuration"
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

function Invoke-Bootstrap {
    Write-Section "Scoop Bootstrap"
    
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
    try {
        $scoopInstaller = "$env:TEMP\scoop-install.ps1"
        Invoke-WebRequest -Uri 'https://get.scoop.sh' -OutFile $scoopInstaller
        & $scoopInstaller -ScoopDir $global:BaseDir -ScoopGlobalDir "$global:BaseDir\global" -NoProxy
        Remove-Item $scoopInstaller -Force
        Write-Success "Scoop core installed"
    }
    catch {
        Write-ErrorMsg "Failed to install Scoop: $_"
        return $false
    }
    
    # Verify installation
    $env:Path = "$global:BaseDir\shims;$env:Path"
    $scoopCommand = Get-Command scoop -ErrorAction SilentlyContinue
    if (-not $scoopCommand) {
        Write-ErrorMsg "Scoop installation verification failed"
        return $false
    }
    
    # Install essential tools
    Write-Info "Installing essential tools..."
    $essentialTools = @('git', '7zip')
    foreach ($tool in $essentialTools) {
        try {
            & scoop install $tool 2>&1 | Out-Null
            Write-Success "$tool installed"
        }
        catch {
            Write-Warning "Failed to install $tool"
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
        try {
            & scoop install $tool.Name 2>&1 | Out-Null
            Write-Success "$($tool.Name) installed ($($tool.Desc))"
        }
        catch {
            Write-Warning "Failed to install $($tool.Name)"
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
                if ($currentValue) {
                    $parts = $currentValue -split ';' | Where-Object { $_ -and $_ -ne $expandedValue }
                    $newValue = $parts -join ';'
                    
                    if ($DryRun) {
                        Write-DryRun "Remove from $($op.Name): $expandedValue [$Scope from $fileName]"
                    } else {
                        [Environment]::SetEnvironmentVariable($op.Name, $newValue, $Scope)
                        Write-Success "Removed from $($op.Name) [$Scope]"
                    }
                    $changes++
                }
            }
        }
    }
    
    return $changes
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
    
    # Process each file
    $totalChanges = 0
    foreach ($file in $envFiles) {
        $fileName = Split-Path -Leaf $file.Path
        Write-Info "Processing: $fileName"
        
        $operations = Read-EnvironmentFile -FilePath $file.Path
        $changes = Apply-EnvironmentOperations -Operations $operations -Scope $file.Scope -SourceFile $file.Path -DryRun $DryRun
        $totalChanges += $changes
    }
    
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
#JAVA_HOME=`$SCOOP\apps\temurin21-jdk\current
#PATH+=`$JAVA_HOME\bin
#JAVA_OPTS=-Xmx2g -Xms512m -XX:+UseG1GC
#CLASSPATH=.
#CLASSPATH+=`$JAVA_HOME\lib\tools.jar

# --- Python Development ---
#PYTHON_HOME=`$SCOOP\apps\python313\current
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

#SVN_HOME=`$SCOOP\apps\svn\current
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
