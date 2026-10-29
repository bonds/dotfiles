final: prev: {
  ghostty = final.mkDarwinPackage rec {
    pname = "ghostty";
    version = "1.4.0";

    src = prev.fetchurl {
      url = "https://release.files.ghostty.org/${version}/Ghostty.dmg";
      hash = "sha256-OgIHXb0kMY13hCavQd7lUH1T7MRXjt6WkS7Jzm0Y0+g=";
    };

    nativeBuildInputs = [prev._7zz prev.makeBinaryWrapper];

    # DMG has symlinks; 7zz handles them, undmg doesn't
    unpackPhase = ''
      7zz -snld x "$src"
    '';

    installPhase = ''
      mkdir -p $out/Applications $out/bin
      mv Ghostty.app $out/Applications/
      makeWrapper $out/Applications/Ghostty.app/Contents/MacOS/ghostty $out/bin/ghostty
    '';

    meta = {
      description = "Fast, native, feature-rich terminal emulator";
      homepage = "https://ghostty.org/";
      license = prev.lib.licenses.mit;
      platforms = ["aarch64-darwin" "x86_64-darwin"];
    };
  };
}
