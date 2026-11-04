#!/usr/bin/env bash
# Bump modules/overlays/opencode/default.nix to the newest release on the
# OpenCode **V2** line.
#
# Why the V2 line is special (see default.nix for the full story):
#   - the GitHub "latest release" is ambiguous — the newest V1 and the newest
#     V2 are both live — so `releases/latest` must never pick a V2 version;
#   - the CLI is published on npm (payload @opencode/cli-darwin-arm64), so it
#     comes from the npm tarball, and its `bin/opencode --version` must agree
#     with the tag we pin;
#   - the desktop app has no npm package — it comes from the release zip, which
#     V2 only started publishing at v2.2.5. Both pins move together, but a tag
#     without a desktop asset leaves that pin alone instead of faking it.
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

# Rewrite `  <name> = "…";` in the overlay. Used for both halves (CLI + desktop).
set_var() { # name value
  awk -v n="$1" -v v="$2" '
    $0 ~ "^  " n " = \"" { sub(/= ".*";$/, "= \"" v "\";") }
    { print }
  ' "$OVERLAY" > "$OVERLAY.tmp" && mv "$OVERLAY.tmp" "$OVERLAY"
}

# Does the payload's --version banner name the tag we pinned?
#
# The banner is not plain text: V2.2 colourises it, and can pad it or end it with
# CR, so comparing the raw line byte-for-byte fails on output that looks
# identical — the check used to die with "payload reports 'opencode v2.2.5',
# expected 'opencode v2.2.5'", the difference being an escape sequence nobody
# can see. Normalise first (drop ANSI + CR), insist the banner names opencode,
# then compare the version NUMBER. A wrong payload — a different version, a
# different tool, no version at all — still fails; callers print the raw bytes
# with %q so the next failure is visible.
#
# Same function in verify-darwin.sh (the `. "$(dirname "$0")"` helper there is
# for the smoke tests, not this); keep the two in step.
payload_version_matches() { # <raw banner> <expected version> → 0/1
  local raw=$1 want=$2 banner esc ver
  # ESC goes through a variable, not $'…': double backslash handling in $'…' is
  # easy to get wrong and silently matches nothing.
  esc=$(printf '\033')
  banner=$(printf '%s' "$raw" | sed -e "s/${esc}\[[0-9;]*[A-Za-z]//g" -e 's/\r//g')
  case "$banner" in
    *opencode*) ;;
    *) return 1 ;;
  esac
  # `[.]` rather than `\.`: same meaning in ERE, and no backslash to mis-escape.
  ver=$(printf '%s' "$banner" | grep -Eo '[0-9]+[.][0-9]+[.][0-9]+' | head -1 || true)
  [ "$ver" = "$want" ]
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
# List to a file rather than piping into `grep -q`: under `set -o pipefail` grep
# exits at the first match, the producer dies of SIGPIPE, and the pipeline
# reports failure — so the check below would fire on a perfectly good tarball
# (it did, on the 300 MB desktop zip, whose listing never fits in a pipe buffer).
tar -tzf "$tgz" > "$tmpdir/cli-files.txt"
grep -qx 'package/bin/opencode' "$tmpdir/cli-files.txt" \
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
payload_version_matches "$reported" "$version" \
  || die "payload does not report opencode v$version — its banner is $(printf '%q' "$reported")"
echo "OK: payload reports $reported"

# --- 4. Desktop -------------------------------------------------------------
# The desktop app has no npm package, so it can only come from the release zip —
# which the V2 line only started shipping at v2.2.5. Bump it from the same tag,
# but only when the asset is actually there: a tag without a desktop build must
# leave the previous pin intact (an older desktop still runs next to a newer
# CLI) instead of writing a URL that 404s. Cross-check the download against the
# release's own SHA256SUMS, and confirm the bundle layout the install phase
# depends on (OpenCode.app + the app-update.yml it strips) before pinning.
desktop_asset=opencode-desktop-mac-arm64.zip
desktop_url="https://github.com/$REPO/releases/download/v$version/$desktop_asset"
assets=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/v$version" 2>/dev/null \
  | jq -r '.assets[]?.name' 2>/dev/null || true)

