#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
OVERLAY="$DIR/default.nix"

echo "Checking opencode latest version from GitHub releases..."
release_json=$(curl -fsSL https://api.github.com/repos/anomalyco/opencode/releases/latest)
version=$(echo "$release_json" | jq -r '.tag_name | sub("^v"; "")')

if [ -z "$version" ] || [ "$version" = "null" ]; then
  echo "ERROR: Could not parse latest version" >&2
  exit 1
fi
echo "Latest version: $version"

# Map asset name -> published sha256 hex digest.
# GitHub publishes a per-asset digest as part of every release; we cross-check
# our download against it so a transient/mid-publish snapshot (or a CDN mirror
# that's briefly stale) can never corrupt the pin with bytes that don't match
# the official release. Without this, `nr --update` could stamp a wrong hash
# and break the next rebuild — exactly the 1.18.14 failure.
declare -A PUBLISHED
while read -r name hex; do
  PUBLISHED["$name"]="$hex"
done < <(echo "$release_json" \
  | jq -r '.assets[] | select(.digest != null) | "\(.name) \(.digest | sub("^sha256:"; ""))"')

tmp_cli=$(mktemp)
tmp_desktop=$(mktemp)
trap 'rm -f "$tmp_cli" "$tmp_desktop"' EXIT

CLI_NAME="opencode-darwin-arm64.zip"
DESKTOP_NAME="opencode-desktop-mac-arm64.zip"
CLI_URL="https://github.com/anomalyco/opencode/releases/download/v${version}/${CLI_NAME}"
DESKTOP_URL="https://github.com/anomalyco/opencode/releases/download/v${version}/${DESKTOP_NAME}"

echo "Downloading CLI from $CLI_URL ..."
curl -fsSL -o "$tmp_cli" "$CLI_URL"
echo "Downloading desktop from $DESKTOP_URL ..."
curl -fsSL -o "$tmp_desktop" "$DESKTOP_URL"

# Refuse to continue if a download's bytes don't match GitHub's published
# digest. Under `set -e`, returning 1 aborts the script before any hash is
# written to the overlay.
verify() {
  local name="$1" file="$2" expected="${PUBLISHED[$1]:-}"
  local hex
  hex=$(shasum -a 256 -b "$file" | awk '{print $1}')
  if [ -z "$expected" ]; then
    echo "WARNING: no published digest for $name; skipping verification" >&2
    return 0
  fi
  if [ "$hex" != "$expected" ]; then
    echo "ERROR: $name downloaded bytes do not match GitHub's published digest" >&2
    echo "  got (downloaded):   sha256:$hex" >&2
    echo "  published (GitHub): sha256:$expected" >&2
    return 1
  fi
  echo "OK: $name verified (sha256:$hex matches GitHub)" >&2
  return 0
}

verify "$CLI_NAME" "$tmp_cli"
verify "$DESKTOP_NAME" "$tmp_desktop"

cli_hash=$(nix hash file --type sha256 "$tmp_cli")
desktop_hash=$(nix hash file --type sha256 "$tmp_desktop")
echo "CLI SRI hash: $cli_hash"
echo "Desktop SRI hash: $desktop_hash"

# Update targetVersion, the two `version = targetVersion;` lines, and both
# hash lines. The awk rules are scoped precisely:
#   - targetVersion line:   the only `targetVersion = "…";`
#   - package version lines: `version = targetVersion;` (no literal quote)
#   - hash lines:           only the two `hash = "sha256-…";` in fetchurl
awk -v ver="$version" -v cli_hash="$cli_hash" -v desktop_hash="$desktop_hash" '
/targetVersion = ".*";/ { sub(/targetVersion = ".*";/, "targetVersion = \"" ver "\";") }
/version = "[0-9.]+";/ { sub(/version = "[0-9.]+";/, "version = \"" ver "\";") }
/hash = "sha256-[^"]*";/ {
  count++
  if (count == 1) sub(/hash = "[^"]*";/, "hash = \"" cli_hash "\";")
  else if (count == 2) sub(/hash = "[^"]*";/, "hash = \"" desktop_hash "\";")
}
{ print }
' "$OVERLAY" > "$OVERLAY.tmp" && mv "$OVERLAY.tmp" "$OVERLAY"

echo "Updated opencode overlay to version $version"
