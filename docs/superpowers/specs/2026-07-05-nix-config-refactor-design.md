# Nix Config Refactor: flake-parts + DRY + audit cleanup

Date: 2026-07-05
Status: Design approved, pending spec review

## Goal

Refactor `~/.config/nix/` — a 3-machine flake (accismus/darwin, sophrosyne/NixOS,
metanoia/NixOS) — to use flake-parts, eliminate structural duplication in
`flake.nix` and across host configs, and clean up dead code/leftovers.

## Architecture

### Directory layout

```
~/.config/nix/
  flake.nix                 # ~5 lines: mkFlake { inputs; } [ ./flake/default.nix ]
  flake.lock
  flake/                    # flake-parts modules (one per output concern)
    default.nix             #   imports the 6 sub-modules
    formatter.nix           #   perSystem.formatter = alejandra
    checks.nix              #   perSystem.checks = { format-check, secrets-check }
    devShells.nix           #   perSystem.devShells.default
    packages.nix            #   flake.packages.aarch64-darwin (overlay pkgs)
    nixos.nix               #   flake.nixosConfigurations.{sophrosyne, metanoia}
    darwin.nix              #   flake.darwinConfigurations.accismus
  lib/                      # plain nix helpers (not flake-parts modules)
    common-modules.nix      #   self -> [module paths] (always-imported list)
    mkNixos.nix             #   inputs -> hostname: {modules,specialArgs} -> nixosSystem
    mkDarwin.nix            #   inputs -> hostname: {modules,specialArgs} -> darwinSystem
    darwin-overlays.nix     #   [overlay] (4 overlays, shared by mkDarwin + packages)
    vudials-packages.nix    #   vudials -> {pkgs} -> {vuserver, vuclient}
  hosts/                    # per-host wiring + config (default.nix added)
    accismus/
      default.nix           #   mkDarwin "accismus" { modules = [./configuration.nix]; ... }
      configuration.nix     #   (trimmed: no duplicated overlays/common-modules)
      syncthing-config.xml
    metanoia/
      default.nix           #   mkNixos "metanoia" { ... }
      configuration.nix     #   (trimmed: 90-line package wall -> packages/desktop.nix)
      hardware-configuration.nix
    sophrosyne/
      default.nix           #   mkNixos "sophrosyne" { ... }
      configuration.nix     #   (trimmed: duplicated settings -> nixos-common.nix)
      hardware-configuration.nix
  modules/                  # shared system/home modules (existing, reorganised)
    nix.nix                 #   (unchanged)
    nixos-common.nix        #   (expanded: +doas base, openssh hardening, tmux, nh, fstrim)
    nix-registry.nix        #   (unchanged)
    configuration-revision.nix
    ssh-authorized-keys.nix
    secrets-check.nix
    bash-to-fish.nix
    fish-command-not-found.nix
    minecraft-bedrock.nix
    dst-server.nix
    firesafe-backup.nix
    ollama-overlay.nix
    osxphotos-overlay.nix
    opencode-overlay.nix
    zen-browser-overlay.nix
    vudials-uids.nix
    prune-generations.nix
    prune-generations.sh
    packages/
      dev.nix               # (unchanged)
      utils.nix             # (unchanged)
      desktop.nix           # NEW: metanoia's desktop apps, split from configuration.nix
    home/
      common.nix            # (unchanged, now in common-modules via lib)
      direnv.nix
      gnome.nix
      misc.nix
      polyptych.nix
      tmux.nix
      what-changed.nix
      zen-policies.nix
  pkgs/                     # (unchanged)
```

### New files by concern

**`lib/common-modules.nix`** — `self -> [path]`

The always-imported module list, replacing the per-host repetition in
`flake.nix`. Contents:
- `modules/nix.nix`
- `modules/configuration-revision.nix`
- `modules/ssh-authorized-keys.nix`
- `modules/secrets-check.nix`
- `modules/packages/dev.nix`
- `modules/packages/utils.nix`
- `modules/home/common.nix`
- `modules/nix-registry.nix` (was re-exported by darwin-common/nixos-common)
- `modules/fish-command-not-found.nix` (was imported separately per-host)

**`lib/mkNixos.nix`** — `inputs -> hostname: { modules, specialArgs } -> nixosSystem`

