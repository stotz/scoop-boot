# scoop-boot

> 🚀 **Bootstrap script for Scoop package manager and portable Windows development environments**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Scoop](https://img.shields.io/badge/Scoop-Package%20Manager-green.svg)](https://scoop.sh)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-2.0.0-brightgreen.svg)](https://github.com/stotz/scoop-boot/releases)
[![Platform](https://img.shields.io/badge/Platform-Windows-blue.svg)](https://www.microsoft.com/windows)

**scoop-boot.ps1** is a comprehensive PowerShell script that bootstraps [Scoop](https://scoop.sh) package manager and manages development environment variables on Windows systems. It provides a portable, reproducible way to set up and maintain development workstations.

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
- [Commands](#commands)
- [Examples](#examples)
- [Self-Testing](#self-testing)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## Features

✨ **Core Features**
- 🎯 **One-Command Bootstrap** - Install Scoop and all recommended tools with a single command
- 🔧 **Environment Management** - Hierarchical `.env` files with override mechanism
- 📦 **40+ Technologies** - Pre-configured templates for Java, Python, Node.js, Go, Docker, K8s, and more
- 🧪 **Self-Testing** - 26 comprehensive tests to ensure everything works correctly
- 🔄 **Backup & Rollback** - Automatic backups before environment changes
- 🎨 **Order-Independent Parameters** - Arguments can be specified in any order
- 🚫 **No Admin Required** - User-level installation (admin only for system-wide env vars)
- 💾 **Portable** - Everything in one directory, easily movable or backup-able

## Requirements

- **Windows 10/11** or Windows Server 2016+
- **PowerShell 5.1** or higher
- **Execution Policy** allowing script execution:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

## Quick Start

```powershell
# 1. Download scoop-boot.ps1 to your desired location (e.g., C:\usr\bin)
Invoke-WebRequest -Uri https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1 -OutFile C:\usr\bin\scoop-boot.ps1

# 2. Bootstrap Scoop with all recommended tools
C:\usr\bin\scoop-boot.ps1 --bootstrap

# 3. Restart your shell (important!)
exit

# 4. Create environment configuration
scoop-boot.ps1 --init-env=user.default.env

# 5. Apply environment
scoop-boot.ps1 --apply-env
```

## Installation

### Option 1: Manual Download

1. Create your desired installation directory (e.g., `C:\usr\bin`)
2. Download `scoop-boot.ps1` to that directory
3. Run the bootstrap command

### Option 2: Git Clone

```powershell
git clone https://github.com/stotz/scoop-boot.git C:\usr
C:\usr\bin\scoop-boot.ps1 --bootstrap
```

### Option 3: Direct Execution

```powershell
# Run directly from URL (inspect first!)
iex ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1'))
```

## Usage

### Bootstrap Scoop

The `--bootstrap` command installs Scoop and all recommended tools:

```powershell
.\scoop-boot.ps1 --bootstrap
```

This installs:
- **Scoop Core** - Package manager
- **Essential Tools** - git, 7zip
- **Performance Tools** - aria2 (5x faster downloads)
- **Admin Tools** - sudo
- **Extractors** - innounp, dark, lessmsi
- **Alternative Downloaders** - wget
- **Buckets** - main, extras

To force reinstallation:
```powershell
.\scoop-boot.ps1 --bootstrap --force
```

### Environment Management

#### Create Environment File

```powershell
# For user (recommended)
.\scoop-boot.ps1 --init-env=user.default.env

# For specific host/user
.\scoop-boot.ps1 --init-env=user.hostname.username.env

# For system (requires admin)
.\scoop-boot.ps1 --init-env=system.default.env
```

#### Apply Environment

```powershell
# Preview changes (dry run)
.\scoop-boot.ps1 --apply-env --dry-run

# Apply changes
.\scoop-boot.ps1 --apply-env

# Rollback to previous state
.\scoop-boot.ps1 --apply-env --rollback
```

#### Check Status

```powershell
# Show overall status
.\scoop-boot.ps1 --status

# Show environment files status
.\scoop-boot.ps1 --env-status

# Show current environment variables
.\scoop-boot.ps1 --environment
```

### Application Installation

```powershell
# Install single application
.\scoop-boot.ps1 --install nodejs

# Install multiple applications
.\scoop-boot.ps1 --install python openjdk maven gradle

# Show installation suggestions
.\scoop-boot.ps1 --suggest
```

## Environment Configuration

### File Hierarchy

Environment files are loaded in this order (later files override earlier):

1. `system.default.env` - System-wide defaults (requires admin)
2. `system.HOSTNAME.USERNAME.env` - System + host-specific (requires admin)
3. `user.default.env` - User defaults (recommended)
4. `user.HOSTNAME.USERNAME.env` - User + host-specific (highest priority)

Files location: `$SCOOP\etc\environments\`

### Syntax Reference

```ini
# Set variable
JAVA_HOME=$SCOOP\apps\openjdk\current

# Prepend to PATH (add at beginning)
PATH+=$JAVA_HOME\bin

# Append to PATH (add at end)
PATH=+$SCOOP\tools

# Remove from PATH
PATH-=C:\old\path

# Delete variable
-OLD_VARIABLE

# Comments start with #
# This is a comment
```

### Variable Expansion

Variables can reference other variables:

```ini
# $SCOOP expands to your Scoop directory
JAVA_HOME=$SCOOP\apps\openjdk\current

# Reference other variables
MAVEN_REPO=$USERPROFILE\.m2\repository

# Multiple expansions
PATH+=$JAVA_HOME\bin
```

## Commands

| Command | Description | Example |
|---------|-------------|---------|
| `--bootstrap` | Install Scoop and recommended tools | `.\scoop-boot.ps1 --bootstrap` |
| `--force` | Force reinstallation (with --bootstrap) | `.\scoop-boot.ps1 --bootstrap --force` |
| `--status` | Show Scoop and environment status | `.\scoop-boot.ps1 --status` |
| `--init-env=FILE` | Create environment configuration file | `.\scoop-boot.ps1 --init-env=user.default.env` |
| `--apply-env` | Apply environment configurations | `.\scoop-boot.ps1 --apply-env` |
| `--dry-run` | Preview changes without applying | `.\scoop-boot.ps1 --apply-env --dry-run` |
| `--rollback` | Rollback to previous environment | `.\scoop-boot.ps1 --apply-env --rollback` |
| `--env-status` | Show environment files status | `.\scoop-boot.ps1 --env-status` |
| `--environment` | Display current environment variables | `.\scoop-boot.ps1 --environment` |
| `--install APP...` | Install applications via Scoop | `.\scoop-boot.ps1 --install git nodejs` |
| `--suggest` | Show application suggestions | `.\scoop-boot.ps1 --suggest` |
| `--selfTest` | Run self-tests | `.\scoop-boot.ps1 --selfTest` |
| `--version` | Show version | `.\scoop-boot.ps1 --version` |
| `--help` | Display help | `.\scoop-boot.ps1 --help` |

## Examples

### Complete Development Setup

```powershell
# 1. Bootstrap
C:\usr\bin\scoop-boot.ps1 --bootstrap

# 2. Restart shell
exit

# 3. Create environment file
scoop-boot.ps1 --init-env=user.default.env

# 4. Edit the file (example for Java development)
notepad C:\usr\etc\environments\user.default.env
```

Example `user.default.env`:
```ini
# Java Development
JAVA_HOME=$SCOOP\apps\openjdk\current
PATH+=$JAVA_HOME\bin
JAVA_OPTS=-Xmx2g -Xms512m -XX:+UseG1GC

# Maven
MAVEN_HOME=$SCOOP\apps\maven\current
PATH+=$MAVEN_HOME\bin
MAVEN_OPTS=-Xmx1024m

# Node.js
NODE_HOME=$SCOOP\apps\nodejs\current
PATH+=$NODE_HOME
NODE_OPTIONS=--max-old-space-size=4096
```

```powershell
# 5. Apply environment
scoop-boot.ps1 --apply-env

# 6. Install development tools
scoop-boot.ps1 --install openjdk maven nodejs python vscode
```

### Multi-User Setup

For shared workstations:

```powershell
# Admin: Create system defaults
.\scoop-boot.ps1 --init-env=system.default.env
# Edit with company-wide settings
.\scoop-boot.ps1 --apply-env

# Each user: Create personal overrides
.\scoop-boot.ps1 --init-env=user.$env:COMPUTERNAME.$env:USERNAME.env
# Edit with personal preferences
.\scoop-boot.ps1 --apply-env
```

### Python Virtual Environment

```ini
# In user.default.env
PYTHON_HOME=$SCOOP\apps\python\current
PATH+=$PYTHON_HOME
PATH+=$PYTHON_HOME\Scripts
WORKON_HOME=$USERPROFILE\Envs
PIPENV_VENV_IN_PROJECT=1
```

### Docker Development

```ini
# In user.default.env
DOCKER_HOST=tcp://localhost:2375
DOCKER_BUILDKIT=1
COMPOSE_DOCKER_CLI_BUILD=1
```

### Corporate Proxy

```ini
# In system.default.env (for all users)
HTTP_PROXY=http://proxy.company.com:8080
HTTPS_PROXY=http://proxy.company.com:8080
NO_PROXY=localhost,127.0.0.1,*.company.local

# Java proxy
JAVA_TOOL_OPTIONS=-Dhttp.proxyHost=proxy.company.com -Dhttp.proxyPort=8080

# NPM proxy
NPM_CONFIG_PROXY=http://proxy.company.com:8080
```

## Self-Testing

Run comprehensive self-tests to verify installation:

```powershell
.\scoop-boot.ps1 --selfTest
```

Tests include:
- PowerShell version check
- Execution policy verification
- Parameter parsing
- PATH manipulation
- Variable expansion
- Environment file processing
- Admin rights detection
- And 19 more tests...

Expected output:
```
=== Self-Test ===
[OK] PowerShell version >= 5.1
[OK] Execution Policy allows scripts
...
[OK] PATH operations on mock data

Tests: 26 passed, 0 failed, 26 total
```

## Troubleshooting

### Common Issues

#### "Scoop is not installed"
```powershell
# Run bootstrap first
.\scoop-boot.ps1 --bootstrap
```

#### "Cannot be loaded because running scripts is disabled"
```powershell
# Set execution policy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

#### "Administrator rights required"
- Only needed for `system.*.env` files
- Use `user.*.env` files instead (recommended)

#### "Environment variables not updating"
- **Always restart your shell after applying changes**
- Some applications cache environment variables

#### "Path too long" errors
```powershell
# Enable long path support (requires admin)
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
```

### Debug Mode

For troubleshooting, check the dry-run output:
```powershell
.\scoop-boot.ps1 --apply-env --dry-run
```

### Reset Environment

To start fresh:
```powershell
# Backup current settings
copy C:\usr\etc\environments\*.env C:\usr\etc\environments\backup\

# Remove all environment files
Remove-Item C:\usr\etc\environments\*.env

# Create new configuration
.\scoop-boot.ps1 --init-env=user.default.env
```

## Advanced Usage

### Custom Scoop Directory

```powershell
# Set custom directory before bootstrap
$env:SCOOP = "D:\tools\scoop"
[Environment]::SetEnvironmentVariable('SCOOP', $env:SCOOP, 'User')

# Then bootstrap
D:\tools\scoop\bin\scoop-boot.ps1 --bootstrap
```

### GitHub Template Download

The script can download templates from GitHub:
```powershell
# Templates are downloaded from:
# https://raw.githubusercontent.com/stotz/scoop-boot/main/etc/environments/template-default.env
```

### Automated Deployment

For automated workstation setup:
```powershell
# setup.ps1
param([string]$ConfigUrl)

# Download scoop-boot
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1" -OutFile "$env:TEMP\scoop-boot.ps1"

# Bootstrap
& "$env:TEMP\scoop-boot.ps1" --bootstrap

# Download company config
Invoke-WebRequest -Uri $ConfigUrl -OutFile "$env:SCOOP\etc\environments\user.default.env"

# Apply
& "$env:SCOOP\bin\scoop-boot.ps1" --apply-env
```

## Project Structure

```
C:\usr\                       # Example Scoop root
├── bin\
│   └── scoop-boot.ps1       # Main script
├── etc\
│   └── environments\        # Environment configurations
│       ├── system.default.env
│       ├── user.default.env
│       └── backup\          # Automatic backups
├── apps\                    # Installed applications
├── buckets\                 # Scoop buckets
├── cache\                   # Download cache
├── persist\                 # Persistent app data
└── shims\                   # Command shims
```

## Supported Technologies

The templates include configurations for:

**Languages:** Java, Python, Node.js, Go, Rust, Ruby, Perl, C/C++, .NET, Kotlin, Scala  
**Build Tools:** Maven, Gradle, Ant, CMake, Make, Ninja, SBT  
**Databases:** PostgreSQL, MySQL/MariaDB, MongoDB, Redis, SQLite, Elasticsearch  
**Web Servers:** Apache, Nginx, Tomcat, Jetty, IIS Express  
**Containers:** Docker, Podman, Kubernetes, Helm  
**Cloud:** AWS CLI, Azure CLI, Google Cloud SDK, Terraform, Ansible  
**CI/CD:** Jenkins, GitLab Runner, GitHub CLI  
**And many more...**

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Development Guidelines

1. **Keep PowerShell 5.1 compatibility**
2. **Maintain order-independent parameters**
3. **Use ASCII-only output** (no Unicode symbols)
4. **All tests must pass** (`--selfTest`)
5. **Update version number** when adding features
6. **Document new features** in README and help text
7. **Use English** for all documentation and comments

### Testing Your Changes

```powershell
# Run self-tests
.\scoop-boot.ps1 --selfTest

# Test parameter parsing
.\scoop-boot.ps1 --help --version --status

# Test with different parameter orders
.\scoop-boot.ps1 --install git --force --bootstrap
.\scoop-boot.ps1 --bootstrap --force --install git
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Acknowledgments

- [Scoop](https://scoop.sh) - The awesome Windows package manager
- [ScoopInstaller](https://github.com/ScoopInstaller) - The Scoop community
- All contributors and users

## Links

- **Repository:** [https://github.com/stotz/scoop-boot](https://github.com/stotz/scoop-boot)
- **Issues:** [https://github.com/stotz/scoop-boot/issues](https://github.com/stotz/scoop-boot/issues)
- **Scoop:** [https://scoop.sh](https://scoop.sh)
- **Scoop GitHub:** [https://github.com/ScoopInstaller/Scoop](https://github.com/ScoopInstaller/Scoop)

---

<div align="center">
Made with ❤️ for the Windows development community
</div>
