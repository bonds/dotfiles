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
    };
  };

  programs.home-manager.enable = true;
  programs.fish.plugins = with pkgs.fishPlugins; [fzf-fish];
  systemd.user.startServices = "sd-switch";
}
