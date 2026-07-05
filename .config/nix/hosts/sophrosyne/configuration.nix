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

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;

  networking.firewall.allowedTCPPorts = [10443 11080];
  networking.firewall.extraCommands = ''
    iptables -I nixos-fw 1 -i enp0s31f6 -p tcp -j ACCEPT
    iptables -I nixos-fw 2 -i enp0s31f6 -p udp -j ACCEPT
  '';

  console.keyMap = "dvorak";

  users.users.scott = {
    isNormalUser = true;
    description = "Scott Bonds";
    extraGroups = ["networkmanager" "wheel"];
    shell = pkgs.fish;
    packages = with pkgs; [];
    # subUidRanges/subGidRanges intentionally omitted — both containers use
    # --userns=keep-id which ignores subuid ranges and maps container uid 0
    # directly to the host user (scott).
  };

  # Ensure ~/.ssh/authorized_keys points to the XDG-compliant key location
  system.activationScripts.sshAuthorizedKeys = {
    text = ''
      mkdir -p /home/scott/.ssh
      ln -sf /home/scott/.config/ssh/keys /home/scott/.ssh/authorized_keys
    '';
    deps = [];
  };

  # NOPASSWD scoped to rebuild commands only (for remote nix deploys).
  # Everything else prompts for scott's password via the wheel default.
  security.sudo.enable = false;
  security.doas.enable = true;
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
  ];

  environment.systemPackages = with pkgs; [
    pkgs-unstable.python313Packages.huggingface-hub # for downloading models
    nvme-cli # manage NVMe devices from the command line
    util-linux # system utilities (lsblk, fdisk, etc.)
    dmidecode # read system DMI/BIOS info
    edac-utils # memory error detection and reporting tools
    lm_sensors # read CPU/motherboard temp, voltage, and fan sensors
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


    '';
  };

  # Enable lingering for scott so rootless podman user services start at boot
  system.activationScripts.enablePodmanLinger = ''
    mkdir -p /var/lib/systemd/linger
    touch /var/lib/systemd/linger/scott
  '';

  system.stateVersion = "24.11";

  boot.zfs.forceImportRoot = false;
  networking.hostId = "bf6ff4c5";
  services.zfs.autoScrub = {
    enable = true;
    interval = "*-*-01 03:00:00";
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

  home-manager = {
    users.scott = {pkgs, ...}: {
      home.stateVersion = "24.11";
      home.homeDirectory = "/home/scott";
      imports = [
        ../../modules/home/tmux.nix
      ];
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

  virtualisation.podman.enable = true;

  systemd.user.services.minecraft = {
    description = "Minecraft Bedrock Server";
    wantedBy = ["default.target"];

    unitConfig = {
      StartLimitBurst = "5";
    };

    serviceConfig = {
      Type = "simple";
      ExecStartPre = "-${pkgs.podman}/bin/podman rm -f minecraft";
      ExecStart = "${pkgs.podman}/bin/podman run --name minecraft -e EULA=TRUE -v /dragon/containers/minecraft:/data -p 19132:19132/udp itzg/minecraft-bedrock-server";
      ExecStop = "${pkgs.podman}/bin/podman stop -t 60 minecraft";
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };

  systemd.user.services.dontstarve = {
    description = "Don't Starve Together Server";
    wantedBy = ["default.target"];

    unitConfig = {
      StartLimitBurst = "5";
    };

    serviceConfig = {
      Type = "simple";
      ExecStartPre = "-${pkgs.podman}/bin/podman rm -f dontstarve";
      ExecStart = "${pkgs.podman}/bin/podman run --user 0:0 --userns=keep-id -e DST_USER=root -e DST_GROUP=root --name dontstarve -v /dragon/containers/dontstarve:/data -p 10999-11000:10999-11000/udp -p 12346-12347:12346-12347/udp jamesits/dst-server:nightly";
      ExecStop = "${pkgs.podman}/bin/podman stop -t 30 dontstarve";
      TimeoutStopSec = "60";
      Restart = "on-failure";
      RestartSec = "10s";
    };
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
        "accismus" = {id = "UIHTW7V-F3HAJC5-AVFUGTM-XX5LUFU-AW5NQQH-NYABTRZ-UPXBHXH-BNCQCQB";};
      };
      folders = {
        "Documents" = {
          path = "/home/scott/Documents";
          id = "mz9zh-usrfi";
          devices = ["accismus"];
        };
        "Photos" = {
          path = "/dragon/photos";
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
      Photos = "/dragon/photos";
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
    models = "/dragon/ollama";
    host = "127.0.0.1";
  };

  # services.matter-server.enable = true;

  # services.immich = {
  #   enable = true;
  #   port = 2283;
  #   mediaLocation = "/dragon/immich";
  # };

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
    };
  };

  system.configurationRevision = self.rev or self.dirtyRev or null;
}
