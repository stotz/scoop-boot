#!/usr/bin/env bash
# Kept for the documented call tools/release.sh vNNNN: the script lives in bin/ and is
# delivered to C:\usr\bin by --update (see bin/release.sh for the configuration).
exec "$(dirname "$0")/../bin/release.sh" "$@"
