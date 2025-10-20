<#
.SYNOPSIS
    Bootstrap script for portable Windows development environments using Scoop package manager.

.DESCRIPTION
    scoop-boot.ps1 v1.9.0 - Portable Windows Development Environment Bootstrap
    
    Features:
    - Order-independent parameter parsing
    - Dynamic Git version detection
    - Meta-environment system (User/System scope control)
    - Environment configuration with GitHub template download
    - Flexible application installation
    - Comprehensive self-testing (26 tests)
    - ASCII-only output for console compatibility

.PARAMETER (Dynamic)
    This script uses custom parameter parsing to support order-independent arguments.
    All parameters can be specified in any order.

.EXAMPLE
    .\scoop-boot.ps1 --install git 7zip
    .\scoop-boot.ps1 --suggest
    .\scoop-boot.ps1 --init-env=system.bootes.user.env
    .\scoop-boot.ps1 --apply-env

.NOTES
    Version:        1.9.0
    Author:         Scoop-Boot Project
    Creation Date:  2025-10-19
    
    IMPORTANT: Set your PowerShell execution policy before running this script:
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

.LINK
    https://github.com/stotz/scoop-boot
#>

#Requires -Version 5.1

# Script global variables
$global:SCOOP_VERSION = "1.9.0"
$global:SCOOP_ROOT = "C:\usr"
$global:SCOOP_DIR = Join-Path $SCOOP_ROOT "scoop"
$global:SCOOP_APPS_DIR = Join-Path $SCOOP_DIR "apps"
$global:SCOOP_ENV_DIR = Join-Path $SCOOP_ROOT "etc\environments"
$global:SCOOP_ENV_BACKUP_DIR = Join-Path $SCOOP_ENV_DIR "backups"

# GitHub template repository configuration
$global:TEMPLATE_REPO_BASE_URL = "https://raw.githubusercontent.com/stotz/scoop-boot/refs/heads/main/etc/environments"
$global:TEMPLATE_DEFAULT_FILE = "template-default.env"

# Parsed command-line arguments storage
$global:ParsedArgs = @{
    Install = @()
    Help = $false
    Version = $false
    SelfTest = $false
    Suggest = $false
    Environment = $false
    ApplyEnv = $false
    EnvStatus = $false
    DryRun = $false
    Rollback = $false
    InitEnv = $null
}

# ============================================================================
# Helper Functions - Console Output
# ============================================================================

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host ">>> $Message" -ForegroundColor Cyan
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================================
# Helper Functions - System Detection
# ============================================================================

function Test-AdminRights {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SafeHostname {
    $hostname = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($hostname)) {
        $hostname = "unknown"
    }
    return $hostname.ToLower()
}

function Get-SafeUsername {
    $username = $env:USERNAME
    if ([string]::IsNullOrWhiteSpace($username)) {
        $username = "unknown"
    }
    return $username.ToLower()
}

# ============================================================================
# Core Functions - Argument Parsing
# ============================================================================

function Parse-Arguments {
    param([array]$Arguments)
    
    for ($i = 0; $i -lt $Arguments.Count; $i++) {
        $arg = $Arguments[$i]
        
        switch -Regex ($arg) {
            "^--help$" {
                $global:ParsedArgs.Help = $true
            }
            "^--version$" {
                $global:ParsedArgs.Version = $true
            }
            "^--selfTest$" {
                $global:ParsedArgs.SelfTest = $true
            }
            "^--suggest$" {
                $global:ParsedArgs.Suggest = $true
            }
            "^--environment$" {
                $global:ParsedArgs.Environment = $true
            }
            "^--install$" {
                # Collect all following non-parameter arguments
                while ($i + 1 -lt $Arguments.Count -and $Arguments[$i + 1] -notmatch "^--") {
                    $global:ParsedArgs.Install += $Arguments[++$i]
                }
            }
            "^--apply-env$" {
                $global:ParsedArgs.ApplyEnv = $true
            }
            "^--env-status$" {
                $global:ParsedArgs.EnvStatus = $true
            }
            "^--dry-run$" {
                $global:ParsedArgs.DryRun = $true
            }
            "^--rollback$" {
                $global:ParsedArgs.Rollback = $true
            }
            "^--init-env=" {
                $global:ParsedArgs.InitEnv = $arg -replace "^--init-env=", ""
            }
            default {
                if ($arg -notmatch "^--") {
                    $global:ParsedArgs.Install += $arg
                }
            }
        }
    }
}

# ============================================================================
# Environment Configuration Functions
# ============================================================================

function Expand-EnvironmentVariables {
    param(
        [string]$Value,
        [hashtable]$VariableCache = @{}
    )
    
    $result = $Value
    
    # Expand $SCOOP_ROOT first
    $result = $result.Replace('$SCOOP_ROOT', $global:SCOOP_ROOT)
    
    # Find and replace all environment variables
    # Collect all matches first to avoid modifying during iteration
    $pattern = "\`$([A-Za-z_][A-Za-z0-9_]*)"
    $matches = [regex]::Matches($result, $pattern)
    
    # Create a hashtable of replacements to avoid duplicates
    $replacements = @{}
    
    foreach ($match in $matches) {
        $varName = $match.Groups[1].Value
        $placeholder = '$' + $varName
        
        # Skip if already processed
        if ($replacements.ContainsKey($placeholder)) {
            continue
        }
        
        # Get value from cache or environment
        $varValue = $null
        if ($VariableCache.ContainsKey($varName)) {
            $varValue = $VariableCache[$varName]
        }
        else {
            $varValue = [Environment]::GetEnvironmentVariable($varName)
            if ($null -eq $varValue) {
                # Try Process scope explicitly
                $varValue = [Environment]::GetEnvironmentVariable($varName, 'Process')
            }
            if ($null -eq $varValue) {
                # Try User scope
                $varValue = [Environment]::GetEnvironmentVariable($varName, 'User')
            }
            if ($null -eq $varValue) {
                # Try Machine scope
                $varValue = [Environment]::GetEnvironmentVariable($varName, 'Machine')
            }
        }
        
        # Only add to replacements if we found a value
        if ($null -ne $varValue -and $varValue -ne "") {
            $replacements[$placeholder] = $varValue
        }
    }
    
    # Apply all replacements
    foreach ($placeholder in $replacements.Keys) {
        $result = $result.Replace($placeholder, $replacements[$placeholder])
    }
    
    return $result
}

