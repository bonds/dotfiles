# Nix Config Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor `~/.config/nix/` to use flake-parts, eliminate duplication, and clean up dead code.

**Architecture:** Rewrite `flake.nix` to thin `mkFlake` entry point; split outputs into `flake/*.nix` flake-parts modules; extract shared logic into `lib/*.nix` helpers; absorb duplicated NixOS settings into `modules/nixos-common.nix`; delete `modules/darwin-common.nix`; split metanoia's large `environment.systemPackages` into `modules/packages/desktop.nix`.

**Tech Stack:** Nix, flake-parts, nix-darwin, NixOS, alejandra (formatting).

## Global Constraints

- All module changes use `lib.mkDefault` so host configs can override.
- All paths in shared helpers use `${self}/...` or relative paths from the caller's directory.
- All new files must be formatted with `alejandra` before the final commit.
- `nix flake check` (full, not `--no-build`) must pass after each task.
- ALEJANDRA MUST BE RUN ON EVERY `.nix` FILE after creating or editing it. Formatting failures will break `nix flake check`.

---
### Task 1: Add flake-parts input and lock

**Files:**
- Modify: `~/.config/nix/flake.nix`

**Interfaces:** No new interfaces yet — just adds an unused input.

- [ ] **Step 1: Add flake-parts to flake.nix inputs**

Append to the `inputs` block in `~/.config/nix/flake.nix` (after the `polyptych` input, before the closing `;`):

```nix
    flake-parts.url = "github:hercules-ci/flake-parts";
```

- [ ] **Step 2: Lock the new input**

```bash
cd ~/.config/nix && nix flake lock --update-input flake-parts
```

- [ ] **Step 3: Format with alejandra**

```bash
cd ~/.config/nix && alejandra flake.nix
```

- [ ] **Step 4: Verify**

```bash
cd ~/.config/nix && nix flake check
```
Expected: passes (input is defined but unused so far).

---
### Task 2: Create lib/ helper files

**Files:**
- Create: `~/.config/nix/lib/common-modules.nix`
- Create: `~/.config/nix/lib/darwin-overlays.nix`
- Create: `~/.config/nix/lib/vudials-packages.nix`
- Create: `~/.config/nix/lib/mkNixos.nix`
- Create: `~/.config/nix/lib/mkDarwin.nix`

**Interfaces:** These files export functions but are NOT consumed by anything yet — safe to create ahead of the swap.

- [ ] **Step 1: Create `lib/common-modules.nix`**

```nix
self: [
  "${self}/modules/nix.nix"
  "${self}/modules/configuration-revision.nix"
  "${self}/modules/ssh-authorized-keys.nix"
  "${self}/modules/secrets-check.nix"
  "${self}/modules/packages/dev.nix"
  "${self}/modules/packages/utils.nix"
  "${self}/modules/home/common.nix"
  "${self}/modules/nix-registry.nix"
  "${self}/modules/fish-command-not-found.nix"
]
```

- [ ] **Step 2: Create `lib/darwin-overlays.nix`**

```nix
[
  (import ../modules/ollama-overlay.nix)
  (import ../modules/osxphotos-overlay.nix)
  (import ../modules/zen-browser-overlay.nix)
  (import ../modules/opencode-overlay.nix)
]
```

- [ ] **Step 3: Create `lib/vudials-packages.nix`**

```nix
vudials: pkgs: {
  vuserver = pkgs.callPackage "${vudials}/pkgs/vuserver" {};
  vuclient = pkgs.callPackage "${vudials}/pkgs/vuclient" {};
}
```

- [ ] **Step 4: Create `lib/mkNixos.nix`**

```nix
{ self, nixpkgs, nixpkgs-stable, home-manager-stable, nix-index-database }:
let
  commonModules = import ./common-modules.nix self;
in
hostname: { modules ? [], specialArgs ? {} }:
nixpkgs-stable.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = {
    inherit self;
    pkgs-unstable = import nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    };
  } // specialArgs;
  modules = commonModules ++ [
    nix-index-database.nixosModules.nix-index
    home-manager-stable.nixosModules.home-manager
  ] ++ modules;
}
```

