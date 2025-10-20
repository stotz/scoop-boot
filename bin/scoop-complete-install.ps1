<#
.SYNOPSIS
    Complete installation of Scoop development environment based on all chats
    
.DESCRIPTION
    This script installs all tools and configurations from the chats.
    Part 1: Set environment variables as admin
    Part 2: Install tools as regular user
    
.NOTES
    Version: 1.0.0
    Author: System Configuration
    Date: 2025-10-21
    
.EXAMPLE
    # Part 1 - As Administrator PowerShell:
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    .\scoop-complete-install.ps1 -SetEnvironment
    
    # Part 2 - As regular user:
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
    Write-Host "=== Setting Development Environment (Admin Required) ===" -ForegroundColor Cyan
    
    # Check admin rights
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    
    if (-not $isAdmin) {
        Write-Host "[ERROR] This part requires administrator privileges!" -ForegroundColor Red
        Write-Host "Run PowerShell as Administrator and try again." -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "[OK] Running with administrator privileges" -ForegroundColor Green
    
    # Create environment file content
    $envContent = @"
# ============================================================================
# System Environment Configuration
# File: system.$Hostname.$Username.env
# Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# ============================================================================
# Scope: Machine (requires admin)
# SCOOP: $ScoopDir
# Hostname: $Hostname
# Username: $Username
# ============================================================================

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
SVN_HOME=$ScoopDir\apps\svn\current
PATH+=`$SVN_HOME\bin

GIT_HOME=$ScoopDir\apps\git\current
PATH+=`$GIT_HOME\mingw64\bin
PATH+=`$GIT_HOME\usr\bin
PATH+=`$GIT_HOME\cmd
GIT_SSH=$ScoopDir\apps\openssh\current\ssh.exe

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
    Write-Host "=== Environment Setup Complete ===" -ForegroundColor Green
    Write-Host "Next: Run this script as normal user with -InstallTools parameter" -ForegroundColor Yellow
    Write-Host ""
}

