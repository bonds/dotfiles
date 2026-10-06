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
  (final: _prev: {
    photo-export = final.callPackage ../../pkgs/photokit-export {inherit (final) mkDarwinPackage;};
  })
  (final: _prev: {
    # Native .app wrapper around `raven web` (AppKit + WKWebView). Compiles
    # Swift against the system SDK like photo-export; sees the raven CLI it
    # drives as an attribute path baked into the source.
    raven-desktop = final.callPackage ../../pkgs/raven-desktop {
      inherit (final) mkDarwinPackage;
      raven = final.callPackage ../../pkgs/raven {};
    };
  })
  (import ./zen-browser/default.nix)
  (import ./ghostty/default.nix)
  (import ./orca-ade/default.nix)
  (import ./opencode/default.nix inputs.nixpkgs)
  (import ./daisydisk-overlay/default.nix inputs.nixpkgs)
  (import ./openfang/default.nix inputs.nixpkgs)
  (import ./lix/default.nix)
  (import ./osaurus/default.nix)
  (import ./anyio/default.nix)
  (import ./mcp/default.nix)
  (import ./nodejs/default.nix)
  (final: _prev: {
    oxillama = final.callPackage ../../pkgs/oxillama {};
  })
  inputs.vudials.overlays.default
]
