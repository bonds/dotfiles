#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)

sha=$(curl -fsSL "https://api.github.com/repos/laurent22/rsync-time-backup/commits/master" | jq -r '.sha')
url="https://raw.githubusercontent.com/laurent22/rsync-time-backup/$sha/rsync_tmbackup.sh"
date=$(curl -fsSL "https://api.github.com/repos/laurent22/rsync-time-backup/commits/$sha" | jq -r '.commit.committer.date | .[0:10]')

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fL -o "$tmp" "$url"
hash=$(nix hash file --type sha256 "$tmp")

version="0-unstable-$date"

sed -i.bak "s|version = \".*\";|version = \"$version\";|" "$DIR/default.nix"
sed -i.bak "s|hash = \".*\";|hash = \"$hash\";|" "$DIR/default.nix"
sed -i.bak "s|url = \".*/rsync_tmbackup.sh\";|url = \"$url\";|" "$DIR/default.nix"
rm -f "$DIR/default.nix.bak"

echo "Updated rsync-tmbackup to $sha ($date)"
