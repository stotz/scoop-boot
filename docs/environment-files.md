# Environment Files

[README.md](../README.md)  

---

How scoop-boot manages environment variables: which files exist, in which order they
are applied, what the syntax allows, where Scoop puts things under `C:\usr`, and how to
keep a tool at a fixed version.

## Files and load order

All files live in `C:\usr\etc\environments`. The host name and user name in the file
name are lower case (`$env:COMPUTERNAME`, `$env:USERNAME`).

```
system.default.env              Machine scope, all hosts              needs Administrator
system.<host>.<user>.env        Machine scope, this host and user     needs Administrator, source of truth
user.default.env                User scope, all hosts
user.<host>.<user>.env          User scope, this host and user        your additions
```

`--apply-env` (Phase 1) applies the `system.*` files in that order, then calls
`--clean-user-scope`, which applies the `user.*` files. `--clean-user-scope` on its own
applies only the `user.*` files and needs no Administrator.

Before the `system.*` files are applied, every Machine PATH entry inside Scoop's
directories (`apps`, `buckets`, `cache`, `persist`, `shims`, `global`) is removed. The
files therefore define the complete PATH order; nothing from an earlier run survives.
`--clean-user-scope` removes User PATH entries inside those directories and User
variables whose name a `system.*` file sets, because Windows resolves User before
Machine and Scoop writes both on every install and update.

A file name that does not start with `system.` or `user.` is ignored, with a warning.

## Syntax

One operation per line. Names are upper case (`[A-Z_][A-Z0-9_]*`). Blank lines and
lines starting with `#` are ignored. Values are taken as written, without quotes.

```ini
JAVA_HOME=C:\usr\apps\temurin25-jdk\current     # set
PATH+=$JAVA_HOME\bin                            # prepend to a list (highest priority)
PATH=+$USERPROFILE\tools                        # append to a list (lowest priority)
PATH-=C:\old\java\bin                           # remove from a list (exact match)
-OLD_JAVA_HOME                                  # delete the variable
```

The list operations work for every semicolon-separated variable, not only `PATH`:

```ini
PERL5LIB+=$PERL_HOME\perl\lib
PYTHONPATH=+$USERPROFILE\python\libs
CLASSPATH-=C:\old\libs\outdated.jar
PSModulePath+=$SCOOP\modules
```

### Variable expansion

`$NAME` and `${NAME}` are expanded when the line is applied. `$SCOOP` is `C:\usr`,
`$USERPROFILE`, `$USERNAME` and `$HOSTNAME` come from the running session, every other
name is read from the registry: Machine first, then User, then the process. Two
consequences:

- A variable must be set before it is used. `MSYS2_HOME=...` on one line,
  `PATH+=$MSYS2_HOME\usr\bin` on a later line, works; the reverse order writes the
  literal `$MSYS2_HOME` and a warning is printed.
- `--dry-run` cannot expand a variable that the same file defines, because nothing is
  written during a dry run. The warning there is expected.

### PATH order

Later `PATH+=` lines win, because each one prepends. The template therefore lists
low-priority entries first and ends with `$SCOOP\shims` and `$SCOOP\bin`, so that the
scoop wrapper in `bin` is found before Scoop's own shim. `ucrt64\bin` of MSYS2 must come
after Git and Perl in the file (and therefore before them in the PATH): both ship older
`libstdc++-6.dll`, `libgcc_s_seh-1.dll` and `libwinpthread-1.dll`, and if those are found
first, `cc1.exe` fails with exit code -1073741511 (`STATUS_ENTRYPOINT_NOT_FOUND`).

### Templates

`etc/environments/system.hostname.username.env` is the Machine template the Quick Setup
downloads; the comment at its end lists the optional cache relocation (Gradle, Maven,
npm, pip, NuGet, JetBrains, WSL) for machines with roaming or container profiles.
`etc/environments/user.hostname.username.env` is the User template. `template-default.env`
is the long form with every tool scoop-boot knows, as a reference for `--init-env`.

Identity values (name, mail addresses) do not belong in these templates; they belong in
your own `user.<host>.<user>.env`, where scripts can read them.

## What is where under C:\usr

```
C:\usr\
  apps\<app>\<version>\      one directory per installed version
  apps\<app>\current         junction to the active version; "scoop reset <app>" moves it
  buckets\<bucket>\bucket\   manifests (JSON) of each bucket, a git checkout
  cache\                     downloaded installers; "scoop cache rm *" frees the space
  persist\<app>\             app data that survives updates (settings, profiles)
  shims\                     one small exe per command, pointing at apps\<app>\current
  global\                    global installs (scoop-boot does not use them)
  bin\                       scoop-boot scripts and the scoop wrapper
  etc\environments\          the environment files and their backups
  logs\scoopboot\            daily logs, ASR reports
  backups\                   reset backups and previous script versions (--update)
```

`apps`, `buckets`, `cache`, `persist`, `shims` and `global` belong to Scoop and are
removed by the reset. The rest belongs to scoop-boot or to you. Anything else placed
under `C:\usr` (a database server, a GIS distribution, a workspace) is left alone by
every script; its PATH entries and variables are yours to maintain.

## Fixed versions

Scoop updates to the newest manifest on every `scoop update -a`. Three ways to keep a
tool where it is:

```powershell
scoop hold gradle            # scoop update skips it; "scoop list" shows [held]
scoop unhold gradle

scoop reset gradle@9.8.2     # switch "current" back to an installed older version
scoop list gradle            # shows the versions on disk

scoop bucket add versions    # alternative manifests with a version in the name
scoop install python313      # python313 and python314 can be installed side by side
```

`hold` protects one machine. For a team that wants the same, reviewed versions
everywhere, a private bucket is the better tool: [private-bucket.md](private-bucket.md).

Note that the environment file names the tool by its manifest (`temurin25-jdk`,
`python314`); switching to another manifest means changing the file and running Phase 1
again.

## Known issues

- `pip` broken after a Python update: `python -m ensurepip --upgrade`, then
  `python -m pip install --upgrade pip`. `persist\python314\Lib\site-packages` keeps
  the installed packages.
- Git credentials after an update: they are in the Windows Credential Manager, not in
  Scoop's directories; `git config --global credential.helper manager` if the setting
  was lost.
- `gcc` compiles but the program does not start, Windows reports "Your administrator
  caused Windows Security to block this action": Defender ASR rule 01443614 on this
  machine. `scoop-boot.ps1 --asr-report` collects the evidence; the fix is a path
  exclusion by whoever manages Defender.
- `gcc` produces nothing and `cc1.exe` exits with -1073741511: DLL shadowing, see PATH
  order above; `where.exe libstdc++-6.dll` must list `ucrt64\bin` first.
- "The file cannot be accessed by the system" from `wsl`: the image has the inbox stub
  without the WSL package; install the MSI from the microsoft/WSL GitHub releases.

---

[README.md](../README.md)

---
