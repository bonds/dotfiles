{
  pkgs,
  lib,
  ...
}: {
  programs.ghostty = {
    enable = true;
    settings =
      {
        font-family = "Liga SFMono Nerd Font";
        font-size = 18.0;
        window-height = 22;
        window-width = 81;
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        # macOS-only settings, with a hard-coded user path. `base.nix` imports
        # this module on the Linux hosts too, so these keys are gated rather
        # than carried (dead, and a darwin path) into a Linux profile.
        macos-option-as-alt = true;
        macos-icon = "custom";
        macos-custom-icon = "/Users/scott/.config/ghostty/ghostty-icon.icns";
      };
  };
}
