# scoop-boot

> 🚀 **Bootstrap script for Scoop package manager and portable Windows development environments**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Scoop](https://img.shields.io/badge/Scoop-Package%20Manager-green.svg)](https://scoop.sh)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-2.1.0-brightgreen.svg)](https://github.com/stotz/scoop-boot/releases)
[![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)](https://www.microsoft.com/windows)

**scoop-boot.ps1** is a comprehensive PowerShell script that bootstraps [Scoop](https://scoop.sh) package manager and manages development environment variables on Windows systems. It provides a **portable, reproducible, and robust** way to set up and maintain development workstations.

<img width="800" alt="image" src="https://github.com/user-attachments/assets/890aa034-0182-420f-a5b8-46245fc81f99" />

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Installation](#installation)
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
- [Complete Installation Guide](#complete-installation-guide)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)
- [Contributing](#contributing)
- [License](#license)

## Features

✨ **Core Features**
- 🎯 **One-Command Bootstrap** - Install Scoop and all recommended tools with a single command
- 🔧 **Environment Management** - Hierarchical `.env` files with override mechanism
- 📦 **50+ Technologies** - Pre-configured templates for Java, Python, Node.js, C++, Docker, K8s, and more
- 🧪 **Self-Testing** - 26 comprehensive tests to ensure everything works correctly
- 🔄 **Backup & Rollback** - Automatic backups before environment changes
- 🎨 **Order-Independent Parameters** - Arguments can be specified in any order
- 🚫 **No Admin Required** - User-level installation (admin only for system-wide env vars)
- 💾 **Portable** - Everything in one directory, easily movable or backup-able
- 🛡️ **Robust** - Automatic error recovery and validation

## What's New in v2.1

🆕 **Recent Improvements:**
- ✅ **MSYS2/UCRT64 Support** - Proper GCC 15.2.0 configuration for modern C++ development
- ✅ **Enhanced Bootstrap** - Better error handling and automatic fallbacks
- ✅ **Git Integration** - Automatic Git configuration for bucket management
- ✅ **PATH Cleanup** - Intelligent duplicate removal (Machine vs User scope)
- ✅ **Comprehensive Testing** - Production-ready with 50+ package installations verified

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
# 1. Download scoop-boot.ps1 to your desired location (e.g., C:\usr\bin)
New-Item -ItemType Directory -Path C:\usr\bin -Force
Invoke-WebRequest -Uri https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1 -OutFile C:\usr\bin\scoop-boot.ps1

# 2. Bootstrap Scoop with all recommended tools (installs: Scoop + Git + aria2 + 7zip + essential tools)
C:\usr\bin\scoop-boot.ps1 --bootstrap

# 3. Restart your shell (IMPORTANT - loads new PATH)
exit

# 4. Verify installation
scoop-boot.ps1 --status

# 5. Create environment configuration
scoop-boot.ps1 --init-env=user.default.env

# 6. Apply environment (as Administrator if using system.*.env)
scoop-boot.ps1 --apply-env
```

**That's it! You now have a complete development environment.** 🎉

## Installation

### Option 1: Manual Download (Recommended)

```powershell
# Create directory structure
New-Item -ItemType Directory -Path C:\usr\bin -Force
New-Item -ItemType Directory -Path C:\usr\etc\environments -Force

# Download scoop-boot.ps1
Invoke-WebRequest -Uri https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1 `
                  -OutFile C:\usr\bin\scoop-boot.ps1

# Run bootstrap
C:\usr\bin\scoop-boot.ps1 --bootstrap
```

### Option 2: Git Clone

```powershell
git clone https://github.com/stotz/scoop-boot.git C:\usr
C:\usr\bin\scoop-boot.ps1 --bootstrap
```

### Option 3: Complete Installation Package

For a complete development environment with 50+ tools, see [Complete Installation Guide](#complete-installation-guide).

## Usage

### Bootstrap Scoop

The `--bootstrap` command installs Scoop and all essential tools:

```powershell
.\scoop-boot.ps1 --bootstrap
```

**What gets installed:**
- ✅ **Scoop Core** - Package manager (installed to C:\usr by default)
- ✅ **Git 2.51+** - Version control and bucket management
- ✅ **7-Zip 25+** - Archive extraction
- ✅ **aria2 1.37+** - Parallel downloads (5x faster)
- ✅ **sudo** - Run commands as administrator
- ✅ **innounp, dark, lessmsi** - Additional extractors
- ✅ **wget, cacert** - Alternative downloaders and certificates
- ✅ **Buckets** - main and extras repositories

**After bootstrap:**
```powershell
# Verify installation
scoop --version

# Check what's installed
scoop list

# Update Scoop itself
scoop update
```

To force reinstallation:
```powershell
.\scoop-boot.ps1 --bootstrap --force
```

### Environment Management

#### Create Environment File

```powershell
# For current user (recommended - no admin needed)
.\scoop-boot.ps1 --init-env=user.default.env

# For specific host/user combination
.\scoop-boot.ps1 --init-env=user.bootes.john.env

# For system-wide (requires Administrator)
.\scoop-boot.ps1 --init-env=system.default.env
```

**Files are created in:** `C:\usr\etc\environments\`

#### Apply Environment

```powershell
# Preview changes (dry run - see what will change)
.\scoop-boot.ps1 --apply-env --dry-run

# Apply changes (REMEMBER: Restart shell after!)
.\scoop-boot.ps1 --apply-env

# Rollback to previous state
.\scoop-boot.ps1 --apply-env --rollback
```

⚠️ **IMPORTANT:** Always restart your shell (or open a new terminal) after applying environment changes!

#### Check Status

```powershell
# Show overall status
.\scoop-boot.ps1 --status

# Show environment files and their hierarchy
.\scoop-boot.ps1 --env-status

# Show current environment variables
.\scoop-boot.ps1 --environment
```

### Application Installation

```powershell
# Install single application
.\scoop-boot.ps1 --install nodejs

# Install multiple applications at once
.\scoop-boot.ps1 --install python openjdk maven gradle

# Show installation suggestions based on your environment
.\scoop-boot.ps1 --suggest
```

**Popular development stacks:**
```powershell
# Java Development
scoop install temurin21-jdk maven gradle ant kotlin

# Python Development
scoop install python313 python-poetry pipenv

# Node.js Development
scoop install nodejs yarn pnpm

# C++ Development (requires MSYS2 setup - see below)
scoop install msys2 cmake ninja

# Go Development
scoop install go

# .NET Development
scoop install dotnet-sdk

# Database Tools
scoop install postgresql mysql redis mongodb-database-tools

# DevOps Tools
scoop install docker kubectl helm terraform ansible aws azure-cli gcloud
```

## Environment Configuration

### File Hierarchy

Environment files are loaded in this **specific order** (later files override earlier):

1. **`system.default.env`** - System-wide defaults (Machine scope, requires Administrator)
2. **`system.HOSTNAME.USERNAME.env`** - System-specific overrides (Machine scope, requires Administrator)
3. **`user.default.env`** - User defaults (User scope, **recommended**)
4. **`user.HOSTNAME.USERNAME.env`** - User-specific overrides (User scope, highest priority)

📁 **Files location:** `$SCOOP\etc\environments\` (usually `C:\usr\etc\environments\`)

💡 **Best Practice:** Use `user.default.env` for most configurations (no admin needed, portable)

### Syntax Reference

```ini
# ============================================================================
# VARIABLE ASSIGNMENT
# ============================================================================
JAVA_HOME=C:\usr\apps\temurin21-jdk\current
MAVEN_HOME=$SCOOP\apps\maven\current

# ============================================================================
# PATH MANIPULATION
# ============================================================================
# Prepend to PATH (add at beginning - highest priority)
PATH+=$JAVA_HOME\bin
PATH+=$MAVEN_HOME\bin

# Append to PATH (add at end - lowest priority)
PATH=+$SCOOP\tools

# Remove from PATH (exact match required)
PATH-=C:\old\path\to\remove

# Remove with different syntax variations
PATH -= C:\another\old\path
PATH-= C:\path\with\space

# ============================================================================
# VARIABLE DELETION
# ============================================================================
# Delete a variable entirely
-OLD_VARIABLE
-DEPRECATED_SETTING

# ============================================================================
# COMMENTS
# ============================================================================
# Lines starting with # are comments
# Use comments to document your configuration

# ============================================================================
# SCOPE CONTROL (ADVANCED)
# ============================================================================
# system.* files set Machine-level variables (requires Administrator)
# user.* files set User-level variables (no admin needed)
```

### Variable Expansion

Variables can reference other variables and environment variables:

```ini
# Built-in variable: $SCOOP expands to your Scoop directory (e.g., C:\usr)
JAVA_HOME=$SCOOP\apps\temurin21-jdk\current
MAVEN_HOME=$SCOOP\apps\maven\current

# Reference Windows environment variables
M2_REPO=$USERPROFILE\.m2\repository
TEMP_DIR=$TEMP\my-app

# Chain references (variables reference other variables)
PATH+=$JAVA_HOME\bin
PATH+=$MAVEN_HOME\bin

# Multiple references in one line
CLASSPATH=$JAVA_HOME\lib\tools.jar;$MAVEN_HOME\lib

# Cached variables (expanded once and remembered)
CACHED_VAR=$USERPROFILE\AppData\Local\MyApp
ANOTHER_VAR=$CACHED_VAR\config
```

**Variable Expansion Order:**
1. **$SCOOP** - Always points to Scoop root directory
2. **Environment variables** - Windows env vars like %USERPROFILE%, %TEMP%
3. **Previously defined variables** - Variables defined earlier in the file

### MSYS2/UCRT64 Configuration

**IMPORTANT:** MSYS2 uses **UCRT64** (not mingw64) for modern GCC compiler!

```ini
# ============================================================================
# MSYS2/UCRT64 - Modern GCC Compiler & Unix Tools
# ============================================================================
MSYS2_HOME=$SCOOP\apps\msys2\current

# CRITICAL: Use ucrt64 for GCC 15.2.0 (not mingw64!)
PATH+=$MSYS2_HOME\ucrt64\bin
PATH+=$MSYS2_HOME\usr\bin

# After installing MSYS2, run these commands in UCRT64 terminal:
# C:\usr\apps\msys2\current\ucrt64.exe
# pacman -Syu
# pacman -S mingw-w64-ucrt-x86_64-gcc
```

**Why UCRT64?**
- ✅ Modern GCC 15.2.0 compiler
- ✅ Universal C Runtime (modern Windows standard)
- ✅ Better compatibility with Windows 10/11
- ❌ mingw64 is legacy (older msvcrt.dll)

**Verify GCC installation:**
```cmd
C:\> gcc --version
gcc.exe (Rev8, Built by MSYS2 project) 15.2.0
```

## Commands

| Command | Description | Example |
|---------|-------------|---------|
| `--bootstrap` | Install Scoop + essential tools (Git, 7zip, aria2, etc.) | `.\scoop-boot.ps1 --bootstrap` |
| `--force` | Force reinstallation (use with --bootstrap) | `.\scoop-boot.ps1 --bootstrap --force` |
| `--status` | Show Scoop installation and environment status | `.\scoop-boot.ps1 --status` |
| `--init-env=FILE` | Create new environment configuration file | `.\scoop-boot.ps1 --init-env=user.default.env` |
| `--apply-env` | Apply environment configurations (restart shell after!) | `.\scoop-boot.ps1 --apply-env` |
| `--dry-run` | Preview changes without applying them | `.\scoop-boot.ps1 --apply-env --dry-run` |
| `--rollback` | Rollback to previous environment state | `.\scoop-boot.ps1 --apply-env --rollback` |
| `--env-status` | Show environment files and load order | `.\scoop-boot.ps1 --env-status` |
| `--environment` | Display current environment variables | `.\scoop-boot.ps1 --environment` |
| `--install APP...` | Install one or more applications via Scoop | `.\scoop-boot.ps1 --install git nodejs python` |
| `--suggest` | Show installation suggestions for common tools | `.\scoop-boot.ps1 --suggest` |
| `--selfTest` | Run comprehensive self-tests (26 tests) | `.\scoop-boot.ps1 --selfTest` |
| `--version` | Show scoop-boot version | `.\scoop-boot.ps1 --version` |
| `--help` | Display detailed help message | `.\scoop-boot.ps1 --help` |

💡 **Tip:** Parameters can be specified in any order!

## Examples

### Example 1: Java Development Environment

```powershell
# 1. Bootstrap Scoop
C:\usr\bin\scoop-boot.ps1 --bootstrap

# 2. Restart shell
exit

# 3. Create environment file
scoop-boot.ps1 --init-env=user.default.env

# 4. Edit configuration
notepad C:\usr\etc\environments\user.default.env
```

**Example `user.default.env` for Java:**
```ini
# ============================================================================
# Java Development Environment
# ============================================================================

# Java JDK
JAVA_HOME=$SCOOP\apps\temurin21-jdk\current
PATH+=$JAVA_HOME\bin
JAVA_OPTS=-Xmx2g -Xms512m -XX:+UseG1GC -XX:MaxGCPauseMillis=200

# Maven
MAVEN_HOME=$SCOOP\apps\maven\current
PATH+=$MAVEN_HOME\bin
M2_HOME=$MAVEN_HOME
M2_REPO=$USERPROFILE\.m2\repository
MAVEN_OPTS=-Xmx1024m -XX:+TieredCompilation -XX:TieredStopAtLevel=1

# Gradle
GRADLE_HOME=$SCOOP\apps\gradle\current
PATH+=$GRADLE_HOME\bin
GRADLE_USER_HOME=$USERPROFILE\.gradle
GRADLE_OPTS=-Xmx2048m -Dorg.gradle.daemon=true -Dorg.gradle.parallel=true

# Ant
ANT_HOME=$SCOOP\apps\ant\current
PATH+=$ANT_HOME\bin

# Kotlin
KOTLIN_HOME=$SCOOP\apps\kotlin\current
PATH+=$KOTLIN_HOME\bin

# Cleanup - Remove unwanted paths
PATH-=C:\old\java\installation
```

```powershell
# 5. Apply environment
scoop-boot.ps1 --apply-env

# 6. Restart shell
exit

# 7. Install Java development tools
scoop bucket add java
scoop install temurin21-jdk maven gradle ant kotlin

# 8. Verify
java -version
mvn --version
gradle --version
```

### Example 2: Full Stack Development

```ini
# ============================================================================
# Full Stack Development Environment
# ============================================================================

# Core Paths (highest priority)
PATH+=$SCOOP\bin
PATH+=$SCOOP\shims

# Git
GIT_HOME=$SCOOP\apps\git\current
PATH+=$GIT_HOME\cmd
PATH+=$GIT_HOME\usr\bin
GIT_SSH=$SCOOP\apps\openssh\current\ssh.exe

# Java
JAVA_HOME=$SCOOP\apps\temurin21-jdk\current
PATH+=$JAVA_HOME\bin

# Python
PYTHON_HOME=$SCOOP\apps\python313\current
PATH+=$PYTHON_HOME
PATH+=$PYTHON_HOME\Scripts
PYTHONPATH=$PYTHON_HOME\Lib\site-packages

# Node.js
NODE_HOME=$SCOOP\apps\nodejs\current
PATH+=$NODE_HOME
NODE_PATH=$NODE_HOME\node_modules
NPM_CONFIG_PREFIX=$SCOOP\persist\nodejs

# Docker
DOCKER_HOST=tcp://localhost:2375
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1

# Kubernetes
KUBECONFIG=$USERPROFILE\.kube\config
KUBECTL_NAMESPACE=default

# Localization
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
LANGUAGE=en_US:en
```

### Example 3: C++ Development with MSYS2

```ini
# ============================================================================
# C++ Development Environment with GCC 15.2.0
# ============================================================================

# MSYS2/UCRT64 - CRITICAL: Use ucrt64 for modern GCC!
MSYS2_HOME=$SCOOP\apps\msys2\current
PATH+=$MSYS2_HOME\ucrt64\bin
PATH+=$MSYS2_HOME\usr\bin

# CMake
CMAKE_HOME=$SCOOP\apps\cmake\current
PATH+=$CMAKE_HOME\bin

# Make
MAKE_HOME=$SCOOP\apps\make\current
PATH+=$MAKE_HOME\bin

# vcpkg (C++ Package Manager)
VCPKG_ROOT=$SCOOP\apps\vcpkg\current
PATH+=$VCPKG_ROOT
```

**Installation steps:**
```powershell
# Install MSYS2
scoop install msys2

# Open UCRT64 terminal (NOT msys2.exe!)
C:\usr\apps\msys2\current\ucrt64.exe

# In UCRT64 terminal:
pacman -Syu                              # Update system
pacman -S mingw-w64-ucrt-x86_64-gcc     # Install GCC

# Verify (in regular CMD/PowerShell)
gcc --version  # Should show: gcc.exe (Rev8, Built by MSYS2 project) 15.2.0
```

### Example 4: Multi-User Setup

For shared workstations with different users:

```powershell
# ============================================================================
# As Administrator - Set company-wide defaults
# ============================================================================
scoop-boot.ps1 --init-env=system.default.env

# Edit system.default.env:
# - Corporate proxy settings
# - Company-wide tool versions
# - Network drive mappings
# - Required security settings

scoop-boot.ps1 --apply-env
```

**Example `system.default.env`:**
```ini
# Corporate Proxy
HTTP_PROXY=http://proxy.company.com:8080
HTTPS_PROXY=http://proxy.company.com:8080
NO_PROXY=localhost,127.0.0.1,*.company.local

# Java proxy
JAVA_TOOL_OPTIONS=-Dhttp.proxyHost=proxy.company.com -Dhttp.proxyPort=8080

# NPM proxy
NPM_CONFIG_PROXY=http://proxy.company.com:8080
NPM_CONFIG_HTTPS_PROXY=http://proxy.company.com:8080

# Company certificates
NODE_EXTRA_CA_CERTS=C:\Company\Certificates\ca-bundle.crt
```

```powershell
# ============================================================================
# As Each User - Personal preferences (no admin needed)
# ============================================================================
scoop-boot.ps1 --init-env=user.%COMPUTERNAME%.%USERNAME%.env

# Edit user.HOSTNAME.USERNAME.env:
# - Personal tool preferences
# - IDE settings
# - Custom aliases

scoop-boot.ps1 --apply-env
```

### Example 5: Python Virtual Environment

```ini
# ============================================================================
# Python Development Environment
# ============================================================================

PYTHON_HOME=$SCOOP\apps\python313\current
PATH+=$PYTHON_HOME
PATH+=$PYTHON_HOME\Scripts
PYTHONPATH=$PYTHON_HOME\Lib\site-packages

# Virtual Environment Settings
WORKON_HOME=$USERPROFILE\Envs
VIRTUALENVWRAPPER_PYTHON=$PYTHON_HOME\python.exe
PIPENV_VENV_IN_PROJECT=1

# Poetry Configuration
POETRY_HOME=$USERPROFILE\.poetry
POETRY_VIRTUALENVS_IN_PROJECT=true
```

### Example 6: DevOps & Cloud Development

```ini
# ============================================================================
# DevOps & Cloud Tools
# ============================================================================

# Docker
DOCKER_HOST=tcp://localhost:2375
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1

# Kubernetes
KUBECONFIG=$USERPROFILE\.kube\config
KUBECTL_NAMESPACE=development
HELM_HOME=$USERPROFILE\.helm

# AWS
AWS_CONFIG_FILE=$USERPROFILE\.aws\config
AWS_SHARED_CREDENTIALS_FILE=$USERPROFILE\.aws\credentials
AWS_DEFAULT_REGION=us-east-1

# Azure
AZURE_CONFIG_DIR=$USERPROFILE\.azure

# Terraform
TF_PLUGIN_CACHE_DIR=$USERPROFILE\.terraform.d\plugin-cache
TF_LOG=INFO

# Ansible
ANSIBLE_CONFIG=$USERPROFILE\.ansible.cfg
ANSIBLE_INVENTORY=$USERPROFILE\.ansible\inventory
```

## Self-Testing

Run comprehensive self-tests to verify your installation:

```powershell
.\scoop-boot.ps1 --selfTest
```

**What gets tested (26 tests):**
- ✅ PowerShell version compatibility (>= 5.1)
- ✅ Execution policy configuration
- ✅ Parameter parsing and order independence
- ✅ Admin rights detection
- ✅ Directory path generation
- ✅ Hostname and username detection
- ✅ PATH manipulation (prepend, append, remove)
- ✅ Variable assignment and expansion
- ✅ Comment and empty line handling
- ✅ Environment file processing
- ✅ Scope detection (system vs user)
- ✅ Mock environment application
- ✅ End-to-end integration tests

**Expected output:**
```
=== Self-Test ===

[OK] PowerShell version >= 5.1
[OK] Execution Policy allows scripts
[OK] Parameter parsing
[OK] Admin rights detection
[OK] Directory path generation
[OK] Hostname detection
[OK] Username detection
[OK] Host-User filename generation
[OK] Parse PATH += (prepend)
[OK] Parse PATH =+ (append)
[OK] Parse PATH - (remove with space)
[OK] Parse PATH-= (remove without space)
[OK] Parse PATH -= (remove with -= syntax)
[OK] Parse variable assignment
[OK] Parse comment line (should ignore)
[OK] Parse empty line (should ignore)
[OK] Variable expansion with $SCOOP_ROOT
[OK] Variable expansion with env var
[OK] Variable expansion with cache
[OK] Multiple variable expansion
[OK] Scope detection (system.*)
[OK] Scope detection (user.*)
[OK] Mock environment file processing
[OK] END-TO-END: Mock environment apply
[OK] Scope detection with Get-EnvironmentFiles
[OK] PATH operations on mock data

Tests: 26 passed, 0 failed, 26 total
```

If any test fails, please report it as an issue on GitHub.

## Complete Installation Guide

For a **complete development environment** with 50+ tools, use the companion script:

### Two-Phase Installation

**Phase 1: Set Environment Variables (as Administrator)**
```powershell
# Download complete installation script
Invoke-WebRequest -Uri https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-complete-install.ps1 `
                  -OutFile C:\usr\bin\scoop-complete-install.ps1

# Phase 1: Set Machine-level environment variables
.\scoop-complete-install.ps1 -SetEnvironment
```

**Phase 2: Install Tools (as Normal User)**
```powershell
# Close Administrator window, open normal PowerShell

# Phase 2: Install all development tools
.\scoop-complete-install.ps1 -InstallTools
```

**What gets installed (50+ packages):**
- ✅ **Java:** Temurin JDK 8, 11, 17, 21, 23
- ✅ **Build Tools:** Maven, Gradle, Ant, CMake, Make, Ninja, Kotlin
- ✅ **Languages:** Python 3.13, Perl, Node.js 25, MSYS2/GCC
- ✅ **Version Control:** Git, TortoiseSVN, GitHub CLI, lazygit
- ✅ **Editors:** VS Code, Neovim, Notepad++, JetBrains Toolbox
- ✅ **GUI Tools:** Windows Terminal, HxD, WinMerge, DBeaver, Postman
- ✅ **CLI Tools:** jq, curl, openssh, ripgrep, fd, bat
- ✅ **System Tools:** VC++ Runtime, System Informer

**Post-Installation:**
- ✅ Java 21 set as default
- ✅ GCC 15.2.0 configured (UCRT64)
- ✅ Registry integrations (context menus)
- ✅ System tray apps started
- ✅ Duplicate PATH entries cleaned up

## Troubleshooting

### Common Issues

#### 1. "Scoop is not installed"

```powershell
# Solution: Run bootstrap first
.\scoop-boot.ps1 --bootstrap

# Verify
scoop --version
```

#### 2. "Cannot be loaded because running scripts is disabled"

```powershell
# Solution: Fix execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Verify
Get-ExecutionPolicy
```

#### 3. "Administrator rights required"

**Problem:** Trying to use `system.*.env` files without admin rights

**Solutions:**
- **Option A (Recommended):** Use `user.*.env` files instead (no admin needed)
- **Option B:** Run PowerShell as Administrator when applying system files

```powershell
# Check if running as admin
([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
```

#### 4. "Environment variables not updating in my shell"

**Problem:** Shell has cached old environment variables

**Solution:** **ALWAYS restart your shell** after applying changes!

```powershell
# Apply changes
scoop-boot.ps1 --apply-env

# CRITICAL: Close and reopen your terminal/shell
exit

# Or refresh in same shell (PowerShell)
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
```

#### 5. "gcc not found" after MSYS2 installation

**Problem:** Using wrong MSYS2 environment or incorrect PATH

**Solutions:**

**Check 1:** Are you using UCRT64 (not MSYS2)?
```powershell
# WRONG: C:\usr\apps\msys2\current\msys2.exe
# RIGHT: C:\usr\apps\msys2\current\ucrt64.exe
```

**Check 2:** Is UCRT64 in your PATH?
```cmd
C:\> echo %PATH% | findstr ucrt64
# Should show: C:\usr\apps\msys2\current\ucrt64\bin
```

**Check 3:** Is GCC installed in MSYS2?
```bash
# In UCRT64 terminal:
pacman -S mingw-w64-ucrt-x86_64-gcc
```

**Fix environment file:**
```ini
# WRONG:
PATH+=$MSYS2_HOME\mingw64\bin

# RIGHT:
PATH+=$MSYS2_HOME\ucrt64\bin
```

#### 6. "scoop-boot.ps1 bootstrap fails with .cs compilation error"

**Problem:** PowerShell cannot compile temporary C# files

**Symptoms:**
```
[ERROR] Failed to install Scoop: Source file 'C:\Windows\Temp\xxxxx.0.cs' could not be found
```

**Solution:** scoop-boot.ps1 v2.1+ has automatic fallback!
- ✅ Automatically uses alternative installation method
- ✅ Uses user TEMP directory instead of Windows TEMP
- ✅ Downloads official Scoop installer
- ✅ No manual intervention needed

If fallback also fails:
```powershell
# Manual workaround
$env:TEMP = "$env:USERPROFILE\Temp"
$env:TMP = "$env:USERPROFILE\Temp"
New-Item -ItemType Directory -Path $env:TEMP -Force

# Retry bootstrap
.\scoop-boot.ps1 --bootstrap
```

#### 7. "Path too long" errors

```powershell
# Enable long path support (requires Administrator)
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
                 -Name "LongPathsEnabled" `
                 -Value 1 `
                 -PropertyType DWORD `
                 -Force

# Restart required
Restart-Computer
```

#### 8. "Bucket not found" or "Manifest not found"

**Problem:** Buckets not added or Git not configured

**Solutions:**

**Check 1:** Is Git installed?
```powershell
git --version
# If not: scoop install git
```

**Check 2:** Are buckets added?
```powershell
scoop bucket list

# Add missing buckets:
scoop bucket add main
scoop bucket add extras
scoop bucket add java
scoop bucket add versions
```

**Check 3:** Update buckets
```powershell
scoop update
```

### Debug Mode

For detailed troubleshooting:

```powershell
# Dry run - see what will happen
.\scoop-boot.ps1 --apply-env --dry-run

# Check status
.\scoop-boot.ps1 --status
.\scoop-boot.ps1 --env-status

# List environment variables
.\scoop-boot.ps1 --environment
```

### Reset Environment

To start fresh:

```powershell
# 1. Backup current settings
New-Item -ItemType Directory -Path C:\usr\etc\environments\backup -Force
Copy-Item C:\usr\etc\environments\*.env C:\usr\etc\environments\backup\

# 2. Remove all environment files
Remove-Item C:\usr\etc\environments\*.env -Confirm

# 3. Create new configuration
.\scoop-boot.ps1 --init-env=user.default.env

# 4. Edit and apply
notepad C:\usr\etc\environments\user.default.env
.\scoop-boot.ps1 --apply-env
```

### Getting Help

If issues persist:
1. Run `.\scoop-boot.ps1 --selfTest` to verify installation
2. Check the [GitHub Issues](https://github.com/stotz/scoop-boot/issues)
3. Report bugs with output from `--status` and `--selfTest`

## Advanced Usage

### Custom Scoop Directory

```powershell
# Set custom directory BEFORE bootstrap
$env:SCOOP = "D:\DevTools\scoop"
$env:SCOOP_GLOBAL = "D:\DevTools\scoop\global"

# Make it permanent
[Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')
[Environment]::SetEnvironmentVariable('SCOOP_GLOBAL', $env:SCOOP_GLOBAL, 'User')

# Then bootstrap
D:\DevTools\scoop\bin\scoop-boot.ps1 --bootstrap
```

### Automated Workstation Deployment

Create a setup script for automated deployments:

```powershell
# automated-setup.ps1
param(
    [string]$ConfigUrl = "https://company.com/configs/dev-env.env",
    [string]$ScoopDir = "C:\DevTools"
)

# 1. Download scoop-boot
$bootScript = "$env:TEMP\scoop-boot.ps1"
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1" `
                  -OutFile $bootScript

# 2. Set custom directory
$env:SCOOP = $ScoopDir
[Environment]::SetEnvironmentVariable('SCOOP', $ScoopDir, 'User')

# 3. Bootstrap
& $bootScript --bootstrap

# 4. Download company configuration
$envFile = "$ScoopDir\etc\environments\user.default.env"
Invoke-WebRequest -Uri $ConfigUrl -OutFile $envFile

# 5. Apply configuration
& "$ScoopDir\bin\scoop-boot.ps1" --apply-env

# 6. Install company-required tools
& "$ScoopDir\bin\scoop-boot.ps1" --install git nodejs python vscode

Write-Host "Setup complete! Please restart your shell." -ForegroundColor Green
```

**Run deployment:**
```powershell
.\automated-setup.ps1 -ConfigUrl "https://internal.company.com/scoop-env.env"
```

### Continuous Integration

Use scoop-boot in CI/CD pipelines:

```yaml
# .github/workflows/build.yml
name: Build with Scoop

on: [push]

jobs:
  build:
    runs-on: windows-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Setup Scoop
      shell: powershell
      run: |
        Invoke-WebRequest -Uri https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1 `
                          -OutFile scoop-boot.ps1
        .\scoop-boot.ps1 --bootstrap
        
    - name: Install Build Tools
      shell: powershell
      run: |
        scoop install openjdk maven
        
    - name: Build Project
      run: mvn clean package
```

### Network-Restricted Environments

For environments with limited internet access:

```powershell
# 1. Create package mirror
scoop cache show  # List all cached packages

# 2. Copy cache to network share
Copy-Item -Path "$env:SCOOP\cache\*" -Destination "\\fileserver\scoop-mirror\cache\" -Recurse

# 3. On target machines, use local cache
$env:SCOOP_CACHE = "\\fileserver\scoop-mirror\cache"
[Environment]::SetEnvironmentVariable('SCOOP_CACHE', $env:SCOOP_CACHE, 'User')

# 4. Bootstrap with cached packages
.\scoop-boot.ps1 --bootstrap
```

### Custom Environment Templates

Create reusable templates for different teams:

```powershell
# templates/java-team.env
# Java Development Template

JAVA_HOME=$SCOOP\apps\temurin21-jdk\current
PATH+=$JAVA_HOME\bin
MAVEN_HOME=$SCOOP\apps\maven\current
PATH+=$MAVEN_HOME\bin
GRADLE_HOME=$SCOOP\apps\gradle\current
PATH+=$GRADLE_HOME\bin

# Deploy to teams
Copy-Item templates\java-team.env C:\usr\etc\environments\user.default.env
scoop-boot.ps1 --apply-env
```

## Project Structure

```
C:\usr\                          # Scoop root directory (configurable)
├── bin\
│   ├── scoop-boot.ps1          # Main bootstrap script
│   └── scoop-complete-install.ps1  # Complete installation script
├── etc\
│   └── environments\           # Environment configurations
│       ├── system.default.env
│       ├── user.default.env
│       ├── user.bootes.john.env
│       └── backup\             # Automatic backups
│           └── user.default.env.backup_20250129_010230
├── apps\                       # Installed applications
│   ├── git\
│   │   ├── current -> 2.51.2
│   │   └── 2.51.2\
│   ├── python313\
│   │   ├── current -> 3.13.9
│   │   └── 3.13.9\
│   └── ...
├── buckets\                    # Scoop buckets (app repositories)
│   ├── main\
│   ├── extras\
│   ├── java\
│   └── versions\
├── cache\                      # Download cache (speeds up reinstalls)
├── persist\                    # Persistent app data
└── shims\                      # Command shims (auto-added to PATH)
```

## Supported Technologies

Pre-configured templates and support for 50+ technologies:

**Programming Languages**
- Java (OpenJDK, Temurin, Oracle JDK, GraalVM)
- Python (CPython, Anaconda, Miniconda)
- Node.js (LTS, Current, Version manager)
- C/C++ (GCC via MSYS2, LLVM/Clang, MSVC)
- Go, Rust, Ruby, Perl, PHP, Lua, R
- .NET (SDK, Runtime, Framework)
- Kotlin, Scala, Groovy, Clojure

**Build Tools & Package Managers**
- Maven, Gradle, Ant, SBT
- CMake, Make, Ninja, Meson
- npm, yarn, pnpm, Volta
- pip, poetry, pipenv, conda
- vcpkg, Conan, Hunter
- Cargo, Rustup
- Bundler, RubyGems

**Databases & Data Tools**
- PostgreSQL, MySQL, MariaDB
- MongoDB, Redis, Memcached
- SQLite, DuckDB, ClickHouse
- Elasticsearch, Kibana, Logstash
- Apache Kafka, RabbitMQ
- DBeaver, pgAdmin, MySQL Workbench

**Web Servers & Proxies**
- Apache HTTP Server
- Nginx, Caddy
- Tomcat, Jetty, WildFly
- IIS Express
- Traefik, HAProxy

**Containers & Orchestration**
- Docker Desktop, Docker CLI
- Podman, Buildah
- Kubernetes (kubectl, minikube, k3s)
- Helm, Helmfile
- Docker Compose
- Rancher Desktop

**Cloud Tools**
- AWS CLI, SAM CLI, CDK
- Azure CLI, Azure Functions Core Tools
- Google Cloud SDK (gcloud)
- Terraform, Terragrunt
- Pulumi
- OpenTofu

**DevOps & CI/CD**
- Git, Git LFS, GitHub CLI
- GitLab Runner
- Jenkins, Jenkins X
- Ansible, Ansible Lint
- Vagrant, Packer
- Consul, Vault

**IDEs & Editors**
- Visual Studio Code
- JetBrains IDEs (via Toolbox)
- Neovim, Vim
- Notepad++
- Sublime Text
- Emacs

**Version Control**
- Git, Git GUI, Git Bash
- TortoiseSVN, TortoiseGit
- Mercurial (hg)
- Perforce (p4)
- lazygit, tig

**Command Line Tools**
- ripgrep, fd, bat
- fzf, jq, yq
- curl, wget, aria2
- OpenSSH, PuTTY, WinSCP
- tmux, screen
- htop, btop

**Documentation & Diagramming**
- Graphviz, PlantUML
- Doxygen, Sphinx
- Hugo, Jekyll, MkDocs
- Mermaid CLI
- Asciidoctor

**And many more...**

## Best Practices

### 1. Use User-Level Configuration

✅ **DO:** Use `user.*.env` files for personal configurations
```powershell
scoop-boot.ps1 --init-env=user.default.env
```

❌ **DON'T:** Use `system.*.env` unless absolutely necessary (requires admin)

### 2. Document Your Environment

```ini
# user.default.env
# ============================================================================
# Project: My Company Development Environment
# Author: John Doe
# Updated: 2025-01-29
# Description: Standard setup for Java + Node.js development
# ============================================================================

# Java 21 LTS
JAVA_HOME=$SCOOP\apps\temurin21-jdk\current
PATH+=$JAVA_HOME\bin

# Node.js 25 (Current)
NODE_HOME=$SCOOP\apps\nodejs\current
PATH+=$NODE_HOME
```

### 3. Version Control Your Environment Files

```powershell
# Initialize git repository
cd C:\usr\etc\environments
git init
git add user.default.env
git commit -m "Initial development environment"

# Share with team
git remote add origin https://github.com/company/dev-env.git
git push -u origin main
```

### 4. Test Before Applying

```powershell
# Always preview changes first
scoop-boot.ps1 --apply-env --dry-run

# Review output carefully
# Then apply if everything looks good
scoop-boot.ps1 --apply-env
```

### 5. Keep Backups

scoop-boot automatically creates backups, but you can also:

```powershell
# Manual backup
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
Copy-Item C:\usr\etc\environments\user.default.env `
          C:\usr\etc\environments\backup\user.default.env.$timestamp
```

### 6. Regular Updates

```powershell
# Update Scoop itself
scoop update

# Update all installed apps
scoop update *

# Check for outdated apps
scoop status
```

### 7. Clean Cache Periodically

```powershell
# View cache size
scoop cache show

# Clean old downloads
scoop cache rm *

# Or clean specific apps
scoop cache rm python nodejs
```

## Contributing

Contributions are welcome! We appreciate:
- 🐛 Bug reports and fixes
- ✨ New features and enhancements
- 📚 Documentation improvements
- 🧪 Additional tests
- 💡 Suggestions and feedback

### Development Guidelines

1. **PowerShell 5.1 Compatibility** - Maintain compatibility with Windows PowerShell 5.1
2. **Order-Independent Parameters** - Ensure parameters work in any order
3. **ASCII-Only Output** - No Unicode symbols in console output (compatibility)
4. **Comprehensive Testing** - All 26 self-tests must pass
5. **Version Bumping** - Increment version for any changes
6. **Documentation** - Update README and inline help for new features
7. **English Language** - All comments, documentation, and messages in English
8. **Error Handling** - Graceful error handling and user-friendly messages

### Testing Your Changes

```powershell
# 1. Run self-tests
.\scoop-boot.ps1 --selfTest

# 2. Test parameter parsing (all should work)
.\scoop-boot.ps1 --help --version --status
.\scoop-boot.ps1 --status --version --help
.\scoop-boot.ps1 --bootstrap --force --install git

# 3. Test environment management
.\scoop-boot.ps1 --init-env=test.env
.\scoop-boot.ps1 --apply-env --dry-run
.\scoop-boot.ps1 --env-status

# 4. Test on fresh Windows VM
# - Windows 10 (clean install)
# - Windows 11 (clean install)
# - Windows Server 2019/2022
```

### Submitting Changes

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run all tests (`.\scoop-boot.ps1 --selfTest`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

### Code Style

```powershell
# Good: Clear variable names
$environmentFiles = Get-EnvironmentFiles

# Bad: Unclear abbreviations
$envF = Get-Env

# Good: Descriptive function names
function Get-EnvironmentConfiguration { }

# Bad: Unclear function names
function GetEnv { }

# Good: Comments explaining why
# Remove duplicates to prevent PATH pollution

# Bad: Comments explaining what (code is self-explanatory)
# This removes duplicates
```

## Roadmap

**Planned Features:**
- 🔄 Auto-update mechanism for scoop-boot.ps1
- 🌐 Multi-language support (German, French, Spanish)
- 📊 Environment comparison tool
- 🔍 Dependency analyzer
- 🎨 GUI configuration tool
- 📦 Environment export/import (JSON format)
- 🔐 Encrypted environment variables
- 🤖 AI-assisted environment suggestions
- 📈 Usage analytics and recommendations

**Coming Soon:**
- 🐳 Docker container support
- ☁️ Cloud synchronization (OneDrive, Google Drive)
- 📱 Mobile companion app
- 🎮 Interactive TUI (Terminal UI)

See [Roadmap](https://github.com/stotz/scoop-boot/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement) for details.

## Changelog

### v2.1.0 (2025-01-29)
- ✅ **NEW:** MSYS2/UCRT64 support for GCC 15.2.0
- ✅ **NEW:** Enhanced bootstrap with automatic fallback
- ✅ **NEW:** Git integration improvements
- ✅ **NEW:** PATH cleanup (Machine vs User scope)
- ✅ **FIX:** Bootstrap .cs compilation errors
- ✅ **FIX:** Bucket management issues
- ✅ **IMPROVED:** Error handling and user feedback
- ✅ **IMPROVED:** Documentation and examples

### v2.0.0 (2024-10-22)
- 🎉 Major rewrite
- Order-independent parameters
- 26 comprehensive self-tests
- Hierarchical environment files
- Automatic backups and rollback
- Improved error handling

### v1.0.0 (2023)
- Initial release
- Basic bootstrap functionality
- Simple environment management

## License

MIT License

Copyright (c) 2025 stotz

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Acknowledgments

- **[Scoop](https://scoop.sh)** - The amazing Windows package manager this project is built on
- **[ScoopInstaller](https://github.com/ScoopInstaller)** - The Scoop community and maintainers
- **Contributors** - Everyone who has contributed code, bug reports, and suggestions
- **Users** - Thank you for using scoop-boot and providing valuable feedback!

## Links

- 🏠 **Repository:** [https://github.com/stotz/scoop-boot](https://github.com/stotz/scoop-boot)
- 🐛 **Issues:** [https://github.com/stotz/scoop-boot/issues](https://github.com/stotz/scoop-boot/issues)
- 📖 **Wiki:** [https://github.com/stotz/scoop-boot/wiki](https://github.com/stotz/scoop-boot/wiki)
- 💬 **Discussions:** [https://github.com/stotz/scoop-boot/discussions](https://github.com/stotz/scoop-boot/discussions)
- 🌟 **Scoop:** [https://scoop.sh](https://scoop.sh)
- 📚 **Scoop Docs:** [https://github.com/ScoopInstaller/Scoop/wiki](https://github.com/ScoopInstaller/Scoop/wiki)

## Support

**Need help?**
- 📖 Read the [documentation](#table-of-contents)
- 🔍 Check [troubleshooting](#troubleshooting)
- 🐛 Report bugs on [GitHub Issues](https://github.com/stotz/scoop-boot/issues)
- 💬 Ask questions in [Discussions](https://github.com/stotz/scoop-boot/discussions)
- ⭐ Star the project if you find it useful!

## FAQ

**Q: Do I need Administrator rights?**  
A: Only for `system.*.env` files. Use `user.*.env` files for user-level configuration (recommended).

**Q: Can I use scoop-boot with existing Scoop installation?**  
A: Yes! scoop-boot works with existing Scoop installations.

**Q: How do I uninstall?**  
A: Remove the Scoop directory: `Remove-Item -Recurse -Force C:\usr`

**Q: Can I customize the installation directory?**  
A: Yes, set `$env:SCOOP` before running bootstrap.

**Q: Is scoop-boot compatible with Windows Server?**  
A: Yes, Windows Server 2016+ is supported.

**Q: Does scoop-boot work offline?**  
A: Partially. Bootstrap requires internet, but cached packages work offline.

**Q: Can I deploy scoop-boot company-wide?**  
A: Yes! See [Automated Deployment](#automated-workstation-deployment).

**Q: How do I update scoop-boot.ps1?**  
A: Download the latest version from GitHub and replace your existing file.

---

<div align="center">

**Made with ❤️ for the Windows development community**

If you find scoop-boot useful, please ⭐ **star the repository** on GitHub!

[⬆ Back to Top](#scoop-boot)

</div>
