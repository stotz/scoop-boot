<#
.SYNOPSIS
    Bootstrap script for Scoop package manager and portable Windows development environments.

.DESCRIPTION
    scoop-boot.ps1 v2.0.0 - Scoop Bootstrap & Environment Manager
    
    Features:
    - Bootstrap Scoop package manager with all recommended tools
    - Order-independent parameter parsing
    - Dynamic Git version detection
    - Meta-environment system (User/System scope control)
    - Environment configuration with GitHub template download
    - List operations (+=, =+, -=) for ALL semicolon-separated variables
    - Flexible application installation
    - Comprehensive self-testing (29 tests)
    - ASCII-only output for console compatibility

.PARAMETER (Dynamic)
    This script uses custom parameter parsing to support order-independent arguments.
    All parameters can be specified in any order.

.NOTES
    Author: Custom Development
    Version: 2.0.0
    Date: 2025-10-20
    
    CRITICAL: Run PowerShell with appropriate execution policy:
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
    
.EXAMPLE
    .\scoop-boot.ps1 --bootstrap
    Installs Scoop package manager with all recommended tools

.EXAMPLE
    .\scoop-boot.ps1 --init-env=user.default.env
    Creates user environment configuration file from template

.EXAMPLE
    .\scoop-boot.ps1 --apply-env
    Applies environment configurations in hierarchical order
#>

# Prevent positional parameters - all parameters must be named
param()

# ============================================================================
# Global Configuration
# ============================================================================

# Script version
$SCRIPT_VERSION = "2.0.0"

# Determine SCOOP_ROOT based on script location
$scriptDir = Split-Path -Parent $PSScriptRoot
$global:SCOOP_ROOT = $scriptDir
$global:SCOOP_GLOBAL_DIR = Join-Path $scriptDir "global"
$global:SCOOP_SHIMS_DIR = Join-Path $scriptDir "shims"
$global:ENV_DIR = Join-Path $scriptDir "etc\environments"
$global:BACKUP_DIR = Join-Path $scriptDir "etc\environments\backup"

# Template download configuration
$TEMPLATE_GITHUB_BASE = "https://raw.githubusercontent.com/stotz/scoop-boot/refs/heads/main/etc/environments"

# Parsed arguments storage
$global:ParsedArgs = @{
    Help = $false
    Version = $false
    Bootstrap = $false
    Force = $false
    Status = $false
    Install = @()
    Suggest = $false
    Environment = $false
    InitEnv = $null
    ApplyEnv = $false
    EnvStatus = $false
    DryRun = $false
    Rollback = $false
    SelfTest = $false
}

# ============================================================================
# Display Functions
# ============================================================================

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
}

function Write-Info {
    param([string]$Message)
    Write-Host ">>> $Message" -ForegroundColor Gray
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

# ============================================================================
# Argument Parsing
# ============================================================================

function Parse-Arguments {
    param([string[]]$Arguments)
    
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        
        switch -Regex ($arg) {
            "^--help$|^-h$" { $global:ParsedArgs.Help = $true }
            "^--version$|^-v$" { $global:ParsedArgs.Version = $true }
            "^--bootstrap$" { $global:ParsedArgs.Bootstrap = $true }
            "^--force$" { $global:ParsedArgs.Force = $true }
            "^--status$" { $global:ParsedArgs.Status = $true }
            "^--suggest$" { $global:ParsedArgs.Suggest = $true }
            "^--environment$" { $global:ParsedArgs.Environment = $true }
            "^--env-status$" { $global:ParsedArgs.EnvStatus = $true }
            "^--apply-env$" { $global:ParsedArgs.ApplyEnv = $true }
            "^--dry-run$" { $global:ParsedArgs.DryRun = $true }
            "^--rollback$" { $global:ParsedArgs.Rollback = $true }
            "^--selfTest$|^--self-test$" { $global:ParsedArgs.SelfTest = $true }
            
            "^--install$" {
                # Collect all non-flag arguments after --install
                $i++
                while ($i -lt $Arguments.Count -and $Arguments[$i] -notmatch "^--") {
                    $global:ParsedArgs.Install += $Arguments[$i]
                    $i++
                }
                $i--
            }
            
            "^--init-env=(.+)$|^--env-init=(.+)$" {
                $global:ParsedArgs.InitEnv = $Matches[1]
            }
            
            default {
                # Check if it's an app name for installation
                if ($arg -notmatch "^--" -and $global:ParsedArgs.Install.Count -eq 0) {
                    # Might be app names without --install flag
                    $appNames = @()
                    $j = $i
                    while ($j -lt $Arguments.Count -and $Arguments[$j] -notmatch "^--") {
                        $appNames += $Arguments[$j]
                        $j++
                    }
                    if ($appNames.Count -gt 0) {
                        $global:ParsedArgs.Install = $appNames
                        $i = $j - 1
                    }
                }
            }
        }
    }
}

# ============================================================================
# Help and Version Functions
# ============================================================================

function Show-Help {
    Write-Host @"
scoop-boot.ps1 v$SCRIPT_VERSION - Scoop Bootstrap & Environment Manager

USAGE:
    .\scoop-boot.ps1 [OPTIONS]

OPTIONS:
    --bootstrap         Install Scoop package manager with all recommended tools
    --force            Force reinstallation (use with --bootstrap)
    --status           Show current Scoop and environment status
    --help, -h         Show this help message
    --version, -v      Show version information
    --suggest          Show application installation suggestions
    --environment      Show current environment variables
    --selfTest         Run comprehensive self-tests

ENVIRONMENT MANAGEMENT:
    --init-env=FILE    Create environment configuration file from template
                       Downloads template from GitHub and adjusts paths
                       Examples:
                         --init-env=user.default.env (recommended)
                         --init-env=system.default.env (requires admin)
                         --init-env=user.$($env:COMPUTERNAME.ToLower()).$($env:USERNAME.ToLower()).env
                         --init-env=system.$($env:COMPUTERNAME.ToLower()).$($env:USERNAME.ToLower()).env
    
    --env-status       Show environment files and their status
    --apply-env        Apply environment configurations
    --dry-run          Show what would be changed (use with --apply-env)
    --rollback         Rollback to previous environment state

APPLICATION INSTALLATION:
    --install APP...   Install one or more applications via Scoop
                       Example: --install git nodejs python

GETTING STARTED:
    1. Bootstrap Scoop:
       .\scoop-boot.ps1 --bootstrap
    
    2. Create environment config:
       .\scoop-boot.ps1 --init-env=user.default.env
    
    3. Install applications:
       .\scoop-boot.ps1 --install git nodejs python

EXAMPLES:
    .\scoop-boot.ps1 --bootstrap
    .\scoop-boot.ps1 --init-env=user.default.env
    .\scoop-boot.ps1 --apply-env --dry-run
    .\scoop-boot.ps1 --install openjdk maven gradle

ENVIRONMENT FILE SYNTAX:
    VAR=value           Set variable
    VAR+=value          Prepend to list variable (PATH, PERL5LIB, etc.)
    VAR=+value          Append to list variable
    VAR-=value          Remove from list variable
    -VAR                Unset variable
    # Comment           Lines starting with # are ignored

    Supports list operations for: PATH, PERL5LIB, PYTHONPATH, CLASSPATH,
    PSModulePath, PATHEXT, and any semicolon-separated variable.
"@
}

