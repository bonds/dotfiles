#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
OVERLAY="$DIR/default.nix"

echo "Checking OpenFang latest version from GitHub releases..."
release_json=$(curl -fsSL https://api.github.com/repos/RightNow-AI/openfang/releases/latest)
version=$(echo "$release_json" | jq -r '.tag_name | sub("^v"; "")')

if [ -z "$version" ] || [ "$version" = "null" ]; then
  echo "ERROR: Could not parse latest version" >&2
  exit 1
fi
echo "Latest version: $version"

# Look up GitHub's published sha256 digest for one asset (empty when absent).
# GitHub publishes a per-asset digest as part of every release; we cross-check
# our download against it so a bad or mid-publish snapshot can never corrupt the
# pin with bytes that don't match the official release. A jq lookup keeps this
# free of associative arrays, so it runs on macOS's bash 3.2.
published_digest() {
  echo "$release_json" \
    | jq -r --arg name "$1" \
        '.assets[] | select(.name == $name and .digest != null) | .digest | sub("^sha256:"; "")'
}

ASSET="OpenFang_aarch64.app.tar.gz"
URL="https://github.com/RightNow-AI/openfang/releases/download/v${version}/${ASSET}"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

echo "Downloading $URL ..."
curl -fsSL -o "$tmp" "$URL"

expected=$(published_digest "$ASSET")
if [ -n "$expected" ]; then
  hex=$(shasum -a 256 -b "$tmp" | awk '{print $1}')
  if [ "$hex" != "$expected" ]; then
    echo "ERROR: $ASSET downloaded bytes do not match GitHub's published digest" >&2
    echo "  got (downloaded):   sha256:$hex" >&2
    echo "  published (GitHub): sha256:$expected" >&2
    exit 1
  fi
  echo "OK: $ASSET verified against GitHub's published digest" >&2
else
  echo "WARNING: no published digest for $ASSET; skipped verification" >&2
fi

hash=$(nix hash file --type sha256 "$tmp")
echo "SRI hash: $hash"

# Update the version literal and the fetchurl hash. Scoped rules:
#   - version line: the only `version = "<digits…>";`
#   - hash line:    the only `hash = "sha256-…";`
awk -v ver="$version" -v h="$hash" '
/^[[:space:]]*version = "[0-9.]+";/ { sub(/version = "[0-9.]+";/, "version = \"" ver "\";") }
/hash = "sha256-[^"]*";/        { sub(/hash = "sha256-[^"]*";/, "hash = \"" h "\";") }
{ print }
' "$OVERLAY" > "$OVERLAY.tmp" && mv "$OVERLAY.tmp" "$OVERLAY"

echo "Updated openfang overlay to version $version"