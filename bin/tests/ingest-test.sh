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
create table session_v2 (id text primary key, parent_id text, directory text, title text,
  agent text, model text, cost real, tokens_input int, tokens_output int,
  tokens_reasoning int, tokens_cache_read int, tokens_cache_write int,
  time_created int, time_updated int);
create table session_message (id text primary key, session_id text, type text, seq int,
  time_created int, time_updated int, data text);
""")
con.execute(
    "insert into session_v2 values (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
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
             "state": {"status": "completed",
                       "input": {"cmd": "cat /etc/hosts", "path": "/etc/hosts"},
                       "output": "a\nb"}},
            # a failed tool call: status on the part, signature in the output
            {"type": "tool", "id": "call-2", "name": "bash",
             "state": {"status": "error", "input": {"cmd": "nope"},
                       "output": "/bin/bash: nope: command not found"}},
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
if grep -q '"dst":"/etc/hosts"' "$T/raw/sessions/opencode"/*/*/ses_test/edges.jsonl 2>/dev/null; then
    ok "file edge extracted from a tool call"
else
    bad "no file edge for the tool's path"
fi
if grep -q 'command not found' "$T/raw/sessions/opencode"/*/*/ses_test/edges.jsonl 2>/dev/null; then
    ok "error edge carries the failure signature"
else
    bad "no error edge for the failed tool call"
fi
out="$(MEMORY_DIR="$T/mem" MEMORY_RAW="$T/raw" "$MEM" show "session://opencode/ses_test#turn-1" 2>&1)"
case "$out" in
    *"opencode/ses_test"*) ok "show resolves an anchor to its turn" ;;
    *) bad "show did not resolve the anchor" ;;
esac
out="$(run_oc 2>&1)"
check "opencode re-ingest is idempotent" "0" "$(printf '%s' "$out" | sed -n 's/.*ingested \([0-9]*\) opencode session(s).*/\1/p')"

echo "== hermes: flags, api_content, system_prompts join =="
HDB="$T/hermes.db"
python3 - "$HDB" <<'PY'
import sqlite3, sys

con = sqlite3.connect(sys.argv[1])
con.executescript("""
create table sessions (id text primary key, parent_session_id text, cwd text, title text,
  git_branch text, model text, model_config text, system_prompt_hash text,
  started_at real, ended_at real, input_tokens int, output_tokens int,
  cache_read_tokens int, cache_write_tokens int, reasoning_tokens int,
  estimated_cost_usd real, actual_cost_usd real, cost_source text);
create table system_prompts (hash text primary key, prompt text);
create table messages (id integer primary key, session_id text, role text, content text,
  tool_calls text, tool_call_id text, tool_name text, api_content text,
  reasoning_content text, timestamp real, token_count int, finish_reason text,
  active int, compacted int, display_order int);
""")
con.execute("insert into system_prompts values ('abc123', 'you are hermes')")
con.execute(
    "insert into sessions values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
    ("hs1", None, "/tmp/h", "A hermes title", "main", "m", "{}", "abc123",
     1761300000.0, 1761300100.0, 10, 5, 0, 0, 0, 0.1, 0.12, "provider"),
)
# (id, role, content, tool_calls, tool_call_id, tool_name, api_content,
#  reasoning_content, timestamp, token_count, finish_reason, active, compacted,
#  display_order)
rows = [
    (1, "user", "hello", None, None, None, None, None, 1761300001.0, 0, None, 1, 0, 1),
    (2, "assistant", "hi there", None, None, None, "hi there", None,
     1761300002.0, 0, "stop", 1, 0, 2),
    (3, "user", "superseded", None, None, None, None, None,
     1761300003.0, 0, None, 0, 1, 3),
]
for r in rows:
    con.execute(
        "insert into messages values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        (r[0], "hs1", *r[1:]),
    )
con.commit()
con.close()
PY

run_hm() {
    MEMORY_DIR="$T/mem" MEMORY_RAW="$T/raw" MEM_HERMES_DB="$HDB" "$MEM" ingest hermes "$@"
}
out="$(run_hm 2>&1)"
check "hermes session ingested" "1" "$(printf '%s' "$out" | sed -n 's/.*ingested \([0-9]*\) hermes session(s).*/\1/p')"
hd="$(ls -d "$T"/raw/sessions/hermes/*/*/hs1)"
check "all rows archived, incl. the inactive one" "4" "$(wc -l < "$hd/turns.jsonl" | tr -d ' ')"
check "actual cost preferred over estimate" "0.12" "$(sed -n 's/.*"cost_usd": \([0-9.]*\).*/\1/p' "$hd/session.json")"
if grep -q '"synthetic":true' "$hd/turns.jsonl" && grep -rq 'you are hermes' "$T/raw/messages"; then
    ok "system prompt joined from system_prompts"
else
    bad "system prompt not joined"
fi
if grep -rq '"api_content":"hi there"' "$T/raw/messages"; then
    ok "api_content sidecar stored"
else
    bad "api_content missing"
fi
if grep -q '"active":0' "$hd/turns.jsonl"; then
    ok "inactive flags preserved"
else
    bad "inactive flags lost"
fi

out="$(run_hm 2>&1)"
check "hermes re-ingest is idempotent" "0" "$(printf '%s' "$out" | sed -n 's/.*ingested \([0-9]*\) hermes session(s).*/\1/p')"

# A flag flip changes nothing but flags; a digest over content alone would miss it.
python3 - "$HDB" <<'PY'
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute("update messages set active=1 where id=3")
con.commit()
con.close()
PY
out="$(run_hm 2>&1)"
check "a flag-only change triggers re-ingest" "1" "$(printf '%s' "$out" | sed -n 's/.*ingested \([0-9]*\) hermes session(s).*/\1/p')"

echo "== osaurus: SSE reassembly, reasoning keys, truncation =="
ODB="$T/osaurus.db"
python3 - "$ODB" <<'PY'
import json, sqlite3, sys

con = sqlite3.connect(sys.argv[1])
con.executescript("""
create table activity (seq integer primary key, id text, ts_ms integer, category text,
  locality text, source text, method text, path text, status integer, is_error integer,
  duration_ms real, model text, provider_id text, destination_host text,
  destination_label text, transport text, mode text, agent_id text, agent_name text,
  session_id text, turn_id text, request_id text, plugin_id text, access_key_id text,
  audience text, input_tokens int, output_tokens int, tokens_per_second real,
  bytes_sent int, bytes_received int, privacy_filter_applied int, redacted_count int,
  finish_reason text, error_message text, title text, payload blob, prev_hash text, hash text);
