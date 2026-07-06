{
  self,
  nix-darwin,
  nixpkgs,
  home-manager,
  nix-index-database,
  inputs,
}: let
  commonModules = import ./common-modules.nix self;
  darwinOverlays = import ./darwin-overlays.nix;
in
  hostname: {
    modules ? [],
    specialArgs ? {},
  }:
    nix-darwin.lib.darwinSystem {
      specialArgs =
        {
          inherit self inputs;
          isDarwin = true;
        }
        // specialArgs;
      modules =
        [
          {nixpkgs.overlays = darwinOverlays;}
          {nixpkgs.config.allowUnfree = true;}
          nix-index-database.darwinModules.nix-index
          home-manager.darwinModules.home-manager
        ]
        ++ commonModules ++ modules;
    }
