<#
.SYNOPSIS
    Complete reset and cleanup of Scoop installation for testing
    
.DESCRIPTION
    This script performs a complete cleanup:
    - Removes all environment variables
    - Cleans PATH entries
    - Deletes Scoop directories
    - Creates backups before deletion
    
.PARAMETER Force
    Skip confirmation prompts
    
.PARAMETER KeepPersist
    Keep persist directory (contains app data/settings)
    
.EXAMPLE
    # Full cleanup with confirmation
    .\scoop-complete-reset.ps1
    
    # Full cleanup without prompts
    .\scoop-complete-reset.ps1 -Force
    
    # Cleanup but keep app settings
    .\scoop-complete-reset.ps1 -KeepPersist
#>

param(
    [switch]$Force,
    [switch]$KeepPersist
)

$ScoopDir = "C:\usr"
$BackupDir = "C:\usr_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

Write-Host ""
Write-Host "=== Scoop Complete Reset and Cleanup ===" -ForegroundColor Red
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
    Write-Host "Continue? (type 'yes' to confirm): " -ForegroundColor Red -NoNewline
    $confirmation = Read-Host
    if ($confirmation -ne 'yes') {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# ============================================================================
# PART 1: BACKUP IMPORTANT DATA
# ============================================================================
Write-Host ""
Write-Host ">>> Creating backup..." -ForegroundColor Cyan

if (Test-Path $ScoopDir) {
    # Backup persist and environment configs
    $backupItems = @(
        @{Source="$ScoopDir\persist"; Name="persist"},
        @{Source="$ScoopDir\etc"; Name="etc"},
        @{Source="$ScoopDir\bin\scoop-boot.ps1"; Name="scoop-boot.ps1"}
    )
    
    foreach ($item in $backupItems) {
        if (Test-Path $item.Source) {
            $destPath = Join-Path $BackupDir $item.Name
            $destDir = Split-Path $destPath -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item -Path $item.Source -Destination $destPath -Recurse -Force
            Write-Host "[OK] Backed up: $($item.Name)" -ForegroundColor Green
        }
    }
    Write-Host "[INFO] Backup saved to: $BackupDir" -ForegroundColor Gray
}

# ============================================================================
# PART 2: REMOVE ENVIRONMENT VARIABLES (RUN AS ADMIN FOR SYSTEM VARS)
# ============================================================================
Write-Host ""
Write-Host ">>> Cleaning environment variables..." -ForegroundColor Cyan

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

# Variables to remove
$varsToRemove = @(
    'SCOOP', 'SCOOP_GLOBAL',
    'JAVA_HOME', 'JAVA_OPTS',
    'PYTHON_HOME', 'PYTHONPATH',
    'PERL_HOME', 'PERL5LIB',
    'NODE_HOME', 'NODE_PATH', 'NPM_CONFIG_PREFIX',
    'MAVEN_HOME', 'M2_HOME', 'M2_REPO', 'MAVEN_OPTS',
    'GRADLE_HOME', 'GRADLE_USER_HOME', 'GRADLE_OPTS',
    'ANT_HOME', 'KOTLIN_HOME',
    'CMAKE_HOME', 'MAKE_HOME',
    'MSYS2_HOME',
    'SVN_HOME', 'GIT_HOME', 'GIT_SSH',
    'LANG', 'LC_ALL', 'LANGUAGE'
)

foreach ($var in $varsToRemove) {
    # Remove from User scope
    [Environment]::SetEnvironmentVariable($var, $null, 'User')
    Write-Host "[OK] Removed $var from User environment" -ForegroundColor Green
    
    # Remove from System scope if admin
    if ($isAdmin) {
        [Environment]::SetEnvironmentVariable($var, $null, 'Machine')
        Write-Host "[OK] Removed $var from System environment" -ForegroundColor Green
    }
    
    # Remove from current session
    Remove-Item "Env:\$var" -ErrorAction SilentlyContinue
}

if (-not $isAdmin) {
    Write-Host "[WARN] Not running as admin - System variables not cleaned" -ForegroundColor Yellow
    Write-Host "      Run as administrator to clean System environment" -ForegroundColor Yellow
}

# ============================================================================
# PART 3: CLEAN PATH VARIABLE
# ============================================================================
Write-Host ""
Write-Host ">>> Cleaning PATH entries..." -ForegroundColor Cyan

# PATH entries to remove (patterns)
$pathPatternsToRemove = @(
    "$ScoopDir\*",
    "*\apps\*\current*",
    "*\shims",
    "*\bin",
    "*perl*",
    "*python*",
    "*nodejs*",
    "*java*",
    "*temurin*",
    "*gradle*",
    "*maven*",
    "*msys2*"
)

function Clean-PathVariable {
    param(
        [string]$Scope,
        [string[]]$Patterns
    )
    
    $currentPath = [Environment]::GetEnvironmentVariable('Path', $Scope)
    if ($currentPath) {
        $paths = $currentPath -split ';' | Where-Object { $_ }
        $cleanPaths = @()
        $removedCount = 0
        
        foreach ($path in $paths) {
            $shouldRemove = $false
            foreach ($pattern in $Patterns) {
                if ($path -like $pattern) {
                    $shouldRemove = $true
                    $removedCount++
                    Write-Host "  [-] Removing: $path" -ForegroundColor Red
                    break
                }
            }
            if (-not $shouldRemove) {
                $cleanPaths += $path
            }
        }
        
        $newPath = $cleanPaths -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, $Scope)
        Write-Host "[OK] Removed $removedCount PATH entries from $Scope scope" -ForegroundColor Green
    }
}

