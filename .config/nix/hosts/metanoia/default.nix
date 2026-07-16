{
  mkNixos,
  inputs,
}: let
  vudialsPkgs = import ../../lib/vudials-packages.nix inputs.vudials (
    import inputs.nixpkgs {
      system = "x86_64-linux";
      config.allowUnfree = true;
    }
  );
in
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
      {nixpkgs.overlays = [inputs.vudials.overlays.default];}
      inputs.vudials.nixosModules.default
      ../../modules/vudials-uids.nix
    ];
    specialArgs = {
      inherit (vudialsPkgs) vuserver vuclient;
    };
  }
