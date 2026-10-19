# `git gc --prune=now` does not reclaim garbage held by reflogs

**Date:** 2026-10-19

## Symptom

The dotfiles bare repo was **947 MB**, with a single 932 MiB pack file and
42,439 in-pack objects — yet the largest blob reachable from any ref was 13 MB
(`.config/background`), and GitHub reported the repo at 24 MB.

`git fsck --unreachable` listed 30,987 unreachable objects totalling 2.6 GiB
uncompressed: a 462 MB pickle, several 100–200 MB Mach-O binaries, SQLite
databases, and a nested 50 MB `PACK` file (a `.git` directory that was committed
by mistake at some point).

## Cause

Objects stay reachable while **any reflog entry** points at them. `git gc` only
expires reflogs out to `gc.reflogExpireUnreachable` (default 30 days) before
pruning, and this repo had 595 reflog entries. `--prune=now` sets the *object
age* cutoff — it does not make reflog-held objects eligible. The two settings are
independent, so `git gc --prune=now` alone preserves most of the garbage.

## Fix

Expire reflogs first, then prune. Archive any genuinely interesting dangling
commits as refs so the prune cannot lose them (fish, per this repo's
convention):

```fish
set -l G git --git-dir=$HOME/.local/share/dotfiles

# 1. Inspect before deleting: which dangling commits are real work?
for c in ($G fsck --dangling | awk '/dangling commit/{print $3}')
    printf '%s  ' $c
    $G log -1 --format='%ci %s' $c
end

# 2. Keep them cheaply — a ref costs nothing, only its tree stays alive.
#    First confirm no huge blob lives in those trees, or you pin the bloat:
#    $G ls-tree -r <sha> | rg <big-blob-sha>
for c in ($G fsck --dangling | awk '/dangling commit/{print $3}')
    $G update-ref "refs/archive/pre-gc-"(date +%Y-%m-%d)"/"(string sub -l 8 $c) $c
end

# 3. The order matters.
$G reflog expire --expire-unreachable=now --all
$G gc --prune=now
```

Result: **947 MB → 40 MB**, pack 932 MiB → 29.22 MiB, in-pack 42,439 → 12,192,
loose 514 → 0. `git fsck --strict` clean, HEAD unchanged, all 385 tracked files
intact, all worktrees still registered.

**The archive step pins whatever those commits contain** — that is the whole
point of checking their trees first. Reproduced on a scratch repo with a 5 MB
blob in the dangling commit:

| state | objects | size-pack | on disk |
|---|---|---|---|
| before | 7 loose | — | 5.2 MB |
| after gc, commit archived | 7 in 1 pack | 4.77 MiB | 4.9 MB |
| after dropping the archive ref | 4 in 1 pack | 1.41 KiB | 112 KB |

So if the garbage is *inside* the dangling commits, archiving them reclaims
nothing. In the real repo none of the 900 MB was in those trees, which is why
archiving was free.

**Lesson:** when a repo is much bigger than its reachable content, the suspect is
reflogs, not history. `count-objects -vH` plus `fsck --unreachable` sizes it in
seconds; `--prune=now` on its own will look like it did nothing.
