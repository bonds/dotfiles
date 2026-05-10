{
  description = "Scott Bonds <scott@ggr.com> multi-machine flake (darwin + NixOS)";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    arion.url = "github:hercules-ci/arion/v0.2.2.0";
    vudials.url = "git+file:///Users/scott/.config/nix-vudials";
  };
  outputs = inputs @ {
    self,
    nix-darwin,
    nixpkgs,
    nixpkgs-stable,
    home-manager,
    nix-index-database,
    arion,
    vudials,
  }: let
    darwinPkgs = import nixpkgs {
      system = "aarch64-darwin";
      config = {allowUnfree = true;};
    };
    linuxStablePkgs = import nixpkgs-stable {
      system = "x86_64-linux";
      config = {allowUnfree = true;};
    };
  in {
    formatter.aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.alejandra;
    darwinConfigurations."accismus" = nix-darwin.lib.darwinSystem {
      specialArgs = {
        inherit self inputs;
        vuserver = darwinPkgs.callPackage "${vudials}/pkgs/vuserver" {};
        vuclient = darwinPkgs.callPackage "${vudials}/pkgs/vuclient" {};
        isDarwin = true;
      };
      modules = [
        {nixpkgs.overlays = [inputs.nix-index-database.overlays.nix-index];}
        nix-index-database.darwinModules.nix-index
        ./hosts/accismus/configuration.nix
        home-manager.darwinModules.home-manager
        vudials.darwinModules.default
        ./modules/vudials-uids.nix
        {services.vudials.enable = true;}
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "old";
          home-manager.users.scott = {pkgs, ...}: {
            home.stateVersion = "24.11";
            home.homeDirectory = "/Users/scott";
          };
        }
      ];
    };
    nixosConfigurations.util = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        pkgs-unstable = import nixpkgs {
          system = "x86_64-linux";
          config = {allowUnfree = true;};
        };
      };
      modules = [./hosts/util/configuration.nix ./hosts/util/hardware-configuration.nix arion.nixosModules.arion];
    };
    nixosConfigurations.metanoia = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        vuserver = linuxStablePkgs.callPackage "${vudials}/pkgs/vuserver" {};
        vuclient = linuxStablePkgs.callPackage "${vudials}/pkgs/vuclient" {};
        isDarwin = false;
        pkgs-unstable = import nixpkgs {
          system = "x86_64-linux";
          config = {allowUnfree = true;};
        };
      };
      modules = [
        ./hosts/metanoia/configuration.nix
        ./hosts/metanoia/hardware-configuration.nix
        vudials.nixosModules.default
        ./modules/vudials-uids.nix
        home-manager.nixosModules.home-manager
        nix-index-database.nixosModules.nix-index
      ];
    };
  };
}
