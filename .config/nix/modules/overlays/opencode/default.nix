final: prev: {
  opencode = final.mkDarwinPackage rec {
    pname = "opencode";
    version = "1.18.5";

    src = prev.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-darwin-arm64.zip";
      hash = "sha256-hfb57s4XTTvwySWICGplKEOIuJElbI9BAtwxfUdv/KY=";
    };

    nativeBuildInputs = [prev.unzip];

    installPhase = ''
      mkdir -p $out/bin
      install -m 755 opencode $out/bin/opencode
    '';

    meta = {
      description = "AI coding agent built for the terminal";
      homepage = "https://github.com/anomalyco/opencode";
      platforms = ["aarch64-darwin"];
    };
  };

  opencode-desktop = final.mkDarwinPackage rec {
    pname = "opencode-desktop";
    version = "1.18.5";

    src = prev.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v${version}/opencode-desktop-mac-arm64.zip";
      hash = "sha256-LFjhC+o+p9yUl0ExWM9m/80W42CP0iU60ezEMB/139M=";
    };

    nativeBuildInputs = [prev.unzip];

    installPhase = ''
      mkdir -p $out/Applications $out/bin
      cp -r OpenCode.app $out/Applications/
      rm -f $out/Applications/OpenCode.app/Contents/Resources/app-update.yml
      ln -s $out/Applications/OpenCode.app/Contents/MacOS/OpenCode $out/bin/opencode-desktop
    '';

    meta = {
      description = "OpenCode Desktop App (auto-updater disabled)";
      homepage = "https://github.com/anomalyco/opencode";
      platforms = ["aarch64-darwin"];
    };
  };
}
