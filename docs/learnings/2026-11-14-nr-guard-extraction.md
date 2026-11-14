# `nr`'s checkout guards now live in `bin/nr-guard`

**Date:** 2026-11-14
**Status:** done — `2e7ece1`, 30 assertions green, running on accismus and sophrosyne

## What changed

`nr` (`~/.config/fish/conf.d/15-functions.fish`) carried ~120 lines of git logic
inline: resolving the dotfiles git dir, deciding whether `$HOME` was merely
behind `main` or held local edits, and classifying `worktree/` as stale vs
dirty. That logic is now `bin/nr-guard`, called once from the top of `nr`, with
tests in `bin/tests/nr-guard-test.sh` that build throwaway repos under `/tmp`
and point `NR_GUARD_ROOT` at them. The fish function dropped from 538 to 446
lines and keeps only flag parsing, the `nh` build/switch loop, and the
`--update` commit-and-push step.

`nr` calls `$HOME/bin/nr-guard` when it exists, and otherwise runs
`git show main:bin/nr-guard | bash` — a `$HOME` that predates the script still
gets guarded. Both read `$pipestatus[1]`, never the pipeline's status.

## Behaviour decided, and why

- **The apply tree asks per path, not per tree.** `$HOME` several commits behind
  matches no single position of `main`, so testing the set would call ordinary
  staleness "local edits" and refuse to apply. Each present path must be
  explained by some earlier position; anything else is local work.
- **The edit tree asks about its TREE, not its files.** This is the one that bit
  us. A file edited on top of an old state differs from *every* position, so a
  per-file check cannot see that the commit still records `main~1` for all the
  other files — the silent revert of `4d4fb86`. Comparing `HEAD^{tree}` against
  earlier `main` trees catches it. A clean tree on an old `main` is merely
  "behind" and is reported as such.
- **Untracked / newly added paths are not stale.** Nothing is recorded for them,
  so they cannot revert anything.
- **A missing repo is announced**, rather than silently disabling the guards.

## Gotchas hit while building it (all confirmed, not guessed)

1. **A bare `cmd && var=$(...)` line can swallow the statement after it.** In the
   edit-tree loop this made the following `if` act as dead code: `cm "$rev:p" &&
   main_blob=$(...)` followed by `if [ ... ]` never branched as written. Use
   `if cmd; then var=$(...); fi`. Cost the better part of an hour.
2. **In a linked worktree, `git diff <sha> -- path` compares against the work
   tree, not the commit.** Once the file has an edit, it differs from every
   position, so "does this file match an older main?" cannot be answered that
   way. Compare tree hashes, or `hash-object` against `rev-parse <sha>:path`.
3. **`git diff --name-only` ignores staged additions.** Use
   `git diff HEAD --name-only` when a staged new file must count.
4. **macOS bash is 3.2**: `"${arr[@]}"` on an empty array under `set -u` is an
   unbound-variable error; write `${arr[@]+"${arr[@]}"}`.
5. **Test fixtures whose bare repo HEAD is not `main`** produce a linked
   worktree with no `main` ref, which is how gotcha 2 surfaced.
6. **Write files with a tool, not a shell heredoc.** Heredocs containing
   `$(...)`, quotes and unicode repeatedly arrived mangled (dropped characters,
   `$q` placeholders left in output). The mangling produced several wrong
   diagnoses before it was noticed; a corrupted test file even reported PASS
   results that meant nothing.

## Regression test

`bin/tests/nr-guard-test.sh` case 5a pins the tree-hash behaviour: an edit
committed while `main` moved, plus one more uncommitted edit. It **fails against
the old per-file logic** and passes against the current one — verified by
rebuilding the old version and running the suite with `GUARD` overridden.

## Still open

- `nr --update` was never exercised end-to-end through the new guard call.
