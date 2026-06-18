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

  syncthingConfig = pkgs.writeText "syncthing-config.xml" (builtins.readFile ./syncthing-config.xml);

  photosExportScript = pkgs.writeShellScript "photos-export" ''
    exec ${pkgs.osxphotos}/bin/osxphotos export --skip-edited --skip-live --update --directory '{created.year}/{created.month:02d}' "$HOME/Pictures/Syncthing-Photos"
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
    zen-browser # firefox fork with vertical tabs
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
    pkgs.osxphotos # export photos from Apple Photos app
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

  # Remind about manual first-run setup for Zen browser containers
  system.activationScripts.checkZenSetup.text = ''
    containers_setup="$HOME/.config/zen/containers-setup"
    if [ ! -f "$containers_setup" ]; then
      echo "REMINDER: Set up Zen browser containers (one-time):" >&2
      echo "  1. Launch Zen, open Settings > Containers" >&2
      echo "  2. Create: Personal (fingerprint/blue), Work (briefcase/orange)," >&2
      echo "     Banking (dollar/green), Shopping (cart/pink)" >&2
      echo "  3. Run: touch $containers_setup" >&2
      echo "  (this reminder won't show again)" >&2
    fi
  '';

  # Ensure /Applications/Zen.app points to the nix-built version (not DMG)
  system.activationScripts.ensureZenSymlink.text = ''
    nix_zen="/Applications/Nix Apps/Zen.app"
    app_zen="/Applications/Zen.app"
    if [ -d "$nix_zen" ] && [ ! -L "$app_zen" ]; then
      if [ -d "$app_zen" ]; then
        echo "zen-browser: moving DMG install to $app_zen.dmg-backup" >&2
        mv "$app_zen" "$app_zen.dmg-backup-$(date +%Y%m%d)"
      fi
      ln -s "$nix_zen" "$app_zen"
      echo "zen-browser: symlinked $app_zen -> $nix_zen" >&2
    fi
  '';

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
        ../../modules/home/direnv.nix
      ];
      programs.fish.plugins = with pkgs.fishPlugins; [fzf-fish];
    };
  };
}
