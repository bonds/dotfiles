# AGENTS.md

> **Also see:** `.config/nix/AGENTS.md` for nix-flake-specific docs — rebuild
> commands, flake structure, per-machine gotchas, and nix conventions.
> `~/DECISIONS.md` for the *why* behind choices that look odd — read it before
> proposing to change one.

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

Declared in `.config/nix/pkgs/pi/` (extensions, prompts, keybindings,
`decisions.md`) and symlinked read-only into `~/.pi/agent/` by
`modules/home/pi.nix`; only `settings.json` is merged, with `jq`, at activation.
So **edit the repo, then `nr`** — `pi install` and `pi mcp add` cannot persist.
The extension inventory, prompt templates, the Deep Infra cost story,
`mcp.json`, and the skills wiring are in the `pi-harness` skill.

Two rules matter more than the inventory:

- Agents may build-verify (`nh darwin build`) but **never run the activating
  rebuild** — see Conventions.
- What you learn about the harness goes into the repo, not into the session
  that discovered it — see **Compounding** below.

## Skills

Canonical skills: `.config/nix/agent-skills/<name>/SKILL.md`, symlinked per
skill into every harness by `modules/home/pi.nix`. A new directory there shows
up everywhere on the next `nr`, with no other edit. Harness paths and the
wiring rules are in the `pi-harness` skill.

| Skill | Use it when |
|---|---|
| `code-review` | reviewing a diff before commit/push/PR — the rule in Conventions |
| `dotfiles-layout` | locating a tracked config file, or deciding where a new one belongs |
| `machines-and-services` | anything touching accismus/sophrosyne/metanoia, firesafe, photos, Minecraft, DST, Nitter, doas |
| `gh-credentials` | filing issues/PRs on third-party repos, or `gh` scope/403 failures |
| `osaurus-build` | building or testing `~/src/bonds/osaurus` |
| `pi-harness` | editing pi config or an extension/skill/prompt; a tool, cost or session question |

Agents without skill support can read `SKILL.md` directly. The `description` is
what routes the model to the skill: say what it does **and** when to use it, and
quote it (`description: "…"`) — an unquoted `key: value` inside it is invalid
YAML and the harness skips the skill silently.

## Compounding

pi has no weight updates. It gets better only because lessons land in files the
next session loads, and there are two kinds, with two homes:

| Lesson | Home | Trigger |
|---|---|---|
| Agent conduct ("never force-push", "doas needs full paths") | `~/.pi/agent/inbox.md` → `/distill` | a tool failed, or the user corrected you |
| Domain knowledge ("`openFile` also delivers argv") | `<repo>/docs/learnings/` | the world surprised you while working |

Agent lessons climb a ladder, and promoting past the current rung is the point:
`AGENTS.md` line → skill → hook/extension → automation. A rule seen twice
belongs on rung 3, and `AGENTS.md` must not grow — move a paragraph into a
skill in the same edit. `~/DECISIONS.md` holds the settled *why*.

Domain learnings climb nothing: they are facts about a project, so they stay
next to the code, indexed in `docs/learnings/README.md`, committed with it, and
superseded rather than deleted. Use the `learning` tool, or `/learn`.

The loop:

- **Capture.** `learnings-capture.ts` writes one line per distinct tool failure
  to the inbox; `corrections-capture.ts` writes one per correction or stated
  rule ("from now on…", "always…"), recording the action being corrected. Read
  it, do not edit it.
- **Distill.** `/distill` clusters the inbox and promotes each item up the
  ladder, then deletes what it processed.
- **Verify.** After changing `AGENTS.md`, a skill description, or
  `DECISIONS.md`, run `~/.config/nix/pkgs/pi/evals/run.sh`. A failure means the
  wording got worse, not the model.
