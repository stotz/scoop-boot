# Environment Files

[README.md](../README.md)  

---

How scoop-boot manages environment variables: which files exist, in which order they
are applied, what the syntax allows, where Scoop puts things under `C:\usr`, why the
User scope is cleaned, and how to keep a tool at a fixed version.

## Files and load order

All files live in `C:\usr\etc\environments`. The host name and user name in the file
name are lower case (`$env:COMPUTERNAME`, `$env:USERNAME`).

```
system.default.env              Machine scope, all hosts              needs Administrator
system.<host>.<user>.env        Machine scope, this host and user     needs Administrator, source of truth
user.default.env                User scope, all hosts
user.<host>.<user>.env          User scope, this host and user        your additions
```

`--admin-setenv` applies the `system.*` files in that order, then calls
`--clean-user-scope`, which applies the `user.*` files; `--admin-setenv --dry-run` shows
the changes without writing and needs no Administrator. `--clean-user-scope` on its own
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

`$NAME` and `${NAME}` are expanded when the line is applied, in this order:

1. A `NAME=value` line of the files being applied (the `system.*` files for Machine
   scope; for User scope the `user.*` files on top of them). The position of that line
   does not matter: `SVN_HOME=$USR\apps\tortoisesvn\current` near the top and
   `USR=C:\usr` at the bottom work, on a fresh machine and in `--dry-run` as well. When a
   name is defined twice, the last definition is the one references see, which is also
   the value that ends up in the registry.
2. The built-in names `$SCOOP` (`C:\usr`), `$USERPROFILE`, `$USERNAME` and `$HOSTNAME`
   from the running session.
3. The registry: Machine first, then User, then the process.

A definition that refers to itself (`PATH=$PATH;C:\x`) takes the old value from the
registry and extends it. A name that none of the three sources knows stays in the value
as written and is reported with a warning.

`$$` gives a literal `$`: `PROMPT=$$P$$G` sets `$P$G`. A `$` not followed by a name
(`$1`, `$-`, a trailing `$`) needs no escape. `%NAME%` is written as is, and because
scoop-boot stores values as plain strings (REG_SZ), Windows does not expand it either:
write such a value out, or use `$NAME`.

### PATH order

Later `PATH+=` lines win, because each one prepends. The composed file therefore lists
low-priority entries first and ends with `$USR\shims` and `$USR\bin`, so that the
scoop wrapper in `bin` is found before Scoop's own shim. `ucrt64\bin` of MSYS2 must come
after Git and Perl in the file (and therefore before them in the PATH): both ship older
`libstdc++-6.dll`, `libgcc_s_seh-1.dll` and `libwinpthread-1.dll`, and if those are found
first, `cc1.exe` fails with exit code -1073741511 (`STATUS_ENTRYPOINT_NOT_FOUND`). The
`c++` profile is listed behind `perl` in `profiles.conf` for exactly this reason, and
`msys2\usr\bin` is appended (`PATH=+`) so that it stays behind Git's `usr\bin` and
`System32`.

### Profiles

The host files are composed from `etc\profiles` by `--admin-init` (and by `--profile`
at any later time): `system.<host>.<user>.env` is the header, then the `system.env`
fragment of every selected profile in the order of `profiles.conf` (`base` first), then
`etc\profiles\system.footer.env` with the CUSTOM section, the core PATH lines and the
commented cache relocation (Gradle, Maven, npm, pip, NuGet, JetBrains, WSL) for machines
with roaming or container profiles; `user.<host>.<user>.env` is composed the same way
from the `user.env` fragments (only `base` has one). `USR` is set to the Scoop root of
the machine; `TMP`, `DEVL_ROOT` and `DATA` keep the values of the `base` fragment and are
reviewed in Notepad. The profile names stand in the header (`# Profiles:`) and in
`etc\scoop-boot.conf` (`PROFILE=`).

A fragment is an ordinary environment file without header. `$USR` and every other name
resolves across the whole composed file, so a fragment may refer to names another one
defines. A new tool goes into the fragment of its profile, or into a new profile
directory plus a `profile` line in `profiles.conf`; `tools/test.ps1` checks that
`default.txt` still equals the `devel` profile.

For a `system.default.env` or `user.default.env` (all hosts), copy a composed host file
by hand and delete the host and user lines in its header. Identity values (name, mail
addresses) do not belong in the profiles; they belong in your own
`user.<host>.<user>.env`, where scripts can read them.

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
  bin\                       scoop-boot.ps1, scoop-boot.psm1 and the scoop wrapper (scoop.ps1, scoop.cmd, scoop)
  etc\environments\          the environment files (composed from the profiles) and their backups
  etc\packages\              default.txt and debian.txt (delivered: the devel profile), <host>.txt and
                             <host>.debian.txt (yours, composed by --admin-init or --profile, replace them)
  etc\profiles\              profiles.conf, system.footer.env, one directory per profile (delivered)
  etc\wsl\                   debian-setup.sh for --wsl-setup (delivered)
  etc\exports\               package exports (--export), input for --import
  etc\release.files          the files --update delivers (read by --update --branch and tools/release.sh)
  etc\scoop-boot.conf        DIR= lines: the directories --admin-init creates; PROFILE= of this machine
  etc\allowed_signers        the release signing key (first --update, trust on first use)
  etc\release.manifest(.sig) hashes and signature of the installed release
  logs\scoopboot\            daily logs, platform reports
  backups\                   reset backups and previous script versions (--update)
```

`apps`, `buckets`, `cache`, `persist`, `shims` and `global` belong to Scoop and are
removed by the reset. The rest belongs to scoop-boot or to you; `--update` replaces
only the files of `etc\release.files` (`bin\*`, `etc\packages\default.txt` and
`debian.txt`, `etc\profiles\*`, `etc\wsl\*`). Anything else placed under `C:\usr` (a
database server, a GIS distribution, a workspace) is left alone by every command; its
PATH entries and variables are yours to maintain.

## The User scope

Scoop writes `JAVA_HOME`, `GRADLE_USER_HOME`, PATH entries and whatever a manifest's
`env_set` names into the User scope on every install, update and reset, and Windows
resolves User before Machine. `scoop install temurin11-jdk` therefore makes JDK 11 the
default in every new shell although the `system.*` file says 25. `--clean-user-scope`
removes those entries (User PATH entries inside Scoop's directories, User variables
whose name a `system.*` file sets) and applies the `user.*` files; the scoop wrapper in
`bin\` runs it after every state-changing Scoop command, `--user-install` once at the
end. What you want at User scope goes into `user.<host>.<user>.env`, not into the
Windows dialog: the cleanup leaves a User variable alone when no `system.*` file sets
that name (User PATH entries inside Scoop's directories go regardless), but a User
`JAVA_HOME` set by hand is removed like Scoop's, and the Machine value applies again.

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
`python314`); switching to another manifest means changing the file and running `--admin-setenv`
again.

## Known issues

- `pip` broken after a Python update: `python -m ensurepip --upgrade`, then
  `python -m pip install --upgrade pip`. `persist\python314\Lib\site-packages` keeps
  the installed packages.
- After `--admin-reset --keep-persist` and a new `--user-install`, the Python manifest's
  `post_install` may fail with "Failed to write executable - trying to use .deleteme
  logic": `current\Scripts` points into `persist\`, where the previous `pip.exe` still
  lives, and the upgrade cannot replace it through the junction (the same error from
  `python -m pip install --upgrade pip`). Python is installed and the old pip works. To
  get the current pip: `Remove-Item C:\usr\persist\python314\Scripts\pip*.exe`, then
  `python -m ensurepip --upgrade`.
- Git credentials after an update: they are in the Windows Credential Manager, not in
  Scoop's directories; `git config --global credential.helper manager` if the setting
  was lost.
- `gcc` compiles but the program does not start, Windows reports "Your administrator
  caused Windows Security to block this action": Defender ASR rule 01443614 on this
  machine. `scoop-boot.ps1 --platform-report` collects the evidence; the fix is a
  rule-specific exclusion by whoever manages Defender.
- `gcc` produces nothing and `cc1.exe` exits with -1073741511: DLL shadowing, see PATH
  order above; `where.exe libstdc++-6.dll` must list `ucrt64\bin` first.
- "The file cannot be accessed by the system" from `wsl`: the image has the inbox stub
  without the WSL package; install the MSI from the microsoft/WSL GitHub releases.

---

[README.md](../README.md)

---
