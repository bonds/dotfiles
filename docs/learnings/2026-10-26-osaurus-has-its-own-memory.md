# Osaurus keeps its own memory, and it is not where ours belongs

## What it is

`~/.osaurus/memory/memory.sqlite` held, on 2026-10-26: **726 episodes, 80 pinned
facts, 4,465 transcript rows, 1,065 pending signals** — 21 MB.

Its shape is strikingly close to ours, arrived at independently:

| | Osaurus | ours |
|---|---|---|
| write path | debounced 60 s, one LLM call per session → episode + pinned facts | nightly batch, one summary per session |
| read path | relevance gate picks one section, ≤800 tokens, prepended to the message | `mem recall`, on demand |
| decay | salience × 0.5 every 30 days, evict below 0.2 | none (permanent archive) |
| dedupe | Jaccard ≥ 0.9 merge | content addressing |

`POST /memory/ingest` exists specifically "for seeding memory from existing chat
logs or migrating from another system", which makes it tempting.

## Why not to use it for our store

- **A second store, one direction of sync.** This is the fragmentation
  `DECISIONS.md` rejected: knowledge with two homes and no reconciliation.
- **Double distillation.** Their ingest runs *their* LLM over our summaries, so the
  text is paraphrased twice and the `[turn-N]` anchors do not survive. Nothing stays
  checkable.
- **The relevance gate would be swamped.** 996 episodes against their 726 would
  dominate selection for months, and `pending_signals` already sits at 1,065.
- **Their retention is 365 days** and salience-decayed. Permanent knowledge would
  quietly evaporate.

## What to do instead

One store, reached from both sides:

- **Applying**: the `mem` MCP server (stdio, host) exposes `recall`, `show` and
  `learnings` to Osaurus agents. Read-only, so a client retry is harmless.
- **Learning**: Osaurus's sessions reach the archive through `activity.sqlite`
  ingestion, which already captures the wire bodies.
- **Always-on rules**: `~/AGENTS.md`, which Osaurus reads.

## Worth revisiting

Their `episodes` table is 726 session summaries already written by Osaurus —
a cheaper source for osaurus session summaries than re-summarising those sessions
ourselves, though theirs carry salience and topics while ours carry turn anchors.

## Evidence

`session://opencode/ses_e8ca2e501ffeBxfIfKZ5hihPUf#turn-938`

Found by searching the archive for a verbatim phrase from this entry (3 hit(s) for `POST /memory/ingest`), within 3 days of the entry date.

> | Osaurus has its own memory system (726 episodes, 80 pinned facts, `POST /memory/ingest`) | the reason we did *not* push our summaries into it |