Hardcodes:
- `system = "x86_64-linux"`
- `specialArgs.pkgs-unstable` (currently duplicated 2×)
- `common-modules` list
- `nix-index-database.nixosModules.nix-index` (currently duplicated 2×)
- `home-manager-stable.nixosModules.home-manager`

Host passes unique modules + extra specialArgs.

**`lib/mkDarwin.nix`** — `inputs -> hostname: { modules, specialArgs } -> darwinSystem`

Hardcodes:
- `specialArgs.isDarwin = true`
- `nixpkgs.overlays = darwin-overlays`
- `nixpkgs.config.allowUnfree = true`
- `common-modules` list
- `nix-index-database.darwinModules.nix-index`
- `home-manager.darwinModules.home-manager`

Host passes unique modules + extra specialArgs.

**`lib/darwin-overlays.nix`** — `[ overlay ]`

The 4 overlays: ollama, osxphotos, zen-browser, opencode. Shared by mkDarwin
and flake/packages.nix so they stay in sync.

**`lib/vudials-packages.nix`** — `vudials -> { pkgs } -> { vuserver, vuclient }`

DRYs the callPackage duplication between accismus (uses `nixpkgs`) and metanoia
(uses `nixpkgs-stable`). Each host's wiring passes its own configured `pkgs`.
The helper just stamps out the two packages.

**`flake/` — one file per output concern**

| File | Output | Replaces |
|---|---|---|
| `flake/default.nix` | imports the 6 sub-modules | — |
| `flake/formatter.nix` | `perSystem.formatter = alejandra` | `formatter = forAllSystems ...` |
| `flake/checks.nix` | `perSystem.checks.{format,secrets}` | `checks = forAllSystems ...` |
| `flake/devShells.nix` | `perSystem.devShells.default` | `devShells = forAllSystems ...` |
| `flake/packages.nix` | `flake.packages.aarch64-darwin` | `packages.aarch64-darwin = ...` |
| `flake/nixos.nix` | `flake.nixosConfigurations.{sophrosyne,metanoia}` | both nixosSystem blocks |
| `flake/darwin.nix` | `flake.darwinConfigurations.accismus` | the darwinSystem block |

The hand-rolled `forAllSystems` / `systems` list is removed — flake-parts
provides `perSystem` and a `systems` option.

**`hosts/<name>/default.nix` — wiring files**

Each is a function `{ mkNixos | mkDarwin } -> mkHost "name" { modules = [...]; }`.
Keeps "how this host is wired" in the host dir, not in a flake-level file.

- sophrosyne: `modules = [ ./configuration.nix ./hardware-configuration.nix ]`
- metanoia: adds `vudials.nixosModules.default` + `vudials-uids.nix` + vudials specialArgs
- accismus: adds `vudials.darwinModules.default` + `vudials-uids.nix` + `{services.vudials.enable = true;}` + vudials specialArgs

### Changed existing files

**`modules/nixos-common.nix` (expanded)**

Absorbs duplicated NixOS settings (*all with `lib.mkDefault`* so hosts can
override):
- `security.sudo.enable = false; security.doas.enable = true;` + the `:wheel` persist rule
- `services.openssh` hardening: `PermitRootLogin="no"`, `PasswordAuthentication=false`, `AllowAgentForwarding=true`, `KbdInteractiveAuthentication=false`
- `programs.tmux.enable = true`
- `programs.nh.enable = true; programs.nh.flake = "/home/scott/.config/nix";`
- `services.fstrim.enable = true`

Drops its `nix-registry` import (now in common-modules).

**`hosts/*/configuration.nix` (trimmed)**

Each host config drops the settings that moved to common-modules or
common-modules-nix. Hosts keep only what's unique to them:
- sophrosyne: keeps its extra doas noPass rules, pam_ssh_agent_auth, and sophrosyne-specific services (ddns, samba, zfs, minecraft, dst, etc.)
- metanoia: keeps desktop-specific config (gnome, steam, ulauncher, monitor layout, etc.)
- accismus: keeps darwin-specific items (launchd agents, syncthing config deployment, zen icon, touchid, stateVersion=6, etc.)

**`modules/packages/desktop.nix` (new)**

metanoia's ~90-line `environment.systemPackages` wall moves here. Imported by
`hosts/metanoia/configuration.nix`. Mirrors the existing `packages/dev.nix` +
`utils.nix` split.

