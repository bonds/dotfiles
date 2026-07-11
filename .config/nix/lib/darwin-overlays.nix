[
  (import ../modules/ollama-overlay.nix)
  (import ../modules/osxphotos-overlay.nix)
  (import ../modules/zen-browser-overlay.nix)
  (import ../modules/opencode-overlay.nix)
  (import ../modules/safari-web-app-overlay.nix)
  (import ../modules/daisydisk-overlay/default.nix)
  # ld64-957.1 crashes on arm64 macOS Sequoia (SIGTRAP) — use Apple's /usr/bin/ld
  (final: prev: {
    ld64 = prev.ld64.overrideAttrs (old: {
      postFixup =
        (old.postFixup or "")
        + ''
          ln -sf /usr/bin/ld $out/bin/ld
        '';
    });
  })
]
