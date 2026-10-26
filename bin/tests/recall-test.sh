#!/usr/bin/env bash
# Known-item retrieval benchmark — the real archive and the curated docs.
#
# Each case is a query plus a fragment of the session or file that should
# answer it. The question is deliberately "can it find what I know is there",
# not "is the ranking pretty": every case here has exactly one right answer, and
# a miss means recall cannot be trusted by the phase-5 dedupe, which uses it to
# check a candidate principle against what docs/learnings already says.
#
# Runs against the real corpus, so it belongs next to the machine's data rather
# than in the fixture suites.
#
#   bash ~/bin/tests/recall-test.sh
set -uo pipefail

MEM="$HOME/bin/mem"
TOP=3
pass=0
fail=0
details=()

check() {
    local query="$1" want="$2" found snapshot
    # The JSON goes through a file: python3 reading its program from stdin
    # cannot also read the pipe, which is exactly how this test first failed.
    snapshot="$(mktemp)"
    "$MEM" recall "$query" --days 3650 --limit 20 --json >"$snapshot" 2>/dev/null
    found=$(python3 -c 'import json, sys
want, path = sys.argv[1], sys.argv[2]
try:
    hits = json.load(open(path))
except Exception:
    print("none"); raise SystemExit
for rank, hit in enumerate(hits, 1):
    if want in hit.get("session", ""):
        print(rank); break
else:
    print("none")' "$want" "$snapshot")
    rm -f "$snapshot"
    if [ "$found" = "none" ]; then
        printf '  MISS  %-42s %s\n' "$query" "$want"
        fail=$((fail + 1))
        details+=("$query -> $want")
    elif [ "$found" -le "$TOP" ]; then
        printf '  HIT   %-42s %s (rank %s)\n' "$query" "$want" "$found"
        pass=$((pass + 1))
    else
        printf '  WEAK  %-42s %s (rank %s)\n' "$query" "$want" "$found"
        fail=$((fail + 1))
        details+=("$query -> $want (rank $found)")
    fi
}

echo "== known-item retrieval (top $TOP) =="
check "pipe masks exit code"              "pipe-masks-exit-code"
check "Secretive TouchID push refused"    "secretive-touchid"
check "Osaurus snapshot too large"        "osaurus-shell-run-needs"
check "protocol relative URL host"        "url-relative-path-becomes-host"
check "opencode plugin reload registry"   "plugin-reload-breaks"
check "opencode remembers variant"        "remembers-variant-per-model"
check "showuntrackedfiles hides untracked" "showuntrackedfiles-hides"
check "url resolution is a library bug"   "url-relative-path-becomes-host"

echo
if [ ${#details[@]} -gt 0 ]; then
    printf 'missed:\n'
    for d in ${details[@]+"${details[@]}"}; do printf '  - %s\n' "$d"; done
fi
printf 'summarized: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
