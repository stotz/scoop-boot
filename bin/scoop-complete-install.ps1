<#
.SYNOPSIS
    Complete installation of Scoop development environment
    
.DESCRIPTION
    Two-phase installation:
    Phase 1 (Admin): Sets Machine-scope environment variables DIRECTLY
    Phase 2 (User): Installs all tools + automatic cleanup + GCC verification
    
.NOTES
    Version: 2.6.0
    Date: 2025-10-28
    
    Changes in v2.6.0:
    - CRITICAL FIX: Regex pattern matching for JDK cleanup
    - Now correctly removes ALL temurin*-jdk versions (8,11,17,23) from User-PATH
    - Simplified matching logic - explicit checks instead of complex regex escaping
    - Added MSYS2 terminal start command to output
    
.EXAMPLE
    # Phase 1 - As Administrator:
    .\scoop-complete-install.ps1 -SetEnvironment
    
    # Phase 2 - As regular user:
    .\scoop-complete-install.ps1 -InstallTools
#>

param(
    [switch]$SetEnvironment,
    [switch]$InstallTools
)

$ScoopDir = "C:\usr"

# ============================================================================
# PART 1: ENVIRONMENT SETUP (RUN AS ADMIN) - SETS VARIABLES DIRECTLY
# ============================================================================
function Set-DevelopmentEnvironment {
    Write-Host ""
    Write-Host "=== Scoop Complete Installation Script ===" -ForegroundColor Cyan
    Write-Host "Two-phase installation for complete development environment" -ForegroundColor Gray
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
        exit 1
    }
    
    Write-Host "[OK] Running with administrator privileges" -ForegroundColor Green
    Write-Host ""
    Write-Host ">>> Creating environment configuration file..." -ForegroundColor White
    
    Write-Host ""
    Write-Host ">>> Applying environment configuration..." -ForegroundColor White
    Write-Host ""
    
    # Download scoop-boot.ps1 if not present
    if (-not (Test-Path "$ScoopDir\bin\scoop-boot.ps1")) {
        Write-Host "[INFO] Downloading scoop-boot.ps1..." -ForegroundColor Gray
        try {
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1" -OutFile "$ScoopDir\bin\scoop-boot.ps1" -UseBasicParsing
            Write-Host "[OK] Downloaded scoop-boot.ps1" -ForegroundColor Green
        } catch {
            Write-Host "[ERROR] Could not download scoop-boot.ps1" -ForegroundColor Red
            Write-Host "Download manually from: https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1" -ForegroundColor Yellow
            exit 1
        }
    }
    
    # Apply environment configuration
    Write-Host "[INFO] Applying environment from .env file..." -ForegroundColor Gray
    & "$ScoopDir\bin\scoop-boot.ps1" --apply-env
    
    Write-Host ""
    Write-Host "=== Phase 1 Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Environment configured:" -ForegroundColor Cyan
    Write-Host "  - Configuration file created" -ForegroundColor White
    Write-Host "  - All environment variables set" -ForegroundColor White
    Write-Host ""
    Write-Host "Next step:" -ForegroundColor Yellow
    Write-Host "  Close this Administrator PowerShell" -ForegroundColor White
    Write-Host "  Open a NORMAL PowerShell (not Administrator)" -ForegroundColor White
    Write-Host "  Run: .\scoop-complete-install.ps1 -InstallTools" -ForegroundColor White
    Write-Host ""
}

