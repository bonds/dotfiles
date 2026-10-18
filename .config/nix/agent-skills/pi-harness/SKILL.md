---
name: pi-harness
description: "How this machine's pi coding agent is configured: the extensions (protected-paths, permission-gate, git-checkpoint, dirty-repo-guard, reported-cost, notify, footer, plan-mode, learnings-capture, session-recall), the prompt templates (/review /ship /nr /learn /distill), models.json and Deep Infra pricing, mcp.json, settings.json merging, and the skills wiring for every harness. Use when editing pi config, adding an extension, skill or prompt, debugging a missing tool or wrong cost, or asking how pi learns from past sessions."
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
| `notify.ts` | OSC 777 desktop notification on `agent_settled` |
| `custom-footer.ts` | `/footer` toggles branch + tokens + cost |
| `plan-mode/` | read-only `/plan` mode, `ctrl+alt+p` |
| `learnings-capture.ts` | appends tool failures to `~/.pi/agent/inbox.md` |
| `session-recall.ts` | `recall` tool: search past session JSONL |

Rules that keep these safe: no model calls, never throw into the run (wrap
file I/O in `try`), guard terminal-only behavior with `ctx.hasUI` /
`ctx.mode === "tui"`, and keep `tool_call` handlers fail-safe (a throwing
handler blocks the tool).

## Models and cost

`models.json` is generated (read-only symlink) and is the **only** price
source: `deepinfra` has no pi.dev catalog entry, and pi prices a request as
`tokens x model.cost`, ignoring whatever cost the provider reports. Two models
for the `ctrl+p` cycle: `DeepSeek-V4.1-Flash-1017` (default, vision) and
`DeepSeek-V4-Flash` (cheap, text-only).

Prices there are Deep Infra's **list** prices. The API key is not stored — it is
a `!command` reading `/run/agenix/hermes-deepinfra` at request time. This model
carries a discount, so `reported-cost.ts` rewrites each finished message's
`usage.cost` from the provider's own `estimated_cost` (rescaled across
input/output/cache components); without it the footer and `/session` overstate
the bill roughly 2x. If Deep Infra stops reporting a cost, update `models.json`
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

1. **Capture** — `learnings-capture.ts` writes one line per distinct failure
   signature to `~/.pi/agent/inbox.md` (immediately for policy/permission
   failures, on the second occurrence otherwise). No model calls.
2. **Distill** — `/distill` clusters the inbox and promotes each item up the
   ladder: `AGENTS.md` line → skill → hook/extension → automation. Seen twice
   means rung 3; `AGENTS.md` must not grow.
3. **Verify** — `pkgs/pi/evals/run.sh` runs 13 `pi --print` cases that check
   the context still routes to the right files (`MODEL=` and case-name filters
   supported; scratch dirs under `~/.cache/pi-evals` because context files only
   load from the cwd downward, so running from `/tmp` would test bare pi).
   `PI_EVAL_ARGS="--no-skills --skill $HOME/.config/nix/agent-skills"` tests the
   repo copies before a rebuild. Two traps already handled there: pi reads stdin
   in print mode (a case loop must redirect it from `/dev/null`), and macOS
   bash 3.2 cannot expand an empty array under `set -u`.
4. **Recall** — the `recall` tool searches session JSONL for earlier work on
   the same problem. Codemode exposure, so it costs nothing per request.

`/learn` is the manual sibling of capture: it writes `docs/learnings/` in a
repo for a lesson that has no failed tool call behind it.

## Testing without a rebuild

From `~`, point pi at the repo copies directly:

```fish
pi -e .config/nix/pkgs/pi/extensions/protected-paths.ts \
   --skill .config/nix/agent-skills \
   --prompt-template .config/nix/pkgs/pi/prompts
```

Or set `PI_CODING_AGENT_DIR` to a scratch directory. `nh darwin build .` from
`.config/nix` shows the `hm_*` files that a rebuild would install.
