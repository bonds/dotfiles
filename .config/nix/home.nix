{ config, pkgs, ... }:

let lib = pkgs.lib; in
{
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "scott";
  home.homeDirectory = "/home/scott";

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.05"; # Please read the comment before changing.
  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
    #   echo "Hello, ${config.home.username}!"
    # '')
    # pkgs.httpie
    pkgs.gnome.gnome-themes-extra
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';

    ".config/autostart/ulauncher.desktop".text = ''
      [Desktop Entry]

      Type=Application
      Name=ulauncher
      Comment=An app launcher
      Path=/run/current-system/sw/bin
      Exec=env GDK_BACKEND=x11 ulauncher
      Terminal=false
    '';

    ".local/share/applications/dwarf.desktop".text = ''
      [Desktop Entry]

      Type=Application
      Name=Dwarf Fortress
      Comment=a really great game
      Path=/run/current-system/sw/bin
      Exec=dwarf-fortress
      Terminal=false
    '';

    # https://discourse.nixos.org/t/generate-and-install-ublock-config-file-with-home-manager/19209
    # https://www.reddit.com/r/uBlockOrigin/comments/16bzb11/configuring_ublock_origin_for_nix_users_just_in/
    ".mozilla/managed-storage/uBlock0@raymondhill.net.json".text =
      builtins.toJSON {
        name = "uBlock0@raymondhill.net";
        description = "_";
        type = "storage";
        data = {
          adminSettings = {
            userFilters = ''
              cnn.com##.header__wrapper-outer:style(height: 30px !important)
            '';
          };
        };
      }; 
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. These will be explicitly sourced when using a
  # shell provided by Home Manager. If you don't want to manage your shell
  # through Home Manager then you have to manually source 'hm-session-vars.sh'
  # located at either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/scott/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    # EDITOR = "emacs";
  };

  dconf.settings = let inherit (lib.gvariant) mkTuple mkUint32 mkVariant; in {
    "org/gnome/settings-daemon/plugins/power" = {
      sleep-inactive-ac-timeout = 3600;
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };

    "org/gnome/settings-daemon/plugins/color" = {
      night-light-enabled = true;
    };

    "org/gnome/shell" = {
      enabled-extensions = [
        "dash-to-panel@jderose9.github.com"
        "another-window-session-manager@gmail.com"
        "pano@elhan.io"
        "blur-my-shell@aunetx"
        "espresso@coadmunkee.github.com"
      ];
    };

    "org/gnome/shell/extensions/dash-to-panel" = {
      dot-position = "BOTTOM";
    };

    "org/gnome/shell/extensions/dash-to-panel" = {
      show-favorites = false;
      hide-overview-on-startup = false;
      isolate-monitors = true;
      panel-positions = ''
        {"0":"TOP","1":"TOP","2":"TOP"}
      '';
      panel-sizes = ''
        {"0":36,"1":36,"2":36}
      '';
      status-icon-padding = 4;
      panel-element-positions = ''
        {"0":[{"element":"showAppsButton","visible":true,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":true,"position":"stackedBR"},{"element":"systemMenu","visible":false,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}],"1":[{"element":"showAppsButton","visible":true,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":false,"position":"stackedBR"},{"element":"systemMenu","visible":true,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}],"2":[{"element":"showAppsButton","visible":true,"position":"stackedTL"},{"element":"activitiesButton","visible":false,"position":"stackedTL"},{"element":"leftBox","visible":true,"position":"stackedTL"},{"element":"taskbar","visible":true,"position":"stackedTL"},{"element":"centerBox","visible":true,"position":"stackedBR"},{"element":"rightBox","visible":true,"position":"stackedBR"},{"element":"dateMenu","visible":false,"position":"stackedBR"},{"element":"systemMenu","visible":false,"position":"stackedBR"},{"element":"desktopButton","visible":true,"position":"stackedBR"}]}
      '';
    };

    "org/gnome/desktop/input-sources" = {
      xkb-options = [
        "terminate:ctrl_alt_bksp"
        "ctrl:swap_lwin_lctl"
        "ctrl:swap_rwin_rctl"
      ];
    };

    "org/gnome/desktop/wm/preferences" = {
      num-workspaces = 1;
    };

    "org/gnome/shell/weather" = {
      automatic-location = true;
      locations = [ 
        (mkVariant (mkTuple [
            (mkUint32 2) 
            (mkVariant (mkTuple [
              "Palo Alto" 
              "KPAO" 
              true 
              [(mkTuple [0.6539166988983063 (-2.1313379107115065)])]
              [(mkTuple [0.653484136496492  (-2.1317978398759916)])]
            ])) 
        ]))
      ];
    };

    "org/gnome/shell/world-clocks" = {
      locations = [ 
        (mkVariant (mkTuple [ 
          (mkUint32 2) 
          (mkVariant (mkTuple [ 
            "Tel Aviv"
            "LLBG"
            true 
            [(mkTuple [0.5585053606381855 0.609119908946021 ])]
            [(mkTuple [0.5596689192906126 0.6067928090944594])]
            ]))
        ]))
      ];
    };

    "org/gnome/desktop/background" = {
      picture-uri = "file:///home/scott/.config/background";
    };

    "org/gnome/desktop/background" = {
      picture-option = "spanned";
    };
    
    "org/gnome/desktop/background" = {
      picture-uri-dark = "file:///home/scott/.config/background";
    };

    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
      ];
    };

    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "Ulauncher";
      binding = "<Control>space";
      command = "/run/current-system/sw/bin/ulauncher-toggle";
    };
    
    "org/gnome/Console" = {
      font-scale = 1.3;
    };

    "org/gnome/shell/keybindings" = {
      show-screen-recording-ui = [
        "<Shift><Control>p"
      ];
    };

    "org/gnome/Console" = {
      use-system-font = false;
    };

    "org/gnome/Console" = {
      custom-font = "Liga SFMono Nerd Font 10";
    };

    "org/gnome/desktop/interface" = {
      gtk-theme = "Adwaita-dark";
    };

  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

}
