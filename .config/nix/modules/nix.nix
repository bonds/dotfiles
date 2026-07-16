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
      lib.mkDefault (base + lib.optionalString pkgs.stdenv.isLinux linuxExtras);
    nix-path = lib.mkDefault "";
    flake-registry = lib.mkDefault "";
    warn-dirty = lib.mkDefault false;
    trusted-users = lib.mkDefault ["scott"];
    max-jobs = lib.mkDefault "auto";
    auto-optimise-store = lib.mkDefault true;
    extra-trusted-substituters = lib.mkDefault [
      "https://cache.garnix.io"
      "https://nix-community.cachix.org"
      "https://zen-browser.cachix.org"
    ];
    extra-trusted-public-keys = lib.mkDefault [
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78bD7HEGj2x7a7Bs="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "zen-browser.cachix.org-1:6ABdUuAq2NIDh3tKf/5uAn7LoFO2duBBLgJMhsF3cig="
    ];
  };
  nix.package = lib.mkDefault pkgs.lixPackageSets.latest.lix;
  nix.gc = {
    automatic = lib.mkDefault true;
    options = lib.mkDefault "--delete-older-than 7d";
  };
  nix.channel.enable = lib.mkDefault false;
  nixpkgs.config.allowUnfree = lib.mkDefault true;

  # Only register nixpkgs variants as channel aliases, skip build-only inputs
  nix.registry = lib.mapAttrs (_: flake: lib.mkDefault {inherit flake;}) (
    lib.filterAttrs (n: _: lib.elem n ["nixpkgs" "nixpkgs-unstable"]) inputs
  );
  nix.nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") (
    lib.filterAttrs (n: _: lib.elem n ["nixpkgs" "nixpkgs-unstable"]) inputs
  );

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "old";
  };
}
