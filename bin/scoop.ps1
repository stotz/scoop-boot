<#
.SYNOPSIS
    scoop wrapper from scoop-boot. Transparent for every Scoop command.
.DESCRIPTION
    C:\usr\bin is on PATH before C:\usr\shims, so this file is found before Scoop's
    own shim. It forwards everything to the real Scoop and, after commands that
    change the installation (install, update, uninstall, reset, cleanup, hold,
    unhold), runs "scoop-boot.ps1 --clean-user-scope --quiet": Scoop writes
    JAVA_HOME, PATH entries and more into the User scope on each of these, which
    would override the Machine values from the system.*.env file.

    One command that Scoop itself does not have:
        scoop upgrade        = scoop update; scoop update -a; scoop cleanup -a;
                               then clean the user scope

    Bypass: call C:\usr\shims\scoop directly, or set SCOOP_BOOT_WRAPPER=off
    (scoop-complete-install.ps1 does that during Phase 2).
#>
param()

$realScoop = Join-Path $PSScriptRoot '..\shims\scoop.ps1'
$scoopBoot = Join-Path $PSScriptRoot 'scoop-boot.ps1'

if (-not (Test-Path $realScoop)) {
    Write-Host "[ERROR] Scoop is not installed: $realScoop not found. Run scoop-complete-install.ps1 -InstallTools" -ForegroundColor Red
    exit 1
}

$command = if ($args.Count -gt 0) { "$($args[0])".ToLower() } else { '' }
$stateChanging = @('install', 'update', 'uninstall', 'reset', 'cleanup', 'hold', 'unhold')

if ($env:SCOOP_BOOT_WRAPPER -eq 'off' -or -not (Test-Path $scoopBoot)) {
    & $realScoop @args
    $rc = $LASTEXITCODE; if ($null -eq $rc) { $rc = 0 }
    exit $rc
}

if ($command -eq 'upgrade') {
    Write-Host "[scoop-boot] scoop upgrade: update, update -a, cleanup -a, clean user scope" -ForegroundColor DarkCyan
    & $realScoop update
    & $realScoop update -a
    $rc = $LASTEXITCODE; if ($null -eq $rc) { $rc = 0 }
    & $realScoop cleanup -a
    & $scoopBoot --clean-user-scope --quiet
    exit $rc
}

& $realScoop @args
$rc = $LASTEXITCODE; if ($null -eq $rc) { $rc = 0 }
if ($stateChanging -contains $command) {
    & $scoopBoot --clean-user-scope --quiet
}
exit $rc
