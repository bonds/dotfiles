#!/usr/bin/env bash
# mem test suite — the shared memory CLI (bin/mem).
#
# Every case runs against a throwaway MEM_DIR and fixture session stores, so it
# never touches the real inbox, ~/DECISIONS.md or any harness' database.
#
#   bash ~/bin/tests/mem-test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
MEM="$HERE/mem"
T=/tmp/mem-tests
pass=0
fail=0

ok() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
check_rc() { # check_rc <expected> <actual> <label>
    if [ "$1" -eq "$2" ]; then ok "$3 (rc $2)"; else bad "$3 (expected rc $1, got $2)"; fi
}

setup() {
    rm -rf "$T"
    mkdir -p "$T/mem" "$T/repo/docs/learnings" "$T/pi"
    printf '# Learnings\n\nDomain lessons.\n\n## Entries\n\n' > "$T/repo/docs/learnings/README.md"
    (
        cd "$T/repo" || exit 1
        git init -q .
        git -c user.email=t@example.invalid -c user.name=test add -A
        git -c user.email=t@example.invalid -c user.name=test commit -qm init
    )
}

run() { # run <args...> — with the fixture store
    MEMORY_DIR="$T/mem" MEM_PI_SESSIONS="$T/pi" \
        MEM_OPENCODE_DB="$T/absent.db" MEM_HERMES_DB="$T/absent.db" \
        "$MEM" "$@"
}

printf '\n== learn: writes the entry and indexes it ==\n'
setup
run learn flock-gap --repo "$T/repo" --title "flock is not on macOS" \
    --symptom "command -v flock exits 1" --cause "BSD userland has no flock(1)" \
    --fix "use fcntl.flock from python" > /dev/null
check_rc 0 $? "learn succeeds"
f="$(ls "$T/repo"/docs/learnings/*-flock-gap.md 2> /dev/null)"
[ -n "$f" ] && ok "wrote docs/learnings/<date>-flock-gap.md" || bad "no entry file"
grep -q '^## Symptom' "$f" && grep -q '^## Cause' "$f" && grep -q '^## Fix' "$f" \
    && ok "has the three required sections" || bad "sections missing"
grep -qF "[$(date +%Y-%m-%d) — flock is not on macOS](2026" "$T/repo/docs/learnings/README.md" \
    && ok "indexed in README.md" || bad "not indexed"
run learn flock-gap --repo "$T/repo" --title "again" --symptom s --cause c --fix f > /dev/null 2>&1
check_rc 1 $? "refuses to overwrite an existing entry"

printf '\n== learn: refuses outside a repo, accepts --repo ==\n'
setup
( cd /tmp && MEMORY_DIR="$T/mem" "$MEM" learn nope --title t --symptom s --cause c --fix f ) > "$T/out" 2>&1
check_rc 1 $? "refuses with no repo"
grep -q "not inside a git repository" "$T/out" && ok "says why, and what to do instead" \
    || bad "no guidance: $(cat "$T/out")"
grep -q "mem inbox add" "$T/out" && ok "points agent-behaviour lessons at the inbox" || bad "no inbox pointer"

printf '\n== inbox: append, dedupe, header ==\n'
setup
run inbox add bash "rg -r is --replace" > /dev/null
check_rc 0 $? "appends"
grep -q '^# Learnings inbox' "$T/mem/inbox.md" && ok "creates the header" || bad "no header"
run inbox add bash "rg -r is --replace" > "$T/out" 2>&1
check_rc 1 $? "dedupes the same text"
grep -q 'already in the inbox' "$T/out" && ok "says it was already there" || bad "no dedupe message"
[ "$(grep -c '^- \[' "$T/mem/inbox.md")" -eq 1 ] && ok "one line, not two" || bad "duplicated"
run inbox add correction "no, use config push" --session abcd1234 > /dev/null
grep -q 'session abcd1234' "$T/mem/inbox.md" && ok "records the session" || bad "session missing"

printf '\n== distill: prints candidates and the ladder ==\n'
setup
run inbox add bash "one" > /dev/null
run inbox add correction "two" > /dev/null
run distill > "$T/out" 2>&1
check_rc 0 $? "distill runs"
grep -q '2 candidate(s)' "$T/out" && ok "counts candidates" || bad "wrong count"
grep -q 'Promotion ladder' "$T/out" && ok "prints the ladder" || bad "no ladder"
grep -q 'rung 3' "$T/out" && ok "carries the seen-twice rule" || bad "ladder incomplete"

printf '\n== distill: an empty inbox is not an error ==\n'
setup
run distill > "$T/out" 2>&1
check_rc 0 $? "distill on empty"
grep -q 'inbox is empty' "$T/out" && ok "says so" || bad "no message"

