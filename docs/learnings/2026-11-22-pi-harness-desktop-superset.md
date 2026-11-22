# Pi-Harness is a well-built Electron workbench around the pi SDK, and it will fight a nix-managed `~/.pi/agent`

**Date:** 2026-11-22 — research note, not a bug. Written so the next "should I try
pi-harness?" does not repeat ten GitHub API calls.

## Symptom

Asked for an opinion on <https://github.com/wangmiaozero/pi-harness>, which bills
itself as "the operational superset of Pi Coding Agent". The question recurs
because the README sells breadth (runs, trace, replay, evaluation, checkpoints,
agent teams, plus an editor, git UI, desktop pet and realtime voice) and the
answer is not visible from the feature list.

## Snapshot at v2.4.17 (2026-11-22)

| Fact | Value |
|---|---|
| License | `AGPL-3.0-only` (SPDX, in `LICENSE` and `package.json`) |
| Stack | Electron + Vue 3 + Pinia, TypeScript, `electron-vite` |
| Repo | created 2026-08-20, 341★, 29 forks, 379 commits — **376 by wangmiaozero** |
| Cadence | several releases a day (`v2.4.13`→`v2.4.17` inside three days) |
| Pi coupling | **not a fork**: depends on `@earendil-works/pi-coding-agent`, `-agent-core`, `-ai`, `-tui` all pinned `1.5.2` |

The "superset" claim is honest. Pi still owns the agent loop, sessions, tools,
context and compaction; the app adds a control plane *around* it. The real delta
is observability (runs / trace / replay / run-compare / evaluation), recovery
(checkpoints, resume/fork/retry, tool policy, per-run budget) and multi-agent
(task DAG, handoff, review gates, worktree isolation). Everything else — file
editor, git UI, MCP marketplace, cross-harness conversation history, architecture
maps, realtime voice, a desktop pet with 193 actions — is IDE-ish breadth, and a
lot of it for one maintainer.

## Engineering quality is above average for this genre

- `.github/workflows/ci.yml` pins every action by SHA, pins node `24.22.1` /
  pnpm `9.12.1`, and runs `security:node`, `typecheck`, `lint`, vitest with
  `PI_HARNESS_REQUIRE_RUNTIME_TESTS=1`, `pnpm audit --audit-level high`, a license
  list, `compile`, then Electron E2E.
- `src/main/runtime/catalog.json` pins the pi `1.5.2` release tarballs by
  `sha256` **plus per-file content hashes** (`signedFileContentSha256`), with
  license notices — the same discipline as a nix `fetchurl` with a hash.
- The repo's own `AGENTS.md` enforces the right rules: `contextIsolation: true`,
  `nodeIntegration: false`, typed + runtime-validated IPC, `spawn`/`execFile`
  with argument arrays (never shell-string interpolation), secrets never returned
  to the renderer, CI-gated tags, no tag moving.
- The plugin docs say plainly that executable Harness Plugins are **not
  sandboxed**.

## Where it collides with this machine

`src/main/services/app-paths.ts` defaults the pi config dir to `~/.pi/agent`
(override: `PI_HARNESS_PI_CONFIG_DIR`, legacy `PI_SWITCH_PI_CONFIG_DIR`) and
scans skills from `~/.pi/agent/skills` and `~/.agents/skills`. But:

- `config-service.ts` **replaces** `settings.json` / `models.json` (there is a
  raw-editor path), it does not merge. Here `settings.json` is `jq`-merged at
  activation by `modules/home/pi.nix`, and extensions/prompts/keybindings/skills
  are read-only nix store symlinks — a write either hits EROFS or is clobbered by
  the next `nr`.
- `install-service.ts` manages pi itself via `npm view` / `npm install -g`. Here
  pi is a nix package; the app's bundled runtime is pi `1.5.2` against the nix
  `1.6.0`, so a session/config written by one is read by the other.
- Its harness state (`harness-runs.json`, `harness-traces.json`,
  `harness-checkpoints.json`, `secrets.bin`, …) lives in Electron `userData`, so
  the observability is parallel state the terminal `pi` never sees.

## Risks worth naming

1. **Bus factor**: one author, three months old, near-daily releases.
2. **Distribution**: the macOS `.dmg` is ad-hoc signed and not notarized, the
   Windows installer is unsigned. Both need a Gatekeeper/SmartScreen bypass for
   an app that spawns agents with your credentials. `SHA256SUMS` is published but
   only proves consistency with the list.
3. **Monetisation smell**: the sponsor slots are affiliate links to API resellers
   (`infistar.cc`, `tokenarmy.shop` — "Claude Pro 日租 · 不封号"), and the "Free
   Models" path routes prompts through an anonymous relay at
   `https://ai-gateway.kilo.ai/api/v1` (`src/main/services/free-models/ofm/`),
   gated behind a privacy notice.
4. **AGPL-3.0-only**: fine to run locally; copyleft the moment you fork,
   redistribute, or serve it over a network.

## Fix / takeaway

Verdict: legitimate and carefully engineered, but it is a GUI product with a
vendor-ish agenda, and it does not fit a nix-managed terminal workflow. If it is
ever revisited:

- Try it read-only: verify `SHA256SUMS`, and point `PI_HARNESS_PI_CONFIG_DIR` at
  a scratch directory rather than `~/.pi/agent` — `~/.agents/skills` is still
  scanned, so the real skills stay visible.
- Do not let it install or update pi, and do not use its raw settings editor.
- The parts worth stealing are **checkpoints**, **run trace** and
  **worktree-isolated agent teams** — those are extensions we could write against
  the pi SDK directly, in the same way `pkgs/pi/extensions/` already works.

Re-check before acting on any of this: the repo is three months old and moves
daily, so the version table above goes stale fastest.
