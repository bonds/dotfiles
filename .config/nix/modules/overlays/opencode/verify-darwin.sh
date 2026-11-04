#!/usr/bin/env bash
# Smoke-test the freshly built opencode packages (called by `nr-pins verify`).
#
# V2 is a 214 MB single-file Bun binary published only on npm, and it reads
# ~/.config/opencode/opencode.jsonc at startup. Both halves can break without
# breaking the build: the wrong payload hashed into the pin, or a config schema
# the new release no longer accepts.
#
# usage: verify-darwin.sh <system-path> <pname> <package-out-path>
set -euo pipefail
. "$(dirname "$0")/../lib-verify.sh"

sys="$1"
pname="$2"
out="$3"
# The version is the last component of the store path's name: <hash>-<pname>-<version>.
want="${out##*-}"

# Does the binary's --version banner name the version the derivation claims?
# Identical to update.sh's; the banner is coloured (and can carry CR), so the
# raw line cannot be compared byte-for-byte — that reported a mismatch on text
# that prints the same. Normalise, require the banner to name opencode, then
# compare the version number.
payload_version_matches() { # <raw banner> <expected version> → 0/1
    local raw=$1 want=$2 banner esc ver
    esc=$(printf '\033')
    banner=$(printf '%s' "$raw" | sed -e "s/${esc}\[[0-9;]*[A-Za-z]//g" -e 's/\r//g')
    case "$banner" in
        *opencode*) ;;
        *) return 1 ;;
    esac
    ver=$(printf '%s' "$banner" | grep -Eo '[0-9]+[.][0-9]+[.][0-9]+' | head -1 || true)
    [ "$ver" = "$want" ]
}

case "$pname" in
    opencode)
        bin="$out/bin/opencode"
        [ -x "$bin" ] || {
            echo "verify: $bin is missing or not executable" >&2
            exit 1
        }
        # The binary must agree with the version the pin names. update.sh writes
        # both from the same tarball, so a mismatch means the wrong payload was
        # hashed. Needs no background service.
        got="$("$bin" --version 2> /dev/null | tail -1 || true)"
        payload_version_matches "$got" "$want" || {
            echo "verify: $bin does not report opencode v$want — its banner is $(printf '%q' "$got")" >&2
            exit 1
        }
        # Config compatibility, isolated from live state: a throwaway HOME with a
        # copy of the real config, and --standalone AFTER the subcommand (putting
        # it before fails; see docs/learnings/2026-10-22-opencode-v2-managed-service.md).
        tmp="$(mktemp -d)"
        trap 'rm -rf "$tmp"' EXIT
        mkdir -p "$tmp/.config/opencode"
        cp "$HOME/.config/opencode/opencode.jsonc" "$tmp/.config/opencode/" 2> /dev/null || true
        if ! HOME="$tmp" "$bin" models --standalone > "$tmp/models.out" 2> "$tmp/models.err"; then
            # A network failure is not this release's fault, and reverting a good
            # bump because the machine is offline would be worse than not
            # checking. Anything else — a rejected config — is a real failure.
            if grep -qiE 'enotfound|econnrefused|getaddrinfo|offline|network|timed? ?out' "$tmp/models.err"; then
                echo "verify: WARNING — could not list models (looks like a network failure); config parse unproven" >&2
                exit 0
            fi
            echo "verify: $bin rejected the config:" >&2
            sed -n '1,5p' "$tmp/models.err" >&2
            exit 1
        fi
        [ -s "$tmp/models.out" ] || {
            echo "verify: $bin listed no models at all" >&2
            exit 1
        }
        # Every model it lists must not come from the built-in provider alone:
        # the config declares `sophrosyne`, and losing it is exactly what a
        # schema break looks like (the binary starts, silently ignoring `provider`).
        grep -qv '^opencode/' "$tmp/models.out" || {
            echo "verify: only built-in models were listed — the config's provider block was ignored" >&2
            exit 1
        }
        ;;
    opencode-desktop)
        app="$out/Applications/OpenCode.app"
        verify_app "$app" "$want"
        # The overlay strips this to kill the built-in Electron auto-updater
        # (`nr --update` is the only update path). A re-appearing file means the
        # strip silently stopped matching upstream's layout.
        verify_no_updater "$app"
        ;;
    *)
        echo "verify: unexpected package name '$pname'" >&2
        exit 1
        ;;
esac
