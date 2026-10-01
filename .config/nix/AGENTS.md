# AGENTS.md

> **Also see:** `~/AGENTS.md` for the full dotfiles layout — shell config,
> scripts, machine-specific details (syncthing, photos, firesafe), and
> conventions (fish, doas, git workflow).

Personal nix flake for:
- macOS laptop **accismus** (`aarch64-darwin`, nix-darwin, primary `nixos-26.05` stable to avoid cctools ld64 crash)
- NixOS server **sophrosyne** (`x86_64-linux`, `nixos-26.05`, also at `sophrosyne.local` / `home.ggr.com`)
- NixOS workstation **metanoia** (`x86_64-linux`, `nixos-26.05` — currently offline, not plugged in)

## Git repo (accismus)

Accismus dotfiles use a **bare repo at `~/.config/dotfiles/`** with **worktree `$HOME`** — the `.git` directory is not inside `.config/nix`.

- **Alias:** `config` = `git --git-dir=$HOME/.config/dotfiles/ --work-tree=$HOME`
- Defined in `~/.config/fish/conf.d/10-aliases.fish`
- When using the bare repo directly in a script, `cd ~` first so relative paths resolve
- **Remotes:** `origin` (GitHub, `git@github.com:bonds/dotfiles.git`), `sophrosyne` (scott@home.ggr.com:~/.config/dotfiles)
- Push both: `config push origin && config push sophrosyne`
- For comparison: sophrosyne's clone is a normal clone at `~` (`~/.git`)

## Commands

**Always use `nr` for rebuilds.** The `nr` fish function (in `~/.config/fish/conf.d/15-functions.fish`) wraps `nh`, auto-detects the host to pick the right flake target, and handles the split build/activation (nh as user, then exact-path sudo/doas switch). Do not recommend raw `nixos-rebuild` or `darwin-rebuild` commands unless `nr` is broken.

**Scott runs the rebuild himself with `nr` (his alias).** Do not run `nh darwin build`/`switch` or `darwin-rebuild` on his behalf — **build-only verification is fine**, he activates with `nr`.

`nr` is fish-only — from bash it fails with `command not found` but can still exit 0 with empty output and creates **no** new generation (silent no-op — easy to mistake for success). From any non-fish shell (agents, scripts, CI) run it through fish:

```bash
# Agent / script use (non-interactive fish → the tmux wrapper kicks in, so
# the build runs detached in tmux session 'nr-build'). Don't trust the exit
# code alone; poll the pane for completion:
fish -c 'nr'
tmux capture-pane -e -t nr-build -p | tail -30

# RELIABLE agent recipe (Hermes terminal tool): a plain background
# `fish -c 'nr'` can silently no-op (no tmux session, no log, exit 0, no new
# generation). Create the tmux session explicitly and poll for a sentinel:
tmux new-session -d -s nr-build 'fish -i -c "nr"; echo "NR_DONE rc=$status"'
# then poll: tmux capture-pane -t nr-build -p | tail -30  until NR_DONE
# (build ~6-10 min on accismus; activation adds a few more minutes)

# When the agent must wait for the result: force interactive status so nr
# runs in the foreground and propagates the real exit code:
fish -i -c 'nr'
```

**Terminal-tool timeout ≠ switch failure.** If a foreground `fish -i -c 'nr'` call times out, the `darwin-rebuild switch` keeps running as root — don't relaunch it. Poll `ps -p <pid>` / `readlink -f /nix/var/nix/profiles/system` until the generation advances (or the process exits). A switch that ends with the generation UNCHANGED is a failure; check the tmux pane for the error.

Verify the switch actually landed, don't trust the exit code alone. Confirm the symlink advanced and the new binary/version is present:

```bash
readlink -f /nix/var/nix/profiles/system   # should differ from before the switch
# on accismus, the thing you bumped should report the new version, e.g.:
opencode --version
```

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
flake.nix          # Inputs + shared module wiring for all machines (no nixConfig — see Gotchas)
lib/
  syncthing-ids.nix  # Centralized Syncthing device IDs (accismus + sophrosyne)
  shared-modules.nix # Module path list shared by all platforms
  mkNixos.nix        # nixosSystem builder
  mkDarwin.nix       # darwinSystem builder
  mkDarwinPackage.nix # Binary overlay helper (exposed via callPackage)
  user-home.nix      # Platform-aware home directory resolver
