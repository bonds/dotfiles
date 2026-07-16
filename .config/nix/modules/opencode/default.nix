final: prev: {
  opencode = final.mkDarwinPackage {
    pname = "opencode";
    version = "1.17.20";

    src = prev.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v1.17.20/opencode-darwin-arm64.zip";
      hash = "sha256-m7nOMVv2XG41Zzb9oyq9fnDIDrH9CtgfWTOY7dadHVI=";
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

  opencode-desktop = final.mkDarwinPackage {
    pname = "opencode-desktop";
    version = "1.17.20";

    src = prev.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v1.17.20/opencode-desktop-mac-arm64.zip";
      hash = "sha256-7BckTK9TvDuSwKF1hwfSMlPesNgR6+reQJ2cd41TIpw=";
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
