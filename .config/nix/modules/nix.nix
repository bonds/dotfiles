{
  lib,
  pkgs,
  ...
}: let
  pruneGenerations = import ./prune-generations.nix {inherit pkgs;};
in {
  nix.package = lib.mkDefault pkgs.lix;
  nix.settings.nix-path = lib.mkDefault "";
  nix.settings.flake-registry = lib.mkDefault "";
  nix.settings.warn-dirty = lib.mkDefault false;
  nix.settings.trusted-users = lib.mkDefault ["scott"];
  nix.settings.max-jobs = lib.mkDefault "auto";
  nix.settings.http3 = lib.mkDefault true;
  nix.optimise.automatic = lib.mkDefault true;
  nix.gc = {
    automatic = lib.mkDefault true;
    options = lib.mkDefault "";
  };
  nix.channel.enable = lib.mkDefault false;
  nixpkgs.config.allowUnfree = lib.mkDefault true;
  environment.systemPackages = [pruneGenerations];
}
