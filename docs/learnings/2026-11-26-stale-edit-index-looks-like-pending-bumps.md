# A stale edit-tree index shows as staged reverts of the last nr --update commit, not as pending bumps

**Date:** 2026-11-26

## Symptom

`git status` in worktree/ listed `.config/nix/flake.lock` and `modules/overlays/osaurus/default.nix` as staged — the two files the previous `nr --update` bumped — which reads as an uncommitted version bump waiting to be committed. Nothing had changed in either file, and the next `nr` left the tree clean with no commit of its own.

## Cause

`nr --update` stages and commits from the APPLY tree ($HOME, `bare/index`), so its commit moves main without touching the edit worktree index. That index keeps describing the previous main, and git renders "index older than HEAD" as staged changes that look like a reversal of the bump. nr-guard recognises exactly this shape (HEAD already at main, no unstaged diff, every staged blob equal to some earlier main) and syncs it with `reset -q --hard main`, which is why the entries vanished instead of becoming a commit.

## Fix

Before treating staged entries as work, compare them with `git show --stat <last nr --update commit>`: the same paths means a stale index, not a pending bump, and `nr` will sync it. Never `git add -A` or `git commit -a` from the worktree in that state — it reverts the bump (a0a80e4 reverted 17 files that way); commit with explicit paths. Check `git fsck --dangling` if you need proof nothing was lost.
