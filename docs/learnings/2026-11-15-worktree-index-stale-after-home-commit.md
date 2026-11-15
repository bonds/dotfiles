# A `$HOME`-side commit leaves the edit worktree's index looking like a staged revert

**Date:** 2026-11-15

## Symptom

The edit worktree showed two overlays as **staged downgrades**:

```
M  .config/nix/modules/overlays/orca-ade/default.nix     # 1.4.259 -> 1.4.258
M  .config/nix/modules/overlays/osaurus/default.nix      # 1.0.4  -> 1.0.3
```

`nr-guard` called it "worktree/ has uncommitted changes — commit or stash them",
and committing it would have reverted the previous night's `nr --update` bump.

## Cause

`nr --update` commits from the **apply tree**, not the edit worktree:

```
git --git-dir=$_nr_git --work-tree=$HOME commit …
```

That moves `main`, and the edit worktree **shares the `main` ref** (it has no
branch of its own on accismus). So its `HEAD` moves to the new commit while its
files and index still describe the previous one. Git sees `index != HEAD` and
reports the difference as **staged** changes — indistinguishable from a
deliberate revert. Nothing was reverted; the worktree simply never advanced.

`nr-guard`'s stale check was gated on `HEAD != main`, so it skipped the tree
comparison and fell through to the "commit or stash" message. The test fixture
uses a separate `edit` branch, which is why the case was never covered.

## Fix

Do **not** commit that diff. Sync the edit tree:

```bash
git -C ~/.local/share/dotfiles/worktree reset --hard main
```

`nr-guard` now also detects the shared-ref layout: when `HEAD == main`, there
are no unstaged edits, and every staged blob matches an older position of main,
it reports STALE and prints the sync command. Test: `nr-guard-test.sh` case 5d.