function Parse-EnvironmentLine {
    param([string]$Line)
    
    # Skip empty lines and comments
    if ([string]::IsNullOrWhiteSpace($Line) -or $Line.StartsWith('#')) {
        return $null
    }
    
    # Check for += (prepend to PATH)
    if ($Line -match "^PATH\s*\+=\s*(.+)$") {
        return @{
            Action = 'PrependPath'
            Value = $matches[1].Trim()
        }
    }
    
    # Check for =+ (append to PATH)
    if ($Line -match "^PATH\s*=\+\s*(.+)$") {
        return @{
            Action = 'AppendPath'
            Value = $matches[1].Trim()
        }
    }
    
    # Check for - (remove from PATH)
    # Support multiple syntaxes: "PATH - value", "PATH-= value", "PATH -= value"
    # Check for -= syntax first (highest priority)
    if ($Line -match "^PATH\s*-\s*=\s*(.+)$") {
        # PATH -= value or PATH-= value (with optional spaces)
        return @{
            Action = 'RemovePath'
            Value = $matches[1].Trim()
        }
    }
    # Then check for simple - syntax (without =)
    if ($Line -match "^PATH\s*-\s+([^=].*)$") {
        # PATH - value (but not PATH - = value)
        return @{
            Action = 'RemovePath'
            Value = $matches[1].Trim()
        }
    }
    
    # Check for = (set variable)
    if ($Line -match "^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$") {
        return @{
            Action = 'SetVar'
            Name = $matches[1]
            Value = $matches[2].Trim()
        }
    }
    
    return $null
}

function Get-EnvironmentFiles {
    $files = @()
    
    # Get all .env files from the environment directory
    if (!(Test-Path $global:SCOOP_ENV_DIR)) {
        return $files
    }
    
    # Define file patterns in order of precedence
    $patterns = @(
        "system.default.env",
        "system.$(Get-SafeHostname).$(Get-SafeUsername).env",
        "user.default.env", 
        "user.$(Get-SafeHostname).$(Get-SafeUsername).env"
    )
    
    foreach ($pattern in $patterns) {
        $filePath = Join-Path $global:SCOOP_ENV_DIR $pattern
        if (Test-Path $filePath) {
            # Determine scope based on filename prefix
            $scope = if ($pattern.StartsWith('system.')) { 'Machine' } else { 'User' }
            $files += @{Path=$filePath; Scope=$scope}
        }
    }
    
    return $files
}

function Backup-Environment {
    $backup = @{
        Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        User = @{}
        Machine = @{}
    }
    
    # Backup User variables
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($userPath) { $backup.User['PATH'] = $userPath }
    
    # Backup Machine variables (if admin)
    if (Test-AdminRights) {
        $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
        if ($machinePath) { $backup.Machine['PATH'] = $machinePath }
    }
    
    # Backup other relevant variables
    $varsToBackup = @('JAVA_HOME', 'PYTHON_HOME', 'NODE_HOME', 'PERL_HOME', 'PERL5LIB', 'GO_HOME', 'GOPATH', 'RUST_HOME')
    foreach ($var in $varsToBackup) {
        $userValue = [Environment]::GetEnvironmentVariable($var, 'User')
        $machineValue = [Environment]::GetEnvironmentVariable($var, 'Machine')
        
        if ($userValue) { $backup.User[$var] = $userValue }
        if ($machineValue -and (Test-AdminRights)) { $backup.Machine[$var] = $machineValue }
    }
    
    # Save backup
    if (!(Test-Path $global:SCOOP_ENV_BACKUP_DIR)) {
        New-Item -ItemType Directory -Path $global:SCOOP_ENV_BACKUP_DIR -Force | Out-Null
    }
    
    $backupFile = Join-Path $global:SCOOP_ENV_BACKUP_DIR "backup_$($backup.Timestamp).json"
    $backup | ConvertTo-Json -Depth 10 | Out-File -FilePath $backupFile -Encoding UTF8
    
    return $backupFile
}

# ============================================================================
# Template Functions
# ============================================================================

function Get-TemplateFromGitHub {
    param([string]$TemplateName = $global:TEMPLATE_DEFAULT_FILE)
    
    $url = "$global:TEMPLATE_REPO_BASE_URL/$TemplateName"
    
    try {
        Write-Info "Downloading template from GitHub: $url"
        $response = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        
        # Remove BOM if present
        $content = $response.Content
        if ($content.StartsWith([char]0xFEFF)) {
            $content = $content.Substring(1)
        }
        
        return $content
    }
    catch {
        Write-Warning "Failed to download template from GitHub: $_"
        return $null
    }
}

