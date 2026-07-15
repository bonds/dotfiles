{
  self,
  nixpkgs,
  nixpkgs-unstable,
  home-manager,
  nix-index-database,
  agenix,
  inputs,
}: let
  commonModules = import ./common-modules.nix self;
in
  hostname: {
    modules ? [],
    specialArgs ? {},
  }:
    nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs =
        {
          inherit self inputs;
          pkgs-unstable = import nixpkgs-unstable {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
        }
        // specialArgs;
      modules =
        commonModules
        ++ [
          nix-index-database.nixosModules.nix-index
          home-manager.nixosModules.home-manager
          agenix.nixosModules.default
        ]
        ++ modules;
    }
