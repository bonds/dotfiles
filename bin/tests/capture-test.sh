#!/usr/bin/env bash
# capture test suite — the failure-signature pickers behind the shared inbox.
#
# Runs cases against pi's learnings-capture and corrections-capture extensions
# and the opencode memory-capture plugin. Every case uses a throwaway
# MEMORY_DIR under the system temp dir, so the real inbox is never touched.
#
#   bash ~/bin/tests/capture-test.sh
#
# The cases themselves are in capture-test.mjs; bun runs the TS extensions and
# the opencode plugin as they are, with a fake harness around each one.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

if ! command -v bun > /dev/null 2>&1; then
    printf 'SKIP  capture-test: bun is not on PATH\n'
    exit 0
fi

exec bun "$HERE/capture-test.mjs"
