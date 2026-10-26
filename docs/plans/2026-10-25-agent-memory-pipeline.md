# Agent memory pipeline — design plan

Status: **phase 0 code complete** (2026-10-25); phases 1–6 not started.
§9.1 checks 1–2 verified on accismus; 3 (fail-open) still needs a
launchd-packaged proxy; 4 (wire snapshots) outstanding.

Phase 0 lives at `~/.config/nix/pkgs/agent-proxy/` — a transparent, SSE-safe
passthrough with 9 tests against a local mock, plus an end-to-end check against
Deep Infra (TTFB 0.47 s, total 1.86 s, so streaming is genuinely unbuffered).
One blocking bug found in review and fixed: `new URL(path, origin)` treats a
leading `//` as protocol-relative, which would have forwarded the caller's
bearer token to an attacker-chosen host. See
`docs/learnings/2026-10-25-url-relative-path-becomes-host.md`.
Scope: capture → summarise → derive → distribute → maintain, across pi,
opencode, hermes and osaurus.

---

## 1. Problem

Lessons learned in a session are lost when the session is compacted or the
harness is replaced. Today `mem` captures *conclusions* (inbox, learnings,
`DECISIONS.md`) but not the *evidence* that produced them, so:

- a rule cannot be re-checked or expired when its premise changes;
- two rules can contradict each other with no way to arbitrate;
- "why does this rule exist?" has no answer beyond a prose rationale.

The fix is to make the raw record durable and first-class, then derive
everything above it with explicit provenance links.

## 2. Decisions settled

| # | Decision | Rejected alternatives |
|---|---|---|
| D1 | **The memory dir is the system of record.** Harness stores (pi JSONL, opencode/hermes/osaurus SQLite) are backfill sources and caches. | Treating harness stores as primary and indexing them in place — they are pruned, schema-churned, and lost when a harness is replaced. |
| D2 | **Capture at the wire via a local proxy**, one implementation for all four harnesses. | Per-harness hooks only — osaurus has no hooks, hermes' hook is untracked and machine-local, and hooks record intent rather than what the model actually saw. |
| D3 | **Store each message once, content-addressed**, with a per-request manifest. | Storing full request bodies per turn — quadratic; 10–50× the bytes for long sessions. |
| D4 | **Everything is recorded forever, hot, no tiers.** | Cold archive (`xz`) — saves ~60 MB/year for 5–10× the CPU and a new failure mode. |
| D5 | **Tool outputs capped at capture** (~16 KB inline; head+tail+sha256 beyond), pointer to the harness store retained. | Recording them in full — 80–90% of bytes, almost none of the causal-chain value. |
| D6 | **Proxy is local to each machine**, bound to `127.0.0.1`. | One proxy on sophrosyne serving both — adds a network hop to every model call and a shared failure domain. |
| D7 | **Fail-open on capture; fail-open on availability is a documented one-line switch**, not automatic reroute. | Automatic fallback routing — hides outages and silently loses capture. |
| D8 | **Raw transcripts live in a separate, rewritable repo** under the same parent dir. | Committing them to the curated repo — binary blobs, unreadable history, and no way to rewrite a leaked secret without touching decision history. |
| D9 | **Markdown is the source of truth for derived artifacts**; SQLite is a disposable, rebuildable index. | SQLite as the store — loses grep-ability and diffs. |
| D10 | **Per-repo `docs/learnings/` are mirrored into the memory dir** as a *derived, gitignored* copy, with a tracked index carrying source path + commit sha. The repo copy stays authoritative. | A tracked second copy — two writable sources of truth that drift silently. |
| D11 | **Osaurus is a backfill source, not a proxy client.** It already records wire bodies in `~/.osaurus/activity/activity.sqlite` behind a hash chain; the proxy covers pi, opencode and hermes only. | Pointing osaurus at the proxy as well — it would duplicate a *richer* log (tool calls, compaction) and give up the hash chain for nothing. |
| D12 | **Subagent runs get their own session records**, linked to the parent; cost is recorded per session and rolled up on read. | Folding them into the parent — loses turn boundaries and makes anchors ambiguous. |
| D13 | **Summarisation runs on DeepSeek V4.1 Flash at low effort**; escalate to medium only for claims that will become principles. | High effort everywhere — the saving is negligible either way, so the tiering is about verification, not cost. |
| D14 | **The proxy is packaged as a nix module + launchd agent**, but is developed and tested outside nix until phase 1 passes. | Nix from day one — every test iteration becomes a rebuild hand-off. |
| D15 | **Osaurus uses Working Folder mode pointed at the curated root**, sandbox off for that one agent; sandboxed agents cannot see the store. | A link farm into `/workspace` — symlinks do not cross the VM boundary (verified, §3.1); and putting the store inside `~/.osaurus/container/workspace/` would make the container dir the system of record. |
| D16 | **Two indexes**: a small curated index inside the agent root, a large transcript index beside `raw/`. | One index over everything — it would reach hundreds of MB/year and force the snapshot root to grow with the raw archive. |

