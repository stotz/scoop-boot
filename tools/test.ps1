<#
.SYNOPSIS
    Runs the scoop-boot checks from a repository checkout: parse check of every script,
    the self-tests, the profiles and the environment dry run in a scratch installation,
    the delivered-file index, the command line and the rescue mode.
.DESCRIPTION
    What the CI workflow (.github/workflows/ci.yml) runs, as one command for the
    developer. Works from any directory; the repository root is the parent of this
    file's directory. Exit code 0 when everything passed, 1 otherwise.

    Windows PowerShell 5.1:  powershell -File tools\test.ps1
    pwsh (Windows, Linux):   pwsh -File tools/test.ps1
    Git Bash:                powershell -File tools/test.ps1   (POSIX path, see README)
.PARAMETER SkipDryRun
    Leaves out the --admin-setenv --dry-run step (it needs the Windows registry).
#>
param([switch]$SkipDryRun)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$scoopBoot = Join-Path $root 'bin/scoop-boot.ps1'
$failed = 0
$onWindows = (-not (Test-Path variable:IsWindows)) -or $IsWindows

Write-Host "scoop-boot checks in $root (PowerShell $($PSVersionTable.PSVersion), $(if ($onWindows) { 'Windows' } else { 'not Windows' }))"
Write-Host ""

