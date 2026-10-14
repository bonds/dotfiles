#!/usr/bin/env bash
# nr-pins test harness — stubs the nix probe so every path runs in milliseconds
# and never touches the real flake. Run: bash .config/nix/nr-pins-tests.sh
#
# Sibling artifacts: nr-pins (the engine under test) and nr-pins-probe-stub (the
# fake probe). Fixtures are written under $T and never into the flake directory.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/nr-pins"
STUB="$HERE/nr-pins-probe-stub"
T=/tmp/nr-pins-tests
pass=0
fail=0

ok() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
check_rc() { # check_rc <expected> <actual> <label>
    if [ "$1" -eq "$2" ]; then ok "$3 (rc $2)"; else bad "$3 (expected rc $1, got $2)"; fi
}

follows_unresolved() { # → every follows target in $T/flake.nix not declared as an input
    # The invariant nr-pins must guarantee: after any run, every
    # `inputs.X.follows = "Y"` in flake.nix resolves — Y is declared somewhere in
    # `inputs`. Evaluate the fixture's inputs attrset (lazily; `outputs` is never
    # forced, so `mkFlake`/the imports are not touched) rather than grepping.
    # Prints nothing when the invariant holds; "UNVERIFIED(...)" when it cannot
    # be checked, so a broken eval never reads as a pass.
    local declared targets t
    if ! command -v nix > /dev/null 2>&1; then printf 'UNVERIFIED(no nix) '; return; fi
    declared="$(nix eval --file "$T/flake.nix" --apply 'x: builtins.attrNames x.inputs' --json 2>/dev/null | jq -r '.[]' 2>/dev/null)" \
        || { printf 'UNVERIFIED(attrNames failed) '; return; }
    [ -n "$declared" ] || { printf 'UNVERIFIED(no inputs) '; return; }
    targets="$(nix eval --file "$T/flake.nix" \
        --apply 'x: builtins.concatLists (map (n: builtins.attrValues (x.inputs.${n}.inputs or {})) (builtins.attrNames x.inputs))' \
        --json 2>/dev/null | jq -r '.[]? | .follows? // empty' | sort -u)" \
        || { printf 'UNVERIFIED(follows scan failed) '; return; }
    for t in $targets; do
        printf '%s\n' "$declared" | grep -qxF "$t" || printf '%s ' "$t"
    done
}

setup() {
    mkdir -p "$T"
    cat > "$T/flake.lock" <<'JSON'
{
  "nodes": {
    "root":             { "inputs": { "nixpkgs": "nixpkgs", "nixpkgs-unstable": "nixpkgs-unstable", "nix-darwin": "nix-darwin", "hermes-agent": "hermes-agent" } },
    "nixpkgs":          { "locked": { "owner": "NixOS", "repo": "nixpkgs", "rev": "newstable",  "ref": "nixos-26.05" } },
    "nixpkgs-unstable": { "locked": { "owner": "NixOS", "repo": "nixpkgs", "rev": "newunstable", "ref": "nixpkgs-unstable" } },
    "nix-darwin":       { "locked": { "owner": "nix-darwin", "repo": "nix-darwin", "rev": "abc", "ref": "nix-darwin-26.05" } },
    "hermes-agent":     { "locked": { "type": "git", "rev": "deadbeef" } },
    "nixpkgs_2":        { "locked": { "owner": "NixOS", "repo": "nixpkgs", "rev": "aninternalnode", "ref": "nixpkgs-unstable" } }
  }
}
JSON
    cat > "$T/pins-snapshot.json" <<'JSON'
{
  "nodes": {
    "nixpkgs":          { "locked": { "rev": "oldstable" } },
    "nixpkgs-unstable": { "locked": { "rev": "oldunstable" } }
  }
}
JSON
    cp "$HERE/flake-pins.json" "$T/flake-pins.json"
    cp "$HERE/flake.nix" "$T/flake.nix"
}

run() { # run <stub-list> <stub-input|-> <subcommand...>
    local list="$1" only="$2"
    shift 2
    [ "$only" = "-" ] && only=""
    env NR_PINS_STUB_LIST="$list" NR_PINS_STUB_INPUT="$only" \
        NR_PINS_FLAKE_DIR="$T" NR_PINS_SNAPSHOT="$T/pins-snapshot.json" \
        NR_PINS_ATTR="darwinConfigurations.test.system" \
        NR_PINS_PROBE_STUB="$STUB" bash "$S" "$@"
}

run_fail() { # run_fail <subcommand...> — the probe itself fails (unevaluable)
    env NR_PINS_STUB_FAIL=1 \
        NR_PINS_FLAKE_DIR="$T" NR_PINS_SNAPSHOT="$T/pins-snapshot.json" \
        NR_PINS_ATTR="darwinConfigurations.test.system" \
        NR_PINS_PROBE_STUB="$STUB" bash "$S" "$@"
}

