{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  nix.settings.experimental-features = let
    base = "nix-command flakes";
    linuxExtras = " auto-allocate-uids cgroups";
  in
    lib.mkDefault (base + lib.optionalString pkgs.stdenv.isLinux linuxExtras);
  nix.package = lib.mkDefault pkgs.lixPackageSets.latest.lix;
  nix.settings.nix-path = lib.mkDefault "";
  nix.settings.flake-registry = lib.mkDefault "";
  nix.settings.warn-dirty = lib.mkDefault false;
  nix.settings.trusted-users = lib.mkDefault ["scott"];
  nix.settings.max-jobs = lib.mkDefault "auto";
  nix.settings.auto-optimise-store = lib.mkDefault true;
  nix.optimise.automatic = lib.mkDefault true;
  nix.gc = {
    automatic = lib.mkDefault true;
    options = lib.mkDefault "--delete-older-than 7d";
  };
  nix.channel.enable = lib.mkDefault false;
  nixpkgs.config.allowUnfree = lib.mkDefault true;

  # Trusted binary caches (system-level nix.conf — no flake prompt)
  nix.settings.extra-trusted-substituters = lib.mkDefault [
    "https://cache.garnix.io"
    "https://nix-community.cachix.org"
    "https://zen-browser.cachix.org"
  ];
  nix.settings.extra-trusted-public-keys = lib.mkDefault [
    "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78bD7HEGj2x7a7Bs="
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    "zen-browser.cachix.org-1:6ABdUuAq2NIDh3tKf/5uAn7LoFO2duBBLgJMhsF3cig="
  ];

  # Only register nixpkgs variants as channel aliases, skip build-only inputs
  nix.registry = lib.mapAttrs (n: flake: lib.mkDefault {inherit flake;}) (
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
