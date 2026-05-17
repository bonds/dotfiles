# AGENTS.md

Personal nix flake for:
- macOS laptop **accismus** (`aarch64-darwin`, nix-darwin, `nixpkgs-unstable`)
- NixOS server **sophrosyne** (`x86_64-linux`, `nixos-25.11`, also at `sophrosyne.local` / `home.ggr.com`)
- NixOS workstation **metanoia** (`x86_64-linux`, `nixos-25.11`)

## Commands

The `nr` fish function (in `~/.config/fish/config.fish`) wraps `nh` for all machines:

```fish
# Rebuild current machine (uses --hostname to pick the right flake target)
nr

# Rebuild and update all flake inputs (commits flake.lock)
nr --update

# Rebuild and update specific input only
nr -U nix-index-database
```

### accismus (laptop)

```bash
# Build (safe, does not apply changes)
darwin-rebuild build --flake .#accismus

# Switch (requires sudo) — prefer `nr` from fish instead
sudo darwin-rebuild switch --flake .#accismus

# Format: alejandra
nix fmt
```

### sophrosyne (server)

```bash
# Build (safe, does not apply changes)
nixos-rebuild build --flake .#sophrosyne

# Switch (requires sudo on the server)
sudo nixos-rebuild switch --flake .#sophrosyne

# Deploy from laptop via ssh (target-host requires sudo passwordless or --use-remote-sudo)
# home.ggr.com works from anywhere; sophrosyne.local is faster on LAN but mDNS-only
nixos-rebuild switch --flake .#sophrosyne --target-host scott@home.ggr.com --use-remote-sudo
```

### metanoia (workstation)

```bash
# Build (safe, does not apply changes)
nixos-rebuild build --flake .#metanoia

# Switch (requires sudo on the workstation)
sudo nixos-rebuild switch --flake .#metanoia

# Deploy from laptop via ssh
nixos-rebuild switch --flake .#metanoia --target-host scott@metanoia.local --use-remote-sudo
```

### Both

```bash
# Format: alejandra
nix fmt

# Update flake inputs (commit flake.lock afterward)
nix flake update
```

## Structure

```
flake.nix          # Inputs + shared module wiring for all machines
hosts/
  accismus/        # Laptop nix-darwin config
    configuration.nix
  metanoia/        # Workstation NixOS config
    configuration.nix
    hardware-configuration.nix
  sophrosyne/      # Server NixOS config
    configuration.nix
    hardware-configuration.nix
modules/           # Shared modules
  vudials-uids.nix # Scott's dial UID defaults (imported by both accismus + metanoia)
```

## Gotchas

- **`nh` is flaky on macOS.** If it breaks, fall back to plain `darwin-rebuild`.
- **`flake.lock` is tracked.** Commit it after `nix flake update`.
- **`warn-dirty = false`** is set in `nix.conf` — builds work fine with uncommitted changes.
- **Uses `pkgs.lix`** as the nix package on all machines, not the default `pkgs.nix`.
- **`allowUnfree = true`** — required for `helvetica-neue-lt-std` font on laptop.
- **Server uses two nixpkgs:** `nixos-25.11` (stable) for most packages, `nixpkgs-unstable` for ollama + tailscale (passed via `pkgs-unstable` specialArg). Same pattern for metanoia.
- **Server arion** comes from a flake input rather than `builtins.fetchTarball`.
- **`nix-index-database`** replaces the old `~/bin/nix-command-not-found` hand-rolled script with the upstream module.

- **VU dials live in a separate flake** at `/Users/scott/.config/nix-vudials` (`github:bonds/nix-vudials`). It exports `overlays.default` (vuserver + vuclient packages), `nixosModules.default`, and `darwinModules.default`. Dial UIDs are configured in `modules/vudials-uids.nix` in this repo (shared by accismus + metanoia).
- **Launchd agents auto-restart on `darwin-rebuild switch`** via an activation script that detects package hash changes. To manually bounce them: `launchctl kickstart -k gui/501/org.nixos.vuserver && launchctl kickstart -k gui/501/org.nixos.vuclient`.
- **`nix fmt` is unreliable.** It sometimes fails on stdin ("unexpected end of file"). When it does, run alejandra directly on the changed files instead: `alejandra <file> <file>...`.
- **Run alejandra after every nix file change.** Before building or deploying, always format any modified `.nix` files: `alejandra <file> <file>...` (from both `~/.config/nix` and `~/.config/nix-vudials`).
- **VU dials require the FTDI VCP driver (dext)** installed once manually from [ftdichip.com/drivers/vcp-drivers/](https://ftdichip.com/drivers/vcp-drivers/). On darwin the device path is `/dev/cu.usbserial-DQ0164KM`; on NixOS it's `/dev/vuserver-DQ0164KM` (managed by udev rules in the vudials module).
