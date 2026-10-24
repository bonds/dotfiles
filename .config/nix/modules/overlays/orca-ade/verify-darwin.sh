#!/usr/bin/env bash
# Smoke-test the freshly built orca-ade package (called by `nr-pins verify`).
# usage: verify-darwin.sh <system-path> <pname> <package-out-path>
set -euo pipefail
. "$(dirname "$0")/../lib-verify.sh"

[ "$2" = "orca-ade" ] || {
    echo "verify: unexpected package name '$2'" >&2
    exit 1
}
# The version is the last component of the store path's name:
# <hash>-<pname>-<version>. A bundle whose Info.plist disagrees is the wrong asset.
verify_app "$3/Applications/Orca.app" "${3##*-}"