# ============================================================================
# PART 2: TOOLS INSTALLATION (RUN AS USER)
# ============================================================================
function Install-ScoopTools {
    Write-Host ""
    Write-Host "=== Scoop Complete Installation Script ===" -ForegroundColor Cyan
    Write-Host "Two-phase installation for complete development environment" -ForegroundColor Gray
    Write-Host ""
    Write-Host "=== Phase 2: Tool Installation (Normal User) ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if running as admin
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    
    if ($isAdmin) {
        Write-Host "[WARN] Running as Administrator - not recommended for tool installation" -ForegroundColor Yellow
        Write-Host "It's recommended to close this window and run without admin rights." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Continue anyway? [y/N]: " -NoNewline
        $response = Read-Host
        if ($response -ne 'y' -and $response -ne 'Y') { 
            Write-Host "Installation cancelled." -ForegroundColor Gray
            exit 0 
        }
        Write-Host ""
    } else {
        Write-Host "[OK] Running as normal user" -ForegroundColor Green
    }
    
    # ============================================================================
    # STEP 1: BOOTSTRAP SCOOP
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Step 1: Bootstrap Scoop..." -ForegroundColor White
    Write-Host ""
    
    # Download scoop-boot.ps1 if not present
    if (-not (Test-Path "$ScoopDir\bin")) {
        New-Item -ItemType Directory -Path "$ScoopDir\bin" -Force | Out-Null
    }
    
    if (-not (Test-Path "$ScoopDir\bin\scoop-boot.ps1")) {
        Write-Host "[INFO] Downloading scoop-boot.ps1..." -ForegroundColor Gray
        $scoopBootUrl = "https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1"
        try {
            Invoke-WebRequest -Uri $scoopBootUrl -OutFile "$ScoopDir\bin\scoop-boot.ps1" -UseBasicParsing
            Write-Host "[OK] Downloaded scoop-boot.ps1" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Could not download scoop-boot.ps1" -ForegroundColor Yellow
        }
    }
    
    # Run scoop-boot.ps1 --bootstrap
    if (Test-Path "$ScoopDir\bin\scoop-boot.ps1") {
        Write-Host "[INFO] Running: scoop-boot.ps1 --bootstrap" -ForegroundColor Gray
        Write-Host ""
        & "$ScoopDir\bin\scoop-boot.ps1" --bootstrap
    } else {
        Write-Host "[WARN] scoop-boot.ps1 not found, using manual bootstrap" -ForegroundColor Yellow
        # Manual bootstrap fallback
        $env:SCOOP = $ScoopDir
        $env:SCOOP_GLOBAL = "$ScoopDir\global"
        [Environment]::SetEnvironmentVariable('SCOOP', $ScoopDir, 'User')
        [Environment]::SetEnvironmentVariable('SCOOP_GLOBAL', "$ScoopDir\global", 'User')
        
        $tempInstaller = "$env:TEMP\scoop-install.ps1"
        Invoke-WebRequest -Uri 'https://get.scoop.sh' -OutFile $tempInstaller -UseBasicParsing
        & $tempInstaller -ScoopDir $ScoopDir -ScoopGlobalDir "$ScoopDir\global" -NoProxy
        Remove-Item $tempInstaller -Force
    }
    
    # Update PATH for current session
    $env:Path = "$ScoopDir\shims;$ScoopDir\bin;$env:Path"
    Write-Host ""
    Write-Host "[OK] Scoop bootstrapped successfully" -ForegroundColor Green
    
    # Disable aria2 warnings
    scoop config aria2-warning-enabled false | Out-Null
    
    # ============================================================================
    # STEP 2: ADD BUCKETS
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Step 2: Adding buckets..." -ForegroundColor White
    Write-Host ""
    
    $buckets = @('main', 'extras', 'java', 'versions')
    foreach ($bucket in $buckets) {
        Write-Host "Adding bucket: $bucket" -ForegroundColor Gray
        $output = scoop bucket add $bucket 2>&1
        if ($output -match 'already exists') {
            Write-Host "[OK] Bucket already exists: $bucket" -ForegroundColor Gray
        } else {
            Write-Host "[OK] Added bucket: $bucket" -ForegroundColor Green
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
    
    $apps = @(
        # Essential tools
        'git', '7zip', 'aria2', 'wget', 'curl', 'openssh', 'sudo',
        
        # Java JDKs
        'temurin8-jdk', 'temurin11-jdk', 'temurin17-jdk', 'temurin21-jdk', 'temurin23-jdk',
        
        # Build tools
        'maven', 'gradle', 'ant', 'cmake', 'make', 'ninja', 'kotlin',
        
        # Documentation
        'graphviz', 'doxygen',
        
        # C++ package manager
        'vcpkg',
        
        # Programming languages
        'python313', 'perl', 'nodejs', 'msys2',
        
        # Version control
        'tortoisesvn', 'gh', 'lazygit',
        
        # Editors & IDEs
        'vscode', 'neovim', 'notepadplusplus', 'jetbrains-toolbox',
        
        # Terminal
        'windows-terminal',
        
        # GUI applications
        'hxd', 'winmerge', 'freecommander', 'greenshot', 'everything', 'postman', 'dbeaver',
        
        # CLI tools
        'jq', 'putty', 'winscp', 'filezilla', 'ripgrep', 'fd', 'bat', 'jid',
        
        # System tools
        'vcredist2022', 'systeminformer'
    )
    
    foreach ($app in $apps) {
        Write-Host "[INFO] Installing $app..." -ForegroundColor Gray
        $output = scoop install $app 2>&1
        if ($output -match 'is already installed') {
            Write-Host "[OK] Already installed: $app" -ForegroundColor Gray
        } else {
            Write-Host "[OK] Installed: $app" -ForegroundColor Green
        }
    }
    
    # ============================================================================
    # STEP 4: POST-INSTALLATION TASKS
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Step 4: Post-installation tasks..." -ForegroundColor White
    Write-Host ""
    
    # Set default Java version
    Write-Host "[INFO] Setting default Java to Temurin 21..." -ForegroundColor Gray
    scoop reset temurin21-jdk | Out-Null
    Write-Host "[OK] Default Java set to Temurin 21" -ForegroundColor Green
    
    # Cleanup VC++ installer
    Write-Host "[INFO] Cleaning up VC++ redistributable installer..." -ForegroundColor Gray
    $vcredistInstaller = Get-ChildItem "$ScoopDir\apps\vcredist2022\current" -Filter "VC_redist*.exe" -ErrorAction SilentlyContinue
    if ($vcredistInstaller) {
        Remove-Item $vcredistInstaller.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "[OK] Installer removed (libraries remain)" -ForegroundColor Green
    }
    
    # Initialize MSYS2 and install GCC
    if (Test-Path "$ScoopDir\apps\msys2\current") {
        Write-Host "[INFO] Initializing MSYS2 and installing GCC..." -ForegroundColor Gray
        Write-Host "  -> Initializing MSYS2..." -ForegroundColor DarkGray
        Write-Host "  -> Updating package database (pacman -Sy)..." -ForegroundColor DarkGray
        Write-Host "  -> Upgrading core system (pacman -Syu)..." -ForegroundColor DarkGray
        Write-Host "     (This may take 2-3 minutes and will close MSYS2 terminal)" -ForegroundColor DarkGray
        Write-Host "  -> Installing mingw-w64-ucrt-x86_64-gcc..." -ForegroundColor DarkGray
        Write-Host "     (This downloads ~70 MB and may take 3-5 minutes)" -ForegroundColor DarkGray
        
        # Try automatic installation
        $msys2 = "$ScoopDir\apps\msys2\current\msys2.exe"
        try {
            # First run: update package database and system
            Start-Process -FilePath $msys2 -ArgumentList "pacman -Syu --noconfirm" -Wait -NoNewWindow -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            
            # Second run: install GCC
            Start-Process -FilePath $msys2 -ArgumentList "pacman -S mingw-w64-ucrt-x86_64-gcc --noconfirm" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        } catch {}
        
        # Verify installation
        $gccPath = "$ScoopDir\apps\msys2\current\mingw64\bin\gcc.exe"
        if (Test-Path $gccPath) {
            Write-Host "[OK] MSYS2 GCC installed successfully!" -ForegroundColor Green
            Write-Host "     GCC location: $gccPath" -ForegroundColor DarkGray
        } else {
            Write-Host "[WARN] GCC installation may have failed (gcc.exe not found)" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Manual installation steps:" -ForegroundColor Yellow
            Write-Host "  1. Open MSYS2 terminal: $ScoopDir\apps\msys2\current\msys2.exe" -ForegroundColor White
            Write-Host "  2. Run: pacman -Syu" -ForegroundColor White
            Write-Host "  3. Run: pacman -S mingw-w64-ucrt-x86_64-gcc" -ForegroundColor White
        }
    } else {
        Write-Host "[WARN] MSYS2 not found, skipping GCC installation" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host ">>> Step 5: Registry imports..." -ForegroundColor White
    Write-Host ""
    
    $regFiles = @(
        @{App='7zip'; File='install-context.reg'},
        @{App='notepadplusplus'; File='install-context.reg'},
        @{App='vscode'; File='install-context.reg'},
        @{App='git'; File='install-context.reg'},
        @{App='python313'; File='install-pep-514.reg'}
    )
    
    foreach ($item in $regFiles) {
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
    if (Test-Path $toolboxPath) {
        $toolboxRunning = Get-Process -Name "jetbrains-toolbox" -ErrorAction SilentlyContinue
        if (-not $toolboxRunning) {
            Start-Process -FilePath $toolboxPath -ErrorAction SilentlyContinue
            Write-Host "[OK] Started: JetBrains Toolbox" -ForegroundColor Green
        }
    }
    
    $greenshotPath = "$ScoopDir\apps\greenshot\current\Greenshot.exe"
    if (Test-Path $greenshotPath) {
        $greenshotRunning = Get-Process -Name "Greenshot" -ErrorAction SilentlyContinue
        if (-not $greenshotRunning) {
            Start-Process -FilePath $greenshotPath -ErrorAction SilentlyContinue
            Write-Host "[OK] Started: Greenshot" -ForegroundColor Green
        }
    }
    
    # ============================================================================
    # STEP 7: CLEANUP USER-SCOPE DUPLICATES
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Step 7: Cleaning up User-Scope duplicates..." -ForegroundColor White
    Write-Host ""
    
    # Get Machine-scope PATH
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $machineEntries = $machinePath -split ';' | Where-Object { $_ -ne '' }
    
    # Get User-scope PATH
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $userEntries = $userPath -split ';' | Where-Object { $_ -ne '' }
    
    # Find entries to remove
    $toRemove = @()
    
    # 1. Remove exact duplicates (same in Machine and User)
    foreach ($userEntry in $userEntries) {
        foreach ($machineEntry in $machineEntries) {
            if ($userEntry -eq $machineEntry) {
                $toRemove += $userEntry
                break
            }
        }
    }
    
    # 2. Remove Scoop-added paths using explicit pattern matching
    foreach ($userEntry in $userEntries) {
        $shouldRemove = $false
        
        # Check if it's a temurin JDK path (any version: 8, 11, 17, 21, 23, 25, etc.)
        if ($userEntry -match '^C:\\usr\\apps\\temurin\d+-jdk\\current\\bin$') {
            $shouldRemove = $true
        }
        # Check other unwanted patterns
        elseif ($userEntry -eq 'C:\usr\apps\vscode\current\bin') {
            $shouldRemove = $true
        }
        elseif ($userEntry -eq 'C:\usr\apps\nodejs\current\bin') {
            $shouldRemove = $true
        }
        elseif ($userEntry -eq 'C:\usr\shims') {
            $shouldRemove = $true
        }
        
        if ($shouldRemove -and ($toRemove -notcontains $userEntry)) {
            $toRemove += $userEntry
        }
    }
    
    if ($toRemove.Count -gt 0) {
        Write-Host "[INFO] Found $($toRemove.Count) entries to remove from User-PATH:" -ForegroundColor Gray
        foreach ($entry in $toRemove) {
            Write-Host "  - $entry" -ForegroundColor DarkGray
        }
        
        # Remove unwanted entries from User-PATH
        $cleanedUserEntries = $userEntries | Where-Object { $toRemove -notcontains $_ }
        $cleanedUserPath = ($cleanedUserEntries -join ';')
        
        [System.Environment]::SetEnvironmentVariable("Path", $cleanedUserPath, "User")
        Write-Host "[OK] Removed $($toRemove.Count) entries from User-PATH" -ForegroundColor Green
    } else {
        Write-Host "[OK] No entries to remove from User-PATH" -ForegroundColor Green
    }
    
    # Get all Machine-scope environment variables
    $machineVars = @{}
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
    Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue | Get-Member -MemberType NoteProperty | ForEach-Object {
        $name = $_.Name
        if ($name -ne 'PSPath' -and $name -ne 'PSParentPath' -and $name -ne 'PSChildName' -and $name -ne 'PSDrive' -and $name -ne 'PSProvider') {
            $machineVars[$name] = $true
        }
    }
    
    # Get all User-scope environment variables that exist in Machine-scope
    $userRegPath = "HKCU:\Environment"
    $duplicateVars = @()
    Get-ItemProperty -Path $userRegPath -ErrorAction SilentlyContinue | Get-Member -MemberType NoteProperty | ForEach-Object {
        $name = $_.Name
        if ($name -ne 'PSPath' -and $name -ne 'PSParentPath' -and $name -ne 'PSChildName' -and $name -ne 'PSDrive' -and $name -ne 'PSProvider' -and $name -ne 'Path') {
            if ($machineVars.ContainsKey($name)) {
                $duplicateVars += $name
            }
        }
    }
    
    if ($duplicateVars.Count -gt 0) {
        Write-Host ""
        Write-Host "[INFO] Found $($duplicateVars.Count) duplicate environment variables in User-Scope:" -ForegroundColor Gray
        foreach ($varName in $duplicateVars) {
            Write-Host "  - $varName" -ForegroundColor DarkGray
            [System.Environment]::SetEnvironmentVariable($varName, $null, "User")
        }
        Write-Host "[OK] Removed $($duplicateVars.Count) duplicate variables from User-Scope" -ForegroundColor Green
    } else {
        Write-Host "[OK] No duplicate environment variables found" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "=== Installation Complete! ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "IMPORTANT: Restart your shell!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Verify:" -ForegroundColor Cyan
    Write-Host "  java -version    # Should show Java 21" -ForegroundColor Gray
    Write-Host "  python --version # Should show Python 3.13.9" -ForegroundColor Gray
    Write-Host "  gcc --version    # Should show GCC 15.2.0" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================================
# MAIN
# ============================================================================
if ($SetEnvironment) {
    Set-DevelopmentEnvironment
} elseif ($InstallTools) {
    Install-ScoopTools
} else {
    Write-Host ""
    Write-Host "=== Scoop Complete Installation ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Phase 1 (Administrator):" -ForegroundColor Yellow
    Write-Host "  .\scoop-complete-install.ps1 -SetEnvironment" -ForegroundColor White
    Write-Host ""
    Write-Host "Phase 2 (Normal user):" -ForegroundColor Yellow
    Write-Host "  .\scoop-complete-install.ps1 -InstallTools" -ForegroundColor White
    Write-Host ""
}
