{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    ./nix-registry.nix
  ];
}
