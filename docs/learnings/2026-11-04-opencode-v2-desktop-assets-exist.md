# OpenCode V2 started shipping a desktop zip at v2.2.5, so the frozen V1 pin had to move

**Date:** 2026-11-04

## Symptom

`nr --update` stopped on the opencode overlay and changed nothing at all — not
even the CLI pin it had already validated:

```
ERROR: a V2 desktop asset now exists (opencode-desktop-mac-arm64.zip at v2.2.5).
Update the opencode-desktop block by hand: this script only auto-bumps the CLI.
```

## Cause

Nothing was broken: the tripwire did its job. [The V2 overlay](2026-10-22-opencode-v2-is-npm-only.md)
was written when V2 published npm packages only, and it deliberately refused to
bump `opencode-desktop` until a real V2 desktop artifact appeared, because a
version bump there would have aimed `releases/download/v2.x.y/…zip` at a 404.
Upstream began attaching Electron assets at v2.2.5 (`opencode-desktop-mac-arm64.zip`,
298 MB zipped / 756 MB unpacked), so the guard fired instead of silently pinning
a URL that does not exist.

The bundle needed no packaging change: V2's `OpenCode.app` has the same layout as
V1's (top-level `OpenCode.app`, vendor Developer ID `5NZ4Q7NXJ4`,
`Contents/Resources/app-update.yml` present), so stripping the updater file and
re-signing ad-hoc still works — `codesign --verify --deep --strict` passes on the
result, and `verify-darwin.sh` agrees.

## Fix

`update.sh` now bumps both halves from the same tag: it lists the release's
assets, and when `opencode-desktop-mac-arm64.zip` is there it downloads it,
cross-checks the SHA-256 against the release's own `SHA256SUMS`, asserts the
bundle still carries `Contents/Resources/app-update.yml` and reports the tag's
version in `CFBundleShortVersionString`, then rewrites `desktopVersion` /
`desktopHash` next to the CLI pin. A tag *without* a desktop asset leaves the
desktop pin alone with a warning rather than failing the whole bump — an older
desktop still runs beside a newer CLI.

Cost to remember: the V2 desktop is ~320 MiB in the store per bump, so
`nr --update` now pulls ~510 MB (214 MB npm CLI tarball + 298 MB desktop zip)
and grows the store noticeably. That is the price of tracking both halves.

## See also

- [Piping into `grep -q` under `pipefail` fails on a large listing](2026-11-04-pipefail-grep-q-sigpipe.md)
  — the first version of the new layout check rejected a good zip.

## Evidence

`session://pi/733BCFD4-09F6-4E77-9D13-DE2AB5901CAF`