hosts/
  accismus/        # Laptop nix-darwin config
    configuration.nix
  metanoia/        # Workstation NixOS config
    configuration.nix
    desktop.nix
    services.nix
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
  overlays/          # Binary package overlays (mostly darwin; zen-browser is dual-platform)
    darwin.nix       #   Master list of darwin overlays (includes vudials)
    zen-browser/     #   Pinned zen-browser binary + update.sh (darwin .dmg + linux tarball, dual-platform)
    opencode/        #   Pinned opencode CLI + desktop binaries + update.sh
    daisydisk-overlay/ # Pinned DaisyDisk darwin binary + update.sh
  home/            # Home-manager modules (all machines)
    base.nix        #   Shared base: stateVersion, tmux, what-changed (reduces per-host duplication)
    direnv.nix      #   direnv configuration
    gnome.nix       #   GNOME dconf, extensions, keybindings (metanoia only)
    hermes-desktop-app.nix # Hermes Desktop .app wrapper (accismus, home.packages)
    macos-apps.nix  #   macOS GUI .app bundles via home.packages (accismus)
    misc.nix        #   WirePlumber, uBlock, fish plugins, ulauncher (metanoia only)
    orca.nix        #   Orca AIDE .app via home.packages (accismus)
    polyptych.nix   #   Polyptych (spanned fullscreen video player)
    tmux.nix        #   Catppuccin tmux theme, truecolor, cpu/ram/battery modules
    what-changed.nix #  what-changed LLM changelog summaries
    zen-policies.nix #  Zen browser policies (shared by accismus + metanoia)
  packages/         # Per-machine package lists
    dev.nix         #   Dev tools (shared: editors, languages, SCM)
    utils.nix       #   System utilities (shared: file, network, system tools)
    desktop.nix     #   metanoia workstation packages (GNOME, Steam, etc.)
    macos.nix       #   accismus-specific system packages (CLI tools, binaries)
  nixos-common.nix  # Shared NixOS settings — auto-included by mkNixos.nix (not per-host)
  darwin-agents.nix # accismus launchd user agents (extracted from the host config)
  vudials-uids.nix  # Scott's dial UID defaults (imported by both accismus + metanoia)
  bash-to-fish.nix  # Shell detection: bash → fish exec wrapper
  fish-command-not-found.nix  # nix-locate based command-not-found handler
  prune-generations.nix  # Nix generation pruning (darwin + Linux)
  ssh-authorized-keys.nix  # Symlink ~/.config/ssh/keys → ~/.ssh/authorized_keys
  ...[service modules: minecraft-bedrock, dst-server, firesafe-backup, etc.]
