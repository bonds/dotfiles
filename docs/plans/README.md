# Plans

Design documents for changes that are too large to hold in a commit message and
too expensive to re-derive. A plan states what will be built, the decisions
already settled (with the alternatives that were rejected and why), and the
order to build it in — so that a later session can resume without re-litigating
the design.

This is deliberately *not* the same as:

- **`docs/learnings/`** — facts about the world, learned by being surprised.
  A plan is a proposal; a learning is a finding.
- **`~/DECISIONS.md`** — the settled *why* behind a choice that is already in
  effect. A plan's decisions get lifted there once the plan is built.
- **`~/.local/share/agents/memory/inbox.md`** — agent conduct rules awaiting promotion.

## Conventions

- One file per plan: `docs/plans/YYYY-MM-DD-short-slug.md`.
- A header block with **Status** (`proposed` / `in progress` / `complete` /
  `abandoned`), the date it last moved, and which phases are done.
- Decisions get IDs (D1, D2, …) with the rejected alternative recorded next to
  each. A decision without its rejected alternative is not a decision, it is a
  preference.
- Phases are ordered so each one is independently useful and revertable, and
  each names the test that fails before it exists.
- Update the status line when a phase lands. A stale status is worse than no
  plan, because it makes the next reader trust the wrong parts.
- Supersede rather than delete. An abandoned plan is the record of why an
  approach was not worth it.

## Index

- [2026-10-25 — Agent memory pipeline](2026-10-25-agent-memory-pipeline.md) —
  wire capture via a local proxy, summaries, principles with evidence anchors,
  and the Osaurus Working Folder split. Phase 0 (the passthrough) is built;
  phases 1–6 are proposed.
