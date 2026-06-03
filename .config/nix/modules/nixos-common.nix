# Shared NixOS settings for sophrosyne and metanoia.
{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    channel.enable = false;
    registry = lib.mapAttrs (_: flake: lib.mkDefault {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
    settings.experimental-features = lib.mkDefault "nix-command flakes auto-allocate-uids";
    settings.auto-allocate-uids = lib.mkDefault true;
  };

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

  imports = [
    ./fish-command-not-found.nix
  ];
}