### Known conflict, resolved by D10

"Everything under a single parent directory" vs `<repo>/docs/learnings/`, which
sits next to the code so domain facts are committed *with* the project.

Resolution: the repo copy stays authoritative; the memory dir holds a derived
mirror plus a tracked index (source path + commit sha). One place to look,
without a second writable source of truth. Still needs a `DECISIONS.md` entry.

## 3. On-disk layout

One small real root that an agent can be handed, and a bulk archive outside it.
Nothing an agent needs is spread across XDG slots.

```
~/.local/share/agents/
├── memory/                        # ← the root an agent is given (small)
│   ├── README.md
│   ├── inbox.md
│   ├── repos.txt                  # repos whose docs/learnings are mirrored
│   ├── summaries/<harness>/<session>.md
│   ├── principles/<slug>.md
│   ├── retired/                   # superseded, kept not deleted
│   ├── learnings/                 # gitignored mirror, derived from repos.txt
│   └── .index/
│       └── curated.sqlite         # gitignored, rebuildable, ~1–2 MB/year
└── raw/                           # ← outside the root (bulk)
    ├── .gitattributes
    ├── dictionary.zstd.dict
    ├── sessions/<harness>/<YYYY>/<MM>/<session-id>/
    │   ├── manifest.json
    │   ├── turns/0000.jsonl.zst
    │   └── requests/000042.json
    ├── messages/<ab>/<sha256>.json.zst
    └── .index/
        └── transcripts.sqlite     # gitignored, rebuildable

~/.config/agents/                  # proxy config, nix-managed, not agent-facing
```

`~/.agents/skills/` deliberately stays where it is — pi reads it natively as
the Agent Skills standard location — so this move does not eliminate `.agents`.
Only the store relocates: XDG-correct, and a clean root for Osaurus.

`memory/` and `raw/` are **two repos** under one parent, not one. `raw/` carries
`*.zst binary -diff -merge` so the curated history stays readable, and the one
thing you might ever need to rewrite (a leaked secret in a transcript) is
isolated from decision history.

Why the split: `memory/` grows at roughly **10 MB/year** (summaries ~4 MB,
principles ~0.4 MB, curated index ~1–2 MB), so it stays snapshot-able
indefinitely. `raw/` grows at **1.5–2 GB/year** and must never sit inside a
snapshot root.

### 3.1 Osaurus: which mode gets the root

Verified against `docs.osaurus.ai/sandbox` and `docs.osaurus.ai/agent-loop`
(2026-10-25):

- The **sandbox** VM has exactly two VirtioFS mounts: `/workspace` ↔
  `~/.osaurus/container/workspace/`, and `/output`. A sandboxed agent never
  sees an arbitrary host folder — "Sandbox mode never exposes or mounts a host
  folder."
- A **Working Folder** (`.hostFolder` mode) points an agent at any host
  directory with the sandbox **off**, and that agent "can only touch files in
  that folder."
- The two are mutually exclusive: "a chat uses either a folder or the sandbox,
  never both."

| Osaurus agent | Mode | Root | Sees the store |
|---|---|---|---|
| memory agent | Working Folder | `~/.local/share/agents/memory` | read/write |
| code-execution agent | Sandbox | `/workspace` | no |

**A link farm cannot bridge them.** A symlink inside `/workspace` is resolved by
the Alpine guest, where `/Users/scott/...` does not exist. That closes the
question for good.

Consequence to accept: the memory agent runs folder-scoped rather than
VM-isolated. That is the right trade for the one agent that must write to the
system of record, and it is the same boundary `AGENTS.md` has today. Code
execution stays sandboxed and simply cannot reach the store.

**Verified on this machine (2026-10-25).**

