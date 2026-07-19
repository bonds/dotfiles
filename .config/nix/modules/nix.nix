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
    accept-flake-config = lib.mkDefault true; # pick up nixConfig from flake.nix
  };
  nix.package = lib.mkDefault pkgs.lixPackageSets.latest.lix;
  nix.gc = {
    automatic = lib.mkDefault true;
    options = lib.mkDefault "--delete-older-than 7d";
  };
  nix.channel.enable = lib.mkDefault false;
  nixpkgs.config.allowUnfree = lib.mkDefault true;

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
