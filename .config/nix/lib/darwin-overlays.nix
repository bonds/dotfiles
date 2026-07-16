let
  # Expose mkDarwinPackage so overlays can use final.mkDarwinPackage instead
  # of manually importing with stdenvNoCC/lib each time.
  mkDarwinOverlay = final: prev: {
    mkDarwinPackage = final.callPackage ../lib/mkDarwinPackage.nix {};
  };
in [
  mkDarwinOverlay
  (import ../modules/ollama/default.nix)
  (import ../modules/osxphotos/default.nix)
  (import ../modules/zen-browser/default.nix)
  (import ../modules/opencode/default.nix)
  (import ../modules/daisydisk-overlay/default.nix)
]