1. *Working Folder writes through.* A throwaway agent pointed at
   `~/tmp/scratch` with the sandbox off created `hello.txt` there, owned
   `scott:staff`. Nothing appeared under `~/.osaurus/container/workspace/`, so
   it wrote to the real path rather than to a copy.
2. *The sandbox cannot reach it, and its writes go elsewhere.* With the sandbox
   on, `file_read` on the same absolute host path was rejected — "absolute host
   paths outside the sandbox aren't visible" — and `file_search` found no copy.
   A file written in that mode landed at
   `~/.osaurus/container/workspace/agents/<id>/sandbox-test.txt` on the host,
   not in the working folder, which still held only `hello.txt`.

So the two modes are genuinely exclusive, not just documented that way.

**Discovered constraint: the workspace must stay small.** `shell_run` did not
run while `/workspace` held 8.9 GB of leftover Swift build artifacts, and it did
run once the tree was down to 1.1 GB. `/workspace` is
`~/.osaurus/container/workspace/`, mounted by VirtioFS.

Reading the source pins the numbers: `SandboxWorkspaceChangeTracker` sets
`maxBaselineBytes = 2 GiB` of tracked file content and
`maxTrackedEntries = 25_000`. Crossing either **skips change tracking for that
call** — it logs and returns, and the tool still executes — so the gate cannot
deny a command by itself. The real cost is the manifest scan that precedes every
mutation-capable call, which walks the whole tree.

Treat the budget as 2 GiB / 25k entries regardless: that is where undo tracking
stops and where the scan gets slow. The agent's quoted "too large to snapshot"
string appears nowhere in the source, so the original denial's exact cause stays
unconfirmed — the remediation is measured, the mechanism is inferred.
See `docs/learnings/2026-10-25-osaurus-shell-run-needs-a-small-workspace.md`.

Two consequences:

- **D15 is empirical, not just documented.** The memory agent must run with the
  sandbox off. Not only for write-through: `mem` would be invoked via
  `shell_run`, which is precisely the tool that needs the snapshot, so a
  sandboxed memory agent could not run `mem` at all.
- **D16 gets its strongest argument.** Nothing large may ever live under
  `/workspace`. The raw archive at ~2 GB/year would break command execution by
  existing.

If a *sandboxed* agent ever needs recall, the supported route is the Host API
Bridge (`osaurus-host agent memory query`), via a small plugin. Out of scope for
phase 1; note the 8 MiB bridge request cap.

## 4. Schemas

### 4.1 Message (content-addressed, one copy ever)

```json
{
  "v": 1,
  "role": "assistant",
  "content": [{"type": "text", "text": "..."}],
  "tool_calls": [{"id": "call_...", "name": "shell", "arguments": "{...}"}],
  "tool_call_id": null,
  "ts": "2026-10-25T12:00:00Z",
  "harness": "opencode",
  "session": "ses_...",
  "redactions": 0
}
```

Filename = `sha256` of canonical JSON (sorted keys, no whitespace) **after
redaction**. Consequence: replay is semantically identical but not byte-identical
to the original. Accepted.

### 4.2 Request manifest (one per API call)

```json
{
  "v": 1,
  "ts": "2026-10-25T12:00:01Z",
  "harness": "pi",
  "session": "ses_...",
  "turn": 42,
  "provider": "deepinfra",
  "model": "deepseek-ai/DeepSeek-V4.1-Flash-1017",
  "params": {"temperature": 0.7, "max_tokens": 8192, "reasoning_effort": "high"},
  "system": "sha256:...",
  "tools_hash": "sha256:...",
  "messages": ["sha256:...", "sha256:..."],
  "response": "sha256:...",
  "usage": {"in": 1234, "out": 567, "cache_read": 800, "cache_write": 0},
  "cost_usd": 0.0021,
  "request_id": "req_...",
  "latency_ms": 1840,
  "status": 200
}
```

`request_id` comes from the provider response; it is the dedupe key between
live capture and backfill. Fall back to `sha256(system + messages + params)`
when absent.

Borrowed from Osaurus's own activity log (`InsightsService` / `activity.sqlite`),
which reached this design independently and does two things we had missed:

- **A redaction count on every record.** Osaurus calls it `redacted_count`, we
  call it `redactions`; the point is the same, and it belongs on every record so
  an incomplete body is visibly incomplete rather than silently clean.
- **A `prev_hash` / `hash` chain in ingest order.** Cheap to compute, and it
  makes a retroactive edit to the archive visible. Without it, auditable means
  only that we wrote it down; with it, it means we can show it was not changed
  afterwards.

