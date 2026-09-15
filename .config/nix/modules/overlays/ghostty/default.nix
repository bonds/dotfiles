final: prev: {
  ghostty = final.mkDarwinPackage rec {
    pname = "ghostty";
    version = "1.3.1";

    src = prev.fetchurl {
      url = "https://release.files.ghostty.org/${version}/Ghostty.dmg";
      hash = "sha256-GM/ysKbO6Q7q2cfTBk6AiiUqQLryFKp1LB7LeTuPX2k=";
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
      platforms = ["aarch64-darwin" "x86_64-darwin"];
    };
  };
}
