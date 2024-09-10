{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.vuserver;
in {
  options.services.vuserver = {
    enable = mkEnableOption "VU Server";

    user = mkOption {
      type = types.str;
      default = "vuserver";
      description = "User account under which VU Server runs.";
    };

    group = mkOption {
      type = types.str;
      default = "vuserver";
      description = "Group under which VU Server runs.";
    };

    port = mkOption {
      type = types.port;
      default = 5340;
      description = "Port on which VU Server listens.";
    };

    key = mkOption {
      type = types.str;
      default = "cTpAWYuRpA2zx75Yh961Cg";
      description = "API key for VU Server authentication.";
    };
  };

  config = mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "VU Server user";
    };

    users.groups.${cfg.group} = {};

    systemd.services.vuserver = {
      description = "VU Server. Provides API, admin web page, and pushed updates to USB dials";
      after = [ "dev-ttyUSB0.device" ];
      # wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.vuserver}/bin/vuserver";
        User = cfg.user;
        Group = cfg.group;
        Restart = "on-failure";
        WorkingDirectory = "${pkgs.vuserver}/lib";
        RuntimeDirectory = "vuserver";
        LogsDirectory = "vuserver";
        TimeoutStopSec = "1s";
        # StateDirectory = "vuserver";

        Environment = [
          "STATEDIR=%S/vuserver"
          "LOGSDIR=%L/vuserver"
          "RUNTIMEDIR=%t/vuserver"
          "CONFIG=\"{'hostname': 'localhost', 'port': ${toString cfg.port},'communication_timeout': 10, 'master_key': ${cfg.key}}\""
        ];
      };
    };

    environment.systemPackages = [ pkgs.vuserver ];
  };
}
