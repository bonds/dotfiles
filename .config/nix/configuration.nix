# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, lib, inputs, ... }:

{

  # disabledModules = [
  #   "services/misc/ollama.nix"
  # ];

  imports = [ 
    ./hardware.nix # Include the results of the hardware scan.
    ./monitors.nix
    ./wake.nix
    ./apps.nix
    ./firefox.nix
    ./python.nix
    # ./vu1.nix
    inputs.home-manager.nixosModules.default
    # "${inputs.nixpkgs-unstable}/nixos/modules/services/misc/ollama.nix"
  ];

  nixpkgs.overlays = [

    # https://github.com/shaunsingh/SFMono-Nerd-Font-Ligaturized
    (final: prev: {
      sf-mono-liga-bin = prev.stdenvNoCC.mkDerivation rec {
        pname = "sf-mono-liga-bin";
        version = "dev";
        src = inputs.sf-mono-liga-src;
        dontConfigure = true;
        installPhase = ''
          mkdir -p $out/share/fonts/opentype
          cp -R $src/*.otf $out/share/fonts/opentype/
        '';
      };
    }) 

    # https://wiki.nixos.org/wiki/GNOME
    (final: prev: {
      gnome = prev.gnome.overrideScope (gnomeFinal: gnomePrev: {
        mutter = gnomePrev.mutter.overrideAttrs (old: {
          src = pkgs.fetchFromGitLab  {
            domain = "gitlab.gnome.org";
            owner = "vanvugt";
            repo = "mutter";
            rev = "triple-buffering-v4-46";
            hash = "sha256-nz1Enw1NjxLEF3JUG0qknJgf4328W/VvdMjJmoOEMYs=";
            # hash = "sha256-fkPjB/5DPBX06t7yj0Rb3UEuu5b9mu3aS+jhH18+lpI=";
          };
        });
      });
    })

  ];

  age.secrets.vu1.file = ../secrets/vu1.age;

  # Enable the Flakes feature and the accompanying new nix command-line tool
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # https://git.2li.ch/Nebucatnetzer/nixos/commit/36d3953121d968191cd5d83cab201af70e6c864b  
  nix.settings.warn-dirty = false;

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "metanoia"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

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

  services.ollama.enable = true;
  systemd.services.ollama.serviceConfig.Restart = lib.mkForce "always";

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.scott = {
    isNormalUser = true;
    description = "Scott Bonds";
    extraGroups = [ "networkmanager" "wheel" ];
    # shell = pkgs.fish;
    packages = with pkgs; [
      home-manager
    #  thunderbird
    ];
  };

  home-manager = {
    extraSpecialArgs = { inherit inputs; };
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
    users = {
      "scott" = import ./home.nix;
    };
  };

  # Allow unfree packages.
  nixpkgs.config.allowUnfree = true;
  # nixpkgs.config.allowUnfreePredicate = (pkg: true);
  
  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };
  programs.fish.enable = true;
  programs.tmux.enable = true;
  programs.geary.enable = true;

  # https://nixos.wiki/wiki/Fish
  programs.bash = {
    interactiveShellInit = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then

        # gnome-session... tells us that gdm is up and no user is logged
        # in sitting at the machine, in which case gnome-session-inhibit will
        # error out, effectively blocking incoming SSH connections

        # if test -z "$SSH_CONNECTION" || loginctl | grep gdm > /dev/null; then
        if test -z "$SSH_CONNECTION" || ! gnome-session-inhibit --list > /dev/null 2>&1; then
          shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
          exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
        else
          from=$(echo $SSH_CONNECTION | awk '{print $1}')
          to=$(echo $SSH_CONNECTION | awk '{print $3}')
          exec gnome-session-inhibit \
              --app-id $USER@ggr.com \
              --inhibit suspend \
              --reason "SSHed into $(hostname) from $from at $(date '+%F %T')" \
              ${pkgs.fish}/bin/fish 
        fi

      fi
    '';
  };

  # https://discourse.nixos.org/t/how-can-i-resolve-this-libwayland-client-glfw-wayland-error/33824
  # https://nixos.wiki/wiki/Environment_variables
  environment.sessionVariables = rec {
    LD_LIBRARY_PATH = "${pkgs.wayland}/lib:$LD_LIBRARY_PATH";
  };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    # settings = {
    #   ClientAliveInterval = 60;
    #   ClientAliveCountMax = 3;
    # };
  };

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

  # https://wrycode.com/reproducible-syncthing-deployments/
  systemd.services.syncthing.environment.STNODEFAULTFOLDER = "true"; # Don't create default ~/Sync folder

  # for the VU1s and the supporting server
  # KERNEL=="ttyUSB[0-9]", ATTR{idVendor}=="0403", ATTR{idProduct}=="6015", MODE="0666"
  services.udev.extraRules = ''
    KERNEL=="ttyUSB[0-9]", MODE="0666"
  '';

  fonts.packages = with pkgs; [
    sf-mono-liga-bin
  ];

  # powerManagement.powerDownCommands = ''
  #   systemctl stop vu1monitor.service
  #   systemctl stop vu1server.service
  # '';

  # powerManagement.powerUpCommands = ''
  #   sleep 5
  #   systemctl restart vu1server.service
  #   systemctl restart vu1monitor.service
  # '';

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
      TimeoutStopSec = "1s";
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
    script = "systemctl stop vu1monitor.service; systemctl stop vu1server.service; systemctl start vu1server.service; systemctl start vu1monitor.service";
    after = [ "wakeusb.service" ];
    wantedBy = [ "wakeusb.service" ];
    serviceConfig = {
      Type = "oneshot";
    };
  };

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # https://discourse.nixos.org/t/option-to-configure-kernel-for-tallscreen-monitor/15986/2
  boot.kernelParams = [
    "fbcon=rotate:3"
  ];
   
  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

}
