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
    # A two-dimensional semantic space where "mutex" and "flock" share an axis,
    # so a query can match a passage containing none of its words. Written by
    # setup() because each section wipes $T.
    cat > "$T/embed.py" <<'EMBED'
import json, re, sys
SYN = {"mutex": 0, "flock": 0, "fcntl": 0, "push": 1, "remote": 1}
out = []
for text in json.load(sys.stdin):
    v = [0.0, 0.0]
    for word in re.findall(r"[a-z]+", text.lower()):
        if word in SYN:
            v[SYN[word]] += 1.0
    out.append(v)
print(json.dumps(out))
EMBED
    (
        cd "$T/repo" || exit 1
        git init -q .
        git -c user.email=t@example.invalid -c user.name=test add -A
        git -c user.email=t@example.invalid -c user.name=test commit -qm init
    )
}

run() { # run <args...> — with the fixture store
    # MEM_EMBED_KEY_FILE points at nothing so a test can never reach the real
    # embeddings endpoint: an accidental network call in a test suite is a
    # flaky test that also costs money.
    MEMORY_DIR="$T/mem" MEM_PI_SESSIONS="$T/pi" \
        MEM_OPENCODE_DB="$T/absent.db" MEM_HERMES_DB="$T/absent.db" \
        MEMORY_RAW="$T/raw" MEM_INDEX_DIR="$T/index" MEM_DOCS="$T/repo/docs/learnings" \
        MEM_EMBED_KEY_FILE="$T/absent-secret" \
        "$MEM" "$@"
}