fake_nix() { # write a fake `nix` under $T/fakebin that emulates the fetcher cache
    mkdir -p "$T/fakebin"
    : > "$T/fakebin/argv.log"
    cat > "$T/fakebin/nix" <<'FAKE'
#!/usr/bin/env bash
# Fake `nix build --dry-run` for the fetcher-cache cases below. Real nix reuses
# a tarball-ttl-cached branch→rev row unless --refresh is given (see
# nr-pins-emptying-evidence-2026-10-14.md). So:
#   * --refresh present         → the branch re-resolves to its HEAD, and the
#                                 inputs named in $FAKE_NEEDS are listed as
#                                 needing a source build (the blocker is real).
#   * no --refresh, $FAKE_STALE → the probe reuses the stale row: the branch
#                                 resolves to the pinned rev, where the blocker
#                                 substitutes, so nothing is listed to build.
printf '%s\n' "$*" >> "$FAKE_LOG"
refresh=0; input=""; prev=""
for a in "$@"; do
    [ "$a" = "--refresh" ] && refresh=1
    [ "$prev" = "--override-input" ] && input="$a"
    prev="$a"
done
case " ${FAKE_NEEDS:-} " in *" $input "*) want=1 ;; *) want=0 ;; esac
[ "$refresh" -eq 1 ] || [ -z "${FAKE_STALE:-}" ] || want=0
[ "$want" -eq 0 ] && exit 0
hex="$(printf 'a%.0s' $(seq 1 32))"
printf 'these 1 derivations will be built:\n  /nix/store/%s-%s-1.0.drv\n' "$hex" "$FAKE_PNAME"
FAKE
    chmod +x "$T/fakebin/nix"
}

fake_run() { # fake_run <needs-inputs> <pname> <stale|head> <subcommand...>
    local needs="$1" pname="$2" mode="$3" stale=""
    shift 3
    [ "$mode" = "stale" ] && stale=1
    env PATH="$T/fakebin:$PATH" FAKE_LOG="$T/fakebin/argv.log" \
        FAKE_NEEDS="$needs" FAKE_PNAME="$pname" FAKE_STALE="$stale" \
        NR_PINS_FLAKE_DIR="$T" NR_PINS_SNAPSHOT="$T/pins-snapshot.json" \
        NR_PINS_ATTR="darwinConfigurations.test.system" \
        NR_PINS_PROBE_STUB= bash "$S" "$@"
}

apply_here() { # apply_here — run `apply` against the fixture without the stub
    NR_PINS_FLAKE_DIR="$T" bash "$S" apply
}

printf '\n== snapshot ==\n'
setup
run "" - snapshot > /dev/null
[ -f "$T/pins-snapshot.json" ] && [ "$(jq -r '.nodes.nixpkgs.locked.rev' "$T/pins-snapshot.json")" = "newstable" ] \
    && ok "snapshot copies the live lock revs" || bad "snapshot wrong"

printf '\n== check: blockers still present ==\n'
setup
run "thrift anyio" - check > /dev/null
check_rc 1 $? "check keeps both pins"
[ "$(jq '.pins | length' "$T/flake-pins.json")" -eq 2 ] && ok "registry untouched" || bad "registry changed"

printf '\n== check: nothing needs building any more ==\n'
setup
run "" - check > /dev/null
check_rc 2 $? "check drops both pins"
[ "$(jq '.pins | length' "$T/flake-pins.json")" -eq 0 ] && ok "registry emptied" || bad "registry still has pins"
grep -qF 'BEGIN nr-managed input pins' "$T/flake.nix" && ok "block retained" || bad "block lost"
# The bug this guards: emptying the registry used to delete the input
# DECLARATION itself (render_block emitted nothing for an empty registry),
# leaving every `inputs.X.follows = "nixpkgs"` dangling and breaking
# `nix flake update`. The block must still declare both nixpkgs inputs — now at
# their normal branch URLs rather than a pinned rev.
grep -qF 'nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05"' "$T/flake.nix" \
    && ok "nixpkgs still declared at its branch url" || bad "nixpkgs declaration lost with the pin"
grep -qF 'nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable"' "$T/flake.nix" \
    && ok "nixpkgs-unstable still declared at its branch url" || bad "nixpkgs-unstable declaration lost with the pin"
n=$(grep -cE 'url = "github:NixOS/nixpkgs/[0-9a-f]{40}"' "$T/flake.nix" || true)
[ "$n" -eq 0 ] && ok "no pinned rev url survives an emptied registry" || bad "$n pinned rev url(s) left behind"
u="$(follows_unresolved)"; [ -z "$u" ] && ok "every follows target still resolves" || bad "dangling follows: $u"

printf '\n== check: a STALE fetcher-cache row must not drop the pin ==\n'
# The 2026-10-14 incident. probe() ran `nix build --dry-run` WITHOUT --refresh,
# so nix reused its tarball-ttl-cached branch→rev row (tarball-ttl = 3600). A row
# still resolving the branch to the PINNED rev makes the override a no-op there,
# the blocker substitutes, the dry run lists nothing to build — and `check`
# drops a pin whose blocker has not cleared, emptying the registry. RUN B of
# nr-pins-emptying-evidence-2026-10-14.md reproduces it; RUN C shows the one-word
# --refresh fix restores the correct verdict on the very same cache.
#
# The stub replaces probe() wholesale, so it can never see the flag. These two
# cases drive `check` through the REAL probe() with a fake `nix` on PATH instead.
setup
fake_nix
fake_run "nixpkgs-unstable" anyio stale check > "$T/refresh.out" 2>&1
check_rc 2 $? "check reports the drop of the genuinely-cleared pin"
[ "$(jq -r '.pins | map(.input) | join(",")' "$T/flake-pins.json")" = "nixpkgs-unstable" ] \
    && ok "kept the pin whose blocker is still unbuilt at the branch head" \
    || bad "a stale cache row dropped it: $(jq -c '.pins|map(.input)' "$T/flake-pins.json")"
