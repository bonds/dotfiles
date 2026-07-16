{
  self,
  nixpkgs,
  nixpkgs-unstable,
  home-manager,
  nix-index-database,
  agenix,
  inputs,
}: let
  commonModules = import ./shared-modules.nix self;
in
  _hostname: {
    modules ? [],
    specialArgs ? {},
  }:
    nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs =
        {
          inherit self inputs;
          isDarwin = false;
          pkgs-unstable = import nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
        }
        // specialArgs;
      modules =
        commonModules
        ++ [
          "${self}/modules/nixos-common.nix"
          nix-index-database.nixosModules.nix-index
          home-manager.nixosModules.home-manager
          agenix.nixosModules.default
        ]
        ++ modules;
    }
