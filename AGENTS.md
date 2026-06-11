# AGENTS.md

Personal dotfiles repo — this is `$HOME` on each machine, but only a curated subset of files is tracked via git.

## Git tracking strategy

All untracked files are hidden (`status.showUntrackedFiles = no` in `.config/git/config`). Only files explicitly `git add`ed are tracked. The global gitignore (`.config/git/ignore`) additionally ignores `.DS_Store`, `.vscode`, `__pycache__/`, and `**/.claude/settings.local.json`.

**To see tracked files:** `git ls-files`
**To add new files to tracking:** `git add -f <path>` (normal `git add` works too since untracked files are shown as ignored)
**To untrack a file:** `git rm --cached <path>` — the file stays on disk but is no longer managed. Do NOT add it to `.config/git/ignore`; the "hide all untracked" strategy makes that unnecessary.

## Tracked config layout

### Shell
- `.zshrc` — minimal zsh entry point (sources nix, execs fish)
- `.config/fish/config.fish` — entry point, delegates to `conf.d/`
- `.config/fish/conf.d/` — organized fish config split by concern:
  - `00-paths.fish` — env vars, PATH
  - `05-editor.fish` — EDITOR selection
  - `10-aliases.fish` — aliases
  - `15-functions.fish` — custom functions (ls, e, tree, ping, nr, hr, age)
  - `20-ssh.fish` — SSH_AUTH_SOCK (Secretive on macOS)
  - `30-interactive.fish` — starship, atuin, auto-tmux, fzf opts
  - `40-lm-studio.fish` — LM Studio CLI PATH (isolated from tracked files)
- `.config/fish/fish_plugins` — fish plugin list
- `.config/starship/` — prompt configs: `darwin.toml`, `linux.toml`, `openbsd.toml`, `plain.toml` (fallback when no UTF-8)
- `.config/atuin/config.toml` — shell history database config

### Terminal
- `.config/alacritty/alacritty.toml` — Alacritty terminal emulator (font, window size, clipboard)
- `.config/ghostty/config` — Ghostty terminal emulator (font, window size)
- tmux config managed via nix/home-manager (`modules/home/tmux.nix`) — catppuccin frappe theme, truecolor, cpu/ram/battery modules

### Editor
- `.config/helix/config.toml` — Helix editor (soft wrap)
- `.config/helix/languages.toml` — Helix language config

### Git
- `.config/git/config` — per-repo git config (user identity, `showUntrackedFiles = no`)
- `.config/git/ignore` — global gitignore for this repo

### SSH
- `.config/ssh/config` — SSH client config (Secretive agent on macOS, ControlMaster for `*.ggr.com`/`*.local`, auto-tmux on remote connections, port forwarding)
- `.config/ssh/keys` — authorized SSH keys (content tracked in git)
- `.ssh/authorized_keys` — symlink to `~/.config/ssh/keys`, created by nix activation (not tracked in git)

### Nix
- `.config/nix/` — **full nix flake for all machines** (see `.config/nix/AGENTS.md` for detailed docs)
  - Flake for: laptop (accismus/darwin), server (sophrosyne/NixOS), workstation (metanoia/NixOS)
  - `nr` fish function wraps `nh` for rebuilds
- `.config/nix/pkgs/nix-what-changed/` — **`what-changed` tool** — Ported from fish to Python (v0.5.0).
  - Lives at `pkgs/nix-what-changed/` inside the dotfiles flake.
  - Also publishable as a standalone flake: `github:bonds/dotfiles?dir=.config/nix/pkgs/nix-what-changed`.
  - Shows LLM-summarized changelogs after `nr` via `what-changed <old-closure> <new-closure>`.
  - Model: `qwen2.5:1.5b` (ollama) — fastest acceptable quality. Only switch to models at **same speed or faster** with higher benchmark scores. Config at `~/.config/what-changed/config.toml`.
- Benchmark: `what-changed --benchmark [--models m1,m2]` compares speed, quality, bullet accuracy, and word merges. Run before switching default model.
  - Supports ollama + OpenAI-compatible backends. Caches results in `~/.cache/what-changed/`.
  - NixOS/darwin module: `programs.what-changed.enable`.
  - `nix flake check` runs alejandra format check, Python syntax check, and pytest suite.
  - Supports ollama + OpenAI-compatible backends. Caches results in `~/.cache/what-changed/`.

