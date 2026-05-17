# AGENTS.md

Personal dotfiles repo — this is `$HOME` on each machine, but only a curated subset of files is tracked via git.

## Git tracking strategy

All untracked files are hidden (`status.showUntrackedFiles = no` in `.config/git/config`). Only files explicitly `git add`ed are tracked. The global gitignore (`.config/git/ignore`) additionally ignores `.DS_Store`, `.vscode`, and `**/.claude/settings.local.json`.

**To see tracked files:** `git ls-files`
**To add new files to tracking:** `git add -f <path>` (normal `git add` works too since untracked files are shown as ignored)

## Tracked config layout

### Shell
- `.zshrc` — minimal zsh entry point (sources nix, execs fish)
- `.config/fish/config.fish` — main interactive shell (fish) with aliases, functions, path setup, editor selection, starship/atuin integration
- `.config/fish/fish_plugins` — fish plugin list
- `.config/starship/` — prompt configs: `darwin.toml`, `linux.toml`, `openbsd.toml`, `plain.toml` (fallback when no UTF-8)
- `.config/atuin/config.toml` — shell history database config

### Terminal
- `.config/alacritty/alacritty.toml` — Alacritty terminal emulator (font, window size, clipboard)
- `.config/ghostty/config` — Ghostty terminal emulator (font, window size)

### Editor
- `.config/helix/config.toml` — Helix editor (soft wrap)
- `.config/helix/languages.toml` — Helix language config

### Git
- `.config/git/config` — per-repo git config (user identity, `showUntrackedFiles = no`)
- `.config/git/ignore` — global gitignore for this repo

### SSH
- `.config/ssh/config` — SSH client config (Secretive agent on macOS, ControlMaster for `*.ggr.com`/`*.local`, auto-tmux on remote connections, port forwarding)
- `.config/ssh/keys` — authorized SSH keys (directory)
- `.ssh/authorized_keys` — keys allowed to connect to this machine

### Nix
- `.config/nix/` — **full nix flake for all machines** (see `.config/nix/AGENTS.md` for detailed docs)
  - Flake for: laptop (accismus/darwin), server (sophrosyne/NixOS), workstation (metanoia/NixOS)
  - `nr` fish function wraps `nh` for rebuilds

### Haskell
- `.config/ghc/ghci.conf` — GHCi config
- `.config/ghc/ghci.rio.conf` — GHCi RIO config
- `.config/ghc/rio.options` — RIO options

### Passwords & Secrets
- `.config/passage/` — password store (age-encrypted, via passage)
- `.config/secrets/` — encrypted secrets (age)

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
- `bin/darwin/` — macOS-specific: `create_devbox_app_aliases`, `launch-ollama`
- `bin/linux/` — Linux-specific: `idletime`, `maximize_across_multiple_monitors`, `vu1server`, `wear`
- `bin/openbsd/` — OpenBSD-specific: `packages`, `wipe`
- Haskell/Idris source: `rainbow.hs`, `rainbow.idr`

### Machines
Three machines managed from this repo:
- **accismus** — macOS laptop (aarch64-darwin, nix-darwin)
- **metanoia** — NixOS workstation (x86_64-linux)
- **sophrosyne** — NixOS server at `sophrosyne.local` / `home.ggr.com` (x86_64-linux)

## Conventions

- `$EDITOR` is helix (`hx`), set in fish config
- SSH agent via Secretive (TouchID/T2 secure enclave) on macOS
- Font: Liga SFMono Nerd Font
- Shell prompt: starship with UTF-8 symbols (falls back to plain on non-UTF-8 terminals)
- Shell history: atuin (synced database)
- Password management: passage (age-encrypted, not GPG)
- Nix formatting: alejandra (`nix fmt` — unreliable, prefer `alejandra <file>` directly)
