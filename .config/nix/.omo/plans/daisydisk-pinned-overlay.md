# daisydisk-pinned-overlay - Work Plan

## TL;DR (For humans)
<!-- Fill this LAST, after the detailed plan below is written, so it summarizes the REAL plan. -->
<!-- Plain English for a non-engineer: NO file paths, NO todo numbers, NO wave/agent/tool names. -->

**What you'll get:** DaisyDisk will be pinned to the latest version through a Nix overlay (same pattern as ollama/opencode/zen-browser). Running `nr --update` will automatically check for and apply new DaisyDisk versions alongside the other pinned packages. DaisyDisk's own Sparkle auto-updater will be disabled (no more nag prompts) — `nr --update` is the only update path.

**Why this approach:** nixpkgs-unstable lags behind upstream DaisyDisk releases. A pinned binary overlay with a Sparkle-feed update script mirrors the exact same pattern used for the other "cutting edge" packages — consistent update workflow.

**What it will NOT do:** Won't change how DaisyDisk is installed or listed in your system packages (it's already in `configuration.nix`). Won't modify NixOS configs (darwin-only).

**Effort:** Short
**Risk:** Low - follows established pattern exactly

**Decisions to sanity-check:** None — all decisions follow established patterns or the user's explicit choice (Sparkle-feed update script).

Your next move: approve and start work. Full execution detail follows below.

---

> TL;DR (machine): Short effort, Low risk — pin daisydisk via darwin overlay with Sparkle-feed update script wired into `nr --update`.

## Scope
### Must have
- `modules/daisydisk-overlay/default.nix` — pinned overlay for DaisyDisk (aarch64-darwin)
- `modules/daisydisk-overlay/update.sh` — Sparkle-feed-based version+hash update script
- `lib/darwin-overlays.nix` — add `(import ../modules/daisydisk-overlay/default.nix)` to the list
- `~/.config/fish/conf.d/15-functions.fish` — add daisydisk update to the darwin `--update` loop
- `alejandra` formatting on all modified .nix files

### Must NOT have (guardrails, anti-slop, scope boundaries)
- No changes to `hosts/accismus/configuration.nix`
- No changes to NixOS configs
- No flake input additions
- No additional packages or system modifications beyond the overlay

## Verification strategy
> Zero human intervention - all verification is agent-executed.
- Test decision: tests-after — verify the overlay evaluates, the update script runs, and `nr --update` invokes it
- Evidence: .omo/evidence/task-1-daisydisk-pinned-overlay (overlay eval check), .omo/evidence/task-2-daisydisk-pinned-overlay (update script dry-run)

## Execution strategy
### Parallel execution waves
Wave 1: Create overlay + update script (can be done in parallel — the overlay and script are independent)
Wave 2: Wire into darwin-overlays + nr function + format (depends on Wave 1)

### Dependency matrix
| Todo | Depends on | Blocks | Can parallelize with |
| --- | --- | --- | --- |
| 1. Create overlay | — | 3, 5 | 2 |
| 2. Create update script | — | 4 | 1 |
| 3. Wire darwin-overlays | 1 | — | 4 |
| 4. Wire nr function | 2 | — | 3 |
| 5. Add activation script | 1 | — | 3, 4 |

## Todos
> Implementation + Test = ONE todo. Never separate.
<!-- APPEND TASK BATCHES BELOW THIS LINE WITH edit/apply_patch - never rewrite the headers above. -->
- [ ] 1. Create `modules/daisydisk-overlay/default.nix`
  What to do / Must NOT do: Write a `stdenvNoCC.mkDerivation` overlay that overrides `pkgs.daisydisk` (same pattern as `modules/opencode-overlay.nix`). Fetch `DaisyDisk.zip` from `https://daisydiskapp.com/download/DaisyDisk.zip`, unzip, install `DaisyDisk.app` to `$out/Applications/`. Pin version to `4.34.2` and hash to current SRI. Set `dontFixup = true`, `platforms = ["aarch64-darwin"]`, `license = unfree`.
  Must NOT: Do NOT use `fetchzip` (inconsistent with repo pattern). Do NOT package as a flake package — it's an overlay entry.
  Parallelization: Wave 1 | Blocked by: — | Blocks: 3
  References: `modules/opencode-overlay.nix:1-62` (pattern ref), nixpkgs `pkgs/by-name/da/daisydisk/package.nix` (source-of-truth for fetch approach)
  Acceptance criteria: `nix eval --file modules/daisydisk-overlay/default.nix` produces a valid overlay; `nix build nixpkgs#daisydisk` with the overlay applied resolves to version 4.34.2
  QA scenarios: happy — overlay evaluates without error; failure — wrong hash causes expected hash mismatch
  Commit: Y | `feat(daisydisk): add pinned binary overlay with Sparkle update script`

- [ ] 2. Create `modules/daisydisk-overlay/update.sh`
  What to do / Must NOT do: Write a bash script (same pattern as `pkgs/bedrock-server/update.sh`). Fetch the Sparkle feed at `https://daisydiskapp.com/downloads/appcastFeed.php`, parse the first `<item>`'s `<enclosure sparkle:version>` via `xmlstarlet` to get version, download `DaisyDisk.zip` from `https://daisydiskapp.com/download/DaisyDisk.zip`, compute SRI hash via `nix hash file --type sha256`, rewrite `default.nix` version and hash using `sed`. Must be idempotent (safe to re-run).
  Must NOT: Do NOT commit/push in the script. Do NOT download if already at latest version (optimization — nice-to-have but not required).
  Parallelization: Wave 1 | Blocked by: — | Blocks: 4
  References: `pkgs/bedrock-server/update.sh:1-27` (pattern ref), DaisyDisk Sparkle feed `https://daisydiskapp.com/downloads/appcastFeed.php`
  Acceptance criteria: Running `bash modules/daisydisk-overlay/update.sh` downloads the zip, computes hash, and rewrites version+hash in `default.nix` without errors
  QA scenarios: happy — script runs, updates version/hash; failure — feed unreachable produces clear error; idempotent — second run produces same version/hash
  Commit: Y | (same commit as todo 1 — they ship together)

