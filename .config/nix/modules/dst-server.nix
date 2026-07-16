{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption mkIf mkEnableOption types optional optionals optionalString concatMapStringsSep length;
  cfg = config.services.dst-server;

  configDir = ../modules/dst-server-config;
  clusterIniTemplate = import "${configDir}/cluster.ini.nix";
  masterIniTemplate = import "${configDir}/server-master.ini.nix";
  cavesIniTemplate = import "${configDir}/server-caves.ini.nix";

  clusterIniContent = clusterIniTemplate cfg;
  masterIniContent = masterIniTemplate cfg;
  cavesIniContent = cavesIniTemplate cfg;

  serverBin =
    if cfg.architecture == "x64"
    then "${cfg.serverInstallDir}/bin64/dontstarve_dedicated_server_nullrenderer_x64"
    else "${cfg.serverInstallDir}/bin/dontstarve_dedicated_server_nullrenderer";

  libcurlGnutls = pkgs.stdenv.mkDerivation {
    pname = "libcurl-gnutls";
    version = "7.64.0";
    src = pkgs.fetchurl {
      url = "http://snapshot.debian.org/archive/debian/20190323T031635Z/pool/main/c/curl/libcurl3-gnutls_7.64.0-2_amd64.deb";
      sha256 = "sha256-UGA5xyYBonSgxRCRQ5hGvgq4LyXaA3DJCF2riLcvu/U=";
    };
    nativeBuildInputs = [pkgs.dpkg];
    unpackPhase = "dpkg-deb -x $src .";
    installPhase = ''
      mkdir -p $out/lib
      cp -P usr/lib/x86_64-linux-gnu/libcurl-gnutls.so* $out/lib/
    '';
  };

  libnettle6 = pkgs.stdenv.mkDerivation {
    pname = "libnettle6";
    version = "3.4.1";
    src = pkgs.fetchurl {
      url = "http://snapshot.debian.org/archive/debian/20190323T031635Z/pool/main/n/nettle/libnettle6_3.4.1-1_amd64.deb";
      sha256 = "sha256-WjhMdzrmiwx5BezAq/XkWSV5S2eWdIZtd4PYh4b/sNI=";
    };
    nativeBuildInputs = [pkgs.dpkg];
    unpackPhase = "dpkg-deb -x $src .";
    installPhase = ''
      mkdir -p $out/lib
      cp -P usr/lib/x86_64-linux-gnu/libnettle.so* $out/lib/
    '';
  };

  libldap24 = pkgs.stdenv.mkDerivation {
    pname = "libldap-2.4";
    version = "2.4.47";
    src = pkgs.fetchurl {
      url = "http://snapshot.debian.org/archive/debian/20190323T031635Z/pool/main/o/openldap/libldap-2.4-2_2.4.47+dfsg-3_amd64.deb";
      sha256 = "sha256-Sk0JCEtEm5WWuRufJ8CGp2VBCUjaB5/RURwBHJFanBw=";
    };
    nativeBuildInputs = [pkgs.dpkg];
    unpackPhase = "dpkg-deb -x $src .";
    installPhase = ''
      mkdir -p $out/lib
      cp -P usr/lib/x86_64-linux-gnu/libldap*.so* $out/lib/
      cp -P usr/lib/x86_64-linux-gnu/liblber*.so* $out/lib/
    '';
  };

  libsasl2 = pkgs.stdenv.mkDerivation {
    pname = "libsasl2-2";
    version = "2.1.27";
    src = pkgs.fetchurl {
      url = "http://snapshot.debian.org/archive/debian/20190323T031635Z/pool/main/c/cyrus-sasl2/libsasl2-2_2.1.27+dfsg-1_amd64.deb";
      sha256 = "sha256-1YdvsZPEdqIiChs243eWLc0Cc+P4oupC6bWZ/0gOtlU=";
    };
    nativeBuildInputs = [pkgs.dpkg];
    unpackPhase = "dpkg-deb -x $src .";
    installPhase = ''
      mkdir -p $out/lib
      cp -P usr/lib/x86_64-linux-gnu/libsasl2.so* $out/lib/
    '';
  };

  wrappedServerBin = pkgs.writeShellScript "dst-server-wrapper" ''
    export LD_LIBRARY_PATH="${libcurlGnutls}/lib:${libnettle6}/lib:${libldap24}/lib:${libsasl2}/lib:${lib.makeLibraryPath (with pkgs; [
      glibc
      stdenv.cc.cc.lib
      zlib
      gnutls
      libidn2
      nghttp2
      libpsl
      rtmpdump
      libssh2
      krb5
      e2fsprogs
    ])}"
    cd ${cfg.serverInstallDir}/bin64
    exec ./dontstarve_dedicated_server_nullrenderer_x64 "$@"
  '';

  modsSetupContent = ''
    ${concatMapStringsSep "\n" (modId: ''ServerModSetup("${modId}")'') cfg.mods}
  '';

  makePreStartScript = shardName:
    pkgs.writeShellScript "dst-server-${shardName}-prestart" ''
          set -e

          mkdir -p ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/{Master,Caves,mods}
          mkdir -p ${cfg.dataDir}/.klei/ugc
          mkdir -p ${cfg.dataDir}/DoNotStarveTogether/Agreements

          ${optionalString (cfg.clusterTokenFile != null) ''
        if [ -f "${cfg.clusterTokenFile}" ]; then
          tr -d '\n' < "${cfg.clusterTokenFile}" > ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/cluster_token.txt
          chmod 600 ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/cluster_token.txt
        else
          echo "Error: Cluster token file not found at ${cfg.clusterTokenFile}"
          exit 1
        fi
      ''}
          ${optionalString (cfg.clusterToken != null) ''
        echo -n "${cfg.clusterToken}" > ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/cluster_token.txt
        chmod 600 ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/cluster_token.txt
      ''}

          if [ ! -f ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/cluster.ini ]; then
            cat > ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/cluster.ini <<'EOF'
      ${clusterIniContent}
      EOF
          fi

          if [ ! -f ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/Master/server.ini ]; then
            cat > ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/Master/server.ini <<'EOF'
      ${masterIniContent}
      EOF
          fi

          if [ ! -f ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/Caves/server.ini ]; then
            cat > ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/Caves/server.ini <<'EOF'
      ${cavesIniContent}
      EOF
          fi

          if [ ! -f ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/Master/worldgenoverride.lua ]; then
            cp ${configDir}/worldgenoverride-master.lua ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/Master/worldgenoverride.lua
          fi

          if [ ! -f ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/Caves/worldgenoverride.lua ]; then
            cp ${configDir}/worldgenoverride-caves.lua ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/Caves/worldgenoverride.lua
          fi

          if [ ! -f ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/mods/modsettings.lua ]; then
            cp ${configDir}/modsettings.lua ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/mods/modsettings.lua
          fi

          if [ ! -f ${cfg.dataDir}/DoNotStarveTogether/Agreements/agreements.ini ]; then
            cp ${configDir}/agreements.ini ${cfg.dataDir}/DoNotStarveTogether/Agreements/agreements.ini
          fi

          cat > ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/mods/dedicated_server_mods_setup.lua <<'EOF'
      ${modsSetupContent}
      EOF

          ${optionalString cfg.autoUpdate ''
        echo "Updating DST server..."
        mkdir -p ${cfg.serverInstallDir}
        ${pkgs.steamcmd}/bin/steamcmd \
          +force_install_dir ${cfg.serverInstallDir} \
          +login anonymous \
          +app_update 343050 validate \
          +quit || echo "SteamCMD update failed — continuing with existing installation"
      ''}

          if [ ! -L ${cfg.serverInstallDir}/mods ]; then
            rm -rf ${cfg.serverInstallDir}/mods
            ln -sf ${cfg.dataDir}/DoNotStarveTogether/Cluster_1/mods ${cfg.serverInstallDir}/mods
          fi

          if [ -f "${serverBin}" ] && [ ${toString (length cfg.mods)} -gt 0 ]; then
            echo "Updating mods..."
            ${wrappedServerBin} \
              -only_update_server_mods \
              -persistent_storage_root ${cfg.dataDir} \
              -ugc_directory ${cfg.dataDir}/.klei/ugc \
              -cluster Cluster_1 \
              -shard ${shardName} || true
          fi
    '';

  makeServiceConfig = shardName: {
    description = "Don't Starve Together ${shardName} Shard";
    wantedBy = ["multi-user.target"];
    after =
      ["network.target"]
      ++ optional (shardName == "Caves") "dst-server-master.service";
    requires = optionals (shardName == "Caves") ["dst-server-master.service"];

    preStart = toString (makePreStartScript shardName);

    serviceConfig = {
      Type = "simple";
      User = cfg.user;
      Group = cfg.group;
      Restart = "on-failure";
      RestartSec = "30s";
      TimeoutStartSec = "3600s";
      TimeoutStopSec = "720s";

      ExecStart = "${wrappedServerBin} -skip_update_server_mods -persistent_storage_root ${cfg.dataDir} -ugc_directory ${cfg.dataDir}/.klei/ugc -cluster Cluster_1 -shard ${shardName}";

      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ReadWritePaths = [cfg.dataDir cfg.serverInstallDir];
    };

    path = with pkgs; [steamcmd bash coreutils];

    environment = {
      HOME = cfg.dataDir;
      SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    };
  };
