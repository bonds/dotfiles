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

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

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

  console.keyMap = "dvorak";

  users.users.scott = {
    isNormalUser = true;
    description = "Scott Bonds";
    extraGroups = ["networkmanager" "wheel" "docker"];
    packages = with pkgs; [];
  };

  environment.systemPackages = with pkgs; [
    nvme-cli
    util-linux
    docker-compose
    dmidecode
    edac-utils
    # most common packages are in modules/packages/common.nix
  ];

  services.openssh.enable = true;

  system.activationScripts.checkSecrets = {
    text = ''
      warn_missing() {
        echo "WARNING: $1 is missing!" >&2
        echo "  Purpose: $2" >&2
        echo "  Source: $3" >&2
      }

      if [ ! -f /etc/ddns-token ]; then
        warn_missing \
          /etc/ddns-token \
          "DNSimple API token for DDNS (updates home.ggr.com A record)" \
          "Bitwarden vault entry: \"home.ggr.com dns token\""
      fi

      if [ ! -f /etc/email-pass ]; then
        warn_missing \
          /etc/email-pass \
          "Gmail app password for msmtp (system emails, ZED alerts)" \
          "Bitwarden vault entry: \"server email account\""
      fi
    '';
  };

  system.stateVersion = "24.11";

  boot.zfs.forceImportRoot = false;
  networking.hostId = "bf6ff4c5";
  services.zfs.autoScrub.enable = true;
  systemd.services.zfs-scrub-dragon = {
    wantedBy = ["multi-user.target"];
    after = ["zfs-import-dragon.service" "zfs-mount.service"];
    serviceConfig.Type = "oneshot";
    script = "${pkgs.zfs}/bin/zpool scrub dragon || ${pkgs.zfs}/bin/zpool status dragon | grep -q 'scrub in progress'";
  };
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

      scrypted.settings.services = {
        eufy-ws.service = {
          image = "bropat/eufy-security-ws:latest";
          restart = "unless-stopped";
          network_mode = "host";
          environment = {
            USERNAME = "scott+homebridge@ggr.com";
            COUNTRY = "US";
            TRUSTED_DEVICE_NAME = "sophrosyne";
            PORT = "3000";
          };
          env_file = [
            "/dragon/docker/eufy-security-ws/.env"
          ];
          volumes = [
            "/dragon/docker/eufy-security-ws/data:/data"
          ];
        };
        scrypted.service = {
          image = "ghcr.io/koush/scrypted";
          restart = "unless-stopped";
          network_mode = "host";
          volumes = [
            "/dragon/docker/scrypted/volume:/server/volume"
            "/var/run/dbus:/var/run/dbus"
            "/var/run/avahi-daemon/socket:/var/run/avahi-daemon/socket"
          ];
          dns = ["1.1.1.1" "8.8.8.8"];
        };
        watchtower.service = {
          image = "nickfedor/watchtower";
          container_name = "scrypted-watchtower";
          restart = "unless-stopped";
          volumes = [
            "/var/run/docker.sock:/var/run/docker.sock"
          ];
          ports = [
            "10444:8080"
          ];
          command = "--interval 3600 --cleanup --scope scrypted";
          dns = ["1.1.1.1" "8.8.8.8"];
        };
      };
    };
  };

  services.home-assistant.enable = false;

  systemd.services.ddns = {
    startAt = "*:0/15";
    serviceConfig.Type = "oneshot";
    path = [
      pkgs.curl
    ];
    script = ''
      TOKEN=$(cat /etc/ddns-token)
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
        passwordeval = "cat /etc/email-pass";
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

  services.dbus.implementation = null;

  # services.matter-server.enable = true;

  # services.immich = {
  #   enable = true;
  #   port = 2283;
  #   mediaLocation = "/dragon/immich";
  # };

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "both";
    package = pkgs-unstable.tailscale;
  };

  services.homebridge = {
    enable = true;
    openFirewall = true;
    settings = {
      bridge.bind = ["enp0s31f6"];
      platforms = [
        {
          platform = "EufySecurity";
          name = "EufySecurity";
          username = "scott+homebridge@ggr.com";
          country = "US";
          deviceName = "Cedar Port 95";
          ignoreDevices = ["T8400P3121431D4D"];
          cameras = [
            {
              serialNumber = "T8131N632232044C";
              talkback = false;
              videoConfig = {
                maxBitrate = 6000;
                vcodec = "copy";
              };
            }
          ];
        }
      ];
    };
  };

  systemd.services.homebridge.path = [pkgs.python3];

  # Homebridge needs Node.js >=24.5.0 for Eufy PKCS1 padding support
  nixpkgs.overlays = [
    (final: prev: {
      nodejs = final.nodejs_24;
    })
  ];

  hardware.bluetooth.enable = true;

  hardware.rasdaemon.enable = true;

  system.configurationRevision = self.rev or self.dirtyRev or null;
}
