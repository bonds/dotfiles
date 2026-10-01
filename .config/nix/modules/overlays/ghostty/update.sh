#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
OVERLAY="$DIR/default.nix"

# Ghostty publishes to its own file host (not GitHub releases). The version
# comes from the Sparkle appcast, like daisydisk-overlay. There is no upstream
# sha256 manifest to cross-check against (its appcast enclosure carries only an
# Ed25519 signature, which is not directly verifiable with minisign's key
# format), so — exactly like DaisyDisk — this script downloads and hashes.
APPCAST_URL="https://release.files.ghostty.org/appcast.xml"

echo "Checking Ghostty latest version from Sparkle appcast..."
appcast=$(mktemp)
tmp=$(mktemp)
trap 'rm -f "$appcast" "$tmp"' EXIT
# NOTE: curl, not python-urllib — the host returns 403 to urllib's User-Agent.
curl -fsSL "$APPCAST_URL" -o "$appcast"

# The appcast lists releases oldest -> newest, so the last shortVersionString is
# the newest.
version=$(python3 -c "
import xml.etree.ElementTree as ET
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
tree = ET.parse('$appcast')
found = [i for i in tree.findall('.//item') if i.find('enclosure') is not None]
node = found[-1].find('sparkle:shortVersionString', {'sparkle': NS})
print(node.text if node is not None else '')
")

if [ -z "$version" ]; then
  echo "ERROR: Could not parse version from appcast at $APPCAST_URL" >&2
  exit 1
fi
echo "Latest version: $version"

DOWNLOAD_URL="https://release.files.ghostty.org/${version}/Ghostty.dmg"

echo "Downloading $DOWNLOAD_URL ..."
curl -fsSL -o "$tmp" "$DOWNLOAD_URL"
hash=$(nix hash file --type sha256 "$tmp")

echo "SRI hash: $hash"

# Update the version and hash literals. Patterns are anchored to line start.
awk -v ver="$version" -v h="$hash" '
/^[[:space:]]*version = "[0-9][^"]*";/ { sub(/version = "[^"]*";/, "version = \"" ver "\";") }
/^[[:space:]]*hash = "sha256-[^"]*";/  { sub(/hash = "sha256-[^"]*";/, "hash = \"" h "\";") }
{ print }
' "$OVERLAY" > "$OVERLAY.tmp" && mv "$OVERLAY.tmp" "$OVERLAY"

echo "Updated ghostty overlay to version $version"
