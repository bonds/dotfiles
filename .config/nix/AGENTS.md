# AGENTS.md

Personal nix flake for:
- macOS laptop **accismus** (`aarch64-darwin`, nix-darwin, `nixpkgs-unstable`)
- NixOS server **sophrosyne** (`x86_64-linux`, `nixos-26.05`, also at `sophrosyne.local` / `home.ggr.com`)
- NixOS workstation **metanoia** (`x86_64-linux`, `nixos-26.05` — currently offline, not plugged in)

## Commands

**Always use `nr` for rebuilds.** The `nr` fish function (in `~/.config/fish/config.fish`) wraps `nh` and auto-detects the host to pick the right flake target. Do not recommend raw `nixos-rebuild` or `darwin-rebuild` commands unless `nr` is broken.

```fish
# Rebuild current machine
nr

# Rebuild and update all flake inputs (commits flake.lock)
nr --update

# Rebuild and update specific input only
nr -U nix-index-database
```

### Per-machine fallbacks (only if `nr` breaks)

**accismus** (laptop):
```bash
# Build only
darwin-rebuild build --flake .#accismus
# Switch
sudo darwin-rebuild switch --flake .#accismus
```

**sophrosyne** (server):
```bash
# Build only
nixos-rebuild build --flake .#sophrosyne
# Switch
sudo nixos-rebuild switch --flake .#sophrosyne
# Deploy from laptop via ssh
nixos-rebuild switch --flake .#sophrosyne --target-host scott@home.ggr.com --use-remote-sudo
```

**metanoia** (workstation):
```bash
# Build only
nixos-rebuild build --flake .#metanoia
# Switch
sudo nixos-rebuild switch --flake .#metanoia
# Deploy from laptop via ssh
nixos-rebuild switch --flake .#metanoia --target-host scott@metanoia.local --use-remote-sudo
```

### Utility commands

```bash
# Format: alejandra (nix fmt is unreliable; prefer alejandra directly)
alejandra <file> ...

# Update flake inputs (commit flake.lock afterward)
nix flake update
```

## Structure

```
flake.nix          # Inputs + shared module wiring for all machines
hosts/
  accismus/        # Laptop nix-darwin config
    configuration.nix
    syncthing-config.xml
  metanoia/        # Workstation NixOS config
    configuration.nix
    hardware-configuration.nix
    monitors.xml    #   GDM display config (extracted from configuration.nix)
  sophrosyne/      # Server NixOS config
    configuration.nix
    hardware-configuration.nix
    networking.nix
    security.nix
    services.nix
    storage.nix
modules/           # Shared modules
  home/            # Home-manager modules (all machines)
    base.nix        #   Shared base: stateVersion, tmux, what-changed (reduces per-host duplication)
    common.nix      #   Shared home-manager settings (useGlobalPkgs, useUserPackages)
    direnv.nix      #   direnv configuration
    gnome.nix       #   GNOME dconf, extensions, keybindings (metanoia only)
    misc.nix        #   WirePlumber, uBlock, fish plugins, ulauncher (metanoia only)
    polyptych.nix   #   Polyptych (spanned fullscreen video player)
    tmux.nix        #   Catppuccin tmux theme, truecolor, cpu/ram/battery modules
    what-changed.nix #  what-changed LLM changelog summaries
    zen-policies.nix #  Zen browser policies (shared by accismus + metanoia)
  packages/         # Per-machine package lists
    dev.nix         #   Dev tools (shared: editors, languages, SCM)
    utils.nix       #   System utilities (shared: file, network, system tools)
    desktop.nix     #   metanoia workstation packages (GNOME, Steam, etc.)
    macos.nix       #   accismus-specific packages (macOS apps, binaries)
  nix-registry.nix  # Shared nix registry/nixPath pinning (darwin + NixOS)
  nixos-common.nix  # Shared NixOS settings — auto-included by mkNixos.nix (not per-host)
  ollama/           # Overlay: pinned ollama darwin binary + update.sh
  osxphotos/        # Overlay: pinned osxphotos darwin binary + update.sh + wrapper.sh
  zen-browser/      # Overlay: pinned zen-browser darwin binary + update.sh
  opencode/         # Overlay: pinned opencode CLI + desktop binaries + update.sh
  daisydisk-overlay/ # Overlay: pinned DaisyDisk darwin binary + update.sh
  vudials-uids.nix  # Scott's dial UID defaults (imported by both accismus + metanoia)
  bash-to-fish.nix  # Shell detection: bash → fish exec wrapper
  fish-command-not-found.nix  # nix-locate based command-not-found handler
  prune-generations.nix  # Nix generation pruning (darwin + Linux)
  secrets-check.nix # Gitleaks secret scan at build time
  ssh-authorized-keys.nix  # Symlink ~/.config/ssh/keys → ~/.ssh/authorized_keys
  ...[service modules: minecraft-bedrock, dst-server, firesafe-backup, etc.]
```