- **Recall.** The `recall` tool searches past session JSONL for earlier work on
  the same problem; use it before re-deriving an answer.

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
- **Log surprises next to the code** — see **Compounding**: domain knowledge to the repo's `docs/learnings/`, agent rules to the inbox. Worked example: `~/src/bonds/polyptych/docs/learnings/`.
- Before committing any changes, run a code review using the current harness's available code-review skill or tool, and ask the user how to proceed
- After each batch of changes, commit and push to all remotes (`config push origin && config push sophrosyne`). Never force-push (`--force` / `config push -f`) to any remote. If sophrosyne rejects the push because of divergent histories (e.g. a `git commit --amend` or rebase on either side), pull or merge first to reconcile. The sophrosyne bare repo has a `post-receive` hook that checks out the work tree on push — no special `receive.denyCurrentBranch` config needed.
- **`git push` over SSH needs Secretive TouchID — rebuilds do NOT.** Rebuilds (`nr` / `darwin-rebuild` / `nixos-rebuild`) are passwordless everywhere: `doas` noPass rules (full paths for `nixos-rebuild`/`nh` on sophrosyne) and passwordless sudo on accismus — but passwordless does not mean agent-run: **Scott runs the activating rebuild himself with `nr`**; agents may do build-only verification (e.g. non-activating `nh darwin build`) but must NOT run the switch/rebuild on his behalf (authoritative rule: `.config/nix/AGENTS.md` → Commands). The ONLY non-passwordless step is `git push` over SSH (GitHub and the `scott@home.ggr.com` bare repo): Secretive only signs after TouchID approval, and a fresh Hermes agent shell usually has **no identities** (`ssh-add -l` → "The agent has no identities"; `ssh github.com:22` may time out; `ssh.github.com:443` connects but Secretive "refused operation"). The `gh` CLI token is often read-only and 403s on push.
- **TouchID is interactive — never wait for it in a loop, don't "resolve" it by retrying.** If a push fails with `Permission denied (publickey)`/403, the user needs to approve via TouchID and they may be AFK; ask them to push when they're back (e.g. `cd ~/Documents/undated/repos/<repo> && git push origin main`), or note it and move on. Don't assume a broken remote, and don't "resolve" a failed push by running the rebuild yourself — TouchID only guards `git push`; activating rebuilds are Scott's to run (rule above).
- Code repos I'm actively working on live in `~/src/bonds/<name>/` for bonds projects, otherwise `~/Documents/undated/repos/<name>/` (a stale polyptych copy sits in the latter; the live one is `~/src/bonds/polyptych`)
- **Nix deployments to remote machines:** Never attempt a cross-build from the local machine (aarch64-darwin cannot build x86_64-linux derivations that have `allowSubstitutes = false`, such as `arion-compose`). Instead, push the commit and then SSH directly to the target machine and a rebuild via **`fish -c 'nr'`** (runs detached in tmux session `nr-build`, mirroring local agent use) — or `fish -i -c 'nr'` to wait for the result: `ssh sophrosyne "fish -c 'nr'"`. `nr` handles the split build + exact-path `doas` switch, matching the noPass rules. Only fall back to `/run/current-system/sw/bin/nixos-rebuild` directly if `nr` itself is broken. Use the full `/run/current-system/sw/bin/nixos-rebuild` path if you do call it directly, so the `noPass` doas rule matches.
- **Remote rebuilds must run to completion — a background/no-TTY SSH job silently no-ops.** Any remote deploy that can't get a TTY or forward the agent (e.g. Hermes running it in `terminal(background=true)`, or a bare `nixos-rebuild` with `doas` when the agent isn't forwarded) fails to authenticate with doas, prints **nothing, and exits 0 while creating NO new generation** — it looks like success but changes nothing. Run the deploy in the foreground and verify a new generation actually landed: `readlink -f /nix/var/nix/profiles/system` (must differ from before) and look for the `Done. The new configuration is ...` line. Don't trust the exit code alone.
- **sophrosyne's shell is fish.** Inline one-liners passed to `ssh sophrosyne '...'` must be fish-compatible: bash-isms abort the whole line before anything runs — e.g. appending `echo "RC=$?"` makes fish error on `$?` (treated as a command), killing the entire remote command. Use `$status` for exit codes on the remote side.
- **Version bump policy for `what-changed`:** Bump the minor version (e.g. `0.4.0` → `0.5.0`) whenever user-facing features, behavior, or dependencies change. Bug fixes and internal refactors get a patch if there's a prior tagged release, otherwise batch into the next minor. Keep `default.nix` and `pyproject.toml` in sync.
- **`config add` WITHOUT `-f` for `nix-what-changed`:** The directory has a `.gitignore` that excludes `__pycache__/`. Using `config add -f` overrides it and tracks `.pyc` files, which then need a cleanup commit. Use plain `config add .config/nix/pkgs/nix-what-changed/what_changed/<file>.py` for individual files, or `config add .config/nix/pkgs/nix-what-changed/` (without `-f`) to respect the gitignore. A pre-commit hook (`.config/git/hooks/pre-commit`) rejects `.pyc` files automatically if you forget.
- **`flake.lock` changes:** When a commit includes a `flake.lock` update (e.g. after `nr --update`), push both remotes normally (`config push origin && config push sophrosyne`). The sophrosyne post-receive hook does a force checkout so there is no "dirty work tree" rejection. If sophrosyne independently updated its flake.lock (via `nr --update` on the server), the next push from accismus will overwrite it — this is intentional. If you need sophrosyne to pull changes without accismus pushing:
  1. `ssh sophrosyne "config pull origin main"`
  2. The post-receive hook won't fire (it only runs on push), so the work tree will be updated by the checkout. If for some reason the work tree is stale: `ssh sophrosyne "cd ~ && git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME checkout -f main"`

### doas privilege escalation

doas is layered: `noPass` rules for `systemctl`, `journalctl`, `nixos-rebuild`
and `nh` (no TouchID), `pam_ssh_agent_auth` for everything else. Two traps: rule
matching needs the **full path** (`doas /run/current-system/sw/bin/systemctl
restart syncthing`, never the bare name), and `args` is an exact match on the
whole argument list, not a prefix. Agent forwarding is required for the TouchID
path. Details, including the `/etc/ssh/authorized_keys.d/scott` key file: the
`machines-and-services` skill.

## Editable worktree (`live`)

The bare repo lives at `~/.local/share/dotfiles`. Agent edits are made in a
linked worktree at `~/.local/share/dotfiles/live` (checked out on `main`);
`$HOME` is the live tree, used via `--work-tree=$HOME` — not a git worktree.

To sync `$HOME` to the tip of `main` (plain `git checkout main` only prints
"Already on 'main'" and changes nothing):

```bash
git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME checkout main -- .
```
