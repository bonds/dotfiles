#!/usr/bin/env bash
# mem doctor tests — the checks that already found drift by hand.
#
# Everything runs against a fixture tree via MEM_DOCTOR_* overrides, so the test
# exercises the logic rather than today's state of the real repo. The last case
# does run against the real tree, because "the machine is currently healthy" is
# worth asserting too.
#
#   bash ~/bin/tests/doctor-test.sh
set -uo pipefail

MEM="$HOME/bin/mem"
T=/tmp/doctor-tests
pass=0
fail=0

ok() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

setup() {
    rm -rf "$T"
    mkdir -p "$T/skills/alpha" "$T/wired"
    printf 'rule one\nrule two\n' > "$T/AGENTS.md"
    printf 'exists\n' > "$T/existing.md"
    cat > "$T/skills/alpha/SKILL.md" <<EOF
---
name: alpha
description: "does one thing, and says when"
---

# Alpha

Reads \`$T/existing.md\` before acting.
EOF
    ln -sfn "$T/skills/alpha" "$T/wired/alpha"
}

run() {
    MEM_DOCTOR_AGENTS="$T/AGENTS.md" MEM_DOCTOR_SKILLS="$T/skills" \
        MEM_DOCTOR_WIRED="$T/wired" "$MEM" doctor "$@" 2>&1
}

setup

echo "== healthy fixture =="
out="$(run)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "exits 0 when everything is in step"; else bad "exit $rc on a healthy tree"; fi
case "$out" in
    *"always-loaded total"*) ok "reports the budget" ;;
    *) bad "no budget line" ;;
esac
case "$out" in
    *"in step"*) ok "reports the wired skill directory as in step" ;;
    *) bad "no inventory verdict" ;;
esac

echo "== budget =="
out="$(run --budget 1)"; rc=$?
if [ "$rc" -eq 1 ]; then ok "fails when over budget"; else bad "did not fail over budget (rc $rc)"; fi

echo "== inventory drift =="
mkdir -p "$T/wired/beta"
out="$(run)"; rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q 'beta is not in the shared store'; then
    ok "flags a skill that is not in the shared store"
else
    bad "missed the stray skill"
fi
rm -rf "$T/wired/beta"

mv "$T/wired/alpha" /tmp/doctor-alpha-link
out="$(run)"
if printf '%s' "$out" | grep -q 'alpha missing'; then ok "flags a skill missing from a wired path"; else bad "missed the missing skill"; fi
mv /tmp/doctor-alpha-link "$T/wired/alpha"

echo "== descriptions and references =="
sed -i '' '/^description:/d' "$T/skills/alpha/SKILL.md"
out="$(run)"
if printf '%s' "$out" | grep -q 'no description'; then ok "flags a skill with no description"; else bad "missed the missing description"; fi
setup

# home-relative, because that is the only kind the check inspects: a skill
# pointing at /usr/... is checking the OS, not its own truth
printf '\nSee `~/doctor-test-vanished.md` for details.\n' >> "$T/skills/alpha/SKILL.md"
out="$(run)"; rc=$?
if printf '%s' "$out" | grep -q 'references missing'; then ok "flags a dangling path"; else bad "missed the dangling path"; fi
if [ "$rc" -eq 0 ]; then ok "a dangling path warns without failing"; else bad "dangling path failed the run"; fi

setup  # start clean: the previous case left a non-negated reference behind
printf '\nMoved here from `~/doctor-test-vanished.md`, which is gone.\n' >> "$T/skills/alpha/SKILL.md"
out="$(run)"
if printf '%s' "$out" | grep -q 'references missing'; then bad "flagged a path documented as gone"; else ok "ignores a path documented as gone"; fi

echo "== json =="
out="$(run --json)"
if printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if "budget" in d and "findings" in d else 1)'; then
    ok "--json emits budget and findings"
else
    bad "--json output unparseable or incomplete"
fi

echo "== the real tree =="
out="$("$MEM" doctor 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "the live repo passes doctor"; else bad "live repo fails doctor:"; printf '%s\n' "$out" | tail -3; fi
if printf '%s' "$out" | grep -q '^freshness'; then ok "live doctor reports freshness"; else bad "no freshness section"; fi
if printf '%s' "$out" | grep -qE 'last ingest [0-9]{4}-'; then ok "reports a last-ingest timestamp per harness"; else bad "no ingest timestamps"; fi

echo
printf 'summarized: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
