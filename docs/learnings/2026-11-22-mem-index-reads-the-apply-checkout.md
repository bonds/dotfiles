# `mem index` reads the apply checkout, so a new learnings entry is invisible until `nr` runs

**Date:** 2026-11-22

## Symptom

Committed a new entry (`docs/learnings/2026-11-22-pi-harness-desktop-superset.md`)
from the edit checkout and ran `mem index`. It reported `1 to embed — 1/1
embedded`, the index grew, and `mem recall "…pi-harness…" --mode semantic`
returned nothing from `docs/learnings`:

```
sqlite3 -readonly ~/.local/share/agents/index/semantic.db \
  "select count(*) from vec where text like '%Pi-Harness is a well-built%';"
0
```

Meanwhile `git --git-dir=…/bare --work-tree=$HOME rev-parse HEAD` already printed
the new commit, which reads as "the apply tree is current".

## Cause

Two separate things:

- `bin/mem` collects curated docs with
  `sorted((HOME / "docs" / "learnings").glob("*.md"))` — `$HOME/docs/learnings`,
  the **apply** checkout. The edit checkout at
  `~/.local/share/dotfiles/worktree` is never scanned, so a doc exists for the
  index only after `nr`'s `bin/nr-guard` applies `main` into `$HOME`.
- `rev-parse HEAD` for the `$HOME` view reads the **bare** repo's `refs/heads/main`,
  which the worktree commit already moved. HEAD is a ref, not the files: it says
  "current" while `$HOME/docs/learnings` is still one file short.

The `1 to embed` was an unrelated new transcript turn, so the run looked like it
had done the work.

## Fix / takeaway

After adding a learnings entry: commit, push, `nr` (applies `main` into `$HOME`),
*then* `mem index`. Verify with a `select … from vec where ref like '%<slug>%'`
against `~/.local/share/agents/index/semantic.db` rather than trusting the
`N/N embedded` line — and never conclude the apply tree is current from
`rev-parse HEAD`; check that the file itself exists under `$HOME`.
