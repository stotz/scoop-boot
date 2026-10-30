#!/usr/bin/env bash
# scoop-boot: sets up the WSL Debian distribution (delivered by scoop-boot.ps1
# --update; do not edit). scoop-boot.ps1 --wsl-setup runs it inside the
# distribution; it can also be run there by hand.
#
#   debian-setup.sh --packages FILE [--dry-run] [--no-claude] [--yes]
#
#   --packages FILE  apt package list, one package per line, "#" starts a comment
#   --dry-run        shows what would be installed; apt-get runs in simulation mode
#                    (resolves every package, installs nothing, needs no root)
#   --no-claude      leaves out Claude Code
#   --yes            no question before the installation (for CI)
#
# Steps:
#   1. Debian check (ID=debian, or a Debian derivative such as Ubuntu: ID_LIKE=debian)
#   2. apt packages: only the missing ones from the list, --no-install-recommends
#   3. fd and bat under their usual names (Debian ships them as fdfind and batcat)
#   4. Claude Code with the official installer (https://claude.ai/install.sh),
#      skipped when the claude command exists already
#
# Only adds, on a fresh or an existing distribution: no apt-get upgrade, no
# autoremove, and apt-get runs with --no-remove (it stops instead of removing a
# package). The dry run fails when apt would remove anything. An existing file in
# ~/.local/bin is never replaced. Running it again installs only what is missing.
#
# Exit code 0 when every step passed (or would pass in a dry run), 1 otherwise.

set -euo pipefail

PACKAGES_FILE=''
DRY_RUN=0
NO_CLAUDE=0
ASSUME_YES=0
CLAUDE_INSTALLER='https://claude.ai/install.sh'

# ~/.local/bin holds claude, fd and bat; a non-login shell (wsl.exe -- bash ...) lacks it
export PATH="$HOME/.local/bin:$PATH"

info() { echo ">>> $*"; }
ok()   { echo "[OK] $*"; }
dry()  { echo "  [DRY] $*"; }
fail() { echo "[ERROR] $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --packages)   PACKAGES_FILE="${2:-}"; shift ;;
        --packages=*) PACKAGES_FILE="${1#--packages=}" ;;
        --dry-run)    DRY_RUN=1 ;;
        --no-claude)  NO_CLAUDE=1 ;;
        --yes)        ASSUME_YES=1 ;;
        -h|--help)    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *)            fail "unknown option '$1' (--help lists the options)" ;;
    esac
    shift
done

[ -n "$PACKAGES_FILE" ] || fail "--packages FILE is required"
[ -r "$PACKAGES_FILE" ] || fail "package list $PACKAGES_FILE not readable"

# Root runs apt-get directly (CI container), everyone else through sudo
if [ "$(id -u)" -eq 0 ]; then SUDO=''; else SUDO='sudo'; fi

# 1. Debian check
info "Distribution"
os_id=$(. /etc/os-release && echo "${ID:-unknown}")
os_like=$(. /etc/os-release && echo "${ID_LIKE:-}")
os_name=$(. /etc/os-release && echo "${PRETTY_NAME:-unknown}")
if [ "$os_id" = "debian" ]; then
    ok "$os_name"
elif [[ " $os_like " == *" debian "* ]]; then
    ok "$os_name (Debian derivative; the package names of the list may differ)"
else
    fail "this script is for Debian and its derivatives, found $os_name"
fi

# 2. apt packages: comments and blank lines removed, duplicates dropped, order kept
info "apt packages from $PACKAGES_FILE"
mapfile -t wanted < <(sed -e 's/#.*//' -e 's/[[:space:]]//g' "$PACKAGES_FILE" | awk 'NF && !seen[$0]++')
[ "${#wanted[@]}" -gt 0 ] || fail "package list $PACKAGES_FILE is empty"
missing=()
for p in "${wanted[@]}"; do
    if dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed'; then
        :
    else
        missing+=("$p")
    fi
done
ok "${#wanted[@]} in the list, $(( ${#wanted[@]} - ${#missing[@]} )) installed, ${#missing[@]} missing"

if [ "${#missing[@]}" -gt 0 ]; then
    echo "    missing: ${missing[*]}"
    if [ "$DRY_RUN" -eq 1 ]; then
        # Simulation: resolves the packages against the local package index; a name
        # that does not exist fails here, without root and without installing.
        # "Inst" lines are installs (list and dependencies), "Remv" lines removals.
        if ! simulation=$(apt-get -s --no-install-recommends install "${missing[@]}" 2>&1); then
            echo "$simulation" | grep -E '^E:' >&2 || true
            fail "apt-get simulation failed: a package name is wrong or the index is old (sudo apt-get update)"
        fi
        installs=$(grep -c '^Inst ' <<< "$simulation" || true)
        removals=$(grep -c '^Remv ' <<< "$simulation" || true)
        if [ "$removals" -gt 0 ]; then
            grep '^Remv ' <<< "$simulation" >&2
            fail "apt would remove $removals installed package(s); nothing is changed, check the list"
        fi
        dry "apt-get install --no-install-recommends --no-remove ${missing[*]}"
        dry "simulation: $installs package(s) installed (list and dependencies), 0 removed"
    else
        if [ "$ASSUME_YES" -eq 0 ] && [ -t 0 ]; then
            read -r -p "Install ${#missing[@]} packages with apt-get? [y/N] " answer
            [ "$answer" = "y" ] || [ "$answer" = "Y" ] || fail "cancelled"
        fi
        $SUDO apt-get update -qq
        DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq --no-install-recommends --no-remove "${missing[@]}"
        ok "installed: ${missing[*]}"
    fi
fi

# 3. fd and bat under their usual names, as links in ~/.local/bin
info "Command names"
for pair in fdfind:fd batcat:bat; do
    debian_name=${pair%%:*}; usual_name=${pair##*:}
    if command -v "$usual_name" > /dev/null 2>&1 || [ -e "$HOME/.local/bin/$usual_name" ]; then
        ok "$usual_name exists"
    elif [ "$DRY_RUN" -eq 1 ]; then
        dry "ln -s $debian_name ~/.local/bin/$usual_name"
    elif command -v "$debian_name" > /dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        ln -s "$(command -v "$debian_name")" "$HOME/.local/bin/$usual_name"
        ok "$usual_name -> $debian_name"
    fi
done

# 4. Claude Code
info "Claude Code"
if [ "$NO_CLAUDE" -eq 1 ]; then
    ok "skipped (--no-claude)"
elif command -v claude > /dev/null 2>&1; then
    ok "claude exists: $(claude --version 2>/dev/null || echo 'version unknown')"
elif [ "$DRY_RUN" -eq 1 ]; then
    dry "curl -fsSL $CLAUDE_INSTALLER | bash"
else
    curl -fsSL "$CLAUDE_INSTALLER" | bash
    ok "Claude Code installed (open a new shell, then: claude --version)"
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run: nothing installed"
else
    echo "Setup complete"
fi
