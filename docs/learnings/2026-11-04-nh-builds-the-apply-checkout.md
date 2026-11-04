# `nh darwin build ~/.config/nix` verifies the apply checkout, not your edits

**Date:** 2026-11-04

## Symptom

After bumping an overlay in the edit checkout, a build-verify reported success
while proving nothing:

```
$ nh darwin build ~/.config/nix
>>> /nix/store/wz3m538smibk06lf8awjcyjzra9cxw8h-darwin-system-26.05.d31953c
DIFF: 0 bytes
> No version or size changes.
```

The overlay in the diff had clearly changed version, so "no version or size
changes" should have been impossible.

## Cause

`~/.config/nix` is a real directory in `$HOME` — the **apply** checkout, which
`nr` brings to `main` itself before building. Edits belong in
`~/.local/share/dotfiles/worktree/.config/nix`, a separate checkout with its own
index. So `nh darwin build ~/.config/nix` built the tree `nr` last applied: the
old pin. `nh` exits 0, the store path is a real system, and the only hint is the
`DIFF: 0 bytes` line, which reads like "nothing to do" rather than "you built the
wrong tree".

## Fix

Point the build at the tree you edited:

```bash
nh darwin build ~/.local/share/dotfiles/worktree/.config/nix
```

It reports the real delta (`opencode-desktop 1.19.4 -> 2.2.5, +317 MiB`) — treat
a `DIFF: 0 bytes` result after a version bump as a sign you built the wrong
checkout, not as a pass. `nr` itself is unaffected: it applies `main` to `$HOME`
first, so it always builds what was committed.