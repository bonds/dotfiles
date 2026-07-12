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
      /home/scott/.config/ssh/keys \
      /etc/ssh/authorized_keys.d/scott
  '';

  # Restricted rsync wrapper for photo backup — only allows rsync
  # to /dragon/media/photos/. Used by the photo-rsync key on accismus.
  system.activationScripts.photoRsyncWrapper.text = ''
    mkdir -p /usr/local/bin
    cat > /usr/local/bin/rrsync-photos << 'WRAPPER'
    #!/bin/sh
    case "$SSH_ORIGINAL_COMMAND" in
      *rsync*--server*/dragon/media/photos/*)
        exec $SSH_ORIGINAL_COMMAND
        ;;
      *)
        echo "REJECTED: this key is restricted to rsync /dragon/media/photos/ only" >&2
        exit 1
        ;;
    esac
    WRAPPER
    chmod 755 /usr/local/bin/rrsync-photos
  '';

  # Deploy the photo-rsync public key from accismus (synced via Syncthing
  # Documents folder) with restrictions: LAN-only, rsync-to-photos only.
  # The key is appended to the existing authorized_keys file.
  system.activationScripts.photoRsyncKey.text = ''
    PHOTO_KEY="/home/scott/Documents/.config/photo-rsync-key.pub"
    if [ -f "$PHOTO_KEY" ]; then
      KEY_CONTENT=$(cat "$PHOTO_KEY")
      # Remove any old photo-rsync entry and add fresh one
      grep -v "photo-rsync@accismus" /etc/ssh/authorized_keys.d/scott > /tmp/authorized_keys_clean 2>/dev/null || true
      echo "restrict,from=\"192.168.4.*\",command=\"/usr/local/bin/rrsync-photos\" $KEY_CONTENT" >> /tmp/authorized_keys_clean
      install -m 0444 -o root -g root /tmp/authorized_keys_clean /etc/ssh/authorized_keys.d/scott
      rm -f /tmp/authorized_keys_clean
      echo "photo-rsync: deployed restricted key from accismus" >&2
    else
      echo "photo-rsync: no key found at $PHOTO_KEY — has accismus run nr yet?" >&2
    fi
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

      if [ ! -f /home/scott/Documents/.config/photo-rsync-key.pub ]; then
        warn_missing \
          /home/scott/Documents/.config/photo-rsync-key.pub \
          "Photo rsync SSH public key from accismus — needed for automated nightly photo backup" \
          "Run nr on accismus first (generates the key), then wait for Syncthing to sync Documents/, then rebuild sophrosyne"
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

  # Monitor photo backup freshness — emails if no new photos in 48h
  systemd.services.photo-backup-monitor = let
    monitorScript = pkgs.writeShellScript "photo-backup-monitor" ''
      PHOTO_DIR="/dragon/media/photos"
      THRESHOLD_HOURS=48
      LOG_FILE="/var/log/photo-backup-monitor.log"

      log() {
        echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
      }

      # Find newest file (exclude .stfolder and hidden)
      NEWEST=$(find "$PHOTO_DIR" -type f -not -path '*/\.*' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1)

      if [ -z "$NEWEST" ]; then
        log "ALERT: No photos found in $PHOTO_DIR"
        ${pkgs.msmtp}/bin/msmtp -t <<EOM
      To: root
      Subject: [ALERT] Photo backup — no photos on sophrosyne

      No photos found in $PHOTO_DIR.

      The backup may have never run or photos were deleted.
      Check: ssh accismus "launchctl list | grep photos-backup"
      Logs: cat /tmp/photos-backup.out.log
      EOM
        exit 1
      fi

      NEWEST_TIME=$(echo "$NEWEST" | cut -d' ' -f1)
      NEWEST_FILE=$(echo "$NEWEST" | cut -d' ' -f2-)
      NOW=$(date +%s)
      AGE_HOURS=$(( (NOW - $(printf "%.0f" "$NEWEST_TIME")) / 3600 ))

      if [ "$AGE_HOURS" -gt "$THRESHOLD_HOURS" ]; then
        log "ALERT: newest photo ''${AGE_HOURS}h old (threshold ''${THRESHOLD_HOURS}h) — $NEWEST_FILE"
        ${pkgs.msmtp}/bin/msmtp -t <<EOM
      To: root
      Subject: [ALERT] Photo backup stalled — ''${AGE_HOURS}h since last photo

      The most recent photo on sophrosyne is ''${AGE_HOURS}h old.
      File: $NEWEST_FILE
      Threshold: ''${THRESHOLD_HOURS}h

      Check the backup on accismus:
        ssh accismus "launchctl list | grep photos-backup"
        cat /tmp/photos-backup.out.log
        cat /tmp/photos-backup.err.log

      Or check manually:
        ls -lt /dragon/media/photos/2026/ | head -5
      EOM
        exit 1
      fi

      log "OK: newest photo ''${AGE_HOURS}h old — $NEWEST_FILE"
      exit 0
    '';
  in {
    description = "Check if photo backup is fresh — alert if stalled >48h";
    after = ["network.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = monitorScript;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectHome = true;
      ReadWritePaths = ["/var/log" "/dragon/media/photos"];
      RestrictNamespaces = true;
    };
  };
  systemd.timers.photo-backup-monitor = {
    description = "Daily photo backup freshness check";
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
    wantedBy = ["timers.target"];
  };

  services.syncthing = {
    enable = true;
    openDefaultPorts = true;
    user = "scott";
    group = "users";
    configDir = "/home/scott/.config/syncthing";
    settings = {
      devices = {
        "accismus" = {id = "YH5SQ6S-U6AEOAS-F7JU4F2-YBBZFMH-VT2N6OA-BAVSABW-LBVHDZ7-R3FQLQ5";};
      };
      folders = {
        "Documents" = {
          path = "/home/scott/Documents";
          id = "mz9zh-usrfi";
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
