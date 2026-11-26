# Learnings

A running log of surprises and hard-won platform quirks in this dotfiles repo —
git behaviour, nix-managed paths, tooling traps. The point is to stop
re-discovering the same things every session.

Domain knowledge lives here, next to the config it concerns. Agent *conduct*
rules are different: those go to `~/.local/share/agents/memory/inbox.md` (`mem inbox add`,
or a harness hook) and get promoted via `/distill` (see `AGENTS.md` →
Compounding).

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
- [2026-10-24 — A dead opencode plugin reload poisons the server's provider registry](2026-10-24-opencode-plugin-reload-breaks-provider-registry.md)
- [2026-10-25 — OpenCode remembers a variant per model, and `default_agent` emits no selection](2026-10-25-opencode-remembers-variant-per-model.md)
- [2026-10-25 — `new URL(path, origin)` turns a leading `//` into a different host](2026-10-25-url-relative-path-becomes-host.md)
- [2026-10-25 — Osaurus `shell_run` dies when `/workspace` cannot be snapshotted](2026-10-25-osaurus-shell-run-needs-a-small-workspace.md)
- [2026-10-25 — opencode plan mode rejects writes to its own plan directory](2026-10-25-opencode-plan-dir-guard.md)
- [2026-10-26 — Osaurus launches a stdio MCP provider as one executable, with no arguments](2026-10-26-osaurus-mcp-stdio-single-executable.md)
- [2026-10-26 — Osaurus spawns MCP servers with `cwd=/` and a minimal environment](2026-10-26-osaurus-mcp-spawn-environment.md)
- [2026-10-26 — Osaurus keeps its own memory, and it is not where ours belongs](2026-10-26-osaurus-has-its-own-memory.md)
- [2026-10-27 — A live SQLite database reports "database is locked" to readers](2026-10-27-sqlite-busy-timeout.md)
- [2026-11-04 — OpenCode V2 started shipping a desktop zip at v2.2.5, so the frozen V1 pin had to move](2026-11-04-opencode-v2-desktop-assets-exist.md)
- [2026-11-04 — Piping a large listing into `grep -q` fails under `pipefail`](2026-11-04-pipefail-grep-q-sigpipe.md)
- [2026-11-04 — `nh darwin build ~/.config/nix` verifies the apply checkout, not your edits](2026-11-04-nh-builds-the-apply-checkout.md)
- [2026-11-04 — Web search and status pages: which endpoints actually return data](2026-11-04-web-search-that-returns-data.md)
- [2026-11-11 — A nightly photo backup that logs "backup complete" may never have connected](2026-11-11-photo-backup-silent-no-op.md)
- [2026-11-13 — Zoom's "sign in again to renew your session" is an account policy, not a broken install](2026-11-13-zoom-session-expired-is-an-account-policy.md)
- [2026-11-13 — Lix wraps the dry-run build list in ANSI escapes even when stdout is a pipe](2026-11-13-lix-dry-run-list-is-ansi-wrapped.md)
- [2026-11-14 — macOS `strip` inflates non-Mach-O files in a nix build](2026-11-14-macos-strip-inflates-non-macho-files.md)
- [2026-11-14 — `nr --update` commits the apply tree's index, so it can revert an unapplied commit](2026-11-14-nr-update-commits-the-apply-index.md)
- [2026-11-14 — `nr`'s checkout guards now live in `bin/nr-guard`](2026-11-14-nr-guard-extraction.md)
- [2026-11-15 — sleepwatcher's wake hook can remount a drive across a sleep it never hears about](2026-11-15-sleepwatcher-display-sleep-hooks.md)
- [2026-11-15 — A `$HOME`-side commit leaves the edit worktree's index looking like a staged revert](2026-11-15-worktree-index-stale-after-home-commit.md)
- [2026-11-17 — Hermes prices Deep Infra at list, and a `$HERMES_HOME` provider plugin is where you fix it](2026-11-17-hermes-cost-is-list-price.md)
- [2026-11-18 — An ad-hoc signature keys the Photos TCC grant to the cdhash, so every rebuild needs a re-grant](2026-11-18-adhoc-signature-keys-tcc-grant-to-cdhash.md)
- [2026-11-21 — `config checkout main -- :/` never deletes, so a dropped package stays built](2026-11-21-apply-checkout-never-deletes.md)
- [2026-11-21 — `nix flake check --no-build` evaluates the checks and runs none of them](2026-11-21-no-build-never-runs-the-checks.md)
- [2026-11-21 — A git-backed flake ignores files git does not know about](2026-11-21-flakes-ignore-untracked-files.md)
- [2026-11-21 — pi.dev/packages lists download counts only in the HTML, sorted by most downloads](2026-11-21-pi-package-gallery-download-counts.md)
- [2026-11-21 — Verify billed cost survives a proxy by comparing effective rates per message](2026-11-21-verifying-billed-cost-through-a-proxy.md)
- [2026-11-21 — pi's cost seam is `message_end`, and a third-party footer inherits the rewrite for free](2026-11-21-pi-cost-seam-is-message-end.md)
- [2026-11-21 — bge-m3 embeddings are not bitwise deterministic, so compare recall scores with a tolerance](2026-11-21-embedding-scores-jitter-between-calls.md)
- [2026-11-22 — A `~/…` token in a skill is a claim that the path exists, and `mem doctor` checks it](2026-11-22-skill-path-tokens-are-claims.md)
- [2026-11-22 — Cloning a macOS .app for a second Dock identity: re-sign the outer bundle only](2026-11-22-cloned-app-resign-outer-bundle-only.md)
- [2026-11-22 — Pi-Harness is a well-built Electron workbench around the pi SDK, and it will fight a nix-managed `~/.pi/agent`](2026-11-22-pi-harness-desktop-superset.md)
- [2026-11-22 — `mem index` reads the apply checkout, so a new learnings entry is invisible until `nr` runs](2026-11-22-mem-index-reads-the-apply-checkout.md)
- [2026-11-24 — A fish function is snapshotted at shell start, so an edited `nr` keeps running the old one](2026-11-24-fish-function-frozen-at-shell-start.md)
- [2026-11-26 — Deep Infra answers a burst of summary calls with a transient 429, and one 429 used to end the stage](2026-11-26-deepinfra-429-is-transient.md)
- [2026-11-26 — ~/bin/mem is a copy, so ~/bin/tests/mem-test.sh tests the applied code and not your edit](2026-11-26-mem-tests-must-run-from-the-worktree.md)
- [2026-11-26 — A background server started inside $(...) keeps the substitution open forever](2026-11-26-backgrounded-server-hangs-cmdsub.md)
