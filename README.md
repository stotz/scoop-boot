# scoop-boot

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](bin/)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-lightgrey.svg)](#support-matrix)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](#author--license)

One PowerShell script, `scoop-boot.ps1`, that sets up, configures and tears down a Windows development environment based on the [Scoop](https://scoop.sh) package manager: three commands from a fresh machine to a working tool set, environment variables managed through files, and a reset that leaves your files alone. Everything lives under `C:\usr`.

---

## Quick Setup

From a fresh Windows machine (for example an Azure Virtual Desktop) to a working environment. All commands are PowerShell.

### 0. Prerequisites

- Windows display language: **English (United States)**.
  Settings > Time & Language > Language & region > Windows display language.
  Error messages in English are searchable; localized ones are not.
- Administrator rights for steps 1 and 2. Step 3 runs as a normal user.
- Internet access to `github.com`, `raw.githubusercontent.com` and the download hosts of the Scoop manifests.
  HTTPS is enough; nothing here needs SSH.

### 1. Initialize (PowerShell as Administrator)

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
New-Item -ItemType Directory -Path C:\usr\bin -Force
Invoke-WebRequest -Uri https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1 -OutFile C:\usr\bin\scoop-boot.ps1
C:\usr\bin\scoop-boot.ps1 --admin-init
```

`--admin-init` creates `C:\usr\etc\environments`, `C:\usr\etc\packages`, `C:\tmp`, `C:\devl`
(repositories) and `C:\data` (data, optional tool caches), downloads the other scripts, the
scoop wrapper and the package list (`--update`), writes `system.<host>.<user>.env` and
`user.<host>.<user>.env` from the templates when they do not exist yet, and opens the
system file in Notepad: review paths and tool versions, then save. `system.*` is applied at
Machine scope and is the source of truth; `user.*` holds your additions at User scope.
Running `--admin-init` again keeps everything that exists.

If you run PowerShell as a separate admin account ("run as"), the files are named after that
account; rename them to your regular user name.

### 2. Environment (PowerShell as Administrator)

```powershell
C:\usr\bin\scoop-boot.ps1 --admin-setenv
```

Sets `TMP`/`TEMP` to `C:\tmp`, applies the `system.*` file at Machine scope, then cleans
the User scope and applies the `user.*` file.

### 3. Tools (new PowerShell window, normal user)

```powershell
C:\usr\bin\scoop-boot.ps1 --user-install
```

Bootstraps Scoop, adds the `extras`, `java` and `versions` buckets, installs the package
list (JDK 25, Python 3.14, Node.js, Kotlin, Maven, Gradle, MSYS2/GCC, editors, CLI tools),
imports registry files and cleans the User scope. Takes 15-30 minutes; the window title shows
the progress (`scoop-boot [12/70] kotlin`). If your account can only open elevated shells
(local administrator), add `--force` to skip the question about running as Administrator.

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
the start is refused; `--user-install` reports this as `Failed: gcc (running built exe blocked by ASR)`:

```powershell
'int main(void){return 42;}' | Set-Content C:\tmp\hello.c
gcc C:\tmp\hello.c -o C:\tmp\hello.exe; C:\tmp\hello.exe; $LASTEXITCODE   # 42 when allowed
scoop-boot.ps1 --platform-report                                             # evidence for the platform team (Administrator for the full report)
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
itself changed, run `--admin-setenv` again (Administrator).

### Keeping scoop-boot current

```powershell
scoop-boot.ps1 --update        # downloads bin\* from GitHub; previous copies in backups\scripts-<ts>
scoop-boot.ps1 --platform-report    # what the platform does to the setup: ASR, profile container, TMP
```

`--update` never touches `etc\environments`; those files are yours.

### Checking the platform first

On a managed machine (AVD, VDI, a corporate image) two things outside scoop-boot
decide whether the setup works: Defender's ASR rules, which can refuse every build
output and every new tool version, and a profile container (FSLogix), which limits the
profile size and keeps developer caches on a file share. `--platform-report` reads both
before anything is installed and writes `logs\scoopboot\platform-report-<date>.txt`:
Defender version, ASR rules, exclusions and the blocks of the last 14 days; the profile
container with policy, path, fill level and `redirections.xml` exclusions; TMP in
process, User and Machine scope; the developer caches inside the profile with their
sizes. A Findings block at the end names what to ask the platform team for; with
findings the exit code is 1. The report changes nothing. Run it as Administrator for
the rule and exclusion lists; `--asr-report` still works as an alias.

### Package list

`--user-install` installs what `C:\usr\etc\packages\default.txt` lists, one manifest per line in
install order, `#` for comments, `bucket/name` allowed. `--update` delivers that file; do
not edit it. To change the list on one machine, copy it to
`C:\usr\etc\packages\<hostname>.txt` (lower case): that file replaces `default.txt`
completely and is never touched by `--update`. The bootstrap packages (7-Zip, Git, aria2
and the extractors) are installed before the list and are not part of it.

```powershell
scoop-boot.ps1 --list-packages   # which file, which packages, which have post-install steps; installs nothing
```

A few packages need more than `scoop install` (the VC++ runtime check, the MSYS2/GCC
setup, the `nc`/`netcat` shims, registry imports, tray apps). Those steps run only when
their package is in the list; `--list-packages` marks them.

### Caches outside the user profile (optional)

Gradle, Maven, npm, pip, NuGet, JetBrains indexes and WSL disks all default to
`%USERPROFILE%`. On a roaming or container profile (FSLogix, size quotas) that is the
wrong place. The `system.*` template ends with a commented block that moves them to
`C:\data\caches\<tool>`: uncomment what you need, run `--admin-setenv` again
(Administrator), open a new shell. The block also lists the
one-time commands for the things that are not environment variables (JetBrains
properties files, `wsl --manage <distro> --move`, Docker's disk image location).

### Logs

Every script prints a banner with its version and the first eight digits of its own
SHA-256, and mirrors all console output into a daily log:

```
C:\usr\logs\scoopboot\<yyyyMMdd>.log
2026-10-22T09:21:04 scoop-boot.ps1 --user-install (1.16.0) [INFO] [OK] Installed: maven
```

All commands write to the same file; the second field names the command that produced
the line. Scoop's own messages are included (it runs in-process); output of pacman,
msiexec and reg is not. Each session starts with host, user, admin flag, Windows and
PowerShell version, script hash and arguments. Logs older than 60 days are removed.
`C:\usr\logs` is not a Scoop directory; the reset leaves it alone.

### What belongs to Scoop under C:\usr

Only `apps`, `buckets`, `cache`, `persist`, `shims` and `global`. `bin` and `etc` belong
to scoop-boot. Anything else you put under `C:\usr` (an EDB PostgreSQL, OSGeo4W, your
own `workspace`) is left alone by every script, including the reset; its PATH entries
and variables are yours to maintain. `--admin-setenv` writes `C:\usr\README_scoop_dir_warnings.md`
with the same rules for whoever looks into the directory later.

### Start over

In an Administrator shell:

```powershell
scoop-boot.ps1 --admin-reset                 # full cleanup, asks for confirmation
scoop-boot.ps1 --admin-reset --force         # no prompts
scoop-boot.ps1 --admin-reset --keep-persist  # keep C:\usr\persist (app data, settings)
```

The reset stops processes running from `C:\usr\apps` (and Explorer, which holds shell
extensions; it is restarted), writes a backup to `C:\usr\backups\<timestamp>` (the last
five are kept), removes Scoop's variables and PATH entries, the Scoop directories, registry
entries and shortcuts. `bin`, `etc`, `logs` and everything that is not Scoop's stay, so
the setup starts again at `--admin-init`.

---

## How it works

Two environment files per machine, both in `C:\usr\etc\environments`:
`system.<host>.<user>.env` is applied at Machine scope by `--admin-setenv` (Administrator) and is
the source of truth for `JAVA_HOME`, `PATH` order and the rest; `user.<host>.<user>.env`
is applied at User scope by `--clean-user-scope` (no Administrator) and holds your
additions. Before the Machine file is applied, every Machine PATH entry inside Scoop's
directories is removed, so the file rebuilds the PATH order from scratch.

Scoop itself writes `JAVA_HOME`, `GRADLE_USER_HOME` and PATH entries into the User scope
on every install and update, and Windows resolves User variables before Machine
variables. `--clean-user-scope` removes those entries again (User PATH entries inside
Scoop's directories, User variables whose name the `system.*` file sets) and the scoop
wrapper runs it after every state-changing Scoop command. `--user-install` runs it once
as its last step.

Everything a script prints goes to the daily log, with the script name, mode and
version in front of each line, so that a question about a machine can be answered from
the log rather than from memory.

Environment file syntax, load order and version pinning: [docs/environment-files.md](docs/environment-files.md).

## Commands

`scoop-boot.ps1`, grouped as in `--help`:

```
Setup (Administrator shell unless noted)
--admin-init         1: directories, --update, environment files from the templates, opens the system file
--admin-setenv       2: apply the environment files at Machine scope (Phase 1); --dry-run: show the changes, no Administrator needed
--user-install       3 (normal shell): bootstrap Scoop, install the package list (Phase 2); --force: no question in an elevated shell
--admin-reset        Remove Scoop again; --force skips the prompt, --keep-persist keeps C:\usr\persist

Maintenance
--update             Download the current scripts, the scoop wrapper and etc\packages\default.txt from GitHub
--branch=NAME        With --update: download from a branch and remember it (etc\scoop-boot.branch); --branch=main switches back
--clean-user-scope   Remove Scoop's User-scope overrides, apply user.* files (no Administrator)
--quiet              With --clean-user-scope: one summary line, and only when something changed
--list-packages      Package list in use, status of each package and its post-install steps; installs nothing
--platform-report    Defender/ASR, profile container, TMP: what the platform does to the setup; exit 1 on findings

Environment files
--env-status         Environment files found and their load order
                     (--admin-init creates the host files; copy a template by hand for *.default.env)

Other
--bootstrap          Install Scoop and the bootstrap packages only (part of --user-install)
--self-test          Self-tests (parser, expansion, package list, help)
--version, --help
```

The wrapper adds `scoop upgrade`. The logic lives in `C:\usr\bin\scoop-boot.psm1`;
`scoop-boot.ps1` is the command line and `--update` keeps both current. `--update`,
`--version` and `--help` work even when the module does not load, so a bad download can
always be repaired with `--update`.

## Documents

- [docs/environment-files.md](docs/environment-files.md) - environment files: load order, syntax, list operations, `C:\usr` layout, version pinning, known issues
- [docs/private-bucket.md](docs/private-bucket.md) - fixed releases instead of rolling updates: a private bucket with reviewed manifests

## Requirements

Windows 10 or 11 (x64), PowerShell 5.1 or newer, local Administrator rights for the
`--admin-*` commands. Tested on Windows 11 (Azure Virtual Desktop).

## Author & License

Urs Stotz, MIT License, https://github.com/stotz/scoop-boot

---

[Quick Setup](#quick-setup) | [Documents](#documents)

---
