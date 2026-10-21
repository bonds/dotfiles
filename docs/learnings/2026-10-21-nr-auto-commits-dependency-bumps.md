# `nr` commits its own dependency bumps, sweeping in pending overlay edits

**Date:** 2026-10-21

## Symptom

The work tree showed two modified overlay files after I had committed only my
own doc edit:

```
$ git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME status --porcelain --untracked-files=no
 M .config/nix/modules/overlays/orca-ade/default.nix
 M .config/nix/modules/overlays/osaurus/default.nix
```

I planned to commit them separately once their `fetchurl` hashes were verified.
Scott ran `nr`; the next `git diff` was empty, and `git log` showed a commit I
had not made:

```
58ec440 nr --update: bump nightly dependency versions
 .config/nix/flake.lock                            | 24 +++++++++++-----------
 .config/nix/modules/overlays/orca-ade/default.nix |  4 ++--
 .config/nix/modules/overlays/osaurus/default.nix  |  4 ++--
```

## Cause

`nr` runs nix-darwin with `--update` and then commits the result itself, under a
fixed message. It does not scope that commit to the files it changed, so
whatever was already modified in `flake.lock` and the overlay files rides along.
This is why the history holds many identical `nr --update: bump nightly
dependency versions` commits — they are machine-made, not hand-written.

Useful corollary: `nr` builds the bumped versions, so a successful run *is* the
hash check.

## Fix

Don't plan a hand-made commit for overlay bumps. Either commit them before
running `nr`, or let `nr` do it and push afterwards — check what got swept in
with `git log -1 --stat`.

Verify hashes by letting `nr` build; `curl -I` returning 200 says nothing about
the hash, and a wrong one only surfaces at build time.

After any `nr`, check for a machine commit sitting ahead of both remotes:

```bash
git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME rev-parse --short HEAD origin/main sophrosyne/main
```

## See also

- `pi-harness` skill — the `learning` tool cannot write here (no `.git` in
  `$HOME`), so entries are written by hand and indexed manually.
