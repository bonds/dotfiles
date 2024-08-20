# This is your system's configuration file.
# Use this to configure your system environment (it replaces /etc/nixos/configuration.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  # You can import other NixOS modules here
  imports = [
    # If you want to use modules your own flake exports (from modules/nixos):
    # outputs.nixosModules.example

    # Or modules from other flakes (such as nixos-hardware):
    # inputs.hardware.nixosModules.common-cpu-amd
    # inputs.hardware.nixosModules.common-ssd

    # You can also split up your configuration and import pieces of it here:
    # ./users.nix

    # Import your generated (nixos-generate-config) hardware configuration
    ./hardware-configuration.nix
    ./services.nix
    ./programs.nix
    ./monitors.nix
    ./wake.nix
    ./apps.nix
    ./firefox.nix
    ./python.nix
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
      # Add overlays your own flake exports (from overlays and pkgs dir):
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages

      # You can also add overlays exported from other flakes:
      # neovim-nightly-overlay.overlays.default

      # Or define it inline, for example:
      # (final: prev: {
      #   hi = final.hello.overrideAttrs (oldAttrs: {
      #     patches = [ ./change-hello-to-hi.patch ];
      #   });
      # })
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
    };
  };

  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Opinionated: disable global registry
      flake-registry = "";
      # Workaround for https://github.com/NixOS/nix/issues/9574
      nix-path = config.nix.nixPath;
      # don't keep telling me when my nix config hasn't been committed
      # to the git repro yet, I don't care!
      # https://git.2li.ch/Nebucatnetzer/nixos/commit/36d3953121d968191cd5d83cab201af70e6c864b  
      warn-dirty = false;
    };
    # Opinionated: disable channels
    channel.enable = false;

    # Opinionated: make flake registry and nix path match flake inputs
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;


  };

  networking.hostName = "metanoia";

  users.users = {
    scott = {
      description = "Scott Bonds";
      # TODO: You can set an initial password for your user.
      # If you do, you can skip setting a root password by passing '--no-root-passwd' to nixos-install.
      # Be sure to change it (using passwd) after rebooting!
      # initialPassword = "correcthorsebatterystaple";
      isNormalUser = true;
      # openssh.authorizedKeys.keys = [
      #   # TODO: Add your SSH public key(s) here, if you plan on using SSH to connect
      # ];
      # TODO: Be sure to add any other groups you need (such as networkmanager, audio, docker, etc)
      extraGroups = [ "networkmanager" "wheel" ];
    };
  };

  # decrypt and install my secrets
  age.identityPaths = [ /home/scott/.ssh/id_ed25519 ];
  age.secrets.vu1.file = /home/scott/.config/secrets/vu1.age;
  age.secrets.github.file = /home/scott/.config/secrets/github.age;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.extraModulePackages = with config.boot.kernelPackages; [
    v4l2loopback
  ];

  # Enable networking
  networking.networkmanager.enable = true;

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # enable my favorite terminal font
  fonts.packages = with pkgs; [
    sf-mono-liga-bin
  ];

  # rotate the console during boot to match my portrait monitors
  # https://discourse.nixos.org/t/option-to-configure-kernel-for-tallscreen-monitor/15986/2
  boot.kernelParams = [ "fbcon=rotate:3" ];

  # this doesn't do anything unfortunately
  # systemd.user.services.ulauncher.restartTriggers = with config; [
  #   config.environment.systemPackages
  # ];

  home-manager = {
    extraSpecialArgs = { inherit inputs; inherit outputs;};
    # useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    users = {
      "scott" = import ../home-manager/home.nix;
    };
  };

  # https://discourse.nixos.org/t/how-can-i-resolve-this-libwayland-client-glfw-wayland-error/33824
  # https://nixos.wiki/wiki/Environment_variables
  environment.sessionVariables = rec {
    LD_LIBRARY_PATH = "${pkgs.wayland}/lib:$LD_LIBRARY_PATH";
  };
  
  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "24.05";
}

