final: prev: {
  # Orca ("agent IDE", https://www.onorca.dev/) — Electron desktop app from
  # stablyai/orca GitHub releases. DMG wrapper following the ghostty pattern
  # (7zz handles the symlinks undmg doesn't). Attribute is `orca-ade` because
  # `orca` is taken by nixpkgs' GNOME screen reader.
  orca-ade = final.mkDarwinPackage rec {
    pname = "orca-ade";
    version = "1.4.222";

    src = prev.fetchurl {
      url = "https://github.com/stablyai/orca/releases/download/v${version}/orca-macos-arm64.dmg";
      hash = "sha256-t3ESdsV7NfZ+S4bVXJj2EKMYHze6+hVuyhlyONmjUVk=";
    };

    nativeBuildInputs = [prev.undmg prev.makeBinaryWrapper];

    # Use undmg (NOT 7zz): the DMG's sealed-resource xattrs and the vendor
    # Notarized Developer ID signature (Lovecast LLC) survive undmg extraction,
    # so Gatekeeper/spctl accepts the bundle. 7zz strips those xattrs, and an
    # ad-hoc re-sign is still rejected by spctl on Sequoia (adhoc lacks a
    # trust anchor), which is why a signed 7zz build still reported
    # "Orca is damaged and can't be opened".
    unpackPhase = ''
      undmg "$src"
    '';

    installPhase = ''
      mkdir -p $out/Applications $out/bin
      mv Orca.app $out/Applications/
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
