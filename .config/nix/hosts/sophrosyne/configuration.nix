{
  config,
  pkgs,
  pkgs-unstable,
  lib,
  inputs,
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

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Mitigation for CVE-2026-31431 (Copy Fail) — local privilege escalation via
  # authencesn not yet backported to 6.12.x. Remove when kernel >= 6.18.22.
  # https://mtlynch.io/claude-code-found-linux-vulnerability/
  boot.blacklistedKernelModules = ["authencesn"];

  networking.hostName = "sophrosyne";

  networking.networkmanager.enable = true;

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

  services.xserver.enable = true;

  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "dvorak";
  };

  console.keyMap = "dvorak";

  services.printing.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  users.users.scott = {
    isNormalUser = true;
    description = "Scott Bonds";
    extraGroups = ["networkmanager" "wheel" "docker"];
    packages = with pkgs; [];
  };

  programs.firefox.enable = true;

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    fastfetch
    ffmpeg
    jq
    ripgrep
    fd
    units
    smartmontools
    nvme-cli
    idris2
    cabal-install
    ghc
    util-linux
    hyperfine
    sysbench
    pv
    lsd
    unzip
    docker-compose
    starship
    git
    btop
    ghostty
    helix
    nh
    fzf
    speedtest-cli
    dmidecode
    edac-utils
  ];

  services.openssh.enable = true;

  system.stateVersion = "24.11";

  boot.supportedFilesystems = ["zfs"];
  boot.zfs.forceImportRoot = false;
  networking.hostId = "bf6ff4c5";
  services.zfs.autoScrub.enable = true;
  systemd.services.zfs-scrub-dragon = {
    wantedBy = ["multi-user.target"];
    after = ["zfs-import-dragon.service" "zfs-mount.service"];
    serviceConfig.Type = "oneshot";
    script = "${pkgs.zfs}/bin/zpool scrub dragon || ${pkgs.zfs}/bin/zpool status dragon | grep -q 'scrub in progress'";
  };
  programs.fish.enable = true;

  programs.bash = {
    interactiveShellInit = ''
      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then
        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      fi
    '';
  };

  services.avahi = {
    enable = true;
    openFirewall = true;
    nssmdns4 = true;
    nssmdns6 = true;
    publish = {
      enable = true;
      addresses = true;
      hinfo = true;
    };
  };

  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        "workgroup" = "WORKGROUP";
        "server string" = "%h server (Samba, NixOS)";
        "server role" = "standalone server";
        "netbios name" = "sophrosyne";
        "map to guest" = "bad user";
        "inherit permissions" = "yes";
        "vfs objects" = "catia fruit streams_xattr";
        "fruit:metadata" = "stream";
        "fruit:model" = "RackMount";
        "fruit:veto_appledouble" = "no";
        "fruit:nfs_aces" = "no";
        "fruit:wipe_intentionally_left_blank_rfork" = "yes";
        "fruit:delete_empty_adfiles" = "yes";
      };
      "media" = {
        "path" = "/dragon/media";
        "guest ok" = "yes";
        "writeable" = "no";
      };
      "timemachine" = {
        "path" = "/dragon/timemachine";
        "guest ok" = "yes";
        "writeable" = "yes";
        "fruit:time machine" = "yes";
      };
      "uploads" = {
        "path" = "/dragon/uploads";
        "guest ok" = "yes";
        "writeable" = "yes";
      };
    };
  };

  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };

  programs.tmux.enable = true;

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.login1.suspend" ||
            action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
            action.id == "org.freedesktop.login1.hibernate" ||
            action.id == "org.freedesktop.login1.hibernate-multiple-sessions")
        {
            return polkit.Result.NO;
        }
    });
  '';

  virtualisation.arion = {
    backend = "docker";
    projects = {
      minecraft.settings.services.minecraft.service = {
        image = "itzg/minecraft-bedrock-server";
        restart = "on-failure:5";
        environment = {
          EULA = "TRUE";
        };
        user = "1000:100";
        volumes = [
          "/dragon/docker/minecraft:/data"
        ];
        ports = [
          "19132:19132/udp"
        ];
      };

      dontstarve.settings.services.dontstarve.service = {
        image = "jamesits/dst-server:latest";
        restart = "on-failure:5";
        stop_grace_period = "6m";
        volumes = [
          "/dragon/docker/dontstarve:/data"
        ];
        ports = [
          "10999-11000:10999-11000/udp"
          "12346-12347:12346-12347/udp"
        ];
      };

      whisper.settings.services.whisper.service = {
        image = "rhasspy/wyoming-whisper";
        restart = "on-failure:5";
        stop_grace_period = "6m";
        volumes = [
          "/dragon/docker/whisper:/data"
        ];
        ports = [
          "10300:10300/tcp"
        ];
        command = "--model tiny-int8 --language en";
      };

      piper.settings.services.piper.service = {
        image = "rhasspy/wyoming-piper";
        restart = "on-failure:5";
        stop_grace_period = "6m";
        volumes = [
          "/dragon/docker/piper:/data"
        ];
        ports = [
          "10200:10200/tcp"
        ];
        command = "--voice en_US-lessac-medium";
      };
    };
  };

  services.home-assistant = {
    enable = true;
    openFirewall = true;
    extraComponents = [
      "analytics"
      "google_translate"
      "met"
      "radio_browser"
      "shopping_list"
      "isal"
      "apple_tv"
      "homekit_controller"
      "thread"
      "tplink_omada"
      "tplink"
      "spotify"
      "brother"
      "ipp"
      "sonos"
      "improv_ble"
      "aranet"
      "piper"
      "whisper"
      "wyoming"
      "ollama"
    ];
    customComponents = [];
    config = {
      default_config = {};
      bluetooth = {};
    };
  };

  systemd.services.ddns = {
    startAt = "*:0/15";
    serviceConfig.Type = "oneshot";
    path = [
      pkgs.curl
    ];
    script = ''
      TOKEN="3sfxws61bbVvhuTZgXBq3Tfu5CZuQiUg"
      ACCOUNT_ID="75214"
      ZONE_ID="ggr.com"
      RECORD_ID="47161920"
      IP=$(curl --ipv4 -s http://icanhazip.com/)

      curl -H "Authorization: Bearer $TOKEN" \
           -H "Content-Type: application/json" \
           -H "Accept: application/json" \
           -X "PATCH" \
           -i "https://api.dnsimple.com/v2/$ACCOUNT_ID/zones/$ZONE_ID/records/$RECORD_ID" \
           -d "{\"content\":\"$IP\"}"
    '';
  };

  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    user = "scott";
    group = "users";
    configDir = "/home/scott/.config/syncthing";
    settings = {
      devices = {
        "laptop" = {id = "UIHTW7V-F3HAJC5-AVFUGTM-XX5LUFU-AW5NQQH-NYABTRZ-UPXBHXH-BNCQCQB";};
        "workstation" = {id = "PO67TVE-4DPKQ3W-A3TNX5K-5OFVKUQ-7GR4VCN-WMVSQ2U-MGOREMU-ZB4U4HAY";};
      };
      folders = {
        "Documents" = {
          path = "/home/scott/Documents";
          id = "mz9zh-usrfi";
          devices = ["laptop" "workstation"];
        };
      };
    };
  };

  programs.msmtp = {
    enable = true;
    setSendmail = true;
    defaults = {
      aliases = "/etc/aliases";
      port = 465;
      tls_trust_file = "/etc/ssl/certs/ca-certificates.crt";
      tls = "on";
      auth = "login";
      tls_starttls = "off";
    };
    accounts = {
      default = {
        host = "smtp.gmail.com";
        user = "woaifafong@gmail.com";
        from = "woaifafong@gmail.com";
        passwordeval = "cat /etc/emailpass.txt";
      };
    };
  };

  services.zfs.zed = {
    enableMail = false;
    settings = {
      ZED_DEBUG_LOG = "/tmp/zed.debug.log";
      ZED_EMAIL_ADDR = ["root"];
      ZED_EMAIL_PROG = "${pkgs.msmtp}/bin/msmtp";
      ZED_EMAIL_OPTS = "@ADDRESS@";

      ZED_NOTIFY_INTERVAL_SECS = 3600;
      ZED_NOTIFY_VERBOSE = true;

      ZED_USE_ENCLOSURE_LEDS = true;
      ZED_SCRUB_AFTER_RESILVER = true;
    };
  };

  environment.etc = {
    "aliases" = {
      text = ''
        root: scott@ggr.com
      '';
      mode = "0644";
    };
  };

  services.ollama = {
    enable = true;
    package = pkgs-unstable.ollama;
    models = "/dragon/ollama";
  };

  services.open-webui = {
    enable = true;
  };

  services.dbus.implementation = "broker";

  services.matter-server.enable = true;

  services.immich = {
    enable = true;
    port = 2283;
    mediaLocation = "/dragon/immich";
  };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    package = pkgs-unstable.tailscale;
  };

  hardware.rasdaemon.enable = true;
}
