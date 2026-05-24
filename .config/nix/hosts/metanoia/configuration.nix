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
  ];

  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    channel.enable = false;
    registry = lib.mapAttrs (_: flake: lib.mkDefault {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };

  networking.hostName = "metanoia";

  users.users.scott = {
    description = "Scott Bonds";
    isNormalUser = true;
    extraGroups = ["networkmanager" "wheel"];
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.extraModulePackages = with config.boot.kernelPackages; [
    v4l2loopback
  ];

  networking.networkmanager.enable = true;
  networking.nftables.enable = true;

  time.timeZone = "America/Los_Angeles";

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

  fonts.packages = with pkgs; [
    helvetica-neue-lt-std
  ];

  boot.kernelParams = ["fbcon=rotate:3"];

  home-manager = {
    extraSpecialArgs = {
      inherit inputs;
    };
    useUserPackages = true;
    backupFileExtension = "backup";
    users.scott = {pkgs, ...}: {
      home = {
        username = "scott";
        homeDirectory = "/home/scott";
        stateVersion = "24.05";
        packages = with pkgs; [
          gnome-themes-extra
        ];
        file = {
          ".config/wireplumber/wireplumber.conf.d/51-disable-devices.conf".text = ''
            monitor.alsa.rules = [
              {
                matches = [
                  {
                    device.name = "~alsa_card.pci-*"
                  }
                  {
                    device.name = "~alsa_card.usb-Elgato_*"
                  }
                ]
                actions = {
                  update-props = {
                  	device.disabled = true
                  }
                }
              }
            ]
          '';

          ".mozilla/managed-storage/uBlock0@raymondhill.net.json".text = builtins.toJSON {
            name = "uBlock0@raymondhill.net";
            description = "_";
            type = "storage";
            data = {
              adminSettings = {
                userFilters = ''
                  cnn.com##.header__wrapper-outer:style(height: 30px !important)
                '';
              };
            };
          };
        };
      };

      programs.home-manager.enable = true;
      programs.fish.plugins = with pkgs.fishPlugins; [fzf-fish];
      systemd.user.startServices = "sd-switch";

      xdg.desktopEntries = {
        dwarf = {
          name = "Dwarf Fortress";
          comment = "a really great game";
          exec = "dwarf-fortress";
          settings = {
            Path = "/run/current-system/sw/bin";
          };
        };
      };

      dconf.settings = let
        inherit (lib.gvariant) mkTuple mkUint32 mkVariant;
      in {
        "org/gnome/settings-daemon/plugins/power" = {
          sleep-inactive-ac-timeout = 900;
        };
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
          gtk-theme = "Adwaita-dark";
        };
        "org/gnome/settings-daemon/plugins/color" = {
          night-light-enabled = true;
        };
        "org/gnome/shell" = {
          enabled-extensions = [
            "dash-to-panel@jderose9.github.com"
            "another-window-session-manager@gmail.com"
            "pano@elhan.io"
            "blur-my-shell@aunetx"
            "espresso@coadmunkee.github.com"
            "window-calls@domandoman.xyz"
          ];
        };
        "org/gnome/shell/extensions/dash-to-panel" = {
          dot-position = "BOTTOM";
          show-favorites = false;
          hide-overview-on-startup = false;
          isolate-monitors = true;
          panel-positions = ''
            {"0":"TOP","1":"TOP","2":"TOP"}
          '';
          panel-sizes = ''
            {"0":36,"1":36,"2":36}
          '';
          status-icon-padding = 4;
          panel-element-positions = ''
            {"0":[{"element":"showAppsButton","visible":true,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":false,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}],"1":[{"element":"showAppsButton","visible":true,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":false,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}],"2":[{"element":"showAppsButton","visible":true,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":false,"position":"stackedBR"},{"element":"systemMenu","visible":false,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}]}
          '';
        };
        "org/gnome/desktop/input-sources" = {
          xkb-options = [
            "terminate:ctrl_alt_bksp"
            "ctrl:swap_lwin_lctl"
            "ctrl:swap_rwin_rctl"
          ];
        };
        "org/gnome/desktop/wm/preferences" = {
          num-workspaces = 1;
        };
        "org/gnome/shell/weather" = {
          automatic-location = true;
          locations = [
            (mkVariant (mkTuple [
              (mkUint32 2)
              (mkVariant (mkTuple [
                "Palo Alto"
                "KPAO"
                true
                [(mkTuple [0.6539166988983063 (-2.1313379107115065)])]
                [(mkTuple [0.653484136496492 (-2.1317978398759916)])]
              ]))
            ]))
          ];
        };
        "org/gnome/shell/world-clocks" = {
          locations = [
            (mkVariant (mkTuple [
              (mkUint32 2)
              (mkVariant (mkTuple [
                "Tel Aviv"
                "LLBG"
                true
                [(mkTuple [0.5585053606381855 0.609119908946021])]
                [(mkTuple [0.5596689192906126 0.6067928090944594])]
              ]))
            ]))
          ];
        };
        "org/gnome/desktop/background" = {
          picture-uri = "file:///home/scott/.config/background";
          picture-option = "spanned";
          picture-uri-dark = "file:///home/scott/.config/background";
        };
        "org/gnome/settings-daemon/plugins/media-keys" = {
          custom-keybindings = [
            "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
            "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
          ];
        };
        "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
          name = "Ulauncher";
          binding = "<Control>space";
          command = "/run/current-system/sw/bin/ulauncher-toggle";
        };
        "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2" = {
          name = "maximize window across all monitors";
          binding = "<Control><Shift>m";
          command = "/home/scott/bin/linux/maximize_across_multiple_monitors";
        };
        "org/gnome/Console" = {
          font-scale = 1.3;
          use-system-font = false;
          custom-font = "Liga SFMono Nerd Font 10";
        };
        "org/gnome/shell/keybindings" = {
          show-screen-recording-ui = [
            "<Shift><Control>p"
          ];
        };
        "org/gnome/shell/extensions/another-window-session-manager" = {
          enable-autorestore-sessions = true;
          restore-at-startup-without-asking = true;
          autorestore-sessions = "defaultSession";
        };
      };
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

  system.switch = {
    enable = false;
    enableNg = true;
  };

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

  programs.mtr.enable = true;
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

  programs.command-not-found.enable = false;

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
  services.dbus.implementation = "broker";
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
    chromium
    pkgs-unstable.ghostty
    todoist
    todoist-electron
    gapless
    lollypop
    resonance
    spot
    tagger
    jujutsu
    delta
    whatsapp-for-linux
    pkgs-unstable.python312Packages.python-kasa
    uefitool
    gamescope
    yubioath-flutter
    coreutils
    kakoune
    zulip
    ventoy-full
    resources
    keeweb
    speedtest-cli
    moreutils
    amberol
    apostrophe
    dig
    nodejs
    gcc
    libreoffice
    glxinfo
    newsflash
    libresprite
    pkgs-unstable.mailspring
    element-desktop
    age-plugin-yubikey
    passage
    rage
    distrobox
    monophony
    kdePackages.audiotube
    zenity
    libnotify
    linuxKernel.packages.linux_zen.xone
    localsend
    easyeffects
    noise-repellent
    cargo
    rust-script
    xclip
    rocmPackages.rocminfo
    usb-reset
    rlwrap
    idris2
    gimp
    krita
    glmark2
    radeontop
    nix-search-cli
    cpu-x
    bsd-finger
    weather
    foliate
    fzf
    pstree
    idris2
    cabal-install
    ghc
    ffmpeg
    nms
    bc
    atuin
    socat
    dconf-editor
    dconf2nix
    obs-studio
    usbview
    fastfetch
    gsound
    libgda6
    gnomeExtensions.easyeffects-preset-selector
    gnomeExtensions.pano
    pkgs-unstable.gnomeExtensions.another-window-session-manager
    gnomeExtensions.dash-to-panel
    jq
    libsecret
    jless
    unzip
    helix
    spotify
    discord
    slack
    signal-desktop
    pkgs-unstable.ollama
    gnome-tweaks
    wmctrl
    obsidian
    dwarf-fortress
    git
    starship
    lsd
    ripgrep
    fd
    nerdfonts
    hyperfine
    sysbench
    zoom-us
    desktop-file-utils
    btop
    rustc
    wget
    usbutils
    ulauncher
    tlp
    (python3.withPackages (pp: with pp; [python-kasa]))
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

  programs.firefox = {
    enable = true;
    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
      };
      DisablePocket = true;
      DisableFirefoxAccounts = false;
      DisableAccounts = false;
      DisableFirefoxScreenshots = true;
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      DontCheckDefaultBrowser = true;
      DisplayBookmarksToolbar = "never";
      DisplayMenuBar = "default-off";
      SearchBar = "unified";
      Preferences = {
        "browser.emi.ui.enable" = {
          Value = false;
          Status = "locked";
        };
        "media.eme.enabled" = {
          Value = false;
          Status = "locked";
        };
      };
      ExtensionSettings = {
        "uBlock0@raymondhill.net" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi";
          installation_mode = "force_installed";
        };
        "jid1-MnnxcxisBPnSXQ@jetpack" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/privacy-badger17/latest.xpi";
          installation_mode = "force_installed";
        };
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden_password_manager/latest.xpi";
          installation_mode = "force_installed";
        };
        "addon@darkreader.org" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/darkreader/latest.xpi";
          installation_mode = "force_installed";
        };
        "search@kagi.com" = {
          install_url = "https://addons.mozilla.org/en-US/firefox/addon/kagi-search-for-firefox/latest.xpi";
          installation_mode = "force_installed";
        };
      };
    };
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
