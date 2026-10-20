# scoop-boot

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](bin/)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-lightgrey.svg)](#support-matrix)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](#author--license)

Three PowerShell scripts that set up, configure and tear down a Windows development environment based on the [Scoop](https://scoop.sh) package manager. Everything lives under `C:\usr`.

| Script                             | Version | Purpose                                              |
|------------------------------------|---------|------------------------------------------------------|
| `bin/scoop-boot.ps1`               | 1.14.2  | Bootstrap Scoop, manage environment variables (.env) |
| `bin/scoop-complete-install.ps1`   | 2.10.1  | Two-phase installation of the full tool set          |
| `bin/scoop-complete-reset.ps1`     | 2.6.0   | Remove everything again (processes, files, registry) |

---

## Quick Setup

From a fresh Windows machine (for example an Azure Virtual Desktop) to a working environment. All commands are PowerShell.

### 0. Prerequisites

- Windows display language: **English (United States)**.
  Settings > Time & Language > Language & region > Windows display language.
  Error messages in English are searchable; localized ones are not.
- Administrator rights for phase 1. Phase 2 runs as a normal user.
- Internet access to `github.com`, `raw.githubusercontent.com` and the download hosts of the Scoop manifests.
  HTTPS is enough; nothing here needs SSH.

### 1. Directories, scripts and environment file (PowerShell as Administrator)

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force

New-Item -ItemType Directory -Path C:\usr\bin -Force
New-Item -ItemType Directory -Path C:\usr\etc\environments -Force
New-Item -ItemType Directory -Path C:\tmp -Force
New-Item -ItemType Directory -Path C:\devl -Force    # workspace for repositories, not used by scoop-boot
New-Item -ItemType Directory -Path C:\data -Force    # data and optional tool caches (DATA in the env file)

# scoop-boot.ps1 fetches the other scripts and the scoop wrapper itself
$base = "https://raw.githubusercontent.com/stotz/scoop-boot/main"
Invoke-WebRequest -Uri "$base/bin/scoop-boot.ps1" -OutFile C:\usr\bin\scoop-boot.ps1
C:\usr\bin\scoop-boot.ps1 --update

# Environment files, named after this host and user (lowercase):
# system.* = Machine scope (the source of truth), user.* = User scope (your additions)
$envName  = "$($env:COMPUTERNAME.ToLower()).$($env:USERNAME.ToLower()).env"
$envFile  = "C:\usr\etc\environments\system.$envName"
$userFile = "C:\usr\etc\environments\user.$envName"
Invoke-WebRequest -Uri "$base/etc/environments/system.hostname.username.env" -OutFile $envFile
Invoke-WebRequest -Uri "$base/etc/environments/user.hostname.username.env"   -OutFile $userFile

# Optional: review paths and tool versions before applying.
# Full path on purpose: Git's usr\bin (in PATH once Git is installed) contains an
# extensionless script named 'notepad', and PowerShell would hand it to ShellExecute
# ("Select an app to open 'notepad'").
C:\Windows\System32\notepad.exe $envFile
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

A compiler that runs is not the same as a program that runs. On machines with endpoint
security that blocks unknown executables (Defender ASR rule 01443614), the build works and
the start is refused; Phase 2 reports this as `Failed: gcc (running built exe blocked by ASR)`:

```powershell
'int main(void){return 42;}' | Set-Content C:\tmp\hello.c
gcc C:\tmp\hello.c -o C:\tmp\hello.exe; C:\tmp\hello.exe; $LASTEXITCODE   # 42 when allowed
scoop-boot.ps1 --asr-report                                                  # evidence for the security team (Administrator for the full report)
```

### Keeping it correct: the scoop wrapper

Scoop writes `JAVA_HOME`, `GRADLE_USER_HOME`, `ANT_HOME`, ... and PATH entries into the
User scope on every install and update. Windows resolves User variables before Machine
variables, so the last installed JDK would silently win over the `.env` file.

`C:\usr\bin` is on PATH before `C:\usr\shims`, so `bin\scoop.ps1` (with `scoop.cmd` for
cmd and `scoop` for Git Bash) is found before Scoop's own shim. It forwards every
command to the real Scoop and, after `install`, `update`, `uninstall`, `reset`,
`cleanup`, `hold` and `unhold`, runs `scoop-boot.ps1 --clean-user-scope --quiet`.
You see one line only when something was cleaned:

```
[scoop-boot] user scope cleaned (3 change(s) after Scoop wrote to it; details in C:\usr\logs\scoopboot\20261009.log)
```

One extra command that Scoop does not have:

```powershell
scoop upgrade      # = scoop update; scoop update -a; scoop cleanup -a; clean user scope
```

Bypass when needed: `C:\usr\shims\scoop ...`, or `$env:SCOOP_BOOT_WRAPPER = 'off'`.
Manual fallback is still `scoop-boot.ps1 --clean-user-scope`. When the `system.*` file
itself changed, run Phase 1 again (`-SetEnvironment`, as Administrator).

### Keeping scoop-boot current

```powershell
scoop-boot.ps1 --update        # downloads bin\* from GitHub; previous copies in backups\scripts-<ts>
scoop-boot.ps1 --asr-report    # Defender/ASR rules, exclusions, blocks of the last 14 days
```

`--update` never touches `etc\environments`; those files are yours. `--asr-report`
writes `logs\scoopboot\asr-report-<date>.txt`, the file to attach when asking the
security team for an exclusion.

### Caches outside the user profile (optional)

Gradle, Maven, npm, pip, NuGet, JetBrains indexes and WSL disks all default to
`%USERPROFILE%`. On a roaming or container profile (FSLogix, size quotas) that is the
wrong place. The `system.*` template ends with a commented block that moves them to
`C:\data\caches\<tool>`: uncomment what you need, run Phase 1 again
(`-SetEnvironment`, as Administrator), open a new shell. The block also lists the
one-time commands for the things that are not environment variables (JetBrains
properties files, `wsl --manage <distro> --move`, Docker's disk image location).

### Logs

Every script prints a banner with its version and the first eight digits of its own
SHA-256, and mirrors all console output into a daily log:

```
C:\usr\logs\scoopboot\<yyyyMMdd>.log
2026-10-08T13:21:04 scoop-complete-install.ps1 -InstallTools (2.9.0) [INFO] [OK] Installed: maven
```

Phase 1 (admin) and Phase 2 (user) write to the same file; the script field carries
the mode. Scoop's own messages are included (it runs in-process); output of pacman,
msiexec and reg is not. Each session starts with host, user, admin flag, Windows and
PowerShell version, script hash and arguments. Logs older than 60 days are removed.
`C:\usr\logs` is not a Scoop directory; the reset leaves it alone.

### What belongs to Scoop under C:\usr

Only `apps`, `buckets`, `cache`, `persist`, `shims` and `global`. `bin` and `etc` belong
to scoop-boot. Anything else you put under `C:\usr` (an EDB PostgreSQL, OSGeo4W, your
own `workspace`) is left alone by every script, including the reset; its PATH entries
and variables are yours to maintain. Phase 1 writes `C:\usr\README_scoop_dir_warnings.md`
with the same rules for whoever looks into the directory later.

### Start over

```powershell
C:\usr\bin\scoop-complete-reset.ps1               # full cleanup, asks for confirmation
C:\usr\bin\scoop-complete-reset.ps1 -Force        # no prompts
C:\usr\bin\scoop-complete-reset.ps1 -KeepPersist  # keep C:\usr\persist (app data, settings)
```

The reset stops processes running from `C:\usr\apps` (and Explorer, which holds shell
extensions; it is restarted), writes a backup to `C:\usr\backups\<timestamp>` (the last
five are kept), removes Scoop's variables and PATH entries, the Scoop directories, registry
entries and shortcuts. `bin`, `etc`, `logs` and everything that is not Scoop's stay.

---

## How it works

Two environment files per machine, both in `C:\usr\etc\environments`:
`system.<host>.<user>.env` is applied at Machine scope by Phase 1 (Administrator) and is
the source of truth for `JAVA_HOME`, `PATH` order and the rest; `user.<host>.<user>.env`
is applied at User scope by `--clean-user-scope` (no Administrator) and holds your
additions. Before the Machine file is applied, every Machine PATH entry inside Scoop's
directories is removed, so the file rebuilds the PATH order from scratch.

Scoop itself writes `JAVA_HOME`, `GRADLE_USER_HOME` and PATH entries into the User scope
on every install and update, and Windows resolves User variables before Machine
variables. `--clean-user-scope` removes those entries again (User PATH entries inside
Scoop's directories, User variables whose name the `system.*` file sets) and the scoop
wrapper runs it after every state-changing Scoop command. Phase 2 runs it once as its
last step.

Everything a script prints goes to the daily log, with the script name, mode and
version in front of each line, so that a question about a machine can be answered from
the log rather than from memory.

Environment file syntax, load order and version pinning: [docs/environment-files.md](docs/environment-files.md).

## Commands

`scoop-boot.ps1`:

```
--bootstrap          Install Scoop, Git, 7-Zip, aria2, extractors, main and extras buckets
--apply-env          Apply the environment files (system.* needs Administrator), then clean the User scope
--clean-user-scope   Remove Scoop's User-scope overrides, apply user.* files (no Administrator)
--quiet              With --clean-user-scope: one summary line, and only when something changed
--dry-run            With --apply-env: show the changes without applying them
--update             Download the current scripts and the scoop wrapper from GitHub (bin\ only)
--asr-report         Defender/ASR rules, exclusions and blocks of the last 14 days to logs\scoopboot\
--status             Scoop and environment overview
--env-status         Environment files found and their load order
--environment        Current environment variables
--init-env=FILE      Create an environment file from the template
--install APP...     Install applications through Scoop
--suggest            Suggested applications
--selfTest           Self-tests of the environment file parser
--version, --help
```

`scoop-complete-install.ps1 -SetEnvironment` (Administrator) and `-InstallTools` (user);
`scoop-complete-reset.ps1 [-Force] [-KeepPersist]`; and the wrapper's `scoop upgrade`.

## Documents

- [docs/environment-files.md](docs/environment-files.md) - environment files: load order, syntax, list operations, `C:\usr` layout, version pinning, known issues
- [docs/private-bucket.md](docs/private-bucket.md) - fixed releases instead of rolling updates: a private bucket with reviewed manifests

## Requirements

Windows 10 or 11 (x64), PowerShell 5.1 or newer, local Administrator rights for Phase 1
and the reset. Tested on Windows 11 (Azure Virtual Desktop).

## Author & License

Urs Stotz, MIT License, https://github.com/stotz/scoop-boot

---

[Quick Setup](#quick-setup) | [Documents](#documents)

---
