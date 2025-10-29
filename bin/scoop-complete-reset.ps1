<#
.SYNOPSIS
    Complete Scoop installation reset and cleanup
    
.DESCRIPTION
    Performs complete cleanup:
    - ROBUST process detection using handle64.exe
    - Removes all environment variables
    - Cleans PATH entries
    - Takes ownership and fixes permissions
    - Removes file attributes
    - Deletes all Scoop directories including junctions
    - Creates backups before deletion
    - PRESERVES: C:\usr\bin\ and C:\usr\etc\
    
.NOTES
    Version: 2.2.0
    Date: 2025-01-29
    
    Changes in v2.2.0:
    - NEW: Uses handle64.exe for COMPLETE process detection
    - CRITICAL FIX: Finds ALL processes (including keyboxd, gpg-agent, etc.)
    - Detects background services without .Path property
    - Kills GnuPG/SSH agents that Get-Process misses
    - No more manual process hunting required
    
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

# ============================================================================
# 1. ROBUST PROCESS DETECTION - Uses handle64.exe for COMPLETE coverage
# ============================================================================
Write-Host ">>> Checking for running Scoop applications..." -ForegroundColor Cyan
Write-Host ""

# Method 1: Kill known system tray apps first (they always block)
Write-Host "[INFO] Stopping known system tray applications..." -ForegroundColor Gray
$systemTrayApps = @('greenshot', 'jetbrains-toolbox', 'everything', 'mousejiggler', 'keyboxd', 'gpg-agent', 'ssh-agent')
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
                $pid = [int]$Matches[2]
                if (-not $processesToKill.ContainsKey($pid)) {
                    $processesToKill[$pid] = $exeName
                }
            }
        }

        if ($processesToKill.Count -gt 0) {
            Write-Host "  [FOUND] $($processesToKill.Count) processes with open handles:" -ForegroundColor Yellow
            foreach ($pid in $processesToKill.Keys) {
                $exeName = $processesToKill[$pid]
                Write-Host "    - $exeName (PID: $pid)" -ForegroundColor Yellow

                try {
                    Stop-Process -Id $pid -Force -ErrorAction Stop
                    Write-Host "      [OK] Killed PID $pid" -ForegroundColor Green
                } catch {
                    Write-Host "      [FAIL] Could not kill PID $pid" -ForegroundColor Red
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

$varsToRemove = @(
    'SCOOP', 'SCOOP_GLOBAL', 'SCOOP_CACHE',
    'JAVA_HOME', 'JAVA_OPTS',
    'GRADLE_HOME', 'GRADLE_USER_HOME', 'GRADLE_OPTS',
    'MAVEN_HOME', 'M2_HOME', 'M2_REPO', 'MAVEN_OPTS',
    'ANT_HOME',
    'KOTLIN_HOME',
    'PYTHON_HOME', 'PYTHONPATH',
    'PERL_HOME', 'PERL5LIB',
    'NODE_HOME', 'NODE_PATH', 'NPM_CONFIG_PREFIX',
    'MSYS2_HOME', 'MSYS2_ROOT',
    'GIT_HOME', 'GIT_INSTALL_ROOT',
    'SVN_HOME',
    'MAKE_HOME',
    'CMAKE_HOME',
    'VCPKG_ROOT',
    'BAT_CONFIG_DIR',
    'LANG', 'LC_ALL', 'LANGUAGE'
)

foreach ($var in $varsToRemove) {
    $currentValue = [System.Environment]::GetEnvironmentVariable($var, "User")
    if ($currentValue) {
        [System.Environment]::SetEnvironmentVariable($var, $null, "User")
        Write-Host "[OK] Removed User variable: $var" -ForegroundColor Green
    }
}

# 4. Clean Machine environment variables
Write-Host ""
Write-Host ">>> Cleaning Machine environment variables..." -ForegroundColor Cyan

foreach ($var in $varsToRemove) {
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
Write-Host "  1. Restart PowerShell for clean environment" -ForegroundColor White
Write-Host "  2. Check: gci env: | ? { `$_.Value -like '*usr*' }" -ForegroundColor White
Write-Host "  3. Reinstall Scoop if needed" -ForegroundColor White
Write-Host ""
Write-Host "Backup location: $BackupDir" -ForegroundColor Gray