- [ ] 3. Disable DaisyDisk's built-in Sparkle auto-updater via activation script
  What to do / Must NOT do: Add an activation script block in `hosts/accismus/configuration.nix` that disables Sparkle auto-updates — exact same pattern as the cmux block at line 162-166. Use `system.activationScripts.disableDaisyDiskSparkle.text` with `sudo -u scott defaults write com.daisydiskapp.DaisyDiskStandAlone SUEnableAutomaticChecks -bool false` and `SUAutomaticallyUpdate -bool false`. Add `2>/dev/null || true` so it doesn't fail on first install when the domain doesn't exist yet.
  Must NOT: Do NOT patch Info.plist in the overlay's installPhase. Do NOT remove/replace Sparkle.framework from the .app bundle. The activation script pattern (proven by cmux) is the right approach for binary-only macOS apps.
  Parallelization: Wave 2 | Blocked by: 1 | Blocks: —
  References: `hosts/accismus/configuration.nix:162-166` (cmux Sparkle disable pattern), bundle ID `com.daisydiskapp.DaisyDiskStandAlone` (confirmed via installed app Info.plist and Homebrew cask)
  Acceptance criteria: After `darwin-rebuild switch`, `defaults read com.daisydiskapp.DaisyDiskStandAlone SUEnableAutomaticChecks` returns `0` and `SUAutomaticallyUpdate` returns `0`; DaisyDisk no longer shows update prompts
  QA scenarios: happy — defaults written correctly; idempotent — re-running activation script is a no-op; failure — domain not found silently ignored
  Commit: Y | (same commit)

- [ ] 4. Wire overlay into `lib/darwin-overlays.nix`
  What to do / Must NOT do: Add `(import ../modules/daisydisk-overlay/default.nix)` to the overlay list in `lib/darwin-overlays.nix`. Must be appended after the existing overlays.
  Parallelization: Wave 2 | Blocked by: 1 | Blocks: —
  References: `lib/darwin-overlays.nix:1-7`
  Acceptance criteria: `lib/darwin-overlays.nix` contains the daisydisk import; overlay evaluates in context of the full darwin overlay stack
  QA scenarios: happy — `nix eval` on the darwin overlays resolves `pkgs.daisydisk` to the overlay version
  Commit: Y | (same commit)

- [ ] 5. Add daisydisk update to `nr --update` loop in fish config
  What to do / Must NOT do: In `~/.config/fish/conf.d/15-functions.fish`, add a block in the darwin `--update` section (after the `nix-update` loop, before `alejandra`) that runs `bash $HOME/.config/nix/modules/daisydisk-overlay/update.sh`. Pattern: same structure as the Linux branch that runs `pkgs/bedrock-server/update.sh`.
  Must NOT: Do NOT add `daisydisk` to the `nix-update --use-github-releases` loop (it doesn't have GitHub releases). Do NOT modify the Linux branch.
  Parallelization: Wave 2 | Blocked by: 2 | Blocks: —
  References: `~/.config/fish/conf.d/15-functions.fish:56-76` (darwin update loop), `:73-75` (Linux bedrock-server update pattern)
  Acceptance criteria: Running `nr --update` (darwin) triggers `modules/daisydisk-overlay/update.sh` after the `nix-update` calls and before `alejandra`
  QA scenarios: happy — update script runs in sequence; failure — script error doesn't prevent alejandra formatting
  Commit: Y | (same commit)

- [ ] 6. Format and verify
  What to do / Must NOT do: Run `alejandra modules/daisydisk-overlay/default.nix lib/darwin-overlays.nix` to format all modified nix files. Verify `nix flake check` passes (or at minimum the overlay evaluates). Then commit all changes to the bare repo via `config add` and `config commit`.
  Parallelization: Wave 3 (final) | Blocked by: 3, 4 | Blocks: —
  References: AGENTS.md (commit/push conventions)
  Acceptance criteria: `alejandra` produces no changes on already-formatted files; `config status` shows only expected files
  QA scenarios: happy — commit succeeds, `nix flake check` passes
  Commit: Y | (same commit — this is the finalize step)

## Final verification wave
> Runs in parallel after ALL todos. ALL must APPROVE. Surface results and wait for the user's explicit okay before declaring complete.
- [ ] F1. Plan compliance audit
- [ ] F2. Code quality review
- [ ] F3. Real manual QA
- [ ] F4. Scope fidelity

## Commit strategy
Single commit with message: `feat(daisydisk): add pinned binary overlay with Sparkle update script`

Files to stage:
- `modules/daisydisk-overlay/default.nix` (new)
- `modules/daisydisk-overlay/update.sh` (new)
- `lib/darwin-overlays.nix` (modified)
- `~/.config/fish/conf.d/15-functions.fish` (modified)
- `hosts/accismus/configuration.nix` (modified)

## Success criteria
- `nr --update` on accismus fetches the latest daisydisk version alongside ollama/opencode/zen-browser
- `pkgs.daisydisk` in `configuration.nix` resolves to the overlay version (latest instead of nixpkgs-lagging)
- The overlay + update script follow the exact same patterns as the other pinned packages
- DaisyDisk's built-in Sparkle auto-updater is disabled — no update prompts, no background checks. The `nr --update` loop is the only update path
