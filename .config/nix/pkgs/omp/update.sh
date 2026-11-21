#!/usr/bin/env bash
# Bump pkgs/omp to the latest OMP release.
#
# OMP is a prebuilt-binary package, not a flake input, so `nr --update` cannot
# bump it with `nix flake update` — it runs this script instead (see the
# overlay-pin section of nr-pins). The script only rewrites the version and the
# two hash lines in default.nix, so the resulting diff is pin-only and
# `nr-pins diagnose` can revert a release that fails to build or breaks the
# smoke test.
#
# Hashes come from the release's SHA256SUMS.txt, so no 220 MB asset is
# downloaded here; nix fetches (and verifies against these) at build time.
#
# Usage: update.sh
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
REPO="can1357/oh-my-pi"

tag=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | jq -r '.tag_name // empty')
if [ -z "$tag" ]; then
    echo "omp: could not resolve the latest release" >&2
    exit 1
fi
version=${tag#v}

sums=$(curl -fsSL "https://github.com/$REPO/releases/download/$tag/SHA256SUMS.txt")
if [ -z "$sums" ]; then
    echo "omp: could not fetch SHA256SUMS.txt for $tag" >&2
    exit 1
fi

# SRI, because that is what the derivation pins. `nix hash to-sri` is gone in
# some newer nix builds (Lix here still has it), so fall back to `convert`.
to_sri() {
    if nix hash to-sri --type sha256 "$1" 2> /dev/null; then
        return
    fi
    nix hash convert --hash-algo sha256 --to sri "$1"
}

hash_for() { # hash_for <asset-name> → SRI, or empty when the asset is missing
    local hex
    hex=$(printf '%s\n' "$sums" | awk -v a="$1" '$2 == a {print $1}')
    [ -n "$hex" ] || return 0
    to_sri "$hex"
}

darwin=$(hash_for omp-darwin-arm64)
linux=$(hash_for omp-linux-x64)
if [ -z "$darwin" ] || [ -z "$linux" ]; then
    echo "omp: $tag is missing omp-darwin-arm64 or omp-linux-x64" >&2
    exit 1
fi

current=$(sed -n 's/^  version = "\(.*\)";/\1/p' "$DIR/default.nix")
if [ "$version" = "$current" ] \
    && [ "$darwin" = "$(sed -n 's/^  hash = "\(.*\)";/\1/p' "$DIR/default.nix")" ] \
    && [ "$linux" = "$(sed -n 's/^  linuxHash = "\(.*\)";/\1/p' "$DIR/default.nix")" ]; then
    echo "omp: already at $version"
    exit 0
fi

sed -i.bak \
    -e "s/^  version = \".*\";/  version = \"$version\";/" \
    -e "s/^  hash = \".*\";/  hash = \"$darwin\";/" \
    -e "s/^  linuxHash = \".*\";/  linuxHash = \"$linux\";/" \
    "$DIR/default.nix"
rm -f "$DIR/default.nix.bak"

echo "omp: $version (darwin-arm64 $darwin)"
