#!/usr/bin/env bash
# Cuts a scoop-boot release: manifest, SSH signature, LATEST pointer, commit, tag, push.
#
#   tools/release.sh v0020            # from the repository root, on main, after the squash merge
#   tools/release.sh v0020 --no-push  # commit and tag only
#   KEY=~/.ssh/other_key tools/release.sh v0020
#
# Steps, each checked before the next:
#   1. main, clean working tree, tag unused, version in bin/scoop-boot.ps1 printed
#   2. etc/allowed_signers: created from the public key when missing (principal and
#      namespace "scoop-boot"); must contain the signing key otherwise; the README must
#      name the key's fingerprint
#   3. etc/release.manifest: tag, date, SHA-256 of every delivered file, taken from the
#      committed blobs (git cat-file): raw.githubusercontent.com serves the blob, and
#      .gitattributes checks bin/scoop.cmd out with CRLF
#   4. etc/release.manifest.sig: ssh-keygen -Y sign (a passphrase is asked for, or
#      the agent answers); a failed signature restores the manifest and the old
#      signature from HEAD
#   5. verified with ssh-keygen -Y verify, the manifest bytes on standard input, as
#      scoop-boot.ps1 --update does it
#   6. etc/LATEST = tag; commit "release <tag>", tag, push main and the tag
#
# --update on every machine then reads LATEST, verifies the manifest with the key in
# its local etc/allowed_signers and compares every file with the manifest before
# writing anything.

set -euo pipefail
# A command that fails under set -e would otherwise end the script without a word.
# Once the manifest is rewritten (and the old signature removed), an abort, for
# example a mistyped passphrase at ssh-keygen, restores both files from HEAD so
# that the next run starts from a clean tree.
manifest_written=
abort() {
    echo "[ERROR] aborted at line $1: $2" >&2
    if [ -n "$manifest_written" ]; then
        git checkout -- etc/release.manifest etc/release.manifest.sig 2>/dev/null || true
        echo "[INFO] etc/release.manifest and etc/release.manifest.sig restored from HEAD; run the script again" >&2
    fi
}
trap 'abort $LINENO "$BASH_COMMAND"' ERR

TAG="${1:-}"
NO_PUSH="${2:-}"
KEY="${KEY:-$HOME/.ssh/id_ed25519}"
DELIVERED="bin/scoop-boot.ps1 bin/scoop-boot.psm1 bin/scoop.ps1 bin/scoop.cmd bin/scoop etc/packages/default.txt etc/packages/debian.txt etc/wsl/debian-setup.sh"

fail() { echo "[ERROR] $*" >&2; exit 1; }
ok()   { echo "[OK] $*"; }

# 1. Preconditions
[ -f bin/scoop-boot.ps1 ] && [ -d .git ] || fail "run from the repository root (bin/scoop-boot.ps1 and .git expected)"
[[ "$TAG" =~ ^v[0-9]{4}$ ]] || fail "usage: tools/release.sh vNNNN [--no-push]  (got '$TAG')"
[ -z "$NO_PUSH" ] || [ "$NO_PUSH" = "--no-push" ] || fail "unknown option '$NO_PUSH'"
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = "main" ] || fail "releases are cut on main (current branch: $branch)"
[ -z "$(git status --porcelain)" ] || { git status --short; fail "working tree is not clean"; }
[ -z "$(git tag --list "$TAG")" ] || fail "tag $TAG exists already"
version=$(sed -n 's/^ *Version: *\([0-9.]*\).*/\1/p' bin/scoop-boot.ps1 | head -1)
ok "main is clean; scoop-boot.ps1 version $version; release $TAG"

command -v ssh-keygen >/dev/null || fail "ssh-keygen not found"
[ -f "$KEY" ] || fail "signing key not found: $KEY"
[ -f "$KEY.pub" ] || fail "public key not found: $KEY.pub"
# read returns 1 at end of file without a trailing newline, the variables are set anyway
read -r key_type key_blob _ < "$KEY.pub" || true
[ -n "$key_type" ] && [ -n "$key_blob" ] || fail "public key file is not in OpenSSH format: $KEY.pub"

# 2. allowed_signers and the README fingerprint
allowed=etc/allowed_signers
if [ ! -f "$allowed" ]; then
    printf 'scoop-boot namespaces="scoop-boot" %s %s scoop-boot release key\n' "$key_type" "$key_blob" > "$allowed"
    ok "created $allowed from $KEY.pub"
elif ! grep -qF "$key_blob" "$allowed"; then
    fail "$allowed does not contain the key from $KEY.pub. A new key is a new trust anchor: update the file and the README fingerprint on purpose"
fi
fingerprint=$(ssh-keygen -lf "$KEY.pub" | awk '{print $2}')
ok "signing key fingerprint $fingerprint"
grep -qF "$fingerprint" README.md || fail "README.md does not name the fingerprint $fingerprint; add it to the Quick Setup before releasing"

# 3. Manifest (LF, no BOM: the signature covers these exact bytes)
manifest=etc/release.manifest
{
    echo "# scoop-boot release manifest: written by tools/release.sh, verified by scoop-boot.ps1 --update"
    echo "tag $TAG"
    echo "date $(date +%Y-%m-%d)"
    for rel in $DELIVERED; do
        [ -f "$rel" ] || fail "delivered file missing: $rel"
        echo "sha256 $(git cat-file blob "HEAD:$rel" | sha256sum | cut -c1-64) $rel"
    done
} > "$manifest"
manifest_written=1
ok "$manifest written ($(grep -c '^sha256 ' "$manifest") files)"

# 4. Signature
rm -f "$manifest.sig"
ssh-keygen -Y sign -f "$KEY" -n scoop-boot "$manifest"
[ -f "$manifest.sig" ] || fail "ssh-keygen -Y sign produced no $manifest.sig"
ok "$manifest.sig written"

# 5. Verify as --update does: manifest bytes on standard input, principal and namespace scoop-boot
result=$(ssh-keygen -Y verify -f "$allowed" -I scoop-boot -n scoop-boot -s "$manifest.sig" < "$manifest") || fail "verification failed: $result"
ok "$result"

# 6. LATEST, commit, tag, push
printf '%s\n' "$TAG" > etc/LATEST
git add etc/release.manifest etc/release.manifest.sig etc/allowed_signers etc/LATEST
git commit -m "release $TAG"
manifest_written=
git tag "$TAG"
if [ "$NO_PUSH" = "--no-push" ]; then
    ok "committed and tagged; push with: git push origin main $TAG"
else
    git push origin main "$TAG"
    ok "release $TAG pushed; machines pick it up with scoop-boot.ps1 --update"
fi
