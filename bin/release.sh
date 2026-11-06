#!/usr/bin/env bash
# Cuts a release of a Git repository: file manifest, SSH signature, LATEST pointer,
# commit, signed annotated tag, push. Written for scoop-boot, usable by any repository
# that follows the same layout (delivered by scoop-boot to C:\usr\bin, so it is on the
# PATH of Git Bash).
#
#   release.sh v0056                 # inside the repository, on the main branch, pushed
#   release.sh v0056 --no-push       # commit and tag only
#   release.sh v1.2.0 --no-sign      # annotated tag without a signature
#   KEY=~/.ssh/other_key release.sh v0056
#
# Configuration: etc/release.conf in the repository (bash, NAME=VALUE), every line
# optional. Defaults in brackets:
#   NAMESPACE        principal and namespace of the SSH signature       [repository directory name]
#   TAG_PATTERN      extended regular expression a tag must match       [^v[0-9]+\.[0-9]+\.[0-9]+$]
#   VERSION_FILE     file whose version is printed with the tag         [none]
#   VERSION_REGEX    sed expression, \1 is the version                  [^ *Version: *\([0-9.]*\)]
#   FINGERPRINT_FILE file that must name the signing key's fingerprint  [README.md]
#   RELEASE_DIR      directory of release.files, release.manifest, LATEST, allowed_signers [etc]
#   MAIN_BRANCH      branch releases are cut on                         [main]
#   KEY              private key that signs the manifest; the environment wins [~/.ssh/id_ed25519]
#
# Steps, each checked before the next:
#   1. inside a repository, on MAIN_BRANCH, clean working tree, tag matches and is
#      unused, HEAD is what origin/MAIN_BRANCH has (push first: the CI of that commit
#      is the release test), version of VERSION_FILE printed
#   2. RELEASE_DIR/allowed_signers: created from the public key when missing
#      (principal and namespace NAMESPACE); must contain the signing key otherwise;
#      FINGERPRINT_FILE must name the key's fingerprint
#   3. RELEASE_DIR/release.manifest: tag, date, SHA-256 of every file listed in
#      RELEASE_DIR/release.files, taken from the committed blobs (git cat-file):
#      raw.githubusercontent.com serves the blob, .gitattributes may check a file out
#      with other line endings
#   4. release.manifest.sig: ssh-keygen -Y sign (a passphrase is asked for, or the
#      agent answers); a run that fails after the manifest was written restores the
#      manifest and the old signature from HEAD
#   5. verified with ssh-keygen -Y verify, the manifest bytes on standard input, as
#      scoop-boot.ps1 --update does it
#   6. RELEASE_DIR/LATEST = tag; commit "release <tag>"; tag -s (git's SSH signing:
#      gpg.format ssh and user.signingkey) or -a with --no-sign; push branch and tag
#
# scoop-boot.ps1 --update on every machine then reads LATEST, verifies the manifest
# with the key in its local etc/allowed_signers and compares every file with the
# manifest before writing anything.

set -euo pipefail

fail() { echo "[ERROR] $*" >&2; exit 1; }
ok()   { echo "[OK] $*"; }

# Once the manifest is rewritten (and the old signature removed), any exit before the
# commit, fail() included, restores both files from HEAD so that the next run starts
# from a clean tree. An EXIT trap sees every exit; an ERR trap does not see exit 1.
manifest_written=
allowed_created=
restore() {
    # back to HEAD's copy, or gone when HEAD has none (first release of a repository)
    if git cat-file -e "HEAD:$1" 2>/dev/null; then git checkout -- "$1"; else rm -f "$1"; fi
}
on_exit() {
    local rc=$1
    [ "$rc" -ne 0 ] || return 0
    if [ -n "$manifest_written" ]; then
        restore "$manifest"; restore "$manifest.sig"
        echo "[INFO] $manifest and $manifest.sig restored; run the script again" >&2
    fi
    if [ -n "$allowed_created" ]; then
        rm -f "$allowed"
        echo "[INFO] $allowed removed again (it is created by a successful run)" >&2
    fi
}
trap 'on_exit $?' EXIT
trap 'echo "[ERROR] command failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# 0. Arguments, repository, configuration
TAG="${1:-}"
NO_PUSH=
NO_SIGN=
shift $(( $# > 0 ? 1 : 0 ))
for opt in "$@"; do
    case "$opt" in
        --no-push) NO_PUSH=1 ;;
        --no-sign) NO_SIGN=1 ;;
        *) fail "unknown option '$opt' (usage: release.sh TAG [--no-push] [--no-sign])" ;;
    esac
done
[ -n "$TAG" ] || fail "usage: release.sh TAG [--no-push] [--no-sign]"

top=$(git rev-parse --show-toplevel 2>/dev/null) || fail "not inside a Git repository"
cd "$top"
env_key="${KEY:-}"
RELEASE_DIR="${RELEASE_DIR:-etc}"
NAMESPACE="${NAMESPACE:-$(basename "$top")}"
TAG_PATTERN='^v[0-9]+\.[0-9]+\.[0-9]+$'
VERSION_FILE=
VERSION_REGEX='^ *Version: *\([0-9.]*\)'
FINGERPRINT_FILE=README.md
MAIN_BRANCH=main
if [ -f "$RELEASE_DIR/release.conf" ]; then
    # shellcheck disable=SC1090
    . "$RELEASE_DIR/release.conf"
    ok "configuration $RELEASE_DIR/release.conf (namespace $NAMESPACE)"
else
    ok "no $RELEASE_DIR/release.conf, defaults (namespace $NAMESPACE, tags vX.Y.Z)"
