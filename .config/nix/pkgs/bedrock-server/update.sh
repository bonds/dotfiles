#!/usr/bin/env bash
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
JSON_URL="https://raw.githubusercontent.com/kittizz/bedrock-server-downloads/main/bedrock-server-downloads.json"

json=$(curl -fsSL "$JSON_URL")

version=$(echo "$json" | jq -r '
  .release | keys | map(split(".") | map(tonumber)) | sort_by(.) | last | map(tostring) | join(".")
')

url=$(echo "$json" | jq -r --arg v "$version" '.release[$v].linux.url')

full_version=$(echo "$url" | sed -n 's/.*bedrock-server-\(.*\)\.zip/\1/p')
echo "Latest BDS: $full_version (tracked as $version)"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
curl -fL -A "itzg/minecraft-bedrock-server" -o "$tmp" "$url"
hash=$(nix hash file --type sha256 "$tmp")

sed -i.bak "s/version = \".*\";/version = \"$full_version\";/" "$DIR/default.nix"
sed -i.bak "s|hash = \".*\";|hash = \"$hash\";|" "$DIR/default.nix"
rm -f "$DIR/default.nix.bak"

echo "Updated to $full_version"
