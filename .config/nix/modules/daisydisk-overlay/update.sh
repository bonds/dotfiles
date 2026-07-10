#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
FEED_URL="https://daisydiskapp.com/downloads/appcastFeed.php"
DOWNLOAD_URL="https://daisydiskapp.com/download/DaisyDisk.zip"

echo "Checking DaisyDisk latest version from Sparkle feed..."

# Parse version from Sparkle appcast feed
version=$(curl -fsSL "$FEED_URL" | xmlstarlet sel -t -v 'rss/channel/item[1]/enclosure/@sparkle:version' -n 2>/dev/null)

if [ -z "$version" ]; then
  echo "ERROR: Could not parse version from Sparkle feed at $FEED_URL" >&2
  exit 1
fi

echo "Latest version: $version"

# Download the zip and compute SRI hash
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

echo "Downloading $DOWNLOAD_URL ..."
curl -fsSL -o "$tmp" "$DOWNLOAD_URL"
hash=$(nix hash file --type sha256 "$tmp")

echo "SRI hash: $hash"

# Rewrite version and hash in default.nix
sed -i.bak "s/version = \".*\";/version = \"$version\";/" "$DIR/default.nix"
sed -i.bak "s|hash = \"sha256-[A-Za-z0-9+/=]*\";|hash = \"$hash\";|" "$DIR/default.nix"
rm -f "$DIR/default.nix.bak"

echo "Updated daisydisk overlay to version $version"
