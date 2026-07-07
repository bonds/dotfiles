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

  opencode-desktop = prev.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "opencode-desktop";
    version = "1.17.14";

    src = prev.fetchurl {
      url = "https://github.com/anomalyco/opencode/releases/download/v${finalAttrs.version}/opencode-desktop-mac-arm64.zip";
      hash = "sha256-W/rT5g5wCoyE1DmGNFQJO1eCoTLPgeNq4o1SWz53dvg=";
    };

    sourceRoot = ".";

    nativeBuildInputs = [prev.unzip];

    installPhase = ''
      mkdir -p $out/Applications $out/bin
      cp -r OpenCode.app $out/Applications/
      # Strip the built-in Electron auto-updater config so the app never
      # checks for or notifies about updates (nr --update is the only path).
      rm -f $out/Applications/OpenCode.app/Contents/Resources/app-update.yml
      ln -s $out/Applications/OpenCode.app/Contents/MacOS/OpenCode $out/bin/opencode-desktop
    '';

    dontFixup = true;

    meta = {
      description = "OpenCode Desktop App (auto-updater disabled)";
      homepage = "https://github.com/anomalyco/opencode";
      license = prev.lib.licenses.mit;
      platforms = ["aarch64-darwin"];
      mainProgram = "opencode-desktop";
    };
  });
}