### 4.3 Session manifest

```json
{
  "v": 1,
  "id": "ses_...",
  "harness": "opencode",
  "started": "...", "ended": "...",
  "cwd": "/Users/scott/src/bonds/polyptych",
  "models": ["deepseek-ai/DeepSeek-V4.1-Flash-1017"],
  "turns": 63,
  "usage": {"in": 0, "out": 0, "cache_read": 0, "cache_write": 0},
  "kind": "main",
  "parent": null,
  "cost_usd": 0.42,
  "retention": "hot",
  "summary": "summaries/opencode/ses_....md",
  "harness_store": "sqlite:~/.local/share/opencode/opencode.db#session:ses_..."
}
```

`retention` is the escape hatch for D4 — a config change later, not a migration.

`kind` is `main` or `subagent`; `parent` holds the parent session id when
`kind=subagent` (D12). `cost_usd` is **own cost only** — subtree totals are
rolled up on read, never stored twice, so a total can never double-count.

### 4.4 Principle

```yaml
---
id: doas-full-path
status: active                  # active | superseded | retired
rung: skill                     # agents-md | skill | hook | automation
applies_when:
  harness: [pi, opencode, hermes, osaurus]
  task: [remote-deploy, privilege-escalation]
  paths: ["**/nix/**"]
statement: >
  doas rules match on the full command path; a bare `systemctl` will not
  match a rule written for `/run/current-system/sw/bin/systemctl`.
evidence:
  - session://opencode/ses_...#turn-42
  - file://.config/nix/agent-skills/machines-and-services/SKILL.md
supersedes: null
superseded_by: null
verified_at: 2026-10-25
verify_after_days: 180
conflicts_with: []
injected_into:
  - agent-skills/machines-and-services/SKILL.md
---

## Why
## Evidence
## Change log
```

Rules:

- Every principle carries **≥1 evidence anchor**. No anchor, no principle.
- Anchors are `session://<harness>/<id>#turn-N` or `file://<path>#L<n>`. No
  prose-only evidence — that is how unfalsifiable rules accumulate.
- `superseded` rather than deleted; `retired/` holds the file.
- `verify_after_days` is re-checked by the maintenance pass, and by
  `nr --update` for principles whose `applies_when` touches nix.

## 5. Proxy

### 5.1 Shape

- `127.0.0.1:8787`, plaintext HTTP in, TLS upstream.
- Route: `/v1/openai/*` → `https://api.deepinfra.com/v1/openai/*`.
- No TLS interception, no custom CA: each harness gets an explicit base URL.
- Managed by launchd (`KeepAlive`, `RunAtLoad`) on accismus; a second instance
  on sophrosyne later. The *store* syncs; the proxy does not.
- **Credential-free.** The proxy forwards the client's `Authorization` header
  and holds no key of its own, so no secret enters the nix store.
- Packaged as a nix module + `launchd.agents` entry (D14), but developed and
  tested outside nix until phase 1 passes, so the test loop is not gated on `nr`.
- Known gotcha: a `nr` switch restarts launchd agents, so a rebuild during a
  long streaming request kills it mid-stream. `KeepAlive` recovers in seconds;
  the harness sees a dropped connection and retries. Acceptable, but do not
  rebuild while a long autonomous run is in flight.

### 5.2 Harness config (one line each, all verified present)

| Harness | File | Key |
|---|---|---|
| pi | `~/.pi/agent/models.json` | `providers.deepinfra.baseUrl` |
| opencode | `~/.config/opencode/opencode.jsonc` | `provider.<id>.options.baseURL` |
| hermes | `~/.hermes/config.yaml` | `model.base_url` |

Plus a second, disabled-by-default provider entry `deepinfra-direct` pointing at
the real upstream — the D7 switch.

Osaurus is deliberately absent from this table: it captures itself (D11), so it
is backfilled rather than proxied. Its Working Folder / sandbox split is
independent of the proxy — see §3.1.

### 5.3 Failure semantics

| Failure | Behaviour |
|---|---|
| Disk write error | Request unaffected; error counted, logged once per minute |
| Queue full | Drop oldest, increment `dropped`; request unaffected |
| Upstream error | Pass through unchanged; capture the error body |
| Proxy process dead | Harness fails; switch to `deepinfra-direct` (one line, documented) |
| Redaction exception | Fail **closed** on the capture record (drop the record), never on the request |