fi
KEY="${env_key:-${KEY:-$HOME/.ssh/id_ed25519}}"
files="$RELEASE_DIR/release.files"
manifest="$RELEASE_DIR/release.manifest"
allowed="$RELEASE_DIR/allowed_signers"
latest="$RELEASE_DIR/LATEST"

# 1. Preconditions
[[ "$TAG" =~ $TAG_PATTERN ]] || fail "tag '$TAG' does not match $TAG_PATTERN"
[ -f "$files" ] || fail "$files not found: one delivered file per line, '#' starts a comment"
DELIVERED=$(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$files" | tr '\n' ' ')
[ -n "$DELIVERED" ] || fail "$files lists no file"
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = "$MAIN_BRANCH" ] || fail "releases are cut on $MAIN_BRANCH (current branch: $branch)"
[ -z "$(git status --porcelain)" ] || { git status --short; fail "working tree is not clean"; }
[ -z "$(git tag --list "$TAG")" ] || fail "tag $TAG exists already"
git fetch --quiet origin "$MAIN_BRANCH" || fail "git fetch origin $MAIN_BRANCH failed"
[ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$MAIN_BRANCH")" ] ||
    fail "HEAD is not origin/$MAIN_BRANCH: push first (the CI run of that commit is the release test), or pull"
version=
if [ -n "$VERSION_FILE" ]; then
    [ -f "$VERSION_FILE" ] || fail "VERSION_FILE not found: $VERSION_FILE"
    version=$(sed -n "s/$VERSION_REGEX.*/\\1/p" "$VERSION_FILE" | head -1)
    [ -n "$version" ] || fail "no version in $VERSION_FILE matches VERSION_REGEX"
fi
ok "$MAIN_BRANCH is clean and pushed${version:+; $VERSION_FILE version $version}; release $TAG"

command -v ssh-keygen >/dev/null || fail "ssh-keygen not found"
[ -f "$KEY" ] || fail "signing key not found: $KEY"
[ -f "$KEY.pub" ] || fail "public key not found: $KEY.pub"
# read returns 1 at end of file without a trailing newline, the variables are set anyway
read -r key_type key_blob _ < "$KEY.pub" || true
[ -n "$key_type" ] && [ -n "$key_blob" ] || fail "public key file is not in OpenSSH format: $KEY.pub"
if [ -z "$NO_SIGN" ]; then
    [ "$(git config --get gpg.format || true)" = "ssh" ] && [ -n "$(git config --get user.signingkey || true)" ] ||
        fail "git tag -s needs gpg.format=ssh and user.signingkey (git config --global gpg.format ssh; git config --global user.signingkey $KEY.pub), or use --no-sign"
fi

# 2. allowed_signers and the fingerprint
if [ ! -f "$allowed" ]; then
    printf '%s namespaces="%s" %s %s %s release key\n' "$NAMESPACE" "$NAMESPACE" "$key_type" "$key_blob" "$NAMESPACE" > "$allowed"
    allowed_created=1
    ok "created $allowed from $KEY.pub"
elif ! grep -qF "$key_blob" "$allowed"; then
    fail "$allowed does not contain the key from $KEY.pub. A new key is a new trust anchor: update the file and the fingerprint in $FINGERPRINT_FILE on purpose"
fi
fingerprint=$(ssh-keygen -lf "$KEY.pub" | awk '{print $2}')
ok "signing key fingerprint $fingerprint"
[ -f "$FINGERPRINT_FILE" ] || fail "FINGERPRINT_FILE not found: $FINGERPRINT_FILE"
grep -qF "$fingerprint" "$FINGERPRINT_FILE" || fail "$FINGERPRINT_FILE does not name the fingerprint $fingerprint; add it before releasing"

# 3. Manifest (LF, no BOM: the signature covers these exact bytes)
manifest_written=1
{
    echo "# $NAMESPACE release manifest: written by release.sh, verified by scoop-boot.ps1 --update"
    echo "tag $TAG"
    echo "date $(date +%Y-%m-%d)"
    for rel in $DELIVERED; do
        [ -f "$rel" ] || fail "delivered file missing: $rel"
        echo "sha256 $(git cat-file blob "HEAD:$rel" | sha256sum | cut -c1-64) $rel"
    done
} > "$manifest"
ok "$manifest written ($(grep -c '^sha256 ' "$manifest") files)"

# 4. Signature
rm -f "$manifest.sig"
ssh-keygen -Y sign -f "$KEY" -n "$NAMESPACE" "$manifest"
[ -f "$manifest.sig" ] || fail "ssh-keygen -Y sign produced no $manifest.sig"
ok "$manifest.sig written"

# 5. Verify as --update does: manifest bytes on standard input, principal and namespace NAMESPACE
result=$(ssh-keygen -Y verify -f "$allowed" -I "$NAMESPACE" -n "$NAMESPACE" -s "$manifest.sig" < "$manifest") || fail "verification failed: $result"
ok "$result"

# 6. LATEST, commit, tag, push
printf '%s\n' "$TAG" > "$latest"
git add "$manifest" "$manifest.sig" "$allowed" "$latest"
git commit --quiet -m "release $TAG"
manifest_written=
if [ -n "$NO_SIGN" ]; then
    git tag -a -m "release $TAG" "$TAG"
    ok "committed; annotated tag $TAG (not signed)"
else
    git tag -s -m "release $TAG" "$TAG"
    ok "committed; signed tag $TAG"
fi
if [ -n "$NO_PUSH" ]; then
    ok "push with: git push origin $MAIN_BRANCH $TAG"
else
    git push --quiet origin "$MAIN_BRANCH" "$TAG"
    ok "release $TAG pushed; machines pick it up with scoop-boot.ps1 --update"
fi
