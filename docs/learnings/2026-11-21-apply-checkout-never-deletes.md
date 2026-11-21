# `config checkout main -- :/` never deletes, so a dropped package stays built

**Symptom.** Dropped `oxillama` from the repo (its upstream 404s), pushed, ran
`nr`, and afterwards `config status` in `$HOME` still listed the three deleted
files — as `A` (staged additions) — with the files still on disk. `nr` had said
`nr: applying dd681cf to /Users/scott` and the system closure was clean, so the
package *was* gone from the build, but the checkout was left dirty. Left alone,
that dirty index is what the next run calls "local edits to tracked files": it
refuses to apply main, and every `nr` after it builds whatever is in `$HOME`.

**Cause.** `git checkout <commit> -- <pathspec>` writes the paths `<commit>`
*has*. A path the commit lacks — i.e. one it deleted — is untouched in both the
index and the work tree. So an apply propagates additions and modifications and
silently drops deletions, and the old recipe (`config checkout main -- :/`) can
never express "main no longer has this".

**Fix.** Apply with the primitive that makes the checkout *equal* main:

```fish
config read-tree -u --reset main
```

`read-tree -u` updates index and work tree, removing paths present in the old
index but absent from the new tree, and leaving untracked files alone. `--reset`
discards local modifications, which is safe in `nr-guard` because the loop
before it has already proved every differing path holds an *older committed
state* — anything it cannot explain takes the refuse-to-apply branch instead.

`bin/nr-guard` now uses it, `bin/tests/nr-guard-test.sh` case 2b pins it (a
deletion in main must be gone from disk and leave the checkout clean), and the
"to discard them" advice names the new command.

Note `bin/nr-update-recover` still uses `checkout main -- "$path"`, which is
correct there: it restores *content* of files that exist in main.
