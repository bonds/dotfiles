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
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "old";
    users.scott = {pkgs, ...}: {
      home = {
        username = "scott";
        homeDirectory = "/home/scott";
        stateVersion = "24.05";
      };

      imports = [
        ../../modules/home/gnome.nix
        ../../modules/home/firefox.nix
        ../../modules/home/misc.nix
        ../../modules/home/tmux.nix
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

  system.stateVersion = "24.05";

  system.configurationRevision = self.rev or self.dirtyRev or null;

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

  security.doas.enable = true;
  security.sudo.enable = false;
  security.doas.extraRules = [
    {
      users = [":wheel"];
      persist = true;
    }
  ];

  programs.tmux.enable = true;
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

  programs.bash = {
    interactiveShellInit = ''
      source ${pkgs.nix-index}/etc/profile.d/command-not-found.sh
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then

        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        # exec ${pkgs.fish}/bin/fish $LOGIN_OPTION

        # gnome-session... tells us that gdm is up and no user is logged
        # in sitting at the machine, in which case gnome-session-inhibit will
        # error out, effectively blocking incoming SSH connections

        if test -z "$SSH_CONNECTION" || ! gnome-session-inhibit --list > /dev/null 2>&1; then
          exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
        else
          from=$(echo $SSH_CONNECTION | awk '{print $1}')
          to=$(echo $SSH_CONNECTION | awk '{print $3}')
          exec gnome-session-inhibit \
              --app-id $USER@ggr.com \
              --inhibit suspend \
              --reason "SSHed into $(hostname) from $from at $(date '+%F %T')" \
              ${pkgs.fish}/bin/fish $LOGIN_OPTION
        fi
      fi
    '';
  };

  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/home/scott/.config/nix";
  };

  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      AllowAgentForwarding = true;
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
        "default.allowed-rates" = [384000 192000 96000 48000 44100];
      };
    };
  };

  services.ollama = {
    package = pkgs-unstable.ollama;
    enable = true;
    environmentVariables = {
      OLLAMA_ORIGINS = "*";
    };
  };

  systemd.services.ollama.serviceConfig.Restart = lib.mkForce "always";

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
  services.fstrim.enable = true;
  services.fwupd.enable = true;

  services.vudials.enable = true;

  powerManagement.powerDownCommands = lib.mkAfter ''
    systemctl stop vuclient.service
    sleep 1
  '';

  powerManagement.powerUpCommands = lib.mkAfter ''
    systemctl start vuclient.service
  '';

  environment.systemPackages = with pkgs; [
    # Common packages shared with all machines are in modules/packages/dev.nix and utils.nix
    chromium # web browser
    pkgs-unstable.ghostty # fast GPU-accelerated terminal emulator
    todoist # task manager desktop app
    todoist-electron # todoist wrapped in Electron
    gapless # gapless music player
    lollypop # GNOME music player
    resonance # music player and library manager
    spot # lightweight Spotify client
    tagger # music metadata editor
    jujutsu # version control system (git-compatible)
    delta # syntax-highlighting pager for git
    karere # WhatsApp desktop client (replaces unmaintained whatsapp-for-linux)
    pkgs-unstable.python312Packages.python-kasa # control TP-Link smart home devices
    uefitool # UEFI firmware image viewer and editor
    gamescope # micro-compositor for running games in a window
    yubioath-flutter # YubiKey OTP and oath manager
    coreutils # GNU core utilities (cp, mv, ls, etc.)
    kakoune # modal code editor (vim-inspired)

    resources # system resource monitor (like htop GUI)
    keeweb # cross-platform password manager
    # moreutils, pstree are in modules/packages/utils.nix
    amberol # small and simple music player
    apostrophe # distraction-free Markdown editor
    dig # DNS lookup utility
    nodejs # JavaScript runtime
    gcc # GNU C compiler
    libreoffice # open-source office suite
    mesa-demos # display OpenGL and GLX info (formerly glxinfo)
    newsflash # RSS feed reader
    libresprite # pixel art editor (Aseprite fork)
    pkgs-unstable.mailspring # open-source email client
    element-desktop # Matrix chat client
    age-plugin-yubikey # age encryption with YubiKey support
    passage # age-based password manager
    rage # encryption tool (age in Rust)
    distrobox # use any Linux distribution in a container
    monophony # YouTube music player
    kdePackages.audiotube # YouTube music client (Kirigami)
    zenity # display GTK dialogs from shell scripts
    libnotify # desktop notification library
    linuxKernel.packages.linux_zen.xone # Xbox One controller driver
    localsend # share files to nearby devices
    easyeffects # real-time audio effects processor
    noise-repellent # noise suppression plugin
    cargo # Rust package manager and build tool
    rust-script # run Rust scripts without a project
    xclip # copy data between X clipboard and stdout
    rocmPackages.rocminfo # AMD ROCm GPU info utility
    usb-reset # reset USB devices from the command line
    gimp # image manipulation program
    krita # digital painting and illustration
    glmark2 # OpenGL benchmark
    radeontop # AMD GPU usage monitor
    nix-search-cli # search nix packages from the command line
    cpu-x # CPU and system information tool
    bsd-finger # user information lookup
    foliate # eBook reader (epub, mobi, etc.)
    nms # no more secrets (decrypt text like in Sneakers)
    bc # arbitrary precision calculator
    dconf-editor # low-level GNOME settings editor
    dconf2nix # convert dconf settings to Nix
    obs-studio # live streaming and screen recording
    usbview # USB device tree viewer
    gsound # GObject library for playing event sounds
    libgda6 # database abstraction library
    gnomeExtensions.easyeffects-preset-selector # switch audio presets from panel
    gnomeExtensions.pano # clipboard manager for GNOME
    pkgs-unstable.gnomeExtensions.another-window-session-manager # save/restore window sessions
    gnomeExtensions.dash-to-panel # combine dash and top panel
    libsecret # store and retrieve passwords/secrets
    jless # JSON viewer with folding and jq integration
    spotify # music streaming client
    discord # voice and text chat
    slack # team communication
    signal-desktop # private messaging app
    gnome-tweaks # advanced GNOME settings
    wmctrl # control X window manager from scripts
    obsidian # knowledge base and note-taking app
    dwarf-fortress # colony management simulation game
    zoom-us # video conferencing client
    desktop-file-utils # utilities for .desktop files
    rustc # Rust compiler
    wget # download files from the web
    usbutils # USB device information utilities
    ulauncher # fast application launcher
    tlp # Linux laptop power saving
    (python3.withPackages (pp: with pp; [python-kasa])) # TP-Link smart home control
  ];

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