n=$(grep -c -- '--refresh' "$T/fakebin/argv.log" || true)
[ "$n" -eq 2 ] && ok "both probes asked nix to re-resolve the branch (--refresh)" \
    || bad "$n/2 probe(s) reused the cached branch→rev row (no --refresh)"

printf '\n== check: a branch-head row that substitutes still drops the pin ==\n'
# The other direction: --refresh must not make a genuinely-cleared pin
# undroppable. Nothing needs building at the branch head here, so the pin goes —
# and the flag is still on every probe.
setup
fake_nix
fake_run "" "" head check > "$T/refresh-head.out" 2>&1
check_rc 2 $? "check drops a pin whose blocker has cleared at the head"
[ "$(jq '.pins | length' "$T/flake-pins.json")" -eq 0 ] && ok "registry emptied" \
    || bad "pin kept: $(jq -c '.pins|map(.input)' "$T/flake-pins.json")"
n=$(grep -c -- '--refresh' "$T/fakebin/argv.log" || true)
[ "$n" -eq 2 ] && ok "the refreshed probes still resolved the branch" \
    || bad "$n/2 probe(s) ran without --refresh"
u="$(follows_unresolved)"; [ -z "$u" ] && ok "every follows target still resolves" || bad "dangling follows: $u"

printf '\n== check: only one blocker cleared ==\n'
setup
run "thrift" - check > /dev/null
check_rc 2 $? "check reports a change (rc 2)"
[ "$(jq -r '.pins | map(.input) | join(",")' "$T/flake-pins.json")" = "nixpkgs" ] \
    && ok "kept the still-blocked pin (nixpkgs), dropped the cleared one (nixpkgs-unstable)" \
    || bad "wrong pins left: $(jq -c '.pins|map(.input)' "$T/flake-pins.json")"

printf '\n== name matching: a version-interpreter-prefixed drv still matches ==\n'
setup
run "python3.12-anyio-4.14.2" - check > /dev/null
[ "$(jq -r '.pins | map(.input) | join(",")' "$T/flake-pins.json")" = "nixpkgs-unstable" ] \
    && ok "anyio matched inside python3.12-anyio-4.14.2" \
    || bad "prefix match failed: $(jq -c '.pins|map(.input)' "$T/flake-pins.json")"

printf '\n== diagnose: pins the culprit at its last-good rev ==\n'
setup
cat > "$T/failing.log" <<'LOG'
error: builder for '/nix/store/a4qflb2vpddmdll0m7rp1qsl4g17vpbj-thrift-0.24.0.drv' failed with exit code 2
error: 1 dependencies of derivation '/nix/store/zzz-darwin-system-26.05.drv' failed to build
LOG
run "thrift" - diagnose "$T/failing.log" > /dev/null
check_rc 2 $? "diagnose pins something"
[ "$(jq -r '.pins[] | select(.input=="nixpkgs") | .url' "$T/flake-pins.json")" = "github:NixOS/nixpkgs/oldstable" ] \
    && ok "pinned nixpkgs at the SNAPSHOT rev (newstable was the bad one)" \
    || bad "wrong url: $(jq -r '.pins[] | select(.input=="nixpkgs") | .url' "$T/flake-pins.json")"
grep -qF 'github:NixOS/nixpkgs/oldstable' "$T/flake.nix" && ok "block regenerated with the pin" || bad "block not regenerated"

printf '\n== diagnose: an ANSI-coloured (nh) log still yields the failing derivation ==\n'
setup
# nix-output-monitor — the tool `nr` tees into the log diagnose is handed —
# colours the store path INSIDE the quotes:
#   error: builder for '<ESC>[35;1m/nix/store/<hash>-<name>.drv<ESC>[0m' failed ...
# A literal "builder for '/nix/store/..." grep therefore never matches an nh log
# and the failure reads as "no failing derivation (eval error?)", so the culprit
# is never pinned and `nr --update` can never self-heal.
printf "error: builder for '\033[35;1m/nix/store/a4qflb2vpddmdll0m7rp1qsl4g17vpbj-thrift-0.24.0.drv\033[0m' failed with exit code 2\n" > "$T/failing-ansi.log"
run "thrift" - diagnose "$T/failing-ansi.log" > /dev/null
check_rc 2 $? "diagnose pins from an ANSI-coloured nh log"
[ "$(jq -r '.pins[] | select(.input=="nixpkgs") | .url' "$T/flake-pins.json")" = "github:NixOS/nixpkgs/oldstable" ] \
    && ok "pinned nixpkgs at the snapshot rev" \
    || bad "wrong url: $(jq -r '.pins[] | select(.input=="nixpkgs") | .url' "$T/flake-pins.json")"

