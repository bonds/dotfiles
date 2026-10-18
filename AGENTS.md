# AGENTS.md

> **Also see:** `.config/nix/AGENTS.md` for nix-flake-specific docs — rebuild
> commands, flake structure, per-machine gotchas, and nix conventions.

Personal dotfiles tracked via a **bare git repo** at `~/.local/share/dotfiles` on
accismus and sophrosyne, managed through a `config` alias
(fish-only, see below).  This avoids a `.git/` directory cluttering `$HOME`, which
was causing issues with various tools.  The approach is the one described in the
[Atlassian dotfiles
tutorial](https://www.atlassian.com/git/tutorials/dotfiles).

## Git tracking strategy

The bare repo lives at `~/.local/share/dotfiles/` on accismus (moved from
`~/.config/dotfiles/` on 2026-10-11) and uses `--work-tree=$HOME` so
that tracked files appear directly in `$HOME`.  Untracked files in `$HOME` are
hidden (`status.showUntrackedFiles = no` set in the bare repo's config).

The `config` alias (defined in `.config/fish/conf.d/10-aliases.fish`) wraps
every git command with the right `--git-dir` and `--work-tree`.  It resolves the
git dir by existence, so the same file is correct on every machine and during a
move:

```fish
if test -d $HOME/.local/share/dotfiles
    alias config='git --git-dir=$HOME/.local/share/dotfiles/ --work-tree=$HOME'
else
    alias config='git --git-dir=$HOME/.config/dotfiles/ --work-tree=$HOME'
end
```

**Everything you do with `config` works just like normal git** — `config status`,
`config add`, `config commit`, `config push`, `config log`, etc.  Only the
alias changes; the subcommands are the same git you already know.

> **⚠️ `config` is a fish-ONLY alias.** It does not exist in bash/zsh/sh, and it
> is **not** available in Hermes' `terminal` tool or any non-fish shell; there
> it errors with `config: command not found` (and, worse, a script invoking it
> can silently no-op, as with `nr`). From any shell use the full invocation
> instead:
>
> ```bash
> # always `cd ~` first so relative paths resolve
> # accismus and sophrosyne: ~/.local/share/dotfiles
> GITDIR=$HOME/.local/share/dotfiles
> cd ~ && git --git-dir=$GITDIR --work-tree=$HOME status
> git --git-dir=$GITDIR --work-tree=$HOME add <path>
> git --git-dir=$GITDIR --work-tree=$HOME commit -m "..."
> git --git-dir=$GITDIR --work-tree=$HOME push origin main
> git --git-dir=$GITDIR --work-tree=$HOME push sophrosyne main
> ```
>
> Every `config` example below works with this `git --git-dir=... --work-tree=...`
> prefix substituted for `config`. (Prefer `cd ~` first; relative paths in the
> dotfiles worktree otherwise fail to resolve.)

**To see tracked files:** `config ls-files`
**To add new files to tracking:** `config add <path>` (the bare repo config
hides untracked files from status, so `git add` won't accidentally stage
everything)
**To untrack a file:** `config rm --cached <path>` — the file stays on disk
but is no longer managed.

## Tracked config layout

The per-file inventory lives in the `dotfiles-layout` skill, and machine /
service details in `machines-and-services` (both in `.config/nix/agent-skills/`,
loaded on demand). Orientation:

- Shell: `.config/fish/` — `config.fish` entry point, `conf.d/` split by concern
- Terminal: `.config/{alacritty,ghostty}/`; tmux via nix (`modules/home/tmux.nix`)
- Editor: `.config/helix/`; `$EDITOR` is `hx`
- Git: `.config/git/` — global config, `ignore`, `hooks/`
- SSH: `.config/ssh/` — `config`, `keys` (symlinked to `~/.ssh/authorized_keys`)
- Nix: `.config/nix/` — the whole flake; see its own `AGENTS.md`
- Scripts: `bin/` plus `bin/{darwin,linux,openbsd}/`

Keep this list short. Detail belongs in the skills, not here.

## GitHub credentials (`gh`)

Two tokens, deliberately separate; **neither is stored in this repo** (it is
public). Fine-grained PAT in the `gh` keyring for Scott's own repos; classic
`public_repo` token in the macOS Keychain behind the `gh-public` wrapper for
third-party public repos. Full setup, rotation, and the gotchas are in the
`gh-credentials` skill.

## Osaurus repo (bonds/osaurus)

Local working copy at `~/src/bonds/osaurus`; feature branches off `main`, pushed
to `origin` for PRs. The repo's own `AGENTS.md` has its proof rules — read it
first. Build/test reality under Xcode 26.3 / Swift 6.2.4 (Debug-only tests, the
vmlx patch, sandboxed `swift test` invocation) is in the `osaurus-build` skill.

## pi coding agent

Config is declarative: `modules/home/pi.nix` (accismus only) symlinks
read-only resources out of `.config/nix/pkgs/pi/` and merges the rest into
`~/.pi/agent/settings.json`.

| Path | Contents |
|---|---|
| `pkgs/pi/extensions/` | `protected-paths.ts` (secrets/`.git`/`node_modules` writes blocked), `permission-gate.ts` (confirms `rm -rf`, `sudo`/`doas`, force-push, disk ops, and any `nr`/`*-rebuild switch` activation), `git-checkpoint.ts`, `dirty-repo-guard.ts`, `reported-cost.ts` (overrides pi's list-price cost with Deep Infra's per-request `usage.estimated_cost`), `notify.ts` (OSC 777 desktop notification when a run settles), `custom-footer.ts` (`/footer` toggles a branch + tokens + cost footer), `plan-mode/` (read-only `/plan` mode, `ctrl+alt+p`) |
| `.config/nix/agent-skills/` | Shared by every agent (see **Skills** below): `code-review`, `dotfiles-layout`, `machines-and-services`, `gh-credentials`, `osaurus-build` |
| `pkgs/pi/prompts/` | `/review`, `/ship` (review → verify → commit → push both remotes), `/nr` (build-only, hand activation to Scott), `/learn` (docs/learnings entry) |
| `pkgs/pi/keybindings.json` | `ctrl+shift+n` new session, `ctrl+shift+r` resume, `ctrl+shift+t` tree |
| `models.json` (generated) | Deep Infra: `DeepSeek-V4.1-Flash-1017` (default, vision) and `DeepSeek-V4-Flash` (cheap, text-only) for the `ctrl+p` cycle; key read at request time from `/run/agenix/hermes-deepinfra` |
| `mcp.json` (generated) | `reel-summarize` → `http://sophrosyne.taileafac.ts.net:8892/sse` (streamable HTTP; `/sse` is just the path) |

Because these are nix-store symlinks, `pi install` and `pi mcp add` cannot
persist: edit the repo and re-run `nr`. `settings.json` stays writable (pi
writes `lastChangelogVersion` itself), so it is merged with `jq` in
`home.activation.piSettings` — add new default settings there, not by hand.
It also sets `enabledModels: ["deepinfra/**"]` (so `ctrl+p` cycles both models
instead of being a no-op — `**`, since model IDs contain a slash and the glob
does not cross it) and `defaultTools: ["+codemode"]` (call tools from a script
rather than one round-trip each).

**Cost display:** pi prices every request as `tokens × model.cost` (USD per
million tokens) and ignores any cost the provider reports; `deepinfra` has no
pi.dev catalog entry, so `models.json` is the only price source. Hence both
halves of the setup: `models.json` carries Deep Infra's **list** prices, and
`reported-cost.ts` rewrites each finished message's `usage.cost` from Deep
Infra's own `usage.estimated_cost` (this model carries `discount: 0.51`, so the
billed amount is ~0.49× list price — a static price alone overstates cost 2×).

Verifying without activating: `nh darwin build .` from `.config/nix` shows the
`hm_*` files. To test resources before a rebuild, pass them explicitly (from
`~`): `pi -e .config/nix/pkgs/pi/extensions/protected-paths.ts --skill
.config/nix/agent-skills --prompt-template .config/nix/pkgs/pi/prompts`, or
point `PI_CODING_AGENT_DIR` at a scratch directory.

## Skills

The canonical skills live in `.config/nix/agent-skills/<name>/SKILL.md` (Agent
Skills format), tracked here and symlinked per skill into each harness by
`modules/home/pi.nix`. Each agent's own directory stays real, so agents can
still add their own skills.

| Skill | Use it when |
|---|---|
| `code-review` | reviewing a diff before commit/push/PR — the rule in Conventions |
| `dotfiles-layout` | locating a tracked config file, or deciding where a new one belongs |
| `machines-and-services` | anything touching accismus/sophrosyne/metanoia, firesafe, photos, Minecraft, DST, Nitter |
| `gh-credentials` | filing issues/PRs on third-party repos, or `gh` scope/403 failures |
| `osaurus-build` | building or testing `~/src/bonds/osaurus` |

Wiring (one symlink per skill, so a skill added here appears everywhere on the
next rebuild — no other edit needed):

| Harness | Directory |
|---|---|
| pi | `~/.agents/skills/` (the Agent Skills location — pi reads it natively; do **not** also link `~/.pi/agent/skills`, the duplicate makes every skill collide at startup) |
| Agent Skills standard | `~/.agents/skills/` |
| Claude Code | `~/.claude/skills/` |
| opencode | `~/.config/opencode/skills/` |
| Hermes | `~/.hermes/skills/dotfiles/` (category dir + `DESCRIPTION.md`) |

**Agents without skill support** (or a harness that ignores the directory) can
still use them: read `.config/nix/agent-skills/<name>/SKILL.md` directly. That is
why this table exists in `AGENTS.md` rather than only in the nix module.

Adding a skill: create `.config/nix/agent-skills/<name>/SKILL.md` with `name` and
`description` frontmatter, then `nr`. Keep the description to what it does *and*
when to use it — that is what routes the model to it. Quote the description
(`description: "…"`): an unquoted `key: value` inside it is invalid YAML and
the harness skips the skill silently.

## Conventions

- **Shell commands must be fish-compatible.** The main interactive shell is fish; zsh only exists as a minimal entry point that immediately execs fish. Use `and` instead of `&&`, `(cmd)` instead of `$(cmd)`, `set -x FOO bar` instead of `export FOO=bar`, and avoid bashisms.
- **Fish gotcha — `if count $argv ...` mis-evaluates.** Do not write `if count $argv -lt 1`; `count` consumes the operator and bound as extra argv, so the condition misbehaves (observed: `count a b c` returned 3 but the `-lt 1` branch still fired). Always assign first: `set -l argc (count $argv)` then `if test $argc -lt 1`.
- **Fish gotcha — `$VAR` used as a command must be a single token:** invoking a non-atomic value as a command (e.g. `$EDITOR file` where `$EDITOR = "echo hi"`) fails — fish looks up the whole string as one command name. This is fine in practice since `$EDITOR` is `hx`, but keep any command-valued var a single token.
- **Fish gotcha — use `date`, not `strftime`:** `strftime` is not a fish builtin. Inline today's date with `(date "+%Y-%m-%d")`. (fish's `date` is the system command.)
- `$EDITOR` is helix (`hx`), set in fish config
- SSH agent via Secretive (TouchID/T2 secure enclave) on macOS
- Font: Liga SFMono Nerd Font
- Shell prompt: starship with UTF-8 symbols (falls back to plain on non-UTF-8 terminals)
- Shell history: atuin (synced database)
- Password management: passage (age-encrypted, not GPG)
- Nix formatting: alejandra (`nix fmt` — unreliable, prefer `alejandra <file>` directly)
- **Prefer `rg` (ripgrep) and `fd` over `grep` and `find`.** Both are installed and much faster. Use `rg` for content search and `fd` for file discovery; fall back to `grep`/`find` only where they're unavailable (e.g. a minimal remote host).
- **Tag and release when you bump a version.** A Git tag is not a GitHub release — create the release too, with notes built from `git log` since the previous tag (auto-generated notes are empty on repos with no PRs): `gh release create <tag> --notes-file <file>`. Creating releases needs `Contents: write`; the fine-grained `gh` PAT may lack it (HTTP 403) — the classic `public_repo` token in the `gh-public-token` Keychain item works for public repos. Worked example: `~/src/bonds/polyptych/AGENTS.md` → Releasing.
- **Log surprises and lessons learned next to the code.** When you hit something non-obvious — undefined behavior, a platform quirk, an API change, a debugging trap — write a short entry in that repo's `docs/learnings/` (index in `docs/learnings/README.md`) so the knowledge accumulates instead of being re-discovered. Keep it brief: symptom, cause, fix/takeaway. Example: `~/src/bonds/polyptych/docs/learnings/`.
- Before committing any changes, run a code review using the current harness's available code-review skill or tool, and ask the user how to proceed
- After each batch of changes, commit and push to all remotes (`config push origin && config push sophrosyne`). Never force-push (`--force` / `config push -f`) to any remote. If sophrosyne rejects the push because of divergent histories (e.g. a `git commit --amend` or rebase on either side), pull or merge first to reconcile. The sophrosyne bare repo has a `post-receive` hook that checks out the work tree on push — no special `receive.denyCurrentBranch` config needed.
- **`git push` over SSH needs Secretive TouchID — rebuilds do NOT.** Rebuilds (`nr` / `darwin-rebuild` / `nixos-rebuild`) are passwordless everywhere: `doas` noPass rules (full paths for `nixos-rebuild`/`nh` on sophrosyne) and passwordless sudo on accismus — but passwordless does not mean agent-run: **Scott runs the activating rebuild himself with `nr`**; agents may do build-only verification (e.g. non-activating `nh darwin build`) but must NOT run the switch/rebuild on his behalf (authoritative rule: `.config/nix/AGENTS.md` → Commands). The ONLY non-passwordless step is `git push` over SSH (GitHub and the `scott@home.ggr.com` bare repo): Secretive only signs after TouchID approval, and a fresh Hermes agent shell usually has **no identities** (`ssh-add -l` → "The agent has no identities"; `ssh github.com:22` may time out; `ssh.github.com:443` connects but Secretive "refused operation"). The `gh` CLI token is often read-only and 403s on push.
- **TouchID is interactive — never wait for it in a loop, don't "resolve" it by retrying.** If a push fails with `Permission denied (publickey)`/403, the user needs to approve via TouchID and they may be AFK; ask them to push when they're back (e.g. `cd ~/Documents/undated/repos/<repo> && git push origin main`), or note it and move on. Don't assume a broken remote, and don't "resolve" a failed push by running the rebuild yourself — TouchID only guards `git push`; activating rebuilds are Scott's to run (rule above).
- Code repos I'm actively working on live in `~/Documents/undated/repos/`
- **Nix deployments to remote machines:** Never attempt a cross-build from the local machine (aarch64-darwin cannot build x86_64-linux derivations that have `allowSubstitutes = false`, such as `arion-compose`). Instead, push the commit and then SSH directly to the target machine and a rebuild via **`fish -c 'nr'`** (runs detached in tmux session `nr-build`, mirroring local agent use) — or `fish -i -c 'nr'` to wait for the result: `ssh sophrosyne "fish -c 'nr'"`. `nr` handles the split build + exact-path `doas` switch, matching the noPass rules. Only fall back to `/run/current-system/sw/bin/nixos-rebuild` directly if `nr` itself is broken. Use the full `/run/current-system/sw/bin/nixos-rebuild` path if you do call it directly, so the `noPass` doas rule matches.
- **Remote rebuilds must run to completion — a background/no-TTY SSH job silently no-ops.** Any remote deploy that can't get a TTY or forward the agent (e.g. Hermes running it in `terminal(background=true)`, or a bare `nixos-rebuild` with `doas` when the agent isn't forwarded) fails to authenticate with doas, prints **nothing, and exits 0 while creating NO new generation** — it looks like success but changes nothing. Run the deploy in the foreground and verify a new generation actually landed: `readlink -f /nix/var/nix/profiles/system` (must differ from before) and look for the `Done. The new configuration is ...` line. Don't trust the exit code alone.
- **sophrosyne's shell is fish.** Inline one-liners passed to `ssh sophrosyne '...'` must be fish-compatible: bash-isms abort the whole line before anything runs — e.g. appending `echo "RC=$?"` makes fish error on `$?` (treated as a command), killing the entire remote command. Use `$status` for exit codes on the remote side.
- **Version bump policy for `what-changed`:** Bump the minor version (e.g. `0.4.0` → `0.5.0`) whenever user-facing features, behavior, or dependencies change. Bug fixes and internal refactors get a patch if there's a prior tagged release, otherwise batch into the next minor. Keep `default.nix` and `pyproject.toml` in sync.
- **`config add` WITHOUT `-f` for `nix-what-changed`:** The directory has a `.gitignore` that excludes `__pycache__/`. Using `config add -f` overrides it and tracks `.pyc` files, which then need a cleanup commit. Use plain `config add .config/nix/pkgs/nix-what-changed/what_changed/<file>.py` for individual files, or `config add .config/nix/pkgs/nix-what-changed/` (without `-f`) to respect the gitignore. A pre-commit hook (`.config/git/hooks/pre-commit`) rejects `.pyc` files automatically if you forget.
- **`flake.lock` changes:** When a commit includes a `flake.lock` update (e.g. after `nr --update`), push both remotes normally (`config push origin && config push sophrosyne`). The sophrosyne post-receive hook does a force checkout so there is no "dirty work tree" rejection. If sophrosyne independently updated its flake.lock (via `nr --update` on the server), the next push from accismus will overwrite it — this is intentional. If you need sophrosyne to pull changes without accismus pushing:
  1. `ssh sophrosyne "config pull origin main"`
  2. The post-receive hook won't fire (it only runs on push), so the work tree will be updated by the checkout. If for some reason the work tree is stale: `ssh sophrosyne "cd ~ && git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME checkout -f main"`

