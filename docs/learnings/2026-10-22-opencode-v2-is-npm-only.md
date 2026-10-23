# OpenCode V2 ships only through npm, so a GitHub-release overlay cannot find it

**Date:** 2026-10-22

## Symptom

Bumping the opencode overlay to the V2 line by keeping the old URL shape failed:
`https://github.com/anomalyco/opencode/releases/download/v2.1.4/opencode-darwin-arm64.zip`
404s even though the tag `v2.1.4` exists.
`https://api.github.com/repos/anomalyco/opencode/releases/latest` reports
`v1.19.4`, and `/releases/tags/v2.1.4` returns 404 — no v2 release object exists
at all.

## Cause

V2 is distributed as npm packages only: the `@opencode/cli` meta-package depends
on a per-platform payload, `@opencode/cli-darwin-arm64`, whose tarball contains
just `package/bin/opencode` (a 214 MB Bun single-file binary) and
`package/package.json`. Upstream tags `v2.*` in git but never attaches release
assets, and `/releases/latest` keeps pointing at the last V1 release — so any
"releases/latest + asset zip" update logic silently stays on V1 forever.

Two consequences: V1 and V2 need different fetch strategies in the same overlay
file, and `opencode-desktop` has no V2 artifact of any kind (no npm package, no
release assets), so the desktop app has to stay pinned on V1 1.19.4.

## Fix

Pin V2 from the npm payload and pick the version from the git tags, not from
`/releases/latest`:

```bash
curl -fsSL https://api.github.com/repos/anomalyco/opencode/git/refs/tags/v2 \
  | jq -r '.[].ref | sub("^refs/tags/v"; "")' \
  | grep -E '^2\.[0-9]+\.[0-9]+$' | sort -V | tail -1
```

Then fetch `https://registry.npmjs.org/@opencode/cli-darwin-arm64/-/cli-darwin-arm64-<ver>.tgz`,
check the bytes against npm's `dist.integrity` (sha512), and run
`bin/opencode --version` with a throwaway `HOME` before writing the pin.

Working implementation: `.config/nix/modules/overlays/opencode/{default.nix,update.sh}`.
The overlay extracts only `package/bin/opencode` from the `.tgz`
(`dontUnpack = true`), and `update.sh` refuses to touch the `opencode-desktop` V1
pin until a real V2 desktop asset appears.

## See also

- [OpenCode V2 commands silently spawn a background service](2026-10-22-opencode-v2-managed-service.md)
