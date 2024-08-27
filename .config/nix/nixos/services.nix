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
  # This setups a SSH server. Very important if you're setting up a headless system.
  # Feel free to remove if you don't need it.
  services.openssh = {
    enable = true;
    settings = {
      # Opinionated: forbid root login through SSH.
      PermitRootLogin = "no";
      # Opinionated: use keys only.
      # Remove if you want to SSH using passwords
      PasswordAuthentication = false;
    };
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    extraConfig.pipewire.adjust-sample-rate = {
      "context.properties" = {
        "default.clock.rate" = 384000;
        "default.allowed-rates" = [ 384000 192000 48000 44100 ];
      };
    };
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # https://wiki.nixos.org/wiki/Ollama
  services.ollama = {
    enable = true;
    # acceleration = "rocm";
    # rocmOverrideGfx = "9.0.a";
    # environmentVariables = {
    #   HIP_VISIBLE_DEVICES = "1";
    #   HCC_AMDGPU_TARGET = "9.0.a";
    # };
  };
  
  systemd.services.ollama.serviceConfig.Restart = lib.mkForce "always";

  # Enable the fingerprint scanner
  services.fprintd.enable = true;

  # Enable <host>.local name resolution
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
      workstation = true;
    };
  };

  services = {
    syncthing = {
      enable = true;
      user = "scott";
      dataDir = "/home/scott/Documents"; # default folder for new synced folders
      configDir = "/home/scott/.config/syncthing";
    };
  };

  # Don't create default ~/Sync folder
  # https://wrycode.com/reproducible-syncthing-deployments/
  systemd.services.syncthing.environment.STNODEFAULTFOLDER = "true";

  # for the VU1s and the supporting server
  # KERNEL=="ttyUSB[0-9]", ATTR{idVendor}=="0403", ATTR{idProduct}=="6015", MODE="0666"
  services.udev.extraRules = ''
    KERNEL=="ttyUSB[0-9]", MODE="0666"
  '';

  hardware.xone.enable = true;

  systemd.services.vu1server = {
    enable = true;
    description = "VU1 server. Provides API, admin web page, and pushes updates to USB dials.";
    script = ''
      cd /home/scott/Documents/repos/VU-Server
      /run/current-system/sw/bin/nix-shell -I "nixpkgs=https://github.com/NixOS/nixpkgs/archive/refs/tags/24.05.zip" --run "python3 server.py"
    '';
    serviceConfig = {
      TimeoutStopSec = "1s";
    };
  }; 

  systemd.services.vu1monitor = {
    enable = true;
    description = "Monitor computer and push info to VU1 server.";
    wantedBy = [ "default.target" ];
    wants = [ "vu1server.service" ];
    after = [ "vu1server.service" ];
    script = "/home/scott/bin/linux/vu1";
    serviceConfig = {
      TimeoutStopSec = "5s";
    };
  }; 

  # systemd.services.vu1sleep = {
  #   enable = true;
  #   description = "Stop VU1 service when computer sleeps.";
  #   script = "systemctl stop vu1monitor.service vu1server.service";
  #   serviceConfig = {
  #     Type = "oneshot";
  #     TimeoutStopSec = "1s";
  #   };
  #   unitConfig = {
  #     Before = "sleep.target";
  #   };
  # };

  systemd.services.vu1resume = {
    enable = true;
    description = "Start VU1 service when computer wakes up.";
    script = "systemctl start vu1server.service vu1monitor.service";
    # script = "systemctl stop vu1monitor.service; systemctl stop vu1server.service; systemctl start vu1server.service; systemctl start vu1monitor.service";
    after = [ "wakeusb.service" ];
    wantedBy = [ "wakeusb.service" ];
    serviceConfig = {
      Type = "oneshot";
    };
  };

  services.pcscd.enable = true;

  # faster dbus implementation
  services.dbus.implementation = "broker";

  # IRQ balancing algorithm to distribute work to more cores for better 
  # performance
  services.irqbalance.enable = true;

  # trim SSDs to keep their performance good
  services.fstrim.enable = true;

}
