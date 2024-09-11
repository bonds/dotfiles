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

    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6015", ATTRS{serial}=="DQ0164KM", SYMLINK+="vuserver-$attr{serial}", TAG+="systemd", ENV{SYSTEMD_WANTS}="vuserver@$attr{serial}.service", MODE="0666"
      ACTION=="remove", SUBSYSTEM=="tty", ENV{ID_VENDOR_ID}=="0403", ENV{ID_MODEL_ID}=="6015", ENV{ID_SERIAL_SHORT}=="DQ0164KM", RUN+="${pkgs.systemd}/bin/systemctl stop vuserver@$env{ID_SERIAL_SHORT}.service"
    '';

    systemd.services."vuserver@" = {
      description = "VU Server for %I. Provides API, admin web page, and pushed updates to USB dials";
      partOf = [ "vuserver.target" ];

      serviceConfig = {
        # ExecStart = "${pkgs.vuserver}/bin/vuserver /dev/vuserver-%I";
        ExecStart = "${pkgs.vuserver}/bin/vuserver";
        User = cfg.user;
        Group = cfg.group;
        Restart = "on-failure";
        WorkingDirectory = "${pkgs.vuserver}/lib";
        RuntimeDirectory = "vuserver";
        LogsDirectory = "vuserver";
        StateDirectory = "vuserver";
        TimeoutStopSec = "1s";
        # partOf = [ "sleep.target" "suspend.target" ];
        # before = [ "sleep.target" "suspend.target" ];
        # after = [ "post-resume.target" ];

        Environment = [
          "STATEDIR=%S/vuserver"
          "LOGSDIR=%L/vuserver"
          "RUNTIMEDIR=%t/vuserver"
          "DEVICE=/dev/vuserver-%I"
          "CONFIG=\"{'hostname': 'localhost', 'port': ${toString cfg.port},'communication_timeout': 10, 'master_key': ${cfg.key}}\""
        ];
      };
    };

    systemd.targets.vuserver = {};

    systemd.services.vuclient = {
      enable = true;
      description = "Monitor computer and push info to VU server.";
      wantedBy = [ "multi-user.target" ];
      wants = [ "vuserver.target" ];
      after = [ "vuserver.target" ];
      # partOf = [ "sleep.target" "suspend.target" ];
      # before = [ "sleep.target" ];
      # before = [ "sleep.target" "suspend.target" "vuserver.target" ];
      # after = [ "post-resume.target" "vuserver.target" ];
      # preStart = "sleep 10"; # give the server time to finish starting
      script = "/home/scott/bin/linux/vu1";
      serviceConfig = {
        TimeoutStopSec = "5s";
        Restart = "on-failure";
      };
    }; 

    # powerManagement.powerDownCommands = ''
    #   systemctl stop vuclient.service vuserver.service
    # '';

    # powerManagement.powerUpCommands = ''
    #   systemctl start vuserver.service vuclient.service
    # '';

    powerManagement.powerDownCommands = ''
      systemctl stop vuclient.service
    '';

    powerManagement.powerUpCommands = ''
      systemctl start vuclient.service
    '';

    environment.systemPackages = [ pkgs.vuserver ];
  };
}