printf '\n== recall: pi sessions, filters, and misses ==\n'
setup
mkdir -p "$T/pi/proj"
cat > "$T/pi/proj/sess1.jsonl" <<'JSONL'
{"type":"message","id":"s1","timestamp":"2026-10-23T10:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"the flock syscall lives in fcntl"}]}}
{"type":"message","id":"s1","timestamp":"2026-10-23T10:01:00.000Z","message":{"role":"user","content":"unrelated chatter"}}
JSONL
run recall flock --days 30 > "$T/out" 2>&1
check_rc 0 $? "recall runs"
grep -q 'pi' "$T/out" && grep -qi 'fcntl' "$T/out" && ok "finds the pi hit" || bad "pi hit missing: $(cat "$T/out")"
run recall "flock nonsense-word" --days 30 > "$T/out" 2>&1
grep -q 'nothing in the last' "$T/out" && ok "requires every word (no false hit)" || bad "matched a partial query"
run recall flock --days 0 > "$T/out" 2>&1
grep -q 'nothing in the last' "$T/out" && ok "respects --days" || bad "--days ignored"

printf '\n== recall: opencode and hermes SQLite fixtures ==\n'
setup
python3 - "$T" <<'PY'
import sqlite3, sys, pathlib
t = pathlib.Path(sys.argv[1])
oc = sqlite3.connect(t / "oc.db")
oc.executescript("""
CREATE TABLE session (id text primary key, title text);
CREATE TABLE part (id text primary key, message_id text, session_id text, time_created integer, data text);
""")
oc.execute("insert into session values ('ses1','Upgrading opencode v2')")
oc.execute("insert into part values ('p1','m1','ses1',?,?)",
           (int(__import__('time').time() * 1000), '{"type":"text","text":"pinned the V2 CLI from npm"}'))
oc.commit()
he = sqlite3.connect(t / "he.db")
he.executescript("""
CREATE TABLE sessions (id text primary key, title text);
CREATE TABLE messages (session_id text, timestamp real, role text, content text);
""")
he.execute("insert into sessions values ('h1','Hermes deep infra work')")
he.execute("insert into messages values ('h1',?, 'tool', 'exit code 1 from nix build')",
           (__import__('time').time(),))
he.commit()
PY
MEMORY_DIR="$T/mem" MEM_PI_SESSIONS="$T/pi" MEM_OPENCODE_DB="$T/oc.db" MEM_HERMES_DB="$T/he.db" \
    "$MEM" recall "npm" --days 30 --source opencode > "$T/out" 2>&1
grep -q 'opencode' "$T/out" && grep -q 'V2 CLI from npm' "$T/out" && ok "finds the opencode hit" \
    || bad "opencode hit missing: $(cat "$T/out")"
MEMORY_DIR="$T/mem" MEM_PI_SESSIONS="$T/pi" MEM_OPENCODE_DB="$T/oc.db" MEM_HERMES_DB="$T/he.db" \
    "$MEM" recall "exit code" --days 30 --source hermes > "$T/out" 2>&1
grep -q 'hermes' "$T/out" && grep -q 'Hermes deep infra work' "$T/out" && ok "finds the hermes hit with its session title" \
    || bad "hermes hit missing: $(cat "$T/out")"

printf '\n== recall: a missing database is not an error ==\n'
setup
run recall anything --days 30 --source hermes > "$T/out" 2>&1
check_rc 0 $? "degrades quietly"
grep -q 'nothing in the last' "$T/out" && ok "reports no hits" || bad "wrong output: $(cat "$T/out")"

printf '\n== concurrency: parallel appends do not corrupt the inbox ==\n'
setup
for i in $(seq 1 12); do
    run inbox add bash "parallel line $i" > /dev/null 2>&1 &
done
wait
n="$(grep -c '^- \[' "$T/mem/inbox.md" 2> /dev/null || echo 0)"
[ "$n" -eq 12 ] && ok "all 12 lines landed" || bad "expected 12 lines, got $n"
# Every candidate line must be whole and carry its own text: a torn write shows
# up as a line that starts like a candidate but is missing its tail, or as a
# fragment that starts mid-line. Only candidate lines are checked — the header
# is prose.
torn="$(grep '^- \[' "$T/mem/inbox.md" | grep -cvE '^- \[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}\] bash — parallel line [0-9]+$' || true)"
[ "$torn" -eq 0 ] && ok "no torn candidate lines" || bad "$torn torn candidate line(s)"
for i in $(seq 1 12); do
    c="$(grep -c "parallel line $i\$" "$T/mem/inbox.md" 2> /dev/null || true)"
    c="${c:-0}"
    [ "$c" -eq 1 ] || { bad "line $i appears $c time(s)"; break; }
done
[ "$(grep -c 'parallel line' "$T/mem/inbox.md")" -eq 12 ] && ok "each of the 12 texts appears exactly once" \
    || bad "duplicate or missing texts"

printf '\n== summarised: %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
