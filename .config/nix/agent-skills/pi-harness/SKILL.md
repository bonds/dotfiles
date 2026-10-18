---
name: pi-harness
description: "How this machine's pi coding agent is configured: the extensions (safety guards, cost reporting, learnings capture, session recall), the prompt templates (/review /ship /nr /learn /distill), models.json and Deep Infra pricing, mcp.json, settings.json merging, and the skills wiring for every harness. Use when editing pi config, adding an extension, skill or prompt, debugging a missing tool or wrong cost, or asking how pi learns from past sessions."
---

Everything is declared in `.config/nix/pkgs/pi/` and symlinked read-only into
`~/.pi/agent/` by `modules/home/pi.nix` (accismus only). So: **edit the repo,
then `nr`**. `pi install` / `pi mcp add` cannot persist — they write into
nix-store symlinks.

| Repo path | Lands at | Contents |
|---|---|---|
| `pkgs/pi/extensions/` | `~/.pi/agent/extensions` | the extensions below |
| `pkgs/pi/prompts/` | `~/.pi/agent/prompts` | `/review`, `/ship`, `/nr`, `/learn`, `/distill` |
| `pkgs/pi/keybindings.json` | `~/.pi/agent/keybindings.json` | `ctrl+shift+n` new, `+r` resume, `+t` tree |
| `pkgs/pi/decisions.md` | `~/DECISIONS.md` | settled choices and their rationale |
| `pkgs/pi/evals/` | not linked | routing evals, run from the repo |
| `agent-skills/` | per-skill symlinks | shared with every harness |

`settings.json` is the exception: pi writes it at runtime
(`lastChangelogVersion`), so `home.activation.piSettings` merges our keys with
`jq` instead of symlinking. Add new defaults there, never by hand.

## Extensions

| File | Does |
|---|---|
| `protected-paths.ts` | blocks `write`/`edit` to secrets, `.git`, `node_modules`, `~/.ssh`, agenix, `auth.json` |
| `permission-gate.ts` | confirms `rm -rf`, `sudo`/`doas`, force-push, disk ops, and any `nr`/`*-rebuild switch` |
| `git-checkpoint.ts` | `git stash create` per turn; offers restore on fork |
| `dirty-repo-guard.ts` | warns when edits land on a dirty tree |
| `reported-cost.ts` | replaces pi's list-price cost with Deep Infra's `usage.estimated_cost` |
| `model-prices.ts` | `/prices` (and `ctrl+shift+l`): picker with aligned billed in/out/cache columns; also appends `· billed $in/$out/$cache` to each `deepinfra` model name for `/model` |
| `notify.ts` | OSC 777 desktop notification on `agent_settled` |
| `custom-footer.ts` | `/footer` toggles branch + tokens + cost |
| `plan-mode/` | read-only `/plan` mode, `ctrl+alt+p` |
| `learnings-capture.ts` | appends tool failures to `~/.pi/agent/inbox.md` |
| `corrections-capture.ts` | appends user corrections and stated rules to the same inbox, with the action being corrected |
| `record-learning.ts` | `learning` tool: writes + indexes `<repo>/docs/learnings/` |
| `session-recall.ts` | `recall` tool: search past session JSONL |

Rules that keep these safe: no model calls, never throw into the run (wrap
file I/O in `try`), guard terminal-only behavior with `ctx.hasUI` /
`ctx.mode === "tui"`, and keep `tool_call` handlers fail-safe (a throwing
handler blocks the tool).

## Models and cost

`models.json` is generated (read-only symlink) and is the **only** price
source: `deepinfra` has no pi.dev catalog entry, and pi prices a request as
`tokens x model.cost`, ignoring whatever cost the provider reports. Five models
for the `ctrl+p` cycle: `DeepSeek-V4.1-Flash-1017` (default, vision, 1M) plus
`Qwen3.8-27B`, `Qwen3.8-Flash`, `GLM-5.3-Flash` and `MiMo-V2.6-Flash`. All are
vision-capable except `Qwen3.8-Flash` (text-only); GLM, Qwen3.8-Flash and MiMo
are 1M, Qwen3.8-27B is 256k. Model IDs and list prices come from
`curl api.deepinfra.com/v1/openai/models` → `metadata.pricing`.

Each model's `name` in `models.json` is a plain label — `DeepSeek V4.1 Flash 1017`,
no price. `model-prices.ts` appends `· billed $in/$out/$cache` at runtime, which
is what the built-in `/model` selector prints for the highlighted model
(`Model Name: <name>`; its rows are `id` + `[provider]` only). Prices are **billed,
not list**: list price is in `cost`, the discount is per model, and this file is
static, so a price written here would be wrong within a week.

