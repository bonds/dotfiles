---
description: Distill the shared learnings inbox into durable changes
---

Read the `memory` skill first (`.config/nix/agent-skills/memory/SKILL.md`) — it
holds the promotion ladder and the two-kinds-of-lesson rule. Then run
`mem distill` to print the inbox at `~/.local/share/agents/memory/inbox.md` together with
that ladder.

Work the candidates in that inbox:

1. Cluster them by cause, not by wording — three commands that failed for the
   same missing tool are one cluster.
2. Read `~/AGENTS.md`, `~/DECISIONS.md` and the skill descriptions under
   `.config/nix/agent-skills/*/SKILL.md` so you do not re-add what already
   exists. Use `mem recall "<distinctive word>"` when a line is too terse to act
   on; the session id in the line narrows it.
3. Pick a rung per cluster and write the change: an `~/AGENTS.md` line (rare,
   and it must not grow — move a paragraph into a skill in the same edit), a
   skill, a hook/extension (pi extension, this plugin, a hermes shell hook), or
   automation.
4. Domain knowledge is not a ladder item: move it to that repo's
   `docs/learnings/` with `mem learn` and delete the line.
5. Present the plan as a table — signature(s) → rung → file → exact change — and
   ask once before applying.
6. Delete the processed lines from the inbox (keep the header). Delete noise
   (transient network errors, typos fixed on the next call) with a note.

Anything you change under `.config/nix/` needs `nr` before it takes effect
(skills and extensions are nix-store symlinks); never run the activating rebuild
yourself.