""")

def sse(chunks, done=True):
    body = "\n\n".join("data: " + json.dumps(c) for c in chunks)
    return body + ("\n\ndata: [DONE]" if done else "\n\ndata: {\"trunc")

req = {"messages": [
    {"role": "system", "content": "you are a test"},
    {"role": "user", "content": "say hello"},
]}
part1 = {"choices": [{"delta": {"role": "assistant", "reasoning": "think"}}]}
part2 = {"choices": [{"delta": {"content": "hello "}}]}
part3 = {"choices": [{"delta": {"content": "world"}, "finish_reason": "stop"}]}
rows = [
    (1, 1761300000000, "Agent", "/v1/openai/chat/completions", 200, "m", "p",
     "a1", "Osaurus", "sess-a", None, "SESS-A:1:r0", 10, 5, 100.0,
     json.dumps({"wireRequestBody": json.dumps(req),
                 "wireResponseBody": sse([part1, part2, part3]),
                 "model": "m", "inputTokens": 10, "outputTokens": 5, "durationMs": 100.0})),
    (2, 1761300060000, "Agent", "/v1/openai/chat/completions", 200, "m", "p",
     "a1", "Osaurus", "sess-a", None, "SESS-A:2:r0", 11, 0, 50.0,
     json.dumps({"wireRequestBody": json.dumps(req),
                 "wireResponseBody": sse([part2], done=False),
                 "model": "m", "inputTokens": 11, "outputTokens": 0, "durationMs": 50.0})),
]
for r in rows:
    con.execute(
        "insert into activity (seq, ts_ms, source, path, status, model, provider_id,"
        " agent_id, agent_name, session_id, turn_id, request_id, input_tokens,"
        " output_tokens, duration_ms, payload, category)"
        " values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'inference')", r)
con.commit(); con.close()
PY

run_os() {
    MEMORY_DIR="$T/mem" MEMORY_RAW="$T/raw" MEM_OSAURUS_DB="$ODB" "$MEM" ingest osaurus "$@"
}
out="$(run_os 2>&1)"
check "osaurus session ingested" "1" "$(printf '%s' "$out" | sed -n 's/.*ingested \([0-9]*\) osaurus session(s).*/\1/p')"
od="$(ls -d "$T"/raw/sessions/osaurus/*/*/sess-a)"
if grep -rq '"text":"hello world"' "$T/raw/messages"; then
    ok "SSE deltas reassembled into one text"
else
    bad "SSE deltas not reassembled"
fi
# canonical JSON sorts keys, so match the two fields rather than one ordering
if grep -rq '"text":"think"' "$T/raw/messages" && grep -rq '"type":"reasoning"' "$T/raw/messages"; then
    ok "reasoning captured from the \`reasoning\` key"
else
    bad "reasoning delta dropped"
fi
check "truncated stream flagged on the turn" "1" "$(grep -c '"truncated":true' "$od/turns.jsonl" | tr -d ' ')"
out="$(run_os 2>&1)"
check "osaurus re-ingest is idempotent" "0" "$(printf '%s' "$out" | sed -n 's/.*ingested \([0-9]*\) osaurus session(s).*/\1/p')"

echo "== summaries: windowing and idempotence (no network) =="
out="$(MEMORY_DIR="$T/mem" MEMORY_RAW="$T/raw" "$MEM" summarize --dry-run --limit 20 2>&1)"
listed="$(printf '%s' "$out" | grep -c '^  [a-z]' | tr -d ' ')"
if [ "$listed" -ge 4 ]; then ok "dry run lists every fixture session ($listed)"; else bad "dry run listed $listed sessions"; fi
if [ -e "$T/mem/summaries" ]; then
    bad "dry run wrote a summaries directory"
else
    ok "dry run wrote nothing"
fi

# A stored summary whose source_digest matches must be skipped, with no API call.
od2="$(ls -d "$T"/raw/sessions/opencode/*/*/ses_test)"
digest="$(shasum -a 256 "$od2/turns.jsonl" | cut -d' ' -f1)"
mkdir -p "$T/mem/summaries/opencode"
printf -- '---\nharness: opencode\nsession: ses_test\nsource_digest: %s\n---\n\nNO DURABLE LESSONS\n' "$digest" \
    > "$T/mem/summaries/opencode/ses_test.md"
out="$(MEMORY_DIR="$T/mem" MEMORY_RAW="$T/raw" "$MEM" summarize --dry-run --limit 20 2>&1)"
if printf '%s' "$out" | grep -q 'ses_test'; then
    bad "a matching source_digest was not skipped"
else
    ok "matching source_digest skips the session"
fi

echo
printf 'summarized: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
