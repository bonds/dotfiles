final: prev: {
  osxphotos = prev.stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "osxphotos";
    version = "0.76.1";

    src = prev.fetchurl {
      url = "https://github.com/RhetTbull/osxphotos/releases/download/v${finalAttrs.version}/osxphotos_MacOS_exe_darwin_arm64_v${finalAttrs.version}.zip";
      hash = "sha256-SDYhKc37BLzlsLuuDiWl6wcSDW996YEtv9ZqILG6YJc=";
    };

    nativeBuildInputs = [prev.unzip];

    sourceRoot = ".";

    installPhase = ''
      mkdir -p $out/bin
      cp osxphotos $out/bin/
      chmod +x $out/bin/osxphotos
    '';

    dontStrip = true;

    meta = {
      description = "Export photos from Apple's macOS Photos app";
      homepage = "https://github.com/RhetTbull/osxphotos";
      license = prev.lib.licenses.mit;
      platforms = ["aarch64-darwin"];
      mainProgram = "osxphotos";
    };
  });
}
