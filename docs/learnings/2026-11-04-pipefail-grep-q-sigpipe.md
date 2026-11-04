# Piping a large listing into `grep -q` fails under `pipefail`

**Date:** 2026-11-04

## Symptom

A layout check in `modules/overlays/opencode/update.sh` rejected a zip that
demonstrably contained the file:

```
ERROR: opencode-desktop-mac-arm64.zip has no OpenCode.app/Contents/Resources/app-update.yml
       — the install phase's strip/re-sign recipe no longer matches upstream's layout
```

while the same check run by hand said the file was there:

```
$ unzip -l /tmp/d.zip | grep 'app-update.yml'
   ...  OpenCode.app/Contents/Resources/app-update.yml
```

## Cause

The script sets `set -euo pipefail`. `grep -q` exits at the *first* match, which
closes the pipe; the producer (`unzip -l`, still writing thousands of entries)
dies of `SIGPIPE` and the pipeline's status becomes 141. `pipefail` reports that,
so `… | grep -q X || die` fires on a perfectly good input.

It is size-dependent, which is what makes it insidious: the same pattern on a
two-entry listing (`tar -tzf | grep -qx package/bin/opencode`) passes, because
the whole listing fits in the 64 KiB pipe buffer and the producer exits before
grep can close the pipe. Only the 300 MB desktop zip — with tens of thousands of
entries — ever hit it.

## Fix

Write the listing to a file and grep the file; no pipe, no SIGPIPE, and the
failure mode disappears:

```bash
unzip -Z1 "$zip" > "$tmpdir/files.txt"
grep -qx 'OpenCode.app/Contents/Resources/app-update.yml' "$tmpdir/files.txt" \
  || die "…"
```

The general rule: under `pipefail`, never pair a producer with an early-exiting
consumer (`grep -q`, `head`, `sed q`). Either drop `pipefail` for that one
pipeline (`{ unzip -l "$zip" || true; } | grep -q …`, ugly), or stage to a file.
