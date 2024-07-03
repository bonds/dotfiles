{ description = "NixOS configuration";

  inputs = { 
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05"; 
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable"; 
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05"; 
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, ... } @inputs: let
      inherit (self) outputs; system = "x86_64-linux"; pkgs = 
      nixpkgs.legacyPackages.${system};
    in {
      overlays = import ./overlays {inherit inputs;}; 
      nixosConfigurations.metanoia = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;}; modules = [
          ./configuration.nix
          inputs.home-manager.nixosModules.default
        ];
      };
      homeConfigurations = {
        "scott@metanoia" = home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.x86_64-linux;
          extraSpecialArgs = {inherit inputs outputs;};
          modules = [./home.nix];
        };
      };
    };
}
