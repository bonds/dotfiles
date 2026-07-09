{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  inputs,
  self,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos-common.nix
    ../../modules/packages/desktop.nix
  ];

  networking.hostName = "metanoia";

  users.users.scott = {
    description = "Scott Bonds";
    isNormalUser = true;
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.fish;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.extraModulePackages = with config.boot.kernelPackages; [
    v4l2loopback
  ];

  networking.networkmanager.enable = true;
  networking.nftables.enable = true;

  fonts.packages = with pkgs; [
    helvetica-neue-lt-std
  ];

  boot.kernelParams = ["fbcon=rotate:3"];

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
        homeDirectory = "/home/scott";
        stateVersion = "24.05";
        packages = [
          (inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.zen-browser.override {
            extraPolicies = zenPolicies;
          })
        ];
      };

      imports = [
        ../../modules/home/gnome.nix
        ../../modules/home/misc.nix
        ../../modules/home/tmux.nix
        ../../modules/home/what-changed.nix
      ];
      programs.what-changed.enable = true;
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

  system.stateVersion = "24.05";

  users.users.root.hashedPassword = "*";

  boot.initrd.systemd.enable = true;
  boot.tmp.useTmpfs = true;
  systemd.services.nix-daemon = {
    environment.TMPDIR = "/var/tmp";
  };

  boot.loader.systemd-boot.configurationLimit = 10;

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  security.doas.extraRules = [
    {
      users = [":wheel"];
      persist = true;
    }
  ];

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    package = pkgs.steam.override {
      extraEnv = {
        GDK_SCALE = 2;
      };
    };
  };

  services.xserver.enable = true;

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  services.printing.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    extraConfig.pipewire.adjust-sample-rate = {
      "context.properties" = {
        "default.clock.rate" = 384000;
        "default.allowed-rates" = [384000 192000 96000 48000 44100];
      };
    };
  };

  services.ollama = {
    package = pkgs-unstable.ollama;
    enable = true;
  };

  systemd.services.ollama.serviceConfig.Restart = lib.mkOverride 900 "always";

  services.fprintd.enable = true;

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  services.syncthing = {
    enable = true;
    user = "scott";
    dataDir = "/home/scott/Documents";
    configDir = "/home/scott/.config/syncthing";
  };

  systemd.services.syncthing.environment.STNODEFAULTFOLDER = "true";

  hardware.xone.enable = true;

  services.pcscd.enable = true;
  services.irqbalance.enable = true;
  services.fwupd.enable = true;

  services.vudials.enable = true;

  powerManagement.powerDownCommands = lib.mkAfter ''
    systemctl stop vuclient.service
    sleep 1
  '';

  systemd.services.vuclient-wake = {
    description = "Restart vuclient after resume from sleep";
    after = ["sleep.target"];
    wantedBy = ["sleep.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/systemctl start vuclient.service";
    };
  };

  systemd.services.wakeusb = {
    serviceConfig = {
      Description = "Reset USB devices on wake from sleep";
      ExecStartPre = "/run/current-system/sw/bin/sleep 1";
      ExecStart = "/run/current-system/sw/bin/sh -c '/run/current-system/sw/bin/rmmod hid_magicmouse; /run/current-system/sw/bin/modprobe hid_magicmouse'";
      Type = "oneshot";
    };
    after = ["sleep.target"];
    wantedBy = ["sleep.target"];
  };

  systemd.tmpfiles.rules = [
    "L+ /run/gdm/.config/monitors.xml - - - - ${pkgs.writeText "gdm-monitors.xml" ''
        <!-- this should all be copied from your ~/.config/monitors.xml -->
      <monitors version="2">
        <configuration>
          <logicalmonitor>
            <x>2160</x>
            <y>0</y>
            <scale>2</scale>
            <primary>yes</primary>
            <transform>
              <rotation>left</rotation>
              <flipped>no</flipped>
            </transform>
            <monitor>
              <monitorspec>
                <connector>DP-1</connector>
                <vendor>DEL</vendor>
                <product>DELL U2718Q</product>
                <serial>4K8X78AB1J6L</serial>
              </monitorspec>
              <mode>
                <width>3840</width>
                <height>2160</height>
                <rate>59.997</rate>
              </mode>
            </monitor>
          </logicalmonitor>
          <logicalmonitor>
            <x>0</x>
            <y>0</y>
            <scale>2</scale>
            <transform>
              <rotation>left</rotation>
              <flipped>no</flipped>
            </transform>
            <monitor>
              <monitorspec>
                <connector>DP-3</connector>
                <vendor>DEL</vendor>
                <product>DELL U2718Q</product>
                <serial>4K8X796K0MLL</serial>
              </monitorspec>
              <mode>
                <width>3840</width>
                <height>2160</height>
                <rate>59.997</rate>
              </mode>
            </monitor>
          </logicalmonitor>
          <logicalmonitor>
            <x>4320</x>
            <y>0</y>
            <scale>2</scale>
            <transform>
              <rotation>left</rotation>
              <flipped>no</flipped>
            </transform>
            <monitor>
              <monitorspec>
                <connector>DP-2</connector>
                <vendor>DEL</vendor>
                <product>DELL U2718Q</product>
                <serial>4K8X799T0L2L</serial>
              </monitorspec>
              <mode>
                <width>3840</width>
                <height>2160</height>
                <rate>59.997</rate>
              </mode>
            </monitor>
          </logicalmonitor>
        </configuration>
      </monitors>

    ''}"
  ];

  systemd.user.services.ulauncher = {
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    unitConfig = {
      Description = "Linux Application Launcher";
      Documentation = ["https://ulauncher.io/"];
    };
    environment = let
      pydeps = pkgs.python3.withPackages (pp:
        with pp; [
          google
          pytz
          pint
          simpleeval
          requests
          parsedatetime
          google-api-python-client
          google-auth-oauthlib
          pydbus
          pygobject3
        ]);
    in {
      PYTHONPATH = "${pydeps}/${pydeps.sitePackages}";
    };
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 1;
      ExecStart = pkgs.writeShellScript "ulauncher-env-wrapper.sh" ''
        export PATH="''${XDG_BIN_HOME}:$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
        export GDK_BACKEND=x11
        exec ${pkgs.ulauncher}/bin/ulauncher --hide-window
      '';
    };
  };
}