in {
  options.services.dst-server = {
    enable = mkEnableOption "Don't Starve Together dedicated server";

    clusterName = mkOption {
      type = types.str;
      default = "NixOS DST Server";
      description = "The name of your server cluster as shown in the server browser";
    };

    clusterDescription = mkOption {
      type = types.str;
      default = "A Don't Starve Together server running on NixOS";
      description = "A description of your server shown in the server browser";
    };

    clusterPassword = mkOption {
      type = types.str;
      default = "";
      description = "Password required to join the server (empty for no password)";
    };

    clusterTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to the cluster token file.";
    };

    clusterToken = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Cluster token as a string (alternative to clusterTokenFile). WARNING: stored in world-readable Nix store.";
    };

    maxPlayers = mkOption {
      type = types.ints.between 1 64;
      default = 16;
    };

    gameMode = mkOption {
      type = types.enum ["survival" "endless" "wilderness"];
      default = "endless";
    };

    pvpEnabled = mkOption {
      type = types.bool;
      default = false;
    };

    pauseWhenEmpty = mkOption {
      type = types.bool;
      default = true;
    };

    ports = {
      master = mkOption {
        type = types.port;
        default = 10999;
      };
      masterSteam = mkOption {
        type = types.port;
        default = 12346;
      };
      caves = mkOption {
        type = types.port;
        default = 11000;
      };
      cavesSteam = mkOption {
        type = types.port;
        default = 12347;
      };
      shardMaster = mkOption {
        type = types.port;
        default = 10998;
      };
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
    };

    dataDir = mkOption {
      type = types.path;
      default = "/dragon/servers/dontstarve/data";
      description = "Directory for server data, saves, and configuration.";
    };

    serverInstallDir = mkOption {
      type = types.path;
      default = "/dragon/servers/dontstarve/install";
      description = "Directory where the DST server binaries are installed by SteamCMD.";
    };

    user = mkOption {
      type = types.str;
      default = "dst";
    };

    group = mkOption {
      type = types.str;
      default = "dst";
    };

    autoUpdate = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically update the server binary via SteamCMD on start.";
    };

    architecture = mkOption {
      type = types.enum ["x86" "x64"];
      default = "x64";
    };

    mods = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["350811795" "378160973"];
    };

    extraClusterConfig = mkOption {
      type = types.lines;
      default = "";
    };

    extraMasterConfig = mkOption {
      type = types.lines;
      default = "";
    };

    extraCavesConfig = mkOption {
      type = types.lines;
      default = "";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.clusterToken != null) != (cfg.clusterTokenFile != null);
        message = "Exactly one of services.dst-server.clusterToken or services.dst-server.clusterTokenFile must be specified.";
      }
    ];

    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      home = cfg.dataDir;
      createHome = false;
      description = "Don't Starve Together server user";
    };

    users.groups.${cfg.group} = {};

    networking.firewall = mkIf cfg.openFirewall {
      allowedUDPPorts = [
        cfg.ports.master
        cfg.ports.caves
        cfg.ports.masterSteam
        cfg.ports.cavesSteam
      ];
    };

    systemd.services.dst-server-master = makeServiceConfig "Master";
    systemd.services.dst-server-caves = makeServiceConfig "Caves";

    systemd.tmpfiles.rules = [
      "d ${cfg.serverInstallDir} 0755 ${cfg.user} ${cfg.group} -"
      "d ${cfg.dataDir} 0755 ${cfg.user} ${cfg.group} -"
    ];
  };
}
