{
  description = "Scott Bonds <scott@ggr.com> multi-machine flake (darwin + NixOS)";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager-stable.url = "github:nix-community/home-manager/release-26.05";
    home-manager-stable.inputs.nixpkgs.follows = "nixpkgs-stable";
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
    home-manager-stable,
    nix-index-database,
    arion,
    vudials,
  }: let
    systems = ["aarch64-darwin" "x86_64-linux"];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    mkCheck = pkgs: name: buildInputs: script:
      pkgs.runCommand name {inherit buildInputs;} ''
        cd ${self}
        ${script}
        touch $out
      '';
  in {
    formatter = forAllSystems (pkgs: pkgs.alejandra);

    checks = forAllSystems (pkgs: {
      format-check = mkCheck pkgs "format-check" [pkgs.alejandra] ''
        alejandra -c . || (echo "Run: alejandra ." && exit 1)
      '';
      secrets-check = mkCheck pkgs "secrets-check" [pkgs.gitleaks] ''
        gitleaks detect \
          --source . \
          --no-git \
          -c ${self}/.gitleaks.toml \
          --verbose \
          --exit-code 1
      '';
    });

    devShells = forAllSystems (pkgs: {
      default = pkgs.mkShell {
        packages = [pkgs.alejandra] ++ nixpkgs.lib.optionals (pkgs.stdenv.isLinux) [pkgs.nh];
      };
    });

    darwinConfigurations.accismus = nix-darwin.lib.darwinSystem {
      specialArgs = {
        inherit self inputs;
        isDarwin = true; # required by vudials module
        vuserver = (import nixpkgs {
          system = "aarch64-darwin";
          config.allowUnfree = true;
        }).callPackage "${vudials}/pkgs/vuserver" {};
        vuclient = (import nixpkgs {
          system = "aarch64-darwin";
          config.allowUnfree = true;
        }).callPackage "${vudials}/pkgs/vuclient" {};
      };
      modules = [
        {nixpkgs.overlays = [(import ./modules/ollama-overlay.nix) (import ./modules/osxphotos-overlay.nix)];}
        nix-index-database.darwinModules.nix-index
        ./modules/nix.nix
        ./modules/secrets-check.nix
        ./modules/packages/dev.nix
        ./modules/packages/utils.nix
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
        pkgs-unstable = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
      };
      modules = [
        ./modules/nix.nix
        ./modules/secrets-check.nix
        ./modules/packages/dev.nix
        ./modules/packages/utils.nix
        ./modules/firesafe-backup.nix
        ./hosts/sophrosyne/configuration.nix
        ./hosts/sophrosyne/hardware-configuration.nix
        arion.nixosModules.arion
        nix-index-database.nixosModules.nix-index
        home-manager-stable.nixosModules.home-manager
      ];
    };
    nixosConfigurations.metanoia = nixpkgs-stable.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = {
        inherit self inputs;
        isDarwin = false; # required by vudials module
        vuserver = (import nixpkgs-stable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        }).callPackage "${vudials}/pkgs/vuserver" {};
        vuclient = (import nixpkgs-stable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        }).callPackage "${vudials}/pkgs/vuclient" {};
        pkgs-unstable = import nixpkgs {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
      };
      modules = [
        ./modules/nix.nix
        ./modules/secrets-check.nix
        ./modules/packages/dev.nix
        ./modules/packages/utils.nix
        ./hosts/metanoia/configuration.nix
        ./hosts/metanoia/hardware-configuration.nix
        vudials.nixosModules.default
        ./modules/vudials-uids.nix
        nix-index-database.nixosModules.nix-index
        home-manager-stable.nixosModules.home-manager
      ];
    };
  };
}
