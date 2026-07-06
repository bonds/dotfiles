{
  lib,
  pkgs,
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
}
