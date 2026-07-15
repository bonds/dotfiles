# AGENTS.md

Personal dotfiles tracked via a **bare git repo** at `~/.config/dotfiles`, managed
through a `config` alias (fish-only, see below).  This avoids a `.git/` directory
cluttering `$HOME`, which was causing issues with various tools.  The approach
is the one described in the [Atlassian dotfiles
tutorial](https://www.atlassian.com/git/tutorials/dotfiles).

## Git tracking strategy

The bare repo lives at `~/.config/dotfiles/` and uses `--work-tree=$HOME` so
that tracked files appear directly in `$HOME`.  Untracked files in `$HOME` are
hidden (`status.showUntrackedFiles = no` set in the bare repo's config).

The `config` alias (defined in `.config/fish/conf.d/10-aliases.fish`) wraps
every git command with the right `--git-dir` and `--work-tree`:

```fish
alias config='git --git-dir=$HOME/.config/dotfiles/ --work-tree=$HOME'
```

**Everything you do with `config` works just like normal git** — `config status`,
`config add`, `config commit`, `config push`, `config log`, etc.  Only the
alias changes; the subcommands are the same git you already know.

**To see tracked files:** `config ls-files`
**To add new files to tracking:** `config add <path>` (the bare repo config
hides untracked files from status, so `git add` won't accidentally stage
everything)
**To untrack a file:** `config rm --cached <path>` — the file stays on disk
but is no longer managed.

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
- `.config/git/config` — **vestigial** (was the old per-repo config before the bare-repo migration). The bare repo's own config lives inside `~/.config/dotfiles/config` and is managed via `config config <key> <value>`.
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
- `.config/nix/pkgs/reel-summarize/` — **`reel-summarize` tool** (v0.1.0) — Local Instagram Reel summarizer.
  - Pipeline: yt-dlp download → ffmpeg frames+audio → whisper transcription → llava:7b per-frame OCR → qwen2.5 summary.
  - Nix-managed via home-manager: `programs.reel-summarize.enable` (enabled on accismus).
  - Runtime deps: `yt-dlp`+`ffmpeg` via nix, ollama with `llava:7b`+`qwen2.5:7b`.
  - CLI: `reel-summarize <url>` — concise prose summary to stdout.
  - Opencode skill at `~/.config/opencode/skills/reel-summarize/SKILL.md`.
  - `nix flake check` runs format check, python syntax check, pytest suite.
  - Config at `~/.config/reel-summarize/config.toml`.
  - **Auto cookie extraction:** Automatically reads cookies from Zen browser's Personal workspace (userContextId=1) via `cookies.sqlite`. No manual cookie setup needed.
  - **GPU acceleration:** All model layers offloaded to GPU via `options.num_gpu = 99` in vision API calls. On M2, `llava:7b` takes ~3-10s per frame.
  - **Default settings (after nix rebuild):** `llava:7b`, `max_frames = 10`, `1 fps`, `timeout = 300s`. Total run: ~1-3 min for a 60s reel.
  - **Source overrides (without nix rebuild):** `PYTHONPATH="/Users/scott/.config/nix/pkgs/reel-summarize:$PYTHONPATH" reel-summarize <url>` picks up uncommitted source changes.

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
- `bin/` root — general utilities: `bench`, `def`, `mylocation`, `rainbow`, `rdemo`, `repo2txt`, `sort_photos`, `wattage`, `wifi_qrcode`, `wol`, `youtube`
- `bin/darwin/` — macOS-specific: `create_devbox_app_aliases`, `launch-ollama`, `macos-defaults` (system preference toggles)
- `bin/linux/` — Linux-specific: `idletime`, `maximize_across_multiple_monitors`, `vu1server`, `wear`
- `bin/openbsd/` — OpenBSD-specific: `packages`, `wipe`
- Haskell/Idris source: `rainbow.hs`, `rainbow.idr`

### Untracked scripts
Useful scripts that live in `~/bin/` but are symlinked or copied from elsewhere (not tracked in git):
- `kbdswitch` — macOS keyboard layout switcher (compiled Swift binary from `~/Documents/undated/repos/macos-cli-kbdswitch/`)
- `pnpm` — symlink to `node_modules/pnpm/bin/pnpm.cjs`
- `npx-wrapper.sh` — adds Nix profile paths to PATH before running npx

### Machines
Three machines managed from this repo:
- **accismus** — macOS laptop (aarch64-darwin, nix-darwin)
  - **Dotfiles** use the bare-repo approach described above (`~/.config/dotfiles`). The `config` fish alias is defined in `~/.config/fish/conf.d/10-aliases.fish`.
  - **Syncthing** managed via nix-darwin launchd agent (not standalone app). Declarative `config.xml` generated and deployed by activation script. Config dir at `~/Library/Application Support/Syncthing/`. Preserves `key.pem`, `cert.pem`, `index-v2/` across rebuilds.
  - **Photos backup** via `photos-backup` launchd agent (daily at 2am). Two-step pipeline: (1) `osxphotos export --export-as-hardlink --sidecar XMP` creates date-organized hardlinks in `~/Pictures/Syncthing-Photos/` (near-zero extra disk on APFS), (2) `rsync` transfers the export to `sophrosyne:/dragon/media/photos/` over SSH LAN. No Syncthing involved for photos.
    - **⚠️ Prerequisite:** In Photos → Settings → General, set "Download Originals to this Mac" (not "Optimize Mac Storage"). If set to Optimize, the export silently gets low-resolution thumbnails and the backup copies are useless. Easy to miss on a fresh account since Photos defaults to Optimize.
    - **`--delete` on rsync:** rsync uses `--delete` so the server mirrors Photos exactly. Deleted photos are still preserved in the firesafe backup's `.deleted/` directory on the USB drive.
    - **Auto-generated SSH key:** A no-passphrase key `~/.ssh/id_photo_rsync` is generated by the nix activation script if missing. The public key is synced to sophrosyne via `~/Documents/.config/photo-rsync-key.pub` (Syncthing Documents folder). On sophrosyne, it gets deployed with `restrict,from="192.168.4.*",command="/usr/local/bin/rrsync-photos"` — only usable from LAN, only for rsync to `/dragon/media/photos/`. The `rrsync-photos` wrapper script enforces the path restriction.
    - **Metadata sidecars:** `--sidecar XMP` writes XMP sidecar files alongside each photo (keywords, GPS, dates, titles), giving browsable metadata on the server.
- **metanoia** — NixOS workstation (x86_64-linux)
  - **Dotfiles:** Should be migrated to the bare-repo approach when back online (same as accismus/sophrosyne).
- **sophrosyne** — NixOS server at `sophrosyne.local` / `home.ggr.com` (x86_64-linux)
  - **Dotfiles** use the same bare-repo approach. Remote push target for this machine: `scott@home.ggr.com:~/.config/dotfiles`. The bare repo has a `post-receive` hook at `~/.config/dotfiles/hooks/post-receive` (installed manually during bootstrap; tracked in the repo at `.config/git/hooks/post-receive` and pointed to via `core.hooksPath`) that checks out the work tree to `$HOME` on each push to `main`.
  - **ZFS pool:** The `dragon` pool is intentionally degraded (raidz2, 1 device kept offline) — running on 1-disk redundancy by design.
  - **Temperature logging:** NVMe/CPU temps and fan speeds are logged every minute to `/dragon/logs/temps.log` via `log-temps.timer`. After a crash or lockup, check the last entries in this file to see if temps spiked before the failure. The log survives reboots since it's on the ZFS pool.
  - **Firesafe USB backup:** Automated off-site backup via an A/B USB drive rotation. Defined in `modules/firesafe-backup.nix` (NixOS module: `programs.firesafe-backup`).
    - **How it works:** A udev rule matches drives labeled `firesafe` and triggers `firesafe-backup.service`, which mounts at `/mnt/firesafe`, reads `.firesafe-id` (A or B), then rsyncs configured sources (Archive, Backups, Documents, Media/* subdirs, Photos) from `/dragon/`.
    - **Deleted file preservation:** Rsync uses `--backup --backup-dir=.deleted/DATE/`. When drive free space drops below 50GB, the oldest `.deleted/` dirs are pruned (one at a time) until the threshold is met.
    - **A/B rotation:** Each drive has a `.firesafe-id` file (A or B). Rotate weekly by swapping drives to always have an off-site copy.
    - **Commands:**
      - `firesafe-status` — mount status, elapsed time, source-count ETA, log tail
      - `firesafe-status -w` — live-updating every 2s
      - `firesafe-eject` — kills backup, syncs, unmounts (uses sudo)
      - `firesafe-reclaim [--dry-run]` — prune `.deleted/` dirs
      - `firesafe-deleted [date]` — browse `.deleted/` contents
    - **Deleted file changelog:** A permanent record of all deleted files (not pruned) is appended to `/dragon/logs/firesafe-backup-changelog.log` on each backup run. The log survives drive rotation and `.deleted/` cleanup. Format: `DATE<tab>SOURCE_PATH`. View with `tail /dragon/logs/firesafe-backup-changelog.log`.
    - **Email notifications:** Results sent via msmtp to scott@ggr.com on completion/failure.
    - **First-time setup:** Label ext4 drive `firesafe` (`e2label`), create `.firesafe-id`, plug in to trigger backup. Drive must be 4.5TB+ to hold Archive + Backups + Documents + selected Media subdirs.
    - **Drive I/O note:** The WD Game Drive USB bridge (1058:262f) is BOT-only, QD=1, no UASP — USB-native PCB, cannot shuck. Random I/O ~1 MB/s; sequential ~40-90 MB/s ext4. ext4 journal vs exFAT speed tradeoffs, dirty page flush hang on umount. See `firesafe-backup.nix` header comment for full details.
  - **Photos pipeline:**
    - Mac (accismus): `photos-backup` launchd agent runs nightly at 2am — `osxphotos export --export-as-hardlink --sidecar XMP` creates hardlinks, then `rsync --delete` sends them to sophrosyne (server mirrors Photos; deleted files preserved in firesafe `.deleted/`)
    - SSH key: `~/.ssh/id_photo_rsync` (no passphrase, auto-generated by nix) used for the rsync. Restricted on sophrosyne to LAN + rsync-to-photos only.
    - Storage: `/dragon/media/photos` on sophrosyne (still the same destination, no longer syncthing-managed)
    - Firesafe: `Photos` source picks up `/dragon/media/photos` during backup
    - ZFS dataset: `dragon/photos` mounted at `/dragon/media/photos`, `atime=off`
    - **Archived plan:** A larger restructure (promoting `/dragon/media` itself to a dataset) was researched but deferred — see `.config/nix/media-dataset-restructure-plan.md` for context.
  - **Minecraft Bedrock server: Native (no container) via `modules/minecraft-bedrock.nix`.
    - Binary packaged at `pkgs/bedrock-server/` — `fetchurl` from Mojang, `autoPatchelfHook` for glibc compat.
    - Data dir: `/dragon/servers/minecraft` (migrated from old `/dragon/containers/minecraft`, kept as backup until `/dragon/containers` dataset was removed).
    - Runs as `minecraft` user, systemd service with FIFO console socket for graceful stop.
    - **Updates:** `nr --update` on Linux auto-bumps via `pkgs/bedrock-server/update.sh` (queries kittizz tracker, downloads zip, computes sha256, rewrites `default.nix`).
  - **Don't Starve Together server:** Native (no container) via `modules/dst-server.nix`.
    - Binary installed via SteamCMD at `/dragon/servers/dontstarve/install/` (app ID 343050, auto-updates on start).
    - Old Debian library shims (`libcurl-gnutls`, `libnettle6`, `libldap-2.4`, `libsasl2`) extracted from Debian snapshots for ABI compatibility.
    - Dual-shard setup (Master + Caves) as two systemd services.
    - Config templates + non-destructive config generation in `modules/dst-server-config/`.
    - Token at `/var/lib/dst-server/cluster_token.txt` (warn_missing in checkSecrets).

## Conventions

- **Shell commands must be fish-compatible.** The main interactive shell is fish; zsh only exists as a minimal entry point that immediately execs fish. Use `and` instead of `&&`, `(cmd)` instead of `$(cmd)`, `set -x FOO bar` instead of `export FOO=bar`, and avoid bashisms.
- `$EDITOR` is helix (`hx`), set in fish config
- SSH agent via Secretive (TouchID/T2 secure enclave) on macOS
- Font: Liga SFMono Nerd Font
- Shell prompt: starship with UTF-8 symbols (falls back to plain on non-UTF-8 terminals)
- Shell history: atuin (synced database)
- Password management: passage (age-encrypted, not GPG)
- Nix formatting: alejandra (`nix fmt` — unreliable, prefer `alejandra <file>` directly)
- Before committing any changes, run a code review using the current harness's available code-review skill or tool, and ask the user how to proceed
- After each batch of changes, commit and push to all remotes (`config push origin && config push sophrosyne`). Never force-push (`--force` / `config push -f`) to any remote. If sophrosyne rejects the push because of divergent histories (e.g. a `git commit --amend` or rebase on either side), pull or merge first to reconcile. The sophrosyne bare repo has a `post-receive` hook that checks out the work tree on push — no special `receive.denyCurrentBranch` config needed.
- Code repos I'm actively working on live in `~/Documents/undated/repos/`
- **Nix deployments to remote machines:** Never attempt a cross-build from the local machine (aarch64-darwin cannot build x86_64-linux derivations that have `allowSubstitutes = false`, such as `arion-compose`). Instead, push the commit and then SSH directly to the target machine to rebuild: `ssh sophrosyne "doas nixos-rebuild switch --flake /home/scott/.config/nix#sophrosyne"`. Use the full `/run/current-system/sw/bin/nixos-rebuild` path if the SSH session's PATH doesn't include it, so the `noPass` doas rule matches.
- **Version bump policy for `what-changed`:** Bump the minor version (e.g. `0.4.0` → `0.5.0`) whenever user-facing features, behavior, or dependencies change. Bug fixes and internal refactors get a patch if there's a prior tagged release, otherwise batch into the next minor. Keep `default.nix` and `pyproject.toml` in sync.
- **`config add` WITHOUT `-f` for `nix-what-changed`:** The directory has a `.gitignore` that excludes `__pycache__/`. Using `config add -f` overrides it and tracks `.pyc` files, which then need a cleanup commit. Use plain `config add .config/nix/pkgs/nix-what-changed/what_changed/<file>.py` for individual files, or `config add .config/nix/pkgs/nix-what-changed/` (without `-f`) to respect the gitignore. A pre-commit hook (`.config/git/hooks/pre-commit`) rejects `.pyc` files automatically if you forget.
- **`flake.lock` changes:** When a commit includes a `flake.lock` update (e.g. after `nr --update`), push both remotes normally (`config push origin && config push sophrosyne`). The sophrosyne post-receive hook does a force checkout so there is no "dirty work tree" rejection. If sophrosyne independently updated its flake.lock (via `nr --update` on the server), the next push from accismus will overwrite it — this is intentional. If you need sophrosyne to pull changes without accismus pushing:
  1. `ssh sophrosyne "config pull origin main"`
  2. The post-receive hook won't fire (it only runs on push), so the work tree will be updated by the checkout. If for some reason the work tree is stale: `ssh sophrosyne "cd ~ && git --git-dir=$HOME/.config/dotfiles --work-tree=$HOME checkout -f main"`

### doas privilege escalation

doas is configured with layered privilege:
- **noPass commands** — `systemctl`, `journalctl`, `nixos-rebuild`, `nh` — skip PAM entirely, no TouchID prompt.
- **Everything else** — authenticates via `pam_ssh_agent_auth`, which challenges the forwarded SSH agent (Secretive on accismus). Expect a TouchID prompt per operation.

Key constraints:
- **doas does NOT resolve bare command names via PATH for rule matching.** Always use the full path: `doas /run/current-system/sw/bin/systemctl restart syncthing`, NOT `doas systemctl restart syncthing`. The existing `nixos-rebuild`/`nh` noPass rules follow the same convention (full path).
- **`args` in doas.conf is an exact match** on the full argument list, not a prefix match. `args restart` only matches `doas cmd restart` (no additional args). All current noPass rules are scoped to `cmd`-level only (no `args`) for this reason.
- **Agent forwarding is required** for TouchID-for-doas. SSH config sets `ForwardAgent yes` for sophrosyne. If for some reason the agent isn't forwarded, doas falls back to password prompt (works interactively only).

The keys file for `pam_ssh_agent_auth` is at `/etc/ssh/authorized_keys.d/scott` (root-owned, outside the nix store — an activation script copies it on each switch to avoid group-writable /nix/store directory rejections).
