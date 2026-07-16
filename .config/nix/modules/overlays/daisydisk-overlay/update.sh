#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
FEED_URL="https://daisydiskapp.com/downloads/appcastFeed.php"
DOWNLOAD_URL="https://daisydiskapp.com/download/DaisyDisk.zip"

echo "Checking DaisyDisk latest version from Sparkle feed..."

version=$(python3 -c "
import xml.etree.ElementTree as ET, urllib.request
NS = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
tree = ET.parse(urllib.request.urlopen('$FEED_URL'))
enc = tree.find('.//item/enclosure')
print(enc.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}version'])
")

if [ -z "$version" ]; then
  echo "ERROR: Could not parse version from Sparkle feed at $FEED_URL" >&2
  exit 1
fi

echo "Latest version: $version"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

echo "Downloading $DOWNLOAD_URL ..."
curl -fsSL -o "$tmp" "$DOWNLOAD_URL"
hash=$(nix hash file --type sha256 "$tmp")

echo "SRI hash: $hash"

sed -i.bak "s/version = \".*\";/version = \"$version\";/" "$DIR/default.nix"
sed -i.bak "s|hash = \"sha256-[A-Za-z0-9+/=]*\";|hash = \"$hash\";|" "$DIR/default.nix"
rm -f "$DIR/default.nix.bak"

echo "Updated daisydisk overlay to version $version"
