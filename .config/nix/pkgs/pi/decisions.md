# Decisions

Settled choices and the reasoning behind them. `AGENTS.md` says *what* to do;
this file says *why*, so the question does not get re-litigated every time an
agent notices the setup is unusual.

Rules: one entry per decision, dated, with the alternative that was rejected.
Add an entry when a decision is made; do not edit history to match a later
mood — supersede it with a new entry and a pointer. Agents: read this before
proposing a change to something that looks odd. If a decision is reversed,
reversing it is a new entry here, not a silent edit.

## Dotfiles

**Bare repo at `~/.local/share/dotfiles` with `--work-tree=$HOME`** (2026-10-11,
moved from `~/.config/dotfiles`). Rejected: a normal `~/.git`, because a `.git`
directory in `$HOME` confuses tools that walk up looking for a repository.
Untracked files are hidden (`status.showUntrackedFiles=no`) so `git add` can
never accidentally stage the whole home directory.

**`config` is a fish-only alias.** It resolves the git dir by existence, so the
same file is correct on every machine and during a move. Rejected: a `bin/`
script on `PATH`, because it would shadow real `git` mistakes less visibly and
agents would have to discover it. Cost: every non-fish caller (Hermes, bash,
scripts) must spell out `git --git-dir=... --work-tree=...`.

**Never force-push.** The sophrosyne bare repo has a `post-receive` hook that
force-checks-out the work tree, so a force-push there destroys uncommitted work
with no recovery. Divergence is reconciled by pulling, not by overwriting.

**`flake.lock` is owned by whoever last updated it.** If sophrosyne updates its
lock and accismus pushes afterwards, accismus wins. Accepted, not a bug.

## Secrets

**Age/agenix and passage, never plaintext in the repo.** The dotfiles repo is
public. Hence: `protected-paths.ts` blocks writes to `secrets/`, `~/.ssh`,
`/run/agenix`, `~/.config/passage`; the pi API key is a `!command` in
`models.json` that reads `/run/agenix/hermes-deepinfra` at request time; SSH
agent is Secretive (TouchID + secure enclave) rather than an on-disk key.

**Two GitHub tokens, deliberately separate.** Fine-grained PAT in the `gh`
keyring for Scott's repos; classic `public_repo` token in the Keychain behind
the `gh-public` wrapper for third-party public repos. Rejected: one broad token,
because a token that can push to Scott's repos should not be the one used to
open an issue on someone else's.

## pi

**Config is declarative in `.config/nix/pkgs/pi/`, symlinked read-only.** The
cost: `pi install` and `pi mcp add` cannot persist, so every change is an edit
plus `nr`. Accepted, because the alternative is config that exists only on one
machine and cannot be reviewed in git. `settings.json` is the exception — pi
writes it at runtime, so it is merged with `jq` at activation.

**Deep Infra over a first-party provider.** ~$0.20/$0.60 per million tokens
with a 1M context, versus an order of magnitude more elsewhere. Cost: no pi.dev
catalog entry, so prices live in `models.json` and `reported-cost.ts` overrides
pi's list-price math with Deep Infra's own `usage.estimated_cost` (the model
carries a discount, so list price overstates the bill ~2x).

**Skills live in `.config/nix/agent-skills/`, one symlink per skill per
harness.** Rejected: one symlink for the whole directory, because each harness
must be able to keep its own skills. `~/.agents/skills` is the only pi path —
linking `~/.pi/agent/skills` as well makes every skill collide at startup.

**`enabledModels: ["deepinfra/**"]`.** `**`, not `*`: model IDs contain a slash
and the glob does not cross it, so `deepinfra/*` matches nothing and `ctrl+p`
becomes a no-op.

**`defaultTools: ["+codemode"]`.** Calling tools from one script beats one
round-trip per tool call; the alternative (default tools only) costs latency
and tokens on every multi-step task.

## Agents

**Scott runs the activating rebuild; agents may only build.** `nr` needs no
password, so the rule is about control, not credentials: an agent switching the
system is an unattended change to the machine it is running on. Agents verify
with `nh darwin build` (or `nixos-rebuild build`) and hand over.

**TouchID is interactive, so a failed push is a hand-off, not a retry loop.**
Secretive signs only after approval and a fresh agent shell usually has no
identities. Rejected: retrying the push, which just burns turns; and using the
`gh` token, which is read-only for push.

**Lessons are recorded where they were learned** (`docs/learnings/` per repo,
`~/.pi/agent/inbox.md` for tool failures) rather than only in chat. A lesson
that lives only in a session is lost when the session is compacted away.
