#!/usr/bin/env bash
# Smoke-test the freshly built swival (called by `nr-pins verify` after a
# successful build, before `nr` switches to it).
#
# A vendored wheel set can build cleanly and still be unusable: a wheel missing
# from the platform list, or a closure that resolves but cannot import (litellm
# drags in google-cloud-aiplatform, grpc, tiktoken, ...). Neither shows up at
# build time — only when the CLI actually starts.
#
# usage: verify.sh <system-path> <pname> <package-out-path>
set -euo pipefail

sys="$1"
pname="$2"
out="$3"
# The version is the last component of the store path's name: <hash>-<pname>-<version>.
want="${out##*-}"

[ -x "$out/bin/swival" ] || {
    echo "verify: $out/bin/swival is missing or not executable" >&2
    exit 1
}

got=$("$out/bin/swival" --version 2>&1 | tail -1)
case "$got" in
    *"$want"*) ;;
    *)
        echo "verify: swival reports '$got', the derivation says '$want'" >&2
        exit 1
        ;;
esac

# --version only proves the entry point imports. --help builds the whole
# argparse surface, which pulls in the provider modules.
if ! "$out/bin/swival" --help > /dev/null 2>&1; then
    echo "verify: 'swival --help' failed — a provider module is missing from the wheel set" >&2
    "$out/bin/swival" --help 2>&1 | tail -5 >&2
    exit 1
fi

# The binary wheels are the fragile part: they are built against a generic
# glibc/macOS SDK, so on NixOS a missing rpath entry surfaces only on import.
# bin/swival is a makeWrapper shell script, so lift its interpreter out of the
# exec line rather than guessing a store path.
py=$(grep -oE '/nix/store/[a-z0-9]+-python3-[0-9.]+/bin/python3' "$out/bin/swival" | head -1)
[ -n "$py" ] || {
    echo "verify: could not find the interpreter in $out/bin/swival" >&2
    exit 1
}
if ! PYTHONPATH="$out/lib/swival" "$py" -c \
    'import litellm, tiktoken, numpy, mcp, html_to_markdown, fast_cipher, rank_bm25, starlette' \
    2> /dev/null; then
    echo "verify: the vendored wheels do not import cleanly" >&2
    PYTHONPATH="$out/lib/swival" "$py" -c \
        'import litellm, tiktoken, numpy, mcp, html_to_markdown, fast_cipher, rank_bm25, starlette' \
        2>&1 | tail -3 >&2
    exit 1
fi
