#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)

owner="cool-japan"
repo="oxillama"

# Get latest release tag from GitHub
api="https://api.github.com/repos/$owner/$repo/releases/latest"
tag=$(curl -fsSL "$api" | jq -r '.tag_name' 2>/dev/null)
if [[ -z "$tag" || "$tag" = "null" ]]; then
  # Fallback: list tags via git ls-remote
  tag=$(git ls-remote --tags "https://github.com/$owner/$repo.git" \
    | grep -oP 'refs/tags/\Kv?[\d.]+' \
    | sort -V \
    | tail -1)
fi

version="${tag#v}"
echo "Latest: $version"

# Check current version in default.nix
current=$(sed -n "s/^  version = \"\(.*\)\";/\1/p" "$DIR/default.nix")
if [[ "$version" == "$current" ]]; then
  echo "Already at $version, nothing to do."
  exit 0
fi

# Download source archive and compute hash
archive_url="https://github.com/$owner/$repo/archive/refs/tags/$tag.tar.gz"
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fsSL -o "$tmp" "$archive_url"
hash=$(nix hash file --type sha256 "$tmp")

# Extract and generate Cargo.lock
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir" "$tmp"' EXIT
tar xzf "$tmp" -C "$tmpdir"
pushd "$tmpdir/$repo-$version" > /dev/null
cargo generate-lockfile 2>&1
popd > /dev/null
cp "$tmpdir/$repo-$version/Cargo.lock" "$DIR/Cargo.lock"

# Update version and hash in default.nix
sed -i.bak "s/version = \".*\";/version = \"$version\";/" "$DIR/default.nix"
sed -i.bak "s|hash = \".*\";|hash = \"$hash\";|" "$DIR/default.nix"
rm -f "$DIR/default.nix.bak"

echo "Updated oxillama to $version (hash: $hash)"
