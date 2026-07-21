#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
OVERLAY="$DIR/default.nix"

echo "Checking osaurus latest version from GitHub releases..."
version=$(curl -fsSL https://api.github.com/repos/osaurus-ai/osaurus/releases/latest | jq -r '.tag_name')

if [ -z "$version" ]; then
  echo "ERROR: Could not parse latest version" >&2
  exit 1
fi

echo "Latest version: $version"

DOWNLOAD_URL="https://github.com/osaurus-ai/osaurus/releases/download/${version}/Osaurus-${version}.dmg"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

echo "Downloading $DOWNLOAD_URL ..."
curl -fsSL -o "$tmp" "$DOWNLOAD_URL"
hash=$(nix hash file --type sha256 "$tmp")

echo "SRI hash: $hash"

sed -i.bak "s/version = \".*\";/version = \"$version\";/" "$OVERLAY"
sed -i.bak "s|hash = \"sha256-[A-Za-z0-9+/=]*\";|hash = \"$hash\";|" "$OVERLAY"
sed -i.bak "s|/download/[^/]*/Osaurus-[^/]*\.dmg|/download/$version/Osaurus-$version.dmg|" "$OVERLAY"
rm -f "$OVERLAY.bak"

echo "Updated osaurus overlay to version $version"
