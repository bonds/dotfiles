{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: let
  userHome = import ../../lib/user-home.nix pkgs;
in {
  imports = [
    ./hardware-configuration.nix
    ./desktop.nix
    ./services.nix
    ../../modules/packages/desktop.nix
    ../../modules/ollama-server.nix
  ];

  networking = {
    hostName = "metanoia";
    networkmanager.enable = true;
    nftables.enable = true;
  };

  users.users.scott = {
    description = "Scott Bonds";
    isNormalUser = true;
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.fish;
  };

  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 10;
      };
      efi.canTouchEfiVariables = true;
    };
    extraModulePackages = with config.boot.kernelPackages; [
      v4l2loopback
    ];
    kernelParams = ["fbcon=rotate:3"];
    initrd.systemd.enable = true;
    tmp.useTmpfs = true;
  };

  fonts.packages = with pkgs; [
    helvetica-neue-lt-std
  ];

  home-manager = {
    extraSpecialArgs = {
      inherit inputs;
    };
    users.scott = {
      pkgs,
      inputs,
      ...
    }: let
      zenPolicies = import ../../modules/home/zen-policies.nix;
    in {
      home = {
        username = "scott";
        homeDirectory = userHome;
        packages = [
          (inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.zen-browser.override {
            extraPolicies = zenPolicies;
          })
        ];
      };

      imports = [
        ../../modules/home/base.nix
        ../../modules/home/gnome.nix
        ../../modules/home/misc.nix
      ];
    };
  };

  environment.sessionVariables = rec {
    LD_LIBRARY_PATH = "${pkgs.wayland}/lib:$LD_LIBRARY_PATH";
    GST_PLUGIN_SYSTEM_PATH_1_0 = lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" (with pkgs.gst_all_1; [
      gst-plugins-good
      gst-plugins-bad
      gst-plugins-ugly
      gst-libav
    ]);
  };

  system.stateVersion = "26.05";

  users.users.root.hashedPassword = "*";

  security.doas.extraRules = [
    {
      users = [":wheel"];
      persist = true;
    }
  ];
}
