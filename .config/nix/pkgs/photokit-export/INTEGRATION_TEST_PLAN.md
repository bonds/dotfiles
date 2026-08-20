# Integration test plan — photo-export smoke test

Status: **planned, not implemented** (created 2026-08-20; consider after
0.2.5 settles and/or before/after the sophrosyne live acceptance run).

## Why

Our 39 unit tests cover only `photoexport_core.swift` (pure logic: config,
guard, UTI map, manifest, date-dir, basename) via `nix flake check`. The
**actual export pipeline** — auth → enumerate → download iCloud-optimized
original → atomic `.part`+rename write → `.xmp` sidecar → manifest append —
is only verified by hand (Spotlight launches). This session it broke in four
different ways (dismount abort, config dest not read, `open --args` not
forwarded, 139GB silent-local-writes). A repeatable smoke test would catch
those regressions reliably.

## What it proves

End-to-end export to a **local** scratch dir:
- PhotoKit auth resolves (first run needs a one-time "Allow" click — TCC gate)
- Asset enumeration works (from the real Photos library)
- iCloud-optimized original download returns data
- Atomic write `.part` → final rename leaves no `.part` leftovers
- `.xmp` sidecar is written next to each file
- Manifest records exactly the expected UUIDs

## What it does NOT prove (explicitly out of scope)

- The **SMB mount** + "files land on `/dragon/media/photos`" — requires a
  live sophrosyne; stays a separate one-time manual acceptance. Cannot be
  faked with a local dir.
- TCC grant itself — human Allow click is unavoidable and out of our control.

## Design

- New script: `bin/photo-export-smoke-test` (bash, ~30 lines).
- Config plumbing already supports it: the app reads `dest` + `limit` from
  `~/Library/Application Support/photo-export/config.toml` (that's why we
  built the config file).
- Flow:
  1. Save current config, write temp config: `dest=/tmp/photo-export-smoke`,
     `limit=5`.
  2. Launch via `open ~/Applications/Home Manager Apps/photo-export.app`
     (so TCC identity applies; first run prompts Allow).
  3. `open -W` block until exit.
  4. Assert:
     - exactly 5 photo files in `/tmp/photo-export-smoke/**`
     - exactly 5 `.xmp` sidecars (same basenames)
     - 0 `.part` files anywhere in the tree
     - manifest (`.cache/photo-export-manifest.txt`) gained the 5 new UUIDs
       (and no more than 5 new since the run started)
  5. Print PASS/FAIL with a file count summary; restore the saved config
     (always, via `trap`).
- Exit 0 on pass, 1 on fail.

## Notes / gaps to decide at implementation time

- **Invocation for TCC**: `open` on the Home Manager Apps path (what LS
  resolves) is the reliable one; do NOT rely on `open --args` (it doesn't
  forward args — that's why config exists).
- **Where to run it**: NOT in `nix flake check` (TCC GUI gate). Either a
  manual `bin/` script, or a `nix run`-able package target the user invokes
  deliberately. Decide when implementing.
- **Dest scratch cleanup**: script should `rm -rf /tmp/photo-export-smoke`
  both before and after, so reruns are clean; don't let it accumulate.
- **Manifest isolation**: consider a dedicated manifest path for the smoke
  run (the app reads `manifest` from config) so the test never pollutes the
  real backup manifest. This is a small config-key already supported.

## Acceptance criteria (when implemented)

- `bin/photo-export-smoke-test` passes on a Mac with Photos library + granted
  TCC (first run: one Allow click documented).
- Fails loudly (non-zero, clear message) if: auth denied, 0 files exported,
  sidecar count mismatch, any `.part` leftover, manifest count wrong.
- Does not modify the real `~/.cache/photo-export-manifest.txt` or the real
  `config.toml` after the run (trap restore).
- Documented in AGENTS.md next to the photokit-export entry.
