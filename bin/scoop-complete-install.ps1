<#
.SYNOPSIS
    Complete installation of Scoop development environment

.DESCRIPTION
    Two-phase installation:
    Phase 1 (Admin): Sets Machine-scope environment variables DIRECTLY + Creates TEMP/TMP directories
    Phase 2 (User): Installs all tools + automatic cleanup + GCC verification

.NOTES
    Version: 2.7.2
    Date: 2025-10-29

    Changes in v2.7.2:
    - NEW: Automatic TEMP/TMP directory creation from .env files
    - NEW: Validates and creates custom TEMP/TMP paths before applying
    - IMPROVED: Better error handling for directory creation
    - IMPROVED: Clearer status messages during environment setup

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
# PART 1: ENVIRONMENT SETUP (RUN AS ADMIN)
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

    # ============================================================================
    # STEP 1: CHECK AND CREATE TEMP/TMP DIRECTORIES FROM .ENV FILES
    # ============================================================================
    Write-Host ">>> Step 1: Checking TEMP/TMP configuration..." -ForegroundColor White
    Write-Host ""

    $envDir = "$ScoopDir\etc\environments"
    if (Test-Path $envDir) {
        # Get all .env files
        $envFiles = Get-ChildItem -Path $envDir -Filter "*.env" -File

        if ($envFiles.Count -gt 0) {
            Write-Host "[INFO] Found $($envFiles.Count) environment file(s)" -ForegroundColor Gray
            Write-Host ""

            # Track TEMP/TMP directories to create
            $tempDirs = @{}

            foreach ($envFile in $envFiles) {
                Write-Host "  Scanning: $($envFile.Name)" -ForegroundColor DarkGray

                # Read file and look for TEMP/TMP assignments
                $content = Get-Content $envFile.FullName
                foreach ($line in $content) {
                    # Skip comments and empty lines
                    if ([string]::IsNullOrWhiteSpace($line) -or $line.Trim().StartsWith('#')) {
                        continue
                    }

                    # Check for TEMP= or TMP=
                    if ($line -match '^(TEMP|TMP)\s*=\s*(.+)$') {
                        $varName = $Matches[1]
                        $varValue = $Matches[2].Trim()

                        # Expand environment variables in path
                        $expandedPath = [System.Environment]::ExpandEnvironmentVariables($varValue)

                        # Store for later creation
                        if (-not $tempDirs.ContainsKey($expandedPath)) {
                            $tempDirs[$expandedPath] = @()
                        }
                        $tempDirs[$expandedPath] += @{File = $envFile.Name; Var = $varName}

                        Write-Host "    Found: $varName=$expandedPath" -ForegroundColor Cyan
                    }
                }
            }

            # Create directories
            if ($tempDirs.Count -gt 0) {
                Write-Host ""
                Write-Host "[INFO] Creating TEMP/TMP directories..." -ForegroundColor Yellow
                Write-Host ""

                foreach ($dirPath in $tempDirs.Keys) {
                    Write-Host "  Creating: $dirPath" -ForegroundColor Gray

                    try {
                        if (-not (Test-Path $dirPath)) {
                            New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
                            Write-Host "    [OK] Created directory" -ForegroundColor Green
                        } else {
                            Write-Host "    [OK] Directory already exists" -ForegroundColor Green
                        }

                        # Show which env files reference this directory
                        $refs = $tempDirs[$dirPath]
                        foreach ($ref in $refs) {
                            Write-Host "      Referenced by: $($ref.File) ($($ref.Var))" -ForegroundColor DarkGray
                        }
                    } catch {
                        Write-Host "    [ERROR] Failed to create directory: $_" -ForegroundColor Red
                        Write-Host "    Please create manually: New-Item -ItemType Directory -Path '$dirPath' -Force" -ForegroundColor Yellow
                    }
                }

                Write-Host ""
                Write-Host "[OK] TEMP/TMP directories prepared" -ForegroundColor Green
            } else {
                Write-Host "[INFO] No custom TEMP/TMP paths found in .env files" -ForegroundColor Gray
                Write-Host "      (Using system defaults)" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "[WARN] No .env files found in $envDir" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[INFO] Environment directory not found: $envDir" -ForegroundColor Gray
        Write-Host "      Will be created during bootstrap" -ForegroundColor DarkGray
    }

    Write-Host ""

    # ============================================================================
    # STEP 2: APPLY ENVIRONMENT CONFIGURATION
    # ============================================================================
    Write-Host ">>> Step 2: Applying environment configuration..." -ForegroundColor White
    Write-Host ""

    # Download scoop-boot.ps1 if not present
    if (-not (Test-Path "$ScoopDir\bin\scoop-boot.ps1")) {
        Write-Host "[INFO] Downloading scoop-boot.ps1..." -ForegroundColor Gray
        try {
            if (-not (Test-Path "$ScoopDir\bin")) {
                New-Item -ItemType Directory -Path "$ScoopDir\bin" -Force | Out-Null
            }
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1" -OutFile "$ScoopDir\bin\scoop-boot.ps1" -UseBasicParsing
            Write-Host "[OK] Downloaded scoop-boot.ps1" -ForegroundColor Green
        } catch {
            Write-Host "[ERROR] Could not download scoop-boot.ps1" -ForegroundColor Red
            Write-Host "Download manually from: https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1" -ForegroundColor Yellow
            exit 1
        }
    }

    # Apply environment configuration
    Write-Host "[INFO] Applying environment from .env files..." -ForegroundColor Gray
    & "$ScoopDir\bin\scoop-boot.ps1" --apply-env

    Write-Host ""
    Write-Host "=== Phase 1 Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Environment configured:" -ForegroundColor Cyan
    Write-Host "  - TEMP/TMP directories created (if specified)" -ForegroundColor White
    Write-Host "  - Configuration files processed" -ForegroundColor White
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
            Write-Host "[ERROR] Could not download scoop-boot.ps1" -ForegroundColor Red
            Write-Host "Download manually and run bootstrap first!" -ForegroundColor Yellow
            exit 1
        }
    }

    # Run scoop-boot.ps1 --bootstrap
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

        # Get TEMP from environment (might be custom from Phase 1)
        $userTemp = [System.Environment]::GetEnvironmentVariable("TEMP", "Machine")
        if ([string]::IsNullOrEmpty($userTemp)) {
            $userTemp = [System.Environment]::GetEnvironmentVariable("TEMP", "User")
        }
        if ([string]::IsNullOrEmpty($userTemp)) {
            $userTemp = "$env:USERPROFILE\Temp"
        }

        # Ensure TEMP directory exists
        if (-not (Test-Path $userTemp)) {
            Write-Host "[INFO] Creating TEMP directory: $userTemp" -ForegroundColor Gray
            New-Item -ItemType Directory -Path $userTemp -Force | Out-Null
        }

        $env:TMP = $userTemp
        $env:TEMP = $userTemp

        Write-Host "[INFO] Using TEMP directory: $userTemp" -ForegroundColor Gray

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
    # STEP 2: ADD ADDITIONAL BUCKETS
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Step 2: Adding additional buckets..." -ForegroundColor White
    Write-Host ""

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

        $msys2 = "$ScoopDir\apps\msys2\current\msys2.exe"
        try {
            Start-Process -FilePath $msys2 -ArgumentList "pacman -Syu --noconfirm" -Wait -NoNewWindow -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Start-Process -FilePath $msys2 -ArgumentList "pacman -S mingw-w64-ucrt-x86_64-gcc --noconfirm" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        } catch {}

        $gccPath = "$ScoopDir\apps\msys2\current\mingw64\bin\gcc.exe"
        if (Test-Path $gccPath) {
            Write-Host "[OK] MSYS2 GCC installed successfully!" -ForegroundColor Green
        } else {
            Write-Host "[WARN] GCC installation may have failed" -ForegroundColor Yellow
        }
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

    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $machineEntries = $machinePath -split ';' | Where-Object { $_ -ne '' }

    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $userEntries = $userPath -split ';' | Where-Object { $_ -ne '' }

    $toRemove = @()

    foreach ($userEntry in $userEntries) {
        foreach ($machineEntry in $machineEntries) {
            if ($userEntry -eq $machineEntry) {
                $toRemove += $userEntry
                break
            }
        }
    }

    foreach ($userEntry in $userEntries) {
        $shouldRemove = $false

        if ($userEntry -match '^C:\\usr\\apps\\temurin\d+-jdk\\current\\bin$') {
            $shouldRemove = $true
        }
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

        $cleanedUserEntries = $userEntries | Where-Object { $toRemove -notcontains $_ }
        $cleanedUserPath = ($cleanedUserEntries -join ';')

        [System.Environment]::SetEnvironmentVariable("Path", $cleanedUserPath, "User")
        Write-Host "[OK] Removed $($toRemove.Count) entries from User-PATH" -ForegroundColor Green
    } else {
        Write-Host "[OK] No entries to remove from User-PATH" -ForegroundColor Green
    }

    $machineVars = @{}
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
    Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue | Get-Member -MemberType NoteProperty | ForEach-Object {
        $name = $_.Name
        if ($name -ne 'PSPath' -and $name -ne 'PSParentPath' -and $name -ne 'PSChildName' -and $name -ne 'PSDrive' -and $name -ne 'PSProvider') {
            $machineVars[$name] = $true
        }
    }

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