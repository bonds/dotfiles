---
name: dotfiles-layout
description: "Inventory of the tracked dotfiles: which file under $HOME holds shell (fish, the `config` alias), terminal (alacritty, ghostty, tmux), editor (helix), git, ssh, nix, haskell, password-store, DECISIONS.md and script config. Use when locating an existing config, answering where is X configured or what is in ~/.config, deciding where a new tracked file belongs, or untracking a file."
---

Paths are relative to `$HOME` unless absolute. Machine and service details
are in the `machines-and-services` skill.

`~/src/` holds the active code: `~/src/bonds/<name>/` (config, dotfiles, local,
neocode, osaurus, polyptych) and `~/src/hihello`. `~/Documents/undated/repos/`
is an **archive** of finished or abandoned work — read-only reference, never a
place to work, and not to be deleted: it holds the only local copy of
`nix-vudials` and `macos-cli-kbdswitch`, so the paths into it in
`.config/nix/AGENTS.md` are intentional, not stale.

### The bare repo and the `config` alias

Tracked files live directly in `$HOME`; there is no `.git` directory there. The
bare repo is `~/.local/share/dotfiles/` and it is driven with
`--work-tree=$HOME`. Untracked files are hidden from `git status`
(`status.showUntrackedFiles = no` in the bare repo's config), so `git add`
cannot accidentally stage the whole home directory — and plain `git status`
will not show you untracked files in *any* worktree; pass `-uall` when it
matters.

The `config` alias (`.config/fish/conf.d/10-aliases.fish`) wraps every git
command with the right `--git-dir` and `--work-tree`. It resolves the git dir
by existence, so the same file is correct on every machine and during a move:

```fish
if test -d $HOME/.local/share/dotfiles
    alias config='git --git-dir=$HOME/.local/share/dotfiles/ --work-tree=$HOME'
else
    alias config='git --git-dir=$HOME/.config/dotfiles/ --work-tree=$HOME'
end
```

Everything works like normal git — `config status`, `config add`,
`config commit`, `config push`, `config log`. Only the alias changes.

**`config` is fish-only.** It does not exist in bash/zsh/sh or in Hermes'
`terminal` tool; there it errors with `config: command not found`, and a script
invoking it can silently no-op (as with `nr`). From any other shell use the full
invocation, always `cd ~` first so relative paths resolve:

```bash
GITDIR=$HOME/.local/share/dotfiles
cd ~ && git --git-dir=$GITDIR --work-tree=$HOME status
```

| task | command |
|---|---|
| see tracked files | `config ls-files` |
| start tracking a file | `config add <path>` (no `-f`: respect `.gitignore`) |
| stop tracking, keep on disk | `config rm --cached <path>` |
| verify a push landed on every remote | `for r in main origin/main sophrosyne/main; do git --git-dir=$HOME/.local/share/dotfiles rev-parse --short "$r"; done` — `rev-parse --short` takes exactly one revision, so passing all three exits 128 with `fatal: Needed a single revision` |
| sync `$HOME` to the tip of `main` | `git --git-dir=$HOME/.local/share/dotfiles --work-tree=$HOME checkout main -- .` |

That last one is needed because a plain `git checkout main` only prints
"Already on 'main'" and changes nothing.

### Shell
- `.zshrc` — minimal zsh entry point (sources nix, execs fish)
- `.config/fish/config.fish` — entry point, delegates to `conf.d/`
- `.config/fish/conf.d/` — organized fish config split by concern:
  - `00-paths.fish` — env vars, PATH
  - `05-editor.fish` — EDITOR selection
  - `10-aliases.fish` — aliases
  - `15-functions.fish` — custom functions (ls, e, tree, ping, nr, hr, age)
  - `20-ssh.fish` — SSH_AUTH_SOCK (Secretive on macOS)
  - `25-gcloud.fish` — `GOOGLE_APPLICATION_CREDENTIALS` (ADC for Google client libraries, readonly SA)
  - `30-interactive.fish` — starship, atuin, auto-tmux, fzf opts
  - `35-nix-github-token.fish` — exports `NIX_CONFIG` access-tokens from `gh auth token` (avoids GitHub rate limits during `nr --update`); no secret in the file
  - `36-gh-public-token.fish` — `gh-public` wrapper: injects a Keychain `public_repo` token as `GH_TOKEN` for third-party public repos; no secret in the file
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
- `.config/git/config` — **the global git config** (moved here from `~/.gitconfig`, which is gone; tracked in this repo). The bare repo's own config lives inside `~/.local/share/dotfiles/config` (accismus) and is managed via `config config <key> <value>`.
- `.config/git/ignore` — **vestigial** (was the old repo-level gitignore). Untracked-file hiding via `status.showUntrackedFiles = no` in the bare repo's config makes it unnecessary.
- `.config/git/hooks/pre-commit` — pre-commit hook (fish indent/syntax check, reject `.pyc` files). The bare repo's `core.hooksPath` points here.
- `.config/git/hooks/pre-push` — pre-push hook (runs `nix flake check --no-build`). Same hooksPath mechanism.
- `.config/git/hooks/post-receive` — post-receive hook (server-side only; on sophrosyne, checks out the work tree after a push to main).

### SSH
- `.config/ssh/config` — SSH client config (Secretive agent on macOS, ControlMaster for `*.ggr.com`/`*.local`, auto-tmux on remote connections, port forwarding)
- `.config/ssh/keys` — authorized SSH keys (content tracked in git)
- `.ssh/authorized_keys` — symlink to `~/.config/ssh/keys`, created by nix activation (not tracked in git)

### Nix
- `.config/nix/` — **full nix flake for all machines** (see `.config/nix/AGENTS.md` for detailed docs)
  - Flake for: laptop (accismus/darwin), server (sophrosyne/NixOS), workstation (metanoia/NixOS)
  - `nr` fish function wraps `nh` for rebuilds
- `.config/nix/agent-skills/` — canonical agent skills (`<name>/SKILL.md`), symlinked per skill into every harness by `modules/home/pi.nix`; see the `pi-harness` skill
- `.config/nix/pkgs/pi/` — pi's declarative config: `extensions/`, `prompts/`, `keybindings.json`, `decisions.md` (→ `~/DECISIONS.md`), `evals/`
- `.config/nix/pkgs/nix-what-changed/` — **`what-changed` tool** — Ported from fish to Python (v0.22.0).
  - Lives at `pkgs/nix-what-changed/` inside the dotfiles flake.
  - Also publishable as a standalone flake: `github:bonds/dotfiles?dir=.config/nix/pkgs/nix-what-changed`.
  - Shows LLM-summarized changelogs after `nr` via `what-changed <old-closure> <new-closure>`.
  - Model: `qwen2.5-7b` via llama.cpp on sophrosyne (`http://sophrosyne.taileafac.ts.net:8080`). Config at `~/.config/what-changed/config.toml`.
- Benchmark: `what-changed --benchmark [--models m1,m2]` compares speed, quality, bullet accuracy, and word merges. Run before switching default model.
  - Supports ollama + OpenAI-compatible backends. Caches results in `~/.cache/what-changed/`.
  - NixOS/darwin module: `programs.what-changed.enable`.
  - `nix flake check` runs the alejandra (format), deadnix, statix, and gitleaks (secrets) checks plus the `what-changed-test` pytest suite (166 tests), which mirrors the standalone sub-flake's own `pytest` check.
- `.config/nix/pkgs/reel-summarize/` — **`reel-summarize` tool** (v0.2.0) — Local Instagram Reel summarizer (shared pipeline/CLI).
  - Pipeline: yt-dlp download → ffmpeg frames+audio → transcribe-cpp (whisper `whisper-small-Q5_K_M.gguf`) → per-frame vision OCR → LLM final summary.
  - Runtime deps: `yt-dlp`+`ffmpeg` via nix, llama.cpp OpenAI-compatible API (text `qwen2.5-7b` @ `:8080`, vision @ `:8081`), whisper via `transcribe-cpp` (`TRANSCRIBE_LIBRARY`).
  - CLI: `reel-summarize <url>` — concise prose summary to stdout. Nix-managed on accismus via home-manager: `programs.reel-summarize.enable`.
  - Config at `~/.config/reel-summarize/config.toml` (backend, host/vision_host, model, fps, max_frames, timeout). Backend defaults to `openai` (llama.cpp); `ollama`/`osaurus` also supported.
  - `nix flake check` runs format check, python syntax check, pytest suite.
  - **Source overrides (without nix rebuild):** `PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize <url>` picks up uncommitted source changes.
- `.config/nix/pkgs/reel-summarize-mcp/` — **`reel-summarize-mcp` server** (v0.1.0) — MCP wrapper exposing the pipeline to the Osaurus agent.
  - Wraps `reel-summarize` (locally `callPackage`d, plus `transcribe-cpp`) with `mcp`/`httpx`/`starlette`/`uvicorn`; streamable HTTP at `/sse` (default port 8892), optional bearer token via `REEL_SUMMARIZE_MCP_TOKEN`.
  - Runs on **sophrosyne** as `systemd.services.reel-summarize-mcp` (see `hosts/sophrosyne/configuration.nix`), as user `llamacpp` with `StateDirectory=reel-summarize-mcp`. Binds `0.0.0.0` — reached from accismus over **Tailscale** (firewall opens 8892 on `tailscale0` only, not LAN/public).
  - Models: text `qwen2.5-7b` @ `127.0.0.1:8080`, vision **Qwen3-VL-2B** @ `127.0.0.1:8081` via `llamacpp-vision-server` (KV cache `q8_0`). IG cookies from agenix: `REEL_SUMMARIZE_COOKIES=/run/agenix/reel-ig-cookies`.
  - Full spec + remaining steps in `reel-summarize-mcp/SPEC.md`.
- `.config/nix/pkgs/photokit-export/` — **`photo-export` package + Swift CLI** (v0.2.5) — PhotoKit-native photo export, sole exporter for the nightly backup. Replaced osxphotos entirely (broken `--download-missing` AppleScript path since 2026-07-26; osxphotos overlay removed).
  - **How it works**: Swift against the system SDK (Xcode-only; Photos.framework isn't in nixpkgs), bundled in `.app` with `NSPhotoLibraryUsageDescription`, ad-hoc signed `com.ggr.photo-export`. Exports ALL assets (local + iCloud-only) via `PHImageManager.requestImageDataAndOrientation` + writes a basic XMP sidecar (description + dates) — no AppleScript, no osxphotos.
  - **Config is source of truth**: `~/Library/Application Support/photo-export/config.toml` (dest, limit, manifest) — `open --args` doesn't reliably forward args to LaunchServices-registered apps. Args (when they arrive) override config. Home-manager `programs.photo-export.enable` writes the config.
  - **Safety guard**: refuses to export when dest is the SMB mount path but not actually mounted (prevents silent local writes — this dumped 139GB once). Logic in `photoexport_core.swift`, unit-tested.
  - **Robustness:** SMB mount via NetFS, mount probe, atomic `.part`+rename writes, 3× retry, resumable manifest `~/.cache/photo-export-manifest.txt`, `yyyy/mm` dirs.
  - **First-run / grant-time:** one-time "Allow" click for Photos access (see `FIRST-RUN.md`). Must launch via `open` (direct exec = denied). Binary byte change (Swift / nix rebuild) re-grants — click again.
  - **Transport is SFTP** (primary; SMB/netFS is the legacy fallback):
    `photo-export` streams each original in-memory over SSH/SFTP as
    `photo-backup` (owner of `/dragon/media/photos`) using
    `~/.ssh/id_photo_rsync` (deployed to `/home/photo-backup/.ssh/authorized_keys`
    with `command=sftp-server -d /dragon/media/photos`). No local temp copies
    (no SSD wear), works over LAN or tailnet. `~/bin/photos-backup` is the nightly
    wrapper (launches the app; the SFTP transport needs no mount).
  - **Tests:** pure logic in `photoexport_core.swift` (single source of truth) + 39 unit tests in `test_core.swift`; wired into `nix flake check` as `photo-export-test` (runs in sandbox via Xcode toolchain). Run manually: copy `test_core.swift` → `main.swift`, `swiftc photoexport_core.swift main.swift`. End-to-end smoke test planned but not implemented: `INTEGRATION_TEST_PLAN.md`.

### Haskell
- `.config/ghc/ghci.conf` — GHCi config
- `.config/ghc/ghci.rio.conf` — GHCi RIO config
- `.config/ghc/rio.options` — RIO options

### Passwords & Secrets
- `.config/passage/` — password store (age-encrypted, via passage)

### Display
- `.local/share/icc/` — monitor ICC color profiles (Mstar, 3x U2718Q)

### Agent harness
- `AGENTS.md` — always-loaded agent instructions for `$HOME` (routing + non-negotiables; detail belongs in a skill)
- `DECISIONS.md` — settled choices and their rationale, so they stop being re-litigated (symlink into `.config/nix/pkgs/pi/decisions.md`)
- `~/.local/share/agents/memory/inbox.md` — **untracked**, written by every harness (pi's capture extensions, the opencode plugin, the hermes hook, `mem inbox add`); drained by `mem distill`
- `~/.pi/agent/sessions/` — **untracked** JSONL session tree, searchable with the `recall` tool
- `docs/learnings/` — per-repo lesson notes, written by `/learn` (symptom / cause / takeaway)

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
- `bin/` root — general utilities: `bench`, `def`, `hm-links`, `mylocation`, `rainbow`, `rdemo`, `repo2txt`, `sort_photos`, `wifi_qrcode`, `wol`, `youtube`
  - `hm-links` — audit/repair home-manager's symlinks in `$HOME`; see the nix
    AGENTS.md gotcha. `hm-links` audits, `--fix` repairs, `--scan` also finds
    orphans the current generation no longer manages.
- `bin/darwin/` — macOS-specific: `create_devbox_app_aliases`, `macos-defaults` (system preference toggles)
- `bin/linux/` — Linux-specific: `idletime`, `maximize_across_multiple_monitors`, `vu1server`, `wear`
- `bin/openbsd/` — OpenBSD-specific: `packages`, `wipe`
- Haskell/Idris source: `rainbow.hs`, `rainbow.idr`

### Untracked scripts
Useful scripts that live in `~/bin/` but are symlinked or copied from elsewhere (not tracked in git):
- `kbdswitch` — macOS keyboard layout switcher (compiled Swift binary from `~/Documents/undated/repos/macos-cli-kbdswitch/`)
- `pnpm` — symlink to `node_modules/pnpm/bin/pnpm.cjs`
- `npx-wrapper.sh` — adds Nix profile paths to PATH before running npx