if printf '%s\n' "$assets" | grep -qx "$desktop_asset"; then
  dzip="$tmpdir/$desktop_asset"
  echo "Downloading $desktop_url ..."
  curl -fsSL -o "$dzip" "$desktop_url"

  # GitHub release assets carry no integrity metadata of their own, but upstream
  # publishes a SHA256SUMS file next to them — same idea as the npm dist.integrity
  # check above, so a truncated CDN response cannot stamp a wrong hash.
  sums=$(curl -fsSL "https://github.com/$REPO/releases/download/v$version/SHA256SUMS" 2>/dev/null || true)
  want_sha=$(printf '%s\n' "$sums" | awk -v f="$desktop_asset" '$2 == f { print $1 }')
  got_sha=$(shasum -a 256 "$dzip" | awk '{ print $1 }')
  if [ -z "$want_sha" ]; then
    echo "WARN: no SHA256SUMS entry for $desktop_asset at v$version — relying on the SRI pin and the build-time verify"
  elif [ "$want_sha" != "$got_sha" ]; then
    die "downloaded desktop zip does not match the release's SHA256SUMS
  got:  $got_sha
  want: $want_sha"
  fi
  [ -z "$want_sha" ] || echo "OK: desktop zip matches the release SHA256SUMS ($got_sha)"

  unzip -Z1 "$dzip" > "$tmpdir/desktop-files.txt"
  grep -qx 'OpenCode.app/Contents/Resources/app-update.yml' "$tmpdir/desktop-files.txt" \
    || die "$desktop_asset has no OpenCode.app/Contents/Resources/app-update.yml — the install phase's strip/re-sign recipe no longer matches upstream's layout"

  # The bundle must be the version the tag names: a stale CDN copy or the wrong
  # platform builds fine and only fails much later, in verify-darwin.sh.
  mkdir -p "$tmpdir/d"
  unzip -qo "$dzip" -d "$tmpdir/d" 'OpenCode.app/Contents/Info.plist'
  bundle_ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$tmpdir/d/OpenCode.app/Contents/Info.plist" 2>/dev/null || true)
  [ "$bundle_ver" = "$version" ] \
    || die "$desktop_asset reports CFBundleShortVersionString '$bundle_ver', expected '$version'"

  desktop_hash=$(nix hash file --type sha256 "$dzip")
  echo "Desktop SRI hash: $desktop_hash"

  set_var desktopVersion "$version"
  set_var desktopHash "$desktop_hash"

  grep -q "^  desktopVersion = \"$version\";" "$OVERLAY" \
    || die "failed to rewrite desktopVersion in $OVERLAY"
  grep -qF "desktopHash = \"$desktop_hash\";" "$OVERLAY" \
    || die "failed to rewrite desktopHash in $OVERLAY"
  echo "Updated opencode-desktop pin to V2 $version"
else
  # Not a failure: a packaging-only tag can ship the CLI without a desktop build.
  # Say so loudly — a desktop that silently stops tracking the CLI is the exact
  # drift this overlay was written to end.
  pinned=$(awk -F'"' '/^  desktopVersion = /{ print $2 }' "$OVERLAY")
  echo "WARN: no $desktop_asset at v$version — leaving opencode-desktop pinned at $pinned."
fi

# --- 5. Rewrite the CLI pin -------------------------------------------------
cli_hash=$(nix hash file --type sha256 "$tgz")
echo "CLI SRI hash: $cli_hash"

set_var cliVersion "$version"
set_var cliHash "$cli_hash"

grep -q "^  cliVersion = \"$version\";" "$OVERLAY" \
  || die "failed to rewrite cliVersion in $OVERLAY"
grep -qF "cliHash = \"$cli_hash\";" "$OVERLAY" \
  || die "failed to rewrite cliHash in $OVERLAY"

echo "Updated opencode CLI pin to V2 $version"
