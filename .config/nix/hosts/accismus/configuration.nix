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

  osaurusIcon = ../../modules/overlays/osaurus/osaurus-icon.icns;
  setOsaurusIconScript = pkgs.writeText "set-osaurus-icon.applescript" ''
    use framework "Cocoa"
    set appPath to "/Applications/Nix Apps/osaurus.app"
    set iconPath to "${osaurusIcon}"
    set img to (current application's NSImage's alloc()'s initWithContentsOfFile:iconPath)
    current application's NSWorkspace's sharedWorkspace()'s setIcon:img forFile:appPath options:2
  '';

  hermesIcon = ../../modules/overlays/hermes-icon.icns;
  setHermesIconScript = pkgs.writeText "set-hermes-icon.applescript" ''
    use framework "Cocoa"
    set appPath to "/Applications/Nix Apps/Hermes.app"
    set iconPath to "${hermesIcon}"
    set img to (current application's NSImage's alloc()'s initWithContentsOfFile:iconPath)
    current application's NSWorkspace's sharedWorkspace()'s setIcon:img forFile:appPath options:2
  '';
in {
  imports = [
    ../../modules/packages/macos.nix
  ];

  security.pam.services.sudo_local.touchIdAuth = true;
  security.pam.services.sudo_local.reattach = false;

  # Passwordless sudo for scott on the rebuild tool — lets `nr` run unattended
  # (no sudo password prompt / no TouchID). Mirrors the NOPASSWD pattern on
  # sophrosyne via doas. `nr` calls `sudo darwin-rebuild switch` directly
  # (deliberately NOT nh: nh wraps elevated commands in `sudo env … <cmd>`,
  # which cannot be scoped by sudoers to anything narrower than full root).
  # darwin-rebuild must run as root to update /nix/var/nix/profiles/system.
  security.sudo.extraConfig = ''
    scott ALL = NOPASSWD: /run/current-system/sw/bin/darwin-rebuild
  '';

  age.identityPaths = ["/etc/age/identity"];

  system.activationScripts.agenixIdentity = {
    text = ''
      mkdir -p /etc/age
      if [ ! -f /etc/age/identity ]; then
        ${pkgs.ssh-to-age}/bin/ssh-to-age -private-key -i /etc/ssh/ssh_host_ed25519_key > /etc/age/identity
        chmod 600 /etc/age/identity
      fi
    '';
  };

  system.activationScripts.osaurusApiKey = {
    deps = ["agenix"];
    text = ''
      mkdir -p "${userHome}/.config/reel-summarize"
      ln -sf /etc/agenix/osaurus-api-key "${userHome}/.config/reel-summarize/osaurus-api-key"
    '';
  };

  age.secrets = {
    osaurus-api-key = {
      file = ../../secrets/osaurus-api-key.age;
      owner = "scott";
      group = "staff";
      mode = "0400";
    };
    # OpenRouter API key for Hermes Agent. Content is the OpenRouter key
    # line (`OPENROUTER_API_KEY=<key>`), which Hermes loads via
    # services.hermes-agent.environmentFiles into $HERMES_HOME/.env.
    hermes-openrouter = {
      file = ../../secrets/hermes-openrouter.age;
      owner = "scott";
      group = "staff";
      mode = "0400";
    };
    # soju bouncer password on sophrosyne. macOS agenix mounts it at
    # /run/agenix/soju-password, which Halloy reads via password_file. Same
    # secret seeds soju's user on sophrosyne (see hosts/sophrosyne).
    soju-password = {
      file = ../../secrets/soju-password.age;
      owner = "scott";
      group = "staff";
      mode = "0400";
    };
  };

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

  networking.hostName = "accismus";
  networking.computerName = "Scott's MacBook Air";

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

    echo "osaurus-icon: setting custom icon on osaurus.app" >&2
    /usr/bin/osascript "${setOsaurusIconScript}" 2>&1 || true

    echo "hermes-icon: setting custom icon on Hermes.app" >&2
    /usr/bin/osascript "${setHermesIconScript}" 2>&1 || true
  '';

  # https://www.danielcorin.com/til/nix-darwin/launch-agents/
  launchd = {
    user = {
      agents = {
        # --- Disabled 2026-08-04: moving to MCP on sophrosyne ---
        # llamacpp-serve = {
        #   command = "${llamacppServeScript}";
        #   serviceConfig = {
        #     KeepAlive = true;
        #     RunAtLoad = true;
        #     StandardOutPath = "${userHome}/Library/Logs/llamacpp.out.log";
        #     StandardErrorPath = "${userHome}/Library/Logs/llamacpp.err.log";
        #   };
        # };
        # llamacpp-vision-serve = {
        #   command = "${llamacppVisionServeScript}";
        #   serviceConfig = {
        #     KeepAlive = true;
        #     RunAtLoad = true;
        #     StandardOutPath = "${userHome}/Library/Logs/llamacpp-vision.out.log";
        #     StandardErrorPath = "${userHome}/Library/Logs/llamacpp-vision.err.log";
        #   };
        # };
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
            StandardOutPath = "${userHome}/Library/Logs/prune-generations.out.log";
            StandardErrorPath = "${userHome}/Library/Logs/prune-generations.err.log";
          };
        };
        photos-backup = {
          command = "${userHome}/bin/photos-backup";
          serviceConfig = {
            StartCalendarInterval = [
              {
                Hour = 2;
                Minute = 0;
              }
            ];
            StandardOutPath = "${userHome}/Library/Logs/photos-backup.out.log";
            StandardErrorPath = "${userHome}/Library/Logs/photos-backup.err.log";
          };
        };
      };
    };
  };

  home-manager = {
    extraSpecialArgs = {
      inherit inputs;
    };
    users.scott = {pkgs, ...}: let
      syncthingIds = import ../../lib/syncthing-ids.nix;
    in {
      home.homeDirectory = userHome;

      imports = [
        ../../modules/home/base.nix
        ../../modules/home/direnv.nix
        ../../modules/home/halloy.nix
        ../../modules/home/ice.nix
        ../../modules/home/photo-export.nix
        ../../modules/home/polyptych.nix
        ../../modules/home/reel-summarize.nix
        inputs.hermes-agent.homeManagerModules.default
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
            id = syncthingIds.folders.Documents;
            label = "Documents";
            type = "sendreceive";
            rescanInterval = 3600;
            fsWatcherEnabled = true;
            fsWatcherDelayS = 10;
            devices = ["sophrosyne"];
          };
          folders.Home = {
            path = "${userHome}";
            id = syncthingIds.folders.Home;
            label = "Home";
            type = "sendonly";
            rescanInterval = 3600;
            devices = ["sophrosyne"];
          };
        };
      };

      programs.reel-summarize.enable = true;
      programs.photo-export.enable = true;
      programs.photo-export.settings.selfmount = true;
      # Use SFTP transport: stream originals in-memory to sophrosyne as
      # photo-backup (owner of /dragon/media/photos). LAN host first; the tailnet
      # MagicDNS name works too (the key has no from= restriction). swap
      # .local for the MagicDNS name when away from the LAN.
      programs.photo-export.settings.remoteHost = "sophrosyne.local";
      programs.photo-export.settings.remoteUser = "photo-backup";
      programs.fish.plugins = with pkgs.fishPlugins; [fzf-fish];

      # Hermes Agent (Nous Research) — OpenRouter provider via agenix secret.
      # The agenix-mount env file (content: OPENROUTER_API_KEY=<key>) is loaded
      # into $HERMES_HOME/.env by services.hermes-agent.environmentFiles.
      programs.hermes-agent.enable = true;
      programs.hermes-agent.desktop.enable = true;
      services.hermes-agent = {
        enable = true;
        # browser dashboard at 127.0.0.1:9119 (interactive setup/first-run)
        backend.mode = "dashboard";
        # OpenRouter API key lives in agenix, decrypted to /run/agenix/ on
        # accismus (active generation dir). Hermes merges it into
        # $HERMES_HOME/.env at activation.
        environmentFiles = ["/run/agenix/hermes-openrouter"];
        settings.model.provider = "openrouter";
        # Default model on OpenRouter (DeepSeek V4 Flash)
        settings.model.default = "deepseek/deepseek-v4-flash-0731";
        # Enable the "session-cost" user plugin backend (sums state.db) so the
        # desktop status-bar chip can read per-session spend.
        settings.plugins.enabled = ["session-cost"];
      };

      home.file.".stignore".text = ''
        # Specific excludes within included dirs
        /.config/dotfiles/**
        /.config/opencode/node_modules/**
        /.config/opencode/skills/**

        # Include specific directories (root-level, no traversal)
        !/.config
        !/Desktop
        !/Documents
        !/Downloads
        !/.plan

        # Deny everything else
        *
      '';
    };
  };
}
