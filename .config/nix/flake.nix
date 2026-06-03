{
  description = "Scott Bonds <scott@ggr.com> multi-machine flake (darwin + NixOS)";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
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
    mkPkgs = importNixpkgs: system:
      import importNixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
  in {
    formatter = {
      aarch64-darwin = nixpkgs.legacyPackages.aarch64-darwin.alejandra;
      x86_64-linux = nixpkgs.legacyPackages.x86_64-linux.alejandra;
    };

    checks = {
      aarch64-darwin.format-check =
        nixpkgs.legacyPackages.aarch64-darwin.runCommand "format-check"
        {buildInputs = [nixpkgs.legacyPackages.aarch64-darwin.alejandra];} ''
          cd ${self}
          alejandra -c . || (echo "Run: alejandra ." && exit 1)
          touch $out
        '';
      x86_64-linux.format-check =
        nixpkgs.legacyPackages.x86_64-linux.runCommand "format-check"
        {buildInputs = [nixpkgs.legacyPackages.x86_64-linux.alejandra];} ''
          cd ${self}
          alejandra -c . || (echo "Run: alejandra ." && exit 1)
          touch $out
        '';
      aarch64-darwin.secrets-check =
        nixpkgs.legacyPackages.aarch64-darwin.runCommand "secrets-check"
        {buildInputs = [nixpkgs.legacyPackages.aarch64-darwin.gitleaks];} ''
          cd ${self}
          gitleaks detect \
            --source . \
            --no-git \
            -c ${self}/.gitleaks.toml \
            --verbose \
            --exit-code 1
          touch $out
        '';
      x86_64-linux.secrets-check =
        nixpkgs.legacyPackages.x86_64-linux.runCommand "secrets-check"
        {buildInputs = [nixpkgs.legacyPackages.x86_64-linux.gitleaks];} ''
          cd ${self}
          gitleaks detect \
            --source . \
            --no-git \
            -c ${self}/.gitleaks.toml \
            --verbose \
            --exit-code 1
          touch $out
        '';
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
        isDarwin = true; # required by vudials module
        vuserver = (mkPkgs nixpkgs "aarch64-darwin").callPackage "${vudials}/pkgs/vuserver" {};
        vuclient = (mkPkgs nixpkgs "aarch64-darwin").callPackage "${vudials}/pkgs/vuclient" {};
      };
      modules = [
        {nixpkgs.overlays = [inputs.nix-index-database.overlays.nix-index (import ./modules/ollama-overlay.nix)];}
        nix-index-database.darwinModules.nix-index
        ./modules/nix.nix
        ./modules/secrets-check.nix
        ./modules/packages/common.nix
        ./hosts/accismus/configuration.nix
        home-manager.darwinModules.home-manager
        vudials.darwinModules.default
        ./modules/vudials-uids.nix
        ./modules/fish-command-not-found.nix
        {services.vudials.enable = true;}
      ];
    };
    nixosConfigurations.sophrosyne = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit self inputs;
        pkgs-unstable = mkPkgs nixpkgs "x86_64-linux";
      };
      modules = [
        ./modules/nix.nix
        ./modules/secrets-check.nix
        ./modules/packages/common.nix
        ./hosts/sophrosyne/configuration.nix
        ./hosts/sophrosyne/hardware-configuration.nix
        arion.nixosModules.arion
        nix-index-database.nixosModules.nix-index
        ./modules/fish-command-not-found.nix
        home-manager.nixosModules.home-manager
      ];
    };
    nixosConfigurations.metanoia = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit self inputs;
        isDarwin = false; # required by vudials module
        vuserver = (mkPkgs nixpkgs-stable "x86_64-linux").callPackage "${vudials}/pkgs/vuserver" {};
        vuclient = (mkPkgs nixpkgs-stable "x86_64-linux").callPackage "${vudials}/pkgs/vuclient" {};
        pkgs-unstable = mkPkgs nixpkgs "x86_64-linux";
      };
      modules = [
        ./modules/nix.nix
        ./modules/secrets-check.nix
        ./modules/packages/common.nix
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