### Haskell
- `.config/ghc/ghci.conf` — GHCi config
- `.config/ghc/ghci.rio.conf` — GHCi RIO config
- `.config/ghc/rio.options` — RIO options

### Passwords & Secrets
- `.config/passage/` — password store (age-encrypted, via passage)

### Display
- `.local/share/icc/` — monitor ICC color profiles (Mstar, 3x U2718Q)

### Misc
- `.plan` — finger plan file
- `.config/background` — desktop background
- `.config/angband/` — Angband game config
- `.config/crawl/init.txt` — Dungeon Crawl Stone Soup config
- `.config/easyeffects/` — audio EQ presets
- `.config/another-window-session-manager/` — saved window session
- `LICENSE` — repo license

### Scripts (`bin/`)
Cross-platform utility scripts, organized by OS:
- `bin/` root — general utilities: `bench`, `mylocation`, `rainbow`, `rdemo`, `repo2txt`, `sort_photos`, `wattage`, `wifi_qrcode`, `wol`, `youtube`, `is_ssh_interactive`
- `bin/darwin/` — macOS-specific: `create_devbox_app_aliases`, `launch-ollama`, `macos-defaults` (system preference toggles)
- `bin/linux/` — Linux-specific: `idletime`, `maximize_across_multiple_monitors`, `vu1server`, `wear`
- `bin/openbsd/` — OpenBSD-specific: `packages`, `wipe`
- Haskell/Idris source: `rainbow.hs`, `rainbow.idr`

### Machines
Three machines managed from this repo:
- **accismus** — macOS laptop (aarch64-darwin, nix-darwin)
- **metanoia** — NixOS workstation (x86_64-linux)
- **sophrosyne** — NixOS server at `sophrosyne.local` / `home.ggr.com` (x86_64-linux)
  - **Temperature logging:** NVMe/CPU temps and fan speeds are logged every minute to `/dragon/logs/temps.log` via `log-temps.timer`. After a crash or lockup, check the last entries in this file to see if temps spiked before the failure. The log survives reboots since it's on the ZFS pool.

## Conventions

- **Shell commands must be fish-compatible.** The main interactive shell is fish; zsh only exists as a minimal entry point that immediately execs fish. Use `and` instead of `&&`, `(cmd)` instead of `$(cmd)`, `set -x FOO bar` instead of `export FOO=bar`, and avoid bashisms.
- `$EDITOR` is helix (`hx`), set in fish config
- SSH agent via Secretive (TouchID/T2 secure enclave) on macOS
- Font: Liga SFMono Nerd Font
- Shell prompt: starship with UTF-8 symbols (falls back to plain on non-UTF-8 terminals)
- Shell history: atuin (synced database)
- Password management: passage (age-encrypted, not GPG)
- Nix formatting: alejandra (`nix fmt` — unreliable, prefer `alejandra <file>` directly)
- Before committing any changes, run a code review using the `code-review-skill` (loaded on-demand via OpenCode's skill tool) and ask the user how to proceed
- After each batch of changes, commit and push to all remotes (`git push origin && git push sophrosyne`)
- Code repos I'm actively working on live in `~/Documents/undated/repos/`
-
- **Version bump policy for `what-changed`:** Bump the minor version (e.g. `0.4.0` → `0.5.0`) whenever user-facing features, behavior, or dependencies change. Bug fixes and internal refactors get a patch if there's a prior tagged release, otherwise batch into the next minor. Keep `default.nix` and `pyproject.toml` in sync.
- **`git add` WITHOUT `-f` for `nix-what-changed`:** The directory has a `.gitignore` that excludes `__pycache__/`. Using `git add -f` overrides it and tracks `.pyc` files, which then need a cleanup commit. Use plain `git add .config/nix/pkgs/nix-what-changed/what_changed/<file>.py` for individual files, or `git add .config/nix/pkgs/nix-what-changed/` (without `-f`) to respect the gitignore. A pre-commit hook (`~/.git/hooks/pre-commit`) rejects `.pyc` files automatically if you forget.
