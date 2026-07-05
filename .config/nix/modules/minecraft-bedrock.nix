{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.minecraft-bedrock;
  startScript = pkgs.writeShellScript "bedrock-server-start" ''
    fifo=/run/minecraft-bedrock/stdin
    dir=$(dirname "$fifo")
    mkdir -p "$dir"
    rm -f "$fifo"
    mkfifo -m 0666 "$fifo"
    # Open read-write so the open doesn't block (no writer yet).
    # This single fd counts as both reader and writer, preventing EOF.
    exec <>"$fifo"
    cd "${cfg.dataDir}"
    exec "${cfg.package}/lib/minecraft/bedrock_server"
  '';
  stopScript = pkgs.writeShellScript "bedrock-server-stop" ''
    echo stop > /run/minecraft-bedrock/stdin 2>/dev/null || true
  '';
in {
  options.services.minecraft-bedrock = {
    enable = mkEnableOption "Minecraft Bedrock Dedicated Server";

    eula = mkOption {
      type = types.bool;
      default = false;
      description = "Whether you agree to Mojang's EULA. Must be true to run the server.";
    };

    dataDir = mkOption {
      type = types.path;
      default = "/dragon/minecraft";
      description = "Directory to store server data (worlds, config, logs).";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ../pkgs/bedrock-server {};
      defaultText = literalExpression "pkgs.callPackage ../pkgs/bedrock-server {}";
      description = "The bedrock-server package to use.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open UDP port 19132 in the firewall.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.eula;
        message = ''
          You must agree to Mojang's EULA to run the Minecraft Bedrock server.
          Set `services.minecraft-bedrock.eula = true;` if you agree.
          See https://minecraft.net/terms
        '';
      }
    ];

    users.users.minecraft = {
      description = "Minecraft server service user";
      isSystemUser = true;
      group = "minecraft";
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.minecraft = {};

    systemd.services.minecraft-bedrock = {
      description = "Minecraft Bedrock Dedicated Server";
      after = ["network-online.target"];
      wants = ["network-online.target"];

      serviceConfig = {
        User = "minecraft";
        Group = "minecraft";
        Type = "simple";
        WorkingDirectory = cfg.dataDir;
        StandardOutput = "journal";
        StandardError = "journal";
        Environment = "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt";
        RuntimeDirectory = "minecraft-bedrock";
        ExecStart = startScript;
        ExecStartPre = [
          "${pkgs.coreutils}/bin/mkdir -p '${cfg.dataDir}'"
          "${pkgs.rsync}/bin/rsync -a --ignore-existing '${cfg.package}/share/minecraft/' '${cfg.dataDir}/'"
        ];
        ExecStop = stopScript;
        Restart = "on-failure";
        RestartSec = 10;
        TimeoutStopSec = 90;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          cfg.dataDir
          "/run/minecraft-bedrock"
        ];
        PrivateTmp = true;
        AmbientCapabilities = "";
        CapabilityBoundingSet = "";
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedUDPPorts = [19132];
    };
  };
}
