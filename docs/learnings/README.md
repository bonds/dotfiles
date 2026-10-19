# Learnings

A running log of surprises and hard-won platform quirks in this dotfiles repo —
git behaviour, nix-managed paths, tooling traps. The point is to stop
re-discovering the same things every session.

Domain knowledge lives here, next to the config it concerns. Agent *conduct*
rules are different: those go to `~/.pi/agent/inbox.md` and get promoted via
`/distill` (see `AGENTS.md` → Compounding).

## Adding an entry

Create `docs/learnings/YYYY-MM-DD-short-slug.md` and link it below. One lesson
per file, with:

- **Symptom** — what you observed, including the exact error text.
- **Cause** — the underlying reason: platform quirk, API change, wrong
  assumption.
- **Fix** — what to do next time, with the command that works.

Keep it short and concrete. Supersede an entry rather than deleting it — a
lesson that was true once is still a lesson about why it changed.

## Entries

- [2026-10-19 — `git gc --prune=now` does not reclaim garbage held by reflogs](2026-10-19-git-gc-reflog-blocks-prune.md)
- [2026-10-19 — `status.showUntrackedFiles=no` hides files in *every* worktree](2026-10-19-showuntrackedfiles-hides-worktree-files.md)
- [2026-10-19 — `~/DECISIONS.md` is a read-only nix store symlink](2026-10-19-decisions-md-is-a-store-symlink.md)
- [2026-10-19 — `rg -r` is `--replace`, not recursive](2026-10-19-ripgrep-r-is-replace.md)