# 1. Parse check: every PowerShell file must parse without errors
Write-Host ">>> Parse check"
foreach ($file in @(Get-ChildItem -Path $root -Recurse -Include '*.ps1', '*.psm1' -File | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' })) {
    $tokens = $null; $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
    $relative = $file.FullName.Substring($root.Length + 1)
    if ($errors) {
        Write-Host "[FAIL] $relative`: $($errors[0].Message) (line $($errors[0].Extent.StartLineNumber))"
        $failed++
    } else {
        Write-Host "[OK] $relative"
    }
}
Write-Host ""

# 2. Self-tests (the module's own suite; test 41 is skipped in a git checkout)
Write-Host ">>> Self-tests"
# Exit code and the summary line both count: until 1.22.0 a leaked pipeline value
# turned a red self-test into exit 0, which the CI found on its first run
$selfTest = & $scoopBoot --self-test *>&1 | ForEach-Object { "$_" }
$selfTestExit = $LASTEXITCODE
$selfTest | ForEach-Object { Write-Host $_ }
if ($selfTestExit -ne 0 -or -not ($selfTest -match 'Tests: \d+ passed, 0 failed')) {
    Write-Host "[FAIL] --self-test: exit $selfTestExit$(if (-not ($selfTest -match 'Tests: \d+ passed, 0 failed')) { ', summary line not clean' })"
    $failed++
} else {
    Write-Host "[OK] --self-test"
}
Write-Host ""

# 3. Profiles in a scratch installation: bin\, etc\packages and etc\profiles copied;
#    --profile=devel composes the host files there, --admin-setenv --dry-run applies
#    the composed system file to the dry-run store and must end with the net-effect
#    summary and exit 0 (the registry is not touched); the PATH it reports must have
#    ucrt64\bin in front of Git and Perl. --profile=devops --dry-run writes nothing;
#    an unknown profile exits with 1; --list-profiles exits with 0.
Write-Host ">>> Profiles and environment dry run (scratch installation)"
$scratch = Join-Path ([IO.Path]::GetTempPath()) "scoop-boot-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Path (Join-Path $scratch 'etc') -Force | Out-Null
    Copy-Item -Path (Join-Path $root 'bin') -Destination (Join-Path $scratch 'bin') -Recurse
    Copy-Item -Path (Join-Path $root 'etc/packages') -Destination (Join-Path $scratch 'etc/packages') -Recurse
    Copy-Item -Path (Join-Path $root 'etc/profiles') -Destination (Join-Path $scratch 'etc/profiles') -Recurse
    $hostName = [System.Net.Dns]::GetHostName().ToLower()
    $userName = [Environment]::UserName.ToLower()
    $scratchScript = Join-Path $scratch 'bin/scoop-boot.ps1'

    $output = & $scratchScript --list-profiles *>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0 -or -not ($output -match 'devel') -or -not ($output -match 'devops')) { Write-Host "[FAIL] --list-profiles: exit $LASTEXITCODE"; $failed++ } else { Write-Host "[OK] --list-profiles" }

    $output = & $scratchScript --profile=devops --dry-run *>&1 | ForEach-Object { "$_" }
    $exit = $LASTEXITCODE
    $written = (Test-Path (Join-Path $scratch "etc/packages/$hostName.txt")) -or (Test-Path (Join-Path $scratch "etc/environments/system.$hostName.$userName.env"))
    if ($exit -ne 0 -or $written -or -not ($output -match 'terraform') -or -not ($output -match 'DRY RUN: nothing written')) {
        $output | ForEach-Object { Write-Host "    $_" }
        Write-Host "[FAIL] --profile=devops --dry-run: exit $exit, files written: $written"
        $failed++
    } else {
        Write-Host "[OK] --profile=devops --dry-run (nothing written)"
    }

    & $scratchScript --profile=no-such-profile *> $null
    if ($LASTEXITCODE -ne 1) { Write-Host "[FAIL] unknown profile exited with $LASTEXITCODE, expected 1"; $failed++ } else { Write-Host "[OK] unknown profile exits with 1" }

    $output = & $scratchScript --profile=devel *>&1 | ForEach-Object { "$_" }
    $exit = $LASTEXITCODE
    $listFile = Join-Path $scratch "etc/packages/$hostName.txt"
    $systemFile = Join-Path $scratch "etc/environments/system.$hostName.$userName.env"
    $userFile = Join-Path $scratch "etc/environments/user.$hostName.$userName.env"
    $conf = Join-Path $scratch 'etc/scoop-boot.conf'
    if ($exit -ne 0 -or -not (Test-Path $listFile) -or -not (Test-Path $systemFile) -or -not (Test-Path $userFile) -or -not ((Get-Content $conf -Raw) -match '(?m)^PROFILE=devel$')) {
        $output | ForEach-Object { Write-Host "    $_" }
        Write-Host "[FAIL] --profile=devel: exit $exit"
        $failed++
    } else {
        Write-Host "[OK] --profile=devel ($hostName.txt, $hostName.debian.txt, system and user file, PROFILE=devel)"
    }
    & $scratchScript --profile=devel *> $null
    if ($LASTEXITCODE -ne 1) { Write-Host "[FAIL] --profile=devel on existing files exited with $LASTEXITCODE, expected 1 (kept)"; $failed++ } else { Write-Host "[OK] existing host files are kept (exit 1 without --force)" }

    if (-not $SkipDryRun) {
        $output = & $scratchScript --admin-setenv --dry-run *>&1 | ForEach-Object { "$_" }
        $exit = $LASTEXITCODE
        if ($env:SCOOP_BOOT_TEST_VERBOSE) { $output | ForEach-Object { Write-Host "    $_" } }
        # After "Net effect" the PATH is printed front to back: one entry per line on
        # Windows (the registry has a PATH to diff against), one line on a runner without
        $netEffect = ($output -join "`n")
        $netEffect = $netEffect.Substring([Math]::Max(0, $netEffect.IndexOf('Net effect')))
        $ucrt = $netEffect.IndexOf('ucrt64\bin'); $mingw = $netEffect.IndexOf('mingw64\bin'); $perl = $netEffect.IndexOf('perl\bin')
        $orderOk = ($ucrt -ge 0) -and ($mingw -gt $ucrt) -and ($perl -gt $ucrt)
        if ($exit -ne 0 -or -not ($output -match 'Net effect') -or -not $orderOk) {
            $output | ForEach-Object { Write-Host "    $_" }
            Write-Host "[FAIL] --admin-setenv --dry-run: exit $exit$(if (-not ($output -match 'Net effect')) { ', no net-effect summary' })$(if (-not $orderOk) { ', ucrt64\bin not in front of Git and Perl' })"
            $failed++
        } else {
            Write-Host "[OK] --admin-setenv --dry-run ($(@($output).Count) lines, net-effect summary, ucrt64\bin before mingw64\bin and perl\bin)"
        }
    }
} finally {
    Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""

# 4. etc/release.files names every delivered file and nothing else: every listed path
#    exists; bin\*, etc\packages\default.txt, debian.txt, etc\wsl\* and every file
#    under etc\profiles are listed (--update --branch and tools/release.sh read it)
Write-Host ">>> Delivered files (etc/release.files)"
$index = @(Get-Content (Join-Path $root 'etc/release.files') | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ })
$missing = @($index | Where-Object { -not (Test-Path (Join-Path $root $_)) })
$expected = @(Get-ChildItem -Path (Join-Path $root 'bin'), (Join-Path $root 'etc/profiles'), (Join-Path $root 'etc/wsl') -Recurse -File | ForEach-Object { $_.FullName.Substring($root.Length + 1) -replace '\\', '/' })
$expected += @('etc/packages/default.txt', 'etc/packages/debian.txt')
$unlisted = @($expected | Where-Object { $index -notcontains $_ })
if ($missing.Count -gt 0 -or $unlisted.Count -gt 0) {
    Write-Host "[FAIL] etc/release.files: missing on disk: $($missing -join ', '); not listed: $($unlisted -join ', ')"
    $failed++
} else {
    Write-Host "[OK] etc/release.files ($($index.Count) files, all present, nothing unlisted)"
}
Write-Host ""

