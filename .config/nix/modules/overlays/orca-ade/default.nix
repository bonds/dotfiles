final: prev: {
  # Orca ("agent IDE", https://www.onorca.dev/) — Electron desktop app from
  # stablyai/orca GitHub releases. DMG wrapper following the ghostty pattern
  # (7zz handles the symlinks undmg doesn't). Attribute is `orca-ade` because
  # `orca` is taken by nixpkgs' GNOME screen reader.
  orca-ade = final.mkDarwinPackage rec {
    pname = "orca-ade";
    version = "1.4.217";

    src = prev.fetchurl {
      url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-macos-arm64.dmg";
      hash = "sha256-YyMCWM7Zi2bp9cf43sSMhU+HfVsQRkhbjBUXCKr4CCo=";
    };

    nativeBuildInputs = [prev._7zz prev.makeBinaryWrapper];

    # DMG has symlinks; 7zz handles them, undmg doesn't
    unpackPhase = ''
      7zz -snld x "$src"
    '';

    installPhase = ''
      mkdir -p $out/Applications $out/bin
      mv "Orca ${version}-arm64/Orca.app" $out/Applications/
      makeWrapper $out/Applications/Orca.app/Contents/MacOS/Orca $out/bin/orca

      # The vendor _CodeSignature is invalidated by 7zz extraction: the
      # per-file com.apple.cs.CodeSignature/CodeRequirements xattrs it stamps
      # don't survive (only com.apple.provenance remains), so Gatekeeper
      # reports "Orca is damaged and can't be opened" and codesign --verify
      # fails with "a sealed resource is missing or invalid". Strip the stale
      # signature and re-sign ad-hoc (same pattern as openfang-overlay) so
      # LaunchServices/Spotlight accept the bundle.
      APP="$out/Applications/Orca.app"
      chmod -R u+w "$APP"
      rm -rf "$APP/Contents/_CodeSignature"
      /usr/bin/codesign --force --deep -s - "$APP"
    '';

    meta = {
      description = "Agent-native IDE that runs on your machine";
      homepage = "https://www.onorca.dev/";
      license = prev.lib.licenses.mit;
      platforms = ["aarch64-darwin"];
    };
  };
}
