<#
.SYNOPSIS
    Bootstrap script for portable Windows development environments using Scoop package manager.

.DESCRIPTION
    scoop-boot.ps1 v1.24.3 - Portable Windows Development Environment Bootstrap

    Features:
    - Setup in three commands: --admin-init, --admin-setenv, --user-install;
      --admin-reset to start over
    - Environment files per host and user, applied at Machine scope; the User
      scope is cleaned after every Scoop command (scoop wrapper in bin\)
    - List operations (+=, =+, -=) for ALL environment variables, order-independent
      variable expansion
    - Profiles (etc\profiles): packages, environment and apt list per part of a
      workplace, composed per machine by --admin-init --profile=NAMES or --profile;
      virtual profiles devel and devops
    - Package list per host (etc\packages), post-install handlers as a table,
      --export and --import to carry the packages of one machine to another
    - --platform-report: what Defender/ASR and a profile container do to the setup
    - --update installs signed releases: manifest with SHA-256 of every file,
      SSH signature, trust on first use; rescue path; daily log
    - --self-test on the machine; tools\test.ps1 for development and CI, with the
      whole setup in fake mode (SCOOPBOOT_FAKE=1: no Scoop, registry or processes)
    - --wsl-install and --wsl-setup: a Debian in WSL 2 with the apt list of the profiles
    - ASCII-only output for console compatibility

.PARAMETER (Dynamic)
    This script uses custom parameter parsing to support order-independent arguments.
    All parameters can be specified in any order.

