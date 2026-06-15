{
  config,
  pkgs,
  lib,
  self,
  ...
}: let
  pruneGenerations = import ../../modules/prune-generations.nix {inherit pkgs;};

  # Syncthing config.xml generated declaratively
  syncthingConfigDir = "/Users/scott/Library/Application Support/Syncthing";

  syncthingConfig = pkgs.writeText "syncthing-config.xml" ''
    <configuration version="51">
        <folder id="mz9zh-usrfi" label="Documents" path="/Users/scott/Documents" type="sendreceive" rescanIntervalS="3600" fsWatcherEnabled="true" fsWatcherDelayS="10">
            <filesystemType>basic</filesystemType>
            <device id="657I6FW-RYP54TY-656UKW2-GPPI4RE-S5EVPNW-I24PFP2-E33UUIW-OGGDRAT"></device>
        </folder>
        <folder id="photos" label="Photos" path="/Users/scott/Pictures/Syncthing-Photos" type="sendonly" rescanIntervalS="3600" fsWatcherEnabled="true" fsWatcherDelayS="10">
            <filesystemType>basic</filesystemType>
            <device id="657I6FW-RYP54TY-656UKW2-GPPI4RE-S5EVPNW-I24PFP2-E33UUIW-OGGDRAT"></device>
        </folder>
        <device id="UIHTW7V-F3HAJC5-AVFUGTM-XX5LUFU-AW5NQQH-NYABTRZ-UPXBHXH-BNCQCQB" name="Scotts-MacBook-Air" compression="metadata" introducer="false" skipIntroductionRemovals="false">
            <address>dynamic</address>
            <paused>false</paused>
            <autoAcceptFolders>false</autoAcceptFolders>
            <maxSendKbps>0</maxSendKbps>
            <maxRecvKbps>0</maxRecvKbps>
            <maxRequestKiB>0</maxRequestKiB>
            <untrusted>false</untrusted>
            <remoteGUIPort>0</remoteGUIPort>
        </device>
        <device id="657I6FW-RYP54TY-656UKW2-GPPI4RE-S5EVPNW-I24PFP2-E33UUIW-OGGDRAT" name="server" compression="metadata" introducer="false" skipIntroductionRemovals="false">
            <address>dynamic</address>
            <paused>false</paused>
            <autoAcceptFolders>false</autoAcceptFolders>
            <maxSendKbps>0</maxSendKbps>
            <maxRecvKbps>0</maxRecvKbps>
            <maxRequestKiB>0</maxRequestKiB>
            <untrusted>false</untrusted>
            <remoteGUIPort>0</remoteGUIPort>
        </device>
        <gui enabled="true" tls="false" sendBasicAuthPrompt="false">
            <address>127.0.0.1:8384</address>
            <apikey>jxzecw6SznUNJYGHeaJUCA33fTJJgGsJ</apikey>
            <theme>default</theme>
        </gui>
        <ldap></ldap>
        <options>
            <listenAddress>default</listenAddress>
            <globalAnnounceServer>default</globalAnnounceServer>
            <globalAnnounceEnabled>true</globalAnnounceEnabled>
            <localAnnounceEnabled>true</localAnnounceEnabled>
            <localAnnouncePort>21027</localAnnouncePort>
            <localAnnounceMCAddr>[ff12::8384]:21027</localAnnounceMCAddr>
            <maxSendKbps>0</maxSendKbps>
            <maxRecvKbps>0</maxRecvKbps>
            <reconnectionIntervalS>60</reconnectionIntervalS>
            <relaysEnabled>true</relaysEnabled>
            <relayReconnectIntervalM>10</relayReconnectIntervalM>
            <startBrowser>true</startBrowser>
            <natEnabled>true</natEnabled>
            <natLeaseMinutes>60</natLeaseMinutes>
            <natRenewalMinutes>30</natRenewalMinutes>
            <natTimeoutSeconds>10</natTimeoutSeconds>
            <urAccepted>3</urAccepted>
            <urSeen>3</urSeen>
            <urUniqueID>pAtwKGLc</urUniqueID>
            <urURL>https://data.syncthing.net/newdata</urURL>
            <urPostInsecurely>false</urPostInsecurely>
            <urInitialDelayS>1800</urInitialDelayS>
            <autoUpgradeIntervalH>12</autoUpgradeIntervalH>
            <upgradeToPreReleases>false</upgradeToPreReleases>
            <keepTemporariesH>24</keepTemporariesH>
            <cacheIgnoredFiles>false</cacheIgnoredFiles>
            <progressUpdateIntervalS>5</progressUpdateIntervalS>
            <limitBandwidthInLan>false</limitBandwidthInLan>
            <minHomeDiskFree unit="%">1</minHomeDiskFree>
            <releasesURL>https://upgrades.syncthing.net/meta.json</releasesURL>
            <overwriteRemoteDeviceNamesOnConnect>false</overwriteRemoteDeviceNamesOnConnect>
            <tempIndexMinBlocks>10</tempIndexMinBlocks>
            <trafficClass>0</trafficClass>
            <setLowPriority>true</setLowPriority>
            <maxFolderConcurrency>0</maxFolderConcurrency>
            <crashReportingURL>https://crash.syncthing.net/newdata</crashReportingURL>
            <crashReportingEnabled>true</crashReportingEnabled>
            <stunKeepaliveStartS>180</stunKeepaliveStartS>
            <stunKeepaliveMinS>20</stunKeepaliveMinS>
            <stunServer>default</stunServer>
            <maxConcurrentIncomingRequestKiB>0</maxConcurrentIncomingRequestKiB>
            <announceLANAddresses>true</announceLANAddresses>
            <sendFullIndexOnUpgrade>false</sendFullIndexOnUpgrade>
            <auditEnabled>false</auditEnabled>
            <auditFile></auditFile>
            <connectionLimitEnough>0</connectionLimitEnough>
            <connectionLimitMax>0</connectionLimitMax>
            <connectionPriorityTcpLan>10</connectionPriorityTcpLan>
            <connectionPriorityQuicLan>20</connectionPriorityQuicLan>
            <connectionPriorityTcpWan>30</connectionPriorityTcpWan>
            <connectionPriorityQuicWan>40</connectionPriorityQuicWan>
            <connectionPriorityRelay>50</connectionPriorityRelay>
            <connectionPriorityUpgradeThreshold>0</connectionPriorityUpgradeThreshold>
        </options>
        <defaults>
            <folder id="" label="" path="~" type="sendreceive" rescanIntervalS="3600" fsWatcherEnabled="true" fsWatcherDelayS="10" fsWatcherTimeoutS="0" ignorePerms="false" autoNormalize="true">
                <filesystemType>basic</filesystemType>
                <device id="UIHTW7V-F3HAJC5-AVFUGTM-XX5LUFU-AW5NQQH-NYABTRZ-UPXBHXH-BNCQCQB" introducedBy=""></device>
                <minDiskFree unit="%">1</minDiskFree>
                <versioning>
                    <cleanupIntervalS>3600</cleanupIntervalS>
                    <fsPath></fsPath>
                    <fsType>basic</fsType>
                </versioning>
                <copiers>0</copiers>
                <pullerMaxPendingKiB>0</pullerMaxPendingKiB>
                <hashers>0</hashers>
                <order>random</order>
                <ignoreDelete>false</ignoreDelete>
                <scanProgressIntervalS>0</scanProgressIntervalS>
                <pullerPauseS>1</pullerPauseS>
                <pullerDelayS>1</pullerDelayS>
                <maxConflicts>10</maxConflicts>
                <disableSparseFiles>false</disableSparseFiles>
                <paused>false</paused>
                <markerName>.stfolder</markerName>
                <copyOwnershipFromParent>false</copyOwnershipFromParent>
                <modTimeWindowS>0</modTimeWindowS>
                <maxConcurrentWrites>16</maxConcurrentWrites>
                <disableFsync>false</disableFsync>
                <blockPullOrder>standard</blockPullOrder>
                <copyRangeMethod>standard</copyRangeMethod>
                <caseSensitiveFS>false</caseSensitiveFS>
                <junctionsAsDirs>false</junctionsAsDirs>
                <syncOwnership>false</syncOwnership>
                <sendOwnership>false</sendOwnership>
                <syncXattrs>false</syncXattrs>
                <sendXattrs>false</sendXattrs>
                <xattrFilter>
                    <maxSingleEntrySize>1024</maxSingleEntrySize>
                    <maxTotalSize>4096</maxTotalSize>
                </xattrFilter>
            </folder>
            <device id="" compression="metadata" introducer="false" skipIntroductionRemovals="false" introducedBy="">
                <address>dynamic</address>
                <paused>false</paused>
                <autoAcceptFolders>false</autoAcceptFolders>
                <maxSendKbps>0</maxSendKbps>
                <maxRecvKbps>0</maxRecvKbps>
                <maxRequestKiB>0</maxRequestKiB>
                <untrusted>false</untrusted>
                <remoteGUIPort>0</remoteGUIPort>
            </device>
            <ignores></ignores>
        </defaults>
    </configuration>
  '';

  photosExportScript = pkgs.writeShellScript "photos-export" ''
    OSXPHOTOS=""
    for p in "$HOME"/osxphotos-venv/bin/osxphotos "$HOME"/Library/Python/*/bin/osxphotos "$HOME"/.local/bin/osxphotos; do
      if [ -x "$p" ]; then
        OSXPHOTOS="$p"
        break
      fi
    done
    if [ -z "$OSXPHOTOS" ]; then
      echo "$(date) osxphotos not found. Run: pip3 install --user osxphotos" >> /tmp/photos-export.err.log
      exit 1
    fi
    exec "$OSXPHOTOS" export --skip-edited --skip-live --update --directory '{created.year}/{created.month:02d}' "$HOME/Pictures/Syncthing-Photos"
  '';
in {
  # https://github.com/nix-darwin/nix-darwin?tab=readme-ov-file#prerequisites

  # List packages installed in system profile. To search by name, run:
  # $ nix search nixpkgs wget
  # Common packages shared with all machines are in modules/packages/dev.nix and utils.nix
  environment.systemPackages = with pkgs; [
    xclip # for copying from terminal to clipboard
    opencode # AI coding agent
    openssh # macos ssh doesn't come with resident ssh support
    ollama # run LLMs locally
    jan # local AI chat desktop app
    utm # virtual machine manager for macOS
    flux # blue light filter for sleep
    discord # voice and text chat
    daisydisk # disk usage visualizer
    coconutbattery # battery health monitor
    mpv # minimalist media player
    yt-dlp # download videos from YouTube and more
    bun # javascript runtime
    typescript # javascript dialect
    google-cloud-sdk # google cloud CLI and friends
    jujutsu # git alternative
    cloc # count lines of code
    nodejs # needed for hihello development
    whisper-cpp # cli tool for converting audio to text
    angband # best cli game ever
    rustup # rust installer
    autokbisw # switch layout based on which keyboard is plugged in
    ice-bar # menu bar organizer
    clamav # antivirus
    cowsay # cli to print stuff with a pic of a cow saying it
    fortune # random quotes
    delta # git delta syntax highlighter
    the-powder-toy # physics simulation game
    coreutils # for timeout for athome script
    hugo # blog engine
    libreoffice-bin # office suite
    rage # encryption tool (age alternative)
    element-desktop # matrix chat client
    docker # docker
    colima # docker for mac
    mtr # better traceroute
    age-plugin-yubikey # age encryption with YubiKey support
    passage # age-based password manager
    idris2Packages.idris2Lsp # language service provider for idris2
    idris2Packages.pack # packages manager for idris2
    pkgs.syncthing # peer-to-peer file synchronization
    (python3.withPackages (p:
      with p; [
        python-kasa # control TP-Link smart home devices
      ]))
  ];

  nix.settings.experimental-features = "nix-command flakes";

  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = false;

  # Ensure ~/.ssh/authorized_keys points to the XDG-compliant key location
  system.activationScripts.sshAuthorizedKeys = {
    text = ''
      mkdir -p /Users/scott/.ssh
      ln -sf /Users/scott/.config/ssh/keys /Users/scott/.ssh/authorized_keys
    '';
    deps = [];
  };

  # Deploy declarative syncthing config.xml (preserves key.pem, cert.pem, and index-v2/)
  system.activationScripts.extraActivation.text = ''
    echo "syncthing-config: deploying to ${syncthingConfigDir}" >&2
    sudo -u scott mkdir -p "${syncthingConfigDir}"
    cp "${syncthingConfig}" "${syncthingConfigDir}/config.xml"
    chown scott:staff "${syncthingConfigDir}/config.xml"
    chmod 644 "${syncthingConfigDir}/config.xml"
    pgrep -f "Syncthing.app" && pkill -f "Syncthing.app" 2>/dev/null || true
  '';

  # Set Git commit hash for darwin-version.
  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # add a font so libreoffice docs look the same across mac and linux
  fonts.packages = with pkgs; [
    helvetica-neue-lt-std
  ];

  users.users.scott.home = "/Users/scott";
  users.users.scott.shell = pkgs.fish;
  system.primaryUser = "scott";

  # https://www.danielcorin.com/til/nix-darwin/launch-agents/
  launchd = {
    user = {
      agents = {
        ollama-serve = {
          command = "${pkgs.ollama}/bin/ollama serve";
          serviceConfig = {
            KeepAlive = true;
            RunAtLoad = true;
            StandardOutPath = "/tmp/ollama.out.log";
            StandardErrorPath = "/tmp/ollama.err.log";
          };
        };
        prune-generations = {
          command = "${pruneGenerations}/bin/prune-generations";
          serviceConfig = {
            StartCalendarInterval = [
              {
                Hour = 3;
                Minute = 0;
                Weekday = 0;
              }
            ];
            StandardOutPath = "/tmp/prune-generations.out.log";
            StandardErrorPath = "/tmp/prune-generations.err.log";
          };
        };
        syncthing = {
          command = "${pkgs.syncthing}/bin/syncthing --no-browser --home='${syncthingConfigDir}'";
          serviceConfig = {
            KeepAlive = true;
            RunAtLoad = true;
            StandardOutPath = "/tmp/syncthing.out.log";
            StandardErrorPath = "/tmp/syncthing.err.log";
          };
        };
        photos-export = {
          command = "${photosExportScript}";
          serviceConfig = {
            StartCalendarInterval = [
              {
                Hour = 2;
                Minute = 0;
              }
            ];
            StandardOutPath = "/tmp/photos-export.out.log";
            StandardErrorPath = "/tmp/photos-export.err.log";
          };
        };
      };
    };
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "old";
    users.scott = {pkgs, ...}: {
      home.stateVersion = "24.11";
      home.homeDirectory = "/Users/scott";
      imports = [
        ../../modules/home/tmux.nix
      ];
      programs.fish.plugins = with pkgs.fishPlugins; [fzf-fish];
    };
  };
}
