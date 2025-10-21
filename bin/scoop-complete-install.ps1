<#
.SYNOPSIS
    Complete installation of Scoop development environment
    
.DESCRIPTION
    This script installs all tools and configurations.
    Phase 1: Set environment variables as admin (Machine scope)
    Phase 2: Install tools as regular user via scoop-boot.ps1 --bootstrap
    
.NOTES
    Version: 2.0.0
    Author: System Configuration
    Date: 2025-10-21
    
.EXAMPLE
    # Phase 1 - As Administrator PowerShell:
    .\scoop-complete-install.ps1 -SetEnvironment
    
    # Phase 2 - As regular user:
    .\scoop-complete-install.ps1 -InstallTools
#>

param(
    [switch]$SetEnvironment,
    [switch]$InstallTools,
    [switch]$All
)

# ============================================================================
# CONFIGURATION
# ============================================================================
$ScoopDir = "C:\usr"
$Hostname = [System.Net.Dns]::GetHostName().ToLower()
$Username = [Environment]::UserName.ToLower()

# ============================================================================
# PART 1: ENVIRONMENT SETUP (RUN AS ADMIN)
# ============================================================================
function Set-DevelopmentEnvironment {
    Write-Host ""
    Write-Host "=== Phase 1: Environment Setup (Admin Required) ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Check admin rights
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    
    if (-not $isAdmin) {
        Write-Host "[ERROR] This part requires administrator privileges!" -ForegroundColor Red
        Write-Host "Run PowerShell as Administrator and try again." -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "[OK] Running with administrator privileges" -ForegroundColor Green
    
    # Ensure scoop-boot.ps1 exists
    if (-not (Test-Path "$ScoopDir\bin\scoop-boot.ps1")) {
        Write-Host "[ERROR] scoop-boot.ps1 not found at $ScoopDir\bin\scoop-boot.ps1" -ForegroundColor Red
        Write-Host "Please download it first from:" -ForegroundColor Yellow
        Write-Host "https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1" -ForegroundColor White
        exit 1
    }
    
    Write-Host "[OK] Found scoop-boot.ps1" -ForegroundColor Green
    
    # Create environment file content
    $envContent = @"
# ============================================================================
# System Environment Configuration
# File: system.$Hostname.$Username.env
# Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# ============================================================================
# Scope: Machine (system-wide, applied by admin via scoop-boot.ps1 --apply-env)
# SCOOP: $ScoopDir
# Hostname: $Hostname
# Username: $Username
# ============================================================================

# ============================================================================
# SCOOP CORE VARIABLES
# ============================================================================
SCOOP=$ScoopDir
SCOOP_GLOBAL=$ScoopDir\global

# ============================================================================
# CLEANUP - Remove old/duplicate PATH entries
# ============================================================================
PATH-=C:\usr\apps\perl\current\site\bin
PATH-=C:\usr\apps\perl\current\bin
PATH-=C:\usr\apps\python\current\Scripts
PATH-=C:\usr\apps\python\current
PATH-=C:\usr\apps\perl\current\perl\site\bin
PATH-=C:\usr\apps\perl\current\perl\bin
PATH-=C:\usr\apps\python313\current\Scripts
PATH-=C:\usr\apps\python313\current
PATH-=C:\usr\apps\ant\current\bin
PATH-=C:\usr\apps\maven\current\bin
PATH-=C:\usr\shims
PATH-=C:\usr\apps\vscode\current\bin

# ============================================================================
# MSYS2/MinGW - LOW PRIORITY (Fallback for Unix tools)
# ============================================================================
MSYS2_HOME=$ScoopDir\apps\msys2\current
PATH+=`$MSYS2_HOME\usr\bin
PATH+=`$MSYS2_HOME\mingw64\bin

# ============================================================================
# VERSION CONTROL
# ============================================================================
SVN_HOME=$ScoopDir\apps\tortoisesvn\current
PATH+=`$SVN_HOME\bin

GIT_HOME=$ScoopDir\apps\git\current
PATH+=`$GIT_HOME\mingw64\bin
PATH+=`$GIT_HOME\usr\bin
PATH+=`$GIT_HOME\cmd

# ============================================================================
# C/C++ DEVELOPMENT
# ============================================================================
MAKE_HOME=$ScoopDir\apps\make\current
PATH+=`$MAKE_HOME\bin

CMAKE_HOME=$ScoopDir\apps\cmake\current
PATH+=`$CMAKE_HOME\bin

# ============================================================================
# NODE.JS DEVELOPMENT
# ============================================================================
NODE_HOME=$ScoopDir\apps\nodejs\current
PATH+=`$NODE_HOME
NODE_PATH=`$NODE_HOME\node_modules
NPM_CONFIG_PREFIX=$ScoopDir\persist\nodejs
PATH+=`$NPM_CONFIG_PREFIX\bin

# ============================================================================
# PERL DEVELOPMENT
# ============================================================================
PERL_HOME=$ScoopDir\apps\perl\current
PATH+=`$PERL_HOME\perl\site\bin
PATH+=`$PERL_HOME\perl\bin
PERL5LIB=`$PERL_HOME\perl\lib;`$PERL_HOME\perl\site\lib

# ============================================================================
# PYTHON DEVELOPMENT
# ============================================================================
PYTHON_HOME=$ScoopDir\apps\python313\current
PATH+=`$PYTHON_HOME\Scripts
PATH+=`$PYTHON_HOME
PYTHONPATH=`$PYTHON_HOME\Lib\site-packages

# ============================================================================
# KOTLIN DEVELOPMENT
# ============================================================================
KOTLIN_HOME=$ScoopDir\apps\kotlin\current
PATH+=`$KOTLIN_HOME\bin

# ============================================================================
# JAVA DEVELOPMENT & BUILD TOOLS
# ============================================================================
ANT_HOME=$ScoopDir\apps\ant\current
PATH+=`$ANT_HOME\bin

GRADLE_HOME=$ScoopDir\apps\gradle\current
PATH+=`$GRADLE_HOME\bin
GRADLE_USER_HOME=`$USERPROFILE\.gradle
GRADLE_OPTS=-Xmx2048m -Dorg.gradle.daemon=true -Dorg.gradle.parallel=true

MAVEN_HOME=$ScoopDir\apps\maven\current
PATH+=`$MAVEN_HOME\bin
M2_HOME=`$MAVEN_HOME
M2_REPO=`$USERPROFILE\.m2\repository
MAVEN_OPTS=-Xmx1024m -XX:+TieredCompilation -XX:TieredStopAtLevel=1

JAVA_HOME=$ScoopDir\apps\temurin21-jdk\current
PATH+=`$JAVA_HOME\bin
JAVA_OPTS=-Xmx2g -Xms512m -XX:+UseG1GC -XX:MaxGCPauseMillis=200

# ============================================================================
# CORE PATHS - HIGHEST PRIORITY (at the bottom!)
# ============================================================================
PATH+=`$SCOOP\shims
PATH+=`$SCOOP\bin

# ============================================================================
# LOCALE & ENCODING
# ============================================================================
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
LANGUAGE=en_US:en
"@
    
    # Create environment directory
    $envDir = "$ScoopDir\etc\environments"
    if (-not (Test-Path $envDir)) {
        New-Item -ItemType Directory -Path $envDir -Force | Out-Null
        Write-Host "[OK] Created directory: $envDir" -ForegroundColor Green
    }
    
    # Save environment file
    $envFile = "$envDir\system.$Hostname.$Username.env"
    $envContent | Out-File -FilePath $envFile -Encoding UTF8
    Write-Host "[OK] Created environment file: $envFile" -ForegroundColor Green
    
    Write-Host ""
    Write-Host ">>> Applying environment configuration to Machine scope..." -ForegroundColor Magenta
    Write-Host "[INFO] Running: scoop-boot.ps1 --apply-env (as Administrator)" -ForegroundColor Cyan
    Write-Host ""
    
    # Apply environment as admin (Machine scope)
    try {
        & "$ScoopDir\bin\scoop-boot.ps1" --apply-env
        Write-Host ""
        Write-Host "[OK] Environment variables set in Machine scope" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Failed to apply environment: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "[INFO] You can manually apply later with: scoop-boot.ps1 --apply-env" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "=== Phase 1 Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Environment variables have been set system-wide (Machine scope)." -ForegroundColor Cyan
    Write-Host "All users on this system will have access to these settings." -ForegroundColor Gray
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "1. Close this Administrator PowerShell" -ForegroundColor White
    Write-Host "2. Open a NEW PowerShell/CMD as REGULAR USER" -ForegroundColor White
    Write-Host "3. Run: .\scoop-complete-install.ps1 -InstallTools" -ForegroundColor White
    Write-Host ""
}

# ============================================================================
# PART 2: TOOLS INSTALLATION (RUN AS USER)
# ============================================================================
function Install-ScoopTools {
    Write-Host ""
    Write-Host "=== Phase 2: Tools Installation (User) ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if running as admin (should NOT be for Scoop)
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if ($isAdmin) {
        Write-Host "[WARN] Running as Administrator - Scoop should be run as normal user!" -ForegroundColor Yellow
        Write-Host "Continue anyway? (y/N): " -NoNewline
        $response = Read-Host
        if ($response -ne 'y') { exit 0 }
    }
    
    Write-Host "[OK] Running as normal user" -ForegroundColor Green
    Write-Host ""
    
    # ============================================================================
    # BOOTSTRAP SCOOP
    # ============================================================================
    Write-Host ">>> Step 1: Bootstrap Scoop..." -ForegroundColor Magenta
    Write-Host ""
    
    # Ensure scoop-boot.ps1 exists
    if (-not (Test-Path "$ScoopDir\bin\scoop-boot.ps1")) {
        Write-Host "[INFO] Downloading scoop-boot.ps1..." -ForegroundColor Cyan
        
        if (-not (Test-Path "$ScoopDir\bin")) {
            New-Item -ItemType Directory -Path "$ScoopDir\bin" -Force | Out-Null
        }
        
        $scoopBootUrl = "https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1"
        try {
            Invoke-WebRequest -Uri $scoopBootUrl -OutFile "$ScoopDir\bin\scoop-boot.ps1"
            Write-Host "[OK] Downloaded scoop-boot.ps1" -ForegroundColor Green
        } catch {
            Write-Host "[ERROR] Could not download scoop-boot.ps1" -ForegroundColor Red
            Write-Host "Please download manually from: $scoopBootUrl" -ForegroundColor Yellow
            exit 1
        }
    }
    
    # Bootstrap Scoop via scoop-boot.ps1
    Write-Host "[INFO] Running: scoop-boot.ps1 --bootstrap" -ForegroundColor Cyan
    & "$ScoopDir\bin\scoop-boot.ps1" --bootstrap
    
    # Update PATH for current session
    $env:Path = "$ScoopDir\shims;$ScoopDir\bin;$env:Path"
    
    Write-Host ""
    Write-Host "[OK] Scoop bootstrapped successfully" -ForegroundColor Green
    Write-Host ""
    
    # Disable aria2 warnings (now that scoop exists)
    scoop config aria2-warning-enabled false 2>$null
    
    # ============================================================================
    # ADD BUCKETS
    # ============================================================================
    Write-Host ">>> Step 2: Adding Scoop buckets..." -ForegroundColor Magenta
    Write-Host ""
    
    $buckets = @('main', 'extras', 'java', 'versions')
    foreach ($bucket in $buckets) {
        Write-Host "Adding bucket: $bucket" -ForegroundColor Gray
        $bucketExists = scoop bucket list 2>$null | Select-String -Pattern "^$bucket"
        if (-not $bucketExists) {
            scoop bucket add $bucket 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "[OK] Added bucket: $bucket" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Could not add bucket: $bucket" -ForegroundColor Yellow
            }
        } else {
            Write-Host "[INFO] Bucket already exists: $bucket" -ForegroundColor Gray
        }
    }
    Write-Host ""
    
    # ============================================================================
    # INSTALL TOOLS
    # ============================================================================
    Write-Host ">>> Step 3: Installing development tools..." -ForegroundColor Magenta
    Write-Host ""
    Write-Host "This will take 15-30 minutes depending on your internet connection." -ForegroundColor Gray
    Write-Host ""
    
    # Essential tools (already installed by bootstrap, but ensure they're there)
    Write-Host "[Category] Essential tools" -ForegroundColor Cyan
    $essentialTools = @('7zip', 'git', 'aria2', 'sudo', 'innounp', 'dark', 'lessmsi', 'wget', 'cacert')
    foreach ($tool in $essentialTools) {
        if (-not (scoop list $tool 2>$null | Select-String $tool)) {
            Write-Host "Installing: $tool" -ForegroundColor Gray
            scoop install $tool 2>$null
        } else {
            Write-Host "[INFO] Already installed: $tool" -ForegroundColor Gray
        }
    }
    Write-Host ""
    
    # Java versions
    Write-Host "[Category] Java Development Kits" -ForegroundColor Cyan
    $javaVersions = @('temurin8-jdk', 'temurin11-jdk', 'temurin17-jdk', 'temurin21-jdk', 'temurin23-jdk')
    foreach ($java in $javaVersions) {
        Write-Host "Installing: $java" -ForegroundColor Gray
        scoop install $java 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installed: $java" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed: $java" -ForegroundColor Yellow
        }
    }
    
    Write-Host "Setting default Java to temurin21-jdk..." -ForegroundColor Gray
    scoop reset temurin21-jdk 2>$null
    Write-Host ""
    
    # Build tools
    Write-Host "[Category] Build Tools" -ForegroundColor Cyan
    $buildTools = @('maven', 'gradle', 'ant', 'kotlin', 'cmake', 'make', 'ninja')
    foreach ($tool in $buildTools) {
        Write-Host "Installing: $tool" -ForegroundColor Gray
        scoop install $tool 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installed: $tool" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed: $tool" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # Programming languages
    Write-Host "[Category] Programming Languages" -ForegroundColor Cyan
    
    Write-Host "Installing: python313" -ForegroundColor Gray
    scoop install python313 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Installed: python313" -ForegroundColor Green
    }
    
    Write-Host "Installing: perl" -ForegroundColor Gray
    scoop install perl 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Installed: perl" -ForegroundColor Green
    }
    
    Write-Host "Installing: nodejs" -ForegroundColor Gray
    scoop install nodejs 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Installed: nodejs" -ForegroundColor Green
    }
    
    Write-Host "Installing: msys2" -ForegroundColor Gray
    scoop install msys2 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Installed: msys2" -ForegroundColor Green
    }
    Write-Host ""
    
    # Version control
    Write-Host "[Category] Version Control" -ForegroundColor Cyan
    $vcsTools = @('tortoisesvn', 'gh', 'lazygit')
    foreach ($tool in $vcsTools) {
        Write-Host "Installing: $tool" -ForegroundColor Gray
        scoop install $tool 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installed: $tool" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed: $tool" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # Editors
    Write-Host "[Category] Editors & IDEs" -ForegroundColor Cyan
    $editors = @('vscode', 'neovim', 'notepadplusplus')
    foreach ($editor in $editors) {
        Write-Host "Installing: $editor" -ForegroundColor Gray
        scoop install $editor 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installed: $editor" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed: $editor" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # GUI tools
    Write-Host "[Category] GUI Applications" -ForegroundColor Cyan
    $guiTools = @(
        'windows-terminal', 'hxd', 'winmerge', 'freecommander', 
        'greenshot', 'mousejiggler', 'processhacker', 'everything',
        'postman', 'dbeaver'
    )
    foreach ($tool in $guiTools) {
        Write-Host "Installing: $tool" -ForegroundColor Gray
        scoop install $tool 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installed: $tool" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed: $tool" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # Utilities
    Write-Host "[Category] Command-Line Utilities" -ForegroundColor Cyan
    $utilities = @('jq', 'openssh', 'putty', 'winscp', 'filezilla', 'curl', 'ripgrep', 'fd', 'bat')
    # Note: htop is Linux-only, use ProcessHacker or Windows Task Manager instead
    foreach ($tool in $utilities) {
        Write-Host "Installing: $tool" -ForegroundColor Gray
        scoop install $tool 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installed: $tool" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed: $tool" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # ============================================================================
    # REGISTRY IMPORTS
    # ============================================================================
    Write-Host ">>> Step 4: Importing registry files..." -ForegroundColor Magenta
    Write-Host ""
    
    # Context menu registrations
    $appsWithContextMenu = @(
        @{App='7zip'; Files=@('install-context.reg')},
        @{App='notepadplusplus'; Files=@('install-context.reg')},
        @{App='vscode'; Files=@('install-context.reg', 'install-associations.reg')},
        @{App='windows-terminal'; Files=@('install-context.reg')},
        @{App='git'; Files=@('install-context.reg')},
        @{App='tortoisesvn'; Files=@('tortoisesvn-install.reg', 'tortoisesvn-install-tools.reg')}
    )
    
    foreach ($item in $appsWithContextMenu) {
        $appDir = "$ScoopDir\apps\$($item.App)\current"
        if (Test-Path $appDir) {
            foreach ($regFileName in $item.Files) {
                $regPath = "$appDir\$regFileName"
                if (Test-Path $regPath) {
                    try {
                        reg import $regPath 2>$null
                        Write-Host "[OK] Imported registry: $($item.App) - $regFileName" -ForegroundColor Green
                    } catch {
                        Write-Host "[WARN] Could not import: $($item.App) - $regFileName" -ForegroundColor Yellow
                    }
                }
            }
        }
    }
    
    # Python PEP-514 registration
    $pythonReg = "$ScoopDir\apps\python313\current\install-pep-514.reg"
    if (Test-Path $pythonReg) {
        reg import $pythonReg 2>$null
        Write-Host "[OK] Imported registry: Python 3.13 PEP-514" -ForegroundColor Green
    }
    Write-Host ""
    
    # ============================================================================
    # FINAL STATUS & MANUAL CONFIGURATION NEEDED
    # ============================================================================
    Write-Host "=== Phase 2 Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Installed applications:" -ForegroundColor Cyan
    scoop list
    Write-Host ""
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  MANUAL CONFIGURATION REQUIRED" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "The following applications require manual configuration:" -ForegroundColor White
    Write-Host ""
    
    # WinMerge
    Write-Host "1. WinMerge (Diff/Merge Tool)" -ForegroundColor Yellow
    Write-Host "   Start: winmerge" -ForegroundColor Gray
    Write-Host "   Configure: Edit > Options > Shell Integration" -ForegroundColor White
    Write-Host "   Enable: 'Add WinMerge to Windows Explorer context menu'" -ForegroundColor White
    Write-Host ""
    
    # HxD
    Write-Host "2. HxD (Hex Editor)" -ForegroundColor Yellow
    Write-Host "   Start: hxd" -ForegroundColor Gray
    Write-Host "   Configure: Tools > Options > Context Menu (optional)" -ForegroundColor White
    Write-Host "   Enable: 'Integrate into Explorer context menu'" -ForegroundColor White
    Write-Host ""
    
    # Greenshot
    Write-Host "3. Greenshot (Screenshot Tool)" -ForegroundColor Yellow
    Write-Host "   Start: greenshot" -ForegroundColor Gray
    Write-Host "   Autostart: Right-click tray icon > Preferences > General" -ForegroundColor White
    Write-Host "   Enable: 'Launch Greenshot on startup'" -ForegroundColor White
    Write-Host "   Hotkeys: PrintScreen = Region, Alt+PrintScreen = Window" -ForegroundColor Gray
    Write-Host ""
    
    # FreeCommander
    Write-Host "4. FreeCommander (File Manager)" -ForegroundColor Yellow
    Write-Host "   Start: freecommander" -ForegroundColor Gray
    Write-Host "   Configure: Settings > Integration (optional)" -ForegroundColor White
    Write-Host "   Enable: 'Replace Windows Explorer' or add to context menu" -ForegroundColor White
    Write-Host ""
    
    # Everything
    Write-Host "5. Everything (File Search)" -ForegroundColor Yellow
    Write-Host "   Start: everything" -ForegroundColor Gray
    Write-Host "   Configure: Tools > Options > General" -ForegroundColor White
    Write-Host "   Enable: 'Start Everything on system startup'" -ForegroundColor White
    Write-Host "   Enable: 'Install Everything service' (requires admin, for NTFS indexing)" -ForegroundColor White
    Write-Host ""
    
    # ProcessHacker
    Write-Host "6. ProcessHacker (Task Manager)" -ForegroundColor Yellow
    Write-Host "   Start: processhacker" -ForegroundColor Gray
    Write-Host "   Configure: Options > Advanced (optional)" -ForegroundColor White
    Write-Host "   Enable: 'Replace Task Manager' (requires admin)" -ForegroundColor White
    Write-Host ""
    
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "IMPORTANT: Restart your shell for all changes to take effect!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Quick verification:" -ForegroundColor Cyan
    Write-Host "  scoop --version" -ForegroundColor Gray
    Write-Host "  java -version" -ForegroundColor Gray
    Write-Host "  python --version" -ForegroundColor Gray
    Write-Host "  node --version" -ForegroundColor Gray
    Write-Host ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
Write-Host ""
Write-Host "=== Scoop Complete Installation Script ===" -ForegroundColor Cyan
Write-Host "Two-phase installation for complete development environment" -ForegroundColor Gray
Write-Host ""

if ($All) {
    Set-DevelopmentEnvironment
    Write-Host "Please restart PowerShell as normal user and run:" -ForegroundColor Yellow
    Write-Host ".\scoop-complete-install.ps1 -InstallTools" -ForegroundColor White
    Write-Host ""
    exit 0
}

if ($SetEnvironment) {
    Set-DevelopmentEnvironment
} elseif ($InstallTools) {
    Install-ScoopTools
} else {
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Phase 1 - Run as Administrator (sets environment in Machine scope):" -ForegroundColor Cyan
    Write-Host "  .\scoop-complete-install.ps1 -SetEnvironment" -ForegroundColor White
    Write-Host ""
    Write-Host "Phase 2 - Run as normal user (installs all tools):" -ForegroundColor Cyan
    Write-Host "  .\scoop-complete-install.ps1 -InstallTools" -ForegroundColor White
    Write-Host ""
    Write-Host "Or run both in sequence (requires admin, then restart as user):" -ForegroundColor Cyan
    Write-Host "  .\scoop-complete-install.ps1 -All" -ForegroundColor White
    Write-Host ""
}