# Clean User PATH
Clean-PathVariable -Scope 'User' -Patterns $pathPatternsToRemove

# Clean System PATH if admin
if ($isAdmin) {
    Clean-PathVariable -Scope 'Machine' -Patterns $pathPatternsToRemove
} else {
    Write-Host "[WARN] Not running as admin - System PATH not cleaned" -ForegroundColor Yellow
}

# ============================================================================
# PART 4: DELETE SCOOP DIRECTORIES (PRESERVING bin AND etc)
# ============================================================================
Write-Host ""
Write-Host ">>> Removing Scoop directories..." -ForegroundColor Cyan
Write-Host "[INFO] Preserving: $ScoopDir\bin" -ForegroundColor Gray
Write-Host "[INFO] Preserving: $ScoopDir\etc" -ForegroundColor Gray

if (Test-Path $ScoopDir) {
    # Directories to delete (NOT including bin and etc!)
    $dirsToDelete = @('apps', 'buckets', 'cache', 'shims')
    
    if (-not $KeepPersist) {
        $dirsToDelete += 'persist'
    } else {
        Write-Host "[INFO] Preserving: $ScoopDir\persist (KeepPersist flag set)" -ForegroundColor Gray
    }
    
    Write-Host ""
    foreach ($dir in $dirsToDelete) {
        $fullPath = Join-Path $ScoopDir $dir
        if (Test-Path $fullPath) {
            try {
                # Count items before deletion for info
                $itemCount = (Get-ChildItem $fullPath -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object).Count
                Remove-Item -Path $fullPath -Recurse -Force -ErrorAction Stop
                Write-Host "[OK] Deleted: $dir ($itemCount items removed)" -ForegroundColor Green
            } catch {
                Write-Host "[ERROR] Failed to delete $dir : $_" -ForegroundColor Red
                Write-Host "       Try closing all applications and run again" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[INFO] Not found: $dir (already clean)" -ForegroundColor Gray
        }
    }
    
    # Clean up ONLY Scoop core files from bin, but keep user scripts
    Write-Host ""
    Write-Host ">>> Cleaning Scoop core files from bin..." -ForegroundColor Cyan
    $scoopCoreFiles = @(
        "$ScoopDir\bin\scoop.ps1",
        "$ScoopDir\bin\scoop.cmd",
        "$ScoopDir\bin\scoop",
        "$ScoopDir\bin\checkver.ps1",
        "$ScoopDir\bin\formatjson.ps1",
        "$ScoopDir\bin\getopt.ps1",
        "$ScoopDir\bin\missing-checkver.ps1"
    )
    
    foreach ($file in $scoopCoreFiles) {
        if (Test-Path $file) {
            Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Deleted Scoop file: $(Split-Path -Leaf $file)" -ForegroundColor Green
        }
    }
    
    # Keep scoop-boot.ps1 and other user scripts
    if (Test-Path "$ScoopDir\bin\scoop-boot.ps1") {
        Write-Host "[INFO] Preserved: scoop-boot.ps1" -ForegroundColor Gray
    }
    
    # Show what remains in the Scoop directory
    Write-Host ""
    Write-Host ">>> Remaining structure in $ScoopDir :" -ForegroundColor Cyan
    $remaining = Get-ChildItem $ScoopDir -Force | Select-Object Name, @{N='Type';E={if($_.PSIsContainer){'Directory'}else{'File'}}}
    if ($remaining) {
        $remaining | ForEach-Object {
            $icon = if ($_.Type -eq 'Directory') { "[D]" } else { "[F]" }
            Write-Host "  $icon $($_.Name)" -ForegroundColor $(if ($_.Name -in @('bin','etc','persist')) { 'Green' } else { 'Gray' })
        }
    }
}

# ============================================================================
# PART 5: CLEAN REGISTRY ENTRIES
# ============================================================================
Write-Host ""
Write-Host ">>> Cleaning registry entries..." -ForegroundColor Cyan

# Registry keys to check and remove
$regKeys = @(
    "HKCU:\Software\Classes\Directory\shell\git_shell",
    "HKCU:\Software\Classes\Directory\shell\git_gui",
    "HKCU:\Software\Classes\Directory\Background\shell\git_shell",
    "HKCU:\Software\Classes\Directory\Background\shell\git_gui",
    "HKCU:\Software\Classes\*\shell\Open with Notepad++",
    "HKCU:\Software\Classes\*\shell\VSCode",
    "HKCU:\Software\Classes\Directory\shell\VSCode",
    "HKCU:\Software\Classes\Directory\Background\shell\VSCode",
    "HKCU:\Software\Python\PythonCore\3.13",
    "HKLM:\SOFTWARE\Classes\Directory\shell\git_shell",
    "HKLM:\SOFTWARE\Classes\*\shell\Open with Notepad++"
)

foreach ($key in $regKeys) {
    if (Test-Path $key) {
        try {
            Remove-Item -Path $key -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] Removed registry key: $key" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Could not remove: $key" -ForegroundColor Yellow
        }
    }
}

