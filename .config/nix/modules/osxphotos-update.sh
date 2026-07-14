#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
OVERLAY="$DIR/osxphotos-overlay.nix"

echo "Checking osxphotos latest version from GitHub releases..."
version=$(curl -fsSL https://api.github.com/repos/RhetTbull/osxphotos/releases/latest | jq -r '.tag_name | sub("^v"; "")')

if [ -z "$version" ]; then
  echo "ERROR: Could not parse latest version" >&2
  exit 1
fi

echo "Latest version: $version"

DOWNLOAD_URL="https://github.com/RhetTbull/osxphotos/releases/download/v${version}/osxphotos_MacOS_exe_darwin_arm64_v${version}.zip"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

echo "Downloading $DOWNLOAD_URL ..."
curl -fsSL -o "$tmp" "$DOWNLOAD_URL"
hash=$(nix hash file --type sha256 "$tmp")

echo "SRI hash: $hash"

sed -i.bak "s/version = \".*\";/version = \"$version\";/" "$OVERLAY"
sed -i.bak "s|hash = \"sha256-[A-Za-z0-9+/=]*\";|hash = \"$hash\";|" "$OVERLAY"
rm -f "$OVERLAY.bak"

echo "Updated osxphotos overlay to version $version"
