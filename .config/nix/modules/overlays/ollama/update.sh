#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
OVERLAY="$DIR/default.nix"

echo "Checking ollama latest version from GitHub releases..."
version=$(curl -fsSL https://api.github.com/repos/ollama/ollama/releases/latest | jq -r '.tag_name | sub("^v"; "")')

if [ -z "$version" ]; then
  echo "ERROR: Could not parse latest version" >&2
  exit 1
fi

echo "Latest version: $version"

DOWNLOAD_URL="https://github.com/ollama/ollama/releases/download/v${version}/ollama-darwin.tgz"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

echo "Downloading $DOWNLOAD_URL ..."
curl -fsSL -o "$tmp" "$DOWNLOAD_URL"
hash=$(nix hash file --type sha256 "$tmp")

echo "SRI hash: $hash"

sed -i.bak "s/version = \".*\";/version = \"$version\";/" "$OVERLAY"
sed -i.bak "s|hash = \"sha256-[A-Za-z0-9+/=]*\";|hash = \"$hash\";|" "$OVERLAY"
sed -i.bak "s|/download/v[^/]*/ollama-darwin.tgz|/download/v$version/ollama-darwin.tgz|" "$OVERLAY"
rm -f "$OVERLAY.bak"

echo "Updated ollama overlay to version $version"