# ============================================================================
# PART 6: CLEAN START MENU SHORTCUTS
# ============================================================================
Write-Host ""
Write-Host ">>> Cleaning Start Menu shortcuts..." -ForegroundColor Cyan

$shortcutDirs = @(
    "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Scoop Apps",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Scoop Apps"
)

foreach ($dir in $shortcutDirs) {
    if (Test-Path $dir) {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Removed shortcuts: $dir" -ForegroundColor Green
    }
}

# ============================================================================
# FINAL STATUS
# ============================================================================
Write-Host ""
Write-Host "=== Cleanup Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Backup saved to: $BackupDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "System has been reset. You can now:" -ForegroundColor Yellow
Write-Host "1. Restart PowerShell/CMD for clean environment" -ForegroundColor White
Write-Host "2. Run installation script to start fresh:" -ForegroundColor White
Write-Host "   .\scoop-complete-install.ps1 -SetEnvironment  (as admin)" -ForegroundColor Gray
Write-Host "   .\scoop-complete-install.ps1 -InstallTools    (as user)" -ForegroundColor Gray
Write-Host ""
Write-Host "To restore backup data:" -ForegroundColor Yellow
Write-Host "   Copy from: $BackupDir" -ForegroundColor Gray
Write-Host "   To: $ScoopDir" -ForegroundColor Gray
Write-Host ""

# Show remaining environment variables for verification
Write-Host "Remaining Scoop-related environment variables:" -ForegroundColor Cyan
$allVars = [System.Environment]::GetEnvironmentVariables()
$scoopRelated = $allVars.Keys | Where-Object { 
    $allVars[$_] -like "*scoop*" -or 
    $allVars[$_] -like "*$ScoopDir*" -or
    $_ -in $varsToRemove
}

if ($scoopRelated) {
    foreach ($var in $scoopRelated) {
        Write-Host "  $var = $($allVars[$var])" -ForegroundColor Yellow
    }
} else {
    Write-Host "  None found - system is clean!" -ForegroundColor Green
}