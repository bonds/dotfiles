#!/usr/bin/env bash
# Ingest test suite — the pi importer in bin/mem.
#
# Every case runs against throwaway MEMORY_DIR / MEMORY_RAW / MEM_PI_SESSIONS,
# so it never touches the real archive or a real session log.
#
#   bash ~/bin/tests/ingest-test.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
MEM="$HERE/mem"
T=/tmp/ingest-tests
pass=0
fail=0

ok() { printf '  PASS  %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }
check() { # check <label> <expected> <actual>
    if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1 (expected $2, got $3)"; fi
}

SYSTEM_TEXT='you are a test harness'

setup() {
    rm -rf "$T"
    mkdir -p "$T/mem" "$T/raw" "$T/pi/sessions/proj"

    # Session A: system, user (with a secret), assistant, tool result.
    cat > "$T/pi/sessions/proj/a.jsonl" <<EOF
{"type":"session","version":"1.4.0","id":"sess-a","timestamp":"2026-10-25T10:00:00.000Z","cwd":"/tmp/x","provider":"deepinfra","modelId":"model-a"}
{"type":"message","timestamp":"2026-10-25T10:00:01.000Z","message":{"role":"system","content":[{"type":"text","text":"$SYSTEM_TEXT"}]}}
{"type":"message","timestamp":"2026-10-25T10:00:02.000Z","message":{"role":"user","content":[{"type":"text","text":"deploy with DEEPINFRA_API_KEY=abcdef1234567890abcdef please"}]}}
{"type":"message","timestamp":"2026-10-25T10:00:03.000Z","message":{"role":"assistant","content":[{"type":"text","text":"ok"}],"model":"model-a","provider":"deepinfra","usage":{"input":10,"output":5,"cacheRead":0,"cacheWrite":0,"reasoning":0,"cost":{"total":0.001}}}}
{"type":"message","timestamp":"2026-10-25T10:00:04.000Z","message":{"role":"toolResult","content":[{"type":"text","text":"done"}],"toolName":"bash","toolCallId":"call-1","isError":false}}
EOF

    # Session B: an identical system message, so one copy must serve both.
    cat > "$T/pi/sessions/proj/b.jsonl" <<EOF
{"type":"session","version":"1.4.0","id":"sess-b","timestamp":"2026-10-25T11:00:00.000Z","cwd":"/tmp/x","provider":"deepinfra","modelId":"model-a"}
{"type":"message","timestamp":"2026-10-25T11:00:01.000Z","message":{"role":"system","content":[{"type":"text","text":"$SYSTEM_TEXT"}]}}
{"type":"message","timestamp":"2026-10-25T11:00:02.000Z","message":{"role":"user","content":[{"type":"text","text":"second session"}]}}
EOF
}

run_mem() {
    MEMORY_DIR="$T/mem" MEMORY_RAW="$T/raw" MEM_PI_SESSIONS="$T/pi/sessions" "$MEM" ingest pi "$@"
}

msg_count() { find "$T/raw/messages" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
turn_count() { cat "$T/raw"/sessions/pi/*/*/*/turns.jsonl 2>/dev/null | wc -l | tr -d ' '; }

setup

echo "== ingest normalises and content-addresses =="
out="$(run_mem 2>&1)"
check "reports both sessions" "2" "$(printf '%s' "$out" | sed -n 's/.*ingested \([0-9]*\) pi session(s).*/\1/p')"
# A has 4 messages and B has 2, so 6 turns; B's system message is byte-identical
# to A's, so only 5 message files.
check "turns imported" "6" "$(turn_count)"
check "duplicate message stored once" "5" "$(msg_count)"

echo "== secrets are redacted on the write path =="
if grep -rq 'abcdef1234567890abcdef' "$T/raw/messages"; then
    bad "raw secret survived into the archive"
else
    ok "raw secret absent from the archive"
fi
if grep -rq 'REDACTED:assignment' "$T/raw/messages"; then
    ok "redaction marker written"
else
    bad "no redaction marker found"
fi
redactions="$(sed -n 's/.*"redactions": \([0-9]*\).*/\1/p' "$T/raw/sessions/pi/2026/10/sess-a/session.json" 2>/dev/null)"
check "session records the redaction count" "1" "$redactions"

echo "== re-ingest is idempotent =="
out="$(run_mem 2>&1)"
check "nothing reprocessed" "0" "$(printf '%s' "$out" | sed -n 's/.*ingested \([0-9]*\) pi session(s).*/\1/p')"
check "both sessions skipped" "2" "$(printf '%s' "$out" | sed -n 's/.*, \([0-9]*\) unchanged.*/\1/p')"
check "message count unchanged" "5" "$(msg_count)"

echo "== watermark picks up only the changed session =="
printf '%s\n' '{"type":"message","timestamp":"2026-10-25T10:00:05.000Z","message":{"role":"user","content":[{"type":"text","text":"one more"}]}}' >> "$T/pi/sessions/proj/a.jsonl"
out="$(run_mem 2>&1)"
check "only session A reprocessed" "1" "$(printf '%s' "$out" | sed -n 's/.*ingested \([0-9]*\) pi session(s).*/\1/p')"
check "session B still skipped" "1" "$(printf '%s' "$out" | sed -n 's/.*, \([0-9]*\) unchanged.*/\1/p')"
check "new message added" "6" "$(msg_count)"
check "turns recount for A" "7" "$(turn_count)"

echo "== the hash chain is intact =="
if python3 - "$T/raw" <<'PY'
import hashlib, json, pathlib, sys
raw = pathlib.Path(sys.argv[1])
bad = 0
for f in raw.glob("sessions/pi/*/*/*/turns.jsonl"):
    prev = None
    for line in f.read_text().splitlines():
        if not line.strip():
            continue
        t = json.loads(line)
        body = json.dumps({k: v for k, v in t.items() if k not in ("prev", "hash")},
                          sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        if hashlib.sha256(body.encode()).hexdigest() != t["hash"]:
            bad += 1
        if prev is not None and t["prev"] != prev:
            bad += 1
        prev = t["hash"]
sys.exit(1 if bad else 0)
PY
then
    ok "every turn's hash and prev link verify"
else
    bad "hash chain broken"
fi

echo "== dry run writes nothing =="
rm -rf "$T/raw2"
MEMORY_DIR="$T/mem" MEMORY_RAW="$T/raw2" MEM_PI_SESSIONS="$T/pi/sessions" "$MEM" ingest pi --dry-run >/dev/null 2>&1
if [ -e "$T/raw2/messages" ]; then
    bad "dry run created message files"
else
    ok "dry run wrote no messages"
fi

echo "== opencode: V2 store, parts, compaction, parent link =="
OCDB="$T/opencode.db"
python3 - "$OCDB" <<'PY'
import json, sqlite3, sys

con = sqlite3.connect(sys.argv[1])
con.executescript("""
create table session (id text primary key, parent_id text, directory text, title text,
  agent text, model text, cost real, tokens_input int, tokens_output int,
  tokens_reasoning int, tokens_cache_read int, tokens_cache_write int,
  time_created int, time_updated int);
create table session_message (id text primary key, session_id text, type text, seq int,
  time_created int, time_updated int, data text);
""")
con.execute(
    "insert into session values (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
    ("ses_test", "ses_parent", "/tmp/proj", "A title", "build", "kimi-k2.6", 0.25,
     100, 50, 0, 10, 0, 1761300000000, 1761300100000),
)
rows = [
    ("m1", 1, "system", {"text": "you are a test harness", "time": {}}),
    ("m2", 2, "user", {"text": "please compact", "time": {}}),
    ("m3", 3, "assistant", {
        "agent": "build",
        "model": {"providerID": "p", "id": "kimi-k2.6", "variant": "default"},
        "cost": 0.5,
        "content": [
            {"type": "reasoning", "text": "thinking"},
            {"type": "text", "text": "here is the answer"},
            {"type": "tool", "id": "call-1", "name": "bash",
             "state": {"status": "completed", "input": {"cmd": "ls"}, "output": "a\nb"}},
        ],
    }),
    ("m4", 4, "compaction", {"summary": "earlier context summary", "status": "completed",
                             "reason": "auto"}),
]
for mid, seq, kind, payload in rows:
    con.execute(
        "insert into session_message values (?,?,?,?,?,?,?)",
        (mid, "ses_test", kind, seq, 1761300000000 + seq * 1000, 0, json.dumps(payload)),
    )
con.commit()
con.close()
PY

run_oc() {
    MEMORY_DIR="$T/mem" MEMORY_RAW="$T/raw" MEM_OPENCODE_DB="$OCDB" "$MEM" ingest opencode "$@"
}
out="$(run_oc 2>&1)"
check "opencode session ingested" "1" "$(printf '%s' "$out" | sed -n 's/.*ingested \([0-9]*\) opencode session(s).*/\1/p')"
man="$(ls -d "$T"/raw/sessions/opencode/*/*/ses_test)/session.json"
check "parent link recorded" "ses_parent" "$(sed -n 's/.*"parent": "\([^"]*\)".*/\1/p' "$man")"
check "session cost taken from the session row" "0.25" "$(sed -n 's/.*"cost_usd": \([0-9.]*\).*/\1/p' "$man")"
if grep -q '"role":"compaction"' "$(ls -d "$T"/raw/sessions/opencode/*/*/ses_test)/turns.jsonl"; then
    ok "compaction event archived as a turn"
else
    bad "compaction event not archived"
fi
if grep -rq 'here is the answer' "$T/raw/messages" && grep -rq '"type":"tool_call"' "$T/raw/messages"; then
    ok "assistant parts normalised (text + tool_call)"
else
    bad "assistant parts not normalised"
fi
out="$(run_oc 2>&1)"
check "opencode re-ingest is idempotent" "0" "$(printf '%s' "$out" | sed -n 's/.*ingested \([0-9]*\) opencode session(s).*/\1/p')"

echo
printf 'summarised: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
