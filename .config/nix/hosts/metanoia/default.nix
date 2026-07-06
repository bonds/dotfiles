{
  mkNixos,
  vudialsPkgs,
  inputs,
}:
mkNixos "metanoia" {
  modules = [
    ./configuration.nix
    ./hardware-configuration.nix
    ../../modules/bash-to-fish.nix
    {
      modules.bash-to-fish = {
        enable = true;
        gnome-inhibit.enable = true;
      };
    }
    inputs.vudials.nixosModules.default
    ../../modules/vudials-uids.nix
  ];
  specialArgs = {
    isDarwin = false;
    inherit (vudialsPkgs) vuserver vuclient;
  };
}
