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
  };
  nix.package = lib.mkDefault pkgs.lixPackageSets.latest.lix;
  nix.gc = {
    automatic = lib.mkDefault true;
    options = lib.mkDefault "--delete-older-than 7d";
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