- [ ] **Step 5: Create `lib/mkDarwin.nix`**

```nix
{ self, nix-darwin, nixpkgs, home-manager, nix-index-database }:
let
  commonModules = import ./common-modules.nix self;
  darwinOverlays = import ./darwin-overlays.nix;
in
hostname: { modules ? [], specialArgs ? {} }:
nix-darwin.lib.darwinSystem {
  specialArgs = {
    inherit self;
    isDarwin = true;
  } // specialArgs;
  modules = [
    { nixpkgs.overlays = darwinOverlays; }
    { nixpkgs.config.allowUnfree = true; }
    nix-index-database.darwinModules.nix-index
    home-manager.darwinModules.home-manager
  ] ++ commonModules ++ modules;
}
```

- [ ] **Step 6: Format all new files**

```bash
cd ~/.config/nix && alejandra lib/common-modules.nix lib/darwin-overlays.nix lib/vudials-packages.nix lib/mkNixos.nix lib/mkDarwin.nix
```

- [ ] **Step 7: Verify**

```bash
cd ~/.config/nix && nix flake check
```
Expected: passes (new files exist but no flake references them yet).

---
### Task 3: Create flake-parts modules, host wiring files, and desktop.nix

**Files:**
- Create: `~/.config/nix/flake/default.nix`
- Create: `~/.config/nix/flake/formatter.nix`
- Create: `~/.config/nix/flake/checks.nix`
- Create: `~/.config/nix/flake/devShells.nix`
- Create: `~/.config/nix/flake/packages.nix`
- Create: `~/.config/nix/flake/nixos.nix`
- Create: `~/.config/nix/flake/darwin.nix`
- Create: `~/.config/nix/hosts/accismus/default.nix`
- Create: `~/.config/nix/hosts/metanoia/default.nix`
- Create: `~/.config/nix/hosts/sophrosyne/default.nix`
- Create: `~/.config/nix/modules/packages/desktop.nix`

**Interfaces:** Still dead files until flake.nix swaps over.

- [ ] **Step 1: Create `flake/default.nix`**

```nix
{
  systems = ["aarch64-darwin" "x86_64-linux"];
  imports = [
    ./formatter.nix
    ./checks.nix
    ./devShells.nix
    ./packages.nix
    ./nixos.nix
    ./darwin.nix
  ];
}
```

- [ ] **Step 2: Create `flake/formatter.nix`**

```nix
{ ... }: {
  perSystem = { pkgs, ... }: {
    formatter = pkgs.alejandra;
  };
}
```

- [ ] **Step 3: Create `flake/checks.nix`**

```nix
{ self, ... }: {
  perSystem = { pkgs, ... }: let
    mkCheck = name: buildInputs: script:
      pkgs.runCommand name {inherit buildInputs;} ''
        cd ${self}
        ${script}
        touch $out
      '';
  in {
    checks = {
      format-check = mkCheck "format-check" [pkgs.alejandra] ''
        alejandra -c . || (echo "Run: alejandra ." && exit 1)
      '';
      secrets-check = mkCheck "secrets-check" [pkgs.gitleaks] ''
        gitleaks detect \
          --source . \
          --no-git \
          -c ${self}/.gitleaks.toml \
          --verbose \
          --exit-code 1
      '';
    };
  };
}
```

- [ ] **Step 4: Create `flake/devShells.nix`**

```nix
{ ... }: {
  perSystem = { pkgs, lib, ... }: {
    devShells.default = pkgs.mkShell {
      packages =
        [pkgs.alejandra pkgs.nix-update]
        ++ lib.optionals pkgs.stdenv.isLinux [pkgs.nh];
    };
  };
}
```

- [ ] **Step 5: Create `flake/packages.nix`**

