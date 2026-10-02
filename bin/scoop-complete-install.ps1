<#
.SYNOPSIS
    Complete installation of Scoop development environment

.DESCRIPTION
    Two-phase installation:
    Phase 1 (Admin): Sets Machine-scope environment variables DIRECTLY
    Phase 2 (User): Installs all tools + automatic cleanup + GCC verification

.NOTES
    Version: 2.8.0
    Date: 2026-10-02

    Changes in v2.8.0:
    - Step 7 delegates to scoop-boot.ps1 --clean-user-scope (removes Scoop's
      User-scope overrides of variables the system.* file sets, sweeps User PATH
      entries inside Scoop's subdirectories, applies user.* files)
    - Phase 1 writes C:\usr\README_scoop_dir_warnings.md explaining which
      subdirectories belong to Scoop and what a reset removes
    - Phase 1 no longer sets User-level TMP/TEMP (Machine value is enough and
      User copies are removed as overrides anyway)

    Changes in v2.7.11:
    - Step 4: GCC compile-and-run smoke test with distinct messages for DLL
      shadowing (cc1.exe STATUS_ENTRYPOINT_NOT_FOUND) and for endpoint
      security refusing the built executable (Defender ASR 01443614)
    - Step 7: every User-PATH entry under C:\usr is removed, not only a fixed
      pattern list; the Machine PATH from the .env file is authoritative

    Changes in v2.7.10:
    - MSYS2/GCC: pacman -S is retried up to three times (mirror errors such as
      HTTP 500 on a signature file abort the whole transaction)

    Changes in v2.7.9:
    - FIX: WSL2 detection. wsl.exe output is UTF-16 and was matched with NUL
      bytes in it; "WSL version" 3.x was rejected; Store/MSI kernel path added.
    - FIX: MSYS2/GCC. msys2.exe is a launcher and returns immediately, so the
      two pacman runs overlapped (database lock) and the result depended on
      timing. bash.exe is called directly with MSYSTEM=UCRT64, waits, shows
      output and exit codes. A failure is listed in the summary.
    - Step 6 reports tray apps that are already running

    Changes in v2.7.8:
    - FIX: Step 3 reported "[OK] Installed" for every package regardless of
      the result. Success is now verified via apps\<app>\current; failed
      packages are collected and listed at the end.
    - Removed netcat (blocked by Windows Defender; ncat from nmap replaces it)
      and hxd (download host not reachable)
    - Step 4 creates the shims nc and netcat pointing to ncat.exe (scoop shim add)
    - vcredist2022: skipped when the VC++ 2015-2022 runtime is already
      installed (registry check); otherwise the result is verified and the
      elevated fallback command is printed

    Changes in v2.7.7:
    - FIX: Bootstrap on a fresh machine (official Scoop installer rejects the
      non-empty C:\usr). scoop-boot.ps1 v1.11.0 handles it; the manual
      fallback here applies the same installer patch.
    - Bootstrap output of scoop-boot.ps1 is no longer discarded
    - Phase 1 summary wording corrected (file applied, not created)

    Changes in v2.7.6:
    - Java: only temurin25-jdk is installed (removed 8, 11, 17, 21, 23)
    - Default Java is now Temurin 25
    - Python: python313 replaced by python314
    - Removed obsolete packages: processhacker (superseded by systeminformer), htop (no manifest)
    - svn renamed to sliksvn (manifest rename in Main bucket)
    - Verification hints no longer pin exact patch versions

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

    # Method 2: Parse "wsl --status" and "wsl --version".
    # wsl.exe writes UTF-16; captured through the default console encoding every
    # character is followed by a NUL, which breaks any regex. Read it as Unicode.
    try {
        $previousEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        try {
            $wslStatus  = (wsl --status 2>&1 | Out-String) -replace "`0", ''
            $wslVersion = (wsl --version 2>&1 | Out-String) -replace "`0", ''
            $wslList    = (wsl --list --verbose 2>&1 | Out-String) -replace "`0", ''
        } finally {
            [Console]::OutputEncoding = $previousEncoding
        }

        if ($wslStatus -match 'Default Version:\s*2') {
            Write-Host "  [OK] WSL2 detected: Default Version = 2" -ForegroundColor Green
            return $true
        }

        # Store/MSI WSL (1.x, 2.x, 3.x) reports a kernel version only when WSL2 is usable
        if ($wslVersion -match 'Kernel version:\s*\d') {
            Write-Host "  [OK] WSL2 detected: $(($wslVersion -split "`n" | Select-String 'WSL version').Line.Trim())" -ForegroundColor Green
            return $true
        }

        if ($wslList -match '\s+2\s*$') {
            Write-Host "  [OK] WSL2 detected: at least one distribution runs version 2" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "  [WARN] Could not parse wsl output: $_" -ForegroundColor Yellow
    }

    # Method 3: Kernel file (inbox feature: System32\lxss; Store/MSI package: Program Files\WSL)
    $wslKernelPaths = @(
        "$env:SystemRoot\System32\lxss\tools\kernel",
        "$env:ProgramFiles\WSL\tools\kernel"
    )
    foreach ($wslKernelPath in $wslKernelPaths) {
        if (Test-Path $wslKernelPath) {
            Write-Host "  [OK] WSL2 detected: kernel found at $wslKernelPath" -ForegroundColor Green
            return $true
        }
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

    # ============================================================================
    # CRITICAL: Fix TMP/TEMP FIRST (prevents all Scoop installation issues!)
    # ============================================================================
    Write-Host ">>> Setting up TEMP directories (CRITICAL for Scoop!)..." -ForegroundColor Yellow

    # Create C:\tmp directory
    if (-not (Test-Path "C:\tmp")) {
        New-Item -ItemType Directory -Path "C:\tmp" -Force | Out-Null
        # Set permissions
        icacls "C:\tmp" /grant "Everyone:(OI)(CI)F" /T /Q 2>&1 | Out-Null
        Write-Host "[OK] Created C:\tmp directory with full permissions" -ForegroundColor Green
    } else {
        Write-Host "[OK] C:\tmp directory already exists" -ForegroundColor Gray
    }

    # Set TMP and TEMP at Machine level
    [Environment]::SetEnvironmentVariable("TMP", "C:\tmp", "Machine")
    [Environment]::SetEnvironmentVariable("TEMP", "C:\tmp", "Machine")
    Write-Host "[OK] Set Machine-level: TMP=C:\tmp, TEMP=C:\tmp" -ForegroundColor Green

    # User-level TMP/TEMP are deliberately not set: the .env file sets them at
    # Machine scope and --clean-user-scope removes User overrides of managed names.

    # Apply to current session
    $env:TMP = "C:\tmp"
    $env:TEMP = "C:\tmp"
    Write-Host "[OK] Applied to current session" -ForegroundColor Green

    # Explain the directory layout to whoever looks into C:\usr later
    $dirReadme = "$ScoopDir\README_scoop_dir_warnings.md"
    @'
# C:\usr - read before putting anything here

This directory is the base of a Scoop-managed developer environment set up by
scoop-boot (https://github.com/stotz/scoop-boot). Scoop is NOT the owner of
C:\usr; it owns only these subdirectories:

    apps\       installed applications (one folder per app, "current" junction)
    buckets\    manifest repositories
    cache\      downloaded installers
    persist\    application data that survives updates
    shims\      the executables that are on PATH
    global\     globally installed apps (rarely used)

scoop-complete-reset.ps1 DELETES all of them. It also removes every environment
variable whose value points into them and every PATH entry inside them. Nothing
else is touched.

scoop-boot itself uses:

    bin\        the three scripts
    etc\        environments\*.env (the source of truth for PATH and variables)
    backups\    environment backups written by every reset (last 5 kept)

Rules:

- Do not install or copy software into apps\, shims\ or persist\ by hand;
  the next scoop update or reset will remove or break it.
- Other software may live in its own directory directly under C:\usr (for
  example C:\usr\PostgreSQL). scoop-boot leaves it alone, but its PATH entries
  and variables are then yours to maintain, not the .env file's.
- Do not set JAVA_HOME, PATH and friends by hand in the Windows dialog. Edit
  etc\environments\system.<hostname>.<username>.env and run
  scoop-complete-install.ps1 -SetEnvironment (as Administrator). After
  scoop update or scoop install, run scoop-boot.ps1 --clean-user-scope.
- Keep anything you cannot rebuild out of C:\usr or back it up elsewhere;
  C:\usr\backups holds environment snapshots only, not application data.
'@ | Set-Content -Path $dirReadme -Encoding ASCII
    Write-Host "[OK] Wrote $dirReadme" -ForegroundColor Green
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
    Write-Host "  - Environment file(s) applied at Machine scope" -ForegroundColor White
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
            & "$ScoopDir\bin\scoop-boot.ps1" --bootstrap
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

            # The official installer aborts when the target directory is not empty.
            # C:\usr already contains bin\ and etc\ (scoop-boot layout), so that single
            # check is replaced. Same patch as Get-ScoopInstaller in scoop-boot.ps1.
            $installerContent = [System.IO.File]::ReadAllText($tempInstaller)
            $emptyCheck = 'Deny-Install "''$SCOOP_DIR'' exists and is not empty, please specify another path."'
            $emptyInfo  = 'Write-Host "[INFO] ''$SCOOP_DIR'' is not empty (scoop-boot layout: bin\ and etc\ are expected), continuing"'
            if ($installerContent.Contains($emptyCheck)) {
                [System.IO.File]::WriteAllText($tempInstaller, $installerContent.Replace($emptyCheck, $emptyInfo))
                Write-Host "[OK] Installer prepared (non-empty directory check removed)" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Installer layout changed upstream; running unpatched" -ForegroundColor Yellow
            }

            Write-Host "[INFO] Installing Scoop core..." -ForegroundColor Gray

            # Check if running as admin and use appropriate installation method
            $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
            $isAdminContext = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

            if ($isAdminContext) {
                # Running as admin - use -RunAsAdmin flag
                Write-Host "[INFO] Installing with admin privileges..." -ForegroundColor Gray
                & $tempInstaller -RunAsAdmin -ScoopDir $ScoopDir -ScoopGlobalDir "$ScoopDir\global" -NoProxy
            } else {
                # Running as normal user
                & $tempInstaller -ScoopDir $ScoopDir -ScoopGlobalDir "$ScoopDir\global" -NoProxy
            }

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
    # Browsers
        'firefox', 'googlechrome',

        # Java JDKs
        'temurin25-jdk',

        # Build tools
        'maven', 'gradle', 'ant', 'cmake', 'make', 'ninja', 'kotlin',

        # Documentation
        'graphviz', 'doxygen', 'pandoc', 'ghostscript',

        # C++ package manager
        'vcpkg',

        # Programming languages
        'python314', 'perl', 'nodejs', 'msys2',

        # Version control
        'sliksvn', 'tortoisesvn', 'gh', 'lazygit',

        # Editors & IDEs
        'vscode', 'neovim', 'notepadplusplus', 'jetbrains-toolbox',

        # Terminal
        'windows-terminal',

        # GUI applications
        'winmerge', 'freecommander', 'greenshot', 'everything', 'postman', 'dbeaver',

        # Security tools
        'keepass', 'gnupg', 'openssl',

        # Network tools
        'nmap', 'wireshark',

        # CLI tools
        'jq', 'yq', 'curl', 'openssh', 'putty', 'winscp', 'filezilla', 'ripgrep', 'fd', 'bat', 'jid',
        'btop', 'less', 'sudo', 'wget', 'cacert', 'innounp', 'dark', 'lessmsi',

        # System tools
        'sysinternals', 'mousejiggler',

        # Database tools
        'sqlite', 'mariadb', 'tomcat',

        # Cloud tools
        'azure-cli',

        # Media tools
        'ffmpeg', 'irfanview', 'krita',

        # System libraries
        'vcredist2022', 'systeminformer'

    # NOTE: Docker alternatives (Rancher Desktop, Docker Desktop) are not included
    # Install manually if needed:
    #   - Docker Desktop: https://www.docker.com/products/docker-desktop
    #   - Rancher Desktop: https://rancherdesktop.io
    #   - Podman Desktop: https://podman-desktop.io
    )

    # VC++ 2015-2022 runtime: the vcredist2022 post_install needs elevation.
    # Skip it when the runtime is already present (usual on managed images).
    $vcRuntimeKey = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
    $vcRuntime = Get-ItemProperty $vcRuntimeKey -ErrorAction SilentlyContinue
    if ($vcRuntime -and $vcRuntime.Installed -eq 1) {
        Write-Host "[OK] VC++ runtime already present ($($vcRuntime.Version)), skipping vcredist2022" -ForegroundColor Gray
        $apps = $apps | Where-Object { $_ -ne 'vcredist2022' }
    }

    $failedApps = @()
    foreach ($app in $apps) {
        $appDir = "$ScoopDir\apps\$app\current"
        if (Test-Path $appDir) {
            Write-Host "[OK] Already installed: $app" -ForegroundColor Gray
            continue
        }
        Write-Host "[INFO] Installing $app..." -ForegroundColor Gray
        scoop install $app
        if (Test-Path $appDir) {
            Write-Host "[OK] Installed: $app" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Not installed: $app" -ForegroundColor Red
            $failedApps += $app
        }
    }

    if ($failedApps.Count -gt 0) {
        Write-Host ""
        Write-Host "[WARN] $($failedApps.Count) package(s) failed: $($failedApps -join ', ')" -ForegroundColor Yellow
        Write-Host "       Retry later with: scoop install <name>; remove leftovers with: scoop uninstall <name>" -ForegroundColor Gray
    }

    # ============================================================================
    # STEP 4: POST-INSTALLATION TASKS
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Step 4: Post-installation tasks..." -ForegroundColor White
    Write-Host ""

    # Set default Java version
    Write-Host "[INFO] Setting default Java to Temurin 25..." -ForegroundColor Gray
    scoop reset temurin25-jdk 2>&1 | Out-Null
    Write-Host "[OK] Default Java set to Temurin 25" -ForegroundColor Green

    # VC++ runtime: verify the result of the vcredist2022 post_install (needs elevation)
    $vcRuntime = Get-ItemProperty $vcRuntimeKey -ErrorAction SilentlyContinue
    if ($vcRuntime -and $vcRuntime.Installed -eq 1) {
        Write-Host "[OK] VC++ runtime installed ($($vcRuntime.Version))" -ForegroundColor Green
        $vcredistInstaller = Get-ChildItem "$ScoopDir\apps\vcredist2022\current" -Filter "VC_redist*.exe" -ErrorAction SilentlyContinue
        if ($vcredistInstaller) {
            Remove-Item $vcredistInstaller.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] vcredist2022 installer removed (libraries remain)" -ForegroundColor Gray
        }
    } else {
        Write-Host "[WARN] VC++ runtime not installed (vcredist2022 post_install needs elevation, UAC was denied?)" -ForegroundColor Yellow
        Write-Host "       Run in an Administrator PowerShell:" -ForegroundColor Gray
        Write-Host "       Get-ChildItem C:\usr\cache\vcredist2022* | ForEach-Object { & `$_.FullName /install /quiet /norestart }" -ForegroundColor Gray
        $failedApps += 'vcredist2022 (runtime)'
    }

    # Initialize MSYS2 and install GCC
    if (Test-Path "$ScoopDir\apps\msys2\current") {
        Write-Host "[INFO] Initializing MSYS2 and installing GCC..." -ForegroundColor Gray
        Write-Host "  -> Initializing MSYS2..." -ForegroundColor DarkGray
        Write-Host "     (core update plus GCC download, several minutes)" -ForegroundColor DarkGray

        # msys2.exe is only a launcher: it spawns a terminal and exits at once, so
        # Start-Process -Wait returns before pacman has done anything. Call bash.exe
        # directly instead; that blocks until pacman is finished and streams its output.
        $msysBash = "$ScoopDir\apps\msys2\current\usr\bin\bash.exe"
        $env:MSYSTEM = 'UCRT64'
        $env:CHERE_INVOKING = '1'
        $env:MSYS2_PATH_TYPE = 'minimal'
        try {
            # First login run completes the MSYS2 post-install setup
            & $msysBash -lc 'true' 2>&1 | Out-Null

            # Core update may replace msys2-runtime/pacman and stop; second pass finishes
            foreach ($pass in 1, 2) {
                Write-Host "  -> pacman -Syu, pass $pass" -ForegroundColor DarkGray
                & $msysBash -lc 'pacman -Syu --noconfirm'
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "  [WARN] pacman -Syu pass $pass exited with code $LASTEXITCODE" -ForegroundColor Yellow
                }
            }

            # Package mirrors fail sporadically (HTTP 500 on a single .sig file aborts the
            # whole transaction). Retry a few times; pacman keeps what it already downloaded.
            $gccExe = "$ScoopDir\apps\msys2\current\ucrt64\bin\gcc.exe"
            foreach ($attempt in 1, 2, 3) {
                Write-Host "  -> pacman -S mingw-w64-ucrt-x86_64-gcc, attempt $attempt" -ForegroundColor DarkGray
                & $msysBash -lc 'pacman -S --noconfirm --needed mingw-w64-ucrt-x86_64-gcc'
                if ($LASTEXITCODE -eq 0 -and (Test-Path $gccExe)) { break }
                Write-Host "  [WARN] pacman -S exited with code $LASTEXITCODE" -ForegroundColor Yellow
                if ($attempt -lt 3) { Start-Sleep -Seconds 10 }
            }
        } finally {
            Remove-Item Env:MSYSTEM, Env:CHERE_INVOKING, Env:MSYS2_PATH_TYPE -ErrorAction SilentlyContinue
        }

        # Verify installation (CRITICAL: Check ucrt64, NOT mingw64!)
        $gccPath = "$ScoopDir\apps\msys2\current\ucrt64\bin\gcc.exe"
        if (Test-Path $gccPath) {
            Write-Host "[OK] MSYS2 GCC (UCRT64) installed successfully!" -ForegroundColor Green
            Write-Host "     GCC location: $gccPath" -ForegroundColor DarkGray

            # Smoke test: compile and run a one-line program. Two known failure modes on
            # managed machines, each with its own message:
            #  - cc1.exe exits with -1073741511 (STATUS_ENTRYPOINT_NOT_FOUND) when another
            #    directory earlier in PATH ships older libstdc++/libgcc DLLs
            #  - the built exe is refused by endpoint security (ASR rule 01443614, "Block
            #    executable files unless they meet a prevalence, age, or trusted list criterion")
            $ccTestDir = "$ScoopDir\cache\scoop-boot-cctest"
            New-Item -ItemType Directory -Path $ccTestDir -Force | Out-Null
            $ccTestSrc = "$ccTestDir\hello.c"
            $ccTestExe = "$ccTestDir\hello.exe"
            Set-Content -Path $ccTestSrc -Value 'int main(void){return 42;}' -Encoding ASCII
            Remove-Item $ccTestExe -Force -ErrorAction SilentlyContinue
            $savedPath = $env:Path
            $env:Path = "$ScoopDir\apps\msys2\current\ucrt64\bin;$env:Path"
            & $gccPath $ccTestSrc -o $ccTestExe 2>&1 | Out-Null
            $ccExit = $LASTEXITCODE
            $env:Path = $savedPath
            if (-not (Test-Path $ccTestExe)) {
                Write-Host "[WARN] GCC is installed but cannot compile (gcc exit code $ccExit)" -ForegroundColor Yellow
                if ($ccExit -eq -1073741511) {
                    Write-Host "       cc1.exe: STATUS_ENTRYPOINT_NOT_FOUND. A directory earlier in PATH ships older" -ForegroundColor Gray
                    Write-Host "       libstdc++/libgcc DLLs. Check: where.exe libstdc++-6.dll" -ForegroundColor Gray
                }
                $failedApps += 'gcc (compile test)'
            } else {
                $runOk = $false
                try {
                    & $ccTestExe 2>&1 | Out-Null
                    $runOk = ($LASTEXITCODE -eq 42)
                } catch { }
                if ($runOk) {
                    Write-Host "[OK] GCC compile-and-run test passed" -ForegroundColor Green
                } else {
                    Write-Host "[WARN] GCC compiled the test program, but Windows refused to run it." -ForegroundColor Yellow
                    Write-Host "       Endpoint security (Defender ASR rule 01443614) blocks locally built" -ForegroundColor Gray
                    Write-Host "       executables on this machine. Check the Defender log for event 1121:" -ForegroundColor Gray
                    Write-Host "       Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Windows Defender/Operational'; Id=1121}" -ForegroundColor Gray
                    $failedApps += 'gcc (running built exe blocked by ASR)'
                }
            }
            Remove-Item $ccTestDir -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "[WARN] GCC installation failed (gcc.exe not found in ucrt64)" -ForegroundColor Yellow
            $failedApps += 'msys2 gcc (ucrt64)'
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

    # netcat aliases: the netcat package is blocked by Windows Defender (PUA), so nc and
    # netcat point to ncat from nmap. "scoop shim add" re-adds shims to the User PATH,
    # which Step 7 cleans up again; that is why this runs before Step 7.
    $ncat = "$ScoopDir\apps\nmap\current\ncat.exe"
    if (Test-Path $ncat) {
        foreach ($alias in @('nc', 'netcat')) {
            if (Test-Path "$ScoopDir\shims\$alias.exe") {
                Write-Host "[OK] Shim already present: $alias -> ncat" -ForegroundColor Gray
            } else {
                scoop shim add $alias $ncat 2>&1 | Out-Null
                if (Test-Path "$ScoopDir\shims\$alias.exe") {
                    Write-Host "[OK] Shim created: $alias -> ncat" -ForegroundColor Green
                } else {
                    Write-Host "[WARN] Could not create shim $alias (scoop shim add $alias $ncat)" -ForegroundColor Yellow
                }
            }
        }
    } else {
        Write-Host "[WARN] nmap not found, skipping nc/netcat shims" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host ">>> Step 5: Registry imports..." -ForegroundColor White
    Write-Host ""

    $regFiles = @(
        @{App='7zip'; File='install-context.reg'},
        @{App='notepadplusplus'; File='install-context.reg'},
        @{App='vscode'; File='install-context.reg'},
        @{App='git'; File='install-context.reg'},
        @{App='python314'; File='install-pep-514.reg'}
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
        } else {
            Write-Host "[OK] Already running: JetBrains Toolbox" -ForegroundColor Gray
        }
    }

    $greenshotPath = "$ScoopDir\apps\greenshot\current\Greenshot.exe"
    if (Test-Path $greenshotPath) {
        $greenshotRunning = Get-Process -Name "Greenshot" -ErrorAction SilentlyContinue
        if (-not $greenshotRunning) {
            Start-Process -FilePath $greenshotPath -ErrorAction SilentlyContinue
            Write-Host "[OK] Started: Greenshot" -ForegroundColor Green
        } else {
            Write-Host "[OK] Already running: Greenshot" -ForegroundColor Gray
        }
    }

    # ============================================================================
    # STEP 7: CLEAN USER SCOPE
    # Scoop wrote JAVA_HOME, GRADLE_USER_HOME, ... and PATH entries into the User
    # scope during Step 3; User values override the Machine values from the .env
    # file. scoop-boot.ps1 --clean-user-scope removes them and applies user.* files.
    # ============================================================================
    Write-Host ""
    Write-Host ">>> Step 7: Cleaning User scope (Scoop overrides, user.* files)..." -ForegroundColor White
    Write-Host ""
    & "$ScoopDir\bin\scoop-boot.ps1" --clean-user-scope

    Write-Host ""
    if ($failedApps.Count -gt 0) {
        Write-Host "=== Installation Complete with $($failedApps.Count) failure(s) ===" -ForegroundColor Yellow
        Write-Host "Failed: $($failedApps -join ', ')" -ForegroundColor Yellow
    } else {
        Write-Host "=== Installation Complete! ===" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "IMPORTANT: Restart your shell!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Verify:" -ForegroundColor Cyan
    Write-Host "  java -version    # Should show openjdk 25.x" -ForegroundColor Gray
    Write-Host "  python --version # Should show Python 3.14.x" -ForegroundColor Gray
    Write-Host "  gcc --version    # Should show GCC from MSYS2/UCRT64" -ForegroundColor Gray
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
