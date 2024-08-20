{
  description = "Example Darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    darwin-custom-icons.url = "github:ryanccn/nix-darwin-custom-icons";
    # https://github.com/ryanccn/nix-darwin-custom-icons
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs, darwin-custom-icons }:
  let
    configuration = { pkgs, ... }: {
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      environment.systemPackages = with pkgs; [ 
        socat
        btop
        lsd
        fd
        ripgrep
        sysbench
        hyperfine
        starship
        idris2
        alacritty
        helix
        vim
      ];

      environment.customIcons = {
        enable = true;
        icons = [
          {
            path = "/Applications/Notion.app";
            icon = "/Users/scott/Documents/terminal.icns";
          }
        ];
      };

      # Auto upgrade nix package and the daemon service.
      services.nix-daemon.enable = true;
      # nix.package = pkgs.nix;

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Create /etc/zshrc that loads the nix-darwin environment.
      programs.zsh.enable = true;  # default shell on catalina
      programs.fish.enable = true;

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 4;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "x86_64-darwin";
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#Scotts-MacBook-Air
    darwinConfigurations."Scotts-MacBook-Air" = nix-darwin.lib.darwinSystem {
      modules = [ 
        configuration
        darwin-custom-icons.darwinModules.default
      ];
    };

    # Expose the package set, including overlays, for convenience.
    darwinPackages = self.darwinConfigurations."Scotts-MacBook-Air".pkgs;
  };
}
