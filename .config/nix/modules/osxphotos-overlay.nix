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
            # real binary hidden away (not in PATH directly)
            mkdir -p $out/lib
            cp osxphotos $out/lib/osxphotos
            chmod +x $out/lib/osxphotos

            # wrapper in PATH — avoids TCC-triggering plist reads
            # by injecting --library for library-requiring commands
            # and replacing list with a direct path echo
            mkdir -p $out/bin
            cat > $out/bin/osxphotos <<'WRAPPER'
      ${builtins.readFile ./osxphotos-wrapper.sh}WRAPPER
            substituteInPlace $out/bin/osxphotos --replace-fail "@out@" "$out"
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