## Gotchas

- **`inputs.nixpkgs.follows` can break things on stable channels.** Letting an input follow your nixpkgs can cause build failures if the input expects newer nixpkgs APIs than the stable channel provides. If an input fails to build on a stable channel, remove its follows so it uses its own pinned nixpkgs. This has happened with home-manager and arion in the past.
- **`nix flake check` works on darwin** — NixOS configs evaluate fine cross-platform. Cannot cross-build x86_64 from aarch64 though; build directly on the target machine or deploy via `--target-host`. Runs `format-check` (alejandra) and `secrets-check` (gitleaks). Does NOT run pytest on nix-what-changed (run that explicitly in the sub-flake).
- **`nixos-rebuild switch` needs sudo.** Remote deploy from laptop uses `--target-host scott@host --use-remote-sudo`. Passwordless sudo (`NOPASSWD` in sudoers) is needed for automated deploys.
- **`flake.lock` is tracked.** Commit it after `nix flake update`.
- **`warn-dirty = false`** is set in `nix.conf` — builds work fine with uncommitted changes.
- **Uses `pkgs.lix`** as the nix package on all machines, not the default `pkgs.nix`.
- **`allowUnfree = true`** — required for `helvetica-neue-lt-std` font on laptop.
- **Server uses two nixpkgs:** `nixos-26.05` (stable) for most packages, `nixpkgs-unstable` for ollama + tailscale (passed via `pkgs-unstable` specialArg). Same pattern for metanoia.
- **`nix-index-database`** replaces the old `~/bin/nix-command-not-found` hand-rolled script with the upstream module.
- **`nix fmt` is unreliable.** It sometimes fails on stdin ("unexpected end of file"). When it does, run alejandra directly on the changed files instead: `alejandra <file> <file>...`.
- **Run alejandra after every nix file change.** Before building or deploying, always format any modified `.nix` files: `alejandra <file> <file>...` (from both `~/.config/nix` and `~/.config/nix-vudials`).
- **NEVER commit secrets to the repo.** All secrets (passwords, API tokens, private keys) must live outside git as local-only files on the target machine. The repo only references their paths.
- **Secrets scanning is enforced at build time.** `modules/secrets-check.nix` runs `gitleaks` on the flake source in a derivation added to `environment.systemPackages`. If any secrets are found (not in `.gitleaks.toml` allowlist), the build fails — `darwin-rebuild`, `nixos-rebuild`, and `nr` all refuse to proceed. `nix flake check` also runs a secrets check (useful pre-push since it doesn't require a full build).
- **Local-only secrets on the server must have a `warn_missing` check.** If a service reads a secret file that lives outside the repo (e.g. `/etc/ddns-token`, `/etc/email-pass`), add a corresponding `warn_missing` check in `system.activationScripts.checkSecrets` in `hosts/sophrosyne/configuration.nix`. This prints a clear warning at activation time telling the admin what the secret is for and where to find it (e.g. Bitwarden).
- **After every nix file change, always run the build step to catch errors before attempting a switch.** The switch step requires `sudo` which may fail remotely; the build step catches evaluation and compilation errors first. Do not commit and push changes to sophrosyne or metanoia without first building remotely to verify they compile clean.
- **When changes require a reboot to take effect (kernel params, boot config), tell the user explicitly.** After a successful switch, check whether any changes need a reboot — `boot.kernelParams` changes always do, as do filesystem changes and some systemd settings. Say "reboot needed" rather than just "run nr".
- **After each batch of changes, commit and push to all remotes** (`git push origin && git push sophrosyne`).
- **Hooks are in `.config/git/hooks/` (tracked in git, `hooksPath = .config/git/hooks` in repo git config).** Currently: `pre-commit` (rejects `.pyc` files, checks fish formatting/syntax) and `pre-push` (runs `nix flake check --no-build` before push). Bypass the pre-push hook with `git push --no-verify`. The pre-push hook only checks the nix config subdirectory.
- **Pushing to a checked-out branch on a remote** requires the remote repo to have `receive.denyCurrentBranch = updateInstead` (set on sophrosyne's `~/.git/config`). This auto-updates the work tree when pushed.
- **Sophrosyne's dotfiles repo is a normal clone at `~`** (work tree is `$HOME`, git dir is `~/.git`). `core.bare` must stay `false`. Do NOT set `core.bare = true` — it breaks the working tree. If pushes fail with "unstaged changes": (1) inspect the changes with `ssh sophrosyne.local "cd ~ && git status --short && git diff"`, (2) summarize them for the user, (3) ask whether to commit+push, discard, or stash them. `.ssh/authorized_keys` is not tracked in git; each machine's nix activation script creates the symlink to `~/.config/ssh/keys` with the correct OS-specific path.
- **When renaming a host**, keep old hostnames in SSH config during the transition. After the first rebuild with the new hostname, clean up old references in ssh config and known_hosts.
- **The `dragon` pool on sophrosyne is intentionally degraded.** One drive (`nvme-JAJP600M4TB_C2525C6C11301647512`) is kept offline on purpose. Don't panic if `zpool status` shows DEGRADED — this is expected.

- **VU dials live in a separate flake** at `/Users/scott/.config/nix-vudials` (`github:bonds/nix-vudials`). It exports `overlays.default` (vuserver + vuclient packages), `nixosModules.default`, and `darwinModules.default`. Dial UIDs are configured in `modules/vudials-uids.nix` in this repo (shared by accismus + metanoia).
- **Launchd agents auto-restart on `darwin-rebuild switch`** via an activation script that detects package hash changes. To manually bounce them: `launchctl kickstart -k gui/501/org.nixos.vuserver && launchctl kickstart -k gui/501/org.nixos.vuclient`.
- **VU dials require the FTDI VCP driver (dext)** installed once manually from [ftdichip.com/drivers/vcp-drivers/](https://ftdichip.com/drivers/vcp-drivers/). On darwin the device path is `/dev/cu.usbserial-DQ0164KM`; on NixOS it's `/dev/vuserver-DQ0164KM` (managed by udev rules in the vudials module).

- **The ollama overlay on accismus (`modules/ollama/default.nix`) is intentionally pinned.** Upstream nixpkgs ollama lags behind upstream releases. This overlay fetches the latest macOS binary directly. The pinned version is updated via the `nr` command's update capability. Do not replace this with `pkgs.ollama` or `pkgs-unstable.ollama` — it's pinned on purpose.

- **The opencode overlay on accismus (`modules/opencode/default.nix`) is intentionally pinned.** Same rationale as ollama — nixpkgs-unstable lags behind upstream opencode releases. The overlay fetches the darwin arm64 binary directly from `anomalyco/opencode/releases`. Updated via `nr --update`. Do not replace with `pkgs.opencode` — it's pinned on purpose.
  - **`opencode-desktop`** is a second binary overlay in the same file, fetching the Electron desktop `.zip` from the same releases. Strips `Contents/Resources/app-update.yml` to disable the built-in Electron auto-updater (`nr --update` is the only path). Uses `dontFixup = true`. Added to `nr --update`'s package loop alongside the CLI.
- **The neocode package on accismus is consumed via a flake input** (`github:bonds/NeoCode`). The fork's `flake.nix` exposes `packages.aarch64-darwin.default` that fetches the prebuilt `.dmg`, extracts via `7zz`, strips Sparkle auto-update keys, and re-signs ad-hoc. The DMG hash lives in NeoCode's `flake.nix`, next to the source. To update: rebase fork on upstream, run `neocode-release` from a terminal (builds in `/tmp` to avoid Xcode SCM integration fighting with the dotfiles git repo), then `nr --update` in the dotfiles repo bumps the `neocode` flake input to the new commit.
