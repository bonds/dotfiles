#!/usr/bin/env bash
# Update the rev-pinned `pi` flake input to the latest GitHub release.
#
# pi is a from-source npm build with no binary cache, so flake.nix pins it to a
# rev rather than a branch: chasing main would build a random commit on every
# `nr --update` and risk a broken tree. This follows *releases* instead — it
# resolves the latest release tag to its commit and rewrites the ?rev= in
# flake.nix; `nr --update` then runs `nix flake update`, which re-locks it.
#
# Usage: update.sh [flake.nix]   (defaults to ~/.config/nix/flake.nix)
set -euo pipefail

FLAKE="${1:-$HOME/.config/nix/flake.nix}"
REPO="earendil-works/pi"

tag=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | jq -r '.tag_name // empty')
if [ -z "$tag" ]; then
    echo "pi: could not resolve the latest release" >&2
    exit 1
fi

# Dereference annotated tags; fall back to the tag ref itself (lightweight tags).
rev=$(git ls-remote "https://github.com/$REPO" "refs/tags/$tag^{}" | cut -f1)
[ -n "$rev" ] || rev=$(git ls-remote "https://github.com/$REPO" "refs/tags/$tag" | cut -f1)
if [ -z "$rev" ]; then
    echo "pi: could not resolve $tag to a commit" >&2
    exit 1
fi

if rg -q "earendil-works/pi\?rev=$rev" "$FLAKE"; then
    echo "pi: already at $tag ($rev)"
    exit 0
fi

tmp="$(mktemp)"
sed -E "s|(earendil-works/pi\?rev=)[0-9a-f]+|\1$rev|" "$FLAKE" > "$tmp"
mv "$tmp" "$FLAKE"
echo "pi: $tag -> $rev"
