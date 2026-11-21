#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)

owner="cool-japan"
repo="oxillama"

# Get latest release tag from GitHub
api="https://api.github.com/repos/$owner/$repo/releases/latest"
# Tolerate a failed lookup. With `set -o pipefail`, a 404 here killed the script
# before the fallback below could run — so a repo with no "latest release", or one
# that has moved, produced a bare `curl: (56) 404` in the middle of `nr --update`
# and never bumped. cool-japan/oxillama has 404'd outright since 2026-11-21.
tag=$(curl -fsSL "$api" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null || true)
if [[ -z "$tag" || "$tag" = "null" ]]; then
  # Fallback: list tags via git ls-remote. sed, not `grep -oP` — BSD grep has no -P.
  tag=$(git ls-remote --tags "https://github.com/$owner/$repo.git" 2>/dev/null \
    | sed -n 's|.*refs/tags/||p' \
    | sed 's/\^{}$//' \
    | grep -E '^v?[0-9]+(\.[0-9]+)*$' \
    | sort -V \
    | tail -1 || true)
fi

if [[ -z "$tag" ]]; then
  echo "oxillama: no release or version tag at $owner/$repo — upstream gone or renamed; skipping" >&2
  exit 0
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
