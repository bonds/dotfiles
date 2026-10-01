#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
OVERLAY="$DIR/default.nix"

echo "Checking Orca latest version from GitHub releases..."
# Orca tags look like "v1.4.218"; the overlay version is without the 'v'.
release_json=$(curl -fsSL https://api.github.com/repos/stablyai/orca/releases/latest)
version=$(echo "$release_json" | jq -r '.tag_name | sub("^v"; "")')

if [ -z "$version" ] || [ "$version" = "null" ]; then
  echo "ERROR: Could not parse latest version" >&2
  exit 1
fi
echo "Latest version: $version"

# Map asset name -> published sha256 hex digest.
# GitHub publishes a per-asset digest as part of every release; we cross-check
# our download against it so a transient/mid-publish snapshot can never corrupt
# the pin with bytes that don't match the official release.
declare -A PUBLISHED
while read -r name hex; do
  PUBLISHED["$name"]="$hex"
done < <(echo "$release_json" \
  | jq -r '.assets[] | select(.digest != null) | "\(.name) \(.digest | sub("^sha256:"; ""))"')

ASSET="orca-macos-arm64.dmg"
DOWNLOAD_URL="https://github.com/stablyai/orca/releases/download/v${version}/${ASSET}"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

echo "Downloading $DOWNLOAD_URL ..."
curl -fsSL -o "$tmp" "$DOWNLOAD_URL"

# Refuse to continue if the download's bytes don't match GitHub's published
# digest. Under `set -e`, returning 1 aborts before any hash is written.
expected="${PUBLISHED[$ASSET]:-}"
if [ -n "$expected" ]; then
  hex=$(shasum -a 256 -b "$tmp" | awk '{print $1}')
  if [ "$hex" != "$expected" ]; then
    echo "ERROR: $ASSET downloaded bytes do not match GitHub's published digest" >&2
    echo "  got (downloaded):   sha256:$hex" >&2
    echo "  published (GitHub): sha256:$expected" >&2
    exit 1
  fi
  echo "OK: $ASSET verified (sha256:$hex matches GitHub)" >&2
else
  echo "WARNING: no published digest for $ASSET; skipping verification" >&2
fi

hash=$(nix hash file --type sha256 "$tmp")
echo "SRI hash: $hash"

# Update the version and hash literals. Patterns are anchored to line start.
awk -v ver="$version" -v h="$hash" '
/^[[:space:]]*version = "[0-9][^"]*";/ { sub(/version = "[^"]*";/, "version = \"" ver "\";") }
/^[[:space:]]*hash = "sha256-[^"]*";/  { sub(/hash = "sha256-[^"]*";/, "hash = \"" h "\";") }
{ print }
' "$OVERLAY" > "$OVERLAY.tmp" && mv "$OVERLAY.tmp" "$OVERLAY"

echo "Updated orca-ade overlay to version $version"
