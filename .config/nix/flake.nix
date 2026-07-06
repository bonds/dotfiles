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
    vudials.url = "github:bonds/nix-vudials";
    zen-browser = {
      url = "github:youwen5/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    polyptych.url = "github:bonds/polyptych";
  };
  outputs = inputs @ {
    self,
    nix-darwin,
    nixpkgs,
    nixpkgs-stable,
    home-manager,
    home-manager-stable,
    nix-index-database,
    vudials,
    zen-browser,
    polyptych,
  }: let
    systems = ["aarch64-darwin" "x86_64-linux"];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    darwinOverlays = [
      (import ./modules/ollama-overlay.nix)
      (import ./modules/osxphotos-overlay.nix)
      (import ./modules/zen-browser-overlay.nix)
      (import ./modules/opencode-overlay.nix)
    ];
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
        packages = [pkgs.alejandra pkgs.nix-update] ++ nixpkgs.lib.optionals (pkgs.stdenv.isLinux) [pkgs.nh];
      };
    });

    packages.aarch64-darwin = let
      pkgs = import nixpkgs {
        system = "aarch64-darwin";
        config.allowUnfree = true;
        overlays = darwinOverlays;
      };
    in {
      inherit (pkgs) ollama zen-browser opencode;
    };

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
        {nixpkgs.overlays = darwinOverlays;}
        nix-index-database.darwinModules.nix-index
        ./modules/nix.nix
        ./modules/darwin-common.nix
        ./modules/configuration-revision.nix
        ./modules/ssh-authorized-keys.nix
        ./modules/secrets-check.nix
        ./modules/packages/dev.nix
        ./modules/packages/utils.nix
        ./hosts/accismus/configuration.nix
        ./modules/home/common.nix
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
        ./modules/configuration-revision.nix
        ./modules/ssh-authorized-keys.nix
        ./modules/bash-to-fish.nix
        {modules.bash-to-fish.enable = true;}
        ./modules/minecraft-bedrock.nix
        ./modules/dst-server.nix
        ./modules/secrets-check.nix
        ./modules/packages/dev.nix
        ./modules/packages/utils.nix
        ./modules/firesafe-backup.nix
        ./hosts/sophrosyne/configuration.nix
        ./hosts/sophrosyne/hardware-configuration.nix
        nix-index-database.nixosModules.nix-index
        ./modules/home/common.nix
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
        ./modules/configuration-revision.nix
        ./modules/bash-to-fish.nix
        {
          modules.bash-to-fish = {
            enable = true;
            gnome-inhibit.enable = true;
          };
        }
        ./modules/secrets-check.nix
        ./modules/packages/dev.nix
        ./modules/packages/utils.nix
        ./hosts/metanoia/configuration.nix
        ./hosts/metanoia/hardware-configuration.nix
        vudials.nixosModules.default
        ./modules/vudials-uids.nix
        nix-index-database.nixosModules.nix-index
        ./modules/home/common.nix
        home-manager-stable.nixosModules.home-manager
      ];
    };
  };
}
