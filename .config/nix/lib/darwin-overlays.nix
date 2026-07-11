[
  (import ../modules/ollama-overlay.nix)
  (import ../modules/osxphotos-overlay.nix)
  (import ../modules/zen-browser-overlay.nix)
  (import ../modules/opencode-overlay.nix)
  (import ../modules/safari-web-app-overlay.nix)
  (import ../modules/daisydisk-overlay/default.nix)
  # Override the ld wrapper to use /usr/bin/ld instead of the broken cctools ld64
  # (which crashes with SIGTRAP on arm64 macOS Sequoia).  This is above the
  # bootstrap chain, so it won't trigger stage2-stage4 rebuilds.
  (final: prev: {
    cctools-binutils-darwin-wrapper = prev.cctools-binutils-darwin-wrapper.overrideAttrs (old: {
      postInstall =
        (old.postInstall or "")
        + ''
          # Rewrite the hardcoded ld path in the generated wrapper script
          sed -i 's|/nix/store/[a-z0-9]\+-cctools-binutils-darwin-[0-9.]\+/bin/ld|/usr/bin/ld|g' \
            "$out/bin/ld"
        '';
    });
  })
]
