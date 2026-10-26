# Doctor and the context budget

Status: **proposed** (2026-10-26). Nothing built yet.
Follows: [Agent memory pipeline](2026-10-25-agent-memory-pipeline.md), whose
phases 1, 3, 3.5 and 4 are live and whose phase 5 has produced one promotion.

## 1. Why this is next

Two problems have now been found by hand, twice each, and both are mechanical:

- The always-loaded context was 20% over budget (`AGENTS.md` 4,046 tokens against
  a 4,000 target) and nothing reported it.
- The skills layer carried a 1.1 MB opencode-only duplicate and an unroutable
  skill with no `description:` — and the unroutable one was a *stale copy* of a
  document that had moved on.

Neither was hard to find once someone looked. That is the definition of a check
worth automating.

## 2. The budget decision

**Target: 4,000 tokens of always-loaded context. Rule: no net growth.**

An addition must be paid for by moving a paragraph into a skill in the same edit.
This is stricter than raising the target, and it is what actually holds the line —
a target that has already been breached teaches you to ignore the check.

Baseline after the 2026-10-26 trim: **3,525 tokens** (`AGENTS.md` 2,741 + eight
skill descriptions 784). Headroom: ~475 tokens.

The trim that got there, recorded because the same moves will be tempting again:
nix workflow → `.config/nix/AGENTS.md` (loads only inside that tree); remote
deploy rules → `machines-and-services` skill; `Compounding` (2,272 chars) →
`memory` skill, keeping only the growth rule itself in context.

## 3. `mem doctor`

Report only. Nothing unattended edits a skill or `AGENTS.md` — the same hard rule
as phase 5's proposals. Exit code is non-zero when any check fails, so it can gate
a commit or a weekly pass.

| check | what it does | already caught, by hand |
|---|---|---|
| **budget** | token estimate of always-loaded surfaces, itemised by file | 4,827 vs 4,000 |
| **skill inventory** | each harness path vs canonical `agent-skills/`: extras, missing, untracked, no `description:` | `code-review-skill` (1.1 MB, opencode-only), `release-consolidator` (unroutable) |
| **skill truth** | paths and commands a `SKILL.md` mentions, checked for existence (`~/bin/mem`, `.config/nix/…`, `nr`, `alejandra`) | `release-consolidator` being a stale copy of `RELEASING.md` |
| **learnings hygiene** | every entry has symptom/cause/fix; `docs/learnings/README.md` index and files agree both ways | not yet |
| **archive health** | sessions/turns/messages, content vs on-disk bytes, growth against the 2 GB packing trigger, plus stores we do not own (osaurus 5 GB) | the 2.06x block overhead |
| **summary health** | count, decline rate, `source_digest` drift, `anchors_repaired > 0` | the one fabricated anchor |

### Not in v1: contradiction detection

The one real contradiction (a failed push being "a hand-off, not a retry loop"
while the archive said to diagnose and retry once) surfaced through the proposal
audit, not through a checker. A heuristic comparing "never" against "always"
would mostly produce false positives. Revisit once principles exist as files with
explicit `applies_when` scopes, where overlap becomes computable rather than
guessed.

## 4. Slices

**Slice 1** — ✅ built 2026-10-26: budget, skill inventory, skill truth. The
budget one is what enforces §2. Reports 0 failing and 0 warnings on the live tree
(3,511 / 4,000 tokens); 12 tests, most against a fixture so the logic is exercised
rather than today's state.

Two checks needed tuning before they were trustworthy. A skill that documents
where something *used to* live ("moved here from `~/.gitconfig`, which is gone")
is correct, not stale — lines with negation markers are skipped, after stripping
markdown emphasis, since "do **not** also link" broke the phrase match. And a path
on another machine, or a file the caller supplies (`--body-file ~/body.md`), is
not a dangling reference. Without both, the first run reported four false
positives out of four.

**Slice 2** — ✅ built 2026-10-26 as *freshness*: last ingest per harness, sessions
not yet summarized, summaries behind their session, and the learnings index. This
is the check that would have caught yesterday's data being served today — the
archive is only as true as its last ingest, and everything built on it degrades
silently as it ages.

It reported 2 unsummarised sessions and 1 drifted summary on the first run, which
is exactly the loop closing: doctor names the work, `mem summarize` does it.

Both are testable without network. The checks need `MEM_DOCS`-style overrides so
fixtures can stand in for the real tree, as `recall` already has.

## 5. Deferred, with reasons

| work | why not now |
|---|---|
| `verified_at` on skills | doctor's skill-truth check is a proxy; the honest version is a date per skill, re-checked by doctor. Do it once slice 1 shows the check is stable |
| weekly report | needs doctor to exist first; report only, never fixes |
| phase 6 behavioural evals | nothing currently claims behavioural change. Expensive (N≈5–10 per arm) and unproven need |
| packing | parked at the 2 GB trigger; archive is 340 MB, so ~5 years at current growth |
| Raven importer | deferred: its own plugin API makes integration a `memory_backend` plugin, not an importer. Three days of ACP frames from early October |
| semantic search | summaries now exist, so it is possible — but the benchmark shows lexical recall at rank 1 for 7 of 8 known items. The case is unproven |

## 6. Open questions

1. **Where do durable plans live?** Decided: `~/docs/plans/` (tracked, reaches
   sophrosyne, readable by every harness). `~/.opencode/plan` is harness scratch
   only — and its write guard is broken on this machine.
2. **Does doctor fix anything?** No. It reports. A `--fix` that deletes stray
   skills is a future argument, not a v1 feature.
3. **What runs the weekly pass?** Undecided. launchd would fit, but a report that
   nobody reads is worse than none, so the output needs a destination first (the
   curated repo, probably, as `reports/doctor-<date>.md`).
