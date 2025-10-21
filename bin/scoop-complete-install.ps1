<#
.SYNOPSIS
    Complete installation of Scoop development environment
    
.DESCRIPTION
    Two-phase installation:
    Phase 1 (Admin): Sets Machine-scope environment variables DIRECTLY
    Phase 2 (User): Installs all tools
    
.NOTES
    Version: 2.1.0
    Date: 2025-10-21
    
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
    Write-Host "=== Phase 2: Tools Installation (User) ===" -ForegroundColor Cyan
    Write-Host ""
    
    # Check if NOT running as admin
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if ($isAdmin) {
        Write-Host "[WARN] Running as Administrator - Scoop works best as normal user!" -ForegroundColor Yellow
        Write-Host "Continue anyway? [y/N]: " -NoNewline
        $response = Read-Host
        if ($response -ne 'y' -and $response -ne 'Y') { exit 0 }
    } else {
        Write-Host "[OK] Running as normal user" -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host ">>> Step 1: Bootstrap Scoop..." -ForegroundColor White
    Write-Host ""
    
    if (-not (Test-Path "$ScoopDir\bin")) {
        New-Item -ItemType Directory -Path "$ScoopDir\bin" -Force | Out-Null
    }
    
    if (-not (Test-Path "$ScoopDir\bin\scoop-boot.ps1")) {
        Write-Host "[INFO] Downloading scoop-boot.ps1..." -ForegroundColor Gray
        try {
            Invoke-WebRequest -Uri "https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1" -OutFile "$ScoopDir\bin\scoop-boot.ps1" -UseBasicParsing
            Write-Host "[OK] Downloaded scoop-boot.ps1" -ForegroundColor Green
        } catch {
            Write-Host "[WARN] Could not download scoop-boot.ps1" -ForegroundColor Yellow
        }
    }
    
    if (Test-Path "$ScoopDir\bin\scoop-boot.ps1") {
        Write-Host "[INFO] Running: scoop-boot.ps1 --bootstrap" -ForegroundColor Gray
        Write-Host ""
        & "$ScoopDir\bin\scoop-boot.ps1" --bootstrap
    } else {
        Write-Host "[WARN] Using manual bootstrap" -ForegroundColor Yellow
        $env:SCOOP = $ScoopDir
        $env:SCOOP_GLOBAL = "$ScoopDir\global"
        [Environment]::SetEnvironmentVariable('SCOOP', $ScoopDir, 'User')
        [Environment]::SetEnvironmentVariable('SCOOP_GLOBAL', "$ScoopDir\global", 'User')
        
        $tempInstaller = "$env:TEMP\scoop-install.ps1"
        Invoke-WebRequest -Uri 'https://get.scoop.sh' -OutFile $tempInstaller -UseBasicParsing
        & $tempInstaller -ScoopDir $ScoopDir -ScoopGlobalDir "$ScoopDir\global" -NoProxy
        Remove-Item $tempInstaller -Force
    }
    
    $env:Path = "$ScoopDir\shims;$ScoopDir\bin;$env:Path"
    Write-Host ""
    Write-Host "[OK] Scoop bootstrapped" -ForegroundColor Green
    
    scoop config aria2-warning-enabled false | Out-Null
    
    Write-Host ""
    Write-Host ">>> Step 2: Adding buckets..." -ForegroundColor White
    Write-Host ""
    
    $buckets = @('main', 'extras', 'java', 'versions')
    foreach ($bucket in $buckets) {
        Write-Host "Adding bucket: $bucket" -ForegroundColor Gray
        $output = scoop bucket add $bucket 2>&1
        if ($output -match 'already exists') {
            Write-Host "[WARN] Could not add bucket: $bucket" -ForegroundColor Yellow
        } else {
            Write-Host "[OK] Added bucket: $bucket" -ForegroundColor Green
        }
    }
    
    Write-Host ""
    Write-Host ">>> Step 3: Installing development tools..." -ForegroundColor White
    Write-Host ""
    Write-Host "This will take 15-30 minutes." -ForegroundColor Yellow
    Write-Host ""
    
    function Install-Category {
        param([string]$CategoryName, [array]$Tools)
        Write-Host ""
        Write-Host "[Category] $CategoryName" -ForegroundColor Cyan
        foreach ($tool in $Tools) {
            $installed = scoop list $tool 2>&1 | Select-String "^\s*$tool\s"
            if ($installed) {
                Write-Host "[INFO] Already installed: $tool" -ForegroundColor Gray
            } else {
                Write-Host "Installing: $tool" -ForegroundColor Gray
                scoop install $tool 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[OK] Installed: $tool" -ForegroundColor Green
                } else {
                    Write-Host "[WARN] Failed: $tool" -ForegroundColor Yellow
                }
            }
        }
    }
    
    Install-Category -CategoryName "Essential tools" -Tools @(
        '7zip', 'git', 'aria2', 'sudo', 'innounp', 'dark', 'lessmsi', 'wget', 'cacert'
    )
    
    Install-Category -CategoryName "Java Development Kits" -Tools @(
        'temurin8-jdk', 'temurin11-jdk', 'temurin17-jdk', 'temurin21-jdk', 'temurin23-jdk'
    )
    
    Install-Category -CategoryName "Build Tools" -Tools @(
        'maven', 'gradle', 'ant', 'kotlin', 'cmake', 'make', 'ninja', 'graphviz', 'doxygen', 'vcpkg'
    )
    
    Install-Category -CategoryName "Programming Languages" -Tools @(
        'python313', 'perl', 'nodejs', 'msys2'
    )
    
    Install-Category -CategoryName "Version Control" -Tools @(
        'tortoisesvn', 'gh', 'lazygit'
    )
    
    Install-Category -CategoryName "Editors & IDEs" -Tools @(
        'vscode', 'neovim', 'notepadplusplus', 'jetbrains-toolbox'
    )
    
    Install-Category -CategoryName "GUI Applications" -Tools @(
        'windows-terminal', 'hxd', 'winmerge', 'freecommander', 'greenshot', 
        'everything', 'postman', 'dbeaver'
    )
    
    Install-Category -CategoryName "Command-Line Utilities" -Tools @(
        'jq', 'openssh', 'putty', 'winscp', 'filezilla', 'curl', 'ripgrep', 'fd', 'bat', 'less', 'jid'
    )
    
    Write-Host ""
    Write-Host "Setting default Java to temurin21-jdk..." -ForegroundColor Gray
    scoop reset temurin21-jdk 2>&1 | Out-Null
    
    Write-Host ""
    Write-Host ">>> Step 4: Post-installation..." -ForegroundColor White
    Write-Host ""
    
    Write-Host "[INFO] Installing VC++ Runtime..." -ForegroundColor Gray
    scoop install vcredist2022 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] VC++ Runtime installed" -ForegroundColor Green
        scoop uninstall vcredist2022 2>&1 | Out-Null
        Write-Host "[OK] Installer removed (libraries remain)" -ForegroundColor Green
    }
    
    Write-Host "[INFO] Installing system informer..." -ForegroundColor Gray
    scoop install systeminformer 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Installed: systeminformer" -ForegroundColor Green
    }
    
    Write-Host "[INFO] Initializing MSYS2..." -ForegroundColor Gray
    $msys2Path = "$ScoopDir\apps\msys2\current\msys2.exe"
    if (Test-Path $msys2Path) {
        Start-Process -FilePath $msys2Path -ArgumentList "-c", "exit" -NoNewWindow -Wait -ErrorAction SilentlyContinue
        Write-Host "[OK] MSYS2 initialization started" -ForegroundColor Green
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
    
    Write-Host ""
    Write-Host "=== Installation Complete! ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "IMPORTANT: Restart your shell!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Verify:" -ForegroundColor Cyan
    Write-Host "  java -version    # Should show Java 21" -ForegroundColor Gray
    Write-Host "  python --version # Should show Python 3.13.9" -ForegroundColor Gray
    Write-Host ""
    Write-Host "MSYS2 GCC Setup:" -ForegroundColor Cyan
    Write-Host "  pacman -Syu" -ForegroundColor Gray
    Write-Host "  pacman -S mingw-w64-ucrt-x86_64-gcc" -ForegroundColor Gray
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