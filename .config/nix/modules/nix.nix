{
  lib,
  pkgs,
  inputs,
  ...
}: {
  nix.settings = {
    experimental-features = let
      base = "nix-command flakes";
      linuxExtras = " auto-allocate-uids cgroups";
    in
      lib.mkDefault (base + lib.optionalString pkgs.stdenv.hostPlatform.isLinux linuxExtras);
    # nix-path here is the nix.conf setting (NOT derived from nix.nixPath
    # below — the NixOS/nix-darwin modules never sync these; verified: with
    # nix.nixPath non-empty, config.nix.settings.nix-path still evaluates to
    # ""). Blanking it removes the built-in `nixpkgs=/nix/...channels` search
    # path so `<nixpkgs>` cannot silently resolve to a channel; flake-based
    # lookups (`flake:nixpkgs`) still work. `nix.nixPath` below is the
    # separate NIX_PATH env var (flake: entries), which the angle-bracket
    # syntax cannot use anyway. Both are deliberate: this pins everything to
    # flakes.
    nix-path = lib.mkDefault "";
    flake-registry = lib.mkDefault "";
    warn-dirty = lib.mkDefault false;
    # priority 99 beats the platform default (["root"], priority 100). "root"
    # must stay: the daemon has no implicit root trust — trusted-users is a
    # plain replacing setting whose only default is ["root"], so listing only
    # "scott" would silently drop root's daemon rights.
    trusted-users = lib.mkOverride 99 ["root" "scott"];
    max-jobs = lib.mkDefault "auto";
    auto-optimise-store = lib.mkDefault true;
    # Binary caches for the DAEMON (garnix / nix-community / zen-browser).
    # .config/nix/nix.conf configures these at the *user* level, which only
    # helps nix run as scott (a trusted-user). Anything the daemon builds as
    # root — a root-context rebuild, a systemd-triggered build — would
    # otherwise substitute from cache.nixos.org alone and fall back to source.
    # `extra-*` APPENDS rather than replaces, so cache.nixos.org and its key
    # stay in force (the non-extra keys silently break substitution — see the
    # note in nix.conf).
    extra-substituters = lib.mkDefault "https://cache.garnix.io https://nix-community.cachix.org https://zen-browser.cachix.org";
    extra-trusted-public-keys = lib.mkDefault "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78bD7HEGj2x7a7Bs= nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs= zen-browser.cachix.org-1:6ABdUuAq2NIDh3tKf/5uAn7LoFO2duBBLgJMhsF3cig=";
  };
  nix.package = lib.mkDefault pkgs.lixPackageSets.latest.lix;
  # Generation retention is owned by ONE thing: modules/prune-generations.nix
  # (5 newest + 1/week for 4 weeks + 1/month for 6 months + 1/year for 3 years,
  # run weekly). nix.gc here therefore reclaims *store space only* and must NOT
  # delete generations: plain `nix-collect-garbage` (empty options) removes only
  # unreachable store objects, leaving every generation prune-generations chose
  # to keep intact. The previous `--delete-older-than 7d` raced it — the daily GC
  # deleted everything older than a week before the weekly prune could preserve
  # any of it. Do not re-add a `--delete-old*` flag here without removing
  # prune-generations; see nix-config-review.md F2.
  nix.gc = {
    automatic = lib.mkDefault true;
    options = lib.mkDefault "";
  };
  nix.channel.enable = lib.mkDefault false;

  nix.registry = {
    nixpkgs = lib.mkDefault {flake = inputs.nixpkgs;};
    nixpkgs-unstable = lib.mkDefault {flake = inputs.nixpkgs-unstable;};
  };
  nix.nixPath = [
    "nixpkgs=flake:nixpkgs"
    "nixpkgs-unstable=flake:nixpkgs-unstable"
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "old";
  };
}
