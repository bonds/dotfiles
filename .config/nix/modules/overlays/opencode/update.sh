#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
OVERLAY="$DIR/default.nix"

echo "Checking opencode latest version from GitHub releases..."
version=$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest | jq -r '.tag_name | sub("^v"; "")')

if [ -z "$version" ]; then
  echo "ERROR: Could not parse latest version" >&2
  exit 1
fi

echo "Latest version: $version"

tmp_cli=$(mktemp)
tmp_desktop=$(mktemp)
trap 'rm -f "$tmp_cli" "$tmp_desktop"' EXIT

CLI_URL="https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-darwin-arm64.zip"
echo "Downloading CLI from $CLI_URL ..."
curl -fsSL -o "$tmp_cli" "$CLI_URL"
cli_hash=$(nix hash file --type sha256 "$tmp_cli")
echo "CLI SRI hash: $cli_hash"

DESKTOP_URL="https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-desktop-mac-arm64.zip"
echo "Downloading desktop from $DESKTOP_URL ..."
curl -fsSL -o "$tmp_desktop" "$DESKTOP_URL"
desktop_hash=$(nix hash file --type sha256 "$tmp_desktop")
echo "Desktop SRI hash: $desktop_hash"

# Update version, both hashes, and URLs using awk
awk -v ver="$version" -v cli_hash="$cli_hash" -v desktop_hash="$desktop_hash" '
/version = ".*";/ { sub(/version = ".*";/, "version = \"" ver "\";") }
/hash = "sha256-[^"]*";/ {
  count++
  if (count == 1) sub(/hash = "[^"]*";/, "hash = \"" cli_hash "\";")
  else if (count == 2) sub(/hash = "[^"]*";/, "hash = \"" desktop_hash "\";")
}
{ print }
' "$OVERLAY" > "$OVERLAY.tmp" && mv "$OVERLAY.tmp" "$OVERLAY"

echo "Updated opencode overlay to version $version"