```nix
{ self, inputs, ... }: let
  darwinOverlays = import ./../lib/darwin-overlays.nix;
in {
  flake.packages.aarch64-darwin = let
    pkgs = import inputs.nixpkgs {
      system = "aarch64-darwin";
      config.allowUnfree = true;
      overlays = darwinOverlays;
    };
  in {
    inherit (pkgs) ollama zen-browser opencode;
  };
}
```

- [ ] **Step 6: Create `flake/nixos.nix`**

```nix
{ self, inputs, ... }: let
  mkNixos = import ./../lib/mkNixos.nix {
    inherit self;
    inherit (inputs)
      nixpkgs nixpkgs-stable home-manager-stable nix-index-database;
  };
  vudialsPkgs = (import ./../lib/vudials-packages.nix) inputs.vudials (
    import inputs.nixpkgs-stable {
      system = "x86_64-linux";
      config.allowUnfree = true;
    }
  );
in {
  flake.nixosConfigurations = {
    sophrosyne = (import ./../hosts/sophrosyne/default.nix) { inherit mkNixos; };
    metanoia = (import ./../hosts/metanoia/default.nix) { inherit mkNixos vudialsPkgs inputs; };
  };
}
```

- [ ] **Step 7: Create `flake/darwin.nix`**

```nix
{ self, inputs, ... }: let
  mkDarwin = import ./../lib/mkDarwin.nix {
    inherit self;
    inherit (inputs)
      nix-darwin nixpkgs home-manager nix-index-database;
  };
  vudialsPkgs = (import ./../lib/vudials-packages.nix) inputs.vudials (
    import inputs.nixpkgs {
      system = "aarch64-darwin";
      config.allowUnfree = true;
    }
  );
in {
  flake.darwinConfigurations = {
    accismus = (import ./../hosts/accismus/default.nix) { inherit mkDarwin vudialsPkgs inputs; };
  };
}
```

- [ ] **Step 8: Create `hosts/sophrosyne/default.nix`**

```nix
{ mkNixos }:
mkNixos "sophrosyne" {
  modules = [
    ./configuration.nix
    ./hardware-configuration.nix
  ];
}
```

- [ ] **Step 9: Create `hosts/metanoia/default.nix`**

```nix
{ mkNixos, vudialsPkgs, inputs }:
mkNixos "metanoia" {
  modules = [
    ./configuration.nix
    ./hardware-configuration.nix
    inputs.vudials.nixosModules.default
    ../../modules/vudials-uids.nix
  ];
  specialArgs = {
    isDarwin = false;
    inherit (vudialsPkgs) vuserver vuclient;
  };
}
```

- [ ] **Step 10: Create `hosts/accismus/default.nix`**

```nix
{ mkDarwin, vudialsPkgs, inputs }:
mkDarwin "accismus" {
  modules = [
    ./configuration.nix
    inputs.vudials.darwinModules.default
    ../../modules/vudials-uids.nix
    { services.vudials.enable = true; }
  ];
  specialArgs = {
    inherit (vudialsPkgs) vuserver vuclient;
  };
}
```

- [ ] **Step 11: Create `modules/packages/desktop.nix`**

Contents: metanoia's `environment.systemPackages` block from `hosts/metanoia/configuration.nix` (lines 207–297), extracted as a standalone module. Exact content:

```nix
{
  pkgs,
  pkgs-unstable,
  ...
}: {
  environment.systemPackages = with pkgs; [
    chromium
    pkgs-unstable.ghostty
    todoist
    todoist-electron
    gapless
    lollypop
    resonance
    spot
    tagger
    jujutsu
    delta
    karere
    pkgs-unstable.python312Packages.python-kasa
    uefitool
    gamescope
    yubioath-flutter
    coreutils
    kakoune
    resources
    keeweb
    amberol
    apostrophe
    dig
    nodejs
    gcc
    libreoffice
    mesa-demos
    newsflash
    libresprite
    pkgs-unstable.mailspring
    element-desktop
    age-plugin-yubikey
    passage
    rage
    distrobox
    monophony
    kdePackages.audiotube
    zenity
    libnotify
    linuxKernel.packages.linux_zen.xone
    localsend
    easyeffects
    noise-repellent
    cargo
    rust-script
    xclip
    rocmPackages.rocminfo
    usb-reset
    gimp
    krita
    glmark2
    radeontop
    nix-search-cli
    cpu-x
    bsd-finger
    foliate
    nms
    bc
    dconf-editor
    dconf2nix
    obs-studio
    usbview
    gsound
    libgda6
    gnomeExtensions.easyeffects-preset-selector
    gnomeExtensions.pano
    pkgs-unstable.gnomeExtensions.another-window-session-manager
    gnomeExtensions.dash-to-panel
    libsecret
    jless
    spotify
    discord
    slack
    signal-desktop
    gnome-tweaks
    wmctrl
    obsidian
    dwarf-fortress
    zoom-us
    desktop-file-utils
    rustc
    wget
    usbutils
    ulauncher
    tlp
    (python3.withPackages (pp: with pp; [python-kasa]))
  ];
}
```

- [ ] **Step 12: Format all new files**

```bash
cd ~/.config/nix && alejandra flake/default.nix flake/formatter.nix flake/checks.nix flake/devShells.nix flake/packages.nix flake/nixos.nix flake/darwin.nix hosts/sophrosyne/default.nix hosts/metanoia/default.nix hosts/accismus/default.nix modules/packages/desktop.nix
```

- [ ] **Step 13: Verify**

```bash
cd ~/.config/nix && nix flake check
```
Expected: passes (old flake.nix still in use, new files are dead code).

---
### Task 4: Expand nixos-common.nix with absorbed settings

**Files:**
- Modify: `~/.config/nix/modules/nixos-common.nix`

**Note:** `darwin-common.nix` is NOT deleted yet (old flake.nix still imports
it). It will be deleted in Task 5. Host configs also still have their own
copies of the absorbed settings — both define the same values, so the module
merge is a no-op. Host configs are trimmed in Task 6.

- [ ] **Step 1: Expand `modules/nixos-common.nix`**

Replace the entire file content with:

```nix
# Shared NixOS settings for sophrosyne and metanoia.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  pruneGenerations = import ./prune-generations.nix {inherit pkgs;};
in {
  # NixOS-specific nix settings
  nix.settings.auto-allocate-uids = lib.mkDefault true;
  nix.settings.use-cgroups = lib.mkDefault true;

  time.timeZone = "America/Los_Angeles";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # NOTE: nix-registry.nix and fish-command-not-found.nix are no longer
  # imported directly here — they are provided by the shared common-modules
  # list in lib/common-modules.nix, which is added by mkNixos/mkDarwin.

  programs.command-not-found.enable = false;

  # Absorbed from per-host duplication (all with lib.mkDefault):
  programs.tmux.enable = lib.mkDefault true;
  programs.nh = {
    enable = lib.mkDefault true;
    flake = lib.mkDefault "/home/scott/.config/nix";
  };
  services.fstrim.enable = lib.mkDefault true;

  security.sudo.enable = lib.mkDefault false;
  security.doas.enable = lib.mkDefault true;

  services.openssh = {
    enable = lib.mkDefault true;
    settings = {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkDefault false;
      AllowAgentForwarding = lib.mkDefault true;
    };
  };

  systemd.services.prune-generations = {
    description = "Prune old nix system profile generations";
    after = ["nix-daemon.service"];
    wantedBy = ["timers.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pruneGenerations}/bin/prune-generations";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  systemd.timers.prune-generations = {
    description = "Weekly nix generation pruning";
    wantedBy = ["timers.target"];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };
  };
}
```

- [ ] **Step 2: Format**

```bash
cd ~/.config/nix && alejandra modules/nixos-common.nix
```

- [ ] **Step 3: Verify**

```bash
cd ~/.config/nix && nix flake check
```
Expected: passes. The old flake.nix still references darwin-common.nix (which
exists), nixos-common is expanded with mkDefault settings that match the host
configs' existing values — no duplicate-option errors.

---
### Task 5: Swap flake.nix to flake-parts + delete darwin-common.nix