`GET /healthz` → `{ok, queue_depth, dropped, last_write, upstream}`.
`mem proxy status` reads it and reports which provider entry is active.

**No disk I/O in the request path.** Writes are queued and flushed asynchronously;
the streaming tee only appends to an in-memory buffer.

### 5.4 Streaming

SSE must be forwarded chunk-by-chunk as it arrives. The capture buffer
accumulates the same chunks and is finalised on stream close. Test asserts the
client receives byte-identical chunks with no added latency beyond a fixed
threshold.

## 6. Redaction

On the write path, before compression, before git. Irreversible — no plaintext
copy anywhere "just in case".

Patterns (table-driven, ~20 test cases):

- `sk-[A-Za-z0-9]{20,}`, `ghp_*`, `github_pat_*`, `xox[baprs]-*`, `AKIA[0-9A-Z]{16}`
- `-----BEGIN [A-Z ]*PRIVATE KEY-----` … `-----END`
- `Authorization: Bearer …` — header never logged at all
- `(KEY|TOKEN|SECRET|PASSWORD|PASSWD)\s*[:=]\s*\S{8,}`
- high-entropy tokens ≥32 chars in an assignment context

Replacement: `[REDACTED:<kind>:<sha8>]` — correlatable without revealing.
Osaurus already does the same thing for its own secrets, rewriting to
`[REDACTED:<ENV_KEY>]` (`SecretScrubber`). Match that shape so a reader can tell
a redaction from content without knowing which system wrote it.
`redactions` count per message, so an incomplete record is *visibly* incomplete.

Second gate: entropy scan in `raw/.git/hooks/pre-commit`.

## 7. Compression

- `zstd -19`, one frame per appended batch of turns; frames concatenate and
  stream (`zstd -dc file.zst | hx -`).
- Trained dictionary (`zstd --train` over ~10k sampled messages) — the big win
  on many small, highly similar JSONL records. Versioned alongside the data;
  changing it requires recompression, so treat it as a schema change.
- Hot window: last 7 days uncompressed `.jsonl` so `rg` just works; compress on
  rollover.
- Tool output cap (D5) applied before hashing.

## 8. Index

Two FTS5 databases, because they differ in size and audience:

| Index | Covers | Lives | Size | In the agent root |
|---|---|---|---|---|
| `memory/.index/curated.sqlite` | summaries, principles, learnings | curated repo | ~1–2 MB/year | yes |
| `raw/.index/transcripts.sqlite` | every turn | raw repo | hundreds of MB/year | no |

- `mem recall` always searches curated; it adds transcripts when `MEMORY_RAW`
  is reachable.
- `mem show <anchor>` needs `raw/` and fails with a clear message when it is not
  present — "raw archive not available in this environment" — rather than a
  traceback.
- Both are gitignored and rebuildable: `mem index rebuild --scope curated|raw`.

Environment: `MEMORY_DIR` (curated root), `MEMORY_RAW` (bulk archive, optional),
`MEMORY_CONFIG`. Defaults resolve through `XDG_DATA_HOME` / `XDG_CONFIG_HOME`
with `~/.local/share` and `~/.config` as fallbacks.

## 9. Phases (tests first in each)

| Phase | Delivers | Failing test written first |
|---|---|---|
| **0** | ✅ Proxy passthrough, no capture; verify Osaurus modes (§9.1) | 9 tests green; p50 added latency measured well under 20 ms |
| **1** | Capture, schema, redaction, content addressing | `test_linear_storage` (100-turn synthetic session < 1.2× sum of messages); redaction table; `test_capture_failure_does_not_break_response`; `test_queue_overflow_drops_and_counts`; `test_no_auth_header_written` |
| **2** | Backfill + normalisation from pi JSONL, opencode/hermes/osaurus SQLite | `test_idempotent_reingest`; `test_watermark_resume`; per-harness import fixtures |
| **3** | Compression, dictionary, rollover, FTS index, `mem recall` | `test_stream_decompress_matches`; `test_index_rebuild_from_raw`; `test_recall_returns_cited_turn` |
| **4** | Summariser: goals / tried / worked / failed / gotchas / dead ends | `test_no_durable_lessons_outcome`; `test_every_claim_has_anchor`; `test_budget_cap_stops_run`; `test_idempotent_summarize` |
| **5** | Principle proposals as a diff; `mem doctor`; decay + contradiction passes | `test_principle_requires_anchor`; `test_conflict_detected_by_scope`; `test_doctor_reports_token_cost`; `test_proposal_is_a_diff_not_a_write` |
| **6** | Behavioural evals per principle (A/B with/without, N≈5–10) | `test_eval_harness_records_arm_and_outcome` |

