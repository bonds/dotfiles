---
name: nix-updates
description: "How `nr --update` heals itself: the self-expiring flake-input pins (`nr-pins` snapshot/check/diagnose, the registry, exit codes 0/1/2/3), the git revert of a bad prebuilt-overlay bump, and the per-overlay smoke tests (`verify-darwin.sh`) that run before the switch. Use when a dependency bump fails to build, a pin was added or expired, an overlay release builds but the app is broken, or you are touching nr-pins, flake-pins.json or modules/overlays/*/verify-*.sh."
---

`nr --update` bumps three different kinds of dependency, and only one of them is
a flake input. `nr-pins` (`.config/nix/nr-pins`) gives all three a way back.

| Kind | Bumped by | Undone by |
|---|---|---|
| flake input (`nixpkgs`, `nixpkgs-unstable`, rev-pinned `pi`) | `nix flake update`, `pkgs/pi/update.sh` | a **pin** in `flake-pins.json`, expiring on its own |
| prebuilt overlay (`modules/overlays/*`, prebuilt `pkgs/*`) | its `update.sh` | `git checkout HEAD -- <dir>` (the last committed pin) |
| same, broken at runtime | — | the same revert, triggered by the overlay's smoke test |

## Exit codes

`nr` reads these, so they are part of the contract:

| code | meaning | `nr` does |
|---|---|---|
| 0 | nothing to do / everything verified | proceed |
| 1 | could not undo it, or a hook failed with nothing to revert | stop; do not switch, do not commit |
| 2 | a pin was written (registry + `flake.nix` rewritten) | rebuild |
| 3 | a prebuilt-overlay bump was reverted | rebuild |

## The three commands `nr` calls

- `nr-pins snapshot` → before `nix flake update`: remember the revs that build
  right now. A failed update can only pin a culprit back if this ran.
- `nr-pins check` → drops pins whose blocker has cleared, so they expire on
  their own. **A probe that cannot run is never read as "cleared".**
- `nr-pins diagnose <log>` → after a failed build: parse the failing derivation
  out of the log, then undo the most specific cause that explains it —
  an uncommitted overlay bump whose `pname` is that derivation (revert, rc 3),
  then a moved rev-pinned input whose package is that derivation (pin, rc 2),
  then a nixpkgs-family input whose branch head would have to *build* that
  package from source (pin, rc 2).
- `nr-pins verify <system-path>` → after a SUCCESSFUL build, before the switch:
  run each overlay's hook against the freshly built store path, revert on
  failure. `--all` audits every overlay instead of only the bumped ones.

## Invariants that keep this safe

- **The registry is the source of truth for `flake.nix`.** The block between
  `BEGIN/END nr-managed input pins` is generated — edit `flake-pins.json`, then
  `nr-pins apply` (or `check`, which reconciles). Every input the block owns is
  always declared, pinned or not, or every `inputs.X.follows` dangles.
- **Only `owner == NixOS && repo == nixpkgs` inputs are ever pinned**, never on
  an eval error, never on an input that did not move.
- **A revert needs a pure version/hash diff.** An overlay directory is only
  reverted when it is modified *and* every changed line is a pin line — a hand
  edit beside the bump is never discarded.
- **Skips are not failures, but they are not silent either:** a package missing
  from the closure, or matching two store paths, is reported and skipped;
  a hook that exists but cannot run is a **failure**.
- **The system path for `verify` comes from nh's `>>> /nix/store/…` line** in
  the log `nr` tees. A no-change build prints none, and then there is nothing
  new to verify.

## Smoke-test hooks

`<overlay>/verify-<os>.sh <system-path> <pname> <package-out-path>`, called once
per `pname` the overlay's `default.nix` declares. A platform-agnostic
`verify.sh` is the fallback; the suffixed file wins. Shared helpers:
`modules/overlays/lib-verify.sh` — `verify_app <bundle> <version>` (present,
`codesign --verify --deep --strict`, `CFBundleShortVersionString` equal to the
derivation's version) and `verify_no_updater <bundle>`.

The opencode hook additionally proves `--version` matches the derivation and
that `models --standalone` still parses the real config (throwaway `HOME`, the
real `opencode.jsonc` copied in). `--standalone` goes **after** the subcommand.

Write a hook to assert only what is deterministic: a network-dependent check
must warn, not fail, or an offline `nr --update` reverts a good release.

## Changelogs during `nr --update`

- **A blank changelog is usually a failed URL guess, not an absent upstream.**
  `nix-what-changed` guesses `nixpkgs#<name>.meta.*` then
  `github.com/<pkg>/<pkg>`, which misses Python sub-packages, local derivations,
  date-tagged repos and upstreams with no releases. Look for null metadata in the
  on-disk cache and add an explicit `KNOWN_URLS` entry — that is the override
  point, and it has to stay in sync with both version files and the tests.
- **Test it through the flake environment, not the host Python.** Run the edited
  source from the flake's `python3.withPackages` (or with
  `PYTHONPATH="$PWD:$PYTHONPATH"` and a temporary cache): the system interpreter
  lacks the package's dependencies, so a plain `python3 tool.py` fails for
  reasons unrelated to the change.

## Working on this

- **Run the suite:** `bash ~/.config/nix/nr-pins-tests.sh` — 190 stubbed cases
  in ~1 min, never touches the real flake. Run it after *any* edit to `nr-pins`,
  its tests, or a hook: a collapsed line once merged `revert_overlay`'s
  `local dir=…` into a comment, and only the suite caught it.
- **Commit or stash work in progress before `nr --update`.** It commits
  `flake.lock`, `flake-pins.json`, `nr-pins`, `nr-pins-tests.sh` and every
  overlay it bumped, under one fixed message. `5824dcd` is the scar: it captured
  a mid-edit `nr-pins` whose revert path was broken.
- **Verify a hook by hand** without switching:
  `bash .config/nix/nr-pins verify --all /run/current-system`.
- Manual recovery, when nothing automatic applies: `git revert` the bump
  commit, or restore one file with
  `git --git-dir=~/.local/share/dotfiles --work-tree=~ checkout HEAD -- <path>`
  (from `~`, or with a path relative to it — `--work-tree` does not scope
  pathspecs).
