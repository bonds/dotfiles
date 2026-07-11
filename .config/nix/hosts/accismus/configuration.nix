{
  config,
  pkgs,
  lib,
  self,
  inputs,
  ...
}: let
  pruneGenerations = import ../../modules/prune-generations.nix {inherit pkgs;};

  # Syncthing config.xml generated declaratively
  syncthingConfigDir = "/Users/scott/Library/Application Support/Syncthing";

  syncthingConfig = pkgs.writeText "syncthing-config.xml" (builtins.readFile ./syncthing-config.xml);

  # Custom icon for Zen.app — the DMG ships a Firefox icon packed in
  # Assets.car which shadows the .icns file, so replacing firefox.icns alone
  # doesn't work.  This AppleScript calls NSWorkspace.setIcon (same mechanism
  # as pasting into Get Info) to set a custom icon that overrides everything.
  zenIcon = ../../modules/zen-icon.icns;
  setZenIconScript = pkgs.writeText "set-zen-icon.applescript" ''
    use framework "Cocoa"
    set appPath to "/Applications/Nix Apps/Zen.app"
    set iconPath to "${builtins.unsafeDiscardStringContext (builtins.toString zenIcon)}"
    set img to (current application's NSImage's alloc()'s initWithContentsOfFile:iconPath)
    current application's NSWorkspace's sharedWorkspace()'s setIcon:img forFile:appPath options:2
  '';
in {
  # $ nix search nixpkgs wget
  # Common packages shared with all machines are in modules/packages/dev.nix and utils.nix
  environment.systemPackages = with pkgs;
    [
      caffeine # don't go to sleep
      xclip # for copying from terminal to clipboard
      opencode # AI coding agent (CLI, binary overlay, nr --update)
      inputs.neocode.packages.${pkgs.stdenv.hostPlatform.system}.default # Native macOS SwiftUI client for OpenCode (community, flake, nr --update)
      opencode-desktop # OpenCode Electron desktop app (binary overlay, auto-updater disabled)
      openssh # macos ssh doesn't come with resident ssh support
      ollama # run LLMs locally
      jan # local AI chat desktop app
      utm # virtual machine manager for macOS
      flux # blue light filter for sleep
      zen-browser # firefox fork with vertical tabs
      discord # voice and text chat
      inputs.polyptych.packages.${pkgs.stdenv.hostPlatform.system}.default # spanned fullscreen video player
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
      lima # vms for mac
      mtr # better traceroute
      age-plugin-yubikey # age encryption with YubiKey support
      passage # age-based password manager
      idris2Packages.idris2Lsp # language service provider for idris2
      idris2Packages.pack # packages manager for idris2
      duti # set default file handlers for macOS
      syncthing # peer-to-peer file synchronization
      tailscale # tailnet CLI
      osxphotos # export photos from Apple Photos app
      (python3.withPackages (p:
        with p; [
          python-kasa # control TP-Link smart home devices
        ]))
    ]
    ++ [
      (pkgs.callPackage ../../pkgs/ghosttile {})

      # safari-web-app-slack # Safari web app wrapper (native WebKit, no Electron) — disabled, higher mem than Electron Slack
      nh # nix helper for rebuilds and garbage collection (darwin, no programs.nh module)
    ];

  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = false;

  # Deploy declarative syncthing config.xml (preserves key.pem, cert.pem, and index-v2/)
  system.activationScripts.extraActivation.text = ''
    echo "syncthing-config: deploying to ${syncthingConfigDir}" >&2
    sudo -u scott mkdir -p "${syncthingConfigDir}"
    cp "${syncthingConfig}" "${syncthingConfigDir}/config.xml"
    chown scott:staff "${syncthingConfigDir}/config.xml"
    chmod 644 "${syncthingConfigDir}/config.xml"
    pgrep -f "Syncthing.app" && pkill -f "Syncthing.app" 2>/dev/null || true
  '';

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";

  # add a font so libreoffice docs look the same across mac and linux
  fonts.packages = with pkgs; [
    helvetica-neue-lt-std
    nerd-fonts.jetbrains-mono
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

  # Custom icon for Zen.app — injected into the "applications" activation
  # script so it runs right after rsync deploys the app (otherwise the
  # freshly-rsynced bundle would lose the com.apple.FinderInfo xattr).
  # See the setZenIconScript let-binding for how it works.
  system.activationScripts.applications.text = lib.mkAfter ''
    echo "zen-icon: setting custom icon on Zen.app" >&2
    /usr/bin/osascript "${setZenIconScript}" 2>&1 || true
  '';

  # Symlink nix-built Safari web app (Slack) into ~/Applications/ so Spotlight
  # indexes it like Apple's own "Add to Dock" web apps.
  # system.activationScripts.safariWebApps.text = ''
  #   SRC="${pkgs.safari-web-app-slack}/Applications/Slack.app"
  #   DST="/Users/scott/Applications/Slack.app"
  #   if [ -e "$DST" ]; then
  #     rm -rf "$DST"
  #   fi
  #   ln -sf "$SRC" "$DST"
  #   echo "safari-web-app: symlinked Slack.app to $DST"
  # '';

  # Disable cmux's built-in Sparkle auto-updater so `nr --update` is the
  # only update path (matches ollama/opencode pinned-overlay discipline).
  system.activationScripts.disableCmuxSparkle.text = ''
    sudo -u scott defaults write com.cmuxterm.app SUEnableAutomaticUpdates -bool false 2>/dev/null || true
  '';

  # Disable DaisyDisk's built-in Sparkle auto-updater so `nr --update` is the
  # only update path (matches ollama/opencode pinned-overlay discipline).
  system.activationScripts.disableDaisyDiskSparkle.text = ''
    sudo -u scott defaults write com.daisydiskapp.DaisyDiskStandAlone SUEnableAutomaticChecks -bool false 2>/dev/null || true
    sudo -u scott defaults write com.daisydiskapp.DaisyDiskStandAlone SUAutomaticallyUpdate -bool false 2>/dev/null || true
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
          serviceConfig = {
            ProgramArguments = [
              "/Applications/Nix Apps/OSXPhotos.app/Contents/MacOS/osxphotos"
              "export"
              "--skip-edited"
              "--skip-live"
              "--update"
              "--directory"
              "{created.year}/{created.month:02d}"
              "/Users/scott/Pictures/Syncthing-Photos"
            ];
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
    extraSpecialArgs = {inherit inputs;};
    users.scott = {pkgs, ...}: {
      home.stateVersion = "24.11";
      home.homeDirectory = "/Users/scott";
      imports = [
        ../../modules/home/tmux.nix
        ../../modules/home/direnv.nix
        ../../modules/home/polyptych.nix
        ../../modules/home/what-changed.nix
        ../../modules/home/reel-summarize.nix
      ];
      programs.what-changed.enable = true;
      programs.reel-summarize.enable = true;
      programs.fish.plugins = with pkgs.fishPlugins; [fzf-fish];
    };
  };
}