Each phase is independently useful and revertable. Phases 0–1 are the risky
infrastructure; 2–6 are additive. Phases 0–1 are built and tested outside nix
(D14); packaging lands once phase 1 is green.

### 9.1 Phase 0 acceptance checks

Automated:

- Response through the proxy is byte-identical to direct, streaming included.
- p50 added latency < 20 ms across 50 requests.
- Proxy killed mid-stream: the client sees a closed connection, not a hang.

Manual, one-off — must pass before phase 1 starts, because phases 1–6 assume
them:

1. ✅ **Osaurus Working Folder writes through** (2026-10-25). `hello.txt`
   created on the host at `~/tmp/scratch`, owned `scott:staff`; nothing written
   under `~/.osaurus/container/workspace/`.
2. ✅ **Osaurus sandbox isolation** (2026-10-25). Host path rejected as
   invisible; a sandbox write landed in
   `~/.osaurus/container/workspace/agents/<id>/` instead of the working folder.
3. **Proxy fail-open.** Stop the launchd agent mid-stream: the request dies, the
   harness recovers, and a retry through `deepinfra-direct` succeeds. Confirms
   the D7 switch is real rather than theoretical.
4. ✅ **Osaurus wire snapshots** (2026-10-25). Already captured:
   `~/.osaurus/activity/activity.sqlite`, a hash-chained `activity` table with
   `payload` bodies (capped at 256 KiB by `InsightsService.maxBodySize`), token
   counts, `session_id`/`turn_id`/`request_id`/`agent_name`, and
   `redacted_count`. 5,138 inference rows in 22 days at ~451 KB each.

## 10. Hard rules

1. **Nothing unattended writes to `AGENTS.md`, a `SKILL.md`, or a hook.** The
   output of phase 5 is a diff for review. Capture and summaries may write
   freely — they are derived.
2. **Capture never blocks a request.**
3. **No secret is written, ever**, including in a test fixture.
4. **Every generated artifact is marked** `generated: true` + source hash, so it
   can be regenerated or reverted wholesale.
5. **The summariser must be able to say "no durable lessons."** Lesson
   inflation is a failure mode, not a success metric.
6. **Budgets are explicit**: max tokens per always-loaded surface (target ≤4k),
   max spend per nightly run.

## 11. Open questions

The original five are resolved (D10–D14), and the Osaurus mount question is
answered by §3.1. Remaining:

1. **Budget cap.** A capped session is ~60k tokens in, ~4k out, so ~$0.015 per
   summary at Flash pricing and ~$2–3/month at current volume. Set $2/night as
   a circuit breaker, not a cost control.
2. **Subagent summaries.** Skipped by default: their turns are indexed and
   recallable, but the narrative belongs to the parent session.
3. **Port.** 8787 assumed — confirm nothing on accismus already binds it.
4. **Mirror refresh trigger.** `mem learnings sync` runs on ingest; `mem doctor`
   reports any tracked index entry whose source sha has moved.
5. ~~Osaurus wire snapshots~~ — resolved by §9.1 check 4: they are in
   `activity.sqlite`, so osaurus is backfilled rather than proxied (D11). Open
   sub-question: `redacted_count > 0` on zero of 1.75 M rows, so confirm the
   scrubber is actually wired before trusting that store as a safe source.
6. **One memory agent or several.** A single folder-scoped agent is simplest;
   per-task agents would each need the same Working Folder.

## 12. Non-goals (phase 1)

- Injection of principles at the wire (phase 2 at the earliest; needs cache-prefix
  discipline given 0.006 vs 0.2 per M cache read/write).
- Cold archive / tiering (D4).
- OTEL spans as an alternative capture path.
- Multi-user or multi-tenant anything.
- Replacing harness stores — they stay, as backfill sources.

## 13. Size expectations

Measured 2026-10-25: ~1,414 sessions, ~76k turns, ~710 MB of harness content
over ~5 months → **~1.5–2 GB/year raw**, **~100–200 MB/year compressed** with
zstd + dictionary. Naive full-request capture would be 10–50× larger, which is
why D3 is not optional.