`/prices` is the comparison view, because the built-in selector cannot show a
per-row column: it renders `item.id` and nothing else, and it cannot be replaced
— `app.model.select` is in `RESERVED_KEYBINDINGS_FOR_EXTENSION_CONFLICTS`, and a
command named `model` is skipped in favour of the built-in
(`getBuiltInCommandConflictDiagnostics`). The picker pins
`minPrimaryColumnWidth == maxPrimaryColumnWidth == 32` so every description
starts at column 34, which is what makes the price columns line up; a header
`Text` padded by that same amount sits above the list.

The billed numbers come from two sources: Deep Infra's catalogue
`metadata.discount` at `session_start` (one GET, key resolved through the
registry, so the `!command` → agenix path is reused), then per turn the measured
ratio `usage.estimated_cost ÷ pi's list-price total`, which outranks the
published number and corrects an expired promo. Nothing is shown until one of
them answers — no list price passed off as billed. Names are applied by
re-registering the provider (`pi.registerProvider`): the registry rebuilds its
snapshot from `models.json` on every refresh, so in-place mutation of a `Model`
is lost. Only `name` changes; every other field is copied from the live model.

The API key is not stored — it is a `!command` reading
`/run/agenix/hermes-deepinfra` at request time. `models.json` keeps list prices
because pi needs `cost` for its own math, and `reported-cost.ts` rewrites each
finished message's `usage.cost` from the provider's own `estimated_cost`
(rescaled across input/output/cache components); without it the footer and
`/session` overstate the bill — 2x on the 1017 (discount 0.51), 1.3x on Qwen,
~1.05x on MiMo. If Deep Infra stops reporting a cost, update `models.json`
instead of debugging the extension.

`mcp.json` declares `reel-summarize` → `http://sophrosyne.taileafac.ts.net:8892/sse`
(streamable HTTP; `/sse` is only a path). Tailscale only.

## Skills wiring

Canonical skills: `.config/nix/agent-skills/<name>/SKILL.md`. One symlink per
skill, per harness, so each harness keeps its own directory real:

| Harness | Directory |
|---|---|
| pi / Agent Skills standard | `~/.agents/skills/` (pi reads it natively — do **not** also link `~/.pi/agent/skills`, the duplicate makes every skill collide) |
| Claude Code | `~/.claude/skills/` |
| opencode | `~/.config/opencode/skills/` |
| Hermes | `~/.hermes/skills/dotfiles/` (category dir + `DESCRIPTION.md`) |

Adding a skill is just a new directory there, then `nr`. The `description` is
the router: state what it does **and** when to use it, in the words the user
actually types, and quote it (an unquoted `key: value` is invalid YAML and the
harness skips the skill silently). Keep it under 1024 characters.

## The learning loop

Two stores, because there are two kinds of lesson. Agent *conduct* goes to the
inbox and climbs the ladder; *domain knowledge* (a platform quirk, an API
lifetime rule) stays in the repo next to the code, indexed, and never climbs
anything.

1. **Capture** — `learnings-capture.ts` writes one line per distinct failure
   signature to `~/.pi/agent/inbox.md` (immediately for policy/permission
   failures, on the second occurrence otherwise); `corrections-capture.ts`
   writes one line per correction or stated rule, tagged `correction`/`policy`,
   quoting the sentence and recording what it was correcting ("no" after
   `git push` is the lesson; "no" alone is not). Neither makes a model call.
2. **Distill** — `/distill` clusters the inbox and promotes each item up the
   ladder: `AGENTS.md` line → skill → hook/extension → automation. Seen twice
   means rung 3; `AGENTS.md` must not grow.
3. **Verify** — `pkgs/pi/evals/run.sh` runs the `pi --print` cases in
   `cases.txt` (one per routing fact) and checks
   the context still routes to the right files (`MODEL=` and case-name filters
   supported; scratch dirs under `~/.cache/pi-evals` because context files only
   load from the cwd downward, so running from `/tmp` would test bare pi).
   `PI_EVAL_ARGS="--no-skills --skill $HOME/.config/nix/agent-skills"` tests the
   repo copies before a rebuild. Two traps already handled there: pi reads stdin
   in print mode (a case loop must redirect it from `/dev/null`), and macOS
   bash 3.2 cannot expand an empty array under `set -u`.
4. **Recall** — the `recall` tool searches session JSONL for earlier work on
   the same problem. Codemode exposure, so it costs nothing per request.

`learning` (tool) and `/learn` (prompt) handle domain knowledge: entry in
`<repo>/docs/learnings/YYYY-MM-DD-slug.md`, index line in its `README.md`,
README scaffolded on first use. The tool refuses outside a git repository, so a
lesson in `$HOME` correctly falls through to the inbox or `DECISIONS.md`.

## Testing without a rebuild

From `~`, point pi at the repo copies directly:

```fish
pi -e .config/nix/pkgs/pi/extensions/protected-paths.ts \
   --skill .config/nix/agent-skills \
   --prompt-template .config/nix/pkgs/pi/prompts
```

Or set `PI_CODING_AGENT_DIR` to a scratch directory. `nh darwin build .` from
`.config/nix` shows the `hm_*` files that a rebuild would install.
