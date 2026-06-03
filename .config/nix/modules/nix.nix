{
  lib,
  pkgs,
  ...
}: {
  nix.package = lib.mkDefault pkgs.lix;
  nix.settings.nix-path = lib.mkDefault "";
  nix.settings.flake-registry = lib.mkDefault "";
  nix.settings.warn-dirty = lib.mkDefault false;
  nix.settings.trusted-users = lib.mkDefault ["scott"];
  nix.settings.max-jobs = lib.mkDefault "auto";
  nix.optimise.automatic = lib.mkDefault true;
  nix.gc = {
    automatic = lib.mkDefault true;
    options = lib.mkDefault "--delete-older-than 30d";
  };
  nixpkgs.config.allowUnfree = lib.mkDefault true;
}
