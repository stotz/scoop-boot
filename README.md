# scoop-boot

> 🚀 **Bootstrap script for Scoop package manager and portable Windows development environments**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Scoop](https://img.shields.io/badge/Scoop-Package%20Manager-green.svg)](https://scoop.sh)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-2.8.0-brightgreen.svg)](https://github.com/stotz/scoop-boot/releases)
[![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)](https://www.microsoft.com/windows)

**scoop-boot** is a comprehensive PowerShell toolkit for Windows development environments:
- **`scoop-boot.ps1`** - Core bootstrap and environment management
- **`scoop-complete-install.ps1`** - Automated installation of 80+ development tools
- **`scoop-complete-reset.ps1`** - Safe and complete cleanup with backups

It provides a **portable, reproducible, and robust** way to set up and maintain development workstations.

<img width="800" alt="image" src="https://github.com/user-attachments/assets/890aa034-0182-420f-a5b8-46245fc81f99" />

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [Complete Installation](#complete-installation)
- [Usage](#usage)
  - [Bootstrap Scoop](#bootstrap-scoop)
  - [Environment Management](#environment-management)
  - [Application Installation](#application-installation)
- [Environment Configuration](#environment-configuration)
  - [File Hierarchy](#file-hierarchy)
  - [Syntax Reference](#syntax-reference)
  - [Variable Expansion](#variable-expansion)
  - [MSYS2/UCRT64 Configuration](#msys2ucrt64-configuration)
- [Commands](#commands)
- [Examples](#examples)
- [Self-Testing](#self-testing)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)
- [Contributing](#contributing)
- [License](#license)

## Features

✨ **Core Features**
- 🎯 **One-Command Bootstrap** - Install Scoop and all recommended tools with a single command
- 🔧 **Environment Management** - Hierarchical `.env` files with override mechanism
- 📦 **80+ Technologies** - Pre-configured templates for Java, Python, Node.js, C++, Browsers, and more
- 🧪 **Self-Testing** - 30 comprehensive tests to ensure everything works correctly
- 🔄 **Backup & Rollback** - Automatic backups before environment changes
- 🎨 **Order-Independent Parameters** - Arguments can be specified in any order
- 🚫 **No Admin Required** - User-level installation (admin only for system-wide env vars)
- 💾 **Portable** - Everything in one directory, easily movable or backup-able
- 🛡️ **Robust** - Automatic error recovery and validation
- 🚀 **Complete Installation** - Two-phase installation script for 80+ development tools
- 🗑️ **Complete Reset** - Safe removal script with automatic backups

## What's New in v2.8

🆕 **Recent Improvements:**
- ✅ **Complete Installation Script** - `scoop-complete-install.ps1` for automated 80+ tool setup
- ✅ **Complete Reset Script** - `scoop-complete-reset.ps1` for safe and thorough cleanup
- ✅ **Automatic TMP/TEMP Fix** - Sets C:\tmp automatically to prevent compilation errors
- ✅ **Admin Installation Support** - Detects and uses -RunAsAdmin flag when needed
- ✅ **MSYS2/UCRT64 Support** - Proper GCC 15.2.0 configuration for modern C++ development
- ✅ **Browser Support** - Firefox and Google Chrome installation included
- ✅ **Enhanced Bootstrap** - Better error handling and automatic fallbacks
- ✅ **PATH Cleanup** - Intelligent duplicate removal (Machine vs User scope)
- ✅ **Registry Integration** - Context menu entries for editors and tools
- ✅ **System Tray Apps** - Auto-start for JetBrains Toolbox, Greenshot, etc.

## Requirements

- **Windows 10/11** or Windows Server 2016+
- **PowerShell 5.1** or higher
- **Internet connection** for downloading packages
- **Execution Policy** allowing script execution:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

## Quick Start

```powershell
# 1. Download scoop-boot to your desired location (e.g., C:\usr\bin)
New-Item -ItemType Directory -Path C:\usr\bin -Force
Invoke-WebRequest -Uri https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1 -OutFile C:\usr\bin\scoop-boot.ps1

# 2. Bootstrap Scoop with all recommended tools
C:\usr\bin\scoop-boot.ps1 --bootstrap

# 3. Restart your shell (IMPORTANT - loads new PATH)
exit

# 4. Verify installation
scoop-boot.ps1 --status

# 5. Create environment configuration
scoop-boot.ps1 --init-env=user.default.env

# 6. Apply environment
scoop-boot.ps1 --apply-env
```

**That's it! You now have a complete development environment.** 🎉

## Complete Installation

For a full development environment with 80+ tools, use `scoop-complete-install.ps1`:

### Two-Phase Installation Process

**Phase 1: Set Environment Variables (Run as Administrator)**
```powershell
# Download complete installation script
Invoke-WebRequest -Uri https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-complete-install.ps1 `
                  -OutFile C:\usr\bin\scoop-complete-install.ps1

# Phase 1: Configure environment (Admin required)
.\scoop-complete-install.ps1 -SetEnvironment
```

**Phase 2: Install Tools (Run as Normal User or Admin)**
```powershell
# Close Administrator PowerShell, open normal PowerShell
# Phase 2: Install all tools
.\scoop-complete-install.ps1 -InstallTools
```

### Complete Reset

To completely remove Scoop and all installations, use `scoop-complete-reset.ps1`:

```powershell
# Download reset script
Invoke-WebRequest -Uri https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-complete-reset.ps1 `
                  -OutFile C:\usr\bin\scoop-complete-reset.ps1

# Run complete reset (removes everything)
.\scoop-complete-reset.ps1

# Optional: Keep application data/settings
.\scoop-complete-reset.ps1 -KeepPersist

# Skip confirmation prompts
.\scoop-complete-reset.ps1 -Force
```

**What gets removed:**
- All installed Scoop applications
- All environment variables set by Scoop
- All PATH entries related to Scoop
- Application settings (unless -KeepPersist)
- Scoop itself
- Registry entries and shortcuts

**What is preserved:**
- C:\usr\bin\ directory
- C:\usr\etc\ directory
- Automatic backup in C:\usr_backup_[timestamp]

### What Gets Installed

The complete installation includes 80+ tools:

**Browsers & Internet**
- Firefox, Google Chrome

**Programming Languages**
- Java: Temurin JDK 8, 11, 17, 21, 23
- Python 3.13 with pip
- Node.js 25 with npm
- Perl, MSYS2 (GCC 15.2.0)

**Build Tools**
- Maven, Gradle, Ant, CMake, Make, Ninja
- Kotlin, vcpkg

**Version Control**
- Git, SVN, TortoiseSVN
- GitHub CLI (gh), lazygit

**Editors & IDEs**
- Visual Studio Code, Neovim
- Notepad++, JetBrains Toolbox

**Database Tools**
- SQLite, MariaDB, Tomcat
- DBeaver

**Security Tools**
- KeePass, GnuPG, OpenSSL
- Nmap, Wireshark

**System Tools**
- Sysinternals Suite, Process Hacker
- System Informer, Everything Search
- HxD Hex Editor, WinMerge

**CLI Tools**
- jq, yq, curl, wget, ripgrep, fd, bat
- OpenSSH, PuTTY, WinSCP, FileZilla

**Media & Graphics**
- FFmpeg, IrfanView, Krita

**Cloud Tools**
- Azure CLI

**Development Libraries**
- VC++ Redistributables 2022

### Post-Installation

After installation completes:
- Java 21 is set as default JDK
- GCC 15.2.0 is available via MSYS2/UCRT64
- All PATH entries are optimized
- Registry integrations are applied
- System tray apps are started

## Usage

### Bootstrap Scoop

The `--bootstrap` command installs Scoop and all essential tools:

```powershell
.\scoop-boot.ps1 --bootstrap
```

**What gets installed:**
- ✅ **Scoop Core** - Package manager (installed to C:\usr by default)
- ✅ **Git 2.52+** - Version control and bucket management
- ✅ **7-Zip 25+** - Archive extraction
- ✅ **aria2 1.37+** - Parallel downloads (5x faster)
- ✅ **sudo** - Run commands as administrator
- ✅ **innounp, dark, lessmsi** - Additional extractors
- ✅ **wget, cacert** - Alternative downloaders and certificates
- ✅ **Buckets** - main and extras repositories

### Environment Management

#### Create Environment File

```powershell
# For current user (recommended - no admin needed)
.\scoop-boot.ps1 --init-env=user.default.env

# For specific host/user combination
.\scoop-boot.ps1 --init-env=user.hostname.username.env

# For system-wide (requires Administrator)
.\scoop-boot.ps1 --init-env=system.default.env
```

**Files are created in:** `C:\usr\etc\environments\`

#### Apply Environment

```powershell
# Preview changes (dry run)
.\scoop-boot.ps1 --apply-env --dry-run

# Apply changes
.\scoop-boot.ps1 --apply-env

# Rollback to previous state
.\scoop-boot.ps1 --apply-env --rollback
```

⚠️ **IMPORTANT:** Always restart your shell after applying environment changes!

### Application Installation

```powershell
# Install single application
.\scoop-boot.ps1 --install nodejs

# Install multiple applications
.\scoop-boot.ps1 --install python openjdk maven gradle

# Show suggestions
.\scoop-boot.ps1 --suggest
```

## Environment Configuration

### File Hierarchy

Environment files are loaded in this order (later files override earlier):

1. **`system.default.env`** - System-wide defaults (Machine scope, requires Administrator)
2. **`system.HOSTNAME.USERNAME.env`** - System-specific overrides
3. **`user.default.env`** - User defaults (User scope, **recommended**)
4. **`user.HOSTNAME.USERNAME.env`** - User-specific overrides (highest priority)

### Syntax Reference

```ini
# Variable assignment
JAVA_HOME=$SCOOP\apps\temurin21-jdk\current

# PATH manipulation
PATH+=$JAVA_HOME\bin        # Prepend (high priority)
PATH=+$SCOOP\tools         # Append (low priority)
PATH-=C:\old\path          # Remove from PATH

# Variable deletion
-OLD_VARIABLE

# Variable expansion
$SCOOP                     # Scoop directory
$USERPROFILE              # User profile
$HOSTNAME                 # Machine name
```

### MSYS2/UCRT64 Configuration

**IMPORTANT:** Use UCRT64 for modern GCC compiler:

```ini
# MSYS2/UCRT64 - Modern GCC Compiler
MSYS2_HOME=$SCOOP\apps\msys2\current
PATH+=$MSYS2_HOME\ucrt64\bin    # GCC 15.2.0 is here!
PATH+=$MSYS2_HOME\usr\bin       # Unix tools
```

After MSYS2 installation, install GCC:
```bash
# In UCRT64 terminal (NOT msys2.exe!):
C:\usr\apps\msys2\current\ucrt64.exe
pacman -S mingw-w64-ucrt-x86_64-gcc
```

## Commands

| Command | Description |
|---------|-------------|
| `--bootstrap` | Install Scoop + essential tools |
| `--status` | Show current environment status |
| `--init-env=FILE` | Create environment configuration file |
| `--apply-env` | Apply environment configuration |
| `--dry-run` | Preview changes without applying |
| `--rollback` | Rollback to previous configuration |
| `--env-status` | Show environment files and load order |
| `--environment` | Display current environment variables |
| `--install APP...` | Install applications |
| `--suggest` | Show installation suggestions |
| `--selfTest` | Run comprehensive self-tests |
| `--help` | Display help message |
| `--version` | Show version |

## Troubleshooting

### Common Issues and Solutions

#### "Scoop installation verification failed"

**Solution:** The script has automatic fallback mechanisms. If it still fails:
```powershell
# Manual fix: Set TEMP paths
[Environment]::SetEnvironmentVariable("TMP", "C:\tmp", "Machine")
[Environment]::SetEnvironmentVariable("TEMP", "C:\tmp", "Machine")
New-Item -ItemType Directory -Path "C:\tmp" -Force
```

#### "gcc not found" after installation

**Problem:** PATH points to wrong MSYS2 directory

**Solution:** Ensure your .env file uses UCRT64:
```ini
# Wrong:
PATH+=$MSYS2_HOME\mingw64\bin

# Correct:
PATH+=$MSYS2_HOME\ucrt64\bin
```

#### 7-Zip context menu missing

**Solution:** Register the shell extension manually:
```powershell
regsvr32 "C:\usr\apps\7zip\current\7-zip64.dll"
```

#### Running as Administrator issues

The script automatically detects admin context and uses appropriate flags. Both phases can be run as Administrator if needed.

## Self-Testing

Run comprehensive tests to verify installation:

```powershell
.\scoop-boot.ps1 --selfTest
```

Tests include:
- PowerShell version compatibility
- Parameter parsing
- Environment variable processing
- PATH operations
- Variable expansion
- 30 total tests

## Best Practices

1. **Use User-Level Configuration** - Prefer `user.*.env` over `system.*.env`
2. **Test Before Applying** - Always use `--dry-run` first
3. **Regular Updates** - Run `scoop update *` periodically
4. **Clean Cache** - Use `scoop cache rm *` to free space
5. **Backup Environment** - Keep copies of your .env files

## Contributing

Contributions are welcome! Please:
1. Maintain PowerShell 5.1 compatibility
2. Use ASCII-only output
3. Pass all self-tests
4. Update documentation

## Changelog

### v2.8.0 (2025-01-13)
- ✅ **NEW:** Complete installation script (scoop-complete-install.ps1)
- ✅ **NEW:** Complete reset script (scoop-complete-reset.ps1)
- ✅ **NEW:** Automatic TMP/TEMP configuration
- ✅ **NEW:** Admin installation support with -RunAsAdmin
- ✅ **NEW:** 80+ tools installation package
- ✅ **FIX:** MSYS2 UCRT64 PATH configuration
- ✅ **FIX:** Registry import for context menus
- ✅ **IMPROVED:** Error handling and fallbacks

### v2.1.0 (2025-01-29)
- ✅ MSYS2/UCRT64 support for GCC 15.2.0
- ✅ Enhanced bootstrap with fallbacks
- ✅ PATH cleanup improvements
- ✅ Bootstrap compilation error fixes

## License

MIT License - Copyright (c) 2025 Urs Stotz

## Links

- 🏠 **Repository:** [https://github.com/stotz/scoop-boot](https://github.com/stotz/scoop-boot)
- 🐛 **Issues:** [https://github.com/stotz/scoop-boot/issues](https://github.com/stotz/scoop-boot/issues)
- 💬 **Discussions:** [https://github.com/stotz/scoop-boot/discussions](https://github.com/stotz/scoop-boot/discussions)
- 🌟 **Scoop:** [https://scoop.sh](https://scoop.sh)

---

<div align="center">

**Made with ❤️ for the Windows development community**

If you find scoop-boot useful, please ⭐ **star the repository** on GitHub!

[⬆ Back to Top](#scoop-boot)

</div