```

## Gotchas

- **`inputs.nixpkgs.follows` can break things on stable channels.** Letting an input follow your nixpkgs can cause build failures if the input expects newer nixpkgs APIs than the stable channel provides. If an input fails to build on a stable channel, remove its follows so it uses its own pinned nixpkgs. This has happened with home-manager and arion in the past.
- **`nix flake check` works on darwin** — NixOS configs evaluate fine cross-platform. Cannot cross-build x86_64 from aarch64 though; build directly on the target machine or deploy via `--target-host`. Runs `format-check` (alejandra), `deadnix-check`, `statix-check`, `secrets-check` (gitleaks), and `what-changed-test` (nix-what-changed's pytest suite, run from the root flake's `checks`). The non-hermetic `photo-export-test` (host Xcode) is NOT a check — it lives under `packages` and is built explicitly with `nix build .#photo-export-test` on a machine that has Xcode, because `nix flake check` builds every check and would fail without that exact Xcode.
- **Re-signing icon-baked bundles (`codesign --force --deep --sign -`).** Any overlay that rewrites a signed macOS bundle — Hermes' Info.plist+icon, opencode-desktop's `app-update.yml` removal, NeoCode — must re-sign ad-hoc as the last install step, or the broken seal makes macOS report the app as "damaged". Verify with `codesign --verify --deep --strict <app>` on the built out-path. Two traps: (1) a symlink pointing outside the bundle is an "invalid destination for symbolic link in bundle" — Hermes must COPY its `dist`/`package.json`, not symlink them, before signing; (2) osaurus is deliberately NOT re-signed and does NOT bake its icon (its bundle is notarized — see §B). **Zen is deliberately NOT in this list any more** — its bundle is a pristine `undmg` extraction and keeps Mozilla's original signature (see §B.1).
- **After changing an app's icon, relaunch the Dock (`killall Dock`) — and usually Finder too.** macOS caches app icons in `iconservices`; replacing the `.icns` in a bundle (or redeploying the bundle) does NOT refresh the Dock tile, Spotlight, or Finder. The bundle can be provably correct (`md5` of `Contents/Resources/<icon>.icns` matches, `CFBundleIconFile` points at it) while the Dock still shows the old icon. Fix: `killall Dock` (and `killall Finder` if Finder/Quick Look is stale). If it still doesn't take, `touch` the `.app` bundle and `killall Dock` again. This bit us after swapping the Raven placeholder icon — the icon was correct on disk the whole time.
- **`statix-check` must NOT use `--config`** — statix silently ignores config files inside `/nix/store` (oppiliappan/statix#71), and flake checks run with cwd = `${self}` which IS a store path. The `statix.toml` at the repo root (disabling `repeated_keys`) is auto-discovered by name, so the check runs plain `statix check .`. Don't run `statix fix` unprompted — the W20 `repeated_keys` lint is intentionally disabled because NixOS modules idiomatically repeat attrset keys (e.g. `boot.loader.*`, multiple `systemd.services.*`).
- **`nixos-rebuild switch` needs sudo.** Remote deploy from laptop uses `--target-host scott@host --use-remote-sudo`. Passwordless sudo (`NOPASSWD` in sudoers) is needed for automated deploys.
- **`flake.lock` is tracked.** Commit it after `nix flake update`.
- **`warn-dirty = false`** is set in `nix.conf` — builds work fine with uncommitted changes.
- **`flake.nix` deliberately has NO `nixConfig` block.** The binary caches are configured in `~/.config/nix/nix.conf` only (the `extra-*` variants, tracked in dotfiles). Do not add a `nixConfig` block to "keep both in sync" — there is nothing to sync. Reasons: (1) Lix defaults `accept-flake-config` to `ask`; run non-interactively (agent/CI/`nr`) it *ignores* the flake's settings with a warning rather than applying them, so the block would be noise, not effect; (2) once a setting is approved, `ConfigFile::apply` calls `globalConfig.set(name, value)`, which sets the value *globally* rather than appending `extra-*` after the daemon's list — a surprising override for a setting that already works at user level; (3) it is a privileged surface (Lix's own warning: "may allow the flake to gain root"). If you are ever tempted to add restricted settings to the flake, add them to the user `nix.conf` instead.
- **Uses `pkgs.lix`** as the nix package on all machines, not the default `pkgs.nix`.
- **`allowUnfree = true`** — required for `helvetica-neue-lt-std` font on laptop.
- **All machines use two nixpkgs:** `nixos-26.05` (stable) for most packages, `nixpkgs-unstable` for select packages (passed via `pkgs-unstable` specialArg).
- **`nix-index-database`** replaces the old `~/bin/nix-command-not-found` hand-rolled script with the upstream module.
- **`nix fmt` is unreliable.** It sometimes fails on stdin ("unexpected end of file"). When it does, run alejandra directly on the changed files instead: `alejandra <file> <file>...`.
- **Run alejandra after every nix file change.** Before building or deploying, always format any modified `.nix` files: `alejandra <file> <file>...` (from both `~/.config/nix` and `~/Documents/undated/repos/nix-vudials`).
- **NEVER commit secrets to the repo.** All secrets (passwords, API tokens, private keys) must live outside git as local-only files on the target machine. The repo only references their paths. **Exception:** agenix-encrypted `.age` blobs are safe to track (encryption makes them non-secret; that's the agenix model).
- **Secrets scanning runs via `nix flake check`** (not at build time). The `secrets-check` derivation lives in `flake/checks.nix` and runs `gitleaks detect`. The pre-push hook (`nix flake check --no-build` in `.config/git/hooks/pre-push`) evaluates all checks but doesn't build them — to run gitleaks, use `nix flake check` (without `--no-build`) or `nix build .#checks.aarch64-darwin.secrets-check`.
- **Local-only secrets on the server must have a `warn_missing` check.** If a service reads a secret file that lives outside the repo (e.g. `/etc/ddns-token`, `/etc/email-pass`), add a corresponding `warn_missing` check in `system.activationScripts.checkSecrets` in `hosts/sophrosyne/configuration.nix`. This prints a clear warning at activation time telling the admin what the secret is for and where to find it (e.g. Bitwarden).
- **After every nix file change, always run the build step to catch errors before attempting a switch.** The switch step requires `sudo` which may fail remotely; the build step catches evaluation and compilation errors first. Do not commit and push changes to sophrosyne or metanoia without first building remotely to verify they compile clean.
- **When changes require a reboot to take effect (kernel params, boot config), tell the user explicitly.** After a successful switch, check whether any changes need a reboot — `boot.kernelParams` changes always do, as do filesystem changes and some systemd settings. Say "reboot needed" rather than just "run nr".
- **After each batch of changes, commit and push to all remotes** (`git push origin && git push sophrosyne`).
- **Hooks are in `.config/git/hooks/` (tracked in git, `hooksPath = .config/git/hooks` in repo git config).** Currently: `pre-commit` (rejects `.pyc` files, checks fish formatting/syntax) and `pre-push` (runs `nix flake check --no-build` before push). Bypass the pre-push hook with `git push --no-verify`. The pre-push hook only checks the nix config subdirectory.
- **Pushing to a checked-out branch on a remote** requires the remote repo to have `receive.denyCurrentBranch = updateInstead` (set on sophrosyne's `~/.git/config`). This auto-updates the work tree when pushed.
- **Sophrosyne's dotfiles repo is a normal clone at `~`** (work tree is `$HOME`, git dir is `~/.git`). `core.bare` must stay `false`. Do NOT set `core.bare = true` — it breaks the working tree. If pushes fail with "unstaged changes": (1) inspect the changes with `ssh sophrosyne.local "cd ~ && git status --short && git diff"`, (2) summarize them for the user, (3) ask whether to commit+push, discard, or stash them. `.ssh/authorized_keys` is not tracked in git; each machine's nix activation script creates the symlink to `~/.config/ssh/keys` with the correct OS-specific path.
- **Accismus dotfiles: bare repo at `~/.config/dotfiles/`, worktree `$HOME`.**  
  The `config` alias (`alias config='git --git-dir=$HOME/.config/dotfiles/ --work-tree=$HOME'`) wraps git for this repo — use it for all add/commit/push operations. Remotes: `origin` (GitHub, `git@github.com:bonds/dotfiles.git`) and `sophrosyne` (`scott@home.ggr.com:~/.config/dotfiles`). The `config` alias is defined in `~/.config/fish/conf.d/10-aliases.fish`. If you need to use the bare repo directly (e.g. in a script or from a subdirectory), `cd ~` first so relative paths resolve correctly.
- **When renaming a host**, keep old hostnames in SSH config during the transition. After the first rebuild with the new hostname, clean up old references in ssh config and known_hosts.
- **The `dragon` pool on sophrosyne is intentionally degraded.** One drive (`nvme-JAJP600M4TB_C2525C6C11301647512`) is kept offline on purpose. Don't panic if `zpool status` shows DEGRADED — this is expected.
- **Fish `$` escaping over `ssh 'bash -c \"…\"'` bites every time.** Machines default to fish. In an `ssh host 'bash -c "…$VAR…"'` the fish layer mangles `$`/`$?` before bash sees it; always use a temp script file (`ssh host 'bash -s' < script.sh`) for anything with shell variables or `$()`. Also `$?` doesn't work in fish (use `$status`) — an easy false-"auth failed" during doas/rebuild diagnostics.
- **Nix `''…''` string interpolation traps.** In a nix `''…''` block, `$VAR` and `${VAR}` are nix interpolations. Shell variables must be written `''$VAR` to stay literal for the emitted script, while nix-package paths use `${pkgs...}` (interpolated). Getting the two mixed caused repeated "undefined variable" eval errors and activation-segment failures (e.g. `SFTP_CMD` in `photoRsyncKey`). When in doubt, `nix eval --raw` the rendered content to confirm what the script actually contains before relying on it.
- **NixOS activation snippets are wrapped in a `trap ERR` that aborts the whole switch on any non-zero step.** Any `chown`/`install`/`chmod` in an `activationScripts` snippet that returns non-zero on a re-run (already-applied state) makes the switch fail with `Activation script snippet 'X' failed` + `Failed to run activate script` (exit 2). Make snippet steps idempotent with `|| true` and end with `:` so a re-run never aborts activation. Reproduced with the `photoRsyncKey` snippet; fixed by guarding every step.

- **VU dials live in a separate flake** at `~/Documents/undated/repos/nix-vudials` (`github:bonds/nix-vudials`). It exports `overlays.default` (vuserver + vuclient packages), `nixosModules.default`, and `darwinModules.default`. Dial UIDs are configured in `modules/vudials-uids.nix` in this repo (shared by accismus + metanoia).
- **Launchd agents auto-restart on `darwin-rebuild switch`** via an activation script that detects package hash changes. To manually bounce them: `launchctl kickstart -k gui/501/org.nixos.vuserver && launchctl kickstart -k gui/501/org.nixos.vuclient`.
- **The disk dial reads Finder-consistent "available" (free + purgeable), not `df` used.** `get_disk()` in `~/Documents/undated/repos/nix-vudials/pkgs/vuclient/default.nix` shells out to `apfs_free` (a 27-line Swift tool from `luckman212/apfs-free`, installed at `/usr/local/bin/apfs_free`, **not in nixpkgs**) which calls Apple's public `URLResourceKey.volumeAvailableCapacityForImportantUsageKey` — the same number Finder/DaisyDisk show. It returns percent **used** (100 − available) to keep the dial's 0-100 used convention; falls back to `shutil.disk_usage("/")` on Linux. `df`/`diskutil` cannot report purgeable — it's a CacheDelete-computed value exposed only via that API. `apfs_free` runs in ~25ms, fine for the 1s poll.
- **Deploying a change to a github-pinned flake input from an agent:** edit `flake.nix` to `git+file:///Users/scott/Documents/undated/repos/<repo>`, run `nix flake update <input>`, `nr`, verify, commit+push the repo, revert `flake.nix` to the github URL, `nix flake update <input>` again (same rev → narHash matches, **no rebuild needed**), commit `flake.lock`, push both remotes. Note: `nix build --expr` with `--override-input` does **not** propagate through `builtins.getFlake` — the URL edit + lock update is the reliable path.
- **VU dials require the FTDI VCP driver (dext)** installed once manually from [ftdichip.com/drivers/vcp-drivers/](https://ftdichip.com/drivers/vcp-drivers/). On darwin the device path is `/dev/cu.usbserial-DQ0164KM`; on NixOS it's `/dev/vuserver-DQ0164KM` (managed by udev rules in the vudials module).

- **The opencode overlay on accismus (`modules/overlays/opencode/default.nix`) is intentionally pinned.** nixpkgs-unstable lags behind upstream opencode releases. The overlay fetches the darwin arm64 binary directly from `anomalyco/opencode/releases`. Updated via `nr --update`. Do not replace with `pkgs.opencode` — it's pinned on purpose.
  - **`opencode-desktop`** is a second binary overlay in the same file, fetching the Electron desktop `.zip` from the same releases. Strips `Contents/Resources/app-update.yml` to disable the built-in Electron auto-updater (`nr --update` is the only path). Uses `dontFixup = true`. Added to `nr --update`'s package loop alongside the CLI.
- **`nr --update` on darwin uses `update.sh` scripts, not `nix-update`.** Binary overlays under `modules/overlays/<pkg>/` are updated by their own `update.sh` scripts (called from `nr --update`), not by `nix-update`. `nix-update` doesn't work here because the packages live under `modules/overlays/` (not `pkgs/`) and use the `mkDarwinPackage` wrapper instead of `stdenv.mkDerivation`. The `update.sh` scripts handle both version bumps and SRI hash recomputation. If you add a new binary overlay, write an `update.sh` for it and wire it into `nr` — don't add it to a `nix-update` loop.
- **The neocode package on accismus is consumed via a flake input** (`github:bonds/NeoCode`). The fork's `flake.nix` exposes `packages.aarch64-darwin.default` that fetches the prebuilt `.dmg`, extracts via `7zz`, strips Sparkle auto-update keys, and re-signs ad-hoc. The DMG hash lives in NeoCode's `flake.nix`, next to the source. To update: rebase fork on upstream, run `neocode-release` from a terminal (builds in `/tmp` to avoid Xcode SCM integration fighting with the dotfiles git repo), then `nr --update` in the dotfiles repo bumps the `neocode` flake input to the new commit.
## Packaging apps (prebuilt macOS .app / Python CLIs)

Hard-won lessons from packaging GUI/CLI tools into this flake (raven, orca, DaisyDisk overlays).

### A. Prebuilt macOS .app from a DMG

- **Extract DMGs with `undmg`, not `7zz`.** 7zz drops the per-file `com.apple.cs.*` xattrs carrying the vendor's sealed-resource signature, forcing an ad-hoc re-sign — and on Sequoia `spctl` *assesses* ad-hoc-signed bundles as rejected even when `codesign --verify` passes (note: `spctl` rejection ≠ won't launch — see §B.1). `undmg` preserves the original notarized Developer ID signature so no re-sign is needed. (Exception: the neo-code overlay deliberately 7zz-extracts + ad-hoc re-signs an upstream fork that has no usable Developer ID signature.)
- **When an app won't launch ("damaged and can't be opened"), run `spctl -a -vvv -t exec <app>` FIRST.** `codesign --verify` passing is NOT sufficient — Gatekeeper requires a notarized Developer ID trust anchor. Don't chase quarantine/xattrs before checking spctl.

### B. Where the .app lives + the icon / signature mechanism

- **GUI apps live in `home.packages`** (`home.packages = [ pkgs.<app> ];`), which Home Manager copies to `~/Applications/Home Manager Apps/<App>.app` — a stable, user-owned, Spotlight-indexed path. This is the accepted, corrected arrangement (the earlier blanket "never in `environment.systemPackages`" rule is relaxed). It avoids nix-darwin's system stager, which stages apps to `/Applications/Nix Apps` and re-registers them with LaunchServices on every activation; stale registrations accumulate (old/GC'd `/nix/store` paths, dead volumes) and `open -a <name>` resolves the name across ALL registrations — landing on a rejected or nonexistent bundle → "damaged". Precedent: `modules/home/photo-export.nix`, `modules/home/orca.nix`, `modules/home/macos-apps.nix` (daisydisk, ghosttile, osaurus, openfang-desktop, zen-browser), `modules/home/hermes-desktop-app.nix`. Zen is unified across accismus + metanoia on the local `modules/overlays/zen-browser` overlay (darwin .dmg / linux tarball); see the overlay's `update.sh` and `sources.json`.
- **Custom-icon mechanism: `FinderInfo` xattr (and/or baking).** The durable, signature-safe way to display a custom icon is to apply it to the Home Manager copy with an `osascript` `NSWorkspace setIcon:forFile:options:2` call, which writes the `FinderInfo` xattr (`home.activation.zenIcon` / `home.activation.osaurusIcon` in `modules/home/macos-apps.nix`) — it is independent of the bundle and does not affect the code signature. Baking a `.icns` into the bundle (`Contents/Resources/firefox.icns`) is an optional second step, but it *rewrites* the bundle: fine only for an ad-hoc-signed/notarized-free bundle, NEVER for one with a Developer ID signature you want to keep (see the CRITICAL GOTCHA below). Zen no longer bakes — its icon is **FinderInfo-only** so the bundle stays pristine; macOS may prefer the bundle's own `Assets.car`, which is exactly why the xattr (the stronger display override) is what actually shows.
- **CRITICAL GOTCHA — baking into a Developer-ID-signed bundle breaks the seal.** Rewriting a bundle that carries a Developer ID signature + hardened runtime invalidates its code signature; Gatekeeper then kills the app with "a sealed resource is missing or invalid" (verified: `codesign -dvvv` shows `flags=0x10000(runtime)` on the broken build). A broken seal alone is fatal.
  - **Historic fix (superseded for Zen): ad-hoc re-sign** (`codesign --force --deep --sign -`) as the last install step. It drops the hardened-runtime flag (`0x10000(runtime)` → `0x2(adhoc)`), so `amfid` permits the app. **Do NOT re-sign with `--options runtime`** — adding the hardened-runtime flag back makes it fail again. This remains the adopted approach for overlays that *must* rewrite a bundle (Hermes, opencode-desktop, NeoCode). **Zen no longer needs it** because it no longer rewrites the bundle at all (§B.1).
  - **Notarized-app exception (osaurus):** a *notarized* bundle cannot be re-signed and must never have its icon baked — rewriting `Contents` invalidates its signature and Gatekeeper rejects it (and on Sequoia `spctl` rejects ad-hoc bundles outright). Its icon is applied **only** via the `FinderInfo` xattr, never baked.
  - **Better fix — don't rewrite the bundle at all.** Where a feature can be delivered outside the bundle, do that and keep the original signature. Zen does exactly this: policies via macOS managed preferences and the icon via the `FinderInfo` xattr, so the bundle is a pristine `undmg` extraction and Mozilla's Developer ID + hardened runtime survive untouched (§B.1).
- **Cleanup when a stale registration already exists:** `sudo rm -rf "/Applications/Nix Apps/<App>.app"`, then `lsregister -u <stale /nix/store path or dead /Volumes path>`, then `killall Finder`. `lsregister -u` alone is temporary — the next activation re-registers it, which is why the Home Manager move is the durable fix.

#### B.1 Zen.app: policies via managed preferences, bundle untouched (2026-10-01)

**Current design (supersedes the bake + re-sign approach below).** Zen's DMG is
`undmg`-extracted into `$out/Applications/Zen.app` and that is *all* the darwin
overlay does — no `policies.json`, no icon baking, no `codesign`. Nothing is
written into the bundle, so **Mozilla's original Developer ID signature +
hardened runtime survive** (`Authority=Developer ID Application: Mauro Baladés
(9V5K9TP787)`, `flags=0x10000(runtime)`, `codesign --verify --deep --strict`
rc=0) and **no ad-hoc re-sign is needed**. The two features that used to force a
bundle rewrite are now delivered outside it:

- **Enterprise policies → macOS managed preferences.** Set via
  `targets.darwin.defaults."app.zen-browser.zen" = { EnterprisePoliciesEnabled =
  true; } // (import ./zen-policies.nix);` in `modules/home/macos-apps.nix` —
  **not** `programs.firefox`, whose profile management (`profiles.ini`,
  `user.js`, extension prefs) would risk taking over the owner's hand-built
  2.1 GB profile ("the profile trap" below). `modules/home/zen-policies.nix`
  stays the single policy source (the Linux `wrapFirefox` branch consumes it
  too).
  - **`defaults write` is required, not a raw `.plist` write.** macOS caches
    preferences; dropping a plist file into `~/Library/Preferences` does **not**
    invalidate the cache, so Zen never sees it. Zen issue
    [zen-browser/desktop#12363](https://github.com/zen-browser/desktop/issues/12363)
    (closed "not a bug") confirms `defaults write app.zen-browser.zen <Key>
    <value>` is the supported mechanism. home-manager's `targets.darwin.defaults`
    writer emits `run /usr/bin/defaults import app.zen-browser.zen
    <generated.plist>` (verified in the generated `activate` and its
    `app.zen-browser.zen.plist`), which goes through the `defaults` CLI and
    flushes the cache — so the Nix→plist translation (nested `ExtensionSettings`,
    `Preferences` with `Status = "locked"`, bools→`true/false`, ints staying
    ints) is what Zen ends up reading. Confirmed surviving the conversion with
    `plutil -p`.

  **Verified empirically (headless, 2026-10-01).** Importing the module's exact
  generated plist via `defaults import` and launching the pristine built bundle
  headless, then reading `Services.policies` over Marionette
  (`-remote-allow-system-access` → chrome context), showed all policies active:
  `DisableTelemetry`, `DisableFirefoxStudies`, `DisableAppUpdate`,
  `ManualAppUpdateOnly`, `DisableFirefoxAccounts`, `DisableAccounts`,
  `DisableFirefoxScreenshots`, `OverrideFirstRunPage`, `OverridePostUpdatePage`,
  `DontCheckDefaultBrowser`, `DisplayBookmarksToolbar`, `EnableTrackingProtection`,
  `SearchEngines`, `Preferences` (all 19, `signon.rememberSignons` /
  `browser.contentblocking.category` reported locked) and `ExtensionSettings`
  (all 11 extensions). `DisablePocket` is set in `zen-policies.nix` but is
  **absent from `getActivePolicies()`** — Firefox removed the Pocket policy
  (Pocket was discontinued 2025); it is inert, not a misconfiguration. The same
  result was visible in a headless `about:policies` screenshot (policies listed
  under "Active"). **When re-verifying, prefer the Marionette read over an
  OCR'd screenshot** — the screenshot is legible but OCR mis-reads the long
  extension IDs.
- **Custom icon → `FinderInfo` xattr only.** `home.activation.zenIcon`
  (`NSWorkspace setIcon:forFile:options:2`) applies it to the Home Manager copy;
  since the bundle is no longer modified this is the *only* icon mechanism.

**Launch test (verified 2/2).** A temp copy of the built bundle `open`-ed twice
started the process both times (`pgrep` confirmed the
`/private/tmp/zenlaunch/.../zen` path), then the process was killed. Real prefs
were exported/restored around the test and the real `installs.ini` /
`profiles.ini` / `Profiles/` were confirmed byte-identical afterwards.

**What follows is the HISTORICAL approach — superseded, kept so the reasoning
isn't repeated blindly.** It shipped baking the icon and `policies.json` into a
`undmg`-extracted bundle with Mozilla's Developer ID signature intact → the
code-signature **seal broke** → macOS reported "Zen.app is damaged and can't be
opened" and refused to launch. The then-fix was an **ad-hoc re-sign** as the
last install step.

**The two false leads — do not repeat them.**

- *"The re-sign broke it."* Wrong — the re-sign is what **fixed** it. A single
  flaky `open` trial made the un-re-signed store bundle look like it worked. A
  repeated A/B matrix (2 rounds each) settled it: no-re-sign → FAILS 2/2,
  ad-hoc re-sign → LAUNCHES 2/2. **Always repeat launch tests; one `open` is not
  evidence.**
- *"The store bundle launches, so the deployed copy is the problem."* Same flaky
  trial, same error. The deployed copy was a **stale generation** built before
  the re-sign was added.

**The verified mechanism of that era.** A broken seal alone is **fatal**
(Gatekeeper kills the app). An ad-hoc signature is **not** fatal — it was the
cure, because `--sign -` drops the hardened-runtime flag. Re-signing ad-hoc
**with** `--options runtime` **fails** (the flag comes back). The better fix is
the one now in place: **write nothing into the bundle**, so there is no seal to
break and no re-sign to keep.

**`spctl` vs launch — not the same gate.** `spctl -a -vvv -t exec` *assesses*
against a notarized Developer ID trust anchor and will report an ad-hoc bundle
as "rejected" — yet the app still **launches** (verified). Do not treat an
`spctl` rejection as proof the app is broken; test an actual launch. Conversely,
a broken seal *does* block launch even when `codesign --verify` passes — so
check both, and trust the launch test.

**The icon display trap.** Baking the icon is necessary but **not sufficient**:
macOS may prefer the bundle's own `Assets.car` over any baked `.icns`. The
reliable override is the **FinderInfo xattr** written by the `home.activation`
step (§B). This is why the original design used it — and why removing it (in
favour of baking alone) made the custom icon disappear. With the bundle now
untouched the xattr is also the *only* mechanism.

**The profile trap — moving the app spawns a fresh profile.** Zen keys its
"install" identity by the **app's filesystem path** (a hash in
`~/Library/Application Support/zen/installs.ini`). Moving the app from
`/Applications/Nix Apps/Zen.app` to `~/Applications/Home Manager Apps/Zen.app`
changes that hash, so Zen treats it as a **brand-new install** and creates an
empty profile — your real profile (bookmarks, logins, containers) is left
behind. Fix: remap the new install hash to the existing profile in
`installs.ini` (and `profiles.ini`), e.g.

```
[7CCE27C76CD2D5B5]              # hash of ~/Applications/Home Manager Apps/Zen.app
Default=Profiles/z8ofj1q4.Default (release)
Locked=1
```

Back up both `.ini` files first. Also: **test launches create junk profiles** —
a harness that launches Zen repeatedly litters `Profiles/` with empty
`Default (release)-N` dirs and repoints `installs.ini` at them. Clean those up
and restore the real profile afterwards.

**Stale Spotlight / LaunchServices entries.** Old
`/nix/store/.../Applications/Zen.app` bundles stay indexed by Spotlight and
registered with LaunchServices. `lsregister -u <path>` unregisters them but does
**not** purge the Spotlight index — those entries clear when the store paths are
GC'd. `open -a Zen` resolves the name across ALL registrations, so a stale one
can win and produce "damaged".

### C. Python CLI/TUI apps (buildPythonApplication)

- **Prefer the release WHEEL over the sdist** when the project ships prebuilt web-UI assets — sdists often omit them and the CLI errors at runtime ("No page is built").
- **`format = "wheel"` installs NOTHING if `src` is not named `*.whl`** (wheelUnpackPhase copies to `dist/<src.name>` and the installer only matches `dist/*.whl`). Name the fetch `<pkg>-<ver>-py3-none-any.whl`.
- **Detached child processes do NOT inherit the wrapper's in-process `sys.path`.** If a package re-spawns itself via `[sys.executable, "-m", "<pkg>"]`, export `PYTHONPATH` (the package's own site-packages + propagated deps) via `makeWrapperArgs`, or the child dies with `No module named <pkg>`.
- **Version-range mismatch with nixpkgs?** Override the single dep with `overridePythonAttrs` and set `dontCheckRuntimeDeps = true` rather than letting the mismatch fail the build.
- **CLI tools never appear in Spotlight** (no .app bundle) — expected, not a bug.

### D. Verification discipline

- **Build-green is NOT done.** For GUI apps, prove `spctl -a -vvv -t exec <app>` accepts the bundle; for CLI apps, actually run the binary (`--version`, `--help`, or the failing subcommand) from the built system out-path.
- **Prefer fast checks** (`nix-instantiate --parse`, targeted `nix eval`) over full builds / `nix flake check` — long ones can blow a 30-minute agent time budget. The pre-push hook runs `nix flake check --no-build` for the heavy validation on push anyway. (Non-activating build-only verification — Scott runs `nr` himself — is already documented under Commands above.)