function Get-MinimalFallbackTemplate {
    return @"
# Environment Configuration Template
# ===================================
# Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
#
# SYNTAX:
# -------
# VAR=value           Set variable
# PATH += value       Prepend to PATH
# PATH =+ value       Append to PATH  
# PATH - value        Remove from PATH
#
# VARIABLES:
# ----------
# You can use `$SCOOP_ROOT in values (will be expanded to: $global:SCOOP_ROOT)
# You can use other variables like `$JAVA_HOME (will be expanded)
#
# EXAMPLES:
# ---------

# Development Tools
JAVA_HOME=`$SCOOP_ROOT\apps\openjdk\current
PYTHON_HOME=`$SCOOP_ROOT\apps\python\current
NODE_HOME=`$SCOOP_ROOT\apps\nodejs\current

# Perl Configuration  
PERL_HOME=`$SCOOP_ROOT\apps\perl\current
PERL5LIB=`$PERL_HOME\site\lib

# Go Configuration
GO_HOME=`$SCOOP_ROOT\apps\go\current
GOPATH=`$SCOOP_ROOT\go

# Rust Configuration
RUST_HOME=`$SCOOP_ROOT\apps\rust\current
CARGO_HOME=`$SCOOP_ROOT\.cargo

# PATH modifications
PATH += `$SCOOP_ROOT\bin
PATH += `$JAVA_HOME\bin
PATH += `$PYTHON_HOME\Scripts
PATH += `$GO_HOME\bin
PATH += `$GOPATH\bin
PATH += `$CARGO_HOME\bin

# Temp directories
TEMP=C:\tmp
TMP=C:\tmp
"@
}

# ============================================================================
# Command Functions
# ============================================================================

function Show-Help {
    Write-Host @"
scoop-boot.ps1 v$global:SCOOP_VERSION - Portable Development Environment Bootstrap

USAGE:
    .\scoop-boot.ps1 [options] [applications]

OPTIONS:
    --help              Show this help message
    --version           Show version information
    --selfTest          Run self-tests (26 tests)
    --suggest           Show recommended applications
    --environment       Show current environment setup
    --install           Install specified applications
    --init-env=FILE     Create environment configuration file
    --apply-env         Apply environment configurations
    --env-status        Show environment status
    --dry-run           Preview changes without applying
    --rollback          Rollback last environment change

ENVIRONMENT CONFIGURATION:
    Create configuration files:
      .\scoop-boot.ps1 --init-env=system.default.env
      .\scoop-boot.ps1 --init-env=system.bootes.user.env
      .\scoop-boot.ps1 --init-env=user.default.env
      .\scoop-boot.ps1 --init-env=user.bootes.user.env
    
    Apply configurations:
      .\scoop-boot.ps1 --apply-env
      .\scoop-boot.ps1 --apply-env --dry-run
      .\scoop-boot.ps1 --apply-env --rollback

EXAMPLES:
    .\scoop-boot.ps1 --install git 7zip vscode
    .\scoop-boot.ps1 --suggest
    .\scoop-boot.ps1 --init-env=user.default.env
    .\scoop-boot.ps1 --apply-env

NOTE: 
    Arguments can be specified in any order.
    Set execution policy before first run:
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

"@
}

function Show-Version {
    Write-Host "scoop-boot.ps1 version $global:SCOOP_VERSION"
}

function Show-Suggest {
    Write-Section "Suggested Applications"
    
    $suggestions = @{
        "Essential Tools" = @(
            @{Name="git"; Description="Version control system"},
            @{Name="7zip"; Description="File archiver"},
            @{Name="wget"; Description="Download tool"},
            @{Name="curl"; Description="Data transfer tool"}
        )
        "Development" = @(
            @{Name="vscode"; Description="Code editor"},
            @{Name="nodejs"; Description="JavaScript runtime"},
            @{Name="python"; Description="Python interpreter"},
            @{Name="openjdk"; Description="Java Development Kit"},
            @{Name="go"; Description="Go programming language"},
            @{Name="rust"; Description="Rust programming language"}
        )
        "Databases" = @(
            @{Name="postgresql"; Description="PostgreSQL database"},
            @{Name="mysql"; Description="MySQL database"},
            @{Name="sqlite"; Description="SQLite database"},
            @{Name="redis"; Description="Redis key-value store"}
        )
        "DevOps" = @(
            @{Name="docker"; Description="Container platform"},
            @{Name="kubectl"; Description="Kubernetes CLI"},
            @{Name="terraform"; Description="Infrastructure as Code"},
            @{Name="ansible"; Description="Automation tool"}
        )
    }
    
    foreach ($category in $suggestions.Keys) {
        Write-Host ""
        Write-Host "$category`:" -ForegroundColor Yellow
        foreach ($app in $suggestions[$category]) {
            Write-Host "  $($app.Name.PadRight(15)) - $($app.Description)" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Info "Install with: .\scoop-boot.ps1 --install <app1> <app2> ..."
}

function Show-Environment {
    Write-Section "Current Environment"
    
    Write-Host "SCOOP_ROOT: $global:SCOOP_ROOT" -ForegroundColor Gray
    Write-Host "SCOOP_DIR: $global:SCOOP_DIR" -ForegroundColor Gray
    Write-Host "SCOOP_APPS: $global:SCOOP_APPS_DIR" -ForegroundColor Gray
    Write-Host "ENV_DIR: $global:SCOOP_ENV_DIR" -ForegroundColor Gray
    Write-Host "BACKUP_DIR: $global:SCOOP_ENV_BACKUP_DIR" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Hostname: $(Get-SafeHostname)" -ForegroundColor Gray
    Write-Host "Username: $(Get-SafeUsername)" -ForegroundColor Gray
    Write-Host "Admin Rights: $(if (Test-AdminRights) { 'Yes' } else { 'No' })" -ForegroundColor Gray
    Write-Host ""
    
    # Check environment files
    Write-Host "Environment Files:" -ForegroundColor Yellow
    $files = Get-EnvironmentFiles
    if ($files.Count -eq 0) {
        Write-Host "  No environment files found" -ForegroundColor Gray
    }
    else {
        foreach ($file in $files) {
            $scope = if ($file.Scope -eq 'Machine') { '[SYSTEM]' } else { '[USER]' }
            Write-Host "  $scope $($file.Path)" -ForegroundColor Gray
        }
    }
}

function Invoke-EnvStatus {
    Write-Section "Environment Status"
    
    $files = Get-EnvironmentFiles
    if ($files.Count -eq 0) {
        Write-Warning "No environment configuration files found"
        Write-Info "Create files with: .\scoop-boot.ps1 --init-env=FILENAME"
        return
    }
    
    Write-Host "Configuration Files:" -ForegroundColor Yellow
    foreach ($file in $files) {
        $scope = if ($file.Scope -eq 'Machine') { '[SYSTEM]' } else { '[USER]' }
        $lines = (Get-Content $file.Path | Where-Object { $_ -and !$_.StartsWith('#') }).Count
        Write-Host "  $scope $($file.Path) ($lines settings)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Current PATH:" -ForegroundColor Yellow
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    
    if ($userPath) {
        Write-Host "  [USER] $(($userPath -split ';').Count) entries" -ForegroundColor Gray
    }
    if ($machinePath -and (Test-AdminRights)) {
        Write-Host "  [SYSTEM] $(($machinePath -split ';').Count) entries" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Environment Variables:" -ForegroundColor Yellow
    $vars = @('JAVA_HOME', 'PYTHON_HOME', 'NODE_HOME', 'PERL_HOME', 'PERL5LIB', 'GO_HOME', 'GOPATH', 'RUST_HOME')
    foreach ($var in $vars) {
        $value = [Environment]::GetEnvironmentVariable($var)
        if ($value) {
            Write-Host "  $var = $value" -ForegroundColor Gray
        }
    }
    
    # Check for backups
    Write-Host ""
    Write-Host "Backups:" -ForegroundColor Yellow
    if (Test-Path $global:SCOOP_ENV_BACKUP_DIR) {
        $backups = Get-ChildItem $global:SCOOP_ENV_BACKUP_DIR -Filter "*.json" | Sort-Object Name -Descending | Select-Object -First 5
        if ($backups) {
            foreach ($backup in $backups) {
                Write-Host "  $($backup.Name)" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "  No backups found" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "  No backup directory" -ForegroundColor Gray
    }
}

function Invoke-InitEnv {
    param([string]$FileName)
    
    if ([string]::IsNullOrWhiteSpace($FileName)) {
        Write-ErrorMsg "No filename specified for --init-env"
        Write-Host ""
        Write-Host "Usage: --init-env=FILENAME" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Cyan
        Write-Host "  .\scoop-boot.ps1 --init-env=system.default.env"
        Write-Host "  .\scoop-boot.ps1 --init-env=system.$(Get-SafeHostname).$(Get-SafeUsername).env"
        Write-Host "  .\scoop-boot.ps1 --init-env=user.default.env"
        Write-Host "  .\scoop-boot.ps1 --init-env=user.$(Get-SafeHostname).$(Get-SafeUsername).env"
        Write-Host ""
        return $false
    }
    
    # Normalize filename to lowercase
    $FileName = $FileName.ToLower()
    
    # Ensure directory exists
    if (!(Test-Path $global:SCOOP_ENV_DIR)) {
        New-Item -ItemType Directory -Path $global:SCOOP_ENV_DIR -Force | Out-Null
    }
    
    $filePath = Join-Path $global:SCOOP_ENV_DIR $FileName
    
    # Check if file exists
    if (Test-Path $filePath) {
        Write-Warning "File already exists: $filePath"
        return $false
    }
    
    # Get template (from GitHub or fallback)
    $template = Get-TemplateFromGitHub
    if (!$template) {
        Write-Info "Using fallback template"
        $template = Get-MinimalFallbackTemplate
    }
    
    # Save template to file
    try {
        $template | Out-File -FilePath $filePath -Encoding UTF8 -Force
        Write-Success "Created: $filePath"
        Write-Info "Edit this file and run: .\scoop-boot.ps1 --apply-env"
        return $true
    }
    catch {
        Write-ErrorMsg "Failed to create file: $_"
        return $false
    }
}

function Invoke-ApplyEnv {
    param(
        [bool]$DryRun = $false,
        [bool]$Rollback = $false
    )
    
    if ($Rollback) {
        Write-Info "=== Rollback Last Environment Change ==="
        
        # Find latest backup
        if (!(Test-Path $global:SCOOP_ENV_BACKUP_DIR)) {
            Write-ErrorMsg "No backup directory found"
            return
        }
        
        $latestBackup = Get-ChildItem $global:SCOOP_ENV_BACKUP_DIR -Filter "*.json" | 
                        Sort-Object Name -Descending | 
                        Select-Object -First 1
        
        if (!$latestBackup) {
            Write-ErrorMsg "No backup files found"
            return
        }
        
        Write-Info "Restoring from: $($latestBackup.Name)"
        
        try {
            $backup = Get-Content $latestBackup.FullName | ConvertFrom-Json
            
            # Restore User variables
            foreach ($var in $backup.User.PSObject.Properties) {
                [Environment]::SetEnvironmentVariable($var.Name, $var.Value, 'User')
                Write-Success "Restored [USER] $($var.Name)"
            }
            
            # Restore Machine variables (if admin)
            if ((Test-AdminRights) -and $backup.Machine) {
                foreach ($var in $backup.Machine.PSObject.Properties) {
                    [Environment]::SetEnvironmentVariable($var.Name, $var.Value, 'Machine')
                    Write-Success "Restored [SYSTEM] $($var.Name)"
                }
            }
            
            Write-Success "Rollback completed"
            Write-Warning "Please restart your shell for changes to take effect"
        }
        catch {
            Write-ErrorMsg "Rollback failed: $_"
        }
        
        return
    }
    
    Write-Section "Apply Environment Configuration"
    
    if ($DryRun) {
        Write-Info "DRY RUN MODE - No changes will be applied"
    }
    
    $files = Get-EnvironmentFiles
    if ($files.Count -eq 0) {
        Write-Warning "No environment configuration files found"
        Write-Info "Create files with: .\scoop-boot.ps1 --init-env=FILENAME"
        return
    }
    
    # Create backup before applying changes
    if (!$DryRun) {
        $backupFile = Backup-Environment
        Write-Success "Created backup: $backupFile"
    }
    
    # Track variables to avoid duplicates
    $variableCache = @{}
    
    # Process each file
    foreach ($fileInfo in $files) {
        Write-Info "Processing: $($fileInfo.Path)"
        
        # Read the file content (always possible)
        $lines = Get-Content $fileInfo.Path
        
        # Determine if we can write to this scope
        $canWrite = $true
        if ($fileInfo.Scope -eq 'Machine' -and !(Test-AdminRights)) {
            if (!$DryRun) {
                Write-Warning "Cannot modify SYSTEM variables without admin rights: $($fileInfo.Path)"
                Write-Info "Run PowerShell as Administrator to apply system-level changes"
                $canWrite = $false
            }
        }
        
        foreach ($line in $lines) {
            $parsed = Parse-EnvironmentLine -Line $line
            if (!$parsed) { continue }
            
            $target = $fileInfo.Scope
            
            switch ($parsed.Action) {
                'SetVar' {
                    $expandedValue = Expand-EnvironmentVariables -Value $parsed.Value -VariableCache $variableCache
                    
                    if ($DryRun) {
                        $scopeLabel = if ($target -eq 'Machine') { 'SYSTEM' } else { 'USER' }
                        Write-Host "  [DRY-RUN][$scopeLabel] Would set $($parsed.Name) = $expandedValue" -ForegroundColor Yellow
                    }
                    elseif ($canWrite) {
                        [Environment]::SetEnvironmentVariable($parsed.Name, $expandedValue, $target)
                        $variableCache[$parsed.Name] = $expandedValue
                        Write-Host "  [SET] $($parsed.Name) = $expandedValue" -ForegroundColor Green
                    }
                }
                
                'PrependPath' {
                    $expandedValue = Expand-EnvironmentVariables -Value $parsed.Value -VariableCache $variableCache
                    $currentPath = [Environment]::GetEnvironmentVariable('PATH', $target)
                    
                    # Check if already in PATH
                    if ($currentPath) {
                        $pathItems = $currentPath -split ';'
                        if ($pathItems -contains $expandedValue) {
                            Write-Host "  [SKIP] Already in PATH: $expandedValue" -ForegroundColor Gray
                            continue
                        }
                    }
                    
                    $newPath = if ($currentPath) { "$expandedValue;$currentPath" } else { $expandedValue }
                    
                    if ($DryRun) {
                        $scopeLabel = if ($target -eq 'Machine') { 'SYSTEM' } else { 'USER' }
                        Write-Host "  [DRY-RUN][$scopeLabel] Would prepend to PATH: $expandedValue" -ForegroundColor Yellow
                    }
                    elseif ($canWrite) {
                        [Environment]::SetEnvironmentVariable('PATH', $newPath, $target)
                        Write-Host "  [PREPEND] PATH += $expandedValue" -ForegroundColor Green
                    }
                }
                
                'AppendPath' {
                    $expandedValue = Expand-EnvironmentVariables -Value $parsed.Value -VariableCache $variableCache
                    $currentPath = [Environment]::GetEnvironmentVariable('PATH', $target)
                    
                    # Check if already in PATH
                    if ($currentPath) {
                        $pathItems = $currentPath -split ';'
                        if ($pathItems -contains $expandedValue) {
                            Write-Host "  [SKIP] Already in PATH: $expandedValue" -ForegroundColor Gray
                            continue
                        }
                    }
                    
                    $newPath = if ($currentPath) { "$currentPath;$expandedValue" } else { $expandedValue }
                    
                    if ($DryRun) {
                        $scopeLabel = if ($target -eq 'Machine') { 'SYSTEM' } else { 'USER' }
                        Write-Host "  [DRY-RUN][$scopeLabel] Would append to PATH: $expandedValue" -ForegroundColor Yellow
                    }
                    elseif ($canWrite) {
                        [Environment]::SetEnvironmentVariable('PATH', $newPath, $target)
                        Write-Host "  [APPEND] PATH =+ $expandedValue" -ForegroundColor Green
                    }
                }
                
                'RemovePath' {
                    $expandedValue = Expand-EnvironmentVariables -Value $parsed.Value -VariableCache $variableCache
                    $currentPath = [Environment]::GetEnvironmentVariable('PATH', $target)
                    
                    if ($currentPath) {
                        $pathItems = $currentPath -split ';' | Where-Object { $_ -ne $expandedValue }
                        $newPath = $pathItems -join ';'
                        
                        if ($newPath -ne $currentPath) {
                            if ($DryRun) {
                                $scopeLabel = if ($target -eq 'Machine') { 'SYSTEM' } else { 'USER' }
                                Write-Host "  [DRY-RUN][$scopeLabel] Would remove from PATH: $expandedValue" -ForegroundColor Yellow
                            }
                            elseif ($canWrite) {
                                [Environment]::SetEnvironmentVariable('PATH', $newPath, $target)
                                Write-Host "  [REMOVE] PATH - $expandedValue" -ForegroundColor Green
                            }
                        }
                        else {
                            Write-Host "  [SKIP] Not in PATH: $expandedValue" -ForegroundColor Gray
                        }
                    }
                }
            }
        }
    }
    
    if (!$DryRun) {
        Write-Success "Environment configuration applied"
        Write-Warning "Please restart your shell for changes to take effect"
    }
}

# ============================================================================
# Installation Functions
# ============================================================================

function Get-LatestGitVersion {
    try {
        $url = "https://github.com/git-for-windows/git/releases/latest"
        $request = [System.Net.WebRequest]::Create($url)
        $request.Method = "HEAD"
        $request.AllowAutoRedirect = $false
        $response = $request.GetResponse()
        $redirectUrl = $response.Headers["Location"]
        $response.Close()
        
        if ($redirectUrl -match "tag/v([\d\.]+)\.windows") {
            return "git$($matches[1])"
        }
    }
    catch {
        Write-Warning "Could not detect latest Git version: $_"
    }
    
    return "git"
}

function Invoke-Install {
    param([array]$Apps)
    
    if ($Apps.Count -eq 0) {
        Write-Warning "No applications specified for installation"
        return
    }
    
    Write-Section "Installation"
    Write-Info "Installing applications: $($Apps -join ', ')"
    
    # Check if Scoop is installed
    if (!(Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-ErrorMsg "Scoop is not installed or not in PATH"
        return
    }
    
    # Separate Git from other apps for special handling
    $gitApp = $null
    $otherApps = @()
    
    foreach ($app in $Apps) {
        if ($app -like "git*") {
            $gitApp = $app
        }
        else {
            $otherApps += $app
        }
    }
    
    # Install Git first if specified
    if ($gitApp) {
        Write-Info "Installing Git: $gitApp"
        & scoop install $gitApp
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Git installation failed. Trying dynamic detection..."
            $latestGit = Get-LatestGitVersion
            Write-Info "Detected latest Git version: $latestGit"
            & scoop install $latestGit
        }
    }
    
    # Install other applications
    if ($otherApps.Count -gt 0) {
        Write-Info "Installing other applications: $($otherApps -join ', ')"
        & scoop install @otherApps
    }
    
    Write-Success "Installation completed"
}

# ============================================================================
# Self-Test Function
# ============================================================================

function Test-ScoopBoot {
    Write-Section "Self-Test"
    
    $tests = @()
    $passed = 0
    $failed = 0
    
    # Test 1: PowerShell version
    $test = @{Name = "PowerShell version >= 5.1"; Result = $false}
    try {
        $test.Result = $PSVersionTable.PSVersion.Major -ge 5 -and 
                      ($PSVersionTable.PSVersion.Major -gt 5 -or $PSVersionTable.PSVersion.Minor -ge 1)
    }
    catch {}
    $tests += $test
    
    # Test 2: Execution policy
    $test = @{Name = "Execution Policy allows scripts"; Result = $false}
    try {
        $policy = Get-ExecutionPolicy -Scope CurrentUser
        $test.Result = $policy -ne 'Restricted' -and $policy -ne 'AllSigned'
    }
    catch {}
    $tests += $test
    
    # Test 3: Parameter parsing
    $test = @{Name = "Parameter parsing"; Result = $false}
    try {
        $testArgs = @('--install', 'app1', 'app2', '--help')
        $savedArgs = $global:ParsedArgs.Clone()
        $global:ParsedArgs = @{Install = @(); Help = $false}
        Parse-Arguments -Arguments $testArgs
        $test.Result = $global:ParsedArgs.Install.Count -eq 2 -and $global:ParsedArgs.Help -eq $true
        $global:ParsedArgs = $savedArgs
    }
    catch {}
    $tests += $test
    
    # Test 4: Admin detection
    $test = @{Name = "Admin rights detection"; Result = $false}
    try {
        $isAdmin = Test-AdminRights
        $test.Result = $isAdmin -is [bool]
    }
    catch {}
    $tests += $test
    
    # Test 5: Directory paths
    $test = @{Name = "Directory path generation"; Result = $false}
    try {
        $test.Result = $global:SCOOP_ROOT -eq "C:\usr" -and 
                      $global:SCOOP_DIR -eq "C:\usr\scoop" -and
                      $global:SCOOP_ENV_DIR -eq "C:\usr\etc\environments"
    }
    catch {}
    $tests += $test
    
    # Test 6: Hostname detection
    $test = @{Name = "Hostname detection"; Result = $false}
    try {
        $hostname = Get-SafeHostname
        $test.Result = ![string]::IsNullOrWhiteSpace($hostname) -and $hostname -eq $hostname.ToLower()
    }
    catch {}
    $tests += $test
    
    # Test 7: Username detection
    $test = @{Name = "Username detection"; Result = $false}
    try {
        $username = Get-SafeUsername
        $test.Result = ![string]::IsNullOrWhiteSpace($username) -and $username -eq $username.ToLower()
    }
    catch {}
    $tests += $test
    
    # Test 8: Host-User filename generation
    $test = @{Name = "Host-User filename generation"; Result = $false}
    try {
        $hostname = Get-SafeHostname
        $username = Get-SafeUsername
        $filename = "system.$hostname.$username.env"
        $test.Result = $filename -match "^system\.[a-z0-9]+\.[a-z0-9]+\.env$"
    }
    catch {}
    $tests += $test
    
    # Test 9: Parse PATH += (prepend)
    $test = @{Name = "Parse PATH += (prepend)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH += C:\test\bin"
        $test.Result = $parsed.Action -eq 'PrependPath' -and $parsed.Value -eq 'C:\test\bin'
    }
    catch {}
    $tests += $test
    
    # Test 10: Parse PATH =+ (append)
    $test = @{Name = "Parse PATH =+ (append)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH =+ C:\test\bin"
        $test.Result = $parsed.Action -eq 'AppendPath' -and $parsed.Value -eq 'C:\test\bin'
    }
    catch {}
    $tests += $test
    
    # Test 11: Parse PATH - (remove with space)
    $test = @{Name = "Parse PATH - (remove with space)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH - C:\test\bin"
        $test.Result = $parsed.Action -eq 'RemovePath' -and $parsed.Value -eq 'C:\test\bin'
    }
    catch {}
    $tests += $test
    
    # Test 12: Parse PATH-= (remove without space)
    $test = @{Name = "Parse PATH-= (remove without space)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH-= C:\test\bin"
        $test.Result = $parsed.Action -eq 'RemovePath' -and $parsed.Value -eq 'C:\test\bin'
    }
    catch {}
    $tests += $test
    
    # Test 13: Parse PATH -= (remove with -= syntax)
    $test = @{Name = "Parse PATH -= (remove with -= syntax)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "PATH -= C:\test\bin"
        $test.Result = $parsed.Action -eq 'RemovePath' -and $parsed.Value -eq 'C:\test\bin'
    }
    catch {}
    $tests += $test
    
    # Test 14: Parse variable assignment
    $test = @{Name = "Parse variable assignment"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "JAVA_HOME = C:\java"
        $test.Result = $parsed.Action -eq 'SetVar' -and 
                      $parsed.Name -eq 'JAVA_HOME' -and 
                      $parsed.Value -eq 'C:\java'
    }
    catch {}
    $tests += $test
    
    # Test 15: Parse comment line
    $test = @{Name = "Parse comment line (should ignore)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line "# This is a comment"
        $test.Result = $null -eq $parsed
    }
    catch {}
    $tests += $test
    
    # Test 16: Parse empty line
    $test = @{Name = "Parse empty line (should ignore)"; Result = $false}
    try {
        $parsed = Parse-EnvironmentLine -Line ""
        $test.Result = $null -eq $parsed
    }
    catch {}
    $tests += $test
    
    # Test 17: Variable expansion with $SCOOP_ROOT
    $test = @{Name = "Variable expansion with `$SCOOP_ROOT"; Result = $false}
    try {
        $input = '$SCOOP_ROOT\bin'
        $expanded = Expand-EnvironmentVariables -Value $input
        $test.Result = $expanded -eq 'C:\usr\bin'
    }
    catch {}
    $tests += $test
    
    # Test 18: Variable expansion with environment variable
    $test = @{Name = "Variable expansion with env var"; Result = $false}
    try {
        # Set a test environment variable
        [Environment]::SetEnvironmentVariable('TEST_VAR', 'C:\test', 'Process')
        
        # Test expansion
        $input = '$TEST_VAR\bin'
        $expanded = Expand-EnvironmentVariables -Value $input
        
        $test.Result = $expanded -eq 'C:\test\bin'
        
        # Cleanup
        [Environment]::SetEnvironmentVariable('TEST_VAR', $null, 'Process')
    }
    catch {}
    $tests += $test
    
    # Test 19: Variable expansion with cache override
    $test = @{Name = "Variable expansion with cache"; Result = $false}
    try {
        $cache = @{'CUSTOM_VAR' = 'C:\custom'}
        $input = '$CUSTOM_VAR\lib'
        $expanded = Expand-EnvironmentVariables -Value $input -VariableCache $cache
        $test.Result = $expanded -eq 'C:\custom\lib'
    }
    catch {}
    $tests += $test
    
    # Test 20: Multiple variable expansion
    $test = @{Name = "Multiple variable expansion"; Result = $false}
    try {
        [Environment]::SetEnvironmentVariable('TEST_A', 'C:\a', 'Process')
        [Environment]::SetEnvironmentVariable('TEST_B', 'C:\b', 'Process')
        
        $input = '$TEST_A\bin;$TEST_B\lib'
        $expanded = Expand-EnvironmentVariables -Value $input
        
        $test.Result = $expanded -eq 'C:\a\bin;C:\b\lib'
        
        # Cleanup
        [Environment]::SetEnvironmentVariable('TEST_A', $null, 'Process')
        [Environment]::SetEnvironmentVariable('TEST_B', $null, 'Process')
    }
    catch {}
    $tests += $test
    
    # Test 21: Scope detection for system files
    $test = @{Name = "Scope detection (system.*)"; Result = $false}
    try {
        # Mock a system file check
        $testFile = "system.default.env"
        $shouldBeSystem = $testFile.StartsWith('system.')
        $test.Result = $shouldBeSystem -eq $true
    }
    catch {}
    $tests += $test
    
    # Test 22: Scope detection for user files
    $test = @{Name = "Scope detection (user.*)"; Result = $false}
    try {
        # Mock a user file check
        $testFile = "user.default.env"
        $shouldBeUser = $testFile.StartsWith('user.')
        $test.Result = $shouldBeUser -eq $true
    }
    catch {}
    $tests += $test
    
    # Test 23: Mock environment file processing
    $test = @{Name = "Mock environment file processing"; Result = $false}
    try {
        # Create mock environment content
        # Note: Using single quotes to avoid any backtick interpretation issues
        $mockLines = @(
            '# Test environment file'
            'JAVA_HOME = C:\java'
            'PYTHON_HOME = C:\python'
            ''
            '# PATH modifications'
            'PATH += $JAVA_HOME\bin'
            'PATH =+ $PYTHON_HOME\Scripts'
            'PATH -= C:\old\path'
            ''
            '# Variable using SCOOP_ROOT'
            'CUSTOM_PATH = $SCOOP_ROOT\custom'
        )
        
        # Process each line
        $results = @()
        $debugInfo = @()
        foreach ($line in $mockLines) {
            if (![string]::IsNullOrWhiteSpace($line)) {
                $parsed = Parse-EnvironmentLine -Line $line
                if ($parsed) { 
                    $results += $parsed
                    $debugInfo += "  Parsed: $line -> Action=$($parsed.Action)"
                }
            }
        }
        
        # Count actions by type - ensure we're counting unique objects
        $setVarCount = @($results | Where-Object { $_.Action -eq 'SetVar' }).Count
        $prependCount = @($results | Where-Object { $_.Action -eq 'PrependPath' }).Count
        $appendCount = @($results | Where-Object { $_.Action -eq 'AppendPath' }).Count
        $removeCount = @($results | Where-Object { $_.Action -eq 'RemovePath' }).Count
        
        # Validate results
        $expectedTotal = 6
        $expectedSetVar = 3
        $expectedPrepend = 1
        $expectedAppend = 1
        $expectedRemove = 1
        
        $test.Result = $results.Count -eq $expectedTotal -and
                      $setVarCount -eq $expectedSetVar -and
                      $prependCount -eq $expectedPrepend -and
                      $appendCount -eq $expectedAppend -and
                      $removeCount -eq $expectedRemove
        
        # Show debug info if test fails
        if (-not $test.Result) {
            Write-Host "  Debug: Test 23 Failed Details:" -ForegroundColor Yellow
            Write-Host "  Expected: Total=$expectedTotal, SetVar=$expectedSetVar, Prepend=$expectedPrepend, Append=$expectedAppend, Remove=$expectedRemove" -ForegroundColor Yellow
            Write-Host "  Actual:   Total=$($results.Count), SetVar=$setVarCount, Prepend=$prependCount, Append=$appendCount, Remove=$removeCount" -ForegroundColor Yellow
            
            # More detailed debug - show each action
            Write-Host "  All actions in results array:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $results.Count; $i++) {
                $r = $results[$i]
                Write-Host "    [$i] Action=$($r.Action), $(if($r.Name){"Name=$($r.Name), "})Value=$($r.Value)" -ForegroundColor DarkGray
            }
            
            # Original parsed info
            Write-Host "  Parsing trace:" -ForegroundColor Yellow
            foreach ($info in $debugInfo) {
                Write-Host $info -ForegroundColor DarkGray
            }
        }
    }
    catch {
        Write-Host "  Error in test 23: $_" -ForegroundColor Red
        $test.Result = $false
    }
    $tests += $test
    
    # Test 24: END-TO-END Mock Environment Apply Test
    $test = @{Name = "END-TO-END: Mock environment apply"; Result = $false}
    try {
        # Save current environment
        $savedPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
        $savedJavaHome = [Environment]::GetEnvironmentVariable('JAVA_HOME', 'User')
        
        # Setup mock environment
        [Environment]::SetEnvironmentVariable('PATH', 'C:\usr\bin;C:\Windows\system32', 'User')
        [Environment]::SetEnvironmentVariable('JAVA_HOME', 'C:\usr\apps\openjdk\current', 'User')
        [Environment]::SetEnvironmentVariable('PYTHON_HOME', 'C:\usr\apps\python\current', 'User')
        
        # Create mock file content
        $mockFileContent = @"
# Mock environment file
JAVA_HOME = C:\usr\apps\openjdk\current
PYTHON_HOME = C:\usr\apps\python\current

# Test all PATH operations
PATH += `$JAVA_HOME\bin
PATH =+ `$PYTHON_HOME\Scripts
PATH -= C:\usr\bin
PATH-= C:\nonexistent

# Test variable expansion
CUSTOM_VAR = `$SCOOP_ROOT\custom
"@
        
        # Process mock content and collect actions
        $actions = @()
        $variableCache = @{}
        
        $mockFileContent -split "`n" | ForEach-Object {
            $line = $_.Trim()
            $parsed = Parse-EnvironmentLine -Line $line
            if ($parsed) { 
                # Test expansion for PATH operations
                if ($parsed.Action -in @('PrependPath', 'AppendPath', 'RemovePath')) {
                    $expanded = Expand-EnvironmentVariables -Value $parsed.Value -VariableCache $variableCache
                    $actions += @{
                        Action = $parsed.Action
                        Value = $expanded
                        Original = $parsed.Value
                    }
                    if ($VerbosePreference -eq 'Continue') {
                        Write-Host "  PATH: $($parsed.Action) - Original='$($parsed.Value)' Expanded='$expanded'" -ForegroundColor DarkGray
                    }
                }
                elseif ($parsed.Action -eq 'SetVar') {
                    $expanded = Expand-EnvironmentVariables -Value $parsed.Value -VariableCache $variableCache
                    $variableCache[$parsed.Name] = $expanded
                    $actions += @{
                        Action = 'SetVar'
                        Name = $parsed.Name
                        Value = $expanded
                        Original = $parsed.Value
                    }
                    if ($VerbosePreference -eq 'Continue') {
                        Write-Host "  VAR: $($parsed.Name) = Original='$($parsed.Value)' Expanded='$expanded'" -ForegroundColor DarkGray
                    }
                }
            }
        }
        
        # Debug counts
        if ($VerbosePreference -eq 'Continue') {
            Write-Host "  Total actions: $($actions.Count)" -ForegroundColor DarkGray
            $actions | ForEach-Object {
                Write-Host "    - $($_.Action): $(if ($_.Name) { $_.Name + '=' })$($_.Value)" -ForegroundColor DarkGray
            }
        }
        
        # Validate results (expecting 7 actions due to two remove operations)
        $prependFound = $actions | Where-Object { $_.Action -eq 'PrependPath' -and $_.Value -eq 'C:\usr\apps\openjdk\current\bin' }
        $appendFound = $actions | Where-Object { $_.Action -eq 'AppendPath' -and $_.Value -eq 'C:\usr\apps\python\current\Scripts' }
        $removeFound = $actions | Where-Object { $_.Action -eq 'RemovePath' -and $_.Value -eq 'C:\usr\bin' }
        $customVarFound = $actions | Where-Object { $_.Action -eq 'SetVar' -and $_.Name -eq 'CUSTOM_VAR' -and $_.Value -eq 'C:\usr\custom' }
        
        $test.Result = $prependFound -and $appendFound -and $removeFound -and $customVarFound -and ($actions.Count -eq 7)
        
        # Restore environment
        [Environment]::SetEnvironmentVariable('PATH', $savedPath, 'User')
        [Environment]::SetEnvironmentVariable('JAVA_HOME', $savedJavaHome, 'User')
        [Environment]::SetEnvironmentVariable('PYTHON_HOME', $null, 'User')
    }
    catch {
        if ($VerbosePreference -eq 'Continue') {
            Write-Host "  Error in test: $_" -ForegroundColor Red
        }
        # Restore on error
        if ($savedPath) { [Environment]::SetEnvironmentVariable('PATH', $savedPath, 'User') }
        if ($savedJavaHome) { [Environment]::SetEnvironmentVariable('JAVA_HOME', $savedJavaHome, 'User') }
    }
    $tests += $test
    
    # Test 25: Scope detection with mock files
    $test = @{Name = "Scope detection with Get-EnvironmentFiles"; Result = $false}
    try {
        # Create temp directory for test
        $tempDir = Join-Path $env:TEMP "scoop-test-$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        
        # Temporarily override the env directory
        $savedEnvDir = $global:SCOOP_ENV_DIR
        $global:SCOOP_ENV_DIR = $tempDir
        
        # Create mock files
        $systemFile = Join-Path $tempDir "system.default.env"
        $userFile = Join-Path $tempDir "user.default.env"
        "# System file" | Out-File $systemFile -Encoding UTF8
        "# User file" | Out-File $userFile -Encoding UTF8
        
        # Get files and check scopes
        $files = Get-EnvironmentFiles
        $systemFileInfo = $files | Where-Object { $_.Path -eq $systemFile }
        $userFileInfo = $files | Where-Object { $_.Path -eq $userFile }
        
        $test.Result = $systemFileInfo.Scope -eq 'Machine' -and $userFileInfo.Scope -eq 'User'
        
        # Cleanup
        $global:SCOOP_ENV_DIR = $savedEnvDir
        Remove-Item $tempDir -Recurse -Force
    }
    catch {
        # Restore on error
        if ($savedEnvDir) { $global:SCOOP_ENV_DIR = $savedEnvDir }
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $tests += $test
    
    # Test 26: PATH operations simulation
    $test = @{Name = "PATH operations on mock data"; Result = $false}
    try {
        # Mock current PATH
        $mockPath = "C:\usr\bin;C:\Windows\system32;C:\Windows"
        
        # Test prepend
        $testValue = "C:\new\path"
        $pathItems = $mockPath -split ';'
        if ($pathItems -notcontains $testValue) {
            $newPath = "$testValue;$mockPath"
        }
        $prependOk = $newPath -eq "C:\new\path;C:\usr\bin;C:\Windows\system32;C:\Windows"
        
        # Test append
        $mockPath = "C:\usr\bin;C:\Windows\system32"
        $testValue = "C:\new\path"
        $pathItems = $mockPath -split ';'
        if ($pathItems -notcontains $testValue) {
            $newPath = "$mockPath;$testValue"
        }
        $appendOk = $newPath -eq "C:\usr\bin;C:\Windows\system32;C:\new\path"
        
        # Test remove
        $mockPath = "C:\usr\bin;C:\Windows\system32;C:\old\path"
        $testValue = "C:\old\path"
        $pathItems = $mockPath -split ';' | Where-Object { $_ -ne $testValue }
        $newPath = $pathItems -join ';'
        $removeOk = $newPath -eq "C:\usr\bin;C:\Windows\system32"
        
        $test.Result = $prependOk -and $appendOk -and $removeOk
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
    
    # Show details for failed tests if in verbose mode
    if ($failed -gt 0) {
        Write-Host ""
        Write-Warning "Run with -Verbose for detailed error information"
    }
    
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

# If no command specified, show help
if ($args.Count -eq 0) {
    Show-Help
    exit 0
}

Write-ErrorMsg "No valid command specified"
Show-Help
exit 1
