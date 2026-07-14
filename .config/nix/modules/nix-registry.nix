{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  # Only register inputs that are useful as channel aliases (nixpkgs variants).
  # Skipping: nix-darwin, home-manager, nix-index-database, flake-parts,
  # vudials, zen-browser, polyptych, neocode — these are build inputs only,
  # and registering them risks channel name collisions.
  registryInputs =
    lib.filterAttrs (
      n: _:
        lib.elem n ["nixpkgs" "nixpkgs-unstable"]
    )
    inputs;
in {
  nix = {
    registry = lib.mapAttrs (_: flake: lib.mkDefault {inherit flake;}) registryInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") registryInputs;
  };
}