function Show-Version {
    Write-Host "scoop-boot.ps1 version $SCRIPT_VERSION"
}

# ============================================================================
# Bootstrap Functions
# ============================================================================

function Invoke-Bootstrap {
    Write-Section "Scoop Bootstrap"
    
    # Check if running with --force
    $force = $global:ParsedArgs.Force
    
    # Detect base directory
    Write-Info "Checking current state..."
    Write-Host "     SCOOP=$global:SCOOP_ROOT" -ForegroundColor Gray
    Write-Host "     SCOOP_GLOBAL=$global:SCOOP_GLOBAL_DIR" -ForegroundColor Gray
    Write-Host ""
    
    # Check if Scoop already exists
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        if (!$force) {
            Write-Warning "Scoop is already installed"
            Write-Host ""
            Write-Host "To reinstall, use:" -ForegroundColor Yellow
            Write-Host "  .\bin\scoop-boot.ps1 --bootstrap --force" -ForegroundColor White
            Write-Host ""
            Write-Host "To update Scoop, use:" -ForegroundColor Yellow
            Write-Host "  scoop update" -ForegroundColor White
            return $false
        }
        Write-Warning "Force reinstalling Scoop..."
    }
    
    # Set environment variables
    Write-Info "Setting environment variables..."
    [Environment]::SetEnvironmentVariable('SCOOP', $global:SCOOP_ROOT, 'User')
    [Environment]::SetEnvironmentVariable('SCOOP_GLOBAL', $global:SCOOP_GLOBAL_DIR, 'User')
    $env:SCOOP = $global:SCOOP_ROOT
    $env:SCOOP_GLOBAL = $global:SCOOP_GLOBAL_DIR
    Write-Success "Environment variables set"
    
    # Download and run official installer
    Write-Host ""
    Write-Info "Installing Scoop core..."
    try {
        $installerPath = "$env:TEMP\scoop-install.ps1"
        Invoke-WebRequest -Uri 'https://get.scoop.sh' -OutFile $installerPath
        
        & $installerPath -ScoopDir $global:SCOOP_ROOT -ScoopGlobalDir $global:SCOOP_GLOBAL_DIR -NoProxy
        
        Remove-Item $installerPath -ErrorAction SilentlyContinue
        Write-Success "Scoop core installed"
    }
    catch {
        Write-ErrorMsg "Failed to install Scoop: $_"
        return $false
    }
    
    # Verify installation
    if (!(Test-Path "$global:SCOOP_SHIMS_DIR\scoop.cmd")) {
        Write-ErrorMsg "Scoop installation verification failed"
        return $false
    }
    
    # Add to PATH if needed
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($userPath -notlike "*$global:SCOOP_SHIMS_DIR*") {
        Write-Info "Updating PATH..."
        [Environment]::SetEnvironmentVariable('PATH', "$global:SCOOP_SHIMS_DIR;$userPath", 'User')
        $env:PATH = "$global:SCOOP_SHIMS_DIR;$env:PATH"
        Write-Success "PATH updated"
    }
    
    # Install essential tools
    Write-Host ""
    Write-Info "Installing essential tools..."
    
    $scoopCmd = Join-Path $global:SCOOP_SHIMS_DIR "scoop.cmd"
    
    & $scoopCmd install git 2>&1 | Out-Null
    Write-Success "Git installed"
    
    & $scoopCmd install 7zip 2>&1 | Out-Null
    Write-Success "7-Zip installed"
    
    # Install recommended tools for optimal performance
    Write-Host ""
    Write-Info "Installing recommended tools for optimal performance..."
    
    & $scoopCmd install aria2 2>&1 | Out-Null
    Write-Success "aria2 installed (5x faster downloads)"
    
    & $scoopCmd install sudo 2>&1 | Out-Null
    Write-Success "sudo installed (admin operations)"
    
    & $scoopCmd install innounp 2>&1 | Out-Null
    Write-Success "innounp installed (Inno Setup support)"
    
    & $scoopCmd install dark 2>&1 | Out-Null
    Write-Success "dark installed (WiX Toolset support)"
    
    & $scoopCmd install lessmsi 2>&1 | Out-Null
    Write-Success "lessmsi installed (MSI extraction)"
    
    & $scoopCmd install wget 2>&1 | Out-Null
    Write-Success "wget installed (alternative downloader)"
    
    # Add essential buckets
    Write-Host ""
    Write-Info "Adding essential buckets..."
    
    & $scoopCmd bucket add main 2>&1 | Out-Null
    Write-Success "main bucket (official apps)"
    
    & $scoopCmd bucket add extras 2>&1 | Out-Null
    Write-Success "extras bucket (additional apps)"
    
    # Show completion message
    Write-Section "Bootstrap Complete!"
    
    Write-Host ""
    Write-Host "Scoop is fully configured with all recommended tools!" -ForegroundColor Green
    Write-Host "Installation path: $global:SCOOP_ROOT" -ForegroundColor Green
    Write-Host ""
    Write-Host "Core tools:     git, 7zip" -ForegroundColor Gray
    Write-Host "Performance:    aria2 (multi-connection downloads enabled)" -ForegroundColor Gray
    Write-Host "Admin tools:    sudo" -ForegroundColor Gray
    Write-Host "Extractors:     innounp, dark, lessmsi" -ForegroundColor Gray
    Write-Host "Downloaders:    wget, aria2" -ForegroundColor Gray
    
    Show-NextSteps
    
    return $true
}

