# ~/bin/mem is a copy, so ~/bin/tests/mem-test.sh tests the applied code and not your edit

**Date:** 2026-11-26

## Symptom

Edited bin/mem in the worktree, ran `bash ~/bin/tests/mem-test.sh`, saw 154 passed, and believed the new code was covered. Running the same suite from the worktree gave the real result, and a live `mem summarize` still took the old no-retry path and died on the first 429 — because `ls -l ~/bin/mem` is a 190 KB regular file, not a symlink.

## Cause

The test suite resolves its subject as `MEM="$HERE/mem"` where `HERE` is the script's parent, so invoking it through `~/bin` pins it to $HOME's apply checkout — the tree `nr` last built. Only the worktree copy has the uncommitted change.

## Fix

Run `bash bin/tests/mem-test.sh` (or `bash ~/.local/share/dotfiles/worktree/bin/tests/mem-test.sh`) from the worktree, and exercise the edit with `bin/mem …` from there too. The same applies to any tracked script invoked by path: check `ls -l` for a symlink before assuming `~/bin/X` is the repo copy.
