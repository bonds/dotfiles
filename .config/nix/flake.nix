{ description = "NixOS configuration";

  inputs = { 

    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05"; 
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable"; 
    agenix.url = "github:ryantm/agenix";

    home-manager = {
      url = "github:nix-community/home-manager/release-24.05"; 
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # SFMono w/ patches
    sf-mono-liga-src = {
      url = "github:shaunsingh/SFMono-Nerd-Font-Ligaturized";
      flake = false;
    };

    # https://lix.systems/add-to-config/
    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/2.90.0.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

  };

  outputs = {
    self,
    nixpkgs, 
    nixpkgs-unstable, 
    home-manager, 
    lix-module,
    agenix,
    ... 
  } @inputs: 
    let
      inherit (self) outputs; system = "x86_64-linux"; pkgs = 
      nixpkgs.legacyPackages.${system};
    in {
      overlays = import ./overlays {inherit pkgs; inherit inputs;}; 
      nixosConfigurations.metanoia = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;}; 
        modules = [
          ./configuration.nix
          inputs.home-manager.nixosModules.default
          lix-module.nixosModules.default
          agenix.nixosModules.default
          {
            environment.systemPackages = [ agenix.packages.x86_64-linux.default ];
          }
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
