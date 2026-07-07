final: prev: {
  opencode = prev.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "opencode";
    version = "1.17.14";

    src = prev.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v${finalAttrs.version}/opencode-darwin-arm64.zip";
      hash = "sha256-7AGMCsi80Gad2/m/a78JABzt5/xGA4HbJ8JzJYivsJg=";
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
  });
}
