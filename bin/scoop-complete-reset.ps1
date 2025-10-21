<#
.SYNOPSIS
    Complete Scoop installation reset and cleanup
    
.DESCRIPTION
    Performs complete cleanup:
    - Removes all environment variables
    - Cleans PATH entries
    - Takes ownership and fixes permissions
    - Removes file attributes
    - Deletes all Scoop directories including junctions
    - Creates backups before deletion
    
.PARAMETER Force
    Skip confirmation prompts
    
.PARAMETER KeepPersist
    Keep persist directory (app data/settings)
    
.EXAMPLE
    .\scoop-complete-reset.ps1
    .\scoop-complete-reset.ps1 -Force
    .\scoop-complete-reset.ps1 -KeepPersist
#>

param(
    [switch]$Force,
    [switch]$KeepPersist
)

$ScoopDir = "C:\usr"
$BackupDir = "C:\usr_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

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
        exit 0
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
                & cmd /c "rmdir `"$($junction.FullName)`"" 2>$null
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
            $rdOutput = & cmd /c "rd /s /q `"\\?\$Path`" 2>&1"
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
        Write-Host "  -> Files locked, restarting Explorer..." -ForegroundColor Yellow
        try {
            # Stop Explorer
            taskkill /f /im explorer.exe 2>$null | Out-Null
            Start-Sleep -Seconds 2
            
            # Start Explorer
            Start-Process explorer
            Start-Sleep -Seconds 2
            
            # Try deletion again with cmd rd
            & cmd /c "rd /s /q `"\\?\$Path`"" 2>$null
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

# 1. Stop running Scoop processes
Write-Host ">>> Checking for running Scoop applications..." -ForegroundColor Cyan
$runningApps = Get-Process | Where-Object { 
    $_.Path -and $_.Path -like "$ScoopDir\apps\*" 
} | Select-Object Name, Id, Path

if ($runningApps) {
    Write-Host "[WARN] Running Scoop applications detected:" -ForegroundColor Yellow
    $runningApps | Format-Table -AutoSize
    
    if ($Force) {
        Write-Host "[INFO] Force mode: Stopping processes..." -ForegroundColor Yellow
        $runningApps | ForEach-Object {
            try {
                Stop-Process -Id $_.Id -Force -ErrorAction Stop
                Write-Host "[OK] Stopped: $($_.Name)" -ForegroundColor Green
            } catch {
                Write-Host "[WARN] Could not stop: $($_.Name)" -ForegroundColor Yellow
            }
        }
        Start-Sleep -Seconds 2
    } else {
        Write-Host "Stop them? [y/N]: " -NoNewline -ForegroundColor Yellow
        $stopConfirm = Read-Host
        if ($stopConfirm -eq 'y' -or $stopConfirm -eq 'Y') {
            $runningApps | ForEach-Object {
                try {
                    Stop-Process -Id $_.Id -Force
                    Write-Host "[OK] Stopped: $($_.Name)" -ForegroundColor Green
                } catch {
                    Write-Host "[WARN] Could not stop: $($_.Name)" -ForegroundColor Yellow
                }
            }
            Start-Sleep -Seconds 2
        }
    }
}

# 2. Backup environment variables
Write-Host ""
Write-Host ">>> Creating backup..." -ForegroundColor Cyan
if (-not (Test-Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
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

# 3. Clean User environment variables
Write-Host ""
Write-Host ">>> Cleaning User environment variables..." -ForegroundColor Cyan

$userVarsToRemove = @(
    'SCOOP', 'SCOOP_GLOBAL', 'SCOOP_CACHE',
    'JAVA_HOME', 'GRADLE_HOME', 'GRADLE_USER_HOME', 'MAVEN_HOME',
    'PYTHON_HOME', 'PYTHONPATH', 'PERL_HOME', 'PERL5LIB',
    'NODE_HOME', 'MSYS2_ROOT', 'GIT_HOME'
)

foreach ($var in $userVarsToRemove) {
    $currentValue = [System.Environment]::GetEnvironmentVariable($var, "User")
    if ($currentValue) {
        [System.Environment]::SetEnvironmentVariable($var, $null, "User")
        Write-Host "[OK] Removed User variable: $var" -ForegroundColor Green
    }
}

# 4. Clean Machine environment variables
Write-Host ""
Write-Host ">>> Cleaning Machine environment variables..." -ForegroundColor Cyan

foreach ($var in $userVarsToRemove) {
    $currentValue = [System.Environment]::GetEnvironmentVariable($var, "Machine")
    if ($currentValue) {
        [System.Environment]::SetEnvironmentVariable($var, $null, "Machine")
        Write-Host "[OK] Removed Machine variable: $var" -ForegroundColor Green
    }
}

# 5. Clean User PATH
Write-Host ""
Write-Host ">>> Cleaning User PATH..." -ForegroundColor Cyan
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath) {
    $pathArray = $userPath -split ';' | Where-Object { $_ -notlike "*$ScoopDir*" -and $_ -ne '' }
    $newPath = $pathArray -join ';'
    [System.Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "[OK] User PATH cleaned" -ForegroundColor Green
}

# 6. Clean Machine PATH
Write-Host ""
Write-Host ">>> Cleaning Machine PATH..." -ForegroundColor Cyan
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($machinePath) {
    $pathArray = $machinePath -split ';' | Where-Object { $_ -notlike "*$ScoopDir*" -and $_ -ne '' }
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
    Remove-DirectoryAggressively -Path $dir.Path -Description $dir.Desc
}

# 8. Clean registry
Write-Host ""
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
    Write-Host "Manual cleanup commands:" -ForegroundColor Cyan
    $remainingDirs | ForEach-Object {
        Write-Host "  rd /s /q `"\\?\$ScoopDir\$_`"" -ForegroundColor Gray
    }
} else {
    Write-Host "[OK] All directories successfully removed!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Restart PowerShell for clean environment" -ForegroundColor White
Write-Host "  2. Check: gci env: | ? { `$_.Value -like '*usr*' }" -ForegroundColor White
Write-Host "  3. Reinstall Scoop if needed" -ForegroundColor White
Write-Host ""
Write-Host "Backup location: $BackupDir" -ForegroundColor Gray