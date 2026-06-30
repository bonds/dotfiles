final: prev: {
  opencode = prev.stdenvNoCC.mkDerivation {
    pname = "opencode";
    version = "1.17.11";

    src = prev.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v1.17.11/opencode-darwin-arm64.zip";
      hash = "sha256-QHI0RgE96oJS7qTxgNcH916AWvVO6FoU/XwSZRO6g0I=";
    };

    sourceRoot = ".";

    nativeBuildInputs = [prev.unzip];

    installPhase = ''
      mkdir -p $out/bin
      install -m 755 opencode $out/bin/opencode
    '';

    dontFixup = true;

    meta = {
      description = "AI coding agent built for the terminal";
      homepage = "https://github.com/anomalyco/opencode";
      license = prev.lib.licenses.mit;
      platforms = ["aarch64-darwin"];
      mainProgram = "opencode";
    };
  };
}
