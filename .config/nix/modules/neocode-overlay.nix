final: prev: {
  neocode = prev.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "neocode";
    version = "0.8.1";

    src = prev.fetchurl {
      url = "https://github.com/watzon/NeoCode/releases/download/v${finalAttrs.version}/NeoCode.dmg";
      hash = "sha256-v4gLQRRCg1ie7gMbJrhrgSJahS2rBMTnU/bfiLNCNus=";
    };

    sourceRoot = ".";

    nativeBuildInputs = [prev._7zz];

    installPhase = ''
      mkdir -p $out/Applications $out/bin
      cp -r NeoCode/NeoCode.app $out/Applications/

      # Strip Sparkle auto-updater config so the app never checks for or
      # notifies about updates (nr --update is the only path). Matches the
      # opencode-desktop pattern of stripping app-update.yml.
      /usr/bin/plutil -remove SUFeedURL $out/Applications/NeoCode.app/Contents/Info.plist 2>/dev/null || true
      /usr/bin/plutil -remove SUEnableAutomaticUpdates $out/Applications/NeoCode.app/Contents/Info.plist 2>/dev/null || true

      # Clean up HFS+ extended attribute artifacts that 7zz extracts as
      # separate files; codesign rejects these as unsealed contents.
      find $out/Applications/NeoCode.app -name '*.HFS+' -delete 2>/dev/null || true
      find $out/Applications/NeoCode.app -name '*:com.apple.*' -delete 2>/dev/null || true
      find $out/Applications/NeoCode.app -name '.DS_Store' -delete 2>/dev/null || true

      # Removing Info.plist keys and HFS+ residue invalidates the embedded
      # Developer ID signature. Since the nix store has no quarantine xattr,
      # ad-hoc signing is sufficient (no Gatekeeper enforcement). Also strips
      # the Hardened Runtime flag — acceptable for a nix-managed app.
      find $out/Applications/NeoCode.app -name '_CodeSignature' -type d -exec rm -rf {} + 2>/dev/null || true
      /usr/bin/codesign --force --deep --sign - $out/Applications/NeoCode.app

      ln -s $out/Applications/NeoCode.app/Contents/MacOS/NeoCode $out/bin/neocode
    '';

    dontFixup = true;

    meta = {
      description = "Native macOS SwiftUI client for OpenCode (Sparkle auto-updater disabled)";
      homepage = "https://github.com/watzon/NeoCode";
      license = prev.lib.licenses.mit;
      platforms = ["aarch64-darwin"];
      mainProgram = "neocode";
    };
  });
}