run_sem() { # run_sem <args...> — same, with the fixture embedder
    MEM_EMBED_CMD="python3 $T/embed.py" run "$@"
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

printf '\n== learn: from $HOME falls back to the dotfiles edit checkout ==\n'
# The dotfiles repo has no .git in $HOME, so `rev-parse --show-toplevel` fails
# there; without a fallback this died even though the lesson had an obvious
# home. MEM_DOTFILES_WORKTREE keeps the write inside the fixture.
mkdir -p "$T/wt/docs/learnings"
printf '# Learnings\n\nDomain lessons.\n\n## Entries\n\n' > "$T/wt/docs/learnings/README.md"
(
    cd "$HOME" || exit 1
    MEMORY_DIR="$T/mem" MEM_DOTFILES_WORKTREE="$T/wt" \
        "$MEM" learn home-fallback --title "from home" --symptom s --cause c --fix f
) > "$T/out" 2>&1
check_rc 0 $? "learn from \$HOME succeeds"
f="$(ls "$T/wt"/docs/learnings/*-home-fallback.md 2> /dev/null)"
[ -n "$f" ] && ok "wrote into the edit checkout" || bad "no entry in the worktree: $(cat "$T/out")"
grep -qF 'home-fallback' "$T/wt/docs/learnings/README.md" && ok "indexed there" || bad "not indexed"
# The fallback must stay narrow: outside $HOME there is no reason to assume the
# caller means the dotfiles repo, so this has to keep failing.
(
    cd /tmp || exit 1
    MEMORY_DIR="$T/mem" MEM_DOTFILES_WORKTREE="$T/wt" \
        "$MEM" learn outside-home --title t --symptom s --cause c --fix f
) > /dev/null 2>&1
check_rc 1 $? "still refuses from outside \$HOME"

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

printf '\n== capture: refuses credentials, allows patterns ==\n'
setup
run inbox add bash "the token was ghp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" > "$T/out" 2>&1
check_rc 1 $? "refuses a github token"
grep -q 'refused' "$T/out" && ok "says refused" || bad "no refusal: $(cat "$T/out")"
grep -q 'ghp_aaaa' "$T/out" && bad "echoed the secret back" || ok "does not echo the secret"
grep -q 'already in the inbox' "$T/out" && bad "wrote it anyway" || ok "wrote nothing"
[ -f "$T/mem/inbox.md" ] && bad "created the inbox" || ok "inbox untouched"
run inbox add bash "a ghp_ token is 36 characters" > /dev/null 2>&1
check_rc 0 $? "accepts a description of the shape"
run inbox add note "export GITHUB_TOKEN=abcdefghijklmnop1234 broke" > "$T/out" 2>&1
check_rc 1 $? "refuses an env-style assignment"
run inbox add note "export GITHUB_TOKEN=abcdefghijklmnop1234 broke" --allow-secret > /dev/null 2>&1
check_rc 0 $? "--allow-secret overrides"
run learn leaky --repo "$T/repo" --title t --symptom "curl -H 'Authorization: Bearer abcdefghijklmnop1234' 401" \
    --cause c --fix f > "$T/out" 2>&1
check_rc 1 $? "refuses a credential in --symptom"
[ -n "$(ls "$T/repo"/docs/learnings/*-leaky.md 2> /dev/null)" ] && bad "wrote the entry" || ok "wrote no entry"
run learn leaky --repo "$T/repo" --title t --symptom s --cause c --fix "the bearer header is 16+ chars" \
    > /dev/null 2>&1
check_rc 0 $? "a lesson about the header shape still lands"

printf '\n== distill: flags stale candidates ==\n'
setup
OLD=$(python3 -c 'import datetime;print((datetime.date.today()-datetime.timedelta(days=40)).isoformat())')
FRESH=$(python3 -c 'import datetime;print(datetime.date.today().isoformat())')
printf '%s\n' "- [$OLD 10:00] bash — an old unresolved line" "- [$FRESH 09:00] bash — a fresh one" \
    > "$T/mem/inbox.md"
run distill --no-check --json > "$T/out" 2>&1
check_rc 0 $? "distill --json runs"
python3 -c "import json;d=json.load(open('$T/out'));assert d['candidates'][0]['stale'] is True" \
    && ok "flags the 40d-old candidate" || bad "stale not flagged: $(cat "$T/out")"
python3 -c "import json;d=json.load(open('$T/out'));assert d['candidates'][1]['stale'] is False" \
    && ok "leaves the fresh one alone" || bad "fresh flagged stale"
run distill --no-check > "$T/out" 2>&1
grep -q 'STALE  40d' "$T/out" && ok "prints the age in text mode" || bad "no STALE line"
run distill --no-check --stale-days 100 > "$T/out" 2>&1
grep -q 'STALE' "$T/out" && bad "--stale-days ignored" || ok "--stale-days raises the bar"

printf '\n== distill: finds the rule a candidate would contradict ==\n'
setup
cat > "$T/rules.md" <<'RULES'
- Never force-push to a shared remote branch.
- Prefer rg (ripgrep) and fd over grep and find.
RULES
printf '%s\n' "- [$FRESH 10:00] correction — force-push to a shared remote branch is fine for feature work" \
    "- [$FRESH 10:01] bash — the oven timer beeps twice" > "$T/mem/inbox.md"
MEM_RULES="$T/rules.md" run distill --json > "$T/out" 2>&1
check_rc 0 $? "distill with a rules fixture runs"
python3 -c "import json;d=json.load(open('$T/out'));r=d['candidates'][0]['related'];assert r and r[0]['contradicts'] is True, r" \
    && ok "flags the polarity clash" || bad "clash missed: $(cat "$T/out")"
python3 -c "import json;d=json.load(open('$T/out'));assert d['candidates'][1]['related']==[]" \
    && ok "unrelated candidate stays clean" || bad "false positive on an unrelated line"
MEM_RULES="$T/rules.md" run distill > "$T/out" 2>&1
grep -q 'CONTRADICTS?' "$T/out" && ok "labels it in text mode" || bad "no CONTRADICTS? label"
grep -q 'may contradict a rule that already exists' "$T/out" && ok "summarises the clash count" \
    || bad "no summary line"
run distill --no-check > "$T/out" 2>&1
grep -q 'CONTRADICTS?' "$T/out" && bad "--no-check still scanned" || ok "--no-check skips the scan"

printf '\n== semantic: index, then query a vector space ==\n'
setup
mkdir -p "$T/raw/sessions/pi/2026/11/sess-a" "$T/raw/messages/d1"
printf '{"i":0,"msg":"d1","role":"user","ts":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%S+00:00)" > "$T/raw/sessions/pi/2026/11/sess-a/turns.jsonl"
printf '{"role":"user","content":[{"type":"text","text":"the flock syscall lives in fcntl, and the append lock needs it to serialise writers"}]}' \
    > "$T/raw/messages/d1/d1.json"
run index --dry-run > "$T/out" 2>&1
check_rc 0 $? "index --dry-run needs no embedder"
grep -q '1 unit(s) in range, 1 to embed' "$T/out" && ok "counts the units" || bad "wrong count: $(cat "$T/out")"
[ -f "$T/index/semantic.db" ] && bad "dry run created a database" || ok "dry run writes nothing"
run_sem index > "$T/out" 2>&1
check_rc 0 $? "index builds"
grep -q '1/1 embedded' "$T/out" && ok "embedded the turn" || bad "no progress: $(cat "$T/out")"
run_sem index > "$T/out" 2>&1
grep -q '0 to embed' "$T/out" && ok "re-indexing is incremental" || bad "re-embedded everything: $(cat "$T/out")"
run recall mutex --days 365 --source pi > "$T/out" 2>&1
grep -q 'nothing in the last' "$T/out" && ok "keyword search cannot find it" \
    || bad "keyword found it, so the fixture proves nothing"
run_sem recall mutex --days 365 --mode semantic --source pi > "$T/out" 2>&1
check_rc 0 $? "semantic recall runs"
grep -q 'fcntl' "$T/out" && ok "semantic recall finds the turn" || bad "semantic miss: $(cat "$T/out")"
run_sem recall mutex --days 365 --mode hybrid --source pi > "$T/out" 2>&1
check_rc 0 $? "hybrid recall runs"
grep -q 'fcntl' "$T/out" && ok "hybrid keeps the semantic hit" || bad "hybrid lost it: $(cat "$T/out")"
run recall mutex --days 365 --mode semantic --source pi > "$T/out" 2>&1
check_rc 0 $? "no embedder is not an error"
grep -q 'semantic search unavailable' "$T/out" && ok "says why, and falls back" || bad "no fallback message"
MEM_EMBED_MODEL=other/model run_sem recall mutex --mode semantic > "$T/out" 2>&1
check_rc 0 $? "a model mismatch is not fatal"
grep -q 'built with BAAI/bge-m3, not other/model' "$T/out" && ok "refuses to compare two models" \
    || bad "no model-mismatch message: $(cat "$T/out")"
MEM_EMBED_MODEL=other/model run_sem index > "$T/out" 2>&1
check_rc 1 $? "index refuses to mix models"
MEM_EMBED_CMD=false run index --rebuild > "$T/out" 2>&1
check_rc 1 $? "a failing embedder is an error"
grep -q 'no embedder' "$T/out" && ok "names the way out" || bad "no guidance: $(cat "$T/out")"

printf '\n== semantic: the similarity floor ==\n'
setup
mkdir -p "$T/raw/messages"
# Cosine against the query axis is dialled by how many words sit on each axis:
# 3 flock / 4 push -> 0.60, 2/3 -> 0.555, 1/2 -> 0.447, 0 -> 0. The trailing
# words are unmapped padding that clears the 60-character index floor. One
# session per passage: recall caps a session at two hits, so four passages in
# one session would test the cap instead of the floor.
PAD="and this sentence is only padding, written to clear the index floor"
i=0
for text in "flock flock flock push push push push" \
    "flock flock push push push" "flock push push" "push remote"; do
    mkdir -p "$T/raw/messages/m$i" "$T/raw/sessions/pi/2026/11/sess-b$i"
    printf '{"role":"user","content":[{"type":"text","text":"%s %s"}]}' "$text" "$PAD" \
        > "$T/raw/messages/m$i/m$i.json"
    printf '{"i":0,"msg":"m%d","role":"user","ts":"%s"}\n' "$i" \
        "$(date -u +%Y-%m-%dT%H:%M:%S+00:00)" > "$T/raw/sessions/pi/2026/11/sess-b$i/turns.jsonl"
    i=$((i + 1))
done
json_len() { python3 -c "import json;print(len(json.load(open('$T/out'))))" 2> /dev/null || echo ERR; }
run_sem index > "$T/out" 2>&1
check_rc 0 $? "index builds the fixture"
grep -q '4 to embed' "$T/out" && ok "four passages indexed" || bad "wrong count: $(cat "$T/out")"
run_sem recall mutex --days 365 --mode semantic --source pi --json > "$T/out" 2>&1
[ "$(json_len)" = 2 ] && ok "the floor keeps the two close passages" || bad "expected 2: $(cat "$T/out")"
run_sem recall mutex --days 365 --mode semantic --source pi --min-score 0.58 --json > "$T/out" 2>&1
[ "$(json_len)" = 1 ] && ok "--min-score raises the floor" || bad "expected 1: $(cat "$T/out")"
run_sem recall mutex --days 365 --mode semantic --source pi --min-score 0 --json > "$T/out" 2>&1
[ "$(json_len)" = 4 ] && ok "--min-score 0 keeps everything" || bad "expected 4: $(cat "$T/out")"

printf '\n== recall: the archive requires every word, like the stores ==\n'
setup
mkdir -p "$T/raw/sessions/pi/2026/11/sess-c" "$T/raw/messages/aa" \
    "$T/raw/messages/bb" "$T/raw/messages/cc"
# message_path() shards on the first two characters of the digest, so the files
# have to live at messages/<aa>/<aa>.json — a flat messages/a.json is invisible.
printf '{"role":"user","content":[{"type":"text","text":"the flock syscall lives in fcntl"}]}' \
    > "$T/raw/messages/aa/aa.json"
printf '{"role":"user","content":[{"type":"text","text":"flock is missing on darwin"}]}' \
    > "$T/raw/messages/bb/bb.json"
printf '{"role":"user","content":[{"type":"text","text":"fcntl has a lockf equivalent"}]}' \
    > "$T/raw/messages/cc/cc.json"
NOW="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"
printf '{"i":0,"msg":"aa","role":"user","ts":"%s"}\n' "$NOW" \
    >> "$T/raw/sessions/pi/2026/11/sess-c/turns.jsonl"
printf '{"i":1,"msg":"bb","role":"user","ts":"%s"}\n' "$NOW" \
    >> "$T/raw/sessions/pi/2026/11/sess-c/turns.jsonl"
printf '{"i":2,"msg":"cc","role":"user","ts":"%s"}\n' "$NOW" \
    >> "$T/raw/sessions/pi/2026/11/sess-c/turns.jsonl"
run recall "flock fcntl" --days 365 --source archive --json > "$T/out" 2>&1
check_rc 0 $? "archive recall runs"
[ "$(json_len)" = 1 ] && ok "only the message with both words matches" \
    || bad "OR-matching came back: $(cat "$T/out")"
grep -q 'lives in fcntl' "$T/out" && ok "and it is the right message" || bad "wrong hit"

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

printf '\n== recall: the output budget is enforced ==\n'
setup
# One hit per session (a session may contribute at most two), so the budget is
# what limits the output here, not the per-session cap.
for n in 1 2 3 4; do
    mkdir -p "$T/pi/p$n"
    printf '{"type":"message","id":"b%d","timestamp":"2026-10-23T10:0%d:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"the budget lesson number %d with enough padding to cost a few tokens"}]}}\n' \
        "$n" "$n" "$n" > "$T/pi/p$n/budget.jsonl"
done
run recall budget --days 30 --tokens 0 --source pi > "$T/out" 2>&1
check_rc 0 $? "recall --tokens 0 runs"
[ "$(grep -c 'budget lesson' "$T/out")" -eq 4 ] && ok "--tokens 0 shows every hit" \
    || bad "expected 4 hits, got $(grep -c 'budget lesson' "$T/out")"
run recall budget --days 30 --tokens 1 --source pi > "$T/out" 2>&1
check_rc 0 $? "recall --tokens 1 runs"
grep -q 'over the 1-token budget' "$T/out" && ok "says what the budget dropped" \
    || bad "no truncation note: $(cat "$T/out")"
[ "$(grep -c 'budget lesson' "$T/out")" -lt 4 ] && ok "drops hits over budget" || bad "budget ignored"

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

printf '\n== learn --evidence, why, backfill-evidence: provenance ==\n'
setup
# A one-message archive: the digest is a filename stem, and the turns file is what
# resolves an anchor back to a turn number. Built after every setup(), which wipes
# the throwaway tree.
digest="ab$(printf 'c%.0s' $(seq 1 62))"
raw_fixture() {
    mkdir -p "$T/raw/messages/${digest:0:2}" "$T/raw/sessions/opencode/2026/10/ses_test"
    printf '{"content": [{"type": "text", "text": "flock: command not found"}], "role": "tool", "v": 1}\n' \
        > "$T/raw/messages/${digest:0:2}/$digest.json"
    printf '{"i": 4, "msg": "%s", "role": "tool", "ts": "%s", "hash": "h", "prev": "", "seq": 1}\n' \
        "$digest" "$(date +%Y-%m-%dT%H:%M:%S)" \
        > "$T/raw/sessions/opencode/2026/10/ses_test/turns.jsonl"
    printf '{"id": "ses_test", "harness": "opencode", "started": "%s"}\n' \
        "$(date +%Y-%m-%dT%H:%M:%S)" \
        > "$T/raw/sessions/opencode/2026/10/ses_test/session.json"
}
raw_fixture
runp() {
    MEMORY_DIR="$T/mem" MEMORY_RAW="$T/raw" MEM_DOCS="$T/repo/docs/learnings" \
        MEM_PI_SESSIONS="$T/pi" MEM_OPENCODE_DB="$T/absent.db" MEM_HERMES_DB="$T/absent.db" \
        "$MEM" "$@"
}
runp learn flock-gap --repo "$T/repo" --title "flock is not on macOS" \
    --symptom 'command -v flock exits 1' --cause "BSD has no flock(1)" \
    --fix "use fcntl.flock" --evidence "session://opencode/ses_test#turn-4" > "$T/out" 2>&1
check_rc 0 $? "learn accepts --evidence"
f="$(ls "$T/repo"/docs/learnings/*-flock-gap.md 2> /dev/null)"
grep -q '^## Evidence' "$f" 2> /dev/null && ok "writes an Evidence section" || bad "no Evidence section"
grep -qF 'session://opencode/ses_test#turn-4' "$f" 2> /dev/null \
    && ok "the anchor survives intact" || bad "anchor missing or mangled"

runp why flock-gap > "$T/out" 2>&1
check_rc 0 $? "why <slug> succeeds"
grep -q 'flock is not on macOS' "$T/out" && ok "why prints the entry" || bad "entry not printed"
grep -q '^  evidence:' "$T/out" && ok "why lists the anchors" || bad "no evidence list"
grep -q 'command not found' "$T/out" && ok "why previews the cited turn" || bad "no preview"
runp why session://opencode/ses_test#turn-4 > "$T/out" 2>&1
check_rc 0 $? "why <anchor> succeeds"
grep -q 'flock: command not found' "$T/out" && ok "resolves the anchor to its turn" || bad "turn not shown"
grep -q 'cited by:' "$T/out" && ok "says who cites it" || bad "no citation line"
grep -qF 'docs/learnings/' "$T/out" && ok "names the citing file" || bad "citing file not named"
runp why no-such-entry > "$T/out" 2>&1
check_rc 1 $? "why refuses an unknown slug"
grep -q 'no learning matching' "$T/out" && ok "says what it looked for" || bad "unhelpful failure"

# Backfill runs against an entry written without evidence, so the positive case
# is the command's own path rather than the write-time one.
setup
raw_fixture
runp learn flock-gap2 --repo "$T/repo" --title "flock is not on macOS" \
    --symptom "$(printf 'Running a lock:\n\n```\nflock: command not found\n```')" \
    --cause c --fix f > /dev/null 2>&1
f="$(ls "$T/repo"/docs/learnings/*-flock-gap2.md 2> /dev/null)"
runp backfill-evidence --dry-run > "$T/out" 2>&1
check_rc 0 $? "backfill --dry-run succeeds"
grep -q 'would write evidence for 1' "$T/out" && ok "counts the entry it would fix" || bad "wrong count: $(cat "$T/out")"
grep -q '^## Evidence' "$f" && bad "dry run wrote to the file" || ok "dry run leaves the file alone"
runp backfill-evidence > "$T/out" 2>&1
grep -q '^## Evidence' "$f" && ok "backfill writes the section" || bad "no Evidence section"
grep -qF 'session://opencode/ses_test#turn-4' "$f" && ok "cites the turn holding the phrase" || bad "wrong anchor"
grep -q 'flock: command not found' "$f" && ok "quotes the matching line" || bad "no quote"
runp backfill-evidence > "$T/out" 2>&1
grep -q 'already had it' "$T/out" && ok "re-running does not duplicate the section" || bad "no skip count"

printf '\n== doctor freshness: a no-op ingest is not a stale archive ==\n'
# The archive's own `updated` stamp only moves when a session CHANGES, so a
# harness nobody used for a few days looked stale while the nightly job was
# healthy (2026-11-20: opencode "4d" against "522 unchanged" every night).
# Freshness must follow the run stamp, which lives outside the archive repo.
mkdir -p "$T/raw/state" "$T/state" "$T/wired"
printf '{"v":1,"updated":"2020-01-01T00:00:00","sessions":{}}\n' > "$T/raw/state/opencode.json"
printf '{"opencode":{"ran":"%s","processed":0,"skipped":522}}\n' \
    "$(date +%Y-%m-%dT%H:%M:%S)" > "$T/state/ingest-runs.json"
MEMORY_RAW="$T/raw" MEM_DOCTOR_AGENTS="$T/absent.md" MEM_DOCTOR_SKILLS="$T/skills" \
    MEM_DOCTOR_WIRED="$T/wired" "$MEM" doctor > "$T/out" 2>&1
check_rc 0 $? "clean fixture passes (a fresh run is not a failure)"
grep -qE '^  ok +opencode: last run' "$T/out" \
    && ok "a recent run is fresh even with an old archive stamp" \
    || bad "run stamp ignored: $(grep opencode "$T/out")"
grep -q 'last change 2020-01-01' "$T/out" \
    && ok "still reports when the archive last changed" \
    || bad "change stamp lost: $(grep opencode "$T/out")"
# And the reverse: a stale run must still warn, so a broken importer is visible.
printf '{"opencode":{"ran":"2020-01-01T00:00:00","processed":0,"skipped":0}}\n' \
    > "$T/state/ingest-runs.json"
MEMORY_RAW="$T/raw" MEM_DOCTOR_AGENTS="$T/absent.md" MEM_DOCTOR_SKILLS="$T/skills" \
    MEM_DOCTOR_WIRED="$T/wired" "$MEM" doctor > "$T/out" 2>&1
grep -qE '^  warn +opencode: last run' "$T/out" \
    && ok "a stale run still warns" \
    || bad "stale run not flagged: $(grep opencode "$T/out")"

# The brief is injected into every session, so its size belongs in the budget
# audit — reported, not counted, because it depends on the repo you are in.
grep -q 'session brief' "$T/out" && ok "doctor reports the brief size" \
    || bad "brief missing from the budget audit"

printf '\n== brief: the session-start block a harness injects ==\n'
setup
# Three entries, deliberately added out of order: the brief sorts newest first.
{
    printf -- '- [2026-01-02 — the older one](2026-01-02-older.md)\n'
    printf -- '- [2026-03-04 — the newest one](2026-03-04-newest.md)\n'
    printf -- '- [2026-02-03 — the middle one](2026-02-03-middle.md)\n'
} >> "$T/repo/docs/learnings/README.md"
THREE_AGO="$(python3 -c 'import datetime;print((datetime.date.today()-datetime.timedelta(days=3)).isoformat())')"
TODAY="$(date +%Y-%m-%d)"
printf -- '- [%s 10:00] bash — command not found — ~/x — session abc\n' "$THREE_AGO" > "$T/mem/inbox.md"
printf -- '- [%s 11:00] input — "no, use config push" — ~/x — session abc\n' "$TODAY" >> "$T/mem/inbox.md"
run brief --cwd "$T/repo" > "$T/out" 2>&1
check_rc 0 $? "brief runs"
grep -q '^repo: repo (' "$T/out" && ok "names the repository" || bad "no repo line: $(cat "$T/out")"
grep -q 'docs/learnings: 3 entries' "$T/out" && ok "counts the entries" || bad "wrong count: $(head -2 "$T/out")"
python3 - "$T/out" <<'ORDER'
import sys
lines = [l for l in open(sys.argv[1]) if l.startswith("- 2026")]
want = ["newest", "middle", "older"]
assert [w for w in want if w in lines[0]] == ["newest"], lines
assert [w for w in want if w in lines[1]] == ["middle"], lines
assert [w for w in want if w in lines[2]] == ["older"], lines
ORDER
[ $? -eq 0 ] && ok "newest first, not file order" || bad "wrong order: $(grep '^- 2026' "$T/out")"
grep -q 'inbox: 2 candidate(s), oldest 3d' "$T/out" \
    && ok "reports the inbox backlog and its age" || bad "inbox line: $(grep inbox "$T/out")"

run brief --cwd "$T/repo" --json > "$T/out" 2>&1
python3 - "$T/out" <<'JSON'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["repo"] == "repo", d["repo"]
assert d["learning_count"] == 3, d["learning_count"]
assert d["inbox"] == {"count": 2, "oldest_days": 3}, d["inbox"]
assert d["learnings"][0]["title"] == "the newest one", d["learnings"][0]
assert d["text"].startswith("repo: repo"), d["text"][:40]
JSON
[ $? -eq 0 ] && ok "--json carries the same facts" || bad "json shape: $(head -5 "$T/out")"

# The budget is what stops a big repo from filling the prompt: only the newest
# eight are listed, and the rest are summarised as a count.
setup
i=0
while [ "$i" -lt 12 ]; do
    printf -- '- [2026-04-%02d — entry %d](2026-04-%02d-e%d.md)\n' \
        "$((i + 1))" "$i" "$((i + 1))" "$i" >> "$T/repo/docs/learnings/README.md"
    i=$((i + 1))
done
run brief --cwd "$T/repo" > "$T/out" 2>&1
grep -q '12 entries, 4 older' "$T/out" && ok "summarises the overflow" || bad "count line: $(grep docs/learnings "$T/out")"
[ "$(grep -c '^- 2026' "$T/out")" = 8 ] && ok "lists at most eight" || bad "listed $(grep -c '^- 2026' "$T/out")"

# Outside a repo there is nothing to say about learnings, and inventing some
# from the dotfiles checkout would be wrong — only $HOME maps there.
run brief --cwd "$T" > "$T/out" 2>&1
grep -q 'no git repository' "$T/out" && ok "no repo, no learnings" || bad "claimed a repo: $(cat "$T/out")"
grep -q '^repo:' "$T/out" && bad "borrowed a repo it is not in" || ok "and does not borrow dotfiles"

# A repo that has never recorded anything gets the nudge instead of a blank.
setup
run brief --cwd "$T/repo" > "$T/out" 2>&1
grep -q 'none yet' "$T/out" && ok "an empty repo is told how to start" || bad "no nudge: $(cat "$T/out")"

printf '\n== summarized: %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
