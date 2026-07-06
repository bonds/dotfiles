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
  boot.loader.systemd-boot.configurationLimit = 10;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "sophrosyne";

  networking.networkmanager.enable = true;

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;

  networking.firewall.enable = true;
  networking.nftables.enable = true;

  console.keyMap = "dvorak";

  users.users.scott = {
    isNormalUser = true;
    description = "Scott Bonds";
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.fish;
    packages = with pkgs; [];
  };

  # NOPASSWD scoped to rebuild commands only (for remote nix deploys).
  # Everything else prompts for scott's password via the wheel default.
  security.doas.extraRules = [
    {
      users = ["scott"];
      persist = true;
    }
    {
      users = ["scott"];
      cmd = "/run/current-system/sw/bin/nixos-rebuild";
      noPass = true;
    }
    {
      users = ["scott"];
      cmd = "/run/current-system/sw/bin/nh";
      noPass = true;
    }
    {
      users = ["scott"];
      cmd = "/run/current-system/sw/bin/systemctl";
      noPass = true;
    }
    {
      users = ["scott"];
      cmd = "/run/current-system/sw/bin/journalctl";
      noPass = true;
    }
  ];

  # TouchID-for-doas: authenticate privileged ops via the forwarded
  # Secretive SSH agent (TouchID on accismus). Root-owned keys file per
  # nixpkgs#31611 — do NOT use ~/.ssh/authorized_keys (user-writeable =
  # privilege escalation).
  security.pam.sshAgentAuth.enable = true;
  # doas PAM_USER is the INVOKING user (scott), not the target (root).
  # Hardcode path explicitly to avoid any %u expansion issues.
  security.pam.sshAgentAuth.authorizedKeysFiles = [
    "/etc/ssh/authorized_keys.d/scott"
  ];
  # /nix/store has group-write permissions (nixbld group), which
  # pam_ssh_agent_auth rejects when traversing the symlink chain.
  # So copy the key file to a path outside the store.
  system.activationScripts.doasPamAuthKeys.text = ''
    install -D -m 0444 -o root -g root \
      ${self}/.config/ssh/keys \
      /etc/ssh/authorized_keys.d/scott
  '';

  environment.systemPackages = with pkgs; [
    pkgs-unstable.python313Packages.huggingface-hub # for downloading models
    nvme-cli # manage NVMe devices from the command line
    util-linux # system utilities (lsblk, fdisk, etc.)
    dmidecode # read system DMI/BIOS info
    edac-utils # memory error detection and reporting tools
    lm_sensors # read CPU/motherboard temp, voltage, and fan sensors
    # most common packages are in modules/packages/dev.nix and utils.nix
  ];

  services.openssh.settings.KbdInteractiveAuthentication = false;

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

      if [ ! -f /var/lib/dst-server/cluster_token.txt ]; then
        warn_missing \
          /var/lib/dst-server/cluster_token.txt \
          "Klei cluster token for Don't Starve Together server" \
          "Copy from /dragon/containers/dontstarve/DoNotStarveTogether/Cluster_1/cluster_token.txt"
      fi


    '';
  };

  system.stateVersion = "24.11";

  boot.zfs.forceImportRoot = false;
  networking.hostId = "bf6ff4c5";
  services.zfs.autoScrub = {
    enable = true;
    interval = "*-*-01 03:00:00";
  };

  services.avahi.enable = false;

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

  home-manager = {
    users.scott = {pkgs, ...}: {
      home.stateVersion = "24.11";
      home.homeDirectory = "/home/scott";
      imports = [
        ../../modules/home/tmux.nix
        ../../modules/home/what-changed.nix
      ];
      programs.what-changed.enable = true;
    };
  };

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

  services.minecraft-bedrock = {
    enable = true;
    eula = true;
    dataDir = "/dragon/servers/minecraft";
    openFirewall = true;
  };

  # DST cluster token:
  #   doas cp /dragon/containers/dontstarve/DoNotStarveTogether/Cluster_1/cluster_token.txt /var/lib/dst-server/cluster_token.txt
  #   doas chmod 600 /var/lib/dst-server/cluster_token.txt
  services.dst-server = {
    enable = true;
    clusterTokenFile = "/var/lib/dst-server/cluster_token.txt";
    openFirewall = true;
  };

  programs.nix-ld.enable = true;

  # REMINDER: When adding a secret here, also add a warn_missing check
  # in system.activationScripts.checkSecrets above.
  systemd.services.ddns = {
    startAt = "*:0/15";
    serviceConfig = {
      Type = "oneshot";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectHome = true;
      RestrictNamespaces = true;
    };
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
        "accismus" = {id = "UIHTW7V-F3HAJC5-AVFUGTM-XX5LUFU-AW5NQQH-NYABTRZ-UPXBHXH-BNCQCQB";};
      };
      folders = {
        "Documents" = {
          path = "/home/scott/Documents";
          id = "mz9zh-usrfi";
          devices = ["accismus"];
        };
        "Photos" = {
          path = "/dragon/media/photos";
          id = "photos";
          type = "receiveonly";
          devices = ["accismus"];
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

  programs.firesafe-backup = {
    enable = true;
    sources = {
      Archive = "/dragon/archive";
      Backups = "/dragon/backups";
      Documents = "/dragon/documents";
      "Media/audiobooks" = "/dragon/media/audiobooks";
      "Media/books" = "/dragon/media/books";
      "Media/iphone" = "/dragon/media/iphone";
      "Media/manuals" = "/dragon/media/manuals";
      "Media/music" = "/dragon/media/music";
      "Media/software" = "/dragon/media/software";
      Photos = "/dragon/media/photos";
      "Servers/Dontstarve" = "/dragon/servers/dontstarve/data";
      "Servers/Minecraft" = "/dragon/servers/minecraft";
    };
    emailRecipient = "root";
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

  services.tailscale = {
    enable = true;
    package = pkgs-unstable.tailscale;
    extraSetFlags = ["--advertise-routes=192.168.4.0/24" "--advertise-exit-node"];
  };

  services.ollama = {
    enable = true;
    package = pkgs-unstable.ollama;
    models = "/dragon/servers/ollama";
    host = "127.0.0.1";
  };

  hardware.bluetooth.enable = true;

  hardware.rasdaemon.enable = true;

  # Log NVMe/CPU temps and fan speeds every minute for thermal diagnostics
  systemd.services.log-temps = let
    logScript = pkgs.writeShellScript "log-temps" ''
      log=/dragon/logs/temps.log
      ts=$(date +%s)
      printf "%s " "$ts" >> "$log"
      for d in /dev/nvme*n1; do
        t=$(${pkgs.nvme-cli}/bin/nvme smart-log "$d" 2>/dev/null | sed -n 's/^temperature.*: *\([0-9]*\).*/\1/p')
        printf "nvme-%s=%s " "$(basename $d)" "$t" >> "$log"
      done
      cpu=$(cat /sys/devices/platform/coretemp.0/hwmon/hwmon9/temp1_input 2>/dev/null)
      printf "cpu=%s " "$((cpu / 1000))" >> "$log"
      f1=$(cat /sys/devices/platform/dell_smm_hwmon/hwmon/hwmon10/fan1_input 2>/dev/null)
      f2=$(cat /sys/devices/platform/dell_smm_hwmon/hwmon/hwmon10/fan2_input 2>/dev/null)
      printf "fan-cpu=%s fan-sys=%s" "$f1" "$f2" >> "$log"
      echo >> "$log"
    '';
  in {
    description = "Log temperatures to /dragon/logs/temps.log";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = logScript;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectHome = true;
      ReadWritePaths = ["/dragon/logs"];
      ReadOnlyPaths = ["/sys" "/dev"];
    };
  };
  systemd.timers.log-temps = {
    description = "Log temperatures every minute";
    timerConfig = {
      OnCalendar = "minutely";
      Persistent = true;
    };
    wantedBy = ["timers.target"];
  };

  # Pin fans at max on boot to keep NVMe temps down (prevents PCIe AER errors)
  systemd.services.set-max-fans = let
    fanScript = pkgs.writeShellScript "set-max-fans" ''
      for _ in 1 2 3 4 5; do
        for pwm in /sys/devices/platform/dell_smm_hwmon/hwmon/hwmon*/pwm[12]; do
          if [ -f "$pwm" ]; then
            echo 255 > "$pwm"
          fi
        done
        # check if it worked
        if [ "$(cat /sys/devices/platform/dell_smm_hwmon/hwmon/hwmon*/fan1_input 2>/dev/null)" -gt 4000 ]; then
          exit 0
        fi
        sleep 2
      done
    '';
  in {
    description = "Pin fans to maximum speed";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = fanScript;
      RemainAfterExit = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectHome = true;
      ReadWritePaths = ["/sys/devices/platform/dell_smm_hwmon"];
    };
  };
}
