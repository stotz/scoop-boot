<#
.SYNOPSIS
    Cuts a scoop-boot release: manifest, SSH signature, LATEST pointer, commit, tag, push.

.DESCRIPTION
    Run from the repository root on main after the squash merge of a stage:

        tools\release.ps1 -Tag v0019

    Steps, each one checked before the next:
      1. main, clean working tree, tag unused, version in bin\scoop-boot.ps1 printed
      2. etc\allowed_signers: created from the public key when missing (principal
         and namespace "scoop-boot"); must contain the signing key otherwise
      3. etc\release.manifest: tag, date, SHA-256 of every delivered file
      4. etc\release.manifest.sig: ssh-keygen -Y sign with the SSH key (the same
         key that signs the commits; a passphrase is asked for, or the agent answers)
      5. the signature is verified the way --update verifies it (stdin bytes
         through a .NET process, never a PowerShell pipe)
      6. etc\LATEST = tag; commit "release <tag>", tag, push main and the tag

    --update on every machine then reads LATEST, verifies the manifest with the
    key in its local etc\allowed_signers and compares every file with the
    manifest before writing anything.

.PARAMETER Tag
    Release tag, four digits: v0019.
.PARAMETER Key
    Private SSH key used for signing; default ~\.ssh\id_ed25519. The matching
    .pub file provides the key for allowed_signers.
.PARAMETER NoPush
    Commit and tag only; push by hand.
