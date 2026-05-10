{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.vudials;
in {
  options.services.vudials = {
    enable = mkEnableOption "VU Dials";

    device = mkOption {
      type = types.str;
      default = "/dev/cu.usbserial-DQ0164KM";
      description = "Serial device path for the VU1 hub.";
    };

    port = mkOption {
      type = types.port;
      default = 5340;
      description = "Port on which VU Server listens.";
    };

    runtimedir = mkOption {
      type = types.str;
      default = "/tmp/vuserver/run";
      description = "Runtime directory for www files and PID.";
    };

    statedir = mkOption {
      type = types.str;
      default = "/tmp/vuserver/state";
      description = "State directory for database and key file.";
    };

    logsdir = mkOption {
      type = types.str;
      default = "/tmp/vuserver/logs";
      description = "Log directory.";
    };

    cpudial = mkOption {
      type = types.str;
      default = "";
      description = "UID of the dial that will display CPU load.";
    };

    gpudial = mkOption {
      type = types.str;
      default = "";
      description = "UID of the dial that will display GPU load.";
    };

    memdial = mkOption {
      type = types.str;
      default = "";
      description = "UID of the dial that will display memory load.";
    };

    dskdial = mkOption {
      type = types.str;
      default = "";
      description = "UID of the dial that will display disk usage on root partition.";
    };

    key = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "API key for vuclient to authenticate with vuserver. If null, reads from statedir/key at runtime.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.vuserver];

    system.activationScripts.vudials.text = ''
      _vuhash="${pkgs.vuserver} ${pkgs.vuclient}"
      if [ -f "${cfg.statedir}/.vu-hash" ] && [ "$(cat "${cfg.statedir}/.vu-hash")" != "$_vuhash" ]; then
        launchctl kickstart -k gui/501/org.nixos.vuserver 2>/dev/null || true
        launchctl kickstart -k gui/501/org.nixos.vuclient 2>/dev/null || true
      fi
      mkdir -p ${cfg.statedir}
      echo -n "$_vuhash" > "${cfg.statedir}/.vu-hash"
    '';

    launchd.user.agents = {
      vuserver = {
        command = "${pkgs.vuserver}/bin/vuserver";
        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          StandardOutPath = "${cfg.logsdir}/stdout.log";
          StandardErrorPath = "${cfg.logsdir}/stderr.log";
          EnvironmentVariables = {
            STATEDIR = cfg.statedir;
            LOGSDIR = cfg.logsdir;
            RUNTIMEDIR = cfg.runtimedir;
            PORT = toString cfg.port;
            DEVICE = cfg.device;
          };
        };
      };

      vuclient = {
        command = "${pkgs.vuclient}/bin/vuclient";
        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          StandardOutPath = "/tmp/vuclient.out.log";
          StandardErrorPath = "/tmp/vuclient.err.log";
          EnvironmentVariables =
            {
              CPUDIAL = cfg.cpudial;
              GPUDIAL = cfg.gpudial;
              MEMDIAL = cfg.memdial;
              DSKDIAL = cfg.dskdial;
              VU_KEY_FILE = "${cfg.statedir}/key";
            }
            // lib.optionalAttrs (cfg.key != null) {
              VU_API_KEY = cfg.key;
            };
        };
      };
    };
  };
}
