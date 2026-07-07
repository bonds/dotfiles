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

    installPhase = let
      versionStr = finalAttrs.version;
    in ''
      # CLI binary (keeps `osxphotos` in PATH)
      mkdir -p $out/bin
      cp osxphotos $out/bin/
      chmod +x $out/bin/osxphotos

      # .app bundle for stable TCC identity
      app=$out/Applications/OSXPhotos.app
      mkdir -p "$app/Contents/MacOS"
      cp osxphotos "$app/Contents/MacOS/osxphotos"
      chmod +x "$app/Contents/MacOS/osxphotos"
      cat > "$app/Contents/Info.plist" <<EOF
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleExecutable</key>
        <string>osxphotos</string>
        <key>CFBundleIdentifier</key>
        <string>com.rhettbull.osxphotos</string>
        <key>CFBundleName</key>
        <string>OSXPhotos</string>
        <key>CFBundleVersion</key>
        <string>${versionStr}</string>
        <key>CFBundleShortVersionString</key>
        <string>${versionStr}</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>LSMinimumSystemVersion</key>
        <string>11.0</string>
        <key>LSUIElement</key>
        <true/>
      </dict>
      </plist>
      EOF
      printf 'APPL????' > "$app/Contents/PkgInfo"
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