printf '\n== diagnose: a rev-locked flake.lock (no .locked.ref) still probes ==\n'
setup
# The REAL flake.lock never carries `.locked.ref`: while a pin is active the
# input is locked by rev (owner/repo/rev only) and the declared ref lives in
# `.original`. Reading the branch URL out of the lock therefore made every
# diagnose probe bail with "no branch ref in flake.lock" and nothing was ever
# pinned — the fixture above masked it by hand-writing a `ref`. The registry's
# `base` list is the canonical source for an input's normal branch URL.
jq '.nodes.nixpkgs.locked |= del(.ref) | .nodes["nixpkgs-unstable"].locked |= del(.ref)' \
    "$T/flake.lock" > "$T/revlock.tmp" && mv "$T/revlock.tmp" "$T/flake.lock"
run "thrift" - diagnose "$T/failing.log" > /dev/null
check_rc 2 $? "diagnose pins without .locked.ref"
[ "$(jq -r '.pins[] | select(.input=="nixpkgs") | .url' "$T/flake-pins.json")" = "github:NixOS/nixpkgs/oldstable" ] \
    && ok "pinned nixpkgs at the snapshot rev" \
    || bad "wrong url: $(jq -r '.pins[] | select(.input=="nixpkgs") | .url' "$T/flake-pins.json")"
[ "$(jq -r '.pins[] | select(.input=="nixpkgs") | .branch' "$T/flake-pins.json")" = "github:NixOS/nixpkgs/nixos-26.05" ] \
    && ok "recorded the branch url from the registry base" \
    || bad "wrong branch: $(jq -r '.pins[] | select(.input=="nixpkgs") | .branch' "$T/flake-pins.json")"

printf '\n== diagnose: eval failure (no failing derivation) ==\n'
setup
printf 'error: undefined variable foo\n' > "$T/eval.log"
run "thrift" - diagnose "$T/eval.log" > /dev/null
check_rc 1 $? "diagnose declines to pin an eval error"
[ "$(jq '.pins | length' "$T/flake-pins.json")" -eq 2 ] && ok "registry unchanged" || bad "registry changed"

printf '\n== diagnose: package no nixpkgs input would need (your own breakage) ==\n'
setup
cat > "$T/own.log" <<'LOG'
error: builder for '/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-photo-export-0.2.5.drv' failed with exit code 1
LOG
run "photo-export" some-other-input diagnose "$T/own.log" > /dev/null
check_rc 1 $? "diagnose refuses to pin a non-nixpkgs failure"
grep -qE '^[[:space:]]*photo-export' "$T/flake.nix" && bad "pinned something bogus" || ok "no bogus pin"

printf '\n== diagnose: culprit input did not move ==\n'
setup
cp "$T/flake.lock" "$T/pins-snapshot.json"
run "thrift" - diagnose "$T/failing.log" 2>/dev/null > /dev/null
check_rc 1 $? "diagnose declines when no input moved"

printf '\n== apply: idempotent ==\n'
setup
apply_here > /dev/null 2>&1
cp "$T/flake.nix" "$T/flake.once.nix"
apply_here > /dev/null 2>&1
diff -q "$T/flake.once.nix" "$T/flake.nix" > /dev/null && ok "second apply is a no-op" || bad "apply is not idempotent"

printf '\n== render: a pinned entry keeps its pinned rev url ==\n'
setup
apply_here > /dev/null 2>&1
grep -qF 'nixpkgs.url = "github:NixOS/nixpkgs/774debe7a0d1b496e35677ad955a1011c6ff74f3"' "$T/flake.nix" \
    && ok "pinned nixpkgs renders its pinned rev" || bad "pinned nixpkgs rev not rendered"
grep -qF 'nixpkgs-unstable.url = "github:NixOS/nixpkgs/c9fe7d12cd78d1adcd12dd15e24432dde5b155a0"' "$T/flake.nix" \
    && ok "pinned nixpkgs-unstable renders its pinned rev" || bad "pinned nixpkgs-unstable rev not rendered"
n=$(grep -cE 'url = "github:NixOS/nixpkgs/(nixos-26\.05|nixpkgs-unstable)"' "$T/flake.nix" || true)
[ "$n" -eq 0 ] && ok "no branch url leaks while a pin is active" || bad "$n branch url(s) rendered despite the pins"
u="$(follows_unresolved)"; [ -z "$u" ] && ok "every follows target resolves" || bad "dangling follows: $u"

printf '\n== compat: a registry with no base list still declares the owned inputs ==\n'
setup
printf '{\n  "pins": []\n}\n' > "$T/flake-pins.json"
apply_here > /dev/null 2>&1
grep -qF 'nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05"' "$T/flake.nix" \
    && ok "nixpkgs declared from the default base" || bad "nixpkgs not declared"
grep -qF 'nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable"' "$T/flake.nix" \
    && ok "nixpkgs-unstable declared from the default base" || bad "nixpkgs-unstable not declared"
