---
description: Record a surprising finding in the repo's docs/learnings
argument-hint: "[topic]"
---
We just hit something non-obvious (topic: ${1:-unspecified}). Write it up so it
is not rediscovered.

Create `docs/learnings/<short-kebab-title>.md` in the current repo, or add to
the existing entry if one already covers it. Keep it to three short sections:

- **Symptom** — what was observed, including the exact error text.
- **Cause** — the underlying behavior (platform quirk, API change, undefined
  behavior, wrong assumption).
- **Fix / takeaway** — what to do next time, with the command or code that
  works.

Then add one line to `docs/learnings/README.md` (create it with a
`## Entries` heading if missing) linking the new file with a one-sentence
summary. If the repo has no `docs/learnings/`, say so and ask before creating
the directory.
