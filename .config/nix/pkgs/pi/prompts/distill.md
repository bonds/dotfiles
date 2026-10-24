---
description: Turn inbox failures into skills, hooks or AGENTS.md lines
argument-hint: "[focus]"
---
Distill the learnings inbox into durable changes. Focus (optional): ${1:-everything}.

The inbox is `~/.agents/memory/inbox.md` — one inbox shared by every harness:
pi (`learnings-capture.ts` / `corrections-capture.ts`), the opencode and hermes
hooks, and anything that ran `mem inbox add`. Read it with `mem inbox show`
(`mem distill` prints it together with the ladder). Each line is one distinct
item from one session. Your job is to move each one up the ladder so it cannot
recur.

Correction lines carry what they were correcting (`"no, use config push" —
after \`bash\` \`git push\``): that pairing is the lesson, and a bare "no" is
not. Domain knowledge (a platform quirk, an API lifetime rule) is **not** a
ladder item — it belongs in the repo's `docs/learnings/` via `mem learn` (or the
`learning` tool, or `/learn`), so move it there and delete the line.

## The ladder

Every lesson has a natural rung. Promoting past the current rung is the whole
point; adding another paragraph is the failure mode.

1. **`~/AGENTS.md` line** — a rule or fact, obeyed most of the time, costs
   tokens on every request. Only for things that cannot be enforced.
2. **Skill** (`.config/nix/agent-skills/<name>/SKILL.md`) — detailed guidance
   loaded only when its description routes to it. The right home for anything
   longer than two sentences.
3. **Hook / extension** (`.config/nix/pkgs/pi/extensions/*.ts`) — deterministic.
   Use it whenever the lesson is "don't do X" or "always do Y": if the fix is
   enforceable in code, prose is the wrong answer.
4. **Automation** (nix module, pre-commit hook, `nr` step) — it just happens.

Two rules of thumb:

- **Seen twice → rung 3.** A signature that repeats is a policy, not a fact.
- **AGENTS.md must not grow.** If a line belongs there, look for a line to
  move into a skill in the same edit. Net-zero or smaller.

## Procedure

1. Read the inbox. If it is missing or empty, say so and stop.
2. Read `~/AGENTS.md`, `~/DECISIONS.md`, and the skill descriptions in
   `.config/nix/agent-skills/*/SKILL.md` so you do not re-add what already
   exists. Use the `recall` tool with a distinctive word from each signature
   when the inbox line is too terse to act on — the session id in the line
   narrows the search.
3. Cluster the lines by cause, not by wording: three different commands that
   all failed because a tool is not installed are one cluster.
4. For each cluster, pick the rung and write the change. Concretely:
   - rung 1: a single bullet in `~/AGENTS.md` under the right section
   - rung 2: a new or existing skill; a new skill needs `name` + quoted
     `description` (what it does **and** when to use it, with the words the
     user actually types) and appears in every harness after `nr`
   - rung 3: an extension modeled on `learnings-capture.ts` — small, no model
     calls, guarded so a bug in it cannot break a run
   - rung 4: say what the automation would be and stop; do not build it
     unasked
5. Present the plan as a table: signature(s) → rung → file → the exact change.
   Ask once for approval, then apply everything approved in one pass.
6. Delete the processed lines from the inbox, keeping the header. If a line is
   noise (a transient network error, a typo the agent fixed in the next call),
   delete it and say so — an inbox of unresolved lessons is the point, not a
   log.
7. If you changed a skill description, `~/AGENTS.md`, or `~/DECISIONS.md`, run
   the routing evals: `~/.config/nix/pkgs/pi/evals/run.sh`. Report the
   pass/fail delta; a regression means the wording got worse, so fix the
   wording, not the case.
8. If you changed anything under `.config/nix/`, remind the user to run `nr`
   (extensions and skills are nix-store symlinks; nothing takes effect until
   then). Never run the activating rebuild yourself.
