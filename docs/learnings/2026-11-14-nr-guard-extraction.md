# `nr`'s checkout guards now live in `bin/nr-guard`

**Date:** 2026-11-14
**Status:** in progress — tests 25/26 green, one expectation still wrong

## What changed

`nr` (`~/.config/fish/conf.d/15-functions.fish`) carried ~120 lines of git logic
inline: resolving the dotfiles git dir, deciding whether `$HOME` was merely
behind `main` or held local edits, and classifying `worktree/` as stale vs
dirty. That logic is now `bin/nr-guard`, called once from the top of `nr`,
with tests in `bin/tests/nr-guard-test.sh` that build throwaway repos under
`/tmp` and point `NR_GUARD_ROOT` at them.

The fish function was left untouched so far; wiring it is the next step.

## Behaviour decided, and why

- **A stale edit tree is still dangerous with one local edit on top.** The old
  code asked "does this whole tree match an earlier main?" — true only for an
  untouched stale tree. Commit from one that also has an edit and git records
  that edit alone while every other file still describes `main~1`, which is
  exactly the silent revert `4d4fb86` caused. The test is now per changed file:
  a file holding **main's current blob** was changed under the tree, so stale.
- **Untracked / newly added paths are not stale.** Nothing is recorded for them,
  so they cannot revert anything.

## Gotchas hit while building it (all confirmed, not guessed)

1. **`cmd && var=$(...)` as the last line of a loop body makes the next `if`
   dead code.** When `cmd` succeeds the `if` ran; when it fails the `&&` chain's
   status is non-zero oddly enough to matter in this context and the following
   compound was skipped. Use `if cmd; then var=$(...); fi`. This cost an hour.
2. **In a linked worktree, `git diff <sha> -- path` returns the wrong answer
   when the tree has no local branch of that name.** Compare
   `git hash-object -- path` against `git rev-parse <sha>:path` instead.
3. **`git diff --name-only` ignores staged additions.** Use
   `git diff HEAD --name-only` if a staged new file must count.
4. **macOS bash is 3.2**: `${arr[@]}` under `set -u` must be written
   `${arr[@]+"${arr[@]}"}`.
5. **Test fixtures where the bare repo's HEAD is not `main`** produce a
   linked worktree with no `main` ref, which is how gotcha 2 surfaced.

## Not tested here

`nr` itself does not yet call `nr-guard`; the apply-tree guard in the fish
function is still the old inline copy.
