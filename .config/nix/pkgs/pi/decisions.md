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

**The passage YubiKeys keep `Touch policy: Never` on purpose.** The guarded
secret is low security by design — both keys are enrolled as "Scott's low
security secrets" — so possession of the key *is* the security boundary, and a
physical touch on every decrypt buys nothing worth the friction. Accepted
consequence: the wrapped identities for both passage keys have been in this
public repo since 2024, so anyone holding either YubiKey can decrypt
`NIX_CONFIG.age` with no PIN and no touch. That is the intended trade, not a
gap to close. It does **not** extend to agenix: those secrets are encrypted to a
third YubiKey (`age1yubikey1qwh2pyyk…`) whose identity is in neither the repo
nor on disk. Rejected: re-enrolling with `--touch-policy cached`, which would
protect a deliberately low-value secret at the cost of a prompt on every read.

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

**Prices in the pi UI are billed, never list.** A list price beside the billed
one is space that does not change the decision, and on the discounted models it
is wrong by 2x. So `model-prices.ts` derives the numbers from `cost` × the
discount — published at session start, then measured from each request — and the
`/prices` picker's three columns are in/out/cache, the rates that actually
differ between models. Nothing is shown until a multiplier is known, rather than
passing list off as billed.

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

## Nix

**opencode tracks the V2 CLI from npm; the desktop app stays on V1.**
(2026-10-22) V2 is a rewrite published only as npm packages (`@opencode/cli` →
payload `@opencode/cli-darwin-arm64`); upstream tags `v2.*` but attaches no
release assets, and `/releases/latest` still points at V1, so the old
`releases/download/…zip` fetch could only ever pin V1. Rejected: `pkgs.opencode`
(that *is* the V1 line), waiting for a V2 release asset (none exists), and
running both lines (same binary name and config dirs, so they cannot coexist).
Cost: the pin is ours to maintain, and `opencode-desktop` is frozen at 1.19.4
until upstream ships a V2 desktop artifact.

**A bad prebuilt-overlay bump is reverted from git, not pinned in the registry.**
(2026-10-23) `nr --update` bumps a version + SRI hash in `modules/overlays/*`
(and the prebuilt `pkgs/*`); those are files, not flake inputs, so the pin
registry cannot express them — it renders input declarations, and `reg_init`
rejects an entry whose input it does not own. So `nr-pins diagnose` matches the
failing derivation's pname against the overlay's `pname` and restores the
directory from git, i.e. the last committed pin. Rejected: registry entries
(wrong layer, breaks the registry's invariants), and leaving it manual — the
status quo that left a dirty work tree for the next `nr` to sweep into a commit.

**Runtime breakage is caught before the switch, by reverting, not by blocking.**
(2026-10-24) A prebuilt release can build and still be broken: won't start,
wrong payload, a code-signature seal broken by our own strip-and-re-sign, a
config the new binary rejects. `nr` therefore runs each overlay's smoke test
against the freshly built store path *before* switching and before the
auto-commit, and undoes a failure with the same git revert. Rejected: checking
after activation (the machine is already running the broken thing), abort-only
(leaves the bad bump dirty, and the next `nr --update` re-attempts it with no
memory of the failure), and verifying every directory on every `nr` (~10 s,
nearly all of it `codesign --deep` on Zen and Orca) — hence `--all` as an
explicit audit instead.

**Overlay smoke-test hooks are platform-suffixed (`verify-darwin.sh`).**
(2026-10-24) `zen-browser` is built on sophrosyne too, where `codesign` and
`PlistBuddy` do not exist. A generic `verify.sh` with a `uname` guard inside
would log "passed" for checks that never ran; a suffixed hook is simply absent
on the other platform, so `nr-pins verify` reports zero packages verified rather
than a success it did not earn.

## Agents

**Scott runs the activating rebuild; agents may only build.** `nr` needs no
password, so the rule is about control, not credentials: an agent switching the
system is an unattended change to the machine it is running on. Agents verify
with `nh darwin build` (or `nixos-rebuild build`) and hand over.

**TouchID is interactive, so a failed push is a hand-off, not a retry loop.**
Secretive signs only after approval and a fresh agent shell usually has no
identities. Rejected: retrying the push, which just burns turns; and using the
`gh` token, which is read-only for push.

**One memory store, shared by every harness** (2026-10-24). The inbox, the
learnings entries and `DECISIONS.md` are plain files, and `mem`
(`~/bin/mem`) is the only interface to them: `inbox add`, `learn`, `distill`,
`recall`. pi's extensions, an opencode plugin and a hermes `post_tool_call`
hook all append to `~/.local/share/agents/memory/inbox.md`, under one `flock`, so a lesson
captured by one harness is promotable from any other. Rejected: per-harness
memory (pi's inbox, hermes' `MEMORY.md`, osaurus' own store) — each is invisible
to the others, so the same mistake is re-learned in every harness. Cost:
osaurus only participates through `~/AGENTS.md` and `mem` in its sandbox (it has
no hooks), and hermes does not read `AGENTS.md` at all, so its context comes
from the `memory` skill.

**Lessons are recorded where they were learned** (`docs/learnings/` per repo,
the shared inbox for tool failures) rather than only in chat. A lesson
that lives only in a session is lost when the session is compacted away.
