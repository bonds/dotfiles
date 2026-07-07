{
  stdenvNoCC,
  lib,
  name,
  url,
  icon ? null,
}: let
  webAppRuntime = "/System/Volumes/Preboot/Cryptexes/App/System/Library/CoreServices/Web App.app/Contents/MacOS/Web App";
  sanitizedName = lib.replaceStrings ["/"] [""] name;

  hash = builtins.hashString "sha256" url;
  hexPart = builtins.substring 0 32 hash;
  uuid = lib.toUpper (
    builtins.substring 0 8 hexPart
    + "-"
    + builtins.substring 8 4 hexPart
    + "-"
    + builtins.substring 12 4 hexPart
    + "-"
    + builtins.substring 16 4 hexPart
    + "-"
    + builtins.substring 20 12 hexPart
  );
in
  stdenvNoCC.mkDerivation {
    pname = "safari-web-app-${lib.toLower name}";
    version = "1.0";

    buildCommand = ''
          APPDIR="$out/Applications/${sanitizedName}.app"
          mkdir -p "$APPDIR/Contents/MacOS" "$APPDIR/Contents/Resources"

          # Wrapper script — unquoted heredoc, delimiter at column 0
          cat > "$APPDIR/Contents/MacOS/${sanitizedName}" << WRAPPER_HERE
      #!/bin/bash
      MYDIR="\$(cd "\$(dirname "\$0")"/../.. && pwd -P)"
      BUNDLEID="\$(defaults read "\$MYDIR/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)"
      exec '${webAppRuntime}' --bundlepath "\$MYDIR" --bundleidentifier "\$BUNDLEID"
      WRAPPER_HERE
          chmod +x "$APPDIR/Contents/MacOS/${sanitizedName}"

          # Info.plist as XML — delimiter at column 0
          cat > "$APPDIR/Contents/Info.plist" << PLIST_HERE
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleExecutable</key>
        <string>${sanitizedName}</string>
        <key>CFBundleIconFile</key>
        <string>ApplicationIcon</string>
        <key>CFBundleIdentifier</key>
        <string>com.apple.Safari.WebApp.${uuid}</string>
        <key>CFBundleInfoDictionaryVersion</key>
        <string>6.0</string>
        <key>CFBundleName</key>
        <string>${name}</string>
        <key>CFBundleDisplayName</key>
        <string>${name}</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleShortVersionString</key>
        <string>1.0</string>
        <key>CFBundleSupportedPlatforms</key>
        <array>
          <string>MacOSX</string>
        </array>
        <key>CFBundleVersion</key>
        <string>1</string>
        <key>LSMinimumSystemVersion</key>
        <string>14.0</string>
        <key>Manifest</key>
        <dict>
          <key>display</key>
          <string>standalone</string>
          <key>name</key>
          <string>${name}</string>
          <key>scope</key>
          <string>/</string>
          <key>short_name</key>
          <string>${name}</string>
          <key>start_url</key>
          <string>${url}</string>
        </dict>
      </dict>
      </plist>
      PLIST_HERE

          # Icon (pre-converted .icns file, optional)
          ${lib.optionalString (icon != null) ''
        cp ${builtins.toString icon} "$APPDIR/Contents/Resources/ApplicationIcon.icns"
      ''}

          # Ad-hoc sign — macOS tool, only works on darwin
          /usr/bin/codesign -f -s - "$APPDIR"

          mkdir -p "$out/bin"
    '';

    dontFixup = true;

    meta = with lib; {
      description = "Safari web app wrapper for ${name}";
      homepage = url;
      platforms = platforms.darwin;
    };
  }
