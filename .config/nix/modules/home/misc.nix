# Misc home-manager settings for metanoia.
{
  config,
  pkgs,
  ...
}: {
  home = {
    packages = with pkgs; [
      gnome-themes-extra # GTK theme engine and base themes
    ];
    file = {
      ".config/wireplumber/wireplumber.conf.d/51-disable-devices.conf".text = ''
        monitor.alsa.rules = [
          {
            matches = [
              {
                device.name = "~alsa_card.pci-*"
              }
              {
                device.name = "~alsa_card.usb-Elgato_*"
              }
            ]
            actions = {
              update-props = {
              	device.disabled = true
              }
            }
          }
        ]
      '';

      ".mozilla/managed-storage/uBlock0@raymondhill.net.json".text = builtins.toJSON {
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
  };

  programs.home-manager.enable = true;
  programs.fish.plugins = with pkgs.fishPlugins; [fzf-fish];
  systemd.user.startServices = "sd-switch";
}