u="$(follows_unresolved)"; [ -z "$u" ] && ok "every follows target resolves" || bad "dangling follows: $u"
# ...and the broken on-disk state (empty pins, block with no input declarations)
# is repaired by `check`.
setup
printf '{\n  "pins": []\n}\n' > "$T/flake-pins.json"
grep -vE '^[[:space:]]*(nixpkgs|nixpkgs-unstable)\.url' "$T/flake.nix" > "$T/noin" && mv "$T/noin" "$T/flake.nix"
grep -qE '^[[:space:]]*nixpkgs\.url' "$T/flake.nix" && bad "fixture not actually broken" || ok "fixture mimics the broken on-disk state"
run "thrift anyio" - check > "$T/repair.out" 2>&1
check_rc 2 $? "check repairs the broken block"
u="$(follows_unresolved)"; [ -z "$u" ] && ok "repaired block resolves every follows target" || bad "dangling follows: $u"

printf '\n== check: a probe that CANNOT be evaluated must KEEP the pins ==\n'
setup
run_fail check > /dev/null 2>&1
check_rc 1 $? "check keeps pins when the probe fails"
[ "$(jq '.pins | length' "$T/flake-pins.json")" -eq 2 ] && ok "registry untouched on probe failure" \
    || bad "registry changed on probe failure: $(jq -c '.pins|map(.input)' "$T/flake-pins.json")"
grep -qF 'github:NixOS/nixpkgs/774debe7a0d1b496e35677ad955a1011c6ff74f3' "$T/flake.nix" \
    && ok "pin line still in flake.nix" || bad "a failed probe dropped the pin"

printf '\n== diagnose: a probe that CANNOT be evaluated must NOT pin ==\n'
setup
cat > "$T/failing2.log" <<'LOG'
error: builder for '/nix/store/a4qflb2vpddmdll0m7rp1qsl4g17vpbj-thrift-0.24.0.drv' failed with exit code 2
LOG
run_fail diagnose "$T/failing2.log" > /dev/null 2>&1
check_rc 1 $? "diagnose declines when the probe cannot run"

printf '\n== apply: refuses to truncate a file whose END marker is gone ==\n'
setup
grep -v 'END nr-managed input pins' "$T/flake.nix" > "$T/broken" && mv "$T/broken" "$T/flake.nix"
cp "$T/flake.nix" "$T/before.bak"
apply_here > /dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "apply refused (rc $rc)" || bad "apply reported success on a marker-less file"
diff -q "$T/before.bak" "$T/flake.nix" > /dev/null && ok "flake.nix left untouched" || bad "flake.nix was modified"

printf '\n== apply: refuses a duplicated block ==\n'
setup
sed -n '/BEGIN nr-managed input pins/,/END nr-managed input pins/p' "$T/flake.nix" > "$T/block.txt"
awk -v b="$T/block.txt" '{ print; if ($0 ~ /END nr-managed input pins/ && !d) { while ((getline l < b) > 0) print l; close(b); d=1 } }' \
    "$T/flake.nix" > "$T/dup" && mv "$T/dup" "$T/flake.nix"
cp "$T/flake.nix" "$T/dup.bak"
apply_here > /dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "apply refused a duplicated block (rc $rc)" || bad "apply accepted a duplicated block"
diff -q "$T/dup.bak" "$T/flake.nix" > /dev/null && ok "flake.nix left untouched" || bad "flake.nix was modified"

printf '\n== diagnose: a probe error must not be reported as "not the culprit" ==\n'
setup
cat > "$T/failing3.log" <<'LOG'
error: builder for '/nix/store/a4qflb2vpddmdll0m7rp1qsl4g17vpbj-thrift-0.24.0.drv' failed with exit code 2
LOG
run_fail diagnose "$T/failing3.log" > "$T/diag.out" 2>&1
check_rc 1 $? "diagnose declines"
grep -q 'could not be evaluated' "$T/diag.out" && ok "reports the probe failure honestly" \
    || bad "did not report the probe failure: $(tail -2 "$T/diag.out" | tr '\n' ' ')"
grep -q 'not a nixpkgs input regression' "$T/diag.out" && bad "still claims not-a-regression on a probe error" \
    || ok "does not claim not-a-regression"
[ "$(jq '.pins | length' "$T/flake-pins.json")" -eq 2 ] && ok "registry unchanged" || bad "registry changed"

printf '\n== check: a registry entry with missing pnames must keep the pin ==\n'
setup
jq 'del(.pins[0].pnames)' "$T/flake-pins.json" > "$T/reg.tmp" && mv "$T/reg.tmp" "$T/flake-pins.json"
run "thrift anyio" - check > /dev/null 2>&1
check_rc 1 $? "check keeps the pin it cannot read"
[ "$(jq '.pins | length' "$T/flake-pins.json")" -eq 2 ] && ok "registry intact" || bad "an unreadable entry was dropped"

