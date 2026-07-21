{inputs, ...}: let
  # Expose mkDarwinPackage so overlays can use final.mkDarwinPackage instead
  # of manually importing with stdenvNoCC/lib each time.
  mkDarwinOverlay = final: _prev: {
    mkDarwinPackage = final.callPackage ../../lib/mkDarwinPackage.nix {};
  };
in [
  mkDarwinOverlay
  (final: _prev: {
    transcribe-cpp = final.callPackage ../../pkgs/transcribe-cpp {};
    transcribe-cpp-python = final.callPackage ../../pkgs/transcribe-cpp-python {};
  })
  (import ./osxphotos/default.nix)
  (import ./zen-browser/default.nix)
  (import ./ghostty/default.nix)
  (import ./opencode/default.nix)
  (import ./daisydisk-overlay/default.nix)
  (import ./osaurus/default.nix)
  (final: _prev: {
    oxillama = final.callPackage ../../pkgs/oxillama {};
  })
  inputs.vudials.overlays.default
]
