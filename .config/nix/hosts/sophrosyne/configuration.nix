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

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "sophrosyne";

  networking.networkmanager.enable = true;

  networking.firewall.allowedTCPPorts = [10443 11080];
  networking.firewall.extraCommands = ''
    iptables -I nixos-fw 1 -i enp0s31f6 -p tcp -j ACCEPT
    iptables -I nixos-fw 2 -i enp0s31f6 -p udp -j ACCEPT
  '';

  console.keyMap = "dvorak";

  users.users.scott = {
    isNormalUser = true;
    description = "Scott Bonds";
    extraGroups = ["networkmanager" "wheel" "docker"];
    shell = pkgs.fish;
    packages = with pkgs; [];
  };

  # Ensure ~/.ssh/authorized_keys points to the XDG-compliant key location
  system.activationScripts.sshAuthorizedKeys = {
    text = ''
      mkdir -p /home/scott/.ssh
      ln -sf /home/scott/.config/ssh/keys /home/scott/.ssh/authorized_keys
    '';
    deps = [];
  };

  security.sudo.extraRules = [
    {
      users = ["scott"];
      commands = [
        {
          command = "ALL";
          options = ["NOPASSWD"];
        }
      ];
    }
  ];

  environment.systemPackages = with pkgs; [
    nvme-cli # manage NVMe devices from the command line
    util-linux # system utilities (lsblk, fdisk, etc.)
    docker-compose # define and run multi-container Docker apps
    dmidecode # read system DMI/BIOS info
    edac-utils # memory error detection and reporting tools
    # most common packages are in modules/packages/dev.nix and utils.nix
  ];

  services.openssh.enable = true;

  # REMINDER: When adding a new local-only secret file consumed by this
  # configuration, add a corresponding warn_missing check here.
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

      if [ ! -f /dragon/docker/eufy-security-ws/.env ]; then
        warn_missing \
          /dragon/docker/eufy-security-ws/.env \
          "Eufy password for scrypted homebridge plugin (eufy-security-ws)" \
          "Bitwarden vault entry: \"eufy homebridge\""
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
    enable = false;
    openFirewall = false;
    nssmdns4 = false;
    nssmdns6 = false;
    publish = {
      enable = false;
      addresses = false;
      hinfo = false;
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
        # REMINDER: When adding a secret here, also add a warn_missing check
        # in system.activationScripts.checkSecrets above.
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
          privileged = true;
          environment = {
            SCRYPTED_DOCKER_AVAHI = "true";
          };
          volumes = [
            "/dragon/docker/scrypted/volume:/server/volume"
            "/dragon/docker/scrypted/avahi:/etc/avahi"
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

  # Patch scrypted homekit plugin to handle cameras without direct tcp:// URLs
  # (e.g., Eufy battery cameras). Fixes: TypeError: Cannot read properties of undefined (reading 'startsWith')
  systemd.services.scrypted-homekit-patch = {
    description = "Patch Scrypted HomeKit plugin for Eufy battery cameras";
    after = ["arion-scrypted.service"];
    wants = ["arion-scrypted.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      PLUGIN_JS="/dragon/docker/scrypted/volume/plugins/@scrypted/homekit/zip/unzipped/main.nodejs.js"
      if [ -f "$PLUGIN_JS" ]; then
        if grep -q '!p.url.startsWith("tcp://")' "$PLUGIN_JS"; then
          echo "Patching HomeKit plugin for battery camera compatibility..."
          ${pkgs.gnused}/bin/sed -i 's/!p.url.startsWith("tcp:\/\/")/!p.url?.startsWith("tcp:\/\/")/g' "$PLUGIN_JS"
          ${pkgs.docker}/bin/docker restart scrypted-scrypted-1 || true
        else
          echo "HomeKit plugin already patched or not patchable."
        fi
      else
        echo "HomeKit plugin not found yet, will patch on next run."
      fi
    '';
  };

  # REMINDER: When adding a secret here, also add a warn_missing check
  # in system.activationScripts.checkSecrets above.
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
    # REMINDER: When adding a secret here, also add a warn_missing check
    # in system.activationScripts.checkSecrets above.
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

  hardware.bluetooth.enable = true;

  hardware.rasdaemon.enable = true;

  system.configurationRevision = self.rev or self.dirtyRev or null;
}
