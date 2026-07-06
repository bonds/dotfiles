{
  mkNixos,
  vudialsPkgs,
  inputs,
}:
mkNixos "metanoia" {
  modules = [
    ./configuration.nix
    ./hardware-configuration.nix
    inputs.vudials.nixosModules.default
    ../../modules/vudials-uids.nix
  ];
  specialArgs = {
    isDarwin = false;
    inherit (vudialsPkgs) vuserver vuclient;
  };
}
