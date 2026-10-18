#!/usr/bin/env bash
# Move the rev-pinned `pi` flake input to the latest GitHub release.
#
# pi is declared in the nr-pins managed block, so its URL lives in the pin
# registry (flake-pins.json) as a `base` entry carrying `?rev=<sha>`. This
# script only updates that base URL; `nr --update` then runs `nr-pins check`
# (which re-renders the block into flake.nix) and `nix flake update`.
#
# If the new release fails to build, `nr-pins diagnose` reverts pi to the
# last-good rev and `check` keeps that pin until a newer release appears — so a
# bad release costs one failed build, not one per `nr --update`.
#
# Usage: update.sh [flake-pins.json]   (defaults to ~/.config/nix/flake-pins.json)
set -euo pipefail

REGISTRY="${1:-$HOME/.config/nix/flake-pins.json}"
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

if ! jq -e 'any(.base[]?; .input == "pi")' "$REGISTRY" > /dev/null 2>&1; then
    echo "pi: $REGISTRY has no base entry for pi — add one (see the nr-pins header)" >&2
    exit 1
fi

url="git+https://github.com/$REPO?rev=$rev"
if jq -e --arg u "$url" 'any(.base[]?; .input == "pi" and .url == $u)' "$REGISTRY" > /dev/null 2>&1; then
    echo "pi: already at $tag ($rev)"
    exit 0
fi

tmp="$(mktemp)"
if jq --arg u "$url" \
    '.base = ((.base // []) | map(if .input == "pi" then .url = $u else . end))' \
    "$REGISTRY" > "$tmp" && mv "$tmp" "$REGISTRY"; then
    echo "pi: $tag -> $rev"
else
    rm -f "$tmp"
    echo "pi: could not update $REGISTRY" >&2
    exit 1
fi
