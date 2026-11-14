#!/usr/bin/env bash
# Bump pkgs/swival to the latest PyPI release.
#
# swival is not a flake input, so `nr --update` cannot bump it with
# `nix flake update`; this script regenerates the vendored wheel set in
# sources.nix instead (see generate.py for why the closure is vendored).
#
# Both platforms are resolved here, from upstream's uv.lock at the release
# tag, so the file this writes is correct for accismus and sophrosyne
# regardless of which one ran it.
#
# NOTE: unlike modules/overlays/*, `nr-pins diagnose` will NOT auto-revert a
# bad bump of this package: the regenerated sources.nix changes wheel URLs and
# filenames, not just version/hash lines, so the "diff is pin-only" guard
# refuses. A release that fails to build stops `nr` with the error; recover by
# `git checkout HEAD -- .config/nix/pkgs/swival` and bumping by hand later.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
PKG=swival

latest=$(curl -fsSL "https://pypi.org/pypi/$PKG/json" | jq -r '.info.version // empty')
if [ -z "$latest" ]; then
    echo "swival: could not resolve the latest PyPI release" >&2
    exit 1
fi

current=$(sed -n 's/^  version = "\(.*\)";/\1/p' "$DIR/sources.nix")
if [ "$latest" = "$current" ]; then
    echo "swival: already at $latest"
    exit 0
fi

# The wheel hashes come from the uv.lock the maintainers released with.
lock=$(mktemp)
trap 'rm -f "$lock"' EXIT
found=""
for ref in "$latest" "v$latest"; do
    if curl -fsSL "https://raw.githubusercontent.com/Swival/swival/$ref/uv.lock" -o "$lock"; then
        found=$ref
        break
    fi
done
if [ -z "$found" ]; then
    echo "swival: no uv.lock at tag $latest in Swival/swival" >&2
    exit 1
fi

# generate.py needs pip and tomllib, and must not depend on the host python.
system=$(nix eval --raw --impure --expr 'builtins.currentSystem')
expr="let p = (builtins.getFlake \"nixpkgs\").legacyPackages.${system}; in [ (p.python313.withPackages (ps: [ ps.pip ])) ]"
nix shell --impure --expr "$expr" -c python3 \
    "$DIR/generate.py" --version "$latest" --lock "$lock" --out "$DIR/sources.nix"

# sources.nix is a tracked .nix file, so `nix flake check`'s format-check sees it.
if command -v alejandra > /dev/null 2>&1; then
    alejandra --quiet "$DIR/sources.nix"
fi
