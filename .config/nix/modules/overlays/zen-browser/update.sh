#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
SOURCES="$DIR/sources.json"

echo "Checking zen-browser latest version from GitHub releases..."
# zen-browser tags look like "1.22.3b" (no 'v' prefix)
release_json=$(curl -fsSL https://api.github.com/repos/zen-browser/desktop/releases/latest)
version=$(echo "$release_json" | jq -r '.tag_name')

if [ -z "$version" ] || [ "$version" = "null" ]; then
  echo "ERROR: Could not parse latest version" >&2
  exit 1
fi
echo "Latest version: $version"

# Map asset name -> published sha256 hex digest.
# GitHub publishes a per-asset digest as part of every release; we cross-check
# our download against it so a transient/mid-publish snapshot (or a CDN mirror
# that's briefly stale) can never corrupt the pin with bytes that don't match
# the official release.
declare -A PUBLISHED
while read -r name hex; do
  PUBLISHED["$name"]="$hex"
done < <(echo "$release_json" \
  | jq -r '.assets[] | select(.digest != null) | "\(.name) \(.digest | sub("^sha256:"; ""))"')

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Fetch an asset, verify it against GitHub's published digest, and print its SRI
# hash. Two platforms share this overlay now: the darwin build takes the
# universal .dmg, the Linux build the x86_64 tarball.
fetch_verified() {
  local asset="$1"
  local url="https://github.com/zen-browser/desktop/releases/download/${version}/${asset}"
  local file="$TMPDIR/$asset"

  echo "Downloading $url ..." >&2
  curl -fsSL -o "$file" "$url"

  # Refuse to continue if the download's bytes don't match GitHub's published
  # digest. Under `set -e`, returning 1 aborts before any hash is written.
  local expected="${PUBLISHED[$asset]:-}"
  if [ -n "$expected" ]; then
    local hex
    hex=$(shasum -a 256 -b "$file" | awk '{print $1}')
    if [ "$hex" != "$expected" ]; then
      echo "ERROR: $asset downloaded bytes do not match GitHub's published digest" >&2
      echo "  got (downloaded):   sha256:$hex" >&2
      echo "  published (GitHub): sha256:$expected" >&2
      exit 1
    fi
    echo "OK: $asset verified (sha256:$hex matches GitHub)" >&2
  else
    echo "WARNING: no published digest for $asset; skipping verification" >&2
  fi

  nix hash file --type sha256 "$file"
}

darwin_hash=$(fetch_verified "zen.macos-universal.dmg")
linux_hash=$(fetch_verified "zen.linux-x86_64.tar.xz")

echo "darwin SRI: $darwin_hash"
echo "linux  SRI: $linux_hash"

# Rewrite sources.json with the fresh version, URLs and hashes. The URLs are
# derived from the version so they always track the asset just verified.
jq -n \
  --arg version "$version" \
  --arg dh "$darwin_hash" \
  --arg lh "$linux_hash" \
  '{
    version: $version,
    "aarch64-darwin": {
      url: ("https://github.com/zen-browser/desktop/releases/download/" + $version + "/zen.macos-universal.dmg"),
      hash: $dh
    },
    "x86_64-linux": {
      url: ("https://github.com/zen-browser/desktop/releases/download/" + $version + "/zen.linux-x86_64.tar.xz"),
      hash: $lh
    }
  }' > "$SOURCES.tmp" && mv "$SOURCES.tmp" "$SOURCES"

echo "Updated zen-browser overlay to version $version"
