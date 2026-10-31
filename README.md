# scoop-boot

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](bin/)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-lightgrey.svg)](#requirements)
[![ci](https://github.com/stotz/scoop-boot/actions/workflows/ci.yml/badge.svg)](https://github.com/stotz/scoop-boot/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](#author--license)

One PowerShell script, `scoop-boot.ps1`, that sets up, configures and tears down a Windows development environment based on the [Scoop](https://scoop.sh) package manager: three commands from a fresh machine to a working tool set, environment variables managed through files, and a reset that leaves your files alone. Everything lives under one directory, `C:\usr` in this README; scoop-boot takes its root from wherever its `bin\` folder is.

---

## Quick Setup

From a fresh Windows machine (a laptop, an Azure Virtual Desktop) to a working
environment. All commands are PowerShell; steps 1 and 2 need an Administrator shell,
step 3 a normal one.

### 0. Prerequisites

- Windows display language **English (United States)** (Settings > Time & Language >
  Language & region). Error messages in English are searchable; localized ones are not.
- Local Administrator rights for steps 1 and 2.
- Internet access to `github.com`, `raw.githubusercontent.com` and the download hosts of
  the Scoop manifests. HTTPS is enough; nothing here needs SSH.

### 1. Initialize (PowerShell as Administrator)

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force
New-Item -ItemType Directory -Path C:\usr\bin -Force
Invoke-WebRequest -Uri https://raw.githubusercontent.com/stotz/scoop-boot/main/bin/scoop-boot.ps1 -OutFile C:\usr\bin\scoop-boot.ps1
C:\usr\bin\scoop-boot.ps1 --admin-init                    # the developer workplace (profile devel)
C:\usr\bin\scoop-boot.ps1 --admin-init --profile=devops   # or: infrastructure work
C:\usr\bin\scoop-boot.ps1 --admin-init --profile=java,c++  # or: pick the parts (see "Profiles")
```

`--admin-init` does four things and keeps whatever already exists when run again:

- creates `C:\usr\etc\environments`, `C:\usr\etc\packages` and the directories listed in
  `C:\usr\etc\scoop-boot.conf` (`DIR=` lines; written with the defaults `C:\tmp`,
  `C:\devl` for repositories and `C:\data` for data and tool caches when the file is
  missing, on the drive of the Scoop root);
- downloads the current signed release: the library module, the scoop wrapper, the
  profiles and package lists (see "Releases and `--update`");
- composes `etc\packages\<host>.txt`, `system.<host>.<user>.env` and
  `user.<host>.<user>.env` from the profiles (`--profile=NAMES`; without it `devel`, or
  what `PROFILE=` in `etc\scoop-boot.conf` says from an earlier run);
- opens the system file in Notepad: review paths and tool versions, save, close.

`system.*` is applied at Machine scope and is the source of truth for `JAVA_HOME`, the
`PATH` order and the rest; `user.*` holds your additions at User scope. If you run
PowerShell as a separate admin account ("run as"), the files are named after that
account; rename them to your regular user name.

The first `--update` of a machine prints the fingerprint of the release signing key.
Compare it with this one before trusting the installation:

```
SHA256:ygweazny8W4PyHz5SOOACa6LygoQwm55NFwrgPtSRJI
```

### 2. Environment (PowerShell as Administrator)

```powershell
C:\usr\bin\scoop-boot.ps1 --admin-setenv --dry-run   # what would change, nothing written
C:\usr\bin\scoop-boot.ps1 --admin-setenv             # apply
```

Applies the `system.*` file at Machine scope (including `TMP`/`TEMP`, whose directory
is created if missing), then cleans the User scope and applies the `user.*` file. The
dry run ends with the net effect per scope: changed, new, removed, unchanged variables
and the `PATH` entries that come and go; it needs no Administrator.

### 3. Tools (new PowerShell window, normal user)

```powershell
C:\usr\bin\scoop-boot.ps1 --list-packages   # what the list contains, installs nothing
C:\usr\bin\scoop-boot.ps1 --user-install    # 15-30 minutes
```

Bootstraps Scoop, adds the `extras`, `java` and `versions` buckets, installs the package
list (JDK 25, Python 3.14, Node.js, Kotlin, Maven, Gradle, MSYS2/GCC, editors, CLI tools),
runs the post-install steps (default JDK, GCC smoke test, registry imports, tray apps)
and cleans the User scope once at the end. The window title shows the progress
(`scoop-boot [12/70] kotlin`). If your account can only open elevated shells (local
administrator), add `--force` to skip the question about running as Administrator. A
second run installs what is missing and reports the rest as already installed.

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

### 5. WSL and Debian (optional)

A Debian distribution in WSL 2 next to the Windows tools, with build tools, Python,
Java, the usual command line tools and Claude Code. Both commands show their plan with
`--dry-run` first and install nothing then.

```powershell
C:\usr\bin\scoop-boot.ps1 --wsl-install --dry-run   # which wsl.exe commands would run
C:\usr\bin\scoop-boot.ps1 --wsl-install             # Administrator: WSL and Debian, not started
wsl -d Debian                                       # first start: Linux user and password, then exit
C:\usr\bin\scoop-boot.ps1 --wsl-setup --dry-run     # apt-get resolves every package in simulation mode
C:\usr\bin\scoop-boot.ps1 --wsl-setup               # normal shell: apt packages and Claude Code inside Debian
```

`--wsl-install` runs `wsl --install --no-distribution` when WSL 2 is missing (restart
Windows, then run it again) and `wsl --install -d Debian --no-launch` for the
distribution; `--distro=NAME` takes another one. On an Azure Virtual Desktop WSL 2
needs a VM size with nested virtualization.

`--wsl-setup` runs `etc\wsl\debian-setup.sh` inside the distribution, reading it and
the package list from `C:\usr` under `/mnt/c`: the missing packages of
`etc\packages\debian.txt` with `--no-install-recommends` (sudo asks for the Linux
password), `fd` and `bat` under their usual names (Debian calls them `fdfind` and
`batcat`), and Claude Code with the official installer (`https://claude.ai/install.sh`,
skipped when `claude` exists; `--no-claude` leaves it out). Running it again installs
only what is missing.

On a WSL someone already uses, `--wsl-setup` only adds: the missing packages, installed
with `apt-get --no-remove` (apt stops instead of removing a package), no `upgrade`, no
`autoremove`; files already in `~/.local/bin` and an existing `claude` stay as they
are. The dry run reports "N installed, 0 removed" and fails when apt would remove
anything. Ubuntu and other Debian derivatives work too (`--distro=Ubuntu-24.04`);
when Debian is missing, `--wsl-setup` names the installed distributions. `etc\packages\<host>.debian.txt` replaces the delivered list on
one machine, as `<host>.txt` does for Scoop.

### Profiles

A profile is one part of a workplace: its Scoop packages, its environment variables
and, when it has one, its apt packages for WSL. `--admin-init` and `--profile` compose
the selected profiles into this machine's files; the names can be combined freely, in
any order, and `base` (Git, OpenSSH, the directory conventions, locale) is always part
of it.

```powershell
C:\usr\bin\scoop-boot.ps1 --list-profiles                        # what etc\profiles delivers, with the packages
C:\usr\bin\scoop-boot.ps1 --profile=java,c++,python --dry-run     # the files that would be composed
C:\usr\bin\scoop-boot.ps1 --profile=devops --force                # replace the host files (the old ones stay as .bak)
```

Single profiles: `base`, `desktop` (browsers, editors, Windows Terminal, file and
screenshot tools), `ide` (JetBrains Toolbox), `cli`, `svn`, `java` (Temurin JDK 25,
Maven, Gradle, Ant, Kotlin), `java8`, `java11`, `java17`, `java21` (one more JDK each,
reachable as `JAVA_HOME_NN_X64` for toolchains, not on the PATH), `node`, `perl`,
`python`, `c++` (MSYS2/GCC, make, cmake,
ninja, vcpkg), `tortoisegit` (from the nonportable bucket: an MSI into Program Files
whose manifest refuses a normal shell: `--user-install` lists it at the end with the
`scoop install` command for an Administrator shell or `sudo scoop install`), `docs`,
`network`, `netdiag`, `db`,
`dbclients`, `server`, `azure`,
`azure-tools`, `iac` (Terraform), `pwsh`, `automation`, `media`. Two virtual profiles
bundle them: `devel`, the developer workplace this project was written for (and the
content of `default.txt`), and `devops` for infrastructure work (Azure CLI, AzCopy,
Service Bus and Storage Explorer, Terraform with tflint, terraform-docs and trivy,
network diagnostics, remote access, database clients; for Debian ansible and the usual
network tools) instead of compilers and IDEs.

The composed files (`etc\packages\<host>.txt`, `<host>.debian.txt`,
`etc\environments\system.<host>.<user>.env`, `user.<host>.<user>.env`) are yours: edit
them freely, `--update` never touches them. Existing files are kept unless `--force`.
The profile names are recorded as `PROFILE=` in `etc\scoop-boot.conf`. The profiles
themselves live in `etc\profiles` (one directory per profile with `packages.txt`,
`system.env`, `user.env`, `debian.txt`; `profiles.conf` names them and defines the
virtual ones) and are delivered by `--update`; a new profile is a pull request.

### Moving from an existing Scoop machine

If an older machine already has the packages you want, export its list before you
set up the new one. On the old machine, normal shell:

```powershell
C:\usr\bin\scoop-boot.ps1 --export=oldScoopEnv
```

This writes `C:\usr\etc\exports\oldScoopEnv.txt`: every installed package as
`bucket/name` with version and hold status as a comment, and the buckets with their
URLs. Copy that file to `C:\usr\etc\exports\` on the new machine and, after step 1:

```powershell
C:\usr\bin\scoop-boot.ps1 --import=oldScoopEnv --dry-run   # what would be added
C:\usr\bin\scoop-boot.ps1 --import=oldScoopEnv             # append to etc\packages\<host>.txt
```

Everything the default list lacks is appended to this machine's package list under a
dated `# import` header; buckets Scoop does not know by name get a `# bucket NAME URL`
line that `--user-install` adds in Step 2. Step 3 then installs the combined list. A
second import of the same file adds nothing. `--import=oldScoopEnv --replace` goes the
other way: the host list is written from the export alone, so the new machine gets
exactly the old machine's packages (the previous list is kept as `.bak`).

Why not `scoop export` and `scoop import`? Scoop's import installs straight away, past
the package list: after the next `--admin-reset` those packages are gone and
`--list-packages` never knew them. scoop-boot's export is a package list, the same
format as `etc\packages\default.txt`, read from the files Scoop keeps under `apps\` and
`buckets\` (not from `scoop list`, which truncates long names), and the install stays
with `--user-install`.

Environment files and `etc\scoop-boot.conf` are not part of the export: they are named
after the host and should be reviewed on a new machine, not copied blindly.

---

## Why the scoop wrapper

`C:\usr\bin` is on `PATH` before `C:\usr\shims`, so `bin\scoop.ps1` (with `scoop.cmd`
for cmd and `scoop` for Git Bash) is found before Scoop's own shim. It forwards every
command unchanged to the real Scoop and, after `install`, `update`, `uninstall`,
`reset`, `cleanup`, `hold` and `unhold`, runs `scoop-boot.ps1 --clean-user-scope --quiet`.

The problem it solves: Scoop writes environment variables into the **User** scope on
every install and update, and Windows resolves User variables before Machine
variables. Take the JDKs. The `system.*` file sets `JAVA_HOME` to Temurin 25 at Machine
scope. Then you run `scoop install temurin11-jdk` for an old project: the manifest sets
`JAVA_HOME` to JDK 11 at User scope and puts its `bin` on the User `PATH`. From that
moment every new shell says `java -version` is 11, Gradle and Maven build with 11, and
nothing in the `.env` file changed. The same happens with `scoop update` (it re-adds
`C:\usr\shims` and the `current\bin` of every updated tool to the User `PATH`) and
with `scoop reset`. The wrapper removes those User entries again right after the
command, so the `.env` file stays the only place that decides which JDK is the default;
the other JDKs stay installed and reachable through `JAVA_HOME_11_X64` and friends.
You see one line only when something was cleaned:

```
[scoop-boot] user scope cleaned (3 change(s) after Scoop wrote to it; details in C:\usr\logs\scoopboot\20261009.log)
```

One extra command that Scoop does not have:

```powershell
scoop upgrade      # = scoop update; scoop update -a; scoop cleanup -a; clean user scope
```

Bypass when needed: `C:\usr\shims\scoop ...`, or `$env:SCOOP_BOOT_WRAPPER = 'off'`.
Manual fallback is `scoop-boot.ps1 --clean-user-scope`. When the `system.*` file itself
changed, run `--admin-setenv` again (Administrator).

## Releases and `--update`

```powershell
scoop-boot.ps1 --update    # the current signed release; previous copies in backups\scripts-<ts>
scoop-boot.ps1 --version   # installed release and whether it was verified
```

A release is a Git tag (`v0021`, ...). It carries `etc\release.manifest`, the SHA-256 of
every delivered file, signed with an SSH key (`etc\release.manifest.sig`). `--update`
reads `etc\LATEST` on `main` to learn the current tag, verifies the manifest with the
key in `C:\usr\etc\allowed_signers`, downloads every file from the tag and compares it
with the manifest; only when all of that passes does it replace anything. A failed check
leaves the installation untouched and says why. `allowed_signers` arrives once, on the
first `--update` of a machine (fingerprint above), and is never replaced automatically.
`--update` never touches `etc\environments`, `etc\scoop-boot.conf` or a host package
list; those files are yours.

`raw.githubusercontent.com` caches `etc/LATEST` for up to five minutes: an `--update`
right after a release can still report the previous one; run it again a few minutes
later.

`--update --branch=NAME` downloads a branch head without any check, for testing on one
machine; every run says so until `--update --branch=main`. A branch that was merged and
deleted answers 404; the same command brings the machine back to the release.

## Checking the platform first

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

## Package list

`--user-install` installs what `C:\usr\etc\packages\<hostname>.txt` lists (composed by
`--admin-init` from the profiles), or `default.txt` (the `devel` profile, delivered by
`--update`) when no host file exists: one manifest per line in install order, `#` for
comments, `bucket/name` allowed. The host file replaces `default.txt` completely and is
never touched by `--update`; `--profile` and `--import` write it, editing it by hand
works the same way. The
bootstrap packages (7-Zip, Git, aria2 and the extractors) are installed before the list
and are not part of it. A line `# bucket NAME URL` in the list adds a bucket in Step 2,
which is how a private bucket comes in (see [docs/private-bucket.md](docs/private-bucket.md)).

A few packages need more than `scoop install` (the VC++ runtime check, the MSYS2/GCC
setup, the `nc`/`netcat` shims, registry imports, tray apps). Those steps run only when
their package is in the list; `--list-packages` marks them.

## Caches outside the user profile (optional)

Gradle, Maven, npm, pip, NuGet, JetBrains indexes and WSL disks all default to
`%USERPROFILE%`. On a roaming or container profile (FSLogix, size quotas) that is the
wrong place. The composed `system.*` file ends with a commented block that moves them to
`C:\data\caches\<tool>`: uncomment what you need, run `--admin-setenv` again
(Administrator), open a new shell. The block also lists the one-time commands for the
things that are not environment variables (JetBrains properties files,
`wsl --manage <distro> --move`, Docker's disk image location).

## Logs

Every command prints a banner with its version and the first eight digits of its own
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

## What belongs to Scoop under C:\usr

Only `apps`, `buckets`, `cache`, `persist`, `shims` and `global`. `bin` and `etc` belong
to scoop-boot. Anything else you put under `C:\usr` (an EDB PostgreSQL, OSGeo4W, your
own `workspace`) is left alone by every command, including the reset; its PATH entries
and variables are yours to maintain. `--admin-setenv` writes `C:\usr\README_scoop_dir_warnings.md`
with the same rules for whoever looks into the directory later.

## Start over

In an Administrator PowerShell started from the Start menu, not from a Windows
Terminal or Git Bash that Scoop installed: those run from `apps\` and are stopped
with everything else, which would end the shell halfway. The reset checks this and
refuses to run inside one.

```powershell
scoop-boot.ps1 --admin-reset                 # full cleanup, asks for confirmation
scoop-boot.ps1 --admin-reset --force         # no prompts
scoop-boot.ps1 --admin-reset --keep-persist  # keep C:\usr\persist (app data, settings)
```

The reset stops the processes that run from or hold Scoop's directories (`apps`, and
`persist` unless kept: JetBrains Toolbox installs its IDEs there; plus Explorer,
which holds shell extensions), writes a backup to `C:\usr\backups\<timestamp>` (the last
five are kept), removes Scoop's variables and PATH entries, the Scoop directories, registry
entries and shortcuts. `bin`, `etc`, `logs` and everything that is not Scoop's stay, so
the setup starts again at `--admin-init`. At the end Explorer is told to reload the
environment from the registry, so a shell opened from the Start menu afterwards sees
the cleaned environment without logging off. Exit code 1 when a directory could
not be removed; the output names it, the command to remove it by hand, and the
programs that still hold it (a shell extension's DLL loaded into a file manager, a
shell whose working directory is inside): those are not Scoop's and are left to you.

---

## How it works

Two environment files per machine, both in `C:\usr\etc\environments`:
`system.<host>.<user>.env` is applied at Machine scope by `--admin-setenv` (Administrator) and is
the source of truth for `JAVA_HOME`, `PATH` order and the rest; `user.<host>.<user>.env`
is applied at User scope by `--clean-user-scope` (no Administrator) and holds your
additions. Before the Machine file is applied, every Machine PATH entry inside Scoop's
directories is removed, so the file rebuilds the PATH order from scratch.
`--clean-user-scope` removes Scoop's User-scope entries again (see "Why the scoop
wrapper"); `--user-install` runs it once as its last step, the wrapper after every
state-changing Scoop command.

Everything a command prints goes to the daily log, with the command, mode and version
in front of each line, so that a question about a machine can be answered from the log
rather than from memory.

Environment file syntax, load order and version pinning: [docs/environment-files.md](docs/environment-files.md).

## Commands

`scoop-boot.ps1`, grouped as in `--help`:

```
Setup (Administrator shell unless noted)
--admin-init         1: directories, --update, package list and environment files from the profiles, opens the system file
--profile=NAMES      With --admin-init: the profiles for this machine (default: PROFILE in etc\scoop-boot.conf, else devel)
--admin-setenv       2: apply the environment files at Machine scope (Phase 1); --dry-run: net effect, no Administrator needed
--user-install       3 (normal shell): bootstrap Scoop, install the package list (Phase 2); --force: no question in an elevated shell
--admin-reset        Remove Scoop again; --force skips the prompt, --keep-persist keeps C:\usr\persist

Maintenance
--update             Install the current signed release: scripts, scoop wrapper, package lists, profiles, etc\wsl (the files of etc\release.files)
--branch=NAME        With --update: download from a branch and remember it (etc\scoop-boot.branch); --branch=main switches back
--clean-user-scope   Remove Scoop's User-scope overrides, apply user.* files (no Administrator)
--quiet              With --clean-user-scope: one summary line, and only when something changed
--list-packages      Package list in use, status of each package and its post-install steps; installs nothing
--profile=NAMES      Compose etc\packages\HOSTNAME.txt and the environment files from profiles (devel, devops, java,c++,...); --dry-run, --force
--list-profiles      The profiles etc\profiles delivers, single and virtual, with their packages
--platform-report    Defender/ASR, profile container, TMP: what the platform does to the setup; exit 1 on findings
--export[=NAME]      Installed packages and buckets to etc\exports\NAME.txt (default: hostname)
--import=NAME|FILE   Append what this machine's list lacks to etc\packages\HOSTNAME.txt; --dry-run shows it; --replace clones the list

WSL (optional, after the setup)
--wsl-install        Administrator: WSL and Debian, not started; --distro=NAME for another one; --dry-run shows the commands
--wsl-setup          Normal shell: apt packages of etc\packages\debian.txt and Claude Code inside Debian; --no-claude, --dry-run

Environment files
--env-status         Environment files found and their load order
                     (--admin-init and --profile compose the host files; a *.default.env for all hosts is written by hand)

Other
--bootstrap          Install Scoop and the bootstrap packages only (part of --user-install)
--self-test          Self-tests (parser, expansion, package list, import, export, dry run, profiles, help, static check)
--version, --help
```

The wrapper adds `scoop upgrade`. The logic lives in `C:\usr\bin\scoop-boot.psm1`;
`scoop-boot.ps1` is the command line and `--update` keeps both current. `--update`,
`--version` and `--help` work even when the module does not load, so a bad download can
always be repaired with `--update`. Exit codes: 0 when the command did what it says,
1 otherwise (a failed package, a directory left behind, findings in the platform
report, an unknown option).

## Development

Work happens on a branch; `main` carries tested states only.

```powershell
tools\test.ps1               # parse check, --self-test, profiles and dry run, the setup in fake mode, command line
```

`tools\test.ps1` runs on Windows PowerShell 5.1 and on pwsh, Linux included. It
composes the `devel` profile in a scratch copy of `bin\` and `etc\` and runs the
environment dry run against it (the registry is replaced by the dry-run store), checks
`etc\release.files` against the tree, and then runs the whole setup in fake mode:
with `SCOOPBOOT_FAKE=1` the commands work against a simulated Scoop (the same directory
layout, `apps\<name>\current` with the JSON files Scoop writes, the User-scope writes
Scoop makes) and a registry kept in `etc\fake\registry.json`, with no processes and
nothing installed, so `--admin-init --profile=java,python`, `--admin-setenv`,
`--user-install` (twice), the scoop wrapper, `--export`, `--import --dry-run`,
`--list-packages` and `--admin-reset --force` run through on any platform with the
expected state after each step. The fake mode is also there for trying a change by
hand: `$env:SCOOPBOOT_FAKE = '1'` in a shell, a scratch root with `bin\` and `etc\`,
and every command behaves as on a machine without Scoop. The same script runs in
GitHub Actions (`.github/workflows/ci.yml`)
on `ubuntu-latest` and `windows-latest` for every push and pull request, together with
PSScriptAnalyzer (errors), ShellCheck for the shell scripts and `etc/wsl/debian-setup.sh`
in `debian:stable` and `ubuntu:24.04` containers, each fresh and as an existing
distribution with packages already installed: a wrong package name must fail the dry
run, the dry run must report 0 removals, after the installation every package that was
there before must still be there (and an own `~/.local/bin/fd` untouched), a second run
must find nothing missing, and the tools of the list must start. For a release
tag the workflow also verifies the manifest signature and compares every hash with the
committed file. From Git Bash, call `powershell -File tools/test.ps1` with the POSIX
path; a Windows path with backslashes is eaten by the shell.

To test a branch on one machine: `scoop-boot.ps1 --update --branch=NAME`, and
`--update --branch=main` when done. Releases are cut on `main` with
`tools/release.sh vNNNN` (Git Bash): manifest from the committed blobs, SSH signature,
`etc/LATEST`, commit, tag, push. The signing key's fingerprint must appear in this
README (above); a new key is a new trust anchor and is changed on purpose. A run that
fails after the manifest was written (a mistyped passphrase) restores the manifest and
the previous signature, so the next run starts from a clean tree.

## Documents

- [docs/environment-files.md](docs/environment-files.md) - environment files: load order, syntax, list operations, `C:\usr` layout, version pinning, known issues
- [docs/private-bucket.md](docs/private-bucket.md) - fixed releases instead of rolling updates: a private bucket with reviewed manifests

## Requirements

Windows 10 or 11 (x64), PowerShell 5.1 or newer, local Administrator rights for the
`--admin-*` commands. Tested on Windows 11 (laptop and Azure Virtual Desktop).

## Author & License

Urs Stotz, MIT License, https://github.com/stotz/scoop-boot

---

[Quick Setup](#quick-setup) | [Documents](#documents)

---
