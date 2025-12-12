# Scoop-Boot Complete Setup Guide

## Table of Contents
1. [Environment Configuration (.env Files)](#environment-configuration)
2. [Scoop Core Features](#scoop-core-features)
3. [Directory Structure](#directory-structure)
4. [Version Management & Pinning](#version-management)
5. [Buckets Explained](#buckets-explained)
6. [Complete Workflow Examples](#complete-workflow-examples)

---

## Environment Configuration

### File Hierarchy & Load Order
```
C:\usr\etc\environments\
├── system.default.env              # 1. Machine scope (needs admin)
├── system.HOSTNAME.USERNAME.env    # 2. Machine scope override
├── user.default.env                # 3. User scope (recommended)
└── user.HOSTNAME.USERNAME.env      # 4. User scope override (highest priority)
```

### Environment File Syntax with CORRECT Paths

```ini
# ============================================================================
# VARIABLE OPERATIONS
# ============================================================================

# Set variable (use $SCOOP for portability)
JAVA_HOME=$SCOOP\apps\temurin21-jdk\current
PYTHON_HOME=$SCOOP\apps\python313\current
MAVEN_HOME=$SCOOP\apps\maven\current

# Prepend to PATH (highest priority - added at beginning)
PATH+=$SCOOP\apps\temurin21-jdk\current\bin
PATH+=$SCOOP\apps\python313\current
PATH+=$SCOOP\apps\python313\current\Scripts

# Append to PATH (lowest priority - added at end)
PATH=+$SCOOP\persist\nodejs\bin
PATH=+$USERPROFILE\tools

# Remove from PATH (exact match required)
PATH-=C:\old\java\installation
PATH-=$SCOOP\apps\python312\current

# Delete variable completely
-OLD_JAVA_HOME
-DEPRECATED_VAR

# ============================================================================
# LIST OPERATIONS FOR ALL VARIABLES
# ============================================================================

# Works with ANY semicolon-separated list variable:

# PERL5LIB (Perl libraries)
PERL5LIB+=$SCOOP\apps\perl\current\perl\lib        # Prepend
PERL5LIB+=$SCOOP\apps\perl\current\perl\site\lib
PERL5LIB=+$USERPROFILE\perl5\lib                   # Append

# PYTHONPATH (Python modules)
PYTHONPATH+=$SCOOP\apps\python313\current\Lib\site-packages  # Prepend
PYTHONPATH=+$USERPROFILE\python\libs                         # Append
PYTHONPATH-=$SCOOP\apps\python312\current\Lib\site-packages  # Remove old

# CLASSPATH (Java classes)
CLASSPATH+=$JAVA_HOME\lib\tools.jar               # Prepend
CLASSPATH=+$USERPROFILE\.m2\repository            # Append
CLASSPATH-=C:\old\libs\outdated.jar               # Remove

# PSModulePath (PowerShell modules)
PSModulePath+=$SCOOP\modules                      # Prepend
PSModulePath=+$USERPROFILE\Documents\PowerShell\Modules  # Append

# NODE_PATH (Node.js modules)
NODE_PATH+=$SCOOP\apps\nodejs\current\node_modules
NODE_PATH=+$SCOOP\persist\nodejs\node_modules

# ============================================================================
# REAL-WORLD EXAMPLE: Complete Java Development Setup
# ============================================================================

# Java JDK 21 LTS
JAVA_HOME=$SCOOP\apps\temurin21-jdk\current
PATH+=$JAVA_HOME\bin
JAVA_OPTS=-Xmx2g -Xms512m -XX:+UseG1GC

# Maven
MAVEN_HOME=$SCOOP\apps\maven\current
PATH+=$MAVEN_HOME\bin
M2_HOME=$MAVEN_HOME
M2_REPO=$USERPROFILE\.m2\repository

# Gradle
GRADLE_HOME=$SCOOP\apps\gradle\current
PATH+=$GRADLE_HOME\bin
GRADLE_USER_HOME=$USERPROFILE\.gradle

# ============================================================================
# MSYS2/UCRT64 - CRITICAL: Use ucrt64 for GCC 15.2.0!
# ============================================================================

# Remove old/wrong mingw64 paths
PATH-=$SCOOP\apps\msys2\current\mingw64\bin

# Add correct UCRT64 paths
MSYS2_HOME=$SCOOP\apps\msys2\current
PATH+=$MSYS2_HOME\ucrt64\bin     # GCC 15.2.0 is here!
PATH+=$MSYS2_HOME\usr\bin        # Unix tools
```

---

## Scoop Core Features

### 1. Basic Commands

```powershell
# Search for packages
scoop search python

# Install applications
scoop install python nodejs git

# Update Scoop itself
scoop update

# Update all installed apps
scoop update *

# Update specific app
scoop update python

# Show installed apps
scoop list

# Show outdated apps
scoop status

# Uninstall app
scoop uninstall nodejs

# Clean old versions
scoop cleanup *

# Show app info
scoop info python
```

### 2. Version Management

```powershell
# Install specific version
scoop install python@3.13.0

# List available versions
scoop bucket add versions  # Need versions bucket first
scoop search python

# Switch between versions
scoop reset python313
scoop reset python312

# Hold/Unhold updates
scoop hold python          # Prevent updates
scoop unhold python        # Allow updates again
```

### 3. Version Pinning - Python 3.13 Example

```powershell
# Method 1: Install specific version and hold
scoop install python313
scoop hold python313

# Method 2: Install from versions bucket
scoop bucket add versions
scoop install python@3.13.0
scoop hold python

# Method 3: Reset to specific version after update
scoop update python        # Updates to latest
scoop reset python313      # Switch back to 3.13

# Check current version and hold status
scoop list python
# Output shows:
# python313 3.13.1 [held]  # Won't be updated

# Later, to allow updates again
scoop unhold python313
```

### 4. Cache Management

```powershell
# Show cache location and size
scoop cache show

# Show specific app cache
scoop cache show python

# Remove all cache
scoop cache rm *

# Remove specific app cache
scoop cache rm python

# Cache location
# C:\usr\cache\
```

### 5. Configuration

```powershell
# Show current configuration
scoop config

# Disable aria2 warning
scoop config aria2-warning-enabled false

# Set max aria2 connections (faster downloads)
scoop config aria2-max-connection-per-server 16
scoop config aria2-min-split-size 1M

# Use proxy
scoop config proxy proxy.company.com:8080

# Reset to defaults
scoop config rm proxy
```

### 6. Cleanup & Maintenance

```powershell
# Remove old versions but keep current
scoop cleanup *

# Remove old versions AND cache
scoop cleanup * --cache

# Check for problems
scoop checkup

# Verify app integrity
scoop verify *
```

---

## Directory Structure

### Complete C:\usr Layout

```
C:\usr\                            # $SCOOP root
│
├── apps\                          # Installed applications
│   ├── python313\
│   │   ├── current\              # Symlink to active version
│   │   ├── 3.13.0\              # Version 1
│   │   └── 3.13.1\              # Version 2 (current points here)
│   ├── nodejs\
│   │   ├── current\
│   │   └── 25.0.0\
│   └── git\
│       ├── current\
│       └── 2.51.0\
│
├── buckets\                       # Bucket repositories (JSON manifests)
│   ├── main\                     # Official Scoop bucket
│   │   └── bucket\
│   │       ├── git.json
│   │       ├── python.json
│   │       └── ...
│   ├── extras\                   # Community extras
│   ├── java\                     # Java-specific apps
│   └── versions\                 # Alternative versions
│
├── cache\                         # Downloaded installers (reusable)
│   ├── python#3.13.1#x64.zip
│   ├── nodejs#25.0.0#x64.msi
│   └── git#2.51.0#x64.exe
│
├── persist\                       # Persistent app data (survives updates)
│   ├── nodejs\
│   │   ├── bin\
│   │   └── node_modules\
│   ├── vscode\
│   │   └── data\
│   └── maven\
│       └── .m2\
│
├── shims\                         # Command shims (added to PATH)
│   ├── python.exe               # Points to current python
│   ├── python.shim              # Configuration file
│   ├── pip.exe
│   ├── node.exe
│   ├── npm.exe
│   └── git.exe
│
├── bin\                          # User scripts (scoop-boot location)
│   ├── scoop-boot.ps1
│   ├── scoop-complete-install.ps1
│   └── scoop-complete-reset.ps1
│
└── etc\                          # Configuration
    └── environments\            # Environment .env files
        ├── user.default.env
        └── backups\
```

### Important Directories Explained

#### apps/
- Each app has versioned subdirectories
- `current` is a junction (symlink) to active version
- Multiple versions can coexist
- `scoop reset` changes the `current` link

#### shims/
- Small executables that redirect to actual apps
- Automatically added to PATH (just one entry: C:\usr\shims)
- Updates automatically when switching versions
- Eliminates PATH pollution

#### persist/
- Data that should survive app updates
- Configs, databases, user files
- Linked into app directories during installation
- Backed up during `scoop-complete-reset.ps1`

#### cache/
- Downloaded installers kept for reinstallation
- Speeds up reinstalls significantly
- Can be safely deleted to save space
- Shared across versions

---

## Buckets Explained

### What are Buckets?
Buckets are Git repositories containing JSON manifests that describe how to install applications.

### Main Buckets

```powershell
# Official bucket (default)
scoop bucket add main
# Contains: git, python, nodejs, curl, wget, etc.

# Extras bucket (GUI apps & more)
scoop bucket add extras  
# Contains: vscode, notepad++, firefox, chrome, putty, etc.

# Java bucket (JDKs and Java tools)
scoop bucket add java
# Contains: openjdk, temurin, oracle-jdk, maven, gradle, etc.

# Versions bucket (alternative versions)
scoop bucket add versions
# Contains: python27, python38, nodejs14, php72, etc.

# Games bucket
scoop bucket add games
# Contains: minecraft, steam, epic-games-launcher, etc.

# Nerd Fonts bucket
scoop bucket add nerd-fonts
# Contains: FiraCode-NF, JetBrainsMono-NF, etc.
```

### Bucket Management

```powershell
# List installed buckets
scoop bucket list

# Show known buckets
scoop bucket known

# Add bucket
scoop bucket add extras

# Add custom bucket
scoop bucket add my-bucket https://github.com/user/my-bucket

# Remove bucket
scoop bucket rm extras

# Update all buckets
scoop update
```

### Bucket Structure Example

```json
// File: buckets/main/bucket/python.json
{
    "version": "3.13.1",
    "homepage": "https://www.python.org/",
    "license": "Python-2.0",
    "architecture": {
        "64bit": {
            "url": "https://www.python.org/ftp/python/3.13.1/python-3.13.1-amd64.exe",
            "hash": "sha256:..."
        }
    },
    "installer": {
        "args": [
            "/quiet",
            "InstallAllUsers=0",
            "TargetDir=$dir"
        ]
    },
    "persist": [
        "Scripts",
        "Lib\\site-packages"
    ],
    "bin": [
        "python.exe",
        "Scripts\\pip.exe"
    ],
    "checkver": {
        "url": "https://www.python.org/downloads/",
        "regex": "Python (3\\.[\\d.]+)"
    }
}
```

---

## Complete Workflow Examples

### Example 1: Fresh Development Setup

```powershell
# 1. Bootstrap Scoop
C:\usr\bin\scoop-boot.ps1 --bootstrap

# 2. Create environment configuration
scoop-boot.ps1 --init-env=user.default.env

# 3. Edit configuration (add your settings)
notepad C:\usr\etc\environments\user.default.env

# 4. Apply configuration
scoop-boot.ps1 --apply-env

# 5. Install development stack
scoop bucket add java
scoop bucket add versions
scoop install python313 nodejs openjdk21 maven gradle vscode

# 6. Pin Python to 3.13
scoop hold python313

# 7. Verify
python --version  # Python 3.13.x
java -version     # OpenJDK 21
node --version    # Node.js 25.x
```

### Example 2: Update Management

```powershell
# Check what needs updating
scoop status

# Update everything EXCEPT held packages
scoop update *

# Update specific app (even if held)
scoop unhold python313
scoop update python313
scoop hold python313

# Clean old versions
scoop cleanup *
```

### Example 3: Multiple Python Versions

```powershell
# Install multiple versions
scoop install python313
scoop install python312
scoop install python311

# Switch between them
scoop reset python313  # Use 3.13
python --version       # 3.13.x

scoop reset python312  # Use 3.12
python --version       # 3.12.x

# Create aliases for specific versions
scoop alias add py313 'scoop reset python313'
scoop alias add py312 'scoop reset python312'

# Now switch with:
scoop py313
scoop py312
```

### Example 4: Complete Reset and Reinstall

```powershell
# 1. Backup current setup
scoop export > scoop-apps.json

# 2. Complete reset
.\scoop-complete-reset.ps1 -KeepPersist

# 3. Reinstall from backup
.\scoop-boot.ps1 --bootstrap
scoop import scoop-apps.json
```

### Example 5: Troubleshooting

```powershell
# Check for issues
scoop checkup

# Fix shims
scoop reset *

# Verify installations
scoop verify *

# Check specific app
scoop which python

# Show app dependencies
scoop depends python

# Reinstall problematic app
scoop uninstall python --purge
scoop install python313
```

---

## Pro Tips

### 1. Use persist for important data
```powershell
# Data in persist/ survives updates
# Example: VS Code settings
# C:\usr\persist\vscode\data\user-data\User\settings.json
```

### 2. Speed up downloads
```powershell
# Use aria2 for parallel downloads (5x faster)
scoop install aria2
scoop config aria2-max-connection-per-server 16
```

### 3. Save disk space
```powershell
# Regular cleanup
scoop cleanup * --cache

# Check space usage
Get-ChildItem C:\usr -Recurse | Measure-Object -Property Length -Sum
```

### 4. Create custom aliases
```powershell
# Create shortcuts
scoop alias add upgrade 'scoop update *; scoop cleanup *'
scoop alias add backup 'scoop export > scoop-backup-$(Get-Date -Format "yyyyMMdd").json'

# Use them
scoop upgrade
scoop backup
```

### 5. Environment variable best practices
```powershell
# Always use $SCOOP instead of hardcoded paths
# Good: PATH+=$SCOOP\apps\python313\current
# Bad:  PATH+=C:\usr\apps\python313\current

# Test changes first
scoop-boot.ps1 --apply-env --dry-run
```

---

## Common Issues & Solutions

### Python pip not working after update
```powershell
# Reinstall pip
python -m ensurepip --upgrade
python -m pip install --upgrade pip
```

### Git credentials lost after update
```powershell
# Credentials are in persist
# Check: C:\usr\persist\git\.gitconfig
git config --global credential.helper manager
```

### PATH too long error
```powershell
# Use shims instead of adding each app to PATH
# Scoop automatically uses C:\usr\shims
```

### App won't update (held)
```powershell
scoop unhold appname
scoop update appname
scoop hold appname  # Optional: hold again
```

### Wrong GCC version (mingw64 vs ucrt64)
```powershell
# Check which GCC
where gcc
# Should be: C:\usr\apps\msys2\current\ucrt64\bin\gcc.exe
# NOT: C:\usr\apps\msys2\current\mingw64\bin\gcc.exe
```

---

## Summary

The scoop-boot system provides:
1. **Automated setup** via PowerShell scripts
2. **Environment management** through .env files with flexible syntax
3. **Version management** with pinning and holding
4. **Clean directory structure** with shims preventing PATH pollution
5. **Bucket system** for organized package repositories
6. **Persistent data** surviving updates
7. **Complete automation** including GCC installation via MSYS2/UCRT64

Key directories:
- `C:\usr\apps\` - Applications with version subdirectories
- `C:\usr\shims\` - Command redirectors (single PATH entry)
- `C:\usr\persist\` - Persistent app data
- `C:\usr\cache\` - Downloaded installers
- `C:\usr\buckets\` - Package manifests
- `C:\usr\etc\environments\` - Environment configuration files

---
[Main](README.md)
---
