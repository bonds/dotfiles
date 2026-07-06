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
    registry = lib.mapAttrs (_: flake: lib.mkDefault {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };
}
