{
  mkDarwin,
  inputs,
  ...
}: let
  vudialsPkgs = import ../../lib/vudials-packages.nix inputs.vudials (
    import inputs.nixpkgs {
      system = "aarch64-darwin";
      config.allowUnfree = true;
    }
  );
in
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
