final: prev: {
  osxphotos = final.mkDarwinPackage {
    pname = "osxphotos";
    version = "0.76.1";

    src = prev.fetchurl {
      url = "https://github.com/RhetTbull/osxphotos/releases/download/v0.76.1/osxphotos_MacOS_exe_darwin_arm64_v0.76.1.zip";
      hash = "sha256-SDYhKc37BLzlsLuuDiWl6wcSDW996YEtv9ZqILG6YJc=";
    };

    nativeBuildInputs = [prev.unzip];

    installPhase = ''
      mkdir -p $out/lib
      cp osxphotos $out/lib/osxphotos
      chmod +x $out/lib/osxphotos

      mkdir -p $out/bin
      cat > $out/bin/osxphotos <<'WRAPPER'
      ${builtins.readFile ./wrapper.sh}WRAPPER
      substituteInPlace $out/bin/osxphotos --replace-fail "@out@" "$out"
      chmod +x $out/bin/osxphotos
    '';

    meta = {
      description = "Export photos from Apple's macOS Photos app";
      homepage = "https://github.com/RhetTbull/osxphotos";
      platforms = ["aarch64-darwin"];
    };
  };
}
