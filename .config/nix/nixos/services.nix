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
      AllowAgentForwarding = true;
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
        "default.clock.rate" = 384000; # default = 48000
        # "default.clock.rate" = 192000; # default = 48000
        # "default.allowed-rates" = [ 192000 96000 48000 44100 ];
        # "default.clock.rate" = 44100; # default = 48000
        "default.allowed-rates" = [ 384000 192000 96000 48000 44100 ];
        # https://www.reddit.com/r/VFIO/comments/u23zn4/crackling_with_audio_passthrough_pipewire_jack/
        # "default.clock.quantum" = 2048; # default = 1024
        # "default.clock.min-quantum" = 1024; # default = 32
        # "default.clock.max-quantum" = 8192; # default 8192
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
    package = pkgs.unstable.ollama; # Uncomment if you want to use the unstable channel, see https://fictionbecomesfact.com/nixos-unstable-channel
    enable = true;
    # acceleration = "rocm";
    # rocmOverrideGfx = "11.0.2";
    environmentVariables = {
      # https://github.com/tcsenpai/spacellama
      OLLAMA_ORIGINS = "*";
      # HIP_VISIBLE_DEVICES = "1";
      # HSA_OVERRIDE_GFX_VERSION = "11.0.2";
    };
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

  hardware.xone.enable = true;

  # systemd.services.vuclient = {
  #   enable = true;
  #   description = "Monitor computer and push info to VU1 server.";
  #   wantedBy = [ "default.target" ];
  #   wants = [ "vuserver.service" ];
  #   after = [ "vuserver.service" ];
  #   # preStart = "sleep 10"; # give the server time to finish starting
  #   script = "/home/scott/bin/linux/vu1";
  #   serviceConfig = {
  #     TimeoutStopSec = "5s";
  #   };
  # }; 

  services.pcscd.enable = true;

  # faster dbus implementation
  services.dbus.implementation = "broker";

  # IRQ balancing algorithm to distribute work to more cores for better 
  # performance
  services.irqbalance.enable = true;

  # trim SSDs to keep their performance good
  services.fstrim.enable = true;

  # firmware updater, run fwupdmgr refresh and fwupdmgr get-updates
  # https://nixos.wiki/wiki/Fwupd
  services.fwupd.enable = true;

  services.vudials = {
     enable = true;
    cpudial = "6A002D000650564139323920";
    gpudial = "860043000650564139323920";
    memdial = "60003D000650564139323920";
    dskdial = "6B002A000650564139323920";
  };  

  # https://nixos.wiki/wiki/Samba
  # fileSystems."/home/scott/Music" = {
  #   device = "//util.local/media/music";
  #   fsType = "cifs";
  #   options = let
  #     # this line prevents hanging on network split
  #     automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
  #   # in ["${automount_opts},credentials=/etc/nixos/smb-secrets"];
  #   in ["${automount_opts}"];
  # };

  # https://github.com/NixOS/nixpkgs/issues/195936
  environment.sessionVariables.GST_PLUGIN_SYSTEM_PATH_1_0 = lib.makeSearchPathOutput "lib" "lib/gstreamer-1.0" (with pkgs.gst_all_1; [
    gst-plugins-good
    gst-plugins-bad
    gst-plugins-ugly
    gst-libav
  ]);

}
