final: prev: {
  osaurus = final.mkDarwinPackage rec {
    pname = "osaurus";
    version = "0.22.7";

    src = prev.fetchurl {
      url = "https://github.com/osaurus-ai/osaurus/releases/download/${version}/Osaurus-${version}.dmg";
      hash = "sha256-VPKzd4c8P0hM9clLkhjhb6F7AFiMyShIjze/9OqcUu4=";
    };

    nativeBuildInputs = [prev._7zz];

    unpackPhase = ''
      7zz -snld x "$src"
    '';

    installPhase = ''
      mkdir -p $out/Applications
      app=$(find . -name "*.app" -type d | head -1)
      if [ -z "$app" ]; then
        echo "ERROR: .app bundle not found in DMG contents"
        ls -la
        exit 1
      fi
      mv "$app" "$out/Applications/"
    '';

    meta = {
      description = "Own your AI — native macOS AI agent harness";
      homepage = "https://osaurus.ai";
      license = prev.lib.licenses.mit;
      platforms = ["aarch64-darwin"];
    };
  };
}
