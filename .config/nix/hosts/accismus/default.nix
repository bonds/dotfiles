{
  mkDarwin,
  vudialsPkgs,
  inputs,
}:
mkDarwin "accismus" {
  modules = [
    ./configuration.nix
    inputs.vudials.darwinModules.default
    ../../modules/vudials-uids.nix
    {services.vudials.enable = true;}
  ];
  specialArgs = {
    inherit (vudialsPkgs) vuserver vuclient;
  };
}
