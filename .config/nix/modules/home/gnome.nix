# GNOME desktop settings for metanoia.
{lib, ...}: let
  inherit (lib.gvariant) mkTuple mkUint32 mkVariant;
in {
  dconf.settings = {
    "org/gnome/settings-daemon/plugins/power" = {
      sleep-inactive-ac-timeout = 900;
    };
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "Adwaita-dark";
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
        "window-calls@domandoman.xyz"
      ];
    };
    "org/gnome/shell/extensions/dash-to-panel" = {
      dot-position = "BOTTOM";
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
            [(mkTuple [0.653484136496492 (-2.1317978398759916)])]
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
            [(mkTuple [0.5585053606381855 0.609119908946021])]
            [(mkTuple [0.5596689192906126 0.6067928090944594])]
          ]))
        ]))
      ];
    };
    "org/gnome/desktop/background" = {
      picture-uri = "file:///home/scott/.config/background";
      picture-option = "spanned";
      picture-uri-dark = "file:///home/scott/.config/background";
    };
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom1/"
        "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2/"
      ];
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      name = "Ulauncher";
      binding = "<Control>space";
      command = "/run/current-system/sw/bin/ulauncher-toggle";
    };
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom2" = {
      name = "maximize window across all monitors";
      binding = "<Control><Shift>m";
      command = "/home/scott/bin/linux/maximize_across_multiple_monitors";
    };
    "org/gnome/Console" = {
      font-scale = 1.3;
      use-system-font = false;
      custom-font = "Liga SFMono Nerd Font 10";
    };
    "org/gnome/shell/keybindings" = {
      show-screen-recording-ui = [
        "<Shift><Control>p"
      ];
    };
    "org/gnome/shell/extensions/another-window-session-manager" = {
      enable-autorestore-sessions = true;
      restore-at-startup-without-asking = true;
      autorestore-sessions = "defaultSession";
    };
  };

  xdg.desktopEntries = {
    dwarf = {
      name = "Dwarf Fortress";
      comment = "a really great game";
      exec = "dwarf-fortress";
      settings = {
        Path = "/run/current-system/sw/bin";
      };
    };
  };
}
