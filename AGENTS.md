# AGENTS.md

> **Also see:** `.config/nix/AGENTS.md` for nix-flake-specific docs — rebuild
> commands, flake structure, per-machine gotchas, and nix conventions.
> `~/DECISIONS.md` for the *why* behind choices that look odd — read it before
> proposing to change one.

Personal dotfiles tracked via a **bare git repo** on accismus and sophrosyne,
managed through a `config` alias (fish-only, see below). Since **2026-10-31**
accismus nests the repo: git dir `~/.local/share/dotfiles/bare`, a **linked edit
checkout** at `~/.local/share/dotfiles/worktree`, and `$HOME` as the **apply
checkout** that `nr` builds. sophrosyne still keeps a flat bare repo at
`~/.local/share/dotfiles` with work tree `$HOME`.  Nesting keeps a `.git`
directory out of `$HOME` while giving edits a checkout of their own; the
underlying approach is the one described in the [Atlassian dotfiles
tutorial](https://www.atlassian.com/git/tutorials/dotfiles).

## Git tracking strategy

Git dir `~/.local/share/dotfiles/bare`, checked out into `$HOME`
(`git --git-dir=… --work-tree=$HOME`) — that is the **apply** side, the tree `nr`
builds. Untracked files are hidden (`status.showUntrackedFiles = no`), which
keeps `git status` readable but does **not** make `git add -A` safe: stage
explicit paths, always. The `config` alias wraps git with the right `--git-dir`
and `--work-tree`, and **it is fish-only** — from bash or a script use the full
`git --git-dir=... --work-tree=...` form from `$HOME`, so pathspecs resolve. It
resolves the git dir by existence, so the same file is correct on every machine
and mid-move.

Alias mechanics, the non-fish invocation, and the add/untrack/sync recipes: the
`dotfiles-layout` skill.

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
| `nix-updates` | `nr --update` behaviour: a dependency bump that failed to build, a pin added or expired, an overlay release that builds but is broken, or touching `nr-pins`/`flake-pins.json`/`verify-*.sh` |

Agents without skill support can read `SKILL.md` directly. The `description` is
what routes the model to the skill: say what it does **and** when to use it, and
quote it (`description: "…"`) — an unquoted `key: value` inside it is invalid
YAML and the harness skips the skill silently.

## Compounding

Two kinds of lesson, two homes: agent conduct goes to the inbox (`mem inbox add`,
drained by `mem distill`); domain knowledge goes to `<repo>/docs/learnings/`. The
rung ladder (AGENTS.md -> skill -> hook -> automation), `mem recall` across every
harness, and the rest of the shared store are in the `memory` skill.

**AGENTS.md must not grow: every addition is paid for by moving a paragraph into a
skill in the same edit.** `mem doctor` reports the always-loaded budget.

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
- **Nix repo work — `flake.lock`, version bumps, releasing, packaging: read `.config/nix/AGENTS.md`** (it loads automatically when you are in that tree).
- **Remote deploys, rebuild verification and sophrosyne's shell: the `machines-and-services` skill.**
- **Prefer `rg` (ripgrep) and `fd` over `grep` and `find`.** Both are installed and much faster. Use `rg` for content search and `fd` for file discovery; fall back to `grep`/`find` only where they're unavailable (e.g. a minimal remote host). Never print a whole large document into the transcript: tool output is capped at 256 KiB, and a truncated JSON parse fails at `char 262144` — select fields (`jq`, `python3 -c`) or write to a file instead.
- **Log surprises next to the code** — see **Compounding**: domain knowledge to the repo's `docs/learnings/`, agent rules to the inbox. Worked example: `~/src/bonds/polyptych/docs/learnings/`.
- Before committing any changes, run a code review using the current harness's available code-review skill or tool, and ask the user how to proceed
- After each batch of changes, commit and push to all remotes (`config push origin && config push sophrosyne`). Never force-push (`--force` / `config push -f`) to any remote. If sophrosyne rejects the push because of divergent histories (e.g. a `git commit --amend` or rebase on either side), pull or merge first to reconcile. The sophrosyne bare repo has a `post-receive` hook that checks out the work tree on push — no special `receive.denyCurrentBranch` config needed.
- **Rebuilds are Scott's; pushes need his TouchID.** `nr` / `darwin-rebuild` / `nixos-rebuild` are passwordless, but passwordless is not permission: agents verify with `nh darwin build` and hand over the switch. `git push` over SSH is the one step needing TouchID approval via Secretive, and the `gh` token is often read-only (403). A failed push is a hand-off, not a retry loop: `Permission denied (publickey)`, `Connection closed by … port 22`, or a 403 all mean the approval prompt went unanswered — ask Scott to push when he's back; once he is, `ssh-add -l` plus **one** retry separates an empty agent from an unanswered prompt. Never "resolve" it by running the rebuild yourself. Signatures and diagnosis: `docs/learnings/2026-10-19-secretive-touchid-closes-the-connection.md`.
- **Never pipe a state-changing command to `tail`/`rg`/`sed`.** The pipeline reports the *last* command's status, so `git push … | tail` exits 0 even when the push failed — and `learnings-capture.ts` never sees the failure. Verify with `rev-parse origin/main` (one ref per call — `--short` rejects multiple), or use `pipefail` / `$pipestatus[1]`. See `docs/learnings/2026-10-19-pipe-masks-exit-code.md`.
- **Write multi-line code to a file, not inline.** `python3 -c`, SQL built inside a shell string, and heredocs with nested quotes all fail on an empty or misquoted variable — `WHERE id = $x` silently becomes a syntax error. Assert a value is non-empty before it lands in generated code.
- **A negative result is not proof.** Empty `rg`/`grep`/`sqlite3` output means the tool found nothing *it could see*: confirm it can read the file before concluding absence, and read a store's source before designing around its schema.
- Active code repos live in `~/src/` (`~/src/bonds/<name>/`, `~/src/hihello`). `~/Documents/undated/repos/` is an **archive** — read-only reference, never work in it, never delete it; see the `dotfiles-layout` skill.
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

## Where tracked files are edited, and how they get applied

Two checkouts of the same bare repo, with different jobs:

| path | role |
|---|---|
| `$HOME` | **apply target** — `config checkout main -- .` writes the committed tree here, and `nr` builds it |
| `~/.local/share/dotfiles/worktree` | **edit target** — every edit is made here (a linked worktree of the bare repo) |

Sequence: **edit in `worktree/` → commit → push `origin` and `sophrosyne` →
`cd ~ && config checkout main -- .` → Scott runs `nr`.**

```fish
# edit and commit in the checkout — plain git, it is a worktree of the same repo
cd $HOME/.local/share/dotfiles/worktree
git add .config/fish/conf.d/15-functions.fish
git commit -m "…"
git push origin main; and git push sophrosyne main

cd ~; and config checkout main -- .   # apply, then `nr`
```

`config` is `git --git-dir=~/.local/share/dotfiles/bare --work-tree=$HOME`, so it
is the alias for the **apply** side and for repo-level queries (`config log`,
`config push`, `config status`). To stage or commit edits, use plain git in the
checkout — `config add` there would be staging against `$HOME`, and passing
`--git-dir=…/bare` is the same mistake: the two checkouts have separate indexes
(`bare/index` vs `bare/worktrees/worktree/index`), so the explicit form stages
and commits the *apply* side's view.

`nr` checks both trees on every run, in ~30 ms, and says so when either is off:

- `WARNING $HOME does not match the committed tree` — the apply side is behind
  `main` or edited in place: run the `config checkout main -- .` line above.
- `WARNING worktree/ (edit tree) …` — commit the edits there, or, if that tree is
  merely stale after a bump committed from `$HOME` (that is where `nr --update`
  commits, deliberately: it commits what it built and verified), sync it with
  `git -C ~/.local/share/dotfiles/worktree reset --hard main`.

A `live` worktree under `~/.local/share/dotfiles/live` existed until 2026-10-19
and was removed because it had drifted to 69 staged files behind `main`, so an
agent editing it would have committed reverts. The 2026-10-31 layout recreates
that position deliberately, which is why `worktree/` is the only place edits
belong and why the two guards exist rather than a rule saying "no second
checkout".
