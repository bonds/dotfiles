# Agent memory pipeline — design plan

Status: **in progress 2026-10-25** — capture is *ingest*, not interception
(§5). Phase 0 (the proxy) was built, tested, then dropped, because every harness
already records the same facts. Phase 1 is live for pi; opencode, hermes and
osaurus importers are still to write.

Phase 0's code stays at `~/.config/nix/pkgs/agent-proxy/`, archived. It works —
9 tests, verified end-to-end against Deep Infra at TTFB 0.47 s — and the review
found a bug worth keeping the lesson from: `new URL(path, origin)` treats a
leading `//` as protocol-relative and would have forwarded the caller's bearer
token to an attacker-chosen host
(`docs/learnings/2026-10-25-url-relative-path-becomes-host.md`).
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
| D2 | **Capture by ingesting the native harness stores**, not by intercepting traffic. All four already record the system prompt, tool schemas, tokens and cost (§5). | A local proxy — it bought a uniform schema and per-request wire bodies, at the cost of a supervised service in front of every model call, for information the stores already held. |
| D3 | **Store each message once, content-addressed**, with a per-session turn log that references the digests. | Storing full request bodies per turn — quadratic, 10–50× the bytes. That was the *proxy's* problem, and ingest does not have it: the stores already hold each message once (measured: 1.4% duplicates within pi), so dedupe is now about identity for anchors and idempotent re-ingest, not about saving bytes. |
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
| D17 | **Ingest incrementally, against a per-store watermark, before compaction can replace history.** | One-off exports — hermes compaction does not rewrite content, it sets `active=0, compacted=0` on the originals and *clones* the carried tail with fresh ids (`hermes_state_messages.py`), so a delayed export sees re-sequenced rows and duplicates with no way to tell which the model actually saw. |

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

`memory/` and `raw/` are **two repos** under one parent, not one, so the curated
history stays readable and the one thing you might ever need to rewrite (a leaked
secret in a transcript) is isolated from decision history.

`raw/` currently marks `*.json` and `*.jsonl` as `text eol=lf`; phase 2 adds
`*.zst binary -diff -merge`. It has a `sophrosyne` remote — a bare repo on the
server, 33 MB packed against a 193 MB working tree, which is the per-file block
overhead collapsing in git's object store. Every harness store lives on
accismus, so ingest runs only there and that remote is purely a backup.

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

## 5. Why there is no proxy

The first draft captured traffic with a local HTTP proxy in front of the
provider. Phase 0 built it and it worked. It was then dropped, because every
harness was already recording the same facts — and in places, more.

| | system prompt | tool schemas | model / params | tokens | cost | reasoning | tool calls |
|---|---|---|---|---|---|---|---|
| **pi** | full `content` plus named `sections` | `toolsAdded`, with descriptions | model, provider, thinking level | in / out / cache read / cache write / reasoning | itemised per turn | ✅ | results with `isError`, `durationMs` |
| **opencode** | `instruction_blob`, content-addressed, pinned per session by `instruction_state` | its own blob | agent, mode, model, provider | per session and per step | per step | reasoning parts | `tool` parts with call state |
| **hermes** | `system_prompts` hash → 46 KB prompt, plus `session.system_prompt_hash` | `tool_names` | model, `model_config` | incl. cache and reasoning | estimated **and** actual, with source and pricing version | `reasoning_content` | `tool_calls`, `api_content` |
| **osaurus** | `activity.sqlite` payloads | — | — | ✅ | billing ledger | — | `mcp_tool_call` |

opencode reaching this design independently is the telling part: its
`instruction_blob` is a hash → content store and `instruction_state` pins which
blobs composed a given session. That is content addressing, arrived at for the
same reason this plan argues for it.

What a proxy bought that these do not:

- **A uniform schema.** A mapping problem, which phase 1 has either way.
- **Sampling parameters exactly as sent.** Partial in all four; none is a
  reason to run a service.
- **Provider-side truth** about retries and routing. Thinner than it sounds —
  hermes already records actual *and* estimated cost with a `cost_source`.
- **The exact per-request message array.** Reconstructible from the turn
  sequence, and arguably better: you can rebuild the context at any turn
  boundary, not only at the sampled ones.

Against that: a supervised service in front of every model call for three
harnesses, a single point of failure, and a bug class phase 0 actually hit.

So capture becomes **ingest**: read the stores, normalise, archive. The archive
is still the system of record (D1), because the stores are not durable —
opencode may prune, pi rotates, osaurus's `activity.sqlite` is already 5 GB, and
hermes re-sequences a session when it compacts — cloning carried messages under
new ids and flagging the originals. That is what D17 is for.

The proxy code stays in the tree, archived: the streaming and SSRF work is
sound and wire truth may be wanted later. It is not shipped, and no harness
points at it.

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

