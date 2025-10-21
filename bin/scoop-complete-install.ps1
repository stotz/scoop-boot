<#
.SYNOPSIS
    Complete Scoop installation and development environment setup
    
.DESCRIPTION
    Two-phase installation script for complete development environment:
    
    Phase 1 (Admin): Set system-wide environment variables
    Phase 2 (User):  Bootstrap Scoop and install all development tools
    
.PARAMETER SetEnvironment
    Run Phase 1: Create environment configuration and apply to Machine scope (requires Admin)
    
.PARAMETER InstallTools
    Run Phase 2: Bootstrap Scoop and install all tools (run as regular user)
    
.EXAMPLE
    # Phase 1 - As Administrator
    PS C:\usr> .\bin\scoop-complete-install.ps1 -SetEnvironment
    
    # Phase 2 - As User
    PS C:\usr> .\bin\scoop-complete-install.ps1 -InstallTools
    
.NOTES
    Based on all configurations from project conversations
    Installs 50+ development tools across multiple categories
#>

param(
    [switch]$SetEnvironment,
    [switch]$InstallTools
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== Scoop Complete Installation Script ===" -ForegroundColor Cyan
Write-Host "Two-phase installation for complete development environment" -ForegroundColor Cyan
Write-Host ""

if (-not $SetEnvironment -and -not $InstallTools) {
    Write-Host "ERROR: You must specify either -SetEnvironment or -InstallTools" -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  Phase 1 (Admin):  .\scoop-complete-install.ps1 -SetEnvironment" -ForegroundColor White
    Write-Host "  Phase 2 (User):   .\scoop-complete-install.ps1 -InstallTools" -ForegroundColor White
    Write-Host ""
    exit 1
}

# ============================================================================
# PHASE 1: ENVIRONMENT SETUP (ADMIN)
# ============================================================================

if ($SetEnvironment) {
    Write-Host "=== Phase 1: Environment Setup (Admin Required) ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Check for admin rights
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "[ERROR] Phase 1 requires Administrator privileges!" -ForegroundColor Red
        Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
        exit 1
    }
    Write-Host "[OK] Running with administrator privileges" -ForegroundColor Green
    
    # Verify scoop-boot.ps1 exists
    $scoopBootPath = "$PSScriptRoot\scoop-boot.ps1"
    if (-not (Test-Path $scoopBootPath)) {
        Write-Host "[ERROR] scoop-boot.ps1 not found at: $scoopBootPath" -ForegroundColor Red
        exit 1
    }
    Write-Host "[OK] Found scoop-boot.ps1" -ForegroundColor Green
    
    # Create environment configuration directory
    $envDir = "C:\usr\etc\environments"
    if (-not (Test-Path $envDir)) {
        New-Item -ItemType Directory -Path $envDir -Force | Out-Null
    }
    
    # Create default environment configuration with cleaned PATH
    $envContent = @"
# Scoop Development Environment Configuration
# System-wide settings (Machine scope)
# Managed by scoop-boot.ps1
#
# IMPORTANT: Tools in C:\usr\shims are automatically available!
# Only add to PATH if needed for support scripts, modules, or DLLs

# === Core Scoop Configuration ===
SCOOP=C:\usr
SCOOP_GLOBAL=C:\usr\global

# === PATH Cleanup (remove old duplicates) ===
PATH-=C:\usr\apps\git\current\cmd
PATH-=C:\usr\apps\cmake\current\bin
PATH-=C:\usr\apps\make\current\bin
PATH-=C:\usr\apps\tortoisesvn\current\bin
PATH-=C:\usr\apps\python313\current
PATH-=C:\usr\apps\python313\current\Scripts
PATH-=C:\usr\apps\perl\current\perl\bin
PATH-=C:\usr\apps\perl\current\perl\site\bin
PATH-=C:\usr\persist\nodejs\bin
PATH-=C:\usr\apps\nodejs\current
PATH-=C:\usr\apps\git\current\usr\bin
PATH-=C:\usr\apps\git\current\mingw64\bin
PATH-=C:\usr\apps\msys2\current\mingw64\bin
PATH-=C:\usr\apps\msys2\current\usr\bin

# === PATH Priority (highest to lowest) ===
# Scoop shims and bins (highest priority)
PATH+=C:\usr\bin
PATH+=C:\usr\shims

# JDK binaries
PATH+=C:\usr\apps\temurin21-jdk\current\bin

# Build tools
PATH+=C:\usr\apps\maven\current\bin
PATH+=C:\usr\apps\gradle\current\bin
PATH+=C:\usr\apps\ant\current\bin
PATH+=C:\usr\apps\kotlin\current\bin

# Python support scripts (3 files: pip, pip3, wheel)
PATH+=C:\usr\apps\python313\current\Scripts

# Perl core tools (178 files)
PATH+=C:\usr\apps\perl\current\perl\bin

# Perl CPAN modules (empty until CPAN modules installed)
# Uncomment when needed: PATH+=C:\usr\apps\perl\current\perl\site\bin

# Node.js global packages (empty until npm -g packages installed)
# Uncomment when needed: PATH+=C:\usr\persist\nodejs\bin

# Git support tools (365 files: bash, ssh, awk, sed, grep)
PATH+=C:\usr\apps\git\current\usr\bin

# Git DLL dependencies (157 files)
PATH+=C:\usr\apps\git\current\mingw64\bin

# MSYS2 Unix tools (503 files - lowest priority fallback)
PATH+=C:\usr\apps\msys2\current\usr\bin

# === Version Control ===
MSYS2_HOME=C:\usr\apps\msys2\current
SVN_HOME=C:\usr\apps\tortoisesvn\current
GIT_HOME=C:\usr\apps\git\current

# === Build Tools ===
MAKE_HOME=C:\usr\apps\make\current
CMAKE_HOME=C:\usr\apps\cmake\current

# === Programming Languages ===
NODE_HOME=C:\usr\apps\nodejs\current
NODE_PATH=C:\usr\apps\nodejs\current\node_modules
NPM_CONFIG_PREFIX=C:\usr\persist\nodejs

PERL_HOME=C:\usr\apps\perl\current
PERL5LIB+=C:\usr\apps\perl\current\perl\lib
PERL5LIB+=C:\usr\apps\perl\current\perl\site\lib

PYTHON_HOME=C:\usr\apps\python313\current
PYTHONPATH=C:\usr\apps\python313\current\Lib\site-packages

KOTLIN_HOME=C:\usr\apps\kotlin\current

# === Java Build Tools ===
ANT_HOME=C:\usr\apps\ant\current

GRADLE_HOME=C:\usr\apps\gradle\current
GRADLE_USER_HOME=C:\Users\$env:USERNAME\.gradle
GRADLE_OPTS=-Xmx2048m -Dorg.gradle.daemon=true -Dorg.gradle.parallel=true

MAVEN_HOME=C:\usr\apps\maven\current
M2_HOME=C:\usr\apps\maven\current
M2_REPO=C:\Users\$env:USERNAME\.m2\repository
MAVEN_OPTS=-Xmx1024m -XX:+TieredCompilation -XX:TieredStopAtLevel=1

# === Java Development Kit ===
JAVA_HOME=C:\usr\apps\temurin21-jdk\current
JAVA_OPTS=-Xmx2g -Xms512m -XX:+UseG1GC -XX:MaxGCPauseMillis=200

# === Locale Settings ===
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
LANGUAGE=en_US:en
"@
    
    $envFile = "$envDir\system.bootes.user.env"
    $envContent | Out-File -FilePath $envFile -Encoding UTF8 -Force
    Write-Host "[OK] Created environment file: $envFile" -ForegroundColor Green
    
    # Apply environment configuration
    Write-Host ""
    Write-Host ">>> Applying environment configuration to Machine scope..." -ForegroundColor Cyan
    Write-Host "[INFO] Running: scoop-boot.ps1 --apply-env (as Administrator)" -ForegroundColor Yellow
    
    & $scoopBootPath --apply-env
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to apply environment configuration" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "[OK] Environment variables set in Machine scope" -ForegroundColor Green
    
    Write-Host ""
    Write-Host "=== Phase 1 Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Environment variables have been set system-wide (Machine scope)." -ForegroundColor Cyan
    Write-Host "All users on this system will have access to these settings." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Close this Administrator PowerShell" -ForegroundColor White
    Write-Host "2. Open a NEW PowerShell/CMD as REGULAR USER" -ForegroundColor White
    Write-Host "3. Run: .\scoop-complete-install.ps1 -InstallTools" -ForegroundColor White
    Write-Host ""
}