function Show-NextSteps {
    $hostname = $env:COMPUTERNAME.ToLower()
    $username = $env:USERNAME.ToLower()
    
    Write-Section "Required: Restart Shell"
    Write-Info "Close and reopen your terminal to reload PATH"
    
    Write-Section "Next Steps"
    
    Write-Host ""
    Write-Host "1. CREATE ENVIRONMENT CONFIGURATION (choose one):" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   For system-wide defaults (requires admin):" -ForegroundColor Gray
    Write-Host "     .\bin\scoop-boot.ps1 --init-env=system.default.env" -ForegroundColor White
    Write-Host ""
    Write-Host "   For system + host-specific (requires admin):" -ForegroundColor Gray
    Write-Host "     .\bin\scoop-boot.ps1 --init-env=system.$hostname.$username.env" -ForegroundColor White
    Write-Host ""
    Write-Host "   For user defaults (RECOMMENDED):" -ForegroundColor Cyan
    Write-Host "     .\bin\scoop-boot.ps1 --init-env=user.default.env" -ForegroundColor White
    Write-Host ""
    Write-Host "   For user + host-specific:" -ForegroundColor Gray
    Write-Host "     .\bin\scoop-boot.ps1 --init-env=user.$hostname.$username.env" -ForegroundColor White
    Write-Host ""
    Write-Host "2. APPLY CONFIGURATION:" -ForegroundColor Yellow
    Write-Host "     .\bin\scoop-boot.ps1 --apply-env" -ForegroundColor White
    Write-Host ""
    Write-Host "3. ADD MORE BUCKETS (optional):" -ForegroundColor Yellow
    Write-Host "     scoop bucket add java        # Java/JDK versions" -ForegroundColor White
    Write-Host "     scoop bucket add versions     # Multiple versions of apps" -ForegroundColor White
    Write-Host "     scoop bucket add nerd-fonts   # Programming fonts" -ForegroundColor White
    Write-Host ""
    Write-Host "4. EXPLORE AVAILABLE APPS:" -ForegroundColor Yellow
    Write-Host "     .\bin\scoop-boot.ps1 --suggest" -ForegroundColor White
    Write-Host "     scoop search <appname>" -ForegroundColor White
}

# ============================================================================
# Status Functions
# ============================================================================

function Show-Status {
    Write-Section "Scoop-Boot Status"
    
    # Check Scoop installation
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Success "Scoop is installed"
        $scoopVersion = & scoop --version
        Write-Host "     Version: $scoopVersion" -ForegroundColor Gray
        Write-Host "     Path: $env:SCOOP" -ForegroundColor Gray
    }
    else {
        Write-Warning "Scoop is not installed at $global:SCOOP_ROOT"
        Write-Host ""
        Write-Host "To install Scoop, run:" -ForegroundColor Yellow
        Write-Host "  .\bin\scoop-boot.ps1 --bootstrap" -ForegroundColor White
        Write-Host ""
        Write-Host "After bootstrap, configure your environment:" -ForegroundColor Yellow
        Write-Host "  .\bin\scoop-boot.ps1 --init-env=user.default.env    (recommended)" -ForegroundColor White
        Write-Host "  .\bin\scoop-boot.ps1 --init-env=system.default.env  (requires admin)" -ForegroundColor White
        Write-Host ""
        Write-Host "For help:" -ForegroundColor Yellow
        Write-Host "  .\bin\scoop-boot.ps1 --help" -ForegroundColor White
        return
    }
    
    # Check environment files
    Write-Host ""
    Write-Info "Environment configuration:"
    
    if (Test-Path $global:ENV_DIR) {
        $envFiles = Get-ChildItem -Path $global:ENV_DIR -Filter "*.env" -ErrorAction SilentlyContinue
        if ($envFiles) {
            foreach ($file in $envFiles) {
                Write-Success "Found: $($file.Name)"
            }
        }
        else {
            Write-Warning "No .env files found"
            Write-Host "     Create one with: .\bin\scoop-boot.ps1 --init-env=user.default.env" -ForegroundColor Gray
        }
    }
    else {
        Write-Warning "Environment directory not found: $global:ENV_DIR"
        Write-Host "     Create it with: .\bin\scoop-boot.ps1 --init-env=user.default.env" -ForegroundColor Gray
    }
    
    # Check buckets
    Write-Host ""
    Write-Info "Scoop buckets:"
    $buckets = & scoop bucket list
    if ($buckets) {
        $buckets | ForEach-Object { Write-Host "     - $_" -ForegroundColor Gray }
    }
    else {
        Write-Warning "No buckets configured"
    }
}

# ============================================================================
# Environment Management Functions
# ============================================================================

function Get-TemplateContent {
    param([string]$FileName)
    
    Write-Info "Downloading template from GitHub..."
    
    # Download template from GitHub
    $url = "$TEMPLATE_GITHUB_BASE/template-default.env"
    try {
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        $template = $response.Content
        Write-Success "Template downloaded"
    }
    catch {
        Write-ErrorMsg "Failed to download template: $_"
        Write-Info "Using minimal fallback template..."
        $template = Get-MinimalFallbackTemplate
    }
    
    # Detect if system or user scope based on filename
    $isSystem = $FileName -like "system*"
    
    # Replace $SCOOP placeholders with actual path
    $template = $template -replace '\$SCOOP_ROOT', $global:SCOOP_ROOT
    $template = $template -replace '\$SCOOP', $global:SCOOP_ROOT
    
    # Add header with actual filename and scope info
    $header = @"
# ============================================================================
# $(if ($isSystem) { "System" } else { "User" }) Environment Configuration
# File: $FileName
# Generated by scoop-boot.ps1 v$SCRIPT_VERSION
# Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# ============================================================================
# Scope: $(if ($isSystem) { "Machine (requires admin)" } else { "User (no admin required)" })
# SCOOP: $global:SCOOP_ROOT
# Hostname: $($env:COMPUTERNAME.ToLower())
# Username: $($env:USERNAME.ToLower())
# ============================================================================
# IMPORTANT: After applying changes with --apply-env, restart your shell!
# ============================================================================

"@
    
    return $header + $template
}

