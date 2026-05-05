# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Personal NixOS/nix-darwin flake managing configuration across three machines:
- **metanoia** — NixOS desktop (x86_64-linux), GNOME on Wayland, portrait monitors, AMD GPU
- **accismus** — macOS laptop (aarch64-darwin) via nix-darwin
- **util** — NixOS headless server, ZFS storage, Samba shares, Home Assistant, game servers

## Common Commands

```bash
# NixOS desktop (metanoia) — rebuild and switch
nh os switch ~/.config/nix          # preferred (nh wraps nixos-rebuild with nicer UI)
sudo nixos-rebuild switch --flake ~/.config/nix#metanoia

# macOS laptop (accismus)
darwin-rebuild build --flake ~/.config/nix#accismus

# Home Manager standalone (if used outside NixOS module)
home-manager switch --flake ~/.config/nix#scott@metanoia

# Format nix files
nix fmt

# Update flake inputs
nix flake update
```

The `nh` tool is configured with `programs.nh.flake = "/home/scott/.config/nix"` so it knows where the flake is.

## Architecture

The flake is based on [Misterio77/nix-starter-configs (standard)](https://github.com/Misterio77/nix-starter-configs/tree/main/standard).

- `flake.nix` — Entry point. Defines inputs (nixpkgs 25.05 + unstable), outputs for all three machines, overlays, custom packages, and home-manager configs.
- `nixos/configuration.nix` — Main NixOS config for **metanoia**. Imports sub-modules and wires in home-manager as a NixOS module (not standalone). Uses `doas` instead of `sudo`.
- `nixos/` — Split NixOS config: `apps.nix` (GUI/CLI packages), `services.nix` (pipewire, ollama, syncthing, avahi, vudials, etc.), `programs.nix` (fish shell, steam, nh), `monitors.nix`, `firefox.nix`, `python.nix`, `wake.nix`.
- `laptop/default.nix` — nix-darwin config for **accismus**.
- `server/configuration.nix` — NixOS config for **util** (ZFS, Samba, Syncthing, Home Assistant, Minecraft/Don't Starve via arion/docker, DDNS).
- `home-manager/home.nix` — Home Manager config for **metanoia** (dconf/GNOME settings, wireplumber config, uBlock filters, desktop entries).
- `overlays/default.nix` — Three overlays: `additions` (custom pkgs), `modifications` (SF Mono font, triple-buffered mutter), `unstable-packages` (exposes `pkgs.unstable.*`).
- `modules/nixos/` — Reusable NixOS modules. Currently just `ulauncher.nix` (systemd user service with Python deps).
- `pkgs/` — Custom package derivations: `vuserver` (Python app from SasaKaranovic/VU-Server) and `vuclient` (shell script from bonds/vuclient) for driving VU1 USB dials.
- `nixos/vudials.nix` — NixOS module for VU dials service with udev rules, systemd services, and configurable dial UIDs.

## Key Patterns

- Unstable packages are accessed via `pkgs.unstable.*` through the `unstable-packages` overlay (not a separate nixpkgs import per-file, except in `server/configuration.nix` which pins unstable to a specific commit).
- The formatter is `alejandra` (not `nixpkgs-fmt`).
- Fish is the interactive shell on all machines, launched from bash's `interactiveShellInit` to keep bash as the login shell.
- `warn-dirty = false` is set so nix doesn't complain about uncommitted flake changes.
