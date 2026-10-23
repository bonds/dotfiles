#!/usr/bin/env bash
# Bump modules/overlays/opencode/default.nix to the newest release on the
# OpenCode **V2** line.
#
# Why the V2 line is special (see default.nix for the full story):
#   - upstream publishes V2 as npm packages, not GitHub release assets;
#   - the GitHub "latest release" is ambiguous — the newest V1 and the newest
#     V2 are both live — so `releases/latest` must never pick a V2 version;
#   - the CLI binary comes from the per-platform payload package
#     @opencode/cli-darwin-arm64, and its `bin/opencode --version` must agree
#     with the tag we pin.
#
# Run by `nr --update` on accismus.
set -euo pipefail

DIR=$(cd "$(dirname "$0")" && pwd)
OVERLAY="$DIR/default.nix"
REPO=anomalyco/opencode
PLATFORM_PKG=@opencode/cli-darwin-arm64
PLATFORM_SLUG=cli-darwin-arm64

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# --- 1. Newest V2 tag -------------------------------------------------------
# Walk the v2.* git tags (not /releases/latest, which can and does still point
# at the V1 line). Sort -V handles 2.0.9 < 2.0.10. The `v2` prefix means a future
# V3 is ignored on purpose: moving lines is a manual decision, not a nightly one.
echo "Checking opencode V2 tags on GitHub..."
# `|| true` keeps `set -e` from exiting on an empty pipeline (curl 4xx, no tag
# matching, or an API rate limit) so the die below can explain what happened.
version=$(curl -fsSL "https://api.github.com/repos/$REPO/git/refs/tags/v2" \
  | jq -r '.[].ref | sub("^refs/tags/v"; "")' \
  | grep -E '^2\.[0-9]+\.[0-9]+$' \
  | sort -V \
  | tail -1 || true)

[ -n "$version" ] || die "found no v2.x.y tags for $REPO"
echo "Latest V2 tag: $version"

# --- 2. npm payload metadata ------------------------------------------------
echo "Resolving $PLATFORM_PKG@$version on npm..."
meta_url="https://registry.npmjs.org/${PLATFORM_PKG/@/%40}/$version"
meta=$(curl -fsSL "$meta_url") || die "npm has no $PLATFORM_PKG@$version (is the V2 CLI published there?)"

tarball=$(echo "$meta" | jq -r '.dist.tarball // empty')
integrity=$(echo "$meta" | jq -r '.dist.integrity // empty')
[ -n "$tarball" ] || die "$PLATFORM_PKG@$version has no dist.tarball"
case "$integrity" in
  sha512-*) ;;
  *) die "$PLATFORM_PKG@$version has no sha512 dist.integrity" ;;
esac

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
tgz="$tmpdir/$PLATFORM_SLUG-$version.tgz"

echo "Downloading $tarball ..."
curl -fsSL -o "$tgz" "$tarball"

# Verify against npm's published integrity so a truncated/stale CDN response
# can never stamp a wrong hash into the overlay.
actual="sha512-$(openssl dgst -sha512 -binary "$tgz" | openssl base64 -A)"
[ "$actual" = "$integrity" ] \
  || die "downloaded tarball does not match npm integrity
  got:       $actual
  published: $integrity"
echo "OK: tarball matches npm integrity ($integrity)"

# --- 3. Payload sanity checks ----------------------------------------------
tar -tzf "$tgz" | grep -qx 'package/bin/opencode' \
  || die "$PLATFORM_SLUG-$version.tgz has no package/bin/opencode"

mkdir -p "$tmpdir/x"
tar -xzf "$tgz" -C "$tmpdir/x" package/bin/opencode
bin="$tmpdir/x/package/bin/opencode"
chmod +x "$bin"

file "$bin" | grep -q 'Mach-O 64-bit executable arm64' \
  || die "payload binary is not a Mach-O arm64 executable: $(file "$bin")"

# Run it with a throwaway HOME: the binary opens $HOME/.local/share/opencode/log
# at startup, and we must not touch Scott's live state from an update script.
reported=$(HOME="$tmpdir/home" "$bin" --version 2>/dev/null | tail -1 || true)
[ "$reported" = "opencode v$version" ] \
  || die "payload reports '$reported', expected 'opencode v$version'"
echo "OK: payload reports $reported"

# --- 4. Desktop -------------------------------------------------------------
# No V2 desktop artifact exists today (no npm package, no GitHub release
# assets for v2 tags). Leave the V1 pin untouched and say so; a stale V1
# desktop still works alongside the V2 CLI.
desktop_asset=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/v$version" 2>/dev/null \
  | jq -r '[.assets[]?.name] | map(select(. == "opencode-desktop-mac-arm64.zip")) | length' 2>/dev/null || true)

if [ "${desktop_asset:-0}" != "0" ]; then
  die "a V2 desktop asset now exists (opencode-desktop-mac-arm64.zip at v$version).
Update the opencode-desktop block by hand: this script only auto-bumps the CLI."
fi
echo "No V2 desktop asset at v$version — leaving opencode-desktop pinned at V1."

# --- 5. Rewrite the pin -----------------------------------------------------
cli_hash=$(nix hash file --type sha256 "$tgz")
echo "CLI SRI hash: $cli_hash"

set_var() { # name value
  awk -v n="$1" -v v="$2" '
    $0 ~ "^  " n " = \"" { sub(/= ".*";$/, "= \"" v "\";") }
    { print }
  ' "$OVERLAY" > "$OVERLAY.tmp" && mv "$OVERLAY.tmp" "$OVERLAY"
}

set_var cliVersion "$version"
set_var cliHash "$cli_hash"

grep -q "^  cliVersion = \"$version\";" "$OVERLAY" \
  || die "failed to rewrite cliVersion in $OVERLAY"
grep -qF "cliHash = \"$cli_hash\";" "$OVERLAY" \
  || die "failed to rewrite cliHash in $OVERLAY"

echo "Updated opencode CLI pin to V2 $version"