printf '\n== snapshot: a failed read must not clobber the previous snapshot ==\n'
setup
printf '{"nodes":{"nixpkgs":{"locked":{"rev":"GOODBASELINE"}}}}\n' > "$T/pins-snapshot.json"
rm -f "$T/flake.lock"
run "" - snapshot > /dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "snapshot refused (rc $rc)" || bad "snapshot reported success with no flake.lock"
[ "$(jq -r '.nodes.nixpkgs.locked.rev' "$T/pins-snapshot.json" 2>/dev/null)" = "GOODBASELINE" ] \
    && ok "previous snapshot preserved" || bad "previous snapshot was clobbered"

printf '\n== fail-closed: a corrupt registry must not read as "no pins" ==\n'
setup
WT="${T}.w"; mkdir -p "$WT"
printf '{ not json\n' > "$T/flake-pins.json"
run "thrift anyio" - check > "$WT/corrupt.out" 2>&1
check_rc 1 $? "check refuses a corrupt registry"
grep -q 'pin registry' "$WT/corrupt.out" && ok "names the unreadable registry" || bad "no such message"
printf "error: builder for '/nix/store/a4qflb2vpddmdll0m7rp1qsl4g17vpbj-thrift-0.24.0.drv' failed with exit code 2\n" > "$WT/failing.log"
run_fail diagnose "$WT/failing.log" > "$WT/corrupt2.out" 2>&1
check_rc 1 $? "diagnose refuses a corrupt registry"
grep -q 'pin registry' "$WT/corrupt2.out" && ok "diagnose names it too" || bad "no such message"

printf '\n== fail-closed: diagnose with no snapshot must refuse, not exonerate ==\n'
setup
rm -f "$T/pins-snapshot.json"
run_fail diagnose "$WT/failing.log" > "$WT/nosnap.out" 2>&1
check_rc 1 $? "diagnose refuses without a snapshot"
grep -q 'no readable snapshot' "$WT/nosnap.out" && ok "says the snapshot is unreadable" || bad "no such message"
grep -q 'not a nixpkgs input regression' "$WT/nosnap.out" && bad "exonerated on an unreadable snapshot" || ok "no exonerating verdict"

printf '\n== fail-closed: a registry write failure must not exonerate ==\n'
setup
chmod 555 "$T"
run "thrift" - diagnose "$WT/failing.log" > "$WT/roreg.out" 2>&1
chmod 755 "$T"
grep -q 'could not write the registry' "$WT/roreg.out" && ok "reports the write failure" || bad "write failure not reported: $(tail -2 "$WT/roreg.out" | tr '\n' ' ')"
grep -q 'not a nixpkgs input regression' "$WT/roreg.out" && bad "claimed not-a-regression despite the write failure" || ok "does not claim not-a-regression"

printf '\n== snapshot: a lock with no .nodes is refused ==\n'
setup
printf '{"version":7}\n' > "$T/flake.lock"
printf '{"nodes":{"nixpkgs":{"locked":{"rev":"GOODBASELINE"}}}}\n' > "$T/pins-snapshot.json"
run "" - snapshot > "$WT/nonodes.out" 2>&1
check_rc 1 $? "snapshot refuses a lock with no .nodes"
[ "$(jq -r '.nodes.nixpkgs.locked.rev' "$T/pins-snapshot.json" 2>/dev/null)" = "GOODBASELINE" ] \
    && ok "baseline preserved" || bad "baseline clobbered"
grep -q 'no .nodes' "$WT/nonodes.out" && ok "says why" || bad "no such message"

printf '\n== check: a null member in pnames must keep the pin, not probe a partial list ==\n'
setup
jq '.pins[0].pnames = ["thrift", null]' "$T/flake-pins.json" > "$WT/reg.tmp" && mv "$WT/reg.tmp" "$T/flake-pins.json"
run "thrift anyio" - check > /dev/null 2>&1
[ "$(jq '.pins | length' "$T/flake-pins.json")" -eq 2 ] && ok "kept the pin with a partial/null pnames" || bad "dropped or truncated the entry"

printf '\n== fail-closed: a readable but corrupt snapshot must not exonerate ==\n'
setup
printf '{"nodes": {"nixpkgs": {"locked": {"rev": "oldstable"\n' > "$T/pins-snapshot.json"
run "thrift" - diagnose "$WT/failing.log" > "$WT/badsnap.out" 2>&1
check_rc 1 $? "diagnose refuses a corrupt snapshot"
grep -q 'not a nixpkgs input regression' "$WT/badsnap.out" && bad "exonerated on a corrupt snapshot" || ok "no exonerating verdict"
grep -q 'no usable nodes' "$WT/badsnap.out" && ok "says the snapshot has no usable nodes" || bad "no such message"

printf '\n== fail-closed: a node-less snapshot must not exonerate ==\n'
setup
printf '{}' > "$T/pins-snapshot.json"
run "thrift" - diagnose "$WT/failing.log" > "$WT/emptysnap.out" 2>&1
check_rc 1 $? "diagnose refuses a node-less snapshot"
grep -q 'not a nixpkgs input regression' "$WT/emptysnap.out" && bad "exonerated on an empty snapshot" || ok "no exonerating verdict"

