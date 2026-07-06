{
  self,
  nixpkgs,
  nixpkgs-stable,
  home-manager-stable,
  nix-index-database,
  inputs,
}: let
  commonModules = import ./common-modules.nix self;
in
  hostname: {
    modules ? [],
    specialArgs ? {},
  }:
    nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs =
        {
          inherit self inputs;
          pkgs-unstable = import nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
        }
        // specialArgs;
      modules =
        commonModules
        ++ [
          nix-index-database.nixosModules.nix-index
          home-manager-stable.nixosModules.home-manager
        ]
        ++ modules;
    }