**`modules/darwin-common.nix` (deleted)**

Only re-exported `nix-registry.nix`. Folded into `common-modules.nix` directly.

### Cleanup (dead code / leftovers)

1. **`virtualisation.podman.enable = true`** on sophrosyne — the commit
   `ffa51145` said "remove podman" but this line remained. **Removed.**
2. **Commented-out `immich` + `matter-server` blocks** in
   `hosts/sophrosyne/configuration.nix` — **deleted.**
3. **Verbose `services.avahi` block** on sophrosyne — simplified to
   `enable = false;` (the sub-option disables are all defaults).
4. **Inline hardcoded PAM public key** — the activation script
   (`system.activationScripts.doasPamAuthKeys`) currently embeds the touchid
   public key text inline. **Changed to read from `${self}/.config/ssh/keys`**
   (the tracked file, same source as `ssh-authorized-keys.nix`), installing the
   whole file to `/etc/ssh/authorized_keys.d/scott`. This is consistent with
   how ~/.ssh/authorized_keys handles all of scott's keys. (Was one key, now
   all tracked keys — behavior broadening but matches the existing SSH auth
   pattern.)
5. **`result` build symlink** — confirm it's not git-tracked (it shouldn't be
   given the repo's untracked-files-hidden config); if tracked, remove with
   `git rm --cached`.
6. **`nix.conf.reference`** — kept as-is (not referenced by anything, but
   harmless).

Eval flow: `inputs` -> `flake.nix` (mkFlake) -> `flake/*.nix` register outputs
-> `flake/nixos.nix`+`flake/darwin.nix` build mkNixos/mkDarwin from `lib/` ->
each `hosts/<name>/default.nix` calls the helper -> `common-modules` + host
`modules` compose the final system. No circular deps: `lib/` depends only on
`inputs`+`self`; `flake/` depends on `lib/`+`hosts/`; `hosts/` depends on
`lib/`+`modules/`.

## Verification & rollout

All steps in sequence, big-bang PR.

### Pre-commit (local on accismus)

1. `alejandra .` — format all `.nix` files.
2. `nix flake check` (full, not `--no-build`) — cross-evaluates all 3 configs,
   builds+runs format-check + secrets-check. **Gate.**
3. `nix build .#darwinConfigurations.accismus.system` (or `darwin-rebuild build
   --flake .#accismus`) — verifies darwin host builds. Cannot cross-build
   x86_64 NixOS from aarch64-darwin, so sophrosyne/metanoia build verified
   elsewhere.

### Commit & push

4. Commit. `flake.lock` will update (new `flake-parts` input). `nix flake lock`
   will pin it.
5. `git push origin && git push sophrosyne`. Pre-push hook runs `nix flake
   check --no-build` (eval-only). sophrosyne's
   `receive.denyCurrentBranch=updateInstead` updates its working tree on push.

### Sophrosyne (remote)

6. `ssh sophrosyne "cd ~/.config/nix && nixos-rebuild build --flake .#sophrosyne"`
   — **build first, do not switch if this fails.**
7. `ssh sophrosyne "doas /run/current-system/sw/bin/nixos-rebuild switch
   --flake .#sophrosyne"` — full path required for doas noPass rule.
8. Post-switch smoke: `systemctl status syncthing minecraft-bedrock dst-server
   firesafe-backup ddns log-temps set-max-fans`, `firesafe-status`, `zpool
   status dragon`, `tailscale status`.

### Accismus (local)

9. `nr` (or `sudo darwin-rebuild switch --flake .#accismus`).
10. Smoke: `launchctl list | grep -E 'ollama|syncthing|photos|prune'`, open Zen,
    confirm `nix flake check` clean.

### Metanoia (offline — eval only)

Covered by step 2's `nix flake check` (cross-eval). Cannot build/switch —
offline. Refactor changes structure, not packages, so build-time risk is low.
Noted in PR description.

### Rollback

- sophrosyne: `doas nixos-rebuild switch --rollback` (10 generations kept).
- accismus: `sudo darwin-rebuild switch --rollback`.
- metanoia: N/A (not switched). Old gen active until first online boot, then
  boot-into-old-gen if new gen fails.

### CI

Deferred — explicitly excluded from this PR. Pre-commit + pre-push hooks serve
as the verification gate.
