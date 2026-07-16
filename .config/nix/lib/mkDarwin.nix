{
  self,
  nix-darwin,
  nixpkgs-unstable,
  home-manager,
  nix-index-database,
  agenix,
  inputs,
  ...
}: let
  commonModules = import ./shared-modules.nix self;
  darwinOverlays = import ../modules/overlays/darwin.nix {inherit inputs;};
in
  _hostname: {
    modules ? [],
    specialArgs ? {},
  }:
    nix-darwin.lib.darwinSystem {
      specialArgs =
        {
          inherit self inputs;
          isDarwin = true;
          pkgs-unstable = import nixpkgs-unstable {
            system = "aarch64-darwin";
            config.allowUnfree = true;
          };
        }
        // specialArgs;
      modules =
        [
          {nixpkgs.overlays = darwinOverlays;}
          nix-index-database.darwinModules.nix-index
          home-manager.darwinModules.home-manager
          agenix.darwinModules.default
        ]
        ++ commonModules ++ modules;
    }
