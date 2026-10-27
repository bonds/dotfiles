# `status.showUntrackedFiles=no` hides files in *every* worktree

**Date:** 2026-10-19

## Symptom

A stale worktree at `~/src/bonds/dotfiles` (branch `dotfiles`, fully merged into
`main`) reported a completely clean tree:

```
$ git status --porcelain
(empty)
```

It actually held three real files: `nix-config-review.md` (16 KB),
`nix-fixes.patch` (11 KB), and `sophrosyne-dotfiles-path-assessment.md` (11 KB).
A `git worktree remove --force` would have deleted them silently.

## Cause

The bare repo sets `status.showUntrackedFiles=no` at the repository level, which
applies to **every** worktree of that repo — not just `$HOME`. So `git status` is
clean by construction, and `git status --porcelain` (which does not override the
setting) is clean too. Plain `git worktree remove` refuses on a dirty tree, but
it considers this tree clean, so it either succeeds and takes the files with it,
or only `--force` does.

This is the same setting that makes `config add` safe against accidentally
staging all of `$HOME` — a deliberate trade (see `DECISIONS.md`) with this
sharp edge.

## Fix

Always pass `-uall` before trusting "clean" in this repo:

```bash
git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME status --porcelain -uall
```

Before removing a worktree:

```bash
cd ~/src/bonds/dotfiles
git status --porcelain -uall          # NOT plain `git status`
git log --oneline main..HEAD          # no unique commits?
git merge-base --is-ancestor HEAD main # merged?
# then: git worktree remove <path>; git branch -d <branch>
```

**Lesson:** `showUntrackedFiles=no` is a repo-wide lie about worktree state.
`-uall` is the only honest view, and it is mandatory before any destructive
worktree operation.

## Evidence

`session://pi/01a1525b-e95e-71f0-9f75-d46b9e77428d#turn-380`

Found by searching the archive for a verbatim phrase from this entry (33 hit(s) for `nix-config-review.md`), within 3 days of the entry date.

> - Entry 2: 3 files, sizes 16KB/11KB/11KB — actual: nix-config-review.md 16520 (16KB), nix-fixes.patch 11319 (11KB), sophrosyne-dotfiles-path-assessment.md 11148 (11KB). ✓