printf '\n== fail-closed: a corrupt flake.lock must not exonerate ==\n'
setup
printf '{ not valid json\n' > "$T/flake.lock"
run "thrift" - diagnose "$WT/failing.log" > "$WT/badlock.out" 2>&1
check_rc 1 $? "diagnose refuses a corrupt lock"
grep -q 'not a nixpkgs input regression' "$WT/badlock.out" && bad "exonerated on a corrupt lock" || ok "no exonerating verdict"
grep -q 'cannot read flake.lock' "$WT/badlock.out" && ok "names the lock" || bad "no such message"

printf '\n== fail-closed: a shape-corrupt registry must not read as "no pins" ==\n'
for bad in '{}' '{"pins": null}' '{"pins": {}}'; do
    setup
    printf '%s\n' "$bad" > "$T/flake-pins.json"
    run "thrift anyio" - check > "$WT/badreg.out" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then bad "check returned 0 for registry $bad"; else ok "check refuses $bad (rc $rc)"; fi
done
grep -q "no 'pins' array" "$WT/badreg.out" && ok "names the missing pins array" || bad "no such message"

printf '\n== fail-closed: an input absent from the snapshot must not exonerate ==\n'
setup
jq 'del(.nodes["nixpkgs"])' "$T/pins-snapshot.json" > "$WT/snap.tmp" && mv "$WT/snap.tmp" "$T/pins-snapshot.json"
run "thrift" - diagnose "$WT/failing.log" > "$WT/partial.out" 2>&1
grep -q 'no rev for it in the snapshot' "$WT/partial.out" && ok "reports the input it cannot judge" || bad "no such message"
grep -q 'not a nixpkgs input regression' "$WT/partial.out" && bad "exonerated with an input absent from the snapshot" || ok "no exonerating verdict"

printf '\n== fail-closed: a shapeless flake.lock must not exonerate ==\n'
for bad in '{"nodes": {}}' \
    '{"nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs"}}}}' \
    '{"nodes":{"root":{"inputs":{"nixpkgs":"nixpkgs"}},"nixpkgs":{"locked":{"repo":"nixpkgs","rev":"x","ref":"nixos-26.05"}}}}'; do
    setup
    printf '%s\n' "$bad" > "$T/flake.lock"
    run "thrift" - diagnose "$WT/failing.log" > "$WT/badlock2.out" 2>&1
    rc=$?
    grep -q 'not a nixpkgs input regression' "$WT/badlock2.out" && bad "exonerated on lock: $bad" || ok "no exonerating verdict (rc $rc)"
done
grep -qE 'no nodes|cannot tell which input regressed' "$WT/badlock2.out" && ok "says it cannot tell" || bad "no such message"

printf '\n== fail-closed: an incomplete registry entry must be refused ==\n'
setup
jq 'del(.pins[0].url)' "$T/flake-pins.json" > "$WT/r.tmp" && mv "$WT/r.tmp" "$T/flake-pins.json"
run "thrift" - check > "$WT/nourl.out" 2>&1
check_rc 1 $? "check refuses a pin with no url"
grep -q 'pin registry' "$WT/nourl.out" && ok "names the field rule" || bad "no such message"

printf '\n== fail-closed: a bad base list must be refused ==\n'
for mut in '.base = []' \
    '.base = "nixpkgs"' \
    '.base = [{"input": "nixpkgs"}]' \
    '.base = [{"input": "nixpkgs", "url": "github:NixOS/nixpkgs/dead beef"}]' \
    '.base = [{"input": "nixpkgs\\n", "url": "github:NixOS/nixpkgs/nixos-26.05"}]' \
    '.base = [{"input": "nixpkgs", "url": ""}]'; do
    setup
    jq "$mut" "$T/flake-pins.json" > "$WT/b.tmp" && mv "$WT/b.tmp" "$T/flake-pins.json"
    run "thrift" - check > "$WT/badb.out" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then bad "accepted a bad base: $mut"; else ok "refused (rc $rc)"; fi
done
grep -q "pin registry" "$WT/badb.out" && ok "names the base rule" || bad "no such message"

printf '\n== fail-closed: a pin outside the base list must be refused ==\n'
setup
jq '.base = [{"input": "nixpkgs", "url": "github:NixOS/nixpkgs/nixos-26.05"}]' "$T/flake-pins.json" > "$WT/o.tmp" && mv "$WT/o.tmp" "$T/flake-pins.json"
run "thrift anyio" - check > "$WT/outside.out" 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "refused a pin its base does not cover (rc $rc)" || bad "accepted an uncovered pin"
grep -q 'base list does not declare it' "$WT/outside.out" && ok "says to add it to base" || bad "no such message: $(tail -1 "$WT/outside.out")"

