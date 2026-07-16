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