# 5. The whole setup in fake mode (SCOOPBOOT_FAKE=1): a scratch root with bin\ and
#    etc\ from the checkout, no Scoop, no registry, no processes. --admin-init with a
#    profile, --admin-setenv, --user-install, the scoop wrapper, --export, --import on
#    the same root, --clean-user-scope and --admin-reset --force must run through with
#    the expected state after each step; nothing outside the scratch root is touched.
Write-Host ">>> Setup end to end in fake mode (scratch root)"
$fakeRoot = Join-Path ([IO.Path]::GetTempPath()) "scoop-boot-fake-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$savedFake = $env:SCOOPBOOT_FAKE
try {
    New-Item -ItemType Directory -Path $fakeRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $root 'bin') -Destination (Join-Path $fakeRoot 'bin') -Recurse
    Copy-Item -Path (Join-Path $root 'etc') -Destination (Join-Path $fakeRoot 'etc') -Recurse
    foreach ($leftover in @('environments', 'LATEST', 'release.manifest', 'release.manifest.sig')) { Remove-Item (Join-Path $fakeRoot "etc/$leftover") -Recurse -Force -ErrorAction SilentlyContinue }
    $env:SCOOPBOOT_FAKE = '1'
    $fakeScript = Join-Path $fakeRoot 'bin/scoop-boot.ps1'
    $hostName = [System.Net.Dns]::GetHostName().ToLower()
    $userName = [Environment]::UserName.ToLower()
    $registry = Join-Path $fakeRoot 'etc/fake/registry.json'
    function Read-FakeStore { if (Test-Path $registry) { Get-Content $registry -Raw | ConvertFrom-Json } else { $null } }
    function Invoke-FakeStep {
        param([string]$Name, [string[]]$Arguments, [scriptblock]$Check, [int]$ExpectedExit = 0)
        $output = & $fakeScript @Arguments *>&1 | ForEach-Object { "$_" }
        $exit = $LASTEXITCODE
        if ($env:SCOOP_BOOT_TEST_VERBOSE) { $output | ForEach-Object { Write-Host "    $_" } }
        $problem = if ($exit -ne $ExpectedExit) { "exit $exit, expected $ExpectedExit" } else { & $Check $output }
        if ($problem) {
            $output | Select-Object -Last 40 | ForEach-Object { Write-Host "    $_" }
            Write-Host "[FAIL] fake $Name`: $problem"
            $script:failed++
        } else {
            Write-Host "[OK] fake $Name"
        }
    }
    Invoke-FakeStep -Name '--admin-init --profile=java,python' -Arguments @('--admin-init', '--profile=java,python') -Check {
        param($o)
        if (-not (Test-Path (Join-Path $fakeRoot "etc/packages/$hostName.txt"))) { return 'host package list missing' }
        if (-not (Test-Path (Join-Path $fakeRoot "etc/environments/system.$hostName.$userName.env"))) { return 'system file missing' }
        if (-not ((Get-Content (Join-Path $fakeRoot 'etc/scoop-boot.conf') -Raw) -match '(?m)^PROFILE=java,python$')) { return 'PROFILE not recorded' }
        if (Test-Path (Join-Path $fakeRoot 'apps')) { return 'apps\ exists before the install' }
    }
    Invoke-FakeStep -Name '--admin-setenv' -Arguments @('--admin-setenv') -Check {
        param($o)
        $store = Read-FakeStore
        if (-not $store) { return 'no fake registry written' }
        if ($store.Machine.JAVA_HOME -ne "$fakeRoot\apps\temurin25-jdk\current") { return "Machine JAVA_HOME is '$($store.Machine.JAVA_HOME)'" }
        if ($store.Machine.PSObject.Properties.Name -contains 'MSYS2_HOME') { return 'MSYS2_HOME set although c++ is not in the profile' }
        if (-not ("$($store.Machine.Path)" -like "$fakeRoot\bin;$fakeRoot\shims;*")) { return "Machine PATH does not start with bin;shims: $($store.Machine.Path)" }
    }
    Invoke-FakeStep -Name '--user-install' -Arguments @('--user-install') -Check {
        param($o)
        foreach ($app in @('scoop', 'git', '7zip', 'temurin25-jdk', 'maven', 'python314', 'gh')) {
            if (-not (Test-Path (Join-Path $fakeRoot "apps/$app/current"))) { return "apps\$app\current missing" }
        }
        if (Test-Path (Join-Path $fakeRoot 'apps/msys2')) { return 'msys2 installed although c++ is not in the profile' }
        if (-not ($o -match 'Packages: 10 installed, 0 already installed, 0 skipped, 0 failed')) { return 'summary line not as expected' }
        $store = Read-FakeStore
        if ($store.User.PSObject.Properties.Name -contains 'JAVA_HOME') { return 'User JAVA_HOME survived the cleanup' }
        if ("$($store.User.Path)" -match 'apps') { return "User PATH still has Scoop entries: $($store.User.Path)" }
    }
    Invoke-FakeStep -Name '--user-install (second run)' -Arguments @('--user-install') -Check {
        param($o)
        if (-not ($o -match 'Packages: 0 installed, 10 already installed, 0 skipped, 0 failed')) { return 'second run did not find everything installed' }
    }
    $wrapper = Join-Path $fakeRoot 'bin/scoop.ps1'
    $output = & $wrapper install extras/hxd *>&1 | ForEach-Object { "$_" }
    $store = Read-FakeStore
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $fakeRoot 'apps/hxd/current')) -or ("$($store.User.Path)" -match 'hxd') -or -not ($output -match 'user scope cleaned')) {
        $output | ForEach-Object { Write-Host "    $_" }
        Write-Host "[FAIL] fake scoop wrapper: install extras/hxd (exit $LASTEXITCODE, User PATH '$($store.User.Path)')"
        $failed++
    } else {
        Write-Host "[OK] fake scoop wrapper: install extras/hxd, user scope cleaned afterwards"
    }
    Invoke-FakeStep -Name '--export=fakeExport' -Arguments @('--export=fakeExport') -Check {
        param($o)
        $export = Join-Path $fakeRoot 'etc/exports/fakeExport.txt'
        if (-not (Test-Path $export)) { return 'export file missing' }
        $text = Get-Content $export -Raw
        if (-not ($text -match '(?m)^extras/hxd\s') -or -not ($text -match '(?m)^temurin25-jdk\s') -or -not ($text -match '(?m)^# bucket extras ')) { return 'export content not as expected' }
    }
    Invoke-FakeStep -Name '--import=fakeExport --dry-run' -Arguments @('--import=fakeExport', '--dry-run') -Check {
        param($o)
        if (-not ($o -match 'extras/hxd')) { return 'hxd not reported as missing from the host list' }
        if (($o -join "`n") -match '(?m)^\s*temurin25-jdk\s*$') { return 'temurin25-jdk reported as missing although listed' }
    }
    Invoke-FakeStep -Name '--list-packages' -Arguments @('--list-packages') -Check {
        param($o)
        if (-not ($o -match 'temurin25-jdk\s+installed')) { return 'temurin25-jdk not shown as installed' }
        if (-not ($o -match "Package list: .*$hostName\.txt")) { return 'host list not in use' }
    }
    Invoke-FakeStep -Name '--admin-reset --force' -Arguments @('--admin-reset', '--force') -Check {
        param($o)
        foreach ($dir in @('apps', 'buckets', 'shims')) { if (Test-Path (Join-Path $fakeRoot $dir)) { return "$dir\ still there" } }
        foreach ($dir in @('bin', 'etc')) { if (-not (Test-Path (Join-Path $fakeRoot $dir))) { return "$dir\ deleted" } }
        $store = Read-FakeStore
        if ($store.Machine.PSObject.Properties.Name -contains 'JAVA_HOME') { return 'Machine JAVA_HOME survived the reset' }
        if ("$($store.Machine.Path)" -match 'apps|shims') { return "Machine PATH still has Scoop entries: $($store.Machine.Path)" }
        if ($store.Machine.TMP -ne 'C:\tmp') { return 'TMP (not Scoop''s) was removed' }
    }
} finally {
    if ($null -eq $savedFake) { Remove-Item Env:SCOOPBOOT_FAKE -ErrorAction SilentlyContinue } else { $env:SCOOPBOOT_FAKE = $savedFake }
    Remove-Item $fakeRoot -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""

# 6. Help, version and the unknown-option path
Write-Host ">>> Command line"
& $scoopBoot --help *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "[FAIL] --help exited with $LASTEXITCODE"; $failed++ } else { Write-Host "[OK] --help" }
& $scoopBoot --version *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "[FAIL] --version exited with $LASTEXITCODE"; $failed++ } else { Write-Host "[OK] --version" }
& $scoopBoot --no-such-option *> $null
if ($LASTEXITCODE -ne 1) { Write-Host "[FAIL] unknown option exited with $LASTEXITCODE, expected 1"; $failed++ } else { Write-Host "[OK] unknown option exits with 1" }

# 7. Rescue mode: the script alone, without bin\scoop-boot.psm1, as the Quick Setup
#    starts. --version answers, a working command is refused with the --update hint,
#    --admin-init is let through to the download. The download is aimed at a branch
#    that does not exist, so it fails (with or without network) and nothing is
#    installed; what counts is the "downloading the release first" line and exit 1
#    without the --update hint
Write-Host ">>> Rescue mode (script without the module)"
$rescue = Join-Path ([IO.Path]::GetTempPath()) "scoop-boot-rescue-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
try {
    New-Item -ItemType Directory -Path (Join-Path $rescue 'bin') -Force | Out-Null
    Copy-Item -Path $scoopBoot -Destination (Join-Path $rescue 'bin/scoop-boot.ps1')
    $alone = Join-Path $rescue 'bin/scoop-boot.ps1'
    $output = & $alone --version *>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 0 -or -not ($output -match 'module not loaded')) { Write-Host "[FAIL] rescue --version: exit $LASTEXITCODE"; $failed++ } else { Write-Host "[OK] rescue --version" }
    $output = & $alone --user-install *>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 1 -or -not ($output -match 'Only --update, --version and --help work')) { Write-Host "[FAIL] rescue --user-install: exit $LASTEXITCODE, hint missing"; $failed++ } else { Write-Host "[OK] rescue refuses --user-install with the --update hint" }
    $output = & $alone --admin-init --branch=scoop-boot-test-no-such-branch *>&1 | ForEach-Object { "$_" }
    if ($LASTEXITCODE -ne 1 -or -not ($output -match 'downloading the release first') -or ($output -match 'Only --update')) { Write-Host "[FAIL] rescue --admin-init: exit $LASTEXITCODE"; $output | ForEach-Object { Write-Host "    $_" }; $failed++ } else { Write-Host "[OK] rescue --admin-init goes to the download first" }
} finally {
    Remove-Item $rescue -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ""

if ($failed -eq 0) {
    Write-Host "[OK] All checks passed"
    exit 0
}
Write-Host "[FAIL] $failed check(s) failed"
exit 1
