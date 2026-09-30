# scoop-boot

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](bin/)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-lightgrey.svg)](#support-matrix)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](#author--license)

Three PowerShell scripts that set up, configure and tear down a Windows development environment based on the [Scoop](https://scoop.sh) package manager. Everything lives under `C:\usr`.

| Script                             | Version | Purpose                                              |
|------------------------------------|---------|------------------------------------------------------|
| `bin/scoop-boot.ps1`               | 1.11.1  | Bootstrap Scoop, manage environment variables (.env) |
| `bin/scoop-complete-install.ps1`   | 2.7.11  | Two-phase installation of the full tool set          |
| `bin/scoop-complete-reset.ps1`     | 2.3.1   | Remove everything again (processes, files, registry) |

---

## Quick Setup

From a fresh Windows machine (for example an Azure Virtual Desktop) to a working environment. All commands are PowerShell.

### 0. Prerequisites

- Windows display language: **English (United States)**.
  Settings > Time & Language > Language & region > Windows display language.
  Error messages in English are searchable; localized ones are not.
- Administrator rights for phase 1. Phase 2 runs as a normal user.
- Internet access to `github.com`, `raw.githubusercontent.com` and the download hosts of the Scoop manifests.

### 1. Directories, scripts and environment file (PowerShell as Administrator)

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force

New-Item -ItemType Directory -Path C:\usr\bin -Force
New-Item -ItemType Directory -Path C:\usr\etc\environments -Force
New-Item -ItemType Directory -Path C:\tmp -Force
New-Item -ItemType Directory -Path C:\devl -Force    # workspace for repositories, not used by scoop-boot

$base = "https://raw.githubusercontent.com/stotz/scoop-boot/main"
Invoke-WebRequest -Uri "$base/bin/scoop-boot.ps1"             -OutFile C:\usr\bin\scoop-boot.ps1
Invoke-WebRequest -Uri "$base/bin/scoop-complete-install.ps1" -OutFile C:\usr\bin\scoop-complete-install.ps1
Invoke-WebRequest -Uri "$base/bin/scoop-complete-reset.ps1"   -OutFile C:\usr\bin\scoop-complete-reset.ps1

# Machine-scope environment file, named after this host and user (lowercase)
$envFile = "C:\usr\etc\environments\system.$($env:COMPUTERNAME.ToLower()).$($env:USERNAME.ToLower()).env"
Invoke-WebRequest -Uri "$base/etc/environments/system.hostname.username.env" -OutFile $envFile

# Optional: review paths and tool versions before applying
# (notepad.exe with extension: on managed machines a bare 'notepad' may resolve to a
#  blocked Store alias and open a "Select an app" dialog instead)
notepad.exe $envFile
```

Notes:

- `$env:USERNAME` is the account running this shell. If you run PowerShell as a separate admin account ("run as"), replace it with your regular user name.
- The file name must start with `system.` (Machine scope) or `user.` (User scope). Other names are rejected by phase 1.

### 2. Phase 1: environment (PowerShell as Administrator)

```powershell
C:\usr\bin\scoop-complete-install.ps1 -SetEnvironment
```

Sets `TMP`/`TEMP` to `C:\tmp`, then applies the `.env` file(s) from `C:\usr\etc\environments` at Machine scope.

### 3. Phase 2: tools (new PowerShell window, normal user)

```powershell
C:\usr\bin\scoop-complete-install.ps1 -InstallTools
```

Bootstraps Scoop, adds the `extras`, `java` and `versions` buckets, installs the tool set (JDK 25, Python 3.14, Node.js, Kotlin, Maven, Gradle, MSYS2/GCC, editors, CLI tools), imports registry files and cleans up duplicate User-scope PATH entries. Takes 15-30 minutes.

### 4. Verify (new shell)

```powershell
scoop --version
java -version      # openjdk 25.x
python --version   # Python 3.14.x
gcc --version      # gcc.exe (Built by MSYS2 project)
node --version     # v26.x
scoop-boot.ps1 --env-status
```

### Start over

```powershell
C:\usr\bin\scoop-complete-reset.ps1          # full cleanup, asks for confirmation
C:\usr\bin\scoop-complete-reset.ps1 -Force   # no prompts
```

---

## Documents

Overview and concepts:

- [Scoop Boot Complete Guide](scoop-boot-complete-guide.md) - environment file syntax, version pinning, bucket handling

Operations and security:

- [Scoop Security Enterprise Guide](scoop-security-enterprise-guide.md) - manifest verification, private buckets, hash checks
- [Scoop Security Scanning with GitHub Actions CI/CD](scoop-security-github-actions.md) - automated scanning of manifests

AI workflow (working documents for AI-assisted development):

- [docs/AI_Instruktion.md](docs/AI_Instruktion.md) - workflow rules between developer and AI (German)
- [docs/AI_TODO.md](docs/AI_TODO.md) - AI working state, decisions and version history (German)

---

## Reference

The sections below describe each script in detail.

## 1. scoop-boot.ps1 (Core Bootstrap)

### Version: 1.11.1
### Lines of Code:
| lines | program                        |
|------:|:-------------------------------|
|  1621 | bin/scoop-boot.ps1             |
|  1039 | bin/scoop-complete-install.ps1 |
|   557 | bin/scoop-complete-reset.ps1   |

### Primary Functions:
- **Bootstrap Scoop** with essential tools
- **Environment variable management** via .env files
- **Application installation** via Scoop
- **Self-testing** with 30 comprehensive tests

### Key Commands:
```powershell
--bootstrap        # Install Scoop + Git + 7zip + aria2 + essential tools
--init-env=FILE    # Create environment configuration file
--apply-env        # Apply environment configuration
--dry-run          # Preview changes without applying
--install APP...   # Install applications
--selfTest         # Run 30 self-tests
--status           # Show current environment status
--env-status       # Show environment files and hierarchy
--environment      # Display current environment variables
--suggest          # Show suggested applications
--rollback         # Rollback to previous configuration
```

### Environment File System:
```
Load Order (later overrides earlier):
1. system.default.env              # Machine scope (needs admin)
2. system.HOSTNAME.USERNAME.env    # Machine scope (needs admin)
3. user.default.env                # User scope (RECOMMENDED)
4. user.HOSTNAME.USERNAME.env      # User scope (highest priority)
```

### Environment File Syntax:
```ini
# Set variable
JAVA_HOME=$SCOOP\apps\temurin25-jdk\current

# Prepend to PATH (highest priority)
PATH+=$JAVA_HOME\bin

# Append to PATH (lowest priority)  
PATH=+$SCOOP\tools

# Remove from PATH
PATH-=C:\old\path

# Delete variable
-OLD_VAR

# List operations work for ALL variables (not just PATH)
PERL5LIB+=C:\perl\lib      # Prepend
PYTHONPATH=+C:\python\lib  # Append
CLASSPATH-=old.jar         # Remove
```

### What Bootstrap Installs:
1. **Scoop Core** to C:\usr
2. **Git** (required for buckets)
3. **7zip** (archive extraction)
4. **aria2** (5x faster downloads)
5. **sudo** (admin operations)
6. **innounp, dark, lessmsi** (additional extractors)
7. **wget, cacert** (alternative downloaders)
8. **Buckets:** main, extras

### Self-Test Coverage (30 tests):
- PowerShell version (>= 5.1)
- Execution policy
- Parameter parsing
- Admin rights detection
- Directory paths
- Hostname/username detection
- PATH manipulation (+=, =+, -=)
- Variable assignment/expansion
- Comment/empty line handling
- Environment file processing
- Scope detection
- Mock environment application
- List operations for all variables

---

## 2. scoop-complete-install.ps1 (Complete Installation)

### Version: 2.7.11
### Lines of Code: see table above
### Two-Phase Installation: Admin + User

### Phase 1: Environment Setup (-SetEnvironment)
**MUST RUN AS ADMINISTRATOR**

What it does:
1. Downloads scoop-boot.ps1 if not present
2. Applies environment configuration from .env files
3. Sets Machine-scope environment variables

### Phase 2: Tool Installation (-InstallTools)
**CAN RUN AS NORMAL USER OR ADMIN**

What it does:

#### Step 1: Bootstrap Scoop
- Uses scoop-boot.ps1 --bootstrap if available
- **FALLBACK:** Manual bootstrap if scoop-boot fails
  - Sets SCOOP environment variables
  - Fixes TEMP/TMP paths to prevent .cs compilation errors
  - Downloads official Scoop installer
  - Installs essential tools (7zip, git, aria2)
  - Adds main and extras buckets

#### Step 2: Add Additional Buckets
- java (for JDK versions)
- versions (for specific app versions)

#### Step 3: Install Development Tools (50+ packages)

**Java Development:**
- temurin25-jdk

**Build Tools:**
- maven, gradle, ant, cmake, make, ninja, kotlin

**Programming Languages:**
- python314, perl, nodejs, msys2

**Version Control:**
- sliksvn, tortoisesvn, gh, lazygit (git already from bootstrap)

**Editors & IDEs:**
- vscode, neovim, notepadplusplus, jetbrains-toolbox

**GUI Applications:**
- windows-terminal, winmerge, freecommander
- greenshot, everything, postman, dbeaver

**CLI Tools:**
- jq, curl, openssh, putty, winscp, filezilla
- ripgrep, fd, bat, jid

**Documentation:**
- graphviz, doxygen

**System Tools:**
- vcredist2022, systeminformer

**Package Manager:**
- vcpkg

#### Step 4: Post-Installation Tasks

**CRITICAL: MSYS2/GCC Installation is AUTOMATIC!**
```powershell
# The script AUTOMATICALLY does (via usr\bin\bash.exe -lc, MSYSTEM=UCRT64, blocking):
1. First login run (MSYS2 post-install setup)
2. Runs: pacman -Syu --noconfirm (two passes: core update, then the rest)
3. Runs: pacman -S --needed mingw-w64-ucrt-x86_64-gcc --noconfirm (up to 3 attempts, mirrors fail sporadically)
4. Verifies GCC at: C:\usr\apps\msys2\current\ucrt64\bin\gcc.exe
5. Compiles and runs a one-line test program; distinct warnings for DLL shadowing
   (older libstdc++ earlier in PATH) and for endpoint security refusing the built exe

# NO MANUAL STEPS REQUIRED!
# If automatic installation fails, script shows manual steps

# Also in Step 4:
# - Default Java: scoop reset temurin25-jdk
# - VC++ runtime check (registry), vcredist2022 only if missing
# - Shims nc and netcat -> ncat.exe from nmap (netcat package is blocked by Defender)
# Step 7 removes every User-PATH entry under C:\usr; the Machine PATH from the .env
# file is authoritative (ucrt64\bin is placed above Git and Perl there on purpose)
```

**Other Post-Installation:**
- Sets Java 25 as default (`scoop reset temurin25-jdk`)
- Cleans up VC++ installer files
- **AUTOMATICALLY installs GCC via MSYS2/UCRT64**

#### Step 5: Registry Imports
- 7zip context menu
- Notepad++ context menu
- VS Code context menu
- Git integration
- Python PEP 514 registration

#### Step 6: Start System Tray Apps
- JetBrains Toolbox
- Greenshot

#### Step 7: Cleanup User-Scope Duplicates
- Removes duplicate PATH entries
- Removes duplicate environment variables
- Optimizes Machine vs User scope variables

### Key Features:
- **Automatic fallback** when scoop-boot.ps1 fails
- **Fixes TEMP/TMP** path issues automatically
- **Detects admin context** and adjusts installation
- **FULLY AUTOMATIC GCC installation** - no manual steps!
- **Intelligent PATH cleanup** to avoid duplicates

---

## 3. scoop-complete-reset.ps1 (Safe Cleanup)

### Version: 2.3.1
### Lines of Code: see table above

### Purpose:
Complete cleanup and removal of Scoop installation

### Parameters:
```powershell
-Force        # Skip confirmation prompts
-KeepPersist  # Keep persist directory (app data/settings)
```

### What it does:

#### 1. Stops Running Processes
**AUTOMATICALLY kills system tray apps:**
- greenshot
- jetbrains-toolbox
- everything
- Any process running from C:\usr\apps\*

#### 2. Creates Backup
- User environment variables → user_env_backup.json
- Machine environment variables → machine_env_backup.json
- Location: C:\usr_backup_[timestamp]

#### 3. Cleans Environment Variables
**Removes from User and Machine scope:**
- SCOOP, SCOOP_GLOBAL, SCOOP_CACHE
- JAVA_HOME, JAVA_OPTS
- GRADLE_HOME, GRADLE_USER_HOME, GRADLE_OPTS
- MAVEN_HOME, M2_HOME, M2_REPO, MAVEN_OPTS
- PYTHON_HOME, PYTHONPATH
- PERL_HOME, PERL5LIB
- NODE_HOME, NODE_PATH, NPM_CONFIG_PREFIX
- MSYS2_HOME, MSYS2_ROOT
- And 20+ more...

#### 4. Cleans PATH
- Removes all entries containing C:\usr
- From both User and Machine scope

#### 5. Aggressive Directory Deletion
**Multi-method approach:**
1. Remove file attributes
2. Take ownership if needed
3. Delete junctions first
4. Try PowerShell Remove-Item with UNC paths
5. Try cmd rd /s /q
6. **Restart Explorer if DLLs locked**
7. Try .NET Directory.Delete

**Directories removed:**
- C:\usr\apps (all applications)
- C:\usr\buckets (bucket definitions)
- C:\usr\cache (downloaded files)
- C:\usr\shims (command shims)
- C:\usr\persist (if not using -KeepPersist)

**PRESERVES:**
- C:\usr\bin\ (scripts)
- C:\usr\etc\ (configurations)

#### 6. Registry Cleanup
- Context menu entries
- Shell extensions

#### 7. Remove Shortcuts
- Start Menu entries

### Key Features:
- **No user prompts** for process termination
- **Automatic Explorer restart** for locked DLLs
- **Multiple deletion methods** for stubborn files
- **Preserves bin and etc** directories
- **Complete backup** before deletion

---

## Critical Configuration: MSYS2/UCRT64

### IMPORTANT: Use UCRT64, NOT mingw64!

**In environment files (.env):**
```ini
# CORRECT - GCC location
MSYS2_HOME=$SCOOP\apps\msys2\current
PATH+=$MSYS2_HOME\ucrt64\bin    # GCC is HERE!
PATH+=$MSYS2_HOME\usr\bin       # Unix tools

# WRONG - Old/legacy
# PATH+=$MSYS2_HOME\mingw64\bin  # DO NOT USE!
```

**Why UCRT64:**
- Modern GCC (UCRT64)
- Universal C Runtime (Windows 10/11 standard)
- Better compatibility

**The installation script handles this AUTOMATICALLY!**

---

## Complete Workflow

### Initial Setup:
```powershell
# 1. Download scripts: see "Quick Setup" at the top of this document

# 2. Option A: Basic Bootstrap (just Scoop + essentials)
C:\usr\bin\scoop-boot.ps1 --bootstrap

# 2. Option B: Complete Installation (50+ tools)
# Phase 1 - As Administrator:
C:\usr\bin\scoop-complete-install.ps1 -SetEnvironment

# Phase 2 - As normal user or admin:
C:\usr\bin\scoop-complete-install.ps1 -InstallTools
# THIS AUTOMATICALLY INSTALLS GCC!
```

### Environment Management:
```powershell
# Create configuration
scoop-boot.ps1 --init-env=user.default.env

# Edit configuration
notepad C:\usr\etc\environments\user.default.env

# Apply configuration
scoop-boot.ps1 --apply-env

# Check status
scoop-boot.ps1 --status
scoop-boot.ps1 --env-status
```

### Complete Reset:
```powershell
# Full cleanup
.\scoop-complete-reset.ps1

# Keep application data
.\scoop-complete-reset.ps1 -KeepPersist

# No confirmation prompts
.\scoop-complete-reset.ps1 -Force
```

---

## Verification After Installation

```powershell
# Java
java -version    # Should show: openjdk 25.0.x

# Python
python --version # Should show: Python 3.14.x

# GCC (AUTOMATICALLY INSTALLED!)
gcc --version    # Should show: gcc.exe (Built by MSYS2 project) 15.x or newer

# Node.js
node --version   # Should show: v26.x.x

# Scoop
scoop --version  # Should show Scoop version
```

---

## Important Notes

1. **GCC Installation is FULLY AUTOMATIC** in scoop-complete-install.ps1
2. **No manual MSYS2 commands needed** - the script does everything
3. **Use UCRT64**, not mingw64 for modern GCC
4. **Bootstrap handles Git installation** automatically
5. **Fallback mechanisms** prevent installation failures
6. **PATH cleanup** prevents duplicates and conflicts
7. **System tray apps** are automatically killed during reset

---

## File Locations

- **Scripts:** C:\usr\bin\
- **Environment files:** C:\usr\etc\environments\
- **Applications:** C:\usr\apps\
- **Persistent data:** C:\usr\persist\
- **Download cache:** C:\usr\cache\
- **Command shims:** C:\usr\shims\

---

## Support Matrix

- **Windows:** 10/11, Server 2016+
- **PowerShell:** 5.1 or higher
- **Architecture:** x64
- **Disk Space:** ~10 GB for complete installation
- **Internet:** Required for downloads

---

## Author & License

- **Author:** Urs Stotz
- **License:** MIT
- **Repository:** https://github.com/stotz/scoop-boot

---

---

[Quick Setup](#quick-setup) | [Documents](#documents)

---
