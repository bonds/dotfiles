---
slug: daisydisk-pinned-overlay
status: awaiting-approval
intent: clear
pending-action: write .omo/plans/daisydisk-pinned-overlay.md
approach: Create a pinned binary overlay for daisydisk (like ollama/opencode/zen-browser/osxphotos) with a Sparkle-feed-based update script, wire into darwin overlays, add to nr --update loop.
---

# Draft: daisydisk-pinned-overlay

## Components (topology ledger)
<!-- Lock the SHAPE before depth. One row per top-level component that can succeed or fail independently. -->
<!-- id | outcome (one line) | status: active|deferred | evidence path -->

1. **daisydisk-overlay.nix** — overlay that overrides pkgs.daisydisk with a pinned binary fetch | active | this draft
2. **daisydisk-overlay/update.sh** — Sparkle-feed-based update script that bumps version + hash | active | this draft  
3. **lib/darwin-overlays.nix** — wire the new overlay into the darwin overlay list | active | this draft
4. **nr fish function** — add daisydisk update to the `--update` loop in `~/.config/fish/conf.d/15-functions.fish` | active | this draft
5. **Activation script** — disable DaisyDisk's built-in Sparkle auto-updater via `defaults write` in `hosts/accismus/configuration.nix` (same pattern as cmux at line 162-166) | active | this draft

## Open assumptions (announced defaults)
<!-- Record any default you adopt instead of asking, so the user can veto it at the gate. -->
<!-- assumption | adopted default | rationale | reversible? -->

1. Use `fetchurl` + manual `unzip` (not `fetchzip`) | Consistent with existing overlays (opencode, osxphotos) | Easily — both work, just a style choice
2. Store version as metadata string even though download URL is versionless | Provides metadata for tracing which version is deployed | Trivial
3. Update script lives alongside the overlay in `modules/daisydisk-overlay/update.sh` | Mirrors the bedrock-server pattern exactly | Yes — could be inlined in `nr` function instead

## Findings (cited - path:lines)

- **Current state**: `daisydisk` is in `hosts/accismus/configuration.nix:49` from nixpkgs-unstable (4.33.3). Latest upstream is 4.34.2.
- **Existing overlays pattern**: `modules/*-overlay.nix` using `stdenvNoCC.mkDerivation` + `fetchurl`, wired in `lib/darwin-overlays.nix:1-7`.
- **nr update mechanism**: `~/.config/fish/conf.d/15-functions.fish:61-67` loops over `ollama zen-browser opencode opencode-desktop` running `nix-update --use-github-releases`. Linux branch runs `bash pkgs/bedrock-server/update.sh`.
- **bedrock-server update script**: `pkgs/bedrock-server/update.sh` downloads zip, computes SRI hash via `nix hash file`, rewrites version+hash via `sed`.
- **DaisyDisk Sparkle feed**: `https://daisydiskapp.com/downloads/appcastFeed.php` — first `<item>` `<enclosure sparkle:version>` gives latest version (4.34.2). Download URL is `https://daisydiskapp.com/download/DaisyDisk.zip`.
- **Platform**: aarch64-darwin only (DaisyDisk is macOS-only).

## Decisions (with rationale)

1. **Pinned overlay** (not flake input) — consistent with ollama/opencode/osxphotos/zen-browser. The overlay pattern is well-established.
2. **Sparkle-feed update script** (not manual) — user explicitly requested automation. The script mirrors bedrock-server/update.sh in technique.
3. **Separate directory `modules/daisydisk-overlay/`** — the overlay .nix file and update.sh live together, same pattern as `pkgs/bedrock-server/`.
4. **Add to `nr --update` loop on darwin** — runs the update script alongside the `nix-update` calls for other packages.
5. **Disable Sparkle auto-updater via activation script** — use `system.activationScripts` with `defaults write` (same pattern as cmux at `configuration.nix:162-166`). Bundle ID: `com.daisydiskapp.DaisyDiskStandAlone`. Keys: `SUEnableAutomaticChecks=false`, `SUAutomaticallyUpdate=false`. This is the proven pattern for binary-only macOS apps in this repo — safer than patching Info.plist inside a Nix sandbox.

## Scope IN

- Create `modules/daisydisk-overlay/default.nix` (the overlay)
- Create `modules/daisydisk-overlay/update.sh` (update script)
- Add overlay to `lib/darwin-overlays.nix`
- Add daisydisk update to the `nr --update` loop in `~/.config/fish/conf.d/15-functions.fish`
- Add activation script in `hosts/accismus/configuration.nix` to disable DaisyDisk's built-in Sparkle auto-updater (same pattern as cmux at line 162-166)
- Run `alejandra` on modified nix files

## Scope OUT (Must NOT have)

- Do NOT modify the overlay to patch `Info.plist` — the activation script approach (like cmux) is the proven pattern for binary-only macOS apps
- Do NOT replace `daisydisk` with a flake input — overlays are the established pattern
- Do NOT replace `daisydisk` with a flake input — overlays are the established pattern
- Do NOT create a `pkgs/daisydisk/` directory — it's an overlay, not a package definition
- Do NOT create or modify any NixOS module — this is darwin-only

## Open questions

None — all forks resolved by user choice (Sparkle-feed update script) or established patterns.

## Approval gate
status: awaiting-approval
<!-- When exploration is exhausted and unknowns are answered, set status: awaiting-approval. -->
<!-- That durable record is the loop guard: on a later turn read it and resume at the gate instead of re-running exploration. -->
