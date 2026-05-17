{
  description = "Scott Bonds <scott@ggr.com> multi-machine flake (darwin + NixOS)";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.11";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    arion.url = "github:hercules-ci/arion/v0.2.2.0";
    vudials.url = "github:bonds/nix-vudials";
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
    pkgs-unstable = import nixpkgs {
      system = "x86_64-linux";
      config = {allowUnfree = true;};
    };
    darwinPkgs = import nixpkgs {
      system = "aarch64-darwin";
      config = {allowUnfree = true;};
    };
    linuxStablePkgs = import nixpkgs-stable {
      system = "x86_64-linux";
      config = {allowUnfree = true;};
    };
  in {
    formatter = {
      aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.alejandra;
      x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;
    };

    devShells.aarch64-darwin.default = nixpkgs.legacyPackages.aarch64-darwin.mkShell {
      packages = [nixpkgs.legacyPackages.aarch64-darwin.alejandra];
    };
    devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      packages = with nixpkgs.legacyPackages.x86_64-linux; [alejandra nh];
    };

    darwinConfigurations.accismus = nix-darwin.lib.darwinSystem {
      specialArgs = {
        inherit self inputs;
        vuserver = darwinPkgs.callPackage "${vudials}/pkgs/vuserver" {};
        vuclient = darwinPkgs.callPackage "${vudials}/pkgs/vuclient" {};
      };
      modules = [
        {nixpkgs.overlays = [inputs.nix-index-database.overlays.nix-index];}
        nix-index-database.darwinModules.nix-index
        ./hosts/accismus/configuration.nix
        home-manager.darwinModules.home-manager
        vudials.darwinModules.default
        ./modules/vudials-uids.nix
        ./modules/fish-command-not-found.nix
        {services.vudials.enable = true;}
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "old";
          home-manager.users.scott = {pkgs, ...}: {
            home.stateVersion = "24.11";
            home.homeDirectory = "/Users/scott";
            programs.fish.plugins = with pkgs.fishPlugins; [fzf-fish];
          };
        }
      ];
    };
    nixosConfigurations.sophrosyne = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        pkgs-unstable = pkgs-unstable;
      };
      modules = [
        ./hosts/sophrosyne/configuration.nix
        ./hosts/sophrosyne/hardware-configuration.nix
        arion.nixosModules.arion
        nix-index-database.nixosModules.nix-index
        ./modules/fish-command-not-found.nix
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "old";
          home-manager.users.scott = {pkgs, ...}: {
            home.stateVersion = "24.11";
            home.homeDirectory = "/home/scott";
            programs.fish.plugins = with pkgs.fishPlugins; [fzf-fish];
          };
        }
      ];
    };
    nixosConfigurations.metanoia = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit inputs;
        vuserver = linuxStablePkgs.callPackage "${vudials}/pkgs/vuserver" {};
        vuclient = linuxStablePkgs.callPackage "${vudials}/pkgs/vuclient" {};
        pkgs-unstable = pkgs-unstable;
      };
      modules = [
        ./hosts/metanoia/configuration.nix
        ./hosts/metanoia/hardware-configuration.nix
        vudials.nixosModules.default
        ./modules/vudials-uids.nix
        ./modules/fish-command-not-found.nix
        home-manager.nixosModules.home-manager
        nix-index-database.nixosModules.nix-index
      ];
    };
  };
}