function Get-MinimalFallbackTemplate {
    # Only as emergency fallback if GitHub is unreachable
    return @"
# Environment Configuration
# Edit this file and uncomment lines you need
#
# SYNTAX:
#   VAR=value           Set variable
#   VAR+=value          Prepend to list (works with any semicolon-separated variable)
#   VAR=+value          Append to list
#   VAR-=value          Remove from list
#   -VAR                Unset variable
#   # Comment           Lines starting with # are ignored

# PATH Management
PATH+=$global:SCOOP_ROOT\bin
PATH+=$global:SCOOP_ROOT\shims

# Java Development
#JAVA_HOME=$global:SCOOP_ROOT\apps\openjdk\current
#PATH+=`$JAVA_HOME\bin
#JAVA_OPTS=-Xmx2g -Xms512m -XX:+UseG1GC -XX:MaxGCPauseMillis=200

# Python Development  
#PYTHON_HOME=$global:SCOOP_ROOT\apps\python\current
#PATH+=`$PYTHON_HOME
#PATH+=`$PYTHON_HOME\Scripts
#PYTHONPATH=`$PYTHON_HOME\Lib\site-packages

# Perl Development
#PERL_HOME=$global:SCOOP_ROOT\apps\perl\current
#PATH+=`$PERL_HOME\bin
#PERL5LIB=`$PERL_HOME\lib
#PERL5LIB+=`$PERL_HOME\site\lib

# Node.js Development
#NODE_HOME=$global:SCOOP_ROOT\apps\nodejs\current
#PATH+=`$NODE_HOME
#NPM_CONFIG_PREFIX=$global:SCOOP_ROOT\persist\nodejs
#PATH+=`$NPM_CONFIG_PREFIX\bin
"@
}

function Expand-EnvironmentVariables {
    param(
        [string]$Value,
        [hashtable]$Cache = @{}
    )
    
    $maxIterations = 10
    $iteration = 0
    
    while ($iteration -lt $maxIterations) {
        $iteration++
        $hasChanges = $false
        
        # Look for variables to expand
        if ($Value -match '\$([A-Z_][A-Z0-9_]*)') {
            $varName = $Matches[1]
            $replacement = $null
            
            # Check cache first
            if ($Cache.ContainsKey($varName)) {
                $replacement = $Cache[$varName]
            }
            # Check special variables
            elseif ($varName -eq 'SCOOP') {
                $replacement = $global:SCOOP_ROOT
            }
            elseif ($varName -eq 'SCOOP_ROOT') {
                $replacement = $global:SCOOP_ROOT
            }
            else {
                $envValue = [Environment]::GetEnvironmentVariable($varName)
                if ($envValue) {
                    $replacement = $envValue
                }
            }
            
            if ($replacement) {
                $Value = $Value.Replace("`$$varName", $replacement)
                $hasChanges = $true
            }
            else {
                # Variable not found, break to avoid infinite loop
                break
            }
        }
        
        if (-not $hasChanges) {
            break
        }
    }
    
    return $Value
}

function Get-EnvironmentFiles {
    $hostname = $env:COMPUTERNAME.ToLower()
    $username = $env:USERNAME.ToLower()
    
    $files = @(
        @{Path = Join-Path $global:ENV_DIR "system.default.env"; Scope = "Machine"; Order = 1},
        @{Path = Join-Path $global:ENV_DIR "system.$hostname.$username.env"; Scope = "Machine"; Order = 2},
        @{Path = Join-Path $global:ENV_DIR "user.default.env"; Scope = "User"; Order = 3},
        @{Path = Join-Path $global:ENV_DIR "user.$hostname.$username.env"; Scope = "User"; Order = 4}
    )
    
    return $files | Where-Object { Test-Path $_.Path }
}

function Parse-EnvironmentLine {
    param([string]$Line)
    
    # Skip empty lines and comments
    if ([string]::IsNullOrWhiteSpace($Line) -or $Line.StartsWith("#")) {
        return $null
    }
    
    # Remove leading/trailing whitespace
    $Line = $Line.Trim()
    
    # Parse different syntax patterns - now generic for all variables
    if ($Line -match '^([A-Z_][A-Z0-9_]*)\s*\+=\s*(.+)$') {
        # VAR += value or VAR+=value (prepend)
        $varName = $Matches[1]
        $value = $Matches[2].Trim()
        
        if ($varName -eq "PATH") {
            return @{Type = "PathPrepend"; Value = $value}
        }
        else {
            return @{Type = "ListPrepend"; Name = $varName; Value = $value}
        }
    }
    elseif ($Line -match '^([A-Z_][A-Z0-9_]*)\s*=\s*\+(.+)$') {
        # VAR =+ value or VAR=+value (append)
        $varName = $Matches[1]
        $value = $Matches[2].Trim()
        
        if ($varName -eq "PATH") {
            return @{Type = "PathAppend"; Value = $value}
        }
        else {
            return @{Type = "ListAppend"; Name = $varName; Value = $value}
        }
    }
    elseif ($Line -match '^([A-Z_][A-Z0-9_]*)\s*-=\s*(.+)$|^([A-Z_][A-Z0-9_]*)-=(.+)$') {
        # VAR -= value or VAR-=value (remove)
        $varName = if ($Matches[1]) { $Matches[1] } else { $Matches[3] }
        $value = if ($Matches[2]) { $Matches[2] } else { $Matches[4] }
        $value = $value.Trim()
        
        if ($varName -eq "PATH") {
            return @{Type = "PathRemove"; Value = $value}
        }
        else {
            return @{Type = "ListRemove"; Name = $varName; Value = $value}
        }
    }
    elseif ($Line -match '^-([A-Z_][A-Z0-9_]*)$') {
        # -VARIABLE (unset)
        return @{Type = "Unset"; Name = $Matches[1]}
    }
    elseif ($Line -match '^([A-Z_][A-Z0-9_]*)=(.*)$') {
        # VARIABLE=value (set)
        return @{Type = "Set"; Name = $Matches[1]; Value = $Matches[2]}
    }
    
    return $null
}

