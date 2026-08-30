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
  metanoiaPkgs = import inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
    # The upstream vudials nixos module references config.nixpkgs.pkgs.systemd in
    # its udev remove rule; NixOS leaves nixpkgs.pkgs unset by default, which broke
    # eval with "attribute 'systemd' missing". Setting nixpkgs.pkgs here (with the
    # same overlays) fixes it — note nixpkgs.overlays is ignored once pkgs is set.
    overlays = [inputs.vudials.overlays.default];
  };
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
      {nixpkgs.pkgs = metanoiaPkgs;}
      inputs.vudials.nixosModules.default
      ../../modules/vudials-uids.nix
    ];
    specialArgs = {
      inherit (vudialsPkgs) vuserver vuclient;
    };
  }
