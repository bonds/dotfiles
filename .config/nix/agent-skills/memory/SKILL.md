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
mem recall "holds a file across processes" --mode hybrid  # vectors + keywords
mem index                                               # embed the archive (nightly too)
mem decisions                                           # ~/DECISIONS.md
```

`mem recall` searches pi's JSONL sessions, opencode's SQLite and hermes' SQLite
in one query — use it before re-deriving something you may have already worked
out. `--source pi|opencode|hermes|all`, `--days`, `--limit`, `--tokens`.

## Three guards on the write and read paths

- **Capture refuses credentials.** `inbox add` and `learn` run the same patterns
the archive redactor uses and exit 1 instead of storing a key. The store is plain
markdown in a public repo, so a lesson about a token describes the shape ("a
`ghp_` token"), not the token. `--allow-secret` is for patterns, never for keys.
- **`distill` flags what has been sitting there.** A candidate older than
`--stale-days` (default 30) prints `STALE`, and each one is scanned against
`AGENTS.md`, `DECISIONS.md` and the skills: `CONTRADICTS?` when the pair's
negation polarity differs, `COVERED?` when a rule already says it. Both are
prompts for a human, never a decision; `--no-check` skips the scan and `--json`
emits records.
- **`recall` has an output budget** (2000 tokens, `--tokens 0` to disable): the
answer lands in a model's context, so it reports how many hits it dropped rather
than silently printing 30k tokens of transcript.

## Semantic recall

`--mode keyword|semantic|hybrid` (default keyword). `semantic` embeds the query
and scans vectors; `hybrid` fuses both rankings (reciprocal rank fusion), which
is what to use when you have the vocabulary wrong — "the thing that holds a file
across processes" finds the `flock` session that never says "lock". Keyword
search requires **every** word, in the archive as well as the stores.

`--min-score` (default 0.55) is the cosine floor, and nothing more than 0.06
below the best hit survives it either, capped at 0.64 — bge-m3 compresses
similarity into 0.5-0.7, so a good query tops out near 0.65 and its junk tail
sits at 0.55-0.58, while a near-verbatim match can score 0.8 and must not drag
the floor past the 0.65 band. `--min-score 0` keeps everything.

`mem index` builds it: one row per archived turn plus one per curated doc, in
`~/.local/share/agents/index/semantic.db` — outside the archive's git repo,
because it is derived data and can always be rebuilt. Incremental (unchanged
text is skipped) and run by `mem nightly` after ingest (`--no-index` opts out).
It covers `--days` 90 by default (recall's own default is 30), skips messages
shorter than 60 characters because they embed close to every query, and keeps
vectors as int8: 22k units is 44 MB, a cold build is ~3 minutes at 4 jobs.

Embeddings: Deep Infra `BAAI/bge-m3` at $0.01/M tokens with the key pi already
uses, ~$0.07 for a cold build. Overrides —
`MEM_EMBED_CMD` (a command taking a JSON array of texts on stdin, for a local
model or the tests), `MEM_EMBED_MODEL`, `MEM_EMBED_URL`, `MEM_EMBED_KEY`,
`MEM_EMBED_KEY_FILE`, `MEM_INDEX_DIR`. With no embedder at all, `recall` falls
back to keyword and says so; the index is never required.

## The session brief

`mem brief [--cwd DIR] [--json]` prints what a session should know before its
first token: the repo's `docs/learnings` titles (newest eight, `N older` for the
rest), the inbox backlog with the age of its oldest candidate, and the freshness
of the nightly report and the index. `pi`'s `memory-brief.ts` runs it at
`session_start` and injects the text as a `<memory>` prompt section, so every
session starts knowing what this repo already learned and what is waiting to be
distilled.

Four properties make it safe to inject unconditionally, and each is a
constraint, not an accident:

- **Local and deterministic** — it reads four files and the index's `meta`
table, plus the distill rule scan. No network, no archive scan, no judgment.
Measured at ~120 ms, which is why it can run on every session start while a
semantic recall (1.3 s, and a network round-trip) cannot.
- **Budgeted** — capped at 1400 characters (254 tokens for this repo) and eight
entries. `mem doctor` prints its size in the budget section, and it is *not*
counted in the always-loaded total because it is repo-scoped.
- **A snapshot** — taken at session start and not refreshed mid-session, so a
capture during the session does not rewrite the system prompt.
- **Fail-open** — a missing `mem`, a non-zero exit, or a timeout means no
section, never a broken run. Outside a repo it says so instead of inventing
learnings; from `$HOME` it describes the dotfiles edit checkout, because the
bare repo has no `.git` there.

## Recall on demand, and the nudge

Two more `pi` extensions use `mem` at the moments a lesson is either useful or
being made. Both are gated, because recall costs a network round-trip and a
nudge costs attention:

- **`memory-recall.ts`** fires only for prompts that ask about the past ("how
  did we", "last time", "have we seen"). It starts `mem recall --mode semantic`
  at `input` and waits at most 1.6 s at `before_agent_start`, so the work
  overlaps prompt expansion; a miss injects nothing and the `recall` tool is
  still there. Hits arrive as an invisible custom message with `display: false`,
  the footer shows `recall N`, and the text says where each hit came from so it
  can be checked. `--mode semantic` rather than `hybrid`: hybrid adds the
  archive's keyword pass (2 s) for little gain when the phrasing is vague.
- **`learning-nudge.ts`** watches for the shape of a domain lesson: a tool call
  fails, then the *same tool* succeeds with *different* arguments within six
  calls, inside a git repository, with no `learning` call yet this session. It
  appends one invisible line at `turn_end` — never `continue: true`, so a nudge
  cannot cost a request — and never fires twice. A failure that fails again is
  not a pair: that false positive ("then succeeded" over a retry that also
  failed) was caught by a model before any test did, which is why the logic now
  has one.

`bun ~/.config/nix/pkgs/pi/extensions/tests/extensions-test.ts` covers both
against a fake `pi` (20 cases): the gating, the invisibility, the once-per-
session rule, and the shapes that must stay silent.

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

The audit runs on a cadence, and decides nothing: `mem nightly` adds a
`distill --summary` stage (`--no-distill` opts out) so the report always says how
many candidates are waiting, how many are stale, and how many look like they
contradict an existing rule. The same counts ride in the session brief and in
the pi footer badge (`inbox 28 · 5 clash`), so a growing backlog is visible
without anyone remembering to ask. Promotion stays a human step — the night job
reports, it never edits `AGENTS.md` or deletes a candidate.

After changing `~/AGENTS.md`, a skill description or `~/DECISIONS.md`, run
`~/.config/nix/pkgs/pi/evals/run.sh`: a failure means the wording got worse.

## Watching the loop itself

`mem nightly` runs from launchd at 04:10 (`modules/darwin-agents.nix`) and writes
one file per night under `~/.local/share/agents/memory/reports/`, named for the
date (`2026-11-21.md`). It exits 0 when only
`doctor` fails, on purpose — so the report's stage headings, not the exit code,
are the record. That is the failure mode this loop actually had: doctor failed
**20 of 26 nights** (always-loaded over budget, a skill out of step, a learnings
entry missing from the index) and nothing said so, because the report is a file
nobody reads.

Three readers now parse it:

- **The session brief** names a broken night job and the command that fixes it:
  `nightly: FAILED doctor (2026-11-21) — run `mem catchup``, or
  `nightly: 5d stale (...)`. A healthy report keeps the old, quiet line.
- **The footer badge** carries the short form from `mem brief --json`
  (`nightly.alarm` = `fail` or `5d`), decided in `bin/mem` so the threshold and
  its wording have one home. Healthy and empty inbox = no badge line at all.
- **`mem doctor` fails** when the newest report is older than `NIGHTLY_STALE_DAYS`
  (2), which turns a dead agent red in `nr` and the pre-push hook within three
  days. A failing stage inside a fresh report only warns: today's run has not
  happened yet, so failing on it would cascade one bad night into a red week.

`mem catchup [--harness X] [--no-index]` is the repair a session may run:
ingest + index + doctor, never `summarize` (money) and never `distill` (a human
decision). It writes no report — a repair is not a record. Nothing runs it
automatically: a session-start job would race the 04:10 launchd run, spend
minutes, and make the brief, which must stay read-only at ~120 ms, a writer.

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

Skills are written in this repo, never through hermes' `skill_manage` tool: it
refuses a description over **60 characters** (`SKILL_PROMPT_DESC_LIMIT`, in
`agent/skill_utils.py`) and truncates longer ones in its index, which destroys
the routing signal our descriptions exist for — and it only sees
profile-scoped skills, so a shared one is "not found in active profile".

Concurrency: the inbox is one file with several writers, so `mem` takes an
exclusive `flock` around every append. Write it through `mem`, not with `>>`.
Tests: `bash ~/bin/tests/mem-test.sh` (fixtures under /tmp; never touches the
real inbox), and `bash ~/bin/tests/capture-test.sh` for the three capture
heuristics — which lines are worth recording, and which messages count as a
correction.