# ============================================================================
# PART 2: TOOLS INSTALLATION (RUN AS USER)
# ============================================================================
function Install-ScoopTools {
    Write-Host "=== Installing Scoop and Development Tools ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if running as admin (should NOT be for Scoop)
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if ($isAdmin) {
        Write-Host "[WARN] Running as Administrator - Scoop works better as normal user!" -ForegroundColor Yellow
        Write-Host "Continue anyway? (y/N): " -NoNewline
        $response = Read-Host
        if ($response -ne 'y') { exit 0 }
    }
    
    # ============================================================================
    # BOOTSTRAP SCOOP
    # ============================================================================
    Write-Host ">>> Bootstrapping Scoop..." -ForegroundColor White
    
    # Download and save scoop-boot.ps1
    if (-not (Test-Path "$ScoopDir\bin")) {
        New-Item -ItemType Directory -Path "$ScoopDir\bin" -Force | Out-Null
    }
    
    if (-not (Test-Path "$ScoopDir\bin\scoop-boot.ps1")) {
        Write-Host "Downloading scoop-boot.ps1..." -ForegroundColor Gray
        $scoopBootUrl = "https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1"
        try {
            Invoke-WebRequest -Uri $scoopBootUrl -OutFile "$ScoopDir\bin\scoop-boot.ps1"
            Write-Host "[OK] Downloaded scoop-boot.ps1" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Could not download scoop-boot.ps1, using manual bootstrap" -ForegroundColor Yellow
        }
    }
    
    # Bootstrap Scoop
    if (Test-Path "$ScoopDir\bin\scoop-boot.ps1") {
        & "$ScoopDir\bin\scoop-boot.ps1" --bootstrap
    } else {
        # Manual bootstrap
        $env:SCOOP = $ScoopDir
        $env:SCOOP_GLOBAL = "$ScoopDir\global"
        [Environment]::SetEnvironmentVariable('SCOOP', $ScoopDir, 'User')
        [Environment]::SetEnvironmentVariable('SCOOP_GLOBAL', "$ScoopDir\global", 'User')
        
        Invoke-WebRequest -Uri 'https://get.scoop.sh' -OutFile "$env:TEMP\install.ps1"
        & "$env:TEMP\install.ps1" -ScoopDir $ScoopDir -ScoopGlobalDir "$ScoopDir\global" -NoProxy
        Remove-Item "$env:TEMP\install.ps1" -Force
    }
    
    # Update PATH for current session
    $env:Path = "$ScoopDir\shims;$ScoopDir\bin;$env:Path"
    
    Write-Host "[OK] Scoop bootstrapped" -ForegroundColor Green
    Write-Host ""
    
    # ============================================================================
    # ADD BUCKETS
    # ============================================================================
    Write-Host ">>> Adding Scoop buckets..." -ForegroundColor White
    
    $buckets = @('main', 'extras', 'java', 'versions')
    foreach ($bucket in $buckets) {
        Write-Host "Adding bucket: $bucket" -ForegroundColor Gray
        scoop bucket add $bucket 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Bucket added: $bucket" -ForegroundColor Green
        }
    }
    Write-Host ""
    
    # ============================================================================
    # INSTALL ESSENTIAL TOOLS
    # ============================================================================
    Write-Host ">>> Installing essential tools..." -ForegroundColor White
    
    $essentialTools = @(
        '7zip',
        'git',
        'aria2',
        'sudo',
        'innounp',
        'dark',
        'lessmsi',
        'wget',
        'cacert'
    )
    
    foreach ($tool in $essentialTools) {
        Write-Host "Installing: $tool" -ForegroundColor Gray
        scoop install $tool 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installed: $tool" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed to install: $tool" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # ============================================================================
    # INSTALL JAVA VERSIONS
    # ============================================================================
    Write-Host ">>> Installing Java versions..." -ForegroundColor White
    
    $javaVersions = @(
        'temurin8-jdk',
        'temurin11-jdk',
        'temurin17-jdk',
        'temurin21-jdk',
        'temurin23-jdk'
        # 'temurin25-jdk'  # Early access, optional
    )
    
    foreach ($java in $javaVersions) {
        Write-Host "Installing: $java" -ForegroundColor Gray
        scoop install $java 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installed: $java" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed to install: $java" -ForegroundColor Yellow
        }
    }
    
    # Set default Java version
    Write-Host "Setting default Java to temurin21-jdk..." -ForegroundColor Gray
    scoop reset temurin21-jdk
    Write-Host ""
    
    # ============================================================================
    # INSTALL BUILD TOOLS
    # ============================================================================
    Write-Host ">>> Installing build tools..." -ForegroundColor White
    
    $buildTools = @(
        'maven',
        'gradle',
        'ant',
        'kotlin',
        'cmake',
        'make',
        'ninja'
    )
    
    foreach ($tool in $buildTools) {
        Write-Host "Installing: $tool" -ForegroundColor Gray
        scoop install $tool 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installed: $tool" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed to install: $tool" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # ============================================================================
    # INSTALL PROGRAMMING LANGUAGES
    # ============================================================================
    Write-Host ">>> Installing programming languages..." -ForegroundColor White
    
    # Python 3.13
    Write-Host "Installing: python313" -ForegroundColor Gray
    scoop install python313 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Installed: python313" -ForegroundColor Green
        # Register Python
        $regFile = "$ScoopDir\apps\python313\current\install-pep-514.reg"
        if (Test-Path $regFile) {
            reg import $regFile 2>$null
            Write-Host "[OK] Registered Python 3.13 in registry" -ForegroundColor Green
        }
    }
    
    # Perl
    Write-Host "Installing: perl" -ForegroundColor Gray
    scoop install perl 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Installed: perl" -ForegroundColor Green
    }
    
    # Node.js
    Write-Host "Installing: nodejs" -ForegroundColor Gray
    scoop install nodejs 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Installed: nodejs" -ForegroundColor Green
    }
    
    # MSYS2 (for Unix tools)
    Write-Host "Installing: msys2" -ForegroundColor Gray
    scoop install msys2 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Installed: msys2" -ForegroundColor Green
    }
    Write-Host ""
    
    # ============================================================================
    # INSTALL VERSION CONTROL
    # ============================================================================
    Write-Host ">>> Installing version control tools..." -ForegroundColor White
    
    $vcsTools = @(
        'svn',
        'gh',        # GitHub CLI
        'lazygit'    # Git TUI
    )
    
    foreach ($tool in $vcsTools) {
        Write-Host "Installing: $tool" -ForegroundColor Gray
        scoop install $tool 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installed: $tool" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed to install: $tool" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # ============================================================================
    # INSTALL EDITORS & IDES
    # ============================================================================
    Write-Host ">>> Installing editors and IDEs..." -ForegroundColor White
    
    $editors = @(
        'vscode',
        'neovim',
        'notepadplusplus'
    )
    
    foreach ($editor in $editors) {
        Write-Host "Installing: $editor" -ForegroundColor Gray
        scoop install $editor 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installed: $editor" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed to install: $editor" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # ============================================================================
    # INSTALL GUI TOOLS
    # ============================================================================
    Write-Host ">>> Installing GUI tools..." -ForegroundColor White
    
    $guiTools = @(
        'windows-terminal',
        'hxd',              # Hex editor
        'winmerge',         # Diff tool
        'freecommander',    # File manager
        'greenshot',        # Screenshot tool
        'mousejiggler',     # Keep system awake
        'processhacker',    # Task manager++
        'everything',       # File search
        'postman',          # API testing
        'dbeaver'           # Database client
    )
    
    foreach ($tool in $guiTools) {
        Write-Host "Installing: $tool" -ForegroundColor Gray
        scoop install $tool 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installed: $tool" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed to install: $tool" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # ============================================================================
    # INSTALL UTILITIES
    # ============================================================================
    Write-Host ">>> Installing utilities..." -ForegroundColor White
    
    $utilities = @(
        'jq',               # JSON processor
        'openssh',          # SSH client
        'putty',            # SSH client GUI
        'winscp',           # SFTP client
        'filezilla',        # FTP client
        'curl',             # HTTP client
        'htop',             # Process viewer
        'ripgrep',          # Fast grep
        'fd',               # Fast find
        'bat'               # Better cat
    )
    
    foreach ($tool in $utilities) {
        Write-Host "Installing: $tool" -ForegroundColor Gray
        scoop install $tool 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[OK] Installed: $tool" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Failed to install: $tool" -ForegroundColor Yellow
        }
    }
    Write-Host ""
    
    # ============================================================================
    # REGISTER CONTEXT MENUS
    # ============================================================================
    Write-Host ">>> Registering context menus..." -ForegroundColor White
    
    # These apps provide context menu registry files
    $contextMenus = @(
        @{App='7zip'; RegFile='install-context.reg'},
        @{App='notepadplusplus'; RegFile='install-context.reg'},
        @{App='vscode'; RegFile='install-context.reg'},
        @{App='windows-terminal'; RegFile='install-context.reg'},
        @{App='git'; RegFile='install-context.reg'}
    )
    
    foreach ($item in $contextMenus) {
        $regPath = "$ScoopDir\apps\$($item.App)\current\$($item.RegFile)"
        if (Test-Path $regPath) {
            reg import $regPath 2>$null
            Write-Host "[OK] Registered context menu for $($item.App)" -ForegroundColor Green
        } else {
            Write-Host "[INFO] No context menu registry file for $($item.App)" -ForegroundColor Gray
        }
    }
    
    # Special registry imports
    Write-Host ">>> Checking for special registry imports..." -ForegroundColor White
    
    # Python PEP-514 registration
    $pythonReg = "$ScoopDir\apps\python313\current\install-pep-514.reg"
    if ((Test-Path $pythonReg) -and -not (Test-Path "HKCU:\Software\Python\PythonCore\3.13")) {
        reg import $pythonReg 2>$null
        Write-Host "[OK] Python 3.13 registered in registry" -ForegroundColor Green
    }
    Write-Host ""
    
    # ============================================================================
    # USAGE INSTRUCTIONS FOR INSTALLED TOOLS
    # ============================================================================
    Write-Host ">>> Usage instructions for installed applications..." -ForegroundColor White
    Write-Host ""
    
    Write-Host "=== Applications with context menus registered ===" -ForegroundColor Cyan
    Write-Host "  7-Zip:            Right-click any file -> 7-Zip menu" -ForegroundColor Gray
    Write-Host "  Notepad++:        Right-click any file -> Edit with Notepad++" -ForegroundColor Gray
    Write-Host "  VS Code:          Right-click folder -> Open with Code" -ForegroundColor Gray
    Write-Host "  Windows Terminal: Right-click folder -> Open in Windows Terminal" -ForegroundColor Gray
    Write-Host "  Git:              Right-click folder -> Git Bash Here" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "=== Applications requiring manual configuration ===" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "HxD (Hex Editor):" -ForegroundColor Yellow
    Write-Host "  Start:     hxd                    (from any terminal)" -ForegroundColor Gray
    Write-Host "  Or:        Start Menu -> HxD" -ForegroundColor Gray
    Write-Host "  Context:   In HxD -> Tools -> Options -> Context Menu (optional)" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "WinMerge (Diff Tool):" -ForegroundColor Yellow
    Write-Host "  Start:     winmerge               (from any terminal)" -ForegroundColor Gray
    Write-Host "  Context:   In WinMerge -> Edit -> Options -> Shell Integration" -ForegroundColor Gray
    Write-Host "             Enable 'Add WinMerge to explorer context menu'" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "FreeCommander (File Manager):" -ForegroundColor Yellow
    Write-Host "  Start:     freecommander          (from any terminal)" -ForegroundColor Gray
    Write-Host "  Replace:   Settings -> Windows -> Replace Windows Explorer (optional)" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "Greenshot (Screenshot Tool):" -ForegroundColor Yellow
    Write-Host "  Start:     greenshot              (from any terminal)" -ForegroundColor Gray
    Write-Host "  Autostart: Will run in system tray automatically" -ForegroundColor Gray
    Write-Host "  Hotkeys:   PrintScreen = Region, Alt+PrintScreen = Window" -ForegroundColor Gray
    Write-Host "  Config:    Right-click tray icon -> Preferences" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "MouseJiggler (Keep Awake):" -ForegroundColor Yellow
    Write-Host "  Start:     mousejiggler           (from any terminal)" -ForegroundColor Gray
    Write-Host "  Usage:     Enable 'Zen Jiggle' for invisible mouse movement" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "ProcessHacker (Task Manager):" -ForegroundColor Yellow
    Write-Host "  Start:     processhacker          (from any terminal)" -ForegroundColor Gray
    Write-Host "  Replace:   Options -> Advanced -> Replace Task Manager (requires admin)" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "Everything (File Search):" -ForegroundColor Yellow
    Write-Host "  Start:     everything             (from any terminal)" -ForegroundColor Gray
    Write-Host "  Autostart: Tools -> Options -> General -> Start Everything on system startup" -ForegroundColor Gray
    Write-Host "  Service:   Tools -> Options -> General -> Install Everything service (for NTFS indexing)" -ForegroundColor Gray
    Write-Host ""
    
    Write-Host "=== Development tools (command line) ===" -ForegroundColor Cyan
    Write-Host "  Java:      java -version          (switch versions: scoop reset temurin21-jdk)" -ForegroundColor Gray
    Write-Host "  Python:    python --version       (package manager: pip install <package>)" -ForegroundColor Gray
    Write-Host "  Node.js:   node --version         (package manager: npm install <package>)" -ForegroundColor Gray
    Write-Host "  Perl:      perl --version         (package manager: cpan install <module>)" -ForegroundColor Gray
    Write-Host "  Maven:     mvn --version          (build: mvn clean install)" -ForegroundColor Gray
    Write-Host "  Gradle:    gradle --version       (build: gradle build)" -ForegroundColor Gray
    Write-Host ""
    
    # ============================================================================
    # APPLY ENVIRONMENT CONFIGURATION
    # ============================================================================
    Write-Host ">>> Applying environment configuration..." -ForegroundColor White
    
    if (Test-Path "$ScoopDir\bin\scoop-boot.ps1") {
        & "$ScoopDir\bin\scoop-boot.ps1" --apply-env
        Write-Host "[OK] Environment configuration applied" -ForegroundColor Green
    } else {
        Write-Host "[WARN] scoop-boot.ps1 not found, skipping environment configuration" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # ============================================================================
    # FINAL STATUS
    # ============================================================================
    Write-Host "=== Installation Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Installed apps:" -ForegroundColor Cyan
    scoop list
    Write-Host ""
    
    Write-Host "IMPORTANT: Restart your shell for all changes to take effect!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "1. Close this terminal and open a new one"
    Write-Host "2. Verify installation: scoop --version"
    Write-Host "3. Set default Java: scoop reset temurin21-jdk"
    Write-Host "4. Update Python pip: python -m pip install --upgrade pip"
    Write-Host ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
Write-Host ""
Write-Host "=== Scoop Complete Installation Script ===" -ForegroundColor Cyan
Write-Host "Based on all configurations from the chats" -ForegroundColor Gray
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
    Write-Host "Step 1 - Run as Administrator:" -ForegroundColor Cyan
    Write-Host "  .\scoop-complete-install.ps1 -SetEnvironment" -ForegroundColor White
    Write-Host ""
    Write-Host "Step 2 - Run as normal user:" -ForegroundColor Cyan
    Write-Host "  .\scoop-complete-install.ps1 -InstallTools" -ForegroundColor White
    Write-Host ""
    Write-Host "Or run both (starts with admin part):" -ForegroundColor Cyan
    Write-Host "  .\scoop-complete-install.ps1 -All" -ForegroundColor White
    Write-Host ""
}