.NOTES
    Version: 1.24.3
    Author: System Administrator
    Requires: PowerShell 5.1 or higher

    Changes in v1.24.3:
    - --user-install tells a package apart that its manifest refuses to install
      from a normal shell (the nonportable bucket checks is_admin in pre_install:
      "Admin rights required", seen with tortoisegit-np on the AVD, 31.10.): the
      summary lists those with the exact commands for an Administrator shell and
      for "sudo scoop install" from the normal one

    Changes in v1.24.2:
    - --profile=devel,java17 typed without quotes in PowerShell arrives as an array
      (PowerShell splits an unquoted comma list); the script joins it back, and
      profile names may also be separated by spaces inside quotes
    - Profile tortoisegit: TortoiseGit from the nonportable bucket (an MSI into
      Program Files: elevation prompt during --user-install, not removed by the
      reset); the bucket comes with the profile's "# bucket" line

    Changes in v1.24.1:
    - Profiles java8, java11, java17, java21: the Temurin JDK and its
      JAVA_HOME_NN_X64, no PATH entry; --profile=devel,java17,java21 installs them
      next to JDK 25. The java profile no longer sets JAVA_HOME_8_X64 to
      JAVA_HOME_21_X64 for JDKs that are not installed

    Changes in v1.24.0:
    - Profiles: etc\profiles holds one directory per part of a workplace (base,
      desktop, ide, cli, svn, java, node, perl, python, c++, docs, network, netdiag,
      db, dbclients, server, azure, azure-tools, iac, pwsh, automation, media), each
      with its Scoop packages, its environment lines and, where it has one, its apt
      list; profiles.conf names them in composition order and defines the virtual
      profiles devel (the developer workplace, the content of default.txt) and
      devops. --profile=NAMES composes etc\packages\<host>.txt, <host>.debian.txt,
      system.<host>.<user>.env and user.<host>.<user>.env from any combination
      (--dry-run shows them, --force replaces existing files and keeps .bak);
      --admin-init --profile=NAMES does it during the setup, without --profile it
      takes PROFILE= from etc\scoop-boot.conf or devel; --list-profiles lists them.
      The environment templates and --package-template of 1.23.0 are replaced
    - etc\release.files names the delivered files; tools/release.sh signs that
      list and --update --branch downloads it (the list was hard-coded before)
    - Fake mode: with SCOOPBOOT_FAKE=1 the setup runs end to end without Scoop,
      registry or processes (a simulated Scoop in the same layout, a registry in
      etc\fake\registry.json); tools/test.ps1 and the CI run --admin-init,
      --admin-setenv, --user-install, the scoop wrapper, --export, --import,
      --list-packages and --admin-reset this way on Linux and Windows
    - --user-install and --bootstrap no longer leave SCOOP_BOOT_WRAPPER=off in the
      shell: every later "scoop install" in that shell skipped the user-scope
      cleanup (found by the fake end-to-end test)
    - --wsl-setup --dry-run fetches the apt index first on a fresh distribution
      (the simulation failed with "package name is wrong or the index is old");
      --wsl-setup without the distribution reports it instead of failing on
      wsl.exe's stderr in Windows PowerShell 5.1
    - --admin-init works on a machine that has only this script, as the Quick
      Setup promises: when bin\scoop-boot.psm1 is missing (or does not load), the
      release is downloaded first and the command goes on with the module just
      installed. Before, the rescue mode refused everything but --update, and the
      first command of the Quick Setup ended with "module not loaded" (new AVD,
      30.10.)
    - The "run this next" hints name the script with its full path
      (C:\usr\bin\scoop-boot.ps1 --admin-setenv): bin\ is on the PATH only after
      --admin-setenv and a new shell, and not at all after a reset
    - Package list: hxd back in (desktop); fzf (cli) and draw.io (desktop) new

    Changes in v1.23.0:
    - --wsl-install (Administrator): WSL and the Debian distribution (--distro=NAME
      for another one), without starting it; --dry-run shows the wsl.exe commands
    - --wsl-setup (normal shell): runs etc\wsl\debian-setup.sh inside the
      distribution: the missing apt packages of etc\packages\debian.txt (or
      etc\packages\<host>.debian.txt), fd and bat under their usual names, Claude
      Code with the official installer (--no-claude leaves it out); --dry-run lets
      apt-get resolve every package in simulation mode and installs nothing
    - --wsl-setup only adds, also on a distribution someone already uses (Ubuntu
      and other Debian derivatives too): apt-get --no-remove, no upgrade, no
      autoremove; the dry run fails when apt would remove a package; files in
      ~/.local/bin and an existing claude stay as they are
    - --update also delivers etc\packages\debian.txt and etc\wsl\debian-setup.sh
    - --package-template=NAME: copies etc\packages\NAME.txt and NAME.debian.txt to
      the host lists (<host>.txt, <host>.debian.txt); existing ones only with
      --force (kept as .bak); --dry-run writes nothing. Template devops: Azure,
      Terraform, Service Bus and Storage Explorer, network and database clients
      instead of compilers and IDEs; for Debian network and automation tools
    - Self-tests 49 to 53: WSL options, Windows-to-WSL path, Debian package list,
      WSL distribution list, package templates

    Changes in v1.22.4:
    - --admin-reset ends with a WM_SETTINGCHANGE "Environment" broadcast (a User
      variable written and removed again) instead of restarting Explorer: Windows
      restarts a stopped Explorer at once with the block of the logon, which still
      held the removed values, and the restart in 1.22.3 lost that race on the
      AVD. On the message Explorer reads the registry again and drops removed
      variables; a shell opened from the Start menu afterwards was clean without
      logging off (confirmed on the AVD, 30.10.). Explorer is started, with a
      registry-built environment, only when it is not running at all

    Changes in v1.22.3:
    - --admin-reset restarts Explorer at the end in every case, with an
      environment block built from the registry (Machine, User, the volatile
      logon values) instead of an inherited one. Windows restarts a stopped
      Explorer with the block of the logon, a script-started one inherits the
      script's; both still carried the removed variables, and every shell opened
      from the Start menu inherited them until the next logon (the AVD, 30.10.)
    - --admin-reset aligns this shell's environment by the same rule as the
      registry cleanup (names on the list, values inside Scoop's directories),
      not only by what this run removed: the shell may have inherited values an
      earlier run already removed
    - --admin-reset looks at the loaded modules when a directory stays locked:
      shell-extension DLLs load into every program with a file dialog or a file
      manager, which no handle scan shows. Scoop's own processes are stopped, any
      other program is named in the output and in the summary (FreeCommander
      from its own directory held apps\tortoisesvn)

    Changes in v1.22.2:
    - --admin-reset aligns its own process environment with the registry after the
      cleanup (removed variables, PATH from Machine plus User). Explorer, started
      again by the reset, inherited the old values and handed them to every shell
      opened from the Start menu: the AVD showed JAVA_HOME and friends in new
      shells although the registry was clean (30.10.)
    - --admin-reset no longer restarts Explorer inside the deletion routine: a
      shell extension (TortoiseSVN, 7-Zip) is a DLL in Explorer that no handle
      scan shows, and the restarted Explorer loaded it back before the retry, so
      apps\tortoisesvn stayed. Explorer is stopped, the deletion retried, and
      Explorer started once at the end, after every directory is gone. Processes
      that started again from the directory meanwhile (an IDE kept running by
      --keep-persist respawns its terminal bash.exe from apps\git) are stopped
      before the retry
    - --admin-reset checks the image paths in up to three passes, like the handle
      scan; the summary names what still runs from a remaining directory

    Changes in v1.22.1:
    - tools\release.sh restores etc\release.manifest and the previous signature
      from HEAD when it aborts after writing the manifest (a mistyped passphrase
      at ssh-keygen left a dirty tree on 30.10.); tested with a passphrase key
      and closed stdin, and the happy path with --no-push
    - Documentation: "# bucket NAME URL" lines explained in the package list
      header, README and docs\private-bucket.md (a private bucket needs no code
      change); user template names Step 5 and the wrapper; README notes the
      release.sh behaviour. No functional change in the scripts

    Changes in v1.22.0:
    - Pester suite in tests\ (tests\*.Tests.ps1, run with tools\test.ps1 or
      Invoke-Pester): parser, expansion, apply and dry-run store, package list,
      import plan, export, handler table, result objects, configuration, help
      against parser, and a static check that no function reads a variable it
      never assigns. Runs on Windows PowerShell 5.1 and on pwsh (Linux included:
      the registry is replaced by the dry-run store). GitHub Actions workflow
      .github\workflows\ci.yml runs the suite on ubuntu-latest and windows-latest
      plus --self-test and the parse check on every push and pull request
    - Set-DevelopmentEnvironment, Install-ScoopTools and Invoke-ScoopReset run
      under Set-StrictMode -Version 1 (undefined variables are errors) instead of
      strict mode off; Show-PackageList under the module's strict mode. Version 2
      and up stay off there: .Count on a single object and missing properties of
      Scoop's JSON are part of that code
    - --user-install: the user-scope cleanup is Step 5 (it said Step 7 since the
      handlers replaced Steps 4 to 6); the summary counts skipped packages
      ("1 skipped" when the VC++ runtime guard left out vcredist2022), so the
      numbers add up to the list
    - --update on a remembered branch that answers 404 for every file says that
      the branch is probably merged and deleted, and names --update --branch=main
    - FIX --self-test exited with 0 even when a test failed: test 26 leaked the
      return value of Apply-EnvironmentOperations into the pipeline, so the
      function returned @(1, $false), which is true. Found by the first CI run.
      The leak is fixed and the dispatch takes the last object as the verdict;
      tools\test.ps1 also checks the summary line
    - --admin-reset scans with handle64 in up to three passes: stop the Scoop
      processes, wait two seconds, scan again, until nothing holds apps\ (or only
      processes that are not Scoop's). The renderer children of Chrome and
      Firefox die with their parent and were reported as "Could not stop"; a
      crash helper or a restarted app took new handles after the single pass and
      apps\ and persist\ stayed behind (laptop, 29.10.). A PID that is gone by
      its turn is "Already gone"; a real failure now names the reason
    - --admin-reset always checks the image path of every process after the
      handle64 scan (it was the fallback when handle64 was missing): handle64
      lists open file handles only, a Git Bash shell or an idle editor started
      from apps\ holds no file but locks its own exe, and apps\git stayed behind
    - --admin-reset scans and stops processes in every directory it deletes, not
      only apps\: JetBrains Toolbox installs Rider and PyCharm under
      persist\jetbrains-toolbox\apps, they ran from there and persist\ stayed
      behind. With --keep-persist those processes are left alone. The diagnostic
      hints name the Scoop root exactly instead of '*usr*'
    - --admin-reset refuses to run from a shell hosted by a process in a Scoop
      directory (a Windows Terminal or a Git Bash mintty from apps\): that host
      is stopped with the other Scoop processes and takes the console and this
      PowerShell with it, leaving the reset half done. Get-ScoopHostedAncestor
      walks the parent chain before anything is touched
    - --admin-reset names the processes that are not Scoop's but hold its
      directories (a cmd whose working directory is under apps\) in the final
      summary when a directory could not be deleted; the environment hint at the
      end checks for Scoop's own directories only (C:\usr\bin in PATH stays)
    - FIX Removing a variable left it empty instead of gone on pwsh 7.6 (a
      PowerShell $null reaches .NET as an empty string there): Set-EnvValue and
      the reset pass [NullString]::Value. Self-test 39 was red on ubuntu-latest
    - README: Quick Setup with the export of the old machine, the scoop wrapper
      explained with the JDK example, why scoop export/import is not used;
      docs\environment-files.md reviewed

    Changes in v1.21.0:
    - Post-install handlers are a table ($global:PackageHandlers: Name, Handler
      function, Description, Arguments). Step 4 of --user-install runs the table
      for every listed package, --list-packages reads the same descriptions; a
      handler reports failures as typed objects, so the stdout of the tools it
      runs (pacman, scoop) no longer leaks into the result. Window title: one
      step per handler. The handler bodies are the former Steps 4 to 6, unchanged
    - Result objects: Set-DevelopmentEnvironment, Install-ScoopTools,
      Show-PackageList, Invoke-ScoopReset and Invoke-ApplyEnv return a typed
      result (Command, Ok, and Installed/AlreadyInstalled/Failed/UserScopeChanges
      or Remaining/Backup); the entry points take Ok as the exit code. Two fixes
      fall out of it: --user-install with failed packages and --admin-reset with
      directories left behind now exit with 1 (they exited 0). Get-LastResult is gone
    - --admin-setenv --dry-run shows the net effect: the operations are applied to
      a simulated store (a prepend after the sweep sees the swept PATH) and the
      store is compared with the registry at the end: per scope changed, new,
      removed, unchanged, with PATH entries added or removed and whether the
      order changes. "82 changes" on an unchanged machine is now "0 changed"
    - --export[=NAME] writes etc\exports\NAME.txt from apps\*\current\scoop-install.json
      and buckets\*\.git\config (never from "scoop list", which truncates names):
      "# bucket NAME URL" lines, then bucket/name per package with version and
      hold as comment, bootstrap packages left out. --import=NAME|FILE [--dry-run]
      appends what the effective list lacks to etc\packages\<host>.txt under
      "# import <date> from NAME (n of m packages were missing)", creates the host
      file from default.txt when needed, adds "# bucket" lines for buckets Scoop
      does not know; a second import adds nothing. --import=NAME --replace writes
      the host file from the export alone (the old machine's list, nothing else;
      the previous list is kept as .bak). Step 2 of --user-install adds the
      "# bucket" buckets. Nothing is installed or uninstalled by --import
    - Self-tests 44 (handler table), 45 (import plan), 46 (dry-run net effect),
      47 (export from a temporary apps tree); 47 tests

    Changes in v1.20.0:
    - The Scoop root is wherever bin\ lives; the conventions around it (tmp, devl,
      data) come from etc\scoop-boot.conf ("DIR=<path>" lines). --admin-init writes
      the file with the defaults on the root's drive when it is missing, creates
      the directories, and sets USR in the new environment file to the root.
      --platform-report reads the same list. No C:\usr, C:\tmp, C:\devl or C:\data
      left in the scripts outside comments and examples
    - TMP and TEMP are the environment file's business: --admin-setenv no longer
      sets them before applying the files; after applying it creates the
      directory the Machine values point to (everyone may write) and takes the
      values into the session. --user-install compares Machine TMP with the
      value the system.* files define instead of C:\tmp; no definition, no check.
      Self-tests 42 (conf) and 43 (env file value); 43 tests
    - tools/release.sh (bash) replaces tools/release.ps1: Urs works in Git Bash,
      where "ssh-keygen -Y verify < file" needs no .NET detour and the blob hashes
      are one pipe. Same manifest, same signature, same checks
    - Rescue fallbacks: Get-Username is defined there too, --admin-init used it

    Changes in v1.19.0:
    - Signed releases. tools\release.ps1 writes etc\release.manifest (tag, date,
      SHA-256 of the six delivered files, taken from the committed blobs), signs it
      with the SSH key (ssh-keygen -Y sign, namespace and principal "scoop-boot"),
      sets etc\LATEST and pushes commit and tag. --update without --branch reads
      LATEST on main, downloads manifest and signature from the tag, verifies the
      signature with the key in the local etc\allowed_signers (delivered once, on
      the first update, fingerprint printed for comparison with the README),
      downloads every file and compares it with the manifest, and only then
      replaces anything. One failed check leaves the installation untouched.
      --update --branch=NAME stays unverified and says so in every run.
      The verified manifest is kept in etc\; --version names the release,
      self-test 41 compares the installed files with it
    - The signature goes to ssh-keygen through a .NET process with the manifest
      bytes on standard input; a PowerShell pipe appends a line break and the
      signature would never match (found in the spike on 23.10.)
    - Reset calls cmd.exe through $env:ComSpec: with Git's or MSYS2's usr\bin
      before System32 in the PATH, "cmd" resolved to an extensionless file and
      opened the "select an app" dialog. The system template explains the order

    Changes in v1.18.0:
    - Removed: --status, --suggest, --install, --environment, --rollback,
      --init-env, --apply-env, the long template etc\environments\template-default.env
      and the embedded template text. --admin-setenv --dry-run shows the changes
      the environment files would make and needs no elevation; the host files
      come from --admin-init, *.default.env files are copied from the templates
      by hand (docs\environment-files.md). Thirteen commands remain
    - An unknown option stops the script with its name instead of being ignored;
      without arguments the help is shown. Self-test 3 covers the parser's
      unknown list, self-test 40 checks that every option in --help is accepted
      by the parser
    - About 420 lines less in scoop-boot.psm1

    Changes in v1.17.0:
    - --platform-report replaces --asr-report (kept as alias): the Defender/ASR
      part as before, plus the user profile (FSLogix profile container: policy,
      container path, fill level, redirections.xml exclusions), TMP in process,
      User and Machine scope, the developer caches inside the profile with their
      sizes, and FSLogix container errors. A Findings block at the end names
      what the platform team has to change (ASR rule 01443614 without exclusion
      for C:\usr, blocks on developer files, container without developer-cache
      exclusions, container over 80 percent, SetTempToLocalPath, a User-scope
      TMP override); with findings the exit code is 1. Report file
      logs\scoopboot\platform-report-<date>.txt. Read-only, works without
      elevation except for the Defender rule and exclusion lists
    - Template: the cache section describes FSLogix correctly (the container is
      attached, not copied; the costs are the size limit and network I/O)

    Changes in v1.16.0:
    - The library moved to bin\scoop-boot.psm1 (logging, environment files,
      package list, bootstrap, setup commands, self-tests). scoop-boot.ps1 is
      the command line: it imports the module into its own scope (nothing leaks
      into the calling shell) and dispatches. The helper scripts import the
      module instead of dot-sourcing this file; the library mode
      ($global:ScoopBootLibraryOnly) is gone
    - Rescue path: --update, --version and --help run without the module. A
      module that does not load prints the error and the way out (--update);
      every other command stops there
    - --update also delivers bin\scoop-boot.psm1; self-test 37 scans both files
      for uninitialised globals, self-test 38 compares the script's version with
      the module's
    - --bootstrap passes -RunAsAdmin to the Scoop installer when the shell is
      elevated (the installer refuses otherwise)
    - Stage 2: the installation (Set-DevelopmentEnvironment, Install-ScoopTools,
      Show-PackageList) and the reset (Invoke-ScoopReset) are module functions;
      scoop-complete-install.ps1 and scoop-complete-reset.ps1 are gone, --update
      moves leftover copies to the backup directory. These functions keep the
      shell defaults they were written for (no strict mode, Continue) until
      they get tests. The log context carries the command
      ("scoop-boot.ps1 --user-install (1.16.0)")
    - --user-install --force skips the question in an elevated shell (an account
      that is a local administrator and has elevated shells only)
    - Window title shows the progress of --user-install, --bootstrap and
      --admin-reset ("scoop-boot [12/74] kotlin", "scoop-boot [72/74] gcc",
      "scoop-boot reset apps"); the counter runs over the packages and the four
      post-install stages; the previous title is restored at the end
    - --admin-init fills in hostname, user name, file name and creation date in
      the header of the environment files it creates. The system template keeps
      CUSTOM above CORE PATHS (a PATH+= in CUSTOM landed in front of bin and shims)
    - --admin-reset prints the image path of processes it leaves running

    Changes in v1.15.0:
    - One version for all three scripts: scoop-complete-install.ps1 (was 2.11.0)
      and scoop-complete-reset.ps1 (was 2.6.0) carry 1.15.0 from now on
    - Variable expansion resolves NAME=value definitions of the .env files first,
      wherever the line stands (USR=C:\usr at the bottom, $USR above it works on a
      fresh machine and in --dry-run); $$ is a literal $; self-tests 34 to 36.
      The system template defines the base directories on top and uses $USR
    - --admin-reset [--force] [--keep-persist] runs scoop-complete-reset.ps1 with
      an admin check first; --list-packages runs the install script's -ListPackages;
      the two helper scripts no longer appear in the user documentation; --self-test accepted next to --selfTest; help text
      grouped by purpose, --rollback no longer listed (it does nothing)
    - --update keeps the newest five backups\scripts-* directories (they
      accumulated before, and the reset's retention tripped over them)
    - FIX --admin-setenv, --user-install, --admin-reset, --list-packages ran the
      helper scripts under this script's $ErrorActionPreference = Stop; a
      manifest's Write-Error (Wireshark post_install) aborted Phase 2 at package
      39 of 62. The entry points now run them with Continue
    - FIX "-NAME" (unset) aborted --apply-env under Set-StrictMode: the parsed
      operation had no Value key. Self-test 39
    - FIX --dry-run failed under Set-StrictMode ("$global:SuppressDryRunOutput
      cannot be retrieved") unless --selfTest had run in the same session; the
      flag is now initialised. Self-test 37 checks every $global: name
    - --branch=NAME is remembered in etc\scoop-boot.branch; --update and
      --admin-init without the switch use it (--branch=main forgets it). Before,
      --admin-init on a test machine silently downloaded main over the branch
    - --bootstrap resumes when the Scoop core exists: the installer is skipped,
      the essential tools are still checked (a run stopped by endpoint security
      at 7z.exe can be repeated once the binary is allowed or pinned). Its
      standalone "Next steps" name the setup commands
    - FIX --bootstrap: the official installer refused to run ("Scoop is already
      installed") because it found the scoop wrapper in bin\ on the PATH; bin\ and
      shims\ are removed from the process PATH while the installer runs. Only
      visible since --admin-init delivers the wrapper before Scoop exists
    - FIX --bootstrap took the scoop wrapper in bin\ for an installed Scoop
      (Get-Command scoop); after a reset that would have skipped the Scoop
      install. Now checks apps\scoop\current\bin\scoop.ps1
    - FIX self-test 8: user names with a dot (urs.stotz) failed the file name
      pattern; the files themselves always worked
    - Setup entry points: --admin-init (directories, --update, environment files
      from the templates, Notepad), --admin-setenv (Phase 1) and --user-install
      (Phase 2) call scoop-complete-install.ps1; the Quick Setup no longer names it
    - Package lists: etc\packages\default.txt (delivered) or etc\packages\<host>.txt
      (yours, replaces default.txt). Library functions Get-PackageListFile,
      Read-PackageList, Get-ManifestAppName; self-tests 31 to 33
    - --update also delivers etc\packages\default.txt, warns when the local copy
      was edited (hash recorded in default.txt.sha256); --branch=NAME downloads
      from a branch for testing

    Changes in v1.14.2:
    - Write-Warning prints "[WARN]" instead of "[!]": the log level detection and
      the --quiet filter only know [WARN], so warnings were logged as INFO and
      hidden by the wrapper

    Changes in v1.14.1:
    - FIX: log attribution after a child script returned. Get-PSCallStack reports
      the Write-Host override as "Write-Host<Process>", so it was not skipped and
      its ScriptName (scoop-boot.ps1) won once that context existed
    - FIX: --asr-report without Administrator printed a phantom rule line and
      Defender's "N/A" strings; now says what needs elevation and keeps the events
    - --bootstrap skips its "Next steps" guide when SCOOP_BOOT_CALLER=install
    - sliksvn dropped from the templates (TortoiseSVN provides the same svn.exe)

    Changes in v1.14.0:
    - NEW: --asr-report writes Defender/ASR rules, exclusions and the ASR blocks
      of the last 14 days to logs\scoopboot\asr-report-<date>.txt
    - NEW: --update downloads the current scripts and the scoop wrapper from
      GitHub into bin\ (previous versions kept in backups\scripts-<timestamp>)
    - NEW: --quiet for --clean-user-scope (used by the scoop wrapper): console
      shows a one-line summary only when something changed
    - scoop wrapper (bin\scoop.ps1, scoop.cmd, scoop): runs --clean-user-scope
      after state-changing Scoop commands; "scoop upgrade" = update, update -a,
      cleanup -a, clean user scope

    Changes in v1.13.1:
    - Logging: context (script, mode, version) is resolved from the call stack,
      so output of child scripts (scoop.ps1, the Scoop installer) is attributed
      to the invoking scoop-boot script instead of an empty "()".
    - Logging: ANSI colour codes stripped, -NoNewline fragments joined into one
      line, carriage-return progress bars reduced to their final state, aria2
      progress lines dropped

    Changes in v1.13.0:
    - Logging: every Write-Host is mirrored to C:\usr\logs\scoopboot\<yyyyMMdd>.log
      with timestamp, script, version and level; session header with host, user,
      admin, Windows and PowerShell version, script hash and arguments; logs older
      than 60 days are pruned. The other two scripts dot-source this file in
      library mode ($global:ScoopBootLibraryOnly) and share the same log.
    - Version banner with the script's SHA-256 (first 8 digits) on every start
    - Bootstrap: 7z.exe and git.exe are started once right after their install;
      "Access is denied" (endpoint security blocking a new release) is reported
      as FATAL with the cause, instead of 60 follow-up extraction errors

    Changes in v1.12.0:
    - NEW: --clean-user-scope. Scoop writes JAVA_HOME, GRADLE_USER_HOME, ANT_HOME,
      ... and PATH entries into the User scope on every install/update; User
      values override Machine values, so the system.* file was silently defeated.
      The command removes User PATH entries inside Scoop's subdirectories and
      User variables whose name the system.* files set, then applies user.* files.
      No admin needed; run after scoop update / scoop install.
    - --apply-env sweeps Scoop entries from the Machine PATH before applying the
      system.* files (the manual PATH-= cleanup block is no longer needed for
      Scoop directories) and runs --clean-user-scope afterwards.
    - Scoop's subdirectories are apps, buckets, cache, persist, shims, global;
      nothing else under the base directory is treated as Scoop's.
    - WARN on unresolved $VAR references instead of writing the literal text

    Changes in v1.11.1:
    - Bootstrap: 7zip before git (git depends on 7zip; avoids the duplicate install)
    - Bootstrap: aria2 warning disabled right after aria2 is installed, not after bootstrap
    - Bootstrap: each essential/recommended tool is verified via apps\<tool>\current

    Changes in v1.11.0:
    - FIX: Bootstrap failed on every fresh machine because the official Scoop
      installer refuses a non-empty target directory, and C:\usr already
      contains bin\ and etc\ in the scoop-boot layout. The downloaded
      installer is now patched at that single check (Get-ScoopInstaller).
    - Installer output is captured and shown when the installation fails
    - Bootstrap verification checks apps\scoop\current and the shims directory
      instead of only Get-Command
    - ListRemove (VAR-=value) only writes and reports when the value was
      actually present; the change counter no longer counts no-ops

    Changes in v1.10.0:
    - List operations (+=, =+, -=) now work for ALL variables (not just PATH)
    - Added support for PERL5LIB, PYTHONPATH, CLASSPATH, PSModulePath, etc.
    - Extended self-tests to cover new list operations
    - Fixed processing stop issue with non-PATH list operations

.EXAMPLE
    .\scoop-boot.ps1 --admin-init
    Creates the directories and the environment files for this host and user (Administrator)

.EXAMPLE
    .\scoop-boot.ps1 --admin-setenv --dry-run
    Shows what the environment files would change

.EXAMPLE
    .\scoop-boot.ps1 --user-install
    Bootstraps Scoop and installs the package list

.EXAMPLE
    .\scoop-boot.ps1 --self-test
    Runs comprehensive self-tests (30 tests)
#>

# ============================================================================
# INIT & VALIDATION
# ============================================================================

param ()  # Required for custom parsing - no positional parameters

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Validate PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 5 -or
    ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Host "ERROR: PowerShell 5.1 or higher required" -ForegroundColor Red
    Write-Host "Current version: $($PSVersionTable.PSVersion)" -ForegroundColor Yellow
    exit 1
}

# ============================================================================
# MODULE
# ============================================================================
# The library lives in scoop-boot.psm1 next to this file. It is imported into this
# script's scope only (-Scope Local): the Write-Host override and the other
# functions are visible to this script and to the helper scripts it calls, and
# gone when it ends, so nothing leaks into the calling shell.
#
# Rescue path: --update, --version and --help must work when the module does not
# load (syntax error after a bad download, file missing), otherwise a broken
# module could never be replaced. The few things --update needs are defined here
# as fallbacks when the import fails; the module's versions win when it loads.

$global:ScriptVersion = "1.24.3"
$global:BaseDir = Split-Path -Parent $PSScriptRoot
$global:BranchFile = Join-Path $global:BaseDir "etc\scoop-boot.branch"
if (-not (Test-Path variable:global:ScoopBootQuiet)) { $global:ScoopBootQuiet = $false }

$script:ModulePath = Join-Path $PSScriptRoot 'scoop-boot.psm1'
$script:ModuleLoaded = $false
$script:ModuleError = ''
try {
    Import-Module $script:ModulePath -Scope Local -Force -DisableNameChecking -ErrorAction Stop
    $script:ModuleLoaded = $true
} catch {
    $script:ModuleError = $_.Exception.Message
}

if (-not $script:ModuleLoaded) {
    function Write-Section { param([string]$Title) Microsoft.PowerShell.Utility\Write-Host "`n=== $Title ===" -ForegroundColor Cyan }
    function Write-Info { param([string]$Message) Microsoft.PowerShell.Utility\Write-Host ">>> $Message" -ForegroundColor Cyan }
    function Write-Success { param([string]$Message) Microsoft.PowerShell.Utility\Write-Host "[OK] $Message" -ForegroundColor Green }
    function Write-Warning { param([string]$Message) Microsoft.PowerShell.Utility\Write-Host "[WARN] $Message" -ForegroundColor Yellow }
    function Write-ErrorMsg { param([string]$Message) Microsoft.PowerShell.Utility\Write-Host "[ERROR] $Message" -ForegroundColor Red }
    function Get-FileSha256Short { param([string]$Path) try { return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.Substring(0, 8).ToLower() } catch { return 'unknown' } }
    function Get-Hostname { return [System.Net.Dns]::GetHostName().ToLower() }
    function Get-Username { return [Environment]::UserName.ToLower() }
}

# ============================================================================
# COMMANDS THAT MUST WORK WITHOUT THE MODULE (update) AND THEIR CALLERS
# ============================================================================

function Get-UpdateBranch {
    <#
    .SYNOPSIS
        Resolves the branch for downloads: an explicit --branch=NAME wins and is
        remembered in etc\scoop-boot.branch (removed again for main); without it the
        remembered branch is used; without that, main.
    #>
    param(
        [string]$Requested = ''
    )
    if ($Requested) {
        if ($Requested -eq 'main') {
            if (Test-Path $global:BranchFile) {
                Remove-Item $global:BranchFile -Force
                Write-Info "Back on main; $global:BranchFile removed"
            }
        } else {
            $dir = Split-Path -Parent $global:BranchFile
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Set-Content -Path $global:BranchFile -Value $Requested -Encoding ASCII
        }
        return $Requested
    }
    if (Test-Path $global:BranchFile) {
        $saved = (Get-Content $global:BranchFile -ErrorAction SilentlyContinue | Select-Object -First 1)
        if ($saved -and $saved.Trim()) { return $saved.Trim() }
    }
    return 'main'
}

function Invoke-AdminInit {
    <#
    .SYNOPSIS
        Setup step 1 (Administrator): directories, scripts, environment files.
    .DESCRIPTION
        Creates bin\, etc\environments and etc\packages under the Scoop root plus the
        directories listed in etc\scoop-boot.conf (written with its defaults tmp,
        devl and data on the root's drive when missing), runs --update (scripts,
        scoop wrapper, package lists, profiles), composes etc\packages\<host>.txt,
        system.<host>.<user>.env and user.<host>.<user>.env from the profiles
        (--profile=NAMES; else PROFILE in etc\scoop-boot.conf; else devel) when they
        do not exist yet, and opens the system file in Notepad. Running it again
        changes nothing that already exists.
    #>
    param(
        [string]$Branch = '',
        [string]$Profile = ''
    )
    Write-Section "Setup 1: Initialize"
    if (-not (Test-AdminRights)) {
        Write-ErrorMsg "--admin-init needs an elevated shell (Run as Administrator)"
        return $false
    }
    # The conventions (tmp, devl, data) come from etc\scoop-boot.conf; scoop-boot
    # itself needs only the root. The file is written with its defaults when missing.
    $config = Get-ScoopBootConfig
    if (-not $config.Exists) {
        [IO.File]::WriteAllText($config.Path, (Get-ScoopBootConfigDefaultText), (New-Object Text.UTF8Encoding($false)))
        Write-Success "Configuration written with defaults: $($config.Path) (DIR=$($config.Dirs -join ', DIR='))"
    } else {
        Write-Host "[OK] Configuration: $($config.Path) (DIR=$($config.Dirs -join ', DIR='))" -ForegroundColor Gray
    }
    foreach ($bad in $config.Invalid) { Write-Warning "Ignored in $($config.Path): DIR=$bad (absolute path without spaces expected)" }
    foreach ($dir in @((Join-Path $global:BaseDir 'bin'), $global:EnvDir, $global:PackagesDir) + @($config.Dirs)) {
        if (Test-Path $dir) {
            Write-Host "[OK] Directory exists: $dir" -ForegroundColor Gray
        } elseif ((Test-ScoopBootFake) -and $config.Dirs -contains $dir) {
            Write-Host "[FAKE] Directory not created outside the Scoop root: $dir" -ForegroundColor DarkCyan
        } else {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Success "Directory created: $dir"
        }
    }

    if ($script:RescueUpdated) {
        Write-Host "[OK] Release downloaded before the module was loaded (see above)" -ForegroundColor Gray
    } elseif (Test-ScoopBootFake) {
        Write-Host "[FAKE] --update skipped: the files of this checkout are used" -ForegroundColor DarkCyan
    } elseif (-not (Invoke-SelfUpdate -Branch $Branch)) {
        return $false
    }
    $Branch = Get-UpdateBranch

    # The profiles --update just delivered compose this machine's files; existing
    # files are kept (a machine set up before 1.24.0 has them from the templates)
    $names = $Profile
    if (-not $names) { $names = (Get-ScoopBootConfig).Profile }
    if (-not $names) { $names = 'devel' }
    if (-not (Invoke-Profile -Names $names -KeepExisting $true -Command 'scoop-boot.ps1 --admin-init --profile')) { return $false }
    $systemFile = Join-Path $global:EnvDir ("system.{0}.{1}.env" -f (Get-Hostname), (Get-Username))
    if (-not (Test-Path $systemFile)) {
        Write-ErrorMsg "$systemFile was not written; check the profiles with $PSCommandPath --list-profiles"
        return $false
    }

    Write-Host ""
    Write-Info "Review paths and tool versions in the system file, save, then run: $PSCommandPath --admin-setenv"
    # Full path on purpose: once Git is installed, its usr\bin holds an extensionless
    # script named "notepad" that PowerShell would hand to ShellExecute.
    if (Test-ScoopBootFake) { Write-Host "[FAKE] Notepad not started for $systemFile" -ForegroundColor DarkCyan; return $true }
    Start-Process -FilePath "$env:SystemRoot\System32\notepad.exe" -ArgumentList "`"$systemFile`""
    return $true
}


function Get-FileSha256 {
    <#
    .SYNOPSIS
        Full SHA-256 of a file, lower case; '' when unreadable. Defined here because --update must verify without the module.
    #>
    param([string]$Path)
    try { return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower() } catch { return '' }
}

function Get-SshKeygenPath {
    <#
    .SYNOPSIS
        ssh-keygen.exe of the Windows OpenSSH client (-Y verify needs OpenSSH 8.1 or newer), else the first one on the PATH.
    #>
    $inbox = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh-keygen.exe'
    if (Test-Path $inbox) { return $inbox }
    $cmd = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return ''
}

function Get-SshKeyFingerprint {
    <#
    .SYNOPSIS
        SHA256 fingerprint of the first key in an allowed_signers file, as ssh-keygen -l prints it.
    #>
    param([string]$AllowedSignersPath)
    try {
        $line = Get-Content -Path $AllowedSignersPath | Where-Object { $_ -and $_ -notmatch '^\s*#' } | Select-Object -First 1
        $blob = ($line -split '\s+' | Where-Object { $_ -match '^AAAA' } | Select-Object -First 1)
        if (-not $blob) { return 'unknown' }
        $sha = [Security.Cryptography.SHA256]::Create().ComputeHash([Convert]::FromBase64String($blob))
        return 'SHA256:' + [Convert]::ToBase64String($sha).TrimEnd('=')
    } catch { return 'unknown' }
}

function Test-ReleaseSignature {
    <#
    .SYNOPSIS
        Verifies etc\release.manifest against its SSH signature with ssh-keygen -Y verify.
    .DESCRIPTION
        The manifest bytes go to ssh-keygen's standard input through a .NET process:
        a PowerShell pipe would append a line break and the signature would not match.
        Principal and namespace are both "scoop-boot"; the public key comes from the
        local etc\allowed_signers, delivered once and never replaced by --update.
    #>
    param(
        [string]$ManifestPath,
        [string]$SignaturePath,
        [string]$AllowedSignersPath
    )
    $sshKeygen = Get-SshKeygenPath
    if (-not $sshKeygen) {
        Write-ErrorMsg "ssh-keygen.exe not found: the Windows OpenSSH client is needed to verify a release (Settings > Optional features)"
        return $false
    }
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $sshKeygen
        $psi.Arguments = "-Y verify -f `"$AllowedSignersPath`" -I scoop-boot -n scoop-boot -s `"$SignaturePath`""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $p = [Diagnostics.Process]::Start($psi)
        $bytes = [IO.File]::ReadAllBytes($ManifestPath)
        $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
        $p.StandardInput.Close()
        $out = $p.StandardOutput.ReadToEnd() + $p.StandardError.ReadToEnd()
        $p.WaitForExit()
        if ($p.ExitCode -eq 0 -and $out -match '^Good ') {
            Write-Success ("Release signature verified ({0})" -f $out.Trim())
            return $true
        }
        Write-ErrorMsg "Release signature NOT valid (ssh-keygen exit $($p.ExitCode)): $($out.Trim())"
        return $false
    } catch {
        Write-ErrorMsg "Signature check failed to run: $($_.Exception.Message)"
        return $false
    }
}

function Read-ReleaseManifest {
    <#
    .SYNOPSIS
        Parses etc\release.manifest: "tag vNNNN", "date ...", "sha256 <hex> <path>" lines; '#' starts a comment.
    #>
    param([string]$Path)
    $manifest = @{ Tag = ''; Date = ''; Files = @{}; Order = @() }
    foreach ($line in (Get-Content -Path $Path)) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        if ($t -match '^tag\s+(\S+)$') { $manifest.Tag = $Matches[1]; continue }
        if ($t -match '^date\s+(\S+)$') { $manifest.Date = $Matches[1]; continue }
        if ($t -match '^sha256\s+([0-9a-f]{64})\s+(\S+)$') { $manifest.Files[$Matches[2]] = $Matches[1]; $manifest.Order += $Matches[2]; continue }
    }
    return $manifest
}

function Invoke-SelfUpdate {
    <#
    .SYNOPSIS
        Downloads the current scoop-boot release (or a branch) from GitHub into bin\ and etc\.
    .DESCRIPTION
        Without --branch: the release named in etc\LATEST on main is downloaded from its
        tag. Its etc\release.manifest (SHA-256 of every delivered file) is verified
        against the SSH signature in etc\release.manifest.sig with the key in the local
        etc\allowed_signers; then every file is downloaded and compared with the
        manifest. Nothing is written before all of that succeeded. allowed_signers is
        downloaded once, on the first update, and its fingerprint is printed: compare
        it with the README (trust on first use, like an SSH host key).

        With --branch=NAME the branch head is downloaded unverified, for testing on
        one machine; the banner warns until --update --branch=main.

        Replaced: scoop-boot.ps1, scoop-boot.psm1 and the scoop wrapper (scoop.ps1,
        scoop.cmd, scoop) under bin\, and etc\packages\default.txt. The environment
        files and any etc\packages\<host>.txt belong to the user and are never
        touched. Previous versions go to backups\scripts-<timestamp>\. A locally
        edited default.txt is reported before it is replaced.
    .PARAMETER Branch
        --branch=NAME: download from this branch and remember it in
        etc\scoop-boot.branch; --branch=main forgets it. Without the switch the
        remembered branch, else the signed release.
    #>
    param(
        [string]$Branch = ''
    )
    Write-Section "scoop-boot Update"
    $Branch = Get-UpdateBranch -Requested $Branch
    $repo = 'https://raw.githubusercontent.com/stotz/scoop-boot'
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    # GetTempPath: TEMP of this session on Windows, and defined on a runner without it
    $temp = Join-Path ([IO.Path]::GetTempPath()) "scoop-boot-update-$stamp"
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    $etcDir = Join-Path $global:BaseDir 'etc'
    if (-not (Test-Path $etcDir)) { New-Item -ItemType Directory -Path $etcDir -Force | Out-Null }
    $allowedSigners = Join-Path $etcDir 'allowed_signers'
    $localManifest = Join-Path $etcDir 'release.manifest'
    $localSignature = Join-Path $etcDir 'release.manifest.sig'
    $manifest = $null

    if ($Branch -eq 'main') {
        # Signed release: LATEST on main names the tag, the tag carries the files
        try {
            $tag = (Invoke-WebRequest -Uri "$repo/main/etc/LATEST" -UseBasicParsing).Content.Trim()
        } catch {
            Write-ErrorMsg "Could not read the release pointer $repo/main/etc/LATEST ($($_.Exception.Message))"
            Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
        if ($tag -notmatch '^v\d{4}$') {
            Write-ErrorMsg "etc/LATEST on main does not name a release tag: '$tag'"
            Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
        $ref = $tag
        $base = "$repo/$ref"
        Write-Info "Release $tag"
        $tempManifest = Join-Path $temp 'release.manifest'
        $tempSignature = Join-Path $temp 'release.manifest.sig'
        try {
            Invoke-WebRequest -Uri "$base/etc/release.manifest" -OutFile $tempManifest -UseBasicParsing
            Invoke-WebRequest -Uri "$base/etc/release.manifest.sig" -OutFile $tempSignature -UseBasicParsing
        } catch {
            Write-ErrorMsg "Download failed: $base/etc/release.manifest(.sig) ($($_.Exception.Message))"
            Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
        if (-not (Test-Path $allowedSigners)) {
            # Trust on first use: the key arrives once; from now on it decides
            try {
                Invoke-WebRequest -Uri "$base/etc/allowed_signers" -OutFile $allowedSigners -UseBasicParsing
            } catch {
                Write-ErrorMsg "Download failed: $base/etc/allowed_signers ($($_.Exception.Message))"
                Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
                return $false
            }
            Write-Warning "Release signing key saved to $allowedSigners (first update on this machine)"
            Write-Warning "Fingerprint $(Get-SshKeyFingerprint -AllowedSignersPath $allowedSigners): compare it with the README before trusting this installation"
        }
        if (-not (Test-ReleaseSignature -ManifestPath $tempManifest -SignaturePath $tempSignature -AllowedSignersPath $allowedSigners)) {
            Write-ErrorMsg "Nothing was changed. If the key was rotated on purpose, delete $allowedSigners and run --update again; the README names the current fingerprint"
            Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
        $manifest = Read-ReleaseManifest -Path $tempManifest
        if ($manifest.Tag -ne $tag -or $manifest.Order.Count -eq 0) {
            Write-ErrorMsg "Manifest of $tag is not usable (tag '$($manifest.Tag)', $($manifest.Order.Count) files)"
            Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
        $files = @($manifest.Order)
    } else {
        $ref = $Branch
        $base = "$repo/$ref"
        Write-Warning "Downloading from branch '$Branch' WITHOUT signature check (remembered in $global:BranchFile; back to signed releases with --update --branch=main)"
        # etc/release.files on the branch names the delivered files, as the manifest
        # does for a release (tools/release.sh reads the same file)
        try {
            $index = (Invoke-WebRequest -Uri "$base/etc/release.files" -UseBasicParsing).Content
        } catch {
            Write-ErrorMsg "Download failed: $base/etc/release.files ($($_.Exception.Message)); a branch before 1.24.0 has no file index, release it or merge main into it"
            Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
        $files = @($index -split "`r?`n" | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ })
        if ($files.Count -eq 0) {
            Write-ErrorMsg "$base/etc/release.files is empty"
            Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }
    }

    # Phase 1: download everything and check it against the manifest; no file is
    # touched before all downloads passed
    $downloads = @{}
    $failed = $false
    foreach ($rel in $files) {
        $download = Join-Path $temp ($rel -replace '[/\\]', '_')
        try {
            Invoke-WebRequest -Uri "$base/$rel" -OutFile $download -UseBasicParsing
        } catch {
            Write-ErrorMsg "Download failed: $base/$rel ($($_.Exception.Message))"
            $failed = $true
            continue
        }
        if ($manifest) {
            $hash = Get-FileSha256 -Path $download
            if ($hash -ne $manifest.Files[$rel]) {
                Write-ErrorMsg "$rel does not match the release manifest (downloaded $($hash.Substring(0,8)), expected $($manifest.Files[$rel].Substring(0,8)))"
                $failed = $true
                continue
            }
        }
        $downloads[$rel] = $download
    }
    if ($failed) {
        Write-ErrorMsg "Update aborted, nothing was changed"
        if (-not $manifest -and $Branch -ne 'main') {
            # Every file of a branch head came back 404: the branch was merged and
            # deleted, which is the normal end of a test branch
            Write-ErrorMsg "Branch '$Branch' is probably deleted (merged); back to the signed release with: $PSCommandPath --update --branch=main"
        }
        Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
        return $false
    }

    # Phase 2: replace what changed, with a backup of the previous version
    $backupDir = Join-Path $global:BaseDir "backups\scripts-$stamp"
    $changed = 0
    foreach ($rel in $files) {
        $name = Split-Path -Leaf $rel
        $target = Join-Path $global:BaseDir ($rel -replace '/', '\')
        $download = $downloads[$rel]
        $newHash = Get-FileSha256Short -Path $download
        $oldHash = if (Test-Path $target) { Get-FileSha256Short -Path $target } else { 'none' }
        $newVer = (Select-String -Path $download -Pattern 'Version:\s*([0-9.]+)' | Select-Object -First 1)
        $newVer = if ($newVer) { $newVer.Matches[0].Groups[1].Value } else { '' }
        if ($newHash -eq $oldHash) {
            Write-Host "[OK] $name unchanged ($oldHash$(if ($newVer) { ", $newVer" }))" -ForegroundColor Gray
            continue
        }
        if (Test-Path $target) {
            if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
            Copy-Item $target (Join-Path $backupDir $name) -Force
        }
        # default.txt: warn when the local copy differs from the version last delivered
        $hashFile = "$target.sha256"
        if ($rel -eq 'etc/packages/default.txt' -and (Test-Path $target) -and (Test-Path $hashFile)) {
            $delivered = (Get-Content $hashFile -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($delivered -and $delivered.Trim() -ne $oldHash) {
                Write-Warning "$name was edited locally; the edited copy is in $backupDir"
                Write-Warning "Keep local changes in etc\packages\$(Get-Hostname).txt instead, it replaces default.txt and is never updated"
            }
        }
        $targetDir = Split-Path -Parent $target
        if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
        Copy-Item $download $target -Force
        if ($rel -eq 'etc/packages/default.txt') { Set-Content -Path $hashFile -Value $newHash -Encoding ASCII }
        Write-Success "$name updated: $oldHash -> $newHash$(if ($newVer) { " ($newVer)" })"
        $changed++
    }
    if ($manifest) {
        # The verified manifest stays: --version names the release, --self-test checks the files against it
        Copy-Item (Join-Path $temp 'release.manifest') $localManifest -Force
        Copy-Item (Join-Path $temp 'release.manifest.sig') $localSignature -Force
    } elseif (Test-Path $localManifest) {
        # Branch files do not belong to any release
        Remove-Item $localManifest, $localSignature -Force -ErrorAction SilentlyContinue
    }
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
    # Files of earlier releases that no longer exist: moved to the backup directory
    foreach ($rel in @('bin/scoop-complete-install.ps1', 'bin/scoop-complete-reset.ps1')) {
        $obsolete = Join-Path $global:BaseDir ($rel -replace '/', '\')
        if (Test-Path $obsolete) {
            if (-not (Test-Path $backupDir)) { New-Item -ItemType Directory -Path $backupDir -Force | Out-Null }
            Move-Item $obsolete (Join-Path $backupDir (Split-Path -Leaf $rel)) -Force
            Write-Success "$(Split-Path -Leaf $rel) removed (part of scoop-boot.psm1 since 1.16.0); copy in $backupDir"
            $changed++
        }
    }
    # Keep the newest five scripts-* backups; the reset prunes its own snapshots the same way
    Get-ChildItem -Path (Join-Path $global:BaseDir 'backups') -Directory -Filter 'scripts-*' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -ne $backupDir } | Sort-Object Name -Descending | Select-Object -Skip 4 |
        ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    if ($changed -eq 0) {
        Write-Info "Everything is current$(if ($manifest) { " (release $($manifest.Tag))" })"
    } else {
        Write-Info "$changed file(s) updated$(if ($manifest) { " to release $($manifest.Tag)" }); previous versions in $backupDir"
        Write-Info "Environment files under etc\environments and host package lists were not touched"
    }
    return $true
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# PowerShell turns an unquoted "--profile=devel,java17" into an array ('--profile=devel',
# 'java17') that arrives as one element; joined back with commas it is the option as
# typed. Every string element stays as it is.
$args = @($args | ForEach-Object { if ($_ -is [array]) { @($_) -join ',' } else { "$_" } })
if ($args -contains '--quiet') { $global:ScoopBootQuiet = $true }
$rescueOnly = @($args | Where-Object { $_ -match '^--(update|version|v|help|h|branch=.+)$' -or $_ -match '^-[vh]$' }).Count -eq @($args).Count -and @($args).Count -gt 0
# --admin-init is the Quick Setup's first command, on a machine that has only this
# script: the module is downloaded first, then the command runs as usual
$adminInitFirst = @($args | Where-Object { $_ -notmatch '^--(quiet|branch=.+)$' }) -join ' ' -eq '--admin-init'
$script:RescueUpdated = $false

if (-not $script:ModuleLoaded) {
    # Rescue mode: no logging, no banner from the module, only the commands that
    # can put a working module back
    $missing = -not (Test-Path $script:ModulePath)
    Microsoft.PowerShell.Utility\Write-Host "scoop-boot.ps1 $global:ScriptVersion (sha256 $(Get-FileSha256Short -Path $PSCommandPath)) | module not loaded" -ForegroundColor DarkCyan
    if ($missing -and $adminInitFirst) {
        Microsoft.PowerShell.Utility\Write-Host "[INFO] $script:ModulePath is not there yet: downloading the release first" -ForegroundColor Cyan
    } else {
        Microsoft.PowerShell.Utility\Write-Host "[ERROR] $script:ModulePath did not load: $script:ModuleError" -ForegroundColor Red
    }
    if (-not $rescueOnly -and -not $adminInitFirst) {
        Microsoft.PowerShell.Utility\Write-Host "        Only --update, --version and --help work until the module is replaced. Run: $PSCommandPath --update" -ForegroundColor Yellow
        exit 1
    }
    if ($args -contains '--version' -or $args -contains '-v') { Microsoft.PowerShell.Utility\Write-Host "scoop-boot.ps1 version $global:ScriptVersion"; exit 0 }
    if ($args -contains '--help' -or $args -contains '-h') {
        Microsoft.PowerShell.Utility\Write-Host "Usage: $PSCommandPath --update [--branch=NAME]   (replaces bin\scoop-boot.psm1 and the scripts; full help once the module loads)"
        exit 0
    }
    $branch = ''
    foreach ($a in $args) { if ($a -match '^--branch=(.+)$') { $branch = $Matches[1] } }
    if (-not (Invoke-SelfUpdate -Branch $branch)) { exit 1 }
    if (-not $adminInitFirst) { exit 0 }
    # The module is on disk now: load it and go on with --admin-init
    try {
        Import-Module $script:ModulePath -Scope Local -Force -DisableNameChecking -ErrorAction Stop
        $script:ModuleLoaded = $true
        $script:RescueUpdated = $true
    } catch {
        Microsoft.PowerShell.Utility\Write-Host "[ERROR] $script:ModulePath did not load after the update: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# The command goes into the log context ("scoop-boot.ps1 --user-install (1.16.0)")
$logMode = @($args | Where-Object { $_ -match '^--' -and $_ -notmatch '^--(quiet|dry-run|force|keep-persist|branch=|distro=|no-claude)' } | Select-Object -First 1)
if ($args -contains '--admin-init') { $logMode = @('--admin-init') }
Initialize-ScoopBootLog -ScriptName 'scoop-boot.ps1' -Version $global:ScriptVersion -Mode "$logMode" -ScriptPath $PSCommandPath -Arguments $args

# Parse arguments; an unknown option stops here (a typo, or a command removed in 1.18.0)
Parse-Arguments -Arguments $args
if (@($global:ParsedArgs.Unknown).Count -gt 0) {
    Write-ErrorMsg "Unknown option(s): $($global:ParsedArgs.Unknown -join ' ')  ($PSCommandPath --help lists the commands)"
    exit 1
}


# Handle commands
if ($global:ParsedArgs.Help) {
    Show-Help
    exit 0
}

if ($global:ParsedArgs.Version) {
    Show-Version
    exit 0
}

if ($global:ParsedArgs.Bootstrap) {
    $savedTitle = Get-ScoopBootTitle
    # The bootstrap bypasses the scoop wrapper for its run only (see Invoke-UserInstall)
    $savedWrapper = $env:SCOOP_BOOT_WRAPPER
    try {
        $success = Invoke-Bootstrap
    } finally {
        Restore-ScoopBootTitle -Saved $savedTitle
        if ($null -eq $savedWrapper) { Remove-Item Env:SCOOP_BOOT_WRAPPER -ErrorAction SilentlyContinue } else { $env:SCOOP_BOOT_WRAPPER = $savedWrapper }
    }
    exit $(if ($success) { 0 } else { 1 })
}

if ($global:ParsedArgs.SelfTest) {
    # The verdict is the last object; anything a test leaks into the pipeline before
    # it must not turn a failure into exit 0 (it did until 1.22.0)
    $success = [bool](@(Test-ScoopBoot) | Select-Object -Last 1)
    exit $(if ($success) { 0 } else { 1 })
}

if ($global:ParsedArgs.EnvStatus) {
    Invoke-EnvStatus
    exit 0
}

if ($global:ParsedArgs.CleanUserScope) {
    $null = Invoke-CleanUserScope -DryRun $global:ParsedArgs.DryRun
    exit 0
}

if ($null -ne $global:ParsedArgs.Export) {
    if (Invoke-Export -Name $global:ParsedArgs.Export) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.Import) {
    if (Invoke-Import -Source $global:ParsedArgs.Import -DryRun $global:ParsedArgs.DryRun -Replace $global:ParsedArgs.Replace) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.PlatformReport) {
    # exit 1 when the report lists findings, so the command can gate a setup
    if (Invoke-PlatformReport) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.Update) {
    if (Invoke-SelfUpdate -Branch $global:ParsedArgs.Branch) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.AdminInit) {
    if (Invoke-AdminInit -Branch $global:ParsedArgs.Branch -Profile $global:ParsedArgs.Profile) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.AdminSetEnv) {
    if (Invoke-AdminSetEnv -DryRun $global:ParsedArgs.DryRun) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.UserInstall) {
    if (Invoke-UserInstall -Force $global:ParsedArgs.Force) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.ListPackages) {
    if (Invoke-ListPackages) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.ListProfiles) {
    if (Show-Profiles) { exit 0 } else { exit 1 }
}

# --profile with --admin-init is handled by --admin-init below
if ($global:ParsedArgs.Profile -and -not $global:ParsedArgs.AdminInit) {
    if (Invoke-Profile -Names $global:ParsedArgs.Profile -DryRun $global:ParsedArgs.DryRun -Force $global:ParsedArgs.Force) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.WslInstall) {
    if (Invoke-WslInstall -Distro $global:ParsedArgs.Distro -DryRun $global:ParsedArgs.DryRun) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.WslSetup) {
    if (Invoke-WslSetup -Distro $global:ParsedArgs.Distro -DryRun $global:ParsedArgs.DryRun -NoClaude $global:ParsedArgs.NoClaude) { exit 0 } else { exit 1 }
}

if ($global:ParsedArgs.AdminReset) {
    if (Invoke-AdminReset -Force $global:ParsedArgs.Force -KeepPersist $global:ParsedArgs.KeepPersist) { exit 0 } else { exit 1 }
}

# No command: the help is the status page
Show-Help
exit $(if ($args.Count -eq 0) { 0 } else { 1 })