printf '\n== fail-closed (S1): a base that omits a FOLLOWED input must be refused ==\n'
# The original bug, one level up: base is non-empty and self-consistent but does
# not declare an input flake.nix follows. Nothing in flake.nix declares
# nixpkgs-unstable outside the block, so omitting it here re-creates the
# dangling-follows flake silently — unless the coverage guard refuses it.
setup
jq '.base = [.base[0]] | .pins = []' "$T/flake-pins.json" > "$WT/s1.tmp" && mv "$WT/s1.tmp" "$T/flake-pins.json"
run "thrift anyio" - check > "$WT/s1.out" 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "refused (rc $rc)" || bad "accepted a base that omits a followed input"
grep -q "follows 'nixpkgs-unstable'" "$WT/s1.out" && ok "names the dangling follows target" || bad "no such message: $(tail -1 "$WT/s1.out")"
# ...and the same base WITH the missing entry is accepted.
setup
jq '.pins = []' "$T/flake-pins.json" > "$WT/s1b.tmp" && mv "$WT/s1b.tmp" "$T/flake-pins.json"
run "thrift anyio" - check > "$WT/s1b.out" 2>&1
rc=$?
[ "$rc" -ne 1 ] && ok "a complete base is accepted (rc $rc)" || bad "refused a complete base: $(tail -1 "$WT/s1b.out")"

printf '\n== diagnose (S2): pinning an input base omits must extend base, not brick the registry ==\n'
setup
# Add a third nixpkgs-family root input that `base` does not declare, and make it
# the only one that moved, so diagnose pins exactly it.
jq '.nodes["nixpkgs-stable"] = {locked: {owner: "NixOS", repo: "nixpkgs", rev: "newstable3", ref: "nixos-26.05"}}
    | .nodes.root.inputs["nixpkgs-stable"] = "nixpkgs-stable"' "$T/flake.lock" > "$WT/s2.lock" && mv "$WT/s2.lock" "$T/flake.lock"
jq '.nodes["nixpkgs-stable"] = {locked: {rev: "oldstable3"}}' "$T/pins-snapshot.json" > "$WT/s2.snap" && mv "$WT/s2.snap" "$T/pins-snapshot.json"
run "thrift" - diagnose "$T/failing.log" > "$WT/s2.out" 2>&1
check_rc 2 $? "diagnose pins the uncovered input"
grep -q 'nixpkgs-stable' "$T/flake-pins.json" && ok "the pin was recorded" || bad "no pin recorded"
jq -e '.base | map(.input) | index("nixpkgs-stable") != null' "$T/flake-pins.json" > /dev/null 2>&1 \
    && ok "base was extended to cover it" || bad "base still omits the pinned input"
# The point of the fix: the registry diagnose just wrote must still be usable.
run "thrift" - apply > "$WT/s2b.out" 2>&1
check_rc 0 $? "the registry it wrote is still usable"
grep -q 'base list does not declare it' "$WT/s2b.out" && bad "the registry was bricked" || ok "no coverage refusal"

printf '\n== check: flake.nix is reconciled to an empty registry ==\n'
setup
printf '{\n  "pins": []\n}\n' > "$T/flake-pins.json"
run "thrift anyio" - check > "$WT/reconcile.out" 2>&1
check_rc 2 $? "reports the reconciliation as a change"
n=$(grep -cE 'url = "github:NixOS/nixpkgs/[0-9a-f]{40}"' "$T/flake.nix" || true)
[ "$n" -eq 0 ] && ok "pinned rev lines removed to match the empty registry" || bad "$n pinned rev line(s) left behind"
grep -qF 'nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05"' "$T/flake.nix" \
    && ok "nixpkgs falls back to its branch url" || bad "nixpkgs declaration lost"
grep -qF 'nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable"' "$T/flake.nix" \
    && ok "nixpkgs-unstable falls back to its branch url" || bad "nixpkgs-unstable declaration lost"
u="$(follows_unresolved)"; [ -z "$u" ] && ok "every follows target resolves after reconcile" || bad "dangling follows: $u"

printf '\n== fail-closed: an entry with a broken field must be refused ==\n'
for mut in 'del(.pins[0].since)' \
    'del(.pins[0].reason)' \
    '.pins[0].branch = "nixos 26.05"' \
    '.pins[0].url = "github:NixOS/nixpkgs/deadbeef\nnixpkgs.url = \"evil\";"' \
    '.pins[0].since = "2026-10-09\n    evil.url = \"github:evil/evil/abc\"; #"' \
    '.pins[0].input = "nixpkgs\n"'; do
    setup
    jq "$mut" "$T/flake-pins.json" > "$WT/m.tmp" && mv "$WT/m.tmp" "$T/flake-pins.json"
    run "thrift" - check > "$WT/mut.out" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then bad "check accepted a bad entry: $mut"; else ok "refused (rc $rc)"; fi
done
grep -q 'pin registry' "$WT/mut.out" && ok "names the rule" || bad "no such message"

printf '\n== check forwards an explicit attr, not the subcommand name ==\n'
setup
: > "$WT/attrs.txt"
NR_PINS_STUB_ATTR_OUT="$WT/attrs.txt" run "thrift" - check darwinConfigurations.test.system > /dev/null 2>&1
attrs="$(sort -u "$WT/attrs.txt" | tr '\n' ' ')"
[ "${attrs% }" = "darwinConfigurations.test.system" ] && ok "attr forwarded verbatim" \
    || bad "attr leaked/ignored: got '${attrs% }'"

printf '\n== summarised: %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
