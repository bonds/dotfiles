---
description: Record a non-obvious discovery in docs/learnings
argument-hint: "[topic]"
---
We just hit something non-obvious (topic: ${1:-unspecified}). Record it so it
is not rediscovered.

This is **domain knowledge** — a platform quirk, an API lifetime rule, an
undefined-behavior trap. Agent-behaviour lessons ("never force-push") belong in
`~/.agents/memory/inbox.md` for `/distill`, not here.

1. If the repo has no `docs/learnings/`, create it with a `README.md` that has
   an `## Entries` heading and the symptom / cause / fix template — copy the
   shape from `~/src/bonds/polyptych/docs/learnings/README.md`.
2. Write `docs/learnings/<YYYY-MM-DD>-<short-kebab-title>.md`, using today's
   date from `date +%Y-%m-%d`. Three sections, kept short and concrete:
   - **Symptom** — what was observed, including the exact error text or the
     wrong behaviour.
   - **Cause** — the underlying reason.
   - **Fix / takeaway** — the command or code that works next time.
3. Add one line under `## Entries` in `docs/learnings/README.md`, linking the
   file with a short title.
4. If the repo's own `AGENTS.md` does not mention `docs/learnings/`, add a
   two-line `## Learnings` section pointing at it. That local echo is what
   makes the practice survive: the rule has lived in `~/AGENTS.md` for a while
   and was followed in exactly the one repo that repeated it locally.

Prefer `mem learn <slug> --title … --symptom … --cause … --fix …` — one call,
works from any harness, and it does steps 1–3 (including the index line). In pi,
the `learning` tool does the same thing. Leave the result uncommitted for the
normal review flow.
