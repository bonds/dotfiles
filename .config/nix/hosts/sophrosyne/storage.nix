{
  config,
  pkgs,
  lib,
  ...
}: {
  nix.settings.min-free = lib.mkDefault (10 * 1024 * 1024 * 1024);
  nix.settings.max-free = lib.mkDefault (50 * 1024 * 1024 * 1024);

  boot.zfs.forceImportRoot = false;
  networking.hostId = "bf6ff4c5";

  services.zfs.autoScrub = {
    enable = true;
    interval = "*-*-01 03:00:00";
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

  system.activationScripts.backupDataset.text = ''
    if ! ${pkgs.zfs}/bin/zfs list dragon/backups >/dev/null 2>&1; then
      ${pkgs.zfs}/bin/zfs create -o compression=zstd -o atime=off dragon/backups
      echo "backup: created dragon/backups dataset with compression=zstd, atime=off" >&2
    else
      ${pkgs.zfs}/bin/zfs set compression=zstd dragon/backups
      ${pkgs.zfs}/bin/zfs set atime=off dragon/backups
      echo "backup: ensured dragon/backups has compression=zstd, atime=off" >&2
    fi
    mkdir -p /dragon/backups/accismus/live
    mkdir -p /dragon/backups/accismus/snapshots
    chown -R scott:users /dragon/backups/accismus
    chmod 700 /dragon/backups/accismus
    echo "backup: directory structure ready at /dragon/backups/accismus" >&2
  '';

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
        passwordeval = "cat ${config.age.secrets.email-pass.path}";
      };
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
}
