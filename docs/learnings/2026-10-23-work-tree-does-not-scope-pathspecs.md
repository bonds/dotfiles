# `git --work-tree=X` does not make pathspecs relative to X

**Date:** 2026-10-23

## Symptom

Checking a working-tree change in the dotfiles bare repo printed an empty diff,
even though the file was demonstrably edited:

```
$ cd ~/.config/nix
$ git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME diff -U0 -- \
    .config/nix/modules/overlays/opencode
$ echo $?
1
```

The same command from `~` shows the four changed lines. `git status` behaved the
same way — the pathspec silently matched nothing.

## Cause

`--work-tree` only tells git which tree the paths *name*; pathspecs on the
command line are still resolved against the **current directory**, exactly as in
a normal repo. From `~/.config/nix`, `.config/nix/modules/...` means
`~/.config/nix/.config/nix/modules/...`, which does not exist. Git treats a
pathspec that matches nothing as "no change" for `diff`/`status`, not as an
error, so the empty output looks like a clean tree.

This is why `nr-pins`' `dot_git` helper does `cd "$DOT_WORK_TREE"` before running
git, and passes paths relative to the work tree: `diagnose` must be able to see
(and `git checkout HEAD --` revert) an overlay bump no matter which directory
`nr` was started from.

## Fix

Always `cd` to the work tree (or pass absolute pathspecs) when driving the
dotfiles repo from a script:

```bash
( cd "$HOME" && git --git-dir="$HOME/.local/share/dotfiles" \
      --work-tree="$HOME" diff --stat -- .config/nix/modules/overlays/opencode )
```

Diagnostic habit: if `git diff -- <path>` is empty but the file looks changed,
run the same command from `~` before concluding the change is gone — and check
`git status --porcelain -- <path>`, which also reports nothing for a pathspec
that matches no file.

## See also

- `~/.config/nix/nr-pins` — `dot_git`, `overlay_changes`, `revert_overlay`