#>
param(
    [Parameter(Mandatory = $true)][string]$Tag,
    [string]$Key = (Join-Path $env:USERPROFILE '.ssh\id_ed25519'),
    [switch]$NoPush
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The files --update delivers; the manifest is their only list
$deliveredFiles = @('bin/scoop-boot.ps1', 'bin/scoop-boot.psm1', 'bin/scoop.ps1', 'bin/scoop.cmd', 'bin/scoop', 'etc/packages/default.txt')

function Fail { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red; exit 1 }

# 1. Preconditions
if (-not (Test-Path 'bin\scoop-boot.ps1') -or -not (Test-Path '.git')) { Fail "Run from the repository root (bin\scoop-boot.ps1 and .git expected)" }
if ($Tag -notmatch '^v\d{4}$') { Fail "Tag must look like v0019, got '$Tag'" }
$branch = (git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'main') { Fail "Releases are cut on main (current branch: $branch)" }
$dirty = @(git status --porcelain)
if ($dirty.Count -gt 0) { Fail "Working tree is not clean:`n$($dirty -join "`n")" }
if ((git tag --list $Tag)) { Fail "Tag $Tag exists already" }
$autocrlf = (git config --get core.autocrlf)
if ($autocrlf -eq 'true') { Write-Host "[WARN] core.autocrlf=true; .gitattributes forces LF, the hashes below are taken from the working tree" -ForegroundColor Yellow }
$version = (Select-String -Path 'bin\scoop-boot.ps1' -Pattern 'Version:\s*([0-9.]+)' | Select-Object -First 1).Matches[0].Groups[1].Value
Write-Host "[OK] main is clean; scoop-boot.ps1 version $version; release $Tag" -ForegroundColor Green

$sshKeygen = Join-Path $env:SystemRoot 'System32\OpenSSH\ssh-keygen.exe'
if (-not (Test-Path $sshKeygen)) { $sshKeygen = (Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue).Source }
if (-not $sshKeygen) { Fail "ssh-keygen.exe not found" }
if (-not (Test-Path $Key)) { Fail "Signing key not found: $Key" }
$pubFile = "$Key.pub"
if (-not (Test-Path $pubFile)) { Fail "Public key not found: $pubFile" }
$pub = (Get-Content $pubFile -Raw).Trim()
$pubParts = $pub -split '\s+'
if ($pubParts.Count -lt 2) { Fail "Public key file is not in OpenSSH format: $pubFile" }
$keyType = $pubParts[0]; $keyBlob = $pubParts[1]

# 2. allowed_signers
$allowed = 'etc\allowed_signers'
if (-not (Test-Path $allowed)) {
    $line = "scoop-boot namespaces=`"scoop-boot`" $keyType $keyBlob scoop-boot release key"
    [IO.File]::WriteAllText($allowed, "$line`n", (New-Object Text.UTF8Encoding($false)))
    Write-Host "[OK] Created $allowed from $pubFile" -ForegroundColor Green
} elseif (-not ((Get-Content $allowed -Raw) -match [regex]::Escape($keyBlob))) {
    Fail "$allowed does not contain the key from $pubFile. A new key means a new trust anchor: update the file and the README fingerprint on purpose"
}
$sha = [Security.Cryptography.SHA256]::Create().ComputeHash([Convert]::FromBase64String($keyBlob))
$fingerprint = 'SHA256:' + [Convert]::ToBase64String($sha).TrimEnd('=')
Write-Host "[OK] Signing key fingerprint $fingerprint" -ForegroundColor Green
if (-not ((Get-Content 'README.md' -Raw) -match [regex]::Escape($fingerprint))) {
    Fail "README.md does not name the fingerprint $fingerprint; add it to the Quick Setup before releasing"
}

# 3. Manifest (LF, no BOM: the signature covers these exact bytes). The hashes are
# taken from the committed blobs, not from the working tree: raw.githubusercontent.com
# serves the blob, and .gitattributes may check a file out with other line endings
# (bin\scoop.cmd is CRLF on disk).
function Get-BlobSha256 {
    param([string]$Rel)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    $psi.Arguments = "cat-file blob HEAD:$Rel"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $ms = New-Object IO.MemoryStream
    $p.StandardOutput.BaseStream.CopyTo($ms)
    $err = $p.StandardError.ReadToEnd(); $p.WaitForExit()
    if ($p.ExitCode -ne 0) { Fail "git cat-file HEAD:$Rel failed: $($err.Trim())" }
    $sha = [Security.Cryptography.SHA256]::Create().ComputeHash($ms.ToArray())
    return (($sha | ForEach-Object { $_.ToString('x2') }) -join '')
}
$lines = @("# scoop-boot release manifest: written by tools/release.ps1, verified by scoop-boot.ps1 --update", "tag $Tag", "date $(Get-Date -Format 'yyyy-MM-dd')")
foreach ($rel in $deliveredFiles) {
    if (-not (Test-Path ($rel -replace '/', '\'))) { Fail "Delivered file missing: $rel" }
    $lines += "sha256 $(Get-BlobSha256 -Rel $rel) $rel"
}
$manifest = 'etc\release.manifest'
[IO.File]::WriteAllText($manifest, (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
Write-Host "[OK] $manifest written ($($deliveredFiles.Count) files)" -ForegroundColor Green

# 4. Signature
$signature = "$manifest.sig"
Remove-Item $signature -Force -ErrorAction SilentlyContinue
& $sshKeygen -Y sign -f $Key -n scoop-boot $manifest
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $signature)) { Fail "ssh-keygen -Y sign failed (exit $LASTEXITCODE)" }
Write-Host "[OK] $signature written" -ForegroundColor Green

# 5. Verify as --update does
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $sshKeygen
$psi.Arguments = "-Y verify -f `"$(Resolve-Path $allowed)`" -I scoop-boot -n scoop-boot -s `"$(Resolve-Path $signature)`""
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$p = [Diagnostics.Process]::Start($psi)
$bytes = [IO.File]::ReadAllBytes((Resolve-Path $manifest))
$p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length); $p.StandardInput.Close()
$out = $p.StandardOutput.ReadToEnd() + $p.StandardError.ReadToEnd(); $p.WaitForExit()
if ($p.ExitCode -ne 0 -or $out -notmatch '^Good ') { Fail "Verification failed: $($out.Trim())" }
Write-Host "[OK] $($out.Trim())" -ForegroundColor Green

# 6. LATEST, commit, tag, push
[IO.File]::WriteAllText('etc\LATEST', "$Tag`n", (New-Object Text.UTF8Encoding($false)))
git add etc/release.manifest etc/release.manifest.sig etc/allowed_signers etc/LATEST
git commit -m "release $Tag"
if ($LASTEXITCODE -ne 0) { Fail "git commit failed" }
git tag $Tag
if ($LASTEXITCODE -ne 0) { Fail "git tag failed" }
if ($NoPush) {
    Write-Host "[OK] Committed and tagged; push with: git push origin main $Tag" -ForegroundColor Green
} else {
    git push origin main $Tag
    if ($LASTEXITCODE -ne 0) { Fail "git push failed" }
    Write-Host "[OK] Release $Tag pushed; machines pick it up with scoop-boot.ps1 --update" -ForegroundColor Green
}
