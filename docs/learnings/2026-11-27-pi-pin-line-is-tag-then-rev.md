# `pi: v1.7.0 -> fb0fe82` prints the new tag then its rev, so it reads as a no-op when the version actually moved

**Date:** 2026-11-27

## Symptom

`nr --update` printed:

```
pi: v1.7.0 -> fb0fe823539f6d04850f6e34748c01f01f212e1f
```

Read as version -> version that says the old pin was already 1.7.0 and only the
rev moved (flake.lock went revCount 8228 -> 9009), i.e. a re-tagged release.
Wrong: the switch took pi **1.6.1 -> 1.7.0**.

## Cause

`pkgs/pi/update.sh` ends with `echo "pi: $tag -> $rev"`. The first field is the
GitHub release *tag* — the new one, just resolved — not the version being left
behind, and the second is the commit that tag dereferences
(`refs/tags/$tag^{}`). The flake version comes from that rev's `package.json`,
so the tag and the built version usually agree, which is what makes the line
look like a version comparison. It is not one.

## Fix / takeaway

Read the line as `tag -> rev`, never as `old -> new`. Get the real before/after
from the two system generations instead of the log line:

```fish
readlink -f /nix/var/nix/profiles/system-899-link/sw/bin/pi   # -> pi-1.6.1
readlink -f (command -v pi)                                   # -> pi-1.7.0
```

Judge the size of the bump from the rev change in `flake-pins.json` /
`flake.nix` and the revCount delta in `flake.lock`, and confirm what was
installed from the store path — never from this line.
