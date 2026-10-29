<#
.SYNOPSIS
    Runs the scoop-boot checks from a repository checkout: parse check of every script,
    the self-tests, and (on Windows) the environment dry run against the templates.
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

# 3. Dry run against the shipped templates in a scratch installation: bin\ and
#    etc\packages copied, the templates renamed to this host and user. The dry run
#    must end with the net-effect summary and exit 0; the registry is not touched.
if (-not $SkipDryRun) {
    Write-Host ">>> Environment dry run against the templates (scratch installation)"
    $scratch = Join-Path ([IO.Path]::GetTempPath()) "scoop-boot-test-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    try {
        New-Item -ItemType Directory -Path (Join-Path $scratch 'etc/environments') -Force | Out-Null
        Copy-Item -Path (Join-Path $root 'bin') -Destination (Join-Path $scratch 'bin') -Recurse
        Copy-Item -Path (Join-Path $root 'etc/packages') -Destination (Join-Path $scratch 'etc/packages') -Recurse
        $hostName = [System.Net.Dns]::GetHostName().ToLower()
        $userName = [Environment]::UserName.ToLower()
        foreach ($scope in @('system', 'user')) {
            Copy-Item -Path (Join-Path $root "etc/environments/$scope.hostname.username.env") -Destination (Join-Path $scratch "etc/environments/$scope.$hostName.$userName.env")
        }
        $output = & (Join-Path $scratch 'bin/scoop-boot.ps1') --admin-setenv --dry-run *>&1 | ForEach-Object { "$_" }
        $exit = $LASTEXITCODE
        if ($env:SCOOP_BOOT_TEST_VERBOSE) { $output | ForEach-Object { Write-Host "    $_" } }
        if ($exit -ne 0 -or -not ($output -match 'Net effect')) {
            $output | ForEach-Object { Write-Host "    $_" }
            Write-Host "[FAIL] --admin-setenv --dry-run: exit $exit$(if (-not ($output -match 'Net effect')) { ', no net-effect summary' })"
            $failed++
        } else {
            Write-Host "[OK] --admin-setenv --dry-run ($(@($output).Count) lines, net-effect summary present)"
        }
    } finally {
        Remove-Item $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host ""
}

# 4. Help, version and the unknown-option path
Write-Host ">>> Command line"
& $scoopBoot --help *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "[FAIL] --help exited with $LASTEXITCODE"; $failed++ } else { Write-Host "[OK] --help" }
& $scoopBoot --version *> $null
if ($LASTEXITCODE -ne 0) { Write-Host "[FAIL] --version exited with $LASTEXITCODE"; $failed++ } else { Write-Host "[OK] --version" }
& $scoopBoot --no-such-option *> $null
if ($LASTEXITCODE -ne 1) { Write-Host "[FAIL] unknown option exited with $LASTEXITCODE, expected 1"; $failed++ } else { Write-Host "[OK] unknown option exits with 1" }
Write-Host ""

if ($failed -eq 0) {
    Write-Host "[OK] All checks passed"
    exit 0
}
Write-Host "[FAIL] $failed check(s) failed"
exit 1
