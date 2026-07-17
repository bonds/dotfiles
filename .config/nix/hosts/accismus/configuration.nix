{
  pkgs,
  lib,
  inputs,
  ...
}: let
  userHome = import ../../lib/user-home.nix pkgs;
  pruneGenerations = import ../../modules/prune-generations.nix {inherit pkgs;};

  zenIcon = ../../modules/zen-icon.icns;
  setZenIconScript = pkgs.writeText "set-zen-icon.applescript" ''
    use framework "Cocoa"
    set appPath to "/Applications/Nix Apps/Zen.app"
    set iconPath to "${zenIcon}"
    set img to (current application's NSImage's alloc()'s initWithContentsOfFile:iconPath)
    current application's NSWorkspace's sharedWorkspace()'s setIcon:img forFile:appPath options:2
  '';
in {
  imports = [
    ../../modules/packages/macos.nix
  ];

  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = false;

  system.activationScripts = {
    photoRsyncKey.text = ''
      KEYFILE="${userHome}/.ssh/id_photo_rsync"
      if [ ! -f "$KEYFILE" ]; then
        echo "photo-rsync: generating key" >&2
        /usr/bin/ssh-keygen -t ed25519 -f "$KEYFILE" -N "" -C "photo-rsync@accismus"
        chown scott:staff "$KEYFILE" "$KEYFILE.pub" 2>/dev/null || true
      fi
      mkdir -p "${userHome}/Documents/.config"
      cp -f "$KEYFILE".pub "${userHome}/Documents/.config/photo-rsync-key.pub"
    '';
    daisydiskDefaults.text = ''
      sudo -u scott defaults write com.daisydiskapp.DaisyDiskStandAlone SUEnableAutomaticChecks -bool false 2>/dev/null || true
      sudo -u scott defaults write com.daisydiskapp.DaisyDiskStandAlone SUAutomaticallyUpdate -bool false 2>/dev/null || true
    '';
  };

  system.activationScripts.extraActivation.text = lib.mkAfter ''
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

  users.users.scott.home = userHome;
  users.users.scott.shell = pkgs.fish;
  system.primaryUser = "scott";

  # Custom icon for Zen.app — injected into the "applications" activation
  # script so it runs right after rsync deploys the app (otherwise the
  # freshly-rsynced bundle would lose the com.apple.FinderInfo xattr).
  # See the setZenIconScript let-binding for how it works.
  system.activationScripts.applications.text = lib.mkAfter ''
    echo "zen-icon: setting custom icon on Zen.app" >&2
    /usr/bin/osascript "${setZenIconScript}" 2>&1 || true
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
        photos-backup = {
          serviceConfig = {
            ProgramArguments = [
              "/bin/sh"
              "-c"
              ''${pkgs.osxphotos}/bin/osxphotos export --export-as-hardlink --sidecar XMP --skip-edited --skip-live --update --directory "{created.year}/{created.month:02d}" ${userHome}/Pictures/Syncthing-Photos/ && rsync -a --delete --stats -e "ssh -i ${userHome}/.ssh/id_photo_rsync" ${userHome}/Pictures/Syncthing-Photos/ sophrosyne:/dragon/media/photos/''
            ];
            StartCalendarInterval = [
              {
                Hour = 2;
                Minute = 0;
              }
            ];
            StandardOutPath = "/tmp/photos-backup.out.log";
            StandardErrorPath = "/tmp/photos-backup.err.log";
          };
        };
      };
    };
  };

  home-manager = {
    extraSpecialArgs = {inherit inputs;};
    users.scott = {pkgs, ...}: let
      syncthingIds = import ../../lib/syncthing-ids.nix;
    in {
      home.homeDirectory = userHome;

      imports = [
        ../../modules/home/base.nix
        ../../modules/home/direnv.nix
        ../../modules/home/polyptych.nix
        ../../modules/home/reel-summarize.nix
      ];

      services.syncthing = {
        enable = true;
        settings = {
          devices.sophrosyne = {
            id = syncthingIds.sophrosyne;
            name = "sophrosyne";
            addresses = ["dynamic"];
            compression = "metadata";
          };
          folders.Documents = {
            path = "${userHome}/Documents";
            id = "mz9zh-usrfi";
            label = "Documents";
            type = "sendreceive";
            rescanInterval = 3600;
            fsWatcherEnabled = true;
            fsWatcherDelayS = 10;
            devices = ["sophrosyne"];
          };
        };
      };

      programs.reel-summarize.enable = true;
      programs.fish.plugins = with pkgs.fishPlugins; [fzf-fish];
    };
  };
}
