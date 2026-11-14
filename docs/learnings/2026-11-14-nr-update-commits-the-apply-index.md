# `nr --update` commits the apply tree's index, so it can revert an unapplied commit

**Date:** 2026-11-14

## Symptom

A package was committed in `~/.local/share/dotfiles/worktree` and pushed. The
next `nr --update` produced a commit that **deleted all of it**:

```
a0a80e4 nr --update: bump nightly dependency versions
 .config/nix/pkgs/swival/default.nix | 116 ----
 ...                                 | ...
 17 files changed, 34 insertions(+), 1245 deletions(-)
```

Nothing failed. `nr` built, verified, switched, and pushed; the only clue was a
line further up the log:

```
nr: WARNING /Users/scott has local edits to tracked files — not applying main:
nr:           .zshrc
nr:           building what is there; to discard them: cd ~; and config checkout main -- :/
```

and the newly added command simply did not exist after the switch.

## Cause

Two things, and the second is the one that destroys work.

1. **The apply was skipped.** `nr` only applies `main` to `$HOME` when the
   *whole* tree matches some recent position of `main`; one uncommitted line in
   `$HOME/.zshrc` (an installer's `export PATH=…`) defeated that, so `$HOME`
   stayed on the previous tree.

2. **`nr --update` commits the apply tree's entire index** — `git add
   $_nr_files`, then `git commit -m …` with no pathspec. `bare/index` is
   `$HOME`'s index, and it still described the tree `$HOME` last received,
   because the commit that moved `HEAD` happened in the *edit* worktree, which
   has its own index. Committing a stale index against a newer `HEAD` records
   every file that newer commit added as a **deletion**.

Reproduce it in a throwaway repo — one bare repo, `$HOME` as its work tree, a
linked worktree sharing the refs:

```
OLD sequence (add bumps, commit the whole index):
    bump.txt    | 1 +
    newfile.txt | 1 -          <-- the unapplied commit, reverted
NEW sequence (reset the index first):
    bump.txt | 1 +
```

## Fix

`nr` now resets the apply tree's index before staging its bumps
(`15-functions.fish`, top of the `--update` commit block):

```fish
git --git-dir=$_nr_git --work-tree=$HOME reset -q
set -l _nr_files $HOME/.config/nix/flake.lock
```

`--mixed` is the default: it touches the index only, never the files `nh` just
built. The commit is then exactly `HEAD` + this run's bumps, and the
`diff --quiet` probe that decides whether `flake.nix` rides along compares
against `HEAD` instead of a stale index.

Two things this does **not** fix:

- A dirty `$HOME` still skips the apply silently enough to miss. If you see
  that warning, you are building an older tree than `main`.
- A revert is not lost data: the content is still in the reverted commit, so
  `git checkout <good-commit> -- <paths>` restores it (that is what `2140b89`
  does for `a0a80e4`). `git revert` is the wrong tool — the commit also carries
  legitimate version bumps.