### doas privilege escalation

doas is configured with layered privilege:
- **noPass commands** — `systemctl`, `journalctl`, `nixos-rebuild`, `nh` — skip PAM entirely, no TouchID prompt.
- **Everything else** — authenticates via `pam_ssh_agent_auth`, which challenges the forwarded SSH agent (Secretive on accismus). Expect a TouchID prompt per operation.

Key constraints:
- **doas does NOT resolve bare command names via PATH for rule matching.** Always use the full path: `doas /run/current-system/sw/bin/systemctl restart syncthing`, NOT `doas systemctl restart syncthing`. The existing `nixos-rebuild`/`nh` noPass rules follow the same convention (full path).
- **`args` in doas.conf is an exact match** on the full argument list, not a prefix match. `args restart` only matches `doas cmd restart` (no additional args). All current noPass rules are scoped to `cmd`-level only (no `args`) for this reason.
- **Agent forwarding is required** for TouchID-for-doas. SSH config sets `ForwardAgent yes` for sophrosyne. If for some reason the agent isn't forwarded, doas falls back to password prompt (works interactively only).

The keys file for `pam_ssh_agent_auth` is at `/etc/ssh/authorized_keys.d/scott` (root-owned, outside the nix store — an activation script copies it on each switch to avoid group-writable /nix/store directory rejections).

## Editable worktree (`live`)

The bare repo lives at `~/.local/share/dotfiles`. Agent edits are made in a
linked worktree at `~/.local/share/dotfiles/live` (checked out on `main`);
`$HOME` is the live tree, used via `--work-tree=$HOME` — not a git worktree.

To sync `$HOME` to the tip of `main` (plain `git checkout main` only prints
"Already on 'main'" and changes nothing):

```bash
git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME checkout main -- .
```
