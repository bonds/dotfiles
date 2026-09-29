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
    '';

    meta = {
      description = "Agent-native IDE that runs on your machine";
      homepage = "https://www.onorca.dev/";
      license = prev.lib.licenses.mit;
      platforms = ["aarch64-darwin"];
    };
  };
}