**Known cost: block overhead, not redundancy.** One file per message means one
4 KB block per message: 4,478 messages measured 11.1 MB of content but 21 MB on
disk. zstd cannot help — the waste is allocation, not repetition. If the archive
passes ~2 GB or ~100k messages, the fix is one file per session plus a digest
index, not better compression. Deferred deliberately: at a fortnight ≈ 23 MB the
arithmetic does not justify the complexity.

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
| **0** | Proxy passthrough — built, tested, then superseded by §5. Archived, not shipped. | (retired) |
| **1** | Ingest + normalise → content-addressed messages and per-session turn logs, per-store watermark, redaction on the write path, hash chain. ✅ **pi** (19 sessions, 4,542 turns, 0 chain errors, 0 live secrets); opencode, hermes, osaurus pending. | `test_idempotent_reingest`; `test_watermark_resume`; `test_message_survives_compaction`; redaction table; `test_linear_storage` |
| **2** | Compression, trained dictionary, hot/cold rollover | `test_stream_decompress_matches`; `test_dictionary_training_deterministic` |
| **3** | FTS index (curated + transcripts), `mem recall` and `mem show` over the archive | `test_index_rebuild_from_raw`; `test_recall_returns_cited_turn` |
| **4** | Summariser: goals / tried / worked / failed / gotchas / dead ends | `test_no_durable_lessons_outcome`; `test_every_claim_has_anchor`; `test_budget_cap_stops_run`; `test_idempotent_summarize` |
| **5** | Principle proposals as a diff; `mem doctor`; decay and contradiction passes | `test_principle_requires_anchor`; `test_conflict_detected_by_scope`; `test_doctor_reports_token_cost`; `test_proposal_is_a_diff_not_a_write` |
| **6** | Behavioural evals per principle (A/B with/without, N≈5–10) | `test_eval_harness_records_arm_and_outcome` |

Each phase is independently useful and revertable. Phase 1 is the risky one;
2–6 are additive on top of a working archive. Phases 1–2 are built and tested
outside nix (D14); packaging lands once ingest is green.

### 9.1 Acceptance checks

Phase 0 — done:

1. ✅ **Working Folder writes through** (2026-10-25). `hello.txt` created on the
   host, owned `scott:staff`; nothing written under the container workspace.
2. ✅ **Sandbox isolation** (2026-10-25). Host path rejected as invisible; a
   sandbox write landed in `~/.osaurus/container/workspace/agents/<id>/`.
3. ~~Proxy fail-open~~ — moot, there is no proxy (§5).
4. ✅ **Osaurus wire snapshots located** (2026-10-25) — `activity.sqlite`.

Phase 1 — before ingest is called done:

5. **Reconstruction is sufficient.** Rebuild the message array for one real pi
   turn from the session log and diff it against what followed in the next
   request. Confirms the turn sequence replaces the wire body.
6. **Compaction does not lose history.** Ingest a hermes session that has since
   been compacted, and show the pre-compaction messages survived.
7. **Idempotence.** Ingest the same stores twice: zero new rows, identical
   hashes.
8. **Redaction.** A fixture with a fake key in a tool result comes out as
   `[REDACTED:…]`, with the count recorded on the record.

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

Settled: the harness paths (D2), the two Osaurus modes (§3.1), the proxy (§5),
and the store location (§3).

Remaining:

1. **Osaurus ingest scope.** `activity.sqlite` is 5 GB, 99.5% embeddings.
   Ingest inference only (5,138 rows in 22 days, ~451 KB each) — the rest is
   not conversation.
2. ~~Hermes `api_content`~~ — resolved from the source: it is a "byte-fidelity
   sidecar, the exact string sent to the API when it differed from `content`".
   So hermes alone keeps the wire string wherever it diverged, which answers
   check 5 for it and means no proxy is needed for that harness.
3. **Watermark per store.** pi has file mtime plus append-only lines; opencode
   has monotonic ids; hermes has ids *and* a `compacted` flag; osaurus has
   `seq`. Each needs its own resume rule, and all must be idempotent.
4. **`redacted_count` is 0 on 1.75 M rows.** Confirm the scrubber is wired
   before treating osaurus's store as a safe source.
5. **Budget cap.** ~$0.015 per summary at Flash pricing, ~$2–3/month. Cap at
   $2/night as a circuit breaker, not a cost control.
6. **Subagent runs.** Own session records with `parent` set, own cost only,
   subtree totals rolled up on read; summaries skipped by default.

## 12. Non-goals

- **Wire-level capture** by proxy (§5). The code exists, archived; nothing
  points at it.
- **Injection at the wire.** That was a proxy dividend. Without a proxy it
  would be a harness plugin or `AGENTS.md`, so it is out of scope entirely.
- **Cold archive / tiering** (D4) — everything stays hot.
- **Multi-user or multi-tenant anything.**
- **Replacing harness stores.** They stay, as ingest sources.

## 13. Size expectations

Measured 2026-10-25: ~1,414 sessions, ~76k turns, ~710 MB of harness content
over ~5 months → **~1.5–2 GB/year raw**, **~100–200 MB/year compressed** with
zstd + dictionary. Naive full-request capture would be 10–50× larger, which is
why D3 is not optional.
