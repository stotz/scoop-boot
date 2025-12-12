# Complete Analysis: Scoop-Boot Scripts Documentation

## Overview
Three PowerShell scripts for Windows development environment management using Scoop package manager:

1. **scoop-boot.ps1** - Core bootstrap and environment management (v1.10.0)
2. **scoop-complete-install.ps1** - Complete installation with 50+ tools (v2.7.1)
3. **scoop-complete-reset.ps1** - Safe cleanup and reset (v2.1.0)

---

## 1. scoop-boot.ps1 (Core Bootstrap)

### Version: 1.10.0
### Lines of Code: 1157

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
JAVA_HOME=$SCOOP\apps\temurin21-jdk\current

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

### Version: 2.7.1
### Lines of Code: 856
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
- temurin8-jdk, temurin11-jdk, temurin17-jdk, temurin21-jdk, temurin23-jdk

**Build Tools:**
- maven, gradle, ant, cmake, make, ninja, kotlin

**Programming Languages:**
- python313, perl, nodejs, msys2

**Version Control:**
- tortoisesvn, gh, lazygit (git already from bootstrap)

**Editors & IDEs:**
- vscode, neovim, notepadplusplus, jetbrains-toolbox

**GUI Applications:**
- windows-terminal, hxd, winmerge, freecommander
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
# The script AUTOMATICALLY does:
1. Initializes MSYS2
2. Runs: pacman -Syu --noconfirm
3. Runs: pacman -S mingw-w64-ucrt-x86_64-gcc --noconfirm
4. Verifies GCC at: C:\usr\apps\msys2\current\ucrt64\bin\gcc.exe

# NO MANUAL STEPS REQUIRED!
# If automatic installation fails, script shows manual steps
```

**Other Post-Installation:**
- Sets Java 21 as default (`scoop reset temurin21-jdk`)
- Cleans up VC++ installer files
- **AUTOMATICALLY installs GCC 15.2.0 via MSYS2/UCRT64**

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

### Version: 2.1.0
### Lines of Code: 408

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
- mousejiggler
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
# CORRECT - GCC 15.2.0 location
MSYS2_HOME=$SCOOP\apps\msys2\current
PATH+=$MSYS2_HOME\ucrt64\bin    # GCC 15.2.0 is HERE!
PATH+=$MSYS2_HOME\usr\bin       # Unix tools

# WRONG - Old/legacy
# PATH+=$MSYS2_HOME\mingw64\bin  # DO NOT USE!
```

**Why UCRT64:**
- Modern GCC 15.2.0
- Universal C Runtime (Windows 10/11 standard)
- Better compatibility

**The installation script handles this AUTOMATICALLY!**

---

## Complete Workflow

### Initial Setup:
```powershell
# 1. Download scripts
New-Item -ItemType Directory -Path C:\usr\bin -Force
Invoke-WebRequest -Uri https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1 -OutFile C:\usr\bin\scoop-boot.ps1
Invoke-WebRequest -Uri https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-complete-install.ps1 -OutFile C:\usr\bin\scoop-complete-install.ps1

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
java -version    # Should show: openjdk 21.0.x

# Python
python --version # Should show: Python 3.13.x

# GCC (AUTOMATICALLY INSTALLED!)
gcc --version    # Should show: gcc.exe (Rev8, Built by MSYS2 project) 15.2.0

# Node.js
node --version   # Should show: v25.x.x

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

- **Author:** System Administrator
- **License:** MIT
- **Repository:** https://github.com/stotz/scoop-boot
