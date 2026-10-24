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
- [2026-10-19 — Secretive/TouchID failures don't only look like `Permission denied (publickey)`](2026-10-19-secretive-touchid-closes-the-connection.md)
- [2026-10-19 — Piping a command to `tail` reports success, and hides the failure from capture](2026-10-19-pipe-masks-exit-code.md)
- [2026-10-19 — `~/DECISIONS.md` is a read-only nix store symlink](2026-10-19-decisions-md-is-a-store-symlink.md)
- [2026-10-19 — `rg -r` is `--replace`, not recursive](2026-10-19-ripgrep-r-is-replace.md)
- [2026-10-21 — `nr` commits its own dependency bumps, sweeping in pending overlay edits](2026-10-21-nr-auto-commits-dependency-bumps.md)
- [2026-10-21 — LibreSSL's `openssl verify` ignores aux trust, so it reports OK for a rejected root](2026-10-21-libressl-verify-ignores-aux-trust.md)
- [2026-10-21 — `security.pki` does not reach the bundle nix OpenSSL tools fall back to](2026-10-21-pki-blacklist-misses-profile-bundle.md)
- [2026-10-22 — OpenCode V2 ships only through npm, so a GitHub-release overlay cannot find it](2026-10-22-opencode-v2-is-npm-only.md)
- [2026-10-22 — OpenCode V2 commands silently spawn a background service on a fixed port](2026-10-22-opencode-v2-managed-service.md)
- [2026-10-23 — `git --work-tree=X` does not make pathspecs relative to X](2026-10-23-work-tree-does-not-scope-pathspecs.md)
- [2026-10-23 — `age` is not installed; encrypt with `rage`, piped from an unnamed hx buffer](2026-10-23-rage-not-age.md)
- [2026-10-23 — OpenCode V2 silently drops model references under the legacy `agent` key](2026-10-23-opencode-agent-singular-is-legacy.md)
- [2026-10-23 — OpenCode's cost is the model's configured price, not the provider's bill](2026-10-23-opencode-cost-is-model-price.md)
- [2026-10-23 — OpenCode requests a step budget, not the model's output limit](2026-10-23-opencode-output-token-ceiling.md)