# ============================================================================
# PHASE 2: TOOLS INSTALLATION (USER)
# ============================================================================

if ($InstallTools) {
    Write-Host "=== Phase 2: Tools Installation (User) ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Check we're NOT running as admin
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) {
        Write-Host "[WARN] Running as Administrator - this phase should run as regular user!" -ForegroundColor Yellow
        Write-Host "[INFO] Continuing anyway, but installed apps will be in admin context..." -ForegroundColor Yellow
    } else {
        Write-Host "[OK] Running as normal user" -ForegroundColor Green
    }
    
    # Bootstrap Scoop
    Write-Host ""
    Write-Host ">>> Step 1: Bootstrap Scoop..." -ForegroundColor Cyan
    Write-Host ""
    
    $scoopBootPath = "$PSScriptRoot\scoop-boot.ps1"
    if (-not (Test-Path $scoopBootPath)) {
        Write-Host "[ERROR] scoop-boot.ps1 not found at: $scoopBootPath" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "[INFO] Running: scoop-boot.ps1 --bootstrap" -ForegroundColor Yellow
    Write-Host ""
    & $scoopBootPath --bootstrap
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Scoop bootstrap failed" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "[OK] Scoop bootstrapped successfully" -ForegroundColor Green
    
    # Disable aria2 warning
    & scoop config aria2-warning-enabled false | Out-Null
    
    # Add buckets
    Write-Host ""
    Write-Host ">>> Step 2: Adding Scoop buckets..." -ForegroundColor Cyan
    Write-Host ""
    
    $buckets = @('main', 'extras', 'java', 'versions')
    
    foreach ($bucket in $buckets) {
        Write-Host "Adding bucket: $bucket" -ForegroundColor Yellow
        $output = & scoop bucket add $bucket 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Added bucket: $bucket" -ForegroundColor Green
        } else {
            if ($output -like "*already exists*") {
                Write-Host "[INFO] Bucket already exists: $bucket" -ForegroundColor Gray
            } else {
                Write-Host "[WARN] Could not add bucket: $bucket" -ForegroundColor Yellow
            }
        }
    }
    
    # Install tools
    Write-Host ""
    Write-Host ">>> Step 3: Installing development tools..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "This will take 15-30 minutes depending on your internet connection." -ForegroundColor Yellow
    Write-Host ""
    
    # Tool categories
    $categories = @(
        @{ Category = "Essential tools"; Tools = @(
            '7zip',         # Archive manager
            'git',          # Version control
            'aria2',        # Download manager
            'sudo',         # Run as admin
            'innounp',      # Inno Setup unpacker
            'dark',         # WiX decompiler
            'lessmsi',      # MSI viewer/extractor
            'wget',         # File downloader
            'cacert'        # CA certificates
        ) },
        @{ Category = "Java Development Kits"; Tools = @(
            'temurin8-jdk',
            'temurin11-jdk',
            'temurin17-jdk',
            'temurin21-jdk',
            'temurin23-jdk'
        ) },
        @{ Category = "Build Tools"; Tools = @(
            'maven',        # Java build tool
            'gradle',       # Java/Kotlin build tool
            'ant',          # Java build tool (legacy)
            'kotlin',       # Kotlin compiler
            'cmake',        # Cross-platform build system
            'make',         # GNU Make
            'ninja',        # Small build system
            'graphviz',     # Graph visualization
            'doxygen',      # Documentation generator
            'vcpkg'         # C++ package manager
        ) },
        @{ Category = "Programming Languages"; Tools = @(
            'python313',    # Python 3.13
            'perl',         # Strawberry Perl
            'nodejs',       # Node.js
            'msys2'         # Unix tools for Windows
        ) },
        @{ Category = "Version Control"; Tools = @(
            'tortoisesvn',  # SVN client
            'gh',           # GitHub CLI
            'lazygit'       # Terminal UI for git
        ) },
        @{ Category = "Editors & IDEs"; Tools = @(
            'vscode',           # Visual Studio Code
            'neovim',           # Modern Vim
            'notepadplusplus',  # Advanced notepad
            'jetbrains-toolbox' # JetBrains IDEs manager
        ) },
        @{ Category = "GUI Applications"; Tools = @(
            'windows-terminal',  # Modern terminal
            'hxd',              # Hex editor
            'winmerge',         # Diff/merge tool
            'freecommander',    # File manager
            'greenshot',        # Screenshot tool
            'everything',       # Fast file search
            'postman',          # API testing
            'dbeaver'           # Universal database tool
        ) },
        @{ Category = "Command-Line Utilities"; Tools = @(
            'jq',           # JSON processor
            'openssh',      # SSH client/server
            'putty',        # SSH/Telnet client
            'winscp',       # SFTP/SCP client
            'filezilla',    # FTP/SFTP client
            'curl',         # HTTP client
            'ripgrep',      # Fast text search (rg)
            'fd',           # Fast file finder
            'bat',          # Cat with syntax highlighting
            'less',         # Pager for viewing files
            'jid'           # JSON incremental digger
        ) }
    )
    
    foreach ($category in $categories) {
        Write-Host ""
        Write-Host "[Category] $($category.Category)" -ForegroundColor Magenta
        
        foreach ($tool in $category.Tools) {
            # Check if already installed
            if (scoop list $tool -ErrorAction SilentlyContinue) {
                Write-Host "[INFO] Already installed: $tool" -ForegroundColor Gray
                continue
            }
            
            Write-Host "Installing: $tool" -ForegroundColor Yellow
            & scoop install $tool 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Installed: $tool" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Could not install: $tool" -ForegroundColor Yellow
            }
        }
    }
    
    # Set default Java version to 21
    Write-Host ""
    Write-Host "Setting default Java to temurin21-jdk..." -ForegroundColor Yellow
    & scoop reset temurin21-jdk | Out-Null
    
    # Post-installation tasks
    Write-Host ""
    Write-Host ">>> Step 4: Post-installation tasks..." -ForegroundColor Cyan
    Write-Host ""
    
    # Install and uninstall vcredist2022 (installs system runtime libraries)
    Write-Host "[INFO] Installing Visual C++ Runtime Libraries..." -ForegroundColor Cyan
    & scoop install vcredist2022 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0 -or (scoop list vcredist2022 -ErrorAction SilentlyContinue)) {
        Write-Host "[OK] VC++ Runtime installed (system libraries)" -ForegroundColor Green
        & scoop uninstall vcredist2022 2>&1 | Out-Null
        Write-Host "[OK] Installer removed (libraries remain in system)" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Could not install VC++ Runtime" -ForegroundColor Yellow
    }
    
    # Install additional recommended tools
    Write-Host ""
    Write-Host "[INFO] Installing additional utilities..." -ForegroundColor Cyan
    
    $additionalTools = @('less', 'jid')
    foreach ($tool in $additionalTools) {
        if (scoop list $tool -ErrorAction SilentlyContinue) {
            Write-Host "[INFO] Already installed: $tool" -ForegroundColor Gray
        } else {
            Write-Host "Installing: $tool" -ForegroundColor Yellow
            & scoop install $tool 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Installed: $tool" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Could not install: $tool" -ForegroundColor Yellow
            }
        }
    }
    
    # Replace processhacker with systeminformer (processhacker is deprecated)
    Write-Host ""
    Write-Host "[INFO] Installing system informer..." -ForegroundColor Cyan
    & scoop install extras/systeminformer 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Installed: systeminformer" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Could not install systeminformer" -ForegroundColor Yellow
    }
    
    # Initialize MSYS2 (required for first-time setup)
    Write-Host ""
    Write-Host "[INFO] Initializing MSYS2..." -ForegroundColor Cyan
    if (Test-Path "$env:SCOOP\apps\msys2\current\msys2.exe") {
        Write-Host "[INFO] Starting MSYS2 first-time setup in background..." -ForegroundColor Yellow
        Write-Host "[INFO] MSYS2 will initialize automatically on first use" -ForegroundColor Yellow
        # Don't wait for MSYS2 - let it initialize in background or on first user start
        Start-Process -FilePath "$env:SCOOP\apps\msys2\current\msys2.exe" -WindowStyle Hidden
        Start-Sleep -Seconds 2
        Write-Host "[OK] MSYS2 initialization started" -ForegroundColor Green
    } else {
        Write-Host "[WARN] MSYS2 not found, skipping initialization" -ForegroundColor Yellow
    }
    
    # Migrate Windows Terminal settings if they exist
    Write-Host ""
    Write-Host "[INFO] Checking for Windows Terminal settings..." -ForegroundColor Cyan
    $oldTerminalSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
    $newTerminalSettings = "$env:SCOOP\apps\windows-terminal\current\settings"
    
    if (Test-Path $oldTerminalSettings) {
        Write-Host "[INFO] Found existing Windows Terminal settings" -ForegroundColor Yellow
        Write-Host "[INFO] Migrating to portable location..." -ForegroundColor Yellow
        try {
            Copy-Item "$oldTerminalSettings\*" -Destination $newTerminalSettings -Recurse -Force -ErrorAction Stop
            Write-Host "[OK] Settings migrated successfully" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Could not migrate settings: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "[INFO] No existing Windows Terminal settings found" -ForegroundColor Gray
    }
    
    # Import registry files
    Write-Host ""
    Write-Host ">>> Step 5: Importing registry files..." -ForegroundColor Cyan
    Write-Host ""
    
    # Registry files to import (context menu integrations, file associations)
    $registryImports = @(
        @{ App = "7zip"; File = "install-context.reg" },
        @{ App = "notepadplusplus"; File = "install-context.reg" },
        @{ App = "vscode"; File = "install-context.reg" },
        @{ App = "vscode"; File = "install-associations.reg" },
        @{ App = "windows-terminal"; File = "install-context.reg" },
        @{ App = "git"; File = "install-context.reg" },
        @{ App = "tortoisesvn"; File = "tortoisesvn-install.reg" },
        @{ App = "tortoisesvn"; File = "tortoisesvn-install-tools.reg" },
        @{ App = "everything"; File = "install-context.reg" }
    )
    
    foreach ($import in $registryImports) {
        $regFile = "$env:SCOOP\apps\$($import.App)\current\$($import.File)"
        if (Test-Path $regFile) {
            $output = & reg import $regFile 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Imported registry: $($import.App) - $($import.File)" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Could not import: $($import.App) - $($import.File)" -ForegroundColor Yellow
                Write-Host "       Error: $output" -ForegroundColor Gray
            }
        } else {
            Write-Host "[INFO] Registry file not found: $($import.App) - $($import.File)" -ForegroundColor Gray
        }
    }
    
    # Import Python PEP-514 registration
    $pythonReg = "$env:SCOOP\apps\python313\current\install-pep-514.reg"
    if (Test-Path $pythonReg) {
        $output = & reg import $pythonReg 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Imported registry: Python 3.13 PEP-514" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Could not import Python PEP-514 registry" -ForegroundColor Yellow
            Write-Host "       Error: $output" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    Write-Host "=== Phase 2 Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Installed applications:" -ForegroundColor Cyan
    & scoop list
    
    # Show manual configuration instructions
    Write-Host ""
    Write-Host "========================================"
    Write-Host "  MANUAL CONFIGURATION REQUIRED"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "The following applications require manual configuration:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. WinMerge (Diff/Merge Tool)" -ForegroundColor Cyan
    Write-Host "   Start: winmerge" -ForegroundColor White
    Write-Host "   Configure: Edit > Options > Shell Integration" -ForegroundColor Gray
    Write-Host "   Enable: 'Add WinMerge to Windows Explorer context menu'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. HxD (Hex Editor)" -ForegroundColor Cyan
    Write-Host "   Start: hxd" -ForegroundColor White
    Write-Host "   Configure: Tools > Options > Context Menu (optional)" -ForegroundColor Gray
    Write-Host "   Enable: 'Integrate into Explorer context menu'" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Greenshot (Screenshot Tool)" -ForegroundColor Cyan
    Write-Host "   Start: greenshot" -ForegroundColor White
    Write-Host "   Autostart: Right-click tray icon > Preferences > General" -ForegroundColor Gray
    Write-Host "   Enable: 'Launch Greenshot on startup'" -ForegroundColor Gray
    Write-Host "   Hotkeys: PrintScreen = Region, Alt+PrintScreen = Window" -ForegroundColor Gray
    Write-Host ""
    Write-Host "4. FreeCommander (File Manager)" -ForegroundColor Cyan
    Write-Host "   Start: freecommander" -ForegroundColor White
    Write-Host "   Configure: Settings > Integration (optional)" -ForegroundColor Gray
    Write-Host "   Enable: 'Replace Windows Explorer' or add to context menu" -ForegroundColor Gray
    Write-Host ""
    Write-Host "5. Everything (File Search)" -ForegroundColor Cyan
    Write-Host "   Start: everything" -ForegroundColor White
    Write-Host "   Configure: Tools > Options > General" -ForegroundColor Gray
    Write-Host "   Enable: 'Start Everything on system startup'" -ForegroundColor Gray
    Write-Host "   Enable: 'Install Everything service' (requires admin, for NTFS indexing)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "6. System Informer (Task Manager Replacement)" -ForegroundColor Cyan
    Write-Host "   Start: systeminformer" -ForegroundColor White
    Write-Host "   Configure: Hacker > Options > Advanced (optional)" -ForegroundColor Gray
    Write-Host "   Enable: 'Replace Task Manager' (requires admin)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "7. JetBrains Toolbox (IDEs Manager)" -ForegroundColor Cyan
    Write-Host "   Start: jetbrains-toolbox" -ForegroundColor White
    Write-Host "   Install IDEs: IntelliJ IDEA, PyCharm, CLion, etc." -ForegroundColor Gray
    Write-Host "   Apps folder: C:\usr\apps\jetbrains-toolbox\current\apps (persisted)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "IMPORTANT: Restart your shell for all changes to take effect!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Quick verification:" -ForegroundColor Cyan
    Write-Host "  scoop --version" -ForegroundColor White
    Write-Host "  java -version" -ForegroundColor White
    Write-Host "  python --version" -ForegroundColor White
    Write-Host "  node --version" -ForegroundColor White
    Write-Host ""
}