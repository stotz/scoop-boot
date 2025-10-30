<#
.SYNOPSIS
    Complete installation of Scoop development environment
    
.DESCRIPTION
    Two-phase installation:
    Phase 1 (Admin): Sets Machine-scope environment variables DIRECTLY
    Phase 2 (User): Installs all tools + automatic cleanup + GCC verification
    
.NOTES
    Version: 2.7.5
    Date: 2025-01-29
    
    Changes in v2.7.5:
    - CRITICAL FIX: Validates .env filenames (must start with "system." or "user.")
    - Detects invalid filenames like "template-default.env"
    - Provides rename command for common mistakes
    - Shows valid naming patterns with examples
    
    Changes in v2.7.4:
    - IMPROVED: User-friendly error messages when .env files missing
    - Shows step-by-step instructions to create environment files
    - Better validation before calling scoop-boot.ps1
    - Lists found .env files before applying
    
    Changes in v2.7.3:
    - REMOVED: Rancher Desktop (unreliable Scoop installation)
    - KEPT: WSL2 detection (for Docker/Linux development)
    - WSL2 now optional - installation continues without it
    - Added manual Docker installation instructions in comments
    
    Changes in v2.7.2:
    - CRITICAL FIX: Robust WSL2 detection using multiple methods
    - Fixes false negative when WSL2 is installed but script fails detection
    - Better parsing of "wsl --status" output
    
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
# HELPER: Robust WSL2 Detection
# ============================================================================
function Test-WSL2Installed {
    Write-Host "[INFO] Checking WSL2 installation..." -ForegroundColor Gray
    
    # Method 1: Check wsl.exe existence
    $wslPath = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wslPath) {
        Write-Host "  [FAIL] wsl.exe not found" -ForegroundColor Red
        return $false
    }
    
    # Method 2: Parse "wsl --status" output
    try {
        $wslStatus = wsl --status 2>&1 | Out-String
        
        # Check for "Default Version: 2"
        if ($wslStatus -match 'Default Version:\s*2') {
            Write-Host "  [OK] WSL2 detected: Default Version = 2" -ForegroundColor Green
            return $true
        }
        
        # Check for "WSL version: 2.x.x"
        if ($wslStatus -match 'WSL version:\s*2\.\d+\.\d+') {
            Write-Host "  [OK] WSL2 detected: $($Matches[0])" -ForegroundColor Green
            return $true
        }
        
        # Check if any distribution is running WSL2
        $wslList = wsl --list --verbose 2>&1 | Out-String
        if ($wslList -match '\s+2\s+') {
            Write-Host "  [OK] WSL2 detected: At least one distribution running version 2" -ForegroundColor Green
            return $true
        }
        
    } catch {
        Write-Host "  [WARN] Could not parse wsl status: $_" -ForegroundColor Yellow
    }
    
    # Method 3: Check WSL2 kernel file existence
    $wslKernelPath = "$env:SystemRoot\System32\lxss\tools\kernel"
    if (Test-Path $wslKernelPath) {
        Write-Host "  [OK] WSL2 detected: Kernel found at $wslKernelPath" -ForegroundColor Green
        return $true
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
        Write-Host "Step 1: Create environment configuration" -ForegroundColor Cyan
        Write-Host "  Run as Administrator:" -ForegroundColor White
        Write-Host "    .\bin\scoop-boot.ps1 --init-env=system.default.env" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Or for host-specific:" -ForegroundColor White
        Write-Host "    .\bin\scoop-boot.ps1 --init-env=system.$(Get-Hostname).$(Get-Username).env" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Step 2: Edit the created file" -ForegroundColor Cyan
        Write-Host "  notepad `"$envDir\system.default.env`"" -ForegroundColor Gray
        Write-Host "  - Uncomment lines you need" -ForegroundColor White
        Write-Host "  - Adjust paths to match your installation" -ForegroundColor White
        Write-Host ""
        Write-Host "Step 3: Test configuration" -ForegroundColor Cyan
        Write-Host "  .\bin\scoop-boot.ps1 --apply-env --dry-run" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Step 4: Apply configuration (as Administrator)" -ForegroundColor Cyan
        Write-Host "  .\bin\scoop-boot.ps1 --apply-env" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Then re-run this installation:" -ForegroundColor Yellow
        Write-Host "  .\scoop-complete-install.ps1 -SetEnvironment" -ForegroundColor White
        Write-Host ""
        exit 1
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
        Write-Host "Option 1: Create new file with correct name" -ForegroundColor Yellow
        Write-Host "  .\bin\scoop-boot.ps1 --init-env=system.default.env" -ForegroundColor Gray
        Write-Host ""
        Write-Host "Option 2: Rename existing file" -ForegroundColor Yellow
        if ($allEnvFiles[0].Name -eq "template-default.env") {
            Write-Host "  Rename '$($allEnvFiles[0].Name)' to 'system.default.env'" -ForegroundColor Gray
            Write-Host "  Command:" -ForegroundColor White
            Write-Host "    Rename-Item `"$envDir\$($allEnvFiles[0].Name)`" -NewName 'system.default.env'" -ForegroundColor Gray
        } else {
            Write-Host "  Rename your .env file to start with 'system.' or 'user.'" -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "Example:" -ForegroundColor Cyan
        Write-Host "  # Wrong:" -ForegroundColor Red
        Write-Host "  template-default.env" -ForegroundColor Red
        Write-Host "  myconfig.env" -ForegroundColor Red
        Write-Host ""
        Write-Host "  # Correct:" -ForegroundColor Green
        Write-Host "  system.default.env" -ForegroundColor Green
        Write-Host "  user.bootes.john.env" -ForegroundColor Green
        Write-Host ""
        Write-Host "After fixing, re-run:" -ForegroundColor Yellow
        Write-Host "  .\scoop-complete-install.ps1 -SetEnvironment" -ForegroundColor White
        Write-Host ""
        exit 1
    }
    
    Write-Host "[INFO] Found $($validEnvFiles.Count) valid environment file(s):" -ForegroundColor Gray
    foreach ($file in $validEnvFiles) {
        Write-Host "  - $($file.Name)" -ForegroundColor DarkGray
    }
    Write-Host ""
    
    # Apply environment configuration
    Write-Host "[INFO] Applying environment from .env file(s)..." -ForegroundColor Gray
    & "$ScoopDir\bin\scoop-boot.ps1" --apply-env
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "[ERROR] Failed to apply environment configuration" -ForegroundColor Red
        Write-Host ""
        Write-Host "Troubleshooting:" -ForegroundColor Yellow
        Write-Host "  1. Check file syntax: notepad `"$envDir\system.default.env`"" -ForegroundColor White
        Write-Host "  2. Test with dry-run: .\bin\scoop-boot.ps1 --apply-env --dry-run" -ForegroundColor White
        Write-Host "  3. Check status: .\bin\scoop-boot.ps1 --env-status" -ForegroundColor White
        Write-Host ""
        exit 1
    }
    
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
    # WSL2 CHECK (optional - for Docker alternatives and Linux development)
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Checking WSL2 (optional for Docker/Linux development)..." -ForegroundColor White
    Write-Host ""
    
    $wsl2Installed = Test-WSL2Installed
    
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
            Write-Host "[ERROR] Could not download scoop-boot.ps1" -ForegroundColor Red
            Write-Host "Download manually and run bootstrap first!" -ForegroundColor Yellow
            exit 1
        }
    }
    
    # Run scoop-boot.ps1 --bootstrap (installs Scoop + 7zip + Git + aria2 + recommended tools + buckets)
    $bootstrapSuccess = $false
    
    if (Test-Path "$ScoopDir\bin\scoop-boot.ps1") {
        Write-Host "[INFO] Trying: scoop-boot.ps1 --bootstrap" -ForegroundColor Gray
        Write-Host ""
        
        try {
            & "$ScoopDir\bin\scoop-boot.ps1" --bootstrap 2>&1 | Out-Null
            Write-Host ""
            
            # Verify bootstrap success
            if ((Test-Path "$ScoopDir\apps\scoop") -and (Test-Path "$ScoopDir\apps\git")) {
                Write-Host "[OK] Bootstrap via scoop-boot.ps1 successful!" -ForegroundColor Green
                $bootstrapSuccess = $true
            }
        } catch {
            Write-Host "[WARN] scoop-boot.ps1 bootstrap failed, using fallback..." -ForegroundColor Yellow
        }
    }
    
    # FALLBACK: Manual bootstrap if scoop-boot.ps1 failed
    if (-not $bootstrapSuccess) {
        Write-Host ""
        Write-Host "[INFO] Using manual bootstrap (scoop-boot.ps1 failed)..." -ForegroundColor Yellow
        Write-Host ""
        
        # Set environment variables
        $env:SCOOP = $ScoopDir
        $env:SCOOP_GLOBAL = "$ScoopDir\global"
        [Environment]::SetEnvironmentVariable('SCOOP', $ScoopDir, 'User')
        [Environment]::SetEnvironmentVariable('SCOOP_GLOBAL', "$ScoopDir\global", 'User')
        
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
            
            Write-Host "[INFO] Installing Scoop core..." -ForegroundColor Gray
            & $tempInstaller -ScoopDir $ScoopDir -ScoopGlobalDir "$ScoopDir\global" -NoProxy
            
            Remove-Item $tempInstaller -Force -ErrorAction SilentlyContinue
            
            if (Test-Path "$ScoopDir\apps\scoop") {
                Write-Host "[OK] Scoop core installed successfully!" -ForegroundColor Green
            } else {
                Write-Host "[ERROR] Scoop installation failed!" -ForegroundColor Red
                exit 1
            }
        } catch {
            Write-Host "[ERROR] Failed to download/install Scoop!" -ForegroundColor Red
            Write-Host "Error: $_" -ForegroundColor Red
            exit 1
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
        exit 1
    }
    
    if (-not (Test-Path "$ScoopDir\apps\git")) {
        Write-Host "[ERROR] Git not found after bootstrap!" -ForegroundColor Red
        exit 1
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
    
    # Bootstrap already added main + extras, we add java + versions
    $additionalBuckets = @('java', 'versions')
    foreach ($bucket in $additionalBuckets) {
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
    
    # Essential tools already installed by bootstrap: 7zip, git, aria2, sudo, innounp, dark, lessmsi, wget, cacert
    # We install everything else
    
    $apps = @(
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
        'jq', 'curl', 'openssh', 'putty', 'winscp', 'filezilla', 'ripgrep', 'fd', 'bat', 'jid',
        
        # System tools
        'vcredist2022', 'systeminformer'
        
        # NOTE: Docker alternatives (Rancher Desktop, Docker Desktop) are not included
        # Install manually if needed:
        #   - Docker Desktop: https://www.docker.com/products/docker-desktop
        #   - Rancher Desktop: https://rancherdesktop.io
        #   - Podman Desktop: scoop install podman-desktop
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
    scoop reset temurin21-jdk 2>&1 | Out-Null
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
        
        # Verify installation (CRITICAL: Check ucrt64, NOT mingw64!)
        $gccPath = "$ScoopDir\apps\msys2\current\ucrt64\bin\gcc.exe"
        if (Test-Path $gccPath) {
            Write-Host "[OK] MSYS2 GCC 15.2.0 installed successfully!" -ForegroundColor Green
            Write-Host "     GCC location: $gccPath" -ForegroundColor DarkGray
        } else {
            Write-Host "[WARN] GCC installation may have failed (gcc.exe not found in ucrt64)" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "Manual installation steps:" -ForegroundColor Yellow
            Write-Host "  1. Open UCRT64 terminal: $ScoopDir\apps\msys2\current\ucrt64.exe" -ForegroundColor White
            Write-Host "  2. Run: pacman -Syu" -ForegroundColor White
            Write-Host "  3. Run: pacman -S mingw-w64-ucrt-x86_64-gcc" -ForegroundColor White
            Write-Host ""
            Write-Host "NOTE: Use ucrt64.exe (modern), NOT msys2.exe (legacy)" -ForegroundColor Yellow
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
    
    if ($wsl2Installed) {
        Write-Host "WSL2 is ready for:" -ForegroundColor Cyan
        Write-Host "  - Docker Desktop (download: https://www.docker.com/products/docker-desktop)" -ForegroundColor Gray
        Write-Host "  - Rancher Desktop (download: https://rancherdesktop.io)" -ForegroundColor Gray
        Write-Host "  - Linux development (wsl)" -ForegroundColor Gray
        Write-Host ""
    }
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