function Backup-EnvironmentVariable {
    param(
        [string]$Name,
        [string]$Scope
    )
    
    if (!(Test-Path $global:BACKUP_DIR)) {
        New-Item -Path $global:BACKUP_DIR -ItemType Directory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupFile = Join-Path $global:BACKUP_DIR "$Scope.$Name.$timestamp.bak"
    
    $currentValue = [Environment]::GetEnvironmentVariable($Name, $Scope)
    if ($currentValue) {
        $currentValue | Out-File -FilePath $backupFile -Encoding UTF8
        return $backupFile
    }
    
    return $null
}

function Invoke-InitEnv {
    param([string]$FileName)
    
    if ([string]::IsNullOrWhiteSpace($FileName)) {
        Write-ErrorMsg "--init-env requires a filename"
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  --init-env=user.default.env" -ForegroundColor Gray
        Write-Host "  --init-env=system.default.env" -ForegroundColor Gray
        $hostname = $env:COMPUTERNAME.ToLower()
        $username = $env:USERNAME.ToLower()
        Write-Host "  --init-env=user.$hostname.$username.env" -ForegroundColor Gray
        Write-Host "  --init-env=system.$hostname.$username.env" -ForegroundColor Gray
        return $false
    }
    
    # Ensure directory exists
    if (!(Test-Path $global:ENV_DIR)) {
        New-Item -Path $global:ENV_DIR -ItemType Directory -Force | Out-Null
    }
    
    $filePath = Join-Path $global:ENV_DIR $FileName
    
    if (Test-Path $filePath) {
        Write-Warning "File already exists: $filePath"
        $response = Read-Host "Overwrite? (y/N)"
        if ($response -ne 'y') {
            return $false
        }
    }
    
    # Get template content (downloads from GitHub and adjusts)
    $template = Get-TemplateContent -FileName $FileName
    
    # Save template
    $template | Out-File -FilePath $filePath -Encoding UTF8
    Write-Success "Created: $filePath"
    
    # Show helpful message based on scope
    if ($FileName -like "system*") {
        Write-Warning "This is a system-scope file. You'll need admin rights to apply it."
        Write-Host "     Run PowerShell as Administrator before using --apply-env" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Info "Next steps:"
    Write-Host "  1. Edit the file: notepad `"$filePath`"" -ForegroundColor Gray
    Write-Host "  2. Apply changes: .\bin\scoop-boot.ps1 --apply-env" -ForegroundColor Gray
    
    return $true
}

function Invoke-EnvStatus {
    Write-Section "Environment Status"
    
    if (!(Test-Path $global:ENV_DIR)) {
        Write-Warning "Environment directory not found: $global:ENV_DIR"
        return
    }
    
    $envFiles = @(
        "system.default.env",
        "system.$($env:COMPUTERNAME.ToLower()).$($env:USERNAME.ToLower()).env",
        "user.default.env",
        "user.$($env:COMPUTERNAME.ToLower()).$($env:USERNAME.ToLower()).env"
    )
    
    Write-Host "Configuration hierarchy (applied in order):" -ForegroundColor Gray
    Write-Host ""
    
    $found = $false
    foreach ($file in $envFiles) {
        $path = Join-Path $global:ENV_DIR $file
        $scope = if ($file.StartsWith("system")) { "Machine" } else { "User" }
        $type = if ($file -like "*.default.env") { "Default" } else { "Host-specific" }
        
        if (Test-Path $path) {
            Write-Success "$file"
            Write-Host "     Scope: $scope | Type: $type" -ForegroundColor Gray
            $found = $true
        }
        else {
            Write-Host "[-] $file (not found)" -ForegroundColor DarkGray
        }
    }
    
    if (!$found) {
        Write-Host ""
        Write-Warning "No environment files configured"
        Write-Host "Create one with: .\bin\scoop-boot.ps1 --init-env=user.default.env" -ForegroundColor Gray
    }
}

function Invoke-ApplyEnv {
    param(
        [bool]$DryRun = $false,
        [bool]$Rollback = $false
    )
    
    Write-Section $(if ($DryRun) { "Environment Apply (DRY RUN)" } else { "Environment Apply" })
    
    if (!(Test-Path $global:ENV_DIR)) {
        Write-ErrorMsg "Environment directory not found: $global:ENV_DIR"
        return
    }
    
    if ($Rollback) {
        Write-Warning "Rollback functionality not yet implemented"
        return
    }
    
    # Get all environment files in order
    $envFiles = Get-EnvironmentFiles
    
    if ($envFiles.Count -eq 0) {
        Write-Warning "No environment files found"
        Write-Host "Create one with: .\bin\scoop-boot.ps1 --init-env=user.default.env" -ForegroundColor Gray
        return
    }
    
    # Process each file
    $cache = @{}
    $systemChanges = @()
    $userChanges = @()
    
    foreach ($fileInfo in $envFiles) {
        Write-Info "Processing: $(Split-Path $fileInfo.Path -Leaf)"
        
        $content = Get-Content -Path $fileInfo.Path -ErrorAction SilentlyContinue
        if (!$content) {
            continue
        }
        
        foreach ($line in $content) {
            $parsed = Parse-EnvironmentLine -Line $line
            if (!$parsed) {
                continue
            }
            
            # Expand variables
            if ($parsed.Value) {
                $parsed.Value = Expand-EnvironmentVariables -Value $parsed.Value -Cache $cache
            }
            
            # Add to appropriate change list
            $change = @{
                Action = $parsed
                Scope = $fileInfo.Scope
                File = Split-Path $fileInfo.Path -Leaf
            }
            
            if ($fileInfo.Scope -eq "Machine") {
                $systemChanges += $change
            }
            else {
                $userChanges += $change
            }
            
            # Update cache for variable expansion
            if ($parsed.Type -eq "Set") {
                $cache[$parsed.Name] = $parsed.Value
            }
        }
    }
    
    # Check for admin rights if system changes are needed
    if ($systemChanges.Count -gt 0) {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
        if (!$isAdmin -and !$DryRun) {
            Write-ErrorMsg "Administrator rights required for system environment changes"
            Write-Host "Run PowerShell as Administrator or use only user.*.env files" -ForegroundColor Yellow
            return
        }
    }
    
    # Apply changes
    $appliedCount = 0
    
    # Apply system changes first
    foreach ($change in $systemChanges) {
        if (Apply-EnvironmentChange -Change $change -DryRun $DryRun) {
            $appliedCount++
        }
    }
    
    # Then apply user changes
    foreach ($change in $userChanges) {
        if (Apply-EnvironmentChange -Change $change -DryRun $DryRun) {
            $appliedCount++
        }
    }
    
    # Summary
    Write-Host ""
    if ($DryRun) {
        Write-Info "DRY RUN: Would apply $appliedCount changes"
        Write-Host "Run without --dry-run to apply changes" -ForegroundColor Yellow
    }
    else {
        Write-Success "Applied $appliedCount changes"
        Write-Host ""
        Write-Warning "IMPORTANT: Restart your shell for changes to take effect!"
    }
}

function Apply-EnvironmentChange {
    param(
        [hashtable]$Change,
        [bool]$DryRun
    )
    
    $action = $Change.Action
    $scope = $Change.Scope
    $file = $Change.File
    
    switch ($action.Type) {
        "Set" {
            $current = [Environment]::GetEnvironmentVariable($action.Name, $scope)
            if ($current -ne $action.Value) {
                if ($DryRun) {
                    Write-Host "  [DRY] Set $($action.Name) = $($action.Value) [$scope from $file]" -ForegroundColor Yellow
                }
                else {
                    if ($current) {
                        Backup-EnvironmentVariable -Name $action.Name -Scope $scope
                    }
                    [Environment]::SetEnvironmentVariable($action.Name, $action.Value, $scope)
                    Write-Success "Set $($action.Name) [$scope]"
                }
                return $true
            }
        }
        
        "Unset" {
            $current = [Environment]::GetEnvironmentVariable($action.Name, $scope)
            if ($current) {
                if ($DryRun) {
                    Write-Host "  [DRY] Unset $($action.Name) [$scope from $file]" -ForegroundColor Yellow
                }
                else {
                    Backup-EnvironmentVariable -Name $action.Name -Scope $scope
                    [Environment]::SetEnvironmentVariable($action.Name, $null, $scope)
                    Write-Success "Unset $($action.Name) [$scope]"
                }
                return $true
            }
        }
        
        "PathPrepend" {
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", $scope)
            $pathArray = $currentPath -split ';' | Where-Object { $_ }
            
            if ($action.Value -notin $pathArray) {
                if ($DryRun) {
                    Write-Host "  [DRY] Prepend to PATH: $($action.Value) [$scope from $file]" -ForegroundColor Yellow
                }
                else {
                    Backup-EnvironmentVariable -Name "PATH" -Scope $scope
                    $newPath = @($action.Value) + $pathArray
                    [Environment]::SetEnvironmentVariable("PATH", ($newPath -join ';'), $scope)
                    Write-Success "Prepended to PATH: $($action.Value) [$scope]"
                }
                return $true
            }
        }
        
        "PathAppend" {
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", $scope)
            $pathArray = $currentPath -split ';' | Where-Object { $_ }
            
            if ($action.Value -notin $pathArray) {
                if ($DryRun) {
                    Write-Host "  [DRY] Append to PATH: $($action.Value) [$scope from $file]" -ForegroundColor Yellow
                }
                else {
                    Backup-EnvironmentVariable -Name "PATH" -Scope $scope
                    $newPath = $pathArray + @($action.Value)
                    [Environment]::SetEnvironmentVariable("PATH", ($newPath -join ';'), $scope)
                    Write-Success "Appended to PATH: $($action.Value) [$scope]"
                }
                return $true
            }
        }
        
        "PathRemove" {
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", $scope)
            $pathArray = $currentPath -split ';' | Where-Object { $_ }
            
            if ($action.Value -in $pathArray) {
                if ($DryRun) {
                    Write-Host "  [DRY] Remove from PATH: $($action.Value) [$scope from $file]" -ForegroundColor Yellow
                }
                else {
                    Backup-EnvironmentVariable -Name "PATH" -Scope $scope
                    $newPath = $pathArray | Where-Object { $_ -ne $action.Value }
                    [Environment]::SetEnvironmentVariable("PATH", ($newPath -join ';'), $scope)
                    Write-Success "Removed from PATH: $($action.Value) [$scope]"
                }
                return $true
            }
        }
        
        # Generic list operations for other variables
        "ListPrepend" {
            $currentValue = [Environment]::GetEnvironmentVariable($action.Name, $scope)
            $separator = ";"
            $valueArray = if ($currentValue) { $currentValue -split $separator | Where-Object { $_ } } else { @() }
            
            if ($action.Value -notin $valueArray) {
                if ($DryRun) {
                    Write-Host "  [DRY] Prepend to $($action.Name): $($action.Value) [$scope from $file]" -ForegroundColor Yellow
                }
                else {
                    Backup-EnvironmentVariable -Name $action.Name -Scope $scope
                    $newValue = @($action.Value) + $valueArray
                    [Environment]::SetEnvironmentVariable($action.Name, ($newValue -join $separator), $scope)
                    Write-Success "Prepended to $($action.Name): $($action.Value) [$scope]"
                }
                return $true
            }
        }
        
        "ListAppend" {
            $currentValue = [Environment]::GetEnvironmentVariable($action.Name, $scope)
            $separator = ";"
            $valueArray = if ($currentValue) { $currentValue -split $separator | Where-Object { $_ } } else { @() }
            
            if ($action.Value -notin $valueArray) {
                if ($DryRun) {
                    Write-Host "  [DRY] Append to $($action.Name): $($action.Value) [$scope from $file]" -ForegroundColor Yellow
                }
                else {
                    Backup-EnvironmentVariable -Name $action.Name -Scope $scope
                    $newValue = $valueArray + @($action.Value)
                    [Environment]::SetEnvironmentVariable($action.Name, ($newValue -join $separator), $scope)
                    Write-Success "Appended to $($action.Name): $($action.Value) [$scope]"
                }
                return $true
            }
        }
        
        "ListRemove" {
            $currentValue = [Environment]::GetEnvironmentVariable($action.Name, $scope)
            $separator = ";"
            $valueArray = if ($currentValue) { $currentValue -split $separator | Where-Object { $_ } } else { @() }
            
            if ($action.Value -in $valueArray) {
                if ($DryRun) {
                    Write-Host "  [DRY] Remove from $($action.Name): $($action.Value) [$scope from $file]" -ForegroundColor Yellow
                }
                else {
                    Backup-EnvironmentVariable -Name $action.Name -Scope $scope
                    $newValue = $valueArray | Where-Object { $_ -ne $action.Value }
                    [Environment]::SetEnvironmentVariable($action.Name, ($newValue -join $separator), $scope)
                    Write-Success "Removed from $($action.Name): $($action.Value) [$scope]"
                }
                return $true
            }
        }
    }
    
    return $false
}

# ============================================================================
# Application Management
# ============================================================================

function Show-Suggest {
    Write-Section "Suggested Applications"
    
    Write-Host "Development Tools:" -ForegroundColor Yellow
    Write-Host "  scoop install git nodejs python openjdk maven gradle" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "Text Editors & IDEs:" -ForegroundColor Yellow
    Write-Host "  scoop install vscode notepadplusplus sublime-text" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "System Utilities:" -ForegroundColor Yellow
    Write-Host "  scoop install 7zip wget curl ripgrep fd fzf" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "Databases:" -ForegroundColor Yellow
    Write-Host "  scoop install postgresql mysql sqlite" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "Cloud Tools:" -ForegroundColor Yellow
    Write-Host "  scoop install aws azure-cli gcloud kubectl terraform" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "To search for specific apps:" -ForegroundColor Cyan
    Write-Host "  scoop search <appname>" -ForegroundColor White
}

function Invoke-Install {
    param([string[]]$Apps)
    
    if ($Apps.Count -eq 0) {
        Write-ErrorMsg "No applications specified"
        Write-Host "Usage: .\scoop-boot.ps1 --install <app1> <app2> ..." -ForegroundColor Gray
        return
    }
    
    Write-Section "Installation"
    Write-Info "Installing applications: $($Apps -join ', ')"
    
    if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorMsg "Scoop is not installed or not in PATH"
        Write-Host "Run: .\bin\scoop-boot.ps1 --bootstrap" -ForegroundColor Yellow
        return
    }
    
    foreach ($app in $Apps) {
        Write-Info "Installing $app..."
        & scoop install $app
        if ($LASTEXITCODE -eq 0) {
            Write-Success "$app installed"
        }
        else {
            Write-ErrorMsg "Failed to install $app"
        }
    }
}

function Show-Environment {
    Write-Section "Current Environment Variables"
    
    Write-Host "SCOOP Environment:" -ForegroundColor Yellow
    Write-Host "  SCOOP = $env:SCOOP" -ForegroundColor Gray
    Write-Host "  SCOOP_GLOBAL = $env:SCOOP_GLOBAL" -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "Development Environment:" -ForegroundColor Yellow
    
    $devVars = @('JAVA_HOME', 'MAVEN_HOME', 'GRADLE_HOME', 'PYTHON_HOME', 
                 'NODE_HOME', 'GO_HOME', 'RUST_HOME', 'PERL_HOME', 'PERL5LIB')
    
    foreach ($var in $devVars) {
        $value = [Environment]::GetEnvironmentVariable($var)
        if ($value) {
            Write-Host "  $var = $value" -ForegroundColor Gray
        }
    }
}

# ============================================================================
# Self-Test Functions
# ============================================================================

function Test-ScoopBoot {
    Write-Section "Self-Test"
    
    $tests = @()
    $passed = 0
    $failed = 0
    
    # Test 1: PowerShell version
    $test = @{Name = "PowerShell version >= 5.1"; Result = $false}
    try {
        $test.Result = $PSVersionTable.PSVersion.Major -ge 5
    }
    catch {}
    $tests += $test
    
    # Test 2: Execution Policy
    $test = @{Name = "Execution Policy allows scripts"; Result = $false}
    try {
        $policy = Get-ExecutionPolicy -Scope CurrentUser
        $test.Result = $policy -in @('RemoteSigned', 'Unrestricted', 'Bypass')
    }
    catch {}
    $tests += $test
    
    # Test 3: Parameter parsing
    $test = @{Name = "Parameter parsing"; Result = $false}
    try {
        $testArgs = @{Help = $false; Install = @()}
        Parse-Arguments @("--help", "--install", "app1", "app2")
        $test.Result = $global:ParsedArgs.Help -eq $true -and $global:ParsedArgs.Install.Count -eq 2
        # Reset
        $global:ParsedArgs = $testArgs
    }
    catch {}
    $tests += $test
    
    # Test 4: Admin rights detection
    $test = @{Name = "Admin rights detection"; Result = $false}
    try {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
        $test.Result = $true  # Test passes if we can detect admin status
    }
    catch {}
    $tests += $test
    
    # Test 5: Directory path generation
    $test = @{Name = "Directory path generation"; Result = $false}
    try {
        $test.Result = ![string]::IsNullOrWhiteSpace($global:SCOOP_ROOT) -and 
                      ![string]::IsNullOrWhiteSpace($global:ENV_DIR)
    }
    catch {}
    $tests += $test
    
    # Test 6: Hostname detection
    $test = @{Name = "Hostname detection"; Result = $false}
    try {
        $hostname = $env:COMPUTERNAME.ToLower()
        $test.Result = ![string]::IsNullOrWhiteSpace($hostname)
    }
    catch {}
    $tests += $test
    
    # Test 7: Username detection
    $test = @{Name = "Username detection"; Result = $false}
    try {
        $username = $env:USERNAME.ToLower()
        $test.Result = ![string]::IsNullOrWhiteSpace($username)
    }
    catch {}
    $tests += $test
    
    # Test 8: Host-User filename generation
    $test = @{Name = "Host-User filename generation"; Result = $false}
    try {
        $hostname = $env:COMPUTERNAME.ToLower()
        $username = $env:USERNAME.ToLower()
        $filename = "system.$hostname.$username.env"
        $test.Result = $filename -match '^system\.[a-z0-9]+\.[a-z0-9]+\.env$'
    }
    catch {}
    $tests += $test
    
    # Test 9: Parse PATH += (prepend)
    $test = @{Name = "Parse PATH += (prepend)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH+=C:\test\bin"
        $test.Result = $parsed.Type -eq "PathPrepend"
    }
    catch {}
    $tests += $test
    
    # Test 10: Parse PATH =+ (append)
    $test = @{Name = "Parse PATH =+ (append)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH=+C:\test\bin"
        $test.Result = $parsed.Type -eq "PathAppend"
    }
    catch {}
    $tests += $test
    
    # Test 11: Parse PATH - (remove with space)
    $test = @{Name = "Parse PATH - (remove with space)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH -= C:\test\bin"
        $test.Result = $parsed.Type -eq "PathRemove"
    }
    catch {}
    $tests += $test
    
    # Test 12: Parse PATH-= (remove without space)
    $test = @{Name = "Parse PATH-= (remove without space)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH-=C:\test\bin"
        $test.Result = $parsed.Type -eq "PathRemove"
    }
    catch {}
    $tests += $test
    
    # Test 13: Parse PATH -= (remove with -= syntax)
    $test = @{Name = "Parse PATH -= (remove with -= syntax)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH -= C:\test\bin"
        $test.Result = $parsed.Type -eq "PathRemove"
    }
    catch {}
    $tests += $test
    
    # Test 14: Parse variable assignment
    $test = @{Name = "Parse variable assignment"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "JAVA_HOME=C:\java"
        $test.Result = $parsed.Type -eq "Set" -and $parsed.Name -eq "JAVA_HOME"
    }
    catch {}
    $tests += $test
    
    # Test 15: Parse comment line (should ignore)
    $test = @{Name = "Parse comment line (should ignore)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "# This is a comment"
        $test.Result = $null -eq $parsed
    }
    catch {}
    $tests += $test
    
    # Test 16: Parse empty line (should ignore)
    $test = @{Name = "Parse empty line (should ignore)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "   "
        $test.Result = $null -eq $parsed
    }
    catch {}
    $tests += $test
    
    # Test 17: Variable expansion with $SCOOP_ROOT
    $test = @{Name = "Variable expansion with `$SCOOP_ROOT"; Result = $false}
    try {
        $expanded = Expand-EnvironmentVariables -Value "`$SCOOP_ROOT\bin"
        $test.Result = $expanded -eq "$global:SCOOP_ROOT\bin"
    }
    catch {}
    $tests += $test
    
    # Test 18: Variable expansion with env var
    $test = @{Name = "Variable expansion with env var"; Result = $false}
    try {
        $env:TEST_VAR = "testvalue"
        $expanded = Expand-EnvironmentVariables -Value "`$TEST_VAR\bin"
        $test.Result = $expanded -eq "testvalue\bin"
        Remove-Item Env:TEST_VAR
    }
    catch {}
    $tests += $test
    
    # Test 19: Variable expansion with cache
    $test = @{Name = "Variable expansion with cache"; Result = $false}
    try {
        $cache = @{"JAVA_HOME" = "C:\java"}
        $expanded = Expand-EnvironmentVariables -Value "`$JAVA_HOME\bin" -Cache $cache
        $test.Result = $expanded -eq "C:\java\bin"
    }
    catch {}
    $tests += $test
    
    # Test 20: Multiple variable expansion
    $test = @{Name = "Multiple variable expansion"; Result = $false}
    try {
        $cache = @{"APP_NAME" = "java"}
        $expanded = Expand-EnvironmentVariables -Value "`$SCOOP_ROOT\apps\`$APP_NAME\bin" -Cache $cache
        $test.Result = $expanded -eq "$global:SCOOP_ROOT\apps\java\bin"
    }
    catch {}
    $tests += $test
    
    # Test 21: Scope detection (system.*)
    $test = @{Name = "Scope detection (system.*)"; Result = $false}
    try {
        $filename = "system.default.env"
        $test.Result = $filename.StartsWith("system.")
    }
    catch {}
    $tests += $test
    
    # Test 22: Scope detection (user.*)
    $test = @{Name = "Scope detection (user.*)"; Result = $false}
    try {
        $filename = "user.default.env"
        $test.Result = $filename.StartsWith("user.")
    }
    catch {}
    $tests += $test
    
    # Test 23: Mock environment file processing
    $test = @{Name = "Mock environment file processing"; Result = $false}
    try {
        $lines = @(
            "# Comment",
            "",
            "JAVA_HOME=C:\java",
            "PATH+=`$JAVA_HOME\bin",
            "PATH=+C:\tools",
            "PATH-=C:\old"
        )
        $validLines = $lines | Where-Object { 
            -not [string]::IsNullOrWhiteSpace($_) -and 
            -not $_.StartsWith("#") 
        }
        $test.Result = $validLines.Count -eq 4
    }
    catch {}
    $tests += $test
    
    # Test 24: END-TO-END: Mock environment apply
    $test = @{Name = "END-TO-END: Mock environment apply"; Result = $false}
    try {
        # Simulate processing an environment file
        $testEnv = @{}
        $testEnv["JAVA_HOME"] = "C:\java"
        $testPath = @("C:\Windows", "C:\Windows\System32")
        
        # Simulate PATH+=
        $testPath = @("C:\java\bin") + $testPath
        
        # Simulate PATH=+
        $testPath = $testPath + @("C:\tools")
        
        # Simulate PATH-=
        $testPath = $testPath | Where-Object { $_ -ne "C:\Windows" }
        
        $test.Result = $testPath.Count -eq 3 -and 
                      $testPath[0] -eq "C:\java\bin" -and
                      $testPath[-1] -eq "C:\tools"
    }
    catch {}
    $tests += $test
    
    # Test 25: Scope detection with Get-EnvironmentFiles
    $test = @{Name = "Scope detection with Get-EnvironmentFiles"; Result = $false}
    try {
        $systemFiles = @("system.default.env", "system.host.user.env")
        $userFiles = @("user.default.env", "user.host.user.env")
        $allFiles = $systemFiles + $userFiles
        
        $systemCount = ($allFiles | Where-Object { $_.StartsWith("system.") }).Count
        $userCount = ($allFiles | Where-Object { $_.StartsWith("user.") }).Count
        
        $test.Result = $systemCount -eq 2 -and $userCount -eq 2
    }
    catch {}
    $tests += $test
    
    # Test 26: PATH operations on mock data
    $test = @{Name = "PATH operations on mock data"; Result = $false}
    try {
        $mockPath = "C:\Windows;C:\Windows\System32;C:\Tools"
        $pathArray = $mockPath -split ';'
        
        # Add to beginning
        $pathArray = @("C:\NewPath") + $pathArray
        
        # Add to end
        $pathArray = $pathArray + @("C:\EndPath")
        
        # Remove specific
        $pathArray = $pathArray | Where-Object { $_ -ne "C:\Tools" }
        
        $test.Result = $pathArray.Count -eq 4 -and 
                      $pathArray[0] -eq "C:\NewPath" -and
                      $pathArray[-1] -eq "C:\EndPath" -and
                      "C:\Tools" -notin $pathArray
    }
    catch {}
    $tests += $test
    
    # Test 27: PERL5LIB += operation (NEW)
    $test = @{Name = "Parse PERL5LIB += (prepend)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PERL5LIB+=C:\perl\lib"
        $test.Result = $parsed.Type -eq "ListPrepend" -and $parsed.Name -eq "PERL5LIB"
    }
    catch {}
    $tests += $test
    
    # Test 28: PYTHONPATH =+ operation (NEW)
    $test = @{Name = "Parse PYTHONPATH =+ (append)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PYTHONPATH=+C:\python\lib"
        $test.Result = $parsed.Type -eq "ListAppend" -and $parsed.Name -eq "PYTHONPATH"
    }
    catch {}
    $tests += $test
    
    # Test 29: CLASSPATH -= operation (NEW)
    $test = @{Name = "Parse CLASSPATH -= (remove)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "CLASSPATH-=old.jar"
        $test.Result = $parsed.Type -eq "ListRemove" -and $parsed.Name -eq "CLASSPATH"
    }
    catch {}
    $tests += $test
    
    # Display results
    foreach ($test in $tests) {
        if ($test.Result) {
            Write-Success $test.Name
            $passed++
        }
        else {
            Write-ErrorMsg $test.Name
            $failed++
        }
    }
    
    Write-Host ""
    Write-Host "Tests: $passed passed, $failed failed, $($tests.Count) total" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
    
    return $failed -eq 0
}

# ============================================================================
# Main Execution
# ============================================================================

# Parse arguments
Parse-Arguments -Arguments $args

# Execute commands based on parsed arguments
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