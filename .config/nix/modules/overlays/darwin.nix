{inputs, ...}: let
  # Expose mkDarwinPackage so overlays can use final.mkDarwinPackage instead
  # of manually importing with stdenvNoCC/lib each time.
  mkDarwinOverlay = final: _prev: {
    mkDarwinPackage = final.callPackage ../../lib/mkDarwinPackage.nix {};
  };
in [
  mkDarwinOverlay
  (import ./ollama/default.nix)
  (import ./osxphotos/default.nix)
  (import ./zen-browser/default.nix)
  (import ./opencode/default.nix)
  (import ./daisydisk-overlay/default.nix)
  inputs.vudials.overlays.default
]
