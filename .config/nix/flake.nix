{
  # based on https://github.com/Misterio77/nix-starter-configs/tree/main/standard

  description = "Scott Bonds' config";

  inputs = {
    # all the packages, stable versions
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    # nixpkgs.url = "/home/scott/Documents/undated/repos/nixpkgs";

    # all the packages, unstable versions
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # home manager
    home-manager.url = "github:nix-community/home-manager/release-24.11";
    # home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # secrets that nix can use
    # agenix.url = "github:ryantm/agenix";
    # sops-nix.url = "github:Mic92/sops-nix";
    # sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # packages for macos
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    # https://github.com/ryanccn/nix-darwin-custom-icons
    darwin-custom-icons.url = "github:ryanccn/nix-darwin-custom-icons";
    mac-app-util.url = "github:hraban/mac-app-util";

    # nh_darwin.url = "github:ToyVo/nh_darwin";
    nh.url = "github:viperML/nh";

    # my favorite terminal font, thanks Apple!
    sf-mono-liga-src = {
      url = "github:shaunsingh/SFMono-Nerd-Font-Ligaturized";
      flake = false;
    };

    # A new and improved, Rust based, nix command replacement
    # https://lix.systems/add-to-config/
    lix-module = {
      url = "https://git.lix.systems/lix-project/nixos-module/archive/2.91.1-1.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # gui for viewing my nixos config
    nixos-conf-editor.url = "github:snowfallorg/nixos-conf-editor";

    # https://github.com/nix-community/nix-index-database
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";

    # https://ghostty.org/docs/install/binary#macos
    ghostty.url = "github:ghostty-org/ghostty";

    # realtime os baby
    # https://github.com/musnix/musnix
    # musnix.url = "github:musnix/musnix";

  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    lix-module,
    nix-darwin,
    darwin-custom-icons,
    # nh_darwin,
    nh,
    nix-index-database,
    mac-app-util,
    # sops-nix,
    ghostty,
    # agenix,
    # sops-nix,
    # musnix,
    ...
  } @ inputs: let
    inherit (self) outputs;
    # Supported systems for your flake packages, shell, etc.
    systems = [
      "x86_64-linux"
      "aarch64-darwin"
    ];
    # This is a function that generates an attribute by calling a function you
    # pass to it, with each system as an argument
    forAllSystems = nixpkgs.lib.genAttrs systems;
  in {
    # Your custom packages
    # Accessible through 'nix build', 'nix shell', etc
    packages = forAllSystems (system: import ./pkgs nixpkgs.legacyPackages.${system});
    # # Formatter for your nix files, available through 'nix fmt'
    # # Other options beside 'alejandra' include 'nixpkgs-fmt'
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

    # Your custom packages and modifications, exported as overlays
    overlays = import ./overlays {inherit inputs;};

    # Reusable nixos modules you might want to export
    # These are usually stuff you would upstream into nixpkgs
    nixosModules = import ./modules/nixos;
    # Reusable home-manager modules you might want to export
    # These are usually stuff you would upstream into home-manager
    homeManagerModules = import ./modules/home-manager;

    # NixOS configuration entrypoint
    # Available through 'nixos-rebuild --flake .#your-hostname'
    nixosConfigurations = {
      metanoia = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [
          # > Our main nixos configuration file <
          ./nixos/configuration.nix
          lix-module.nixosModules.default
          # agenix.nixosModules.default
          home-manager.nixosModules.home-manager
          nix-index-database.nixosModules.nix-index
          mac-app-util.darwinModules.default
          ghostty.packages.x86_64-linux.default
          # musnix.nixosModules.musnix
        ];
      };
      # "accismus.local" = nix-darwin.lib.darwinSystem {
      # # "accismus.local" = nixpkgs.lib.darwinSystem {
      #   specialArgs = {inherit inputs outputs;};
      #   modules = [
      #     # > Our main nixos configuration file <
      #     ./laptop
      #     darwin-custom-icons.darwinModules.default
      #     lix-module.nixosModules.default
      #     nix-index-database.darwinModules.nix-index
      #   ];
      # };
    };

    # Standalone home-manager configuration entrypoint
    # Available through 'home-manager --flake .#your-username@your-hostname'
    homeConfigurations = {
      "scott@metanoia" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux; # Home-manager requires 'pkgs' instance
        extraSpecialArgs = {inherit inputs outputs;};
        modules = [
          # > Our main home-manager configuration file <
          ./home-manager/home.nix
          # agenix.nixosModules.default
          lix-module.nixosModules.default
          nix-index-database.hmModules.nix-index
          mac-app-util.homeManagerModules.default
        ];
      };
    };

    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#Scotts-MacBook-Air
    darwinConfigurations = {
      # accismus.local = nix-darwin.lib.darwinSystem {
      "accismus" = nix-darwin.lib.darwinSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [ 
          ./laptop
          darwin-custom-icons.darwinModules.default
          lix-module.nixosModules.default
          # nh_darwin.nixDarwinModules.default
          # nh_darwin.nixDarwinModules.prebuiltin
          nix-index-database.darwinModules.nix-index
        ];
        # Set Git commit hash for darwin-version.
        system.configurationRevision = self.rev or self.dirtyRev or null;
      };
    };

    # Expose the package set, including overlays, for convenience.
    # darwinPackages = self.darwinConfigurations.accismus.local.pkgs;
    darwinPackages = self.darwinConfigurations."accismus".pkgs;
      
  };
}
