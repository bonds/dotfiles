---
name: memory
description: "The shared memory system for every agent harness (pi, opencode, hermes, osaurus): one inbox at ~/.local/share/agents/memory/inbox.md, `mem` for capturing and recalling, ~/DECISIONS.md for settled choices, and <repo>/docs/learnings/ for domain facts. Use when something surprised you, a tool failed, the user corrected you or stated a rule, when asked to distill the inbox, or when deciding where a lesson belongs."
---

One store, four readers. The files are harness-neutral on purpose — pi, opencode,
hermes and osaurus all read and write the same ones — and `mem` is the neutral
interface so no harness needs its own copy of the logic.

| Store | What goes there | Write it with |
|---|---|---|
| `~/.local/share/agents/memory/inbox.md` | agent conduct: a tool failed, the user corrected you, a rule was stated | `mem inbox add <kind> "…"` (hooks do it for you) |
| `<repo>/docs/learnings/` | domain facts: a platform quirk, an API lifetime rule | `mem learn <slug> --title … --symptom … --cause … --fix …` |
| `~/DECISIONS.md` | settled choices and their rejected alternatives | edit `.config/nix/pkgs/pi/decisions.md`, then `nr` |
| `agent-skills/*/SKILL.md` | promoted rules, loaded on demand | edit the repo, then `nr` |

```bash
mem inbox add bash "rg -r is --replace, not recursive"   # a candidate
mem inbox show · mem distill                            # read / promote
mem learn nix-flock --title … --symptom … --cause … --fix …
mem recall "flock" --days 30 --source pi                # past sessions, all harnesses
mem decisions                                           # ~/DECISIONS.md
```

`mem recall` searches pi's JSONL sessions, opencode's SQLite and hermes' SQLite
in one query — use it before re-deriving something you may have already worked
out. `--source pi|opencode|hermes|all`, `--days`, `--limit`.

## Two kinds of lesson, two homes

| Lesson | Home | Trigger |
|---|---|---|
| Agent conduct ("never force-push", "doas needs full paths") | inbox → distill | a tool failed, or the user corrected you |
| Domain knowledge ("`openFile` also delivers argv") | `<repo>/docs/learnings/` | the world surprised you while working |

Getting this wrong is the common failure: a platform quirk filed in the inbox
gets promoted to a rule nobody needs in context, and a conduct rule filed in
`docs/learnings/` is never read again. When in doubt ask: *would a future
session need this in order to behave, or in order to know a fact?*

## The ladder

Capture is cheap and unconditional; promotion is where the work is. A candidate
is resolved only when it moves **up** a rung:

1. **`~/AGENTS.md` line** — always in context, costs tokens on every request.
   Only for what cannot be enforced. This file must not grow: moving a
   paragraph into a skill is part of the same edit.
2. **Skill** — guidance loaded only when its description routes to it. Anything
   longer than two sentences belongs here, not in AGENTS.md.
3. **Hook / extension** — deterministic, does not depend on the agent
   remembering: `.config/nix/pkgs/pi/extensions/*.ts` for pi, the opencode
   plugin, a hermes shell hook.
4. **Automation** — a nix module, a pre-commit hook, a step in `nr`.

Two rules of thumb: **seen twice → rung 3** (a repeating signature is a policy,
not a fact), and **AGENTS.md must not grow** (net-zero or smaller).

## Distilling

`mem distill` prints the inbox and the ladder. The procedure: read the inbox,
read `~/AGENTS.md`, `~/DECISIONS.md` and the skill descriptions so you do not
re-add what exists, cluster by *cause* rather than wording, pick a rung for each
cluster, present the plan as a table (signature → rung → file → change), apply
what was approved, then delete the processed lines (keep the header). Noise — a
transient network error, a typo fixed on the next call — is deleted with a note;
the inbox is a set of unresolved lessons, not a log.

After changing `~/AGENTS.md`, a skill description or `~/DECISIONS.md`, run
`~/.config/nix/pkgs/pi/evals/run.sh`: a failure means the wording got worse.

## Per-harness wiring

| Harness | Reads | Captures |
|---|---|---|
| pi | AGENTS.md + skills | `learnings-capture.ts`, `corrections-capture.ts` (both write the shared inbox) |
| opencode | AGENTS.md from the working directory upward, `instructions:` in `opencode.jsonc`, skills | `~/.config/opencode/plugins/memory-capture.js` |
| hermes | skills (`~/.hermes/skills/dotfiles/`); it does **not** read AGENTS.md — `SOUL.md` and `~/.hermes/memories/` are its own | shell hook in `~/.hermes/config.yaml` (`post_tool_call`) |
| osaurus | `~/AGENTS.md` | no hooks; a custom agent can run `mem` in its sandbox |

The hermes hook lives in hermes' own (untracked) config, so it is machine-local
and has to be re-added elsewhere:

```yaml
# ~/.hermes/config.yaml
hooks:
  post_tool_call:
    - command: ~/bin/hermes-memory-hook   # reads the payload on stdin, exits 0 always
      timeout: 5
```

It must be approved once (`~/.hermes/shell-hooks-allowlist.json`, or the TTY
prompt, or `--accept-hooks`); `hermes hooks list` shows `✓ allowed`, and
`hermes hooks test post_tool_call --payload-file <json>` fires it by hand.

Concurrency: the inbox is one file with several writers, so `mem` takes an
exclusive `flock` around every append. Write it through `mem`, not with `>>`.
Tests: `bash ~/bin/tests/mem-test.sh` (fixtures under /tmp; never touches the
real inbox), and `bash ~/bin/tests/capture-test.sh` for the three capture
heuristics — which lines are worth recording, and which messages count as a
correction.