**Files:**
- Modify: `~/.config/nix/flake.nix`
- Delete: `~/.config/nix/modules/darwin-common.nix`

**Note:** This is the big swap. The old flake.nix is replaced with the
flake-parts `mkFlake` entry point. The new flake.nix references `flake/*.nix`
modules and `lib/` helpers (created in Tasks 2–3) and no longer imports
`darwin-common.nix` (safe to delete).

- [ ] **Step 1: Replace `flake.nix` content**

Write the entire file at `~/.config/nix/flake.nix` with:

```nix
{
  description = "Scott Bonds <scott@ggr.com> multi-machine flake (darwin + NixOS)";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager-stable.url = "github:nix-community/home-manager/release-26.05";
    home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    vudials.url = "github:bonds/nix-vudials";
    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    polyptych.url = "github:bonds/polyptych";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };
  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} [
      ./flake/default.nix
    ];
}
```

- [ ] **Step 2: Delete darwin-common.nix**

```bash
rm ~/.config/nix/modules/darwin-common.nix
```

- [ ] **Step 3: Format new flake.nix**

```bash
cd ~/.config/nix && alejandra flake.nix
```

- [ ] **Step 4: Verify**

```bash
cd ~/.config/nix && nix flake check
```
Expected: passes. Both darwin and NixOS configs evaluate through the new
flake-parts structure. The old `forAllSystems` / `mkCheck` helper is gone —
all output concerns are handled by the individual `flake/*.nix` modules.

---
### Task 6: Trim host configs + cleanup

**Files:**
- Modify: `~/.config/nix/hosts/sophrosyne/configuration.nix`
- Modify: `~/.config/nix/hosts/metanoia/configuration.nix`
- Modify: `~/.config/nix/hosts/accismus/configuration.nix`

**Note:** Remove settings from host configs that are now provided by the
expanded `nixos-common.nix`, delete dead code, and apply cleanup items from
the audit.

- [ ] **Step 1: Trim sophrosyne configuration.nix**

Remove these blocks/lines:

1. The `programs.tmux.enable = true;` line (line 210)
2. The `services.openssh` block (lines 101–109) — replace with just:
   ```nix
   services.openssh.settings.KbdInteractiveAuthentication = false;
   ```
   (the other openssh settings are now in nixos-common)
3. The `programs.nh` block (lines 313–316) — removed entirely (in nixos-common)
4. The `services.fstrim.enable = true;` line (line 410) — in nixos-common
5. The commented `immich` / `matter-server` blocks (lines 398–404) — deleted
6. The `virtualisation.podman.enable = true;` line (line 236) — deleted
7. The verbose `services.avahi` block (lines 155–165) — replace with:
   ```nix
   services.avahi.enable = false;
   ```
8. The hardcoded PAM public key — change the activation script to read from
   `${self}/.config/ssh/keys` instead of the inline key text:
   Replace the `install` command in `system.activationScripts.doasPamAuthKeys`:
   ```nix
   install -D -m 0444 -o root -g root \
     ${pkgs.writeText "doas-ssh-agent-authorized_keys" ''
     ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBI9RFRQQRMvQ3/Mv+pg6bVxmH8HnGx9uMNh7oZv7fAYGIvr98Wr03820w9B8SxH1XiIox+IPEJsSlhBeAfzNPm0= scott@ggr.com.macbookair.touchid
   ''} \
     /etc/ssh/authorized_keys.d/scott
   ```
   with:
   ```nix
   install -D -m 0444 -o root -g root \
     ${self}/.config/ssh/keys \
     /etc/ssh/authorized_keys.d/scott
   ```

- [ ] **Step 2: Trim metanoia configuration.nix**

Remove these blocks/lines:

1. The `programs.tmux.enable = true;` line (line 107) — in nixos-common
2. The `services.openssh` block (lines 125–132) — entirely covered by nixos-common
3. The `security.sudo.enable = false; security.doas.enable = true;` lines (lines 98–99) — in nixos-common
4. The `programs.nh` block (lines 120–123) — in nixos-common
5. The `services.fstrim.enable = true;` line (line 193) — in nixos-common
6. The entire `environment.systemPackages` block (lines 207–297) — replace with:
   ```nix
   imports = [ ../../modules/packages/desktop.nix ];
   ```
   Add this to the `imports` list near the top of the config. The existing
   `imports` line (line 10–13) should become:
   ```nix
   imports = [
     ./hardware-configuration.nix
     ../../modules/nixos-common.nix
     ../../modules/packages/desktop.nix
   ];
   ```

- [ ] **Step 3: Trim accismus configuration.nix**

Accismus is darwin — nixos-common settings don't apply. The only change:
remove the `environment.systemPackages` entries for `ollama`, `zen-browser`,
`opencode` if they are exclusively provided by the overlay packages output
(rather than from nixpkgs). Actually these packages are installed by the
overlay into the system profile — the packages list in `configuration.nix`
includes `ollama`, `zen-browser`, `opencode` from `pkgs` (which resolves via
the overlay). They are still available via `pkgs` since the overlay is applied
in mkDarwin. **No trimming needed for accismus.**

- [ ] **Step 4: Format all modified files**

```bash
cd ~/.config/nix && alejandra hosts/sophrosyne/configuration.nix hosts/metanoia/configuration.nix
```

- [ ] **Step 5: Verify**

```bash
cd ~/.config/nix && nix flake check
```
Expected: passes. All duplicated settings removed; host configs only contain
what's unique to each host.

---
### Task 7: Full verification + format pass + commit

**Files:** All changed files.

- [ ] **Step 1: Full format pass**

```bash
cd ~/.config/nix && alejandra flake.nix lib/ flake/ hosts/ modules/
```

- [ ] **Step 2: Final `nix flake check`**

```bash
cd ~/.config/nix && nix flake check
```
Expected: passes with no warnings.

- [ ] **Step 3: Local build verification on accismus**

```bash
cd ~/.config/nix && darwin-rebuild build --flake .#accismus
```
Expected: builds successfully. (Only darwin can be built locally; NixOS hosts
are cross-eval only and get verified on sophrosyne.)

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "refactor: flake-parts migration + DRY + audit cleanup"
```
Include the design doc and plan in the commit:
```bash
git add -A .config/nix/ docs/ && git commit -m "refactor: flake-parts migration + DRY + audit cleanup"
```

- [ ] **Step 5: Push to both remotes**

```bash
git push origin && git push sophrosyne
```
The pre-push hook runs `nix flake check --no-build`. sophrosyne's
`receive.denyCurrentBranch = updateInstead` updates its working tree on push.

- [ ] **Step 6: Build and switch on sophrosyne**

```bash
ssh sophrosyne "cd ~/.config/nix && nixos-rebuild build --flake .#sophrosyne && doas /run/current-system/sw/bin/nixos-rebuild switch --flake .#sophrosyne"
```

- [ ] **Step 7: Post-switch smoke checks on sophrosyne**

```bash
ssh sophrosyne 'doas /run/current-system/sw/bin/systemctl status syncthing minecraft-bedrock dst-server ddns log-temps'
```
Also check: `doas firesafe-status`, `doas zpool status dragon` (should still
show DEGRADED-by-design), `tailscale status`.

- [ ] **Step 8: Switch on accismus**

```bash
cd ~/.config/nix && nr
```
Verify: `launchctl list | grep -E 'ollama|syncthing|photos|prune'`,
open Zen browser, confirm `nix flake check` clean.

- [ ] **Step 9: Note metanoia status**

metanoia is offline — eval-only verification was done in Step 2. Document in
the commit/PR that structural verification passes but runtime switch is
blocked until metanoia is online.

<｜｜DSML｜｜tool_calls>
<｜｜DSML｜｜invoke name="edit">
<｜｜DSML｜｜parameter name="filePath" string="true">/Users/scott/docs/superpowers/plans/2026-07-05-nix-config-refactor.md