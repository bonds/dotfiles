# bonds/dotfiles

Personal dotfiles for three machines, plus the Nix flake that declares all of
them.

| machine | system | role |
|---|---|---|
| **accismus** | macOS (nix-darwin) | laptop |
| **sophrosyne** | NixOS | server |
| **metanoia** | NixOS | workstation |

**This repo is public.** Only encrypted secrets are tracked — age/agenix for
service credentials, [passage](https://github.com/FiloSottile/passage) for the
rest. `DECISIONS.md` records that and the other trade-offs that look odd until
you know why.

## Layout

| path | what |
|---|---|
| `.config/nix/` | the flake: hosts, modules, packages, agent skills |
| `.config/fish/` | shell config; `conf.d/` is split by concern |
| `.config/{helix,git,ssh,starship,alacritty,atuin,passage}/` | tracked config, used in place |
| `bin/` | cross-platform scripts (`photos-backup`, `hm-links`, `wol`, …) |
| `docs/learnings/` | platform traps, as symptom / cause / fix |
| `AGENTS.md` | how agents should work here |
| `DECISIONS.md` | why the deliberate oddities are deliberate |

Config that home-manager *generates* (`tmux`, `ghostty`, `halloy`,
`what-changed`, `reel-summarize`, `sleepwatcher`, `direnv`) is a symlink into
`/nix/store`. Edit the module in `.config/nix/modules/home/`, not the file that
appears in `$HOME` — `readlink -f` tells you which you are looking at.

## Managing the dotfiles

A **bare repo** at `~/.local/share/dotfiles` with `--work-tree=$HOME`, so no
`.git` directory clutters `$HOME` and tools that walk up looking for a
repository do not trip over one. Untracked files are hidden
(`status.showUntrackedFiles=no`), so `git add` can never stage the whole home
directory — which also means plain `git status` will not show you untracked
files in *any* worktree; use `-uall` when it matters.

In fish a `config` alias does the plumbing:

```fish
config status
config add .config/fish
config commit -m "…"
config push origin; and config push sophrosyne
```

Outside fish there is no alias — spell it out:

```bash
cd ~ && git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME status
```

Two remotes: `origin` (GitHub) and `sophrosyne` (a bare repo on the server whose
`post-receive` hook checks out the work tree). Never force-push: on sophrosyne
that hook would destroy uncommitted work with no recovery.

## The flake

```fish
nr                  # build and switch this machine (Scott runs this one)
nh darwin build     # build-verify only — what agents are allowed to do
```

`nr` is a fish function (`conf.d/15-functions.fish`), like `config` — it does not
exist in bash. `nh` is the nix helper it wraps; `nh darwin build` is the
build-without-activating form, and switching a machine is Scott's call, not an
agent's.

`nix flake check` runs six checks, and `.config/git/hooks/pre-push` runs them
before every push:

| check | what |
|---|---|
| `format-check` | alejandra |
| `deadnix-check` | unused bindings |
| `statix-check` | nix lint |
| `secrets-check` | gitleaks over the tree |
| `what-changed-test` | 166 tests |
| `reel-summarize-test` | 70 tests |

## Agent harness

`.config/nix/pkgs/pi/` declares the [pi](https://github.com/earendil-works/pi)
coding agent: 13 extensions (permission gate, protected paths, git checkpoint,
cost reporting, learnings capture, session recall, plan mode), 5 prompt
templates (`/review`, `/ship`, `/nr`, `/learn`, `/distill`), and 16 routing
evals that make context edits measurable. It is symlinked read-only into
`~/.pi/agent/` at activation, so `pi install` and `pi mcp add` cannot persist —
edit the repo and rebuild.

Skills live once, in `.config/nix/agent-skills/`, and every harness links to
them:

| skill | use it when |
|---|---|
| `code-review` | reviewing a diff before commit, push, or PR |
| `dotfiles-layout` | locating a config, or deciding where a new one belongs |
| `gh-credentials` | `gh` scopes, third-party repos, releases |
| `machines-and-services` | the three machines, backups, services, doas |
| `osaurus-build` | building or testing `~/src/bonds/osaurus` |
| `pi-harness` | editing pi config; tool, cost or session questions |

## Packages

| package | what |
|---|---|
| `nix-what-changed` | LLM-summarized changelogs after a rebuild — see below |
| `reel-summarize` | transcribe + summarize Reels and YouTube with local models |
| `photokit-export` | Swift PhotoKit exporter feeding the photos pipeline |
| `ghosttile`, `raven`, `raven-desktop` | macOS window manager and desktop apps |
| `oxillama`, `laya`, `transcribe-cpp` | local inference helpers |
| `bedrock-server`, `dst-server` | game servers for sophrosyne |
| `rsync-tmbackup` | rsync-based Time Machine style snapshots |
| `mcp-fetch`, `mcp-searxng-search`, `reel-summarize-mcp` | MCP servers |

## what-changed

`what-changed` diffs two nix system closures, finds which packages changed,
fetches their changelogs, and summarizes each using a local LLM (llama.cpp's
OpenAI-compatible API by default; ollama is also supported).

Run it manually after a rebuild:

```fish
sudo nixos-rebuild switch          # or: darwin-rebuild switch
what-changed -1                     # compare current vs 1 generation ago
```

Or with explicit store paths:

```fish
what-changed /nix/store/xxx-darwin-system-26.05 /nix/store/yyy-darwin-system-26.11
```

Other usage:

```fish
what-changed -1                      # current vs 1 generation ago
what-changed -1 -50                  # 1 gen ago vs 50 gens ago
what-changed 2026-05-01              # current vs gen after May 1
what-changed 2026-01-01 2025-06-01  # gen after Jan 1 vs gen after Jun 1
what-changed /nix/store/xxx /nix/store/yyy  # explicit store paths
what-changed --benchmark             # test model performance
what-changed --brief                 # compact output, no bullets
what-changed --json                  # machine-readable output
```

### Features

- **Smart changelog discovery** — checks `meta.changelog`, GitHub releases, changelog files, known wiki pages, and GitHub API
- **LLM summarization** — uses `qwen2.5-7b` via a llama.cpp OpenAI-compatible API by default (configurable: `ollama` is also supported)
- **Caching** — metadata, changelogs, and LLM summaries are cached so repeat runs are instant
- **Output formats** — rich terminal output, `--json`, `--brief`
- **Config file** — `~/.config/what-changed/config.toml`
- **Test suite** — 166 tests, run via `nix flake check`

### Installing in your Nix config

Add as a flake input:

```nix
{
  inputs.what-changed.url = "github:bonds/dotfiles?dir=.config/nix/pkgs/nix-what-changed";
}
```

Use the package:

```nix
{ inputs, pkgs, ... }: {
  environment.systemPackages = [ inputs.what-changed.packages.${system}.default ];
}
```

Or use the module (adds the package plus optional config):

```nix
{ inputs, ... }: {
  imports = [ inputs.what-changed.nixosModules.default ];
  programs.what-changed.enable = true;
  programs.what-changed.settings = {
    model = "qwen2.5-7b";
    timeout = 180;
  };
}
```

### Requirements

- A local LLM server. The default config targets a [llama.cpp](https://github.com/ggml-org/llama.cpp) server exposing the OpenAI-compatible API on port 8080 (e.g. `llama-server --port 8080 --model qwen2.5-7b.gguf`). [ollama](https://ollama.com) is also supported: set `backend = "ollama"` and `host = "http://localhost:11434"`.
- Nix (obviously)
- Python 3.10+ (included via nix package)

### Configuration

```toml
# ~/.config/what-changed/config.toml
model = "qwen2.5-7b"
timeout = 180
prompt_style = "curate"    # curate (default), strict, concise, no-hallucinate, numbered
backend = "openai"         # "openai" for llama.cpp / OpenAI-compatible APIs, or "ollama"
host = "http://localhost:8080"
max_bullets = 5
```

## License

CC0 1.0 Universal — see [LICENSE](LICENSE).
