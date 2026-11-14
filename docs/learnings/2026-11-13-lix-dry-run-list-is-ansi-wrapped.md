# Lix wraps the dry-run build list in ANSI escapes even when stdout is a pipe

**Date:** 2026-11-13

## Symptom

`nr --update` failed building `python3.12-dunamai-1.26.3` (its own pytest suite
is time-sensitive; see below), and `nr-pins diagnose` refused to pin the input
that caused it:

```
nr-pins: nixpkgs-unstable: its branch head does not need dunamai built — not the culprit
nr-pins: nothing pinnable — this failure is neither a nixpkgs input regression nor an uncommitted prebuilt-overlay bump
```

But the exact command `nr-pins` uses to reach that verdict lists the package
right there:

```
$ cd ~/.config/nix && nix build --dry-run --refresh --no-link \
    --override-input nixpkgs-unstable github:NixOS/nixpkgs/nixpkgs-unstable \
    .#darwinConfigurations.accismus.system
these 135 derivations will be built:
  /nix/store/s03wgslf1x1x396sgd792vy8kgdf14w5-python3.12-dunamai-1.26.3.drv
```

The same misparse affects `nr-pins check`, which reads the same output to decide
a pin has expired — so a pin whose blocker is still there would be dropped.

## Cause

Lix 2.95.2's progress reporter emits terminal control sequences *even when
stdout is a pipe*: every line of the list arrives as

```
\e[?2026h\r\e[K  /nix/store/<hash>-<name>.drv\e[0m
```

`needs_build()` extracted the package names with
`sed -n 's#^.*/nix/store/[a-z0-9]*-\(.*\)\.drv$#\1#p'` — anchored on `.drv$` —
so with a trailing `\e[0m` it matched **nothing**, and "nothing will be built"
was read as "this input is exonerated". Lix (like Nix) prints this list to
stdout, not stderr, so `2>&1` and `$( )` capture the escapes.

The log-parsing half of `nr-pins` already had `strip_ansi` for nh's coloured
`builder for '…' failed` line; the probe output was simply never passed through
it.

## Fix

Strip the escapes before parsing — after capturing the command's exit status,
since a pipeline reports the last command's:

```bash
out="$(probe "$1" "$2" "$3")"
st=$?
[ "$st" -ne 0 ] && return 2
out="$(printf '%s\n' "$out" | strip_ansi)"
```

`nr-pins-tests.sh` now drives `check` through a fake `nix` that emits the
escaped shape (`FAKE_ANSI=1`), so removing the strip fails the suite (191 pass,
1 fail).

Rule of thumb: any `nix` output parsed as text needs `strip_ansi` first. Verified
2026-11-13 against real Lix 2.95.2 output — after stripping, all 135 drv names
parse out of the same dry run.

## Not the same lesson, but the trigger

`python3.12-dunamai`'s `test__version__from_git__with_annotated_tags` asserts the
commit timestamp is within ±1 min of `utcnow()`, which a slow sandboxed run
breaks (78 s between commit and the failing assertion, in a suite that took
9 min). It arrives in the closure only via nixpkgs-unstable's new `httpx2` →
`httpcore2` → `uv-dynamic-versioning` build chain, which is why the
2026-11-13 pin pins nixpkgs-unstable back to `4fe25e1` rather than fixing it.
