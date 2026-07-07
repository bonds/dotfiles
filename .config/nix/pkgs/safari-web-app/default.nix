{
  stdenvNoCC,
  lib,
}: {
  name,
  url,
  icon ? null,
}: let
  webAppRuntime = "/System/Volumes/Preboot/Cryptexes/App/System/Library/CoreServices/Web App.app/Contents/MacOS/Web App";
  sanitizedName = lib.replaceStrings ["/"] [""] name;

  # Deterministic UUID from URL: sha256 → uppercase → UUID format
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

          # Wrapper script — unquoted heredoc allows build-time expansion of webAppRuntime
          cat > "$APPDIR/Contents/MacOS/${sanitizedName}" << WRAPPER
      #!/bin/bash
      MYDIR="\$(cd "\$(dirname "\$0")"/../.. && pwd -P)"
      BUNDLEID="\$(defaults read "\$MYDIR/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)"
      exec '${webAppRuntime}' --bundlepath "\$MYDIR" --bundleidentifier "\$BUNDLEID"
      WRAPPER
          chmod +x "$APPDIR/Contents/MacOS/${sanitizedName}"

          # Build Info.plist
          P="$APPDIR/Contents/Info.plist"
          PB="/usr/libexec/PlistBuddy"

          plutil -create xml1 "$P"

          plutil -insert CFBundleExecutable -string "${sanitizedName}" "$P"
          plutil -insert CFBundleIdentifier -string "com.apple.Safari.WebApp.${uuid}" "$P"
          plutil -insert CFBundleName -string "${name}" "$P"
          plutil -insert CFBundleDisplayName -string "${name}" "$P"
          plutil -insert CFBundlePackageType -string "APPL" "$P"
          plutil -insert CFBundleInfoDictionaryVersion -string "6.0" "$P"
          plutil -insert CFBundleShortVersionString -string "1.0" "$P"
          plutil -insert CFBundleVersion -string "1" "$P"
          plutil -insert LSMinimumSystemVersion -string "14.0" "$P"
          plutil -insert CFBundleSupportedPlatforms -json '["MacOSX"]' "$P"

          # Manifest — PWA metadata consumed by Web App.app
          "$PB" -c "Add :Manifest dict" "$P"
          "$PB" -c "Add :Manifest:display string standalone" "$P"
          "$PB" -c "Add :Manifest:name string ${name}" "$P"
          "$PB" -c "Add :Manifest:short_name string ${name}" "$P"
          "$PB" -c "Add :Manifest:start_url string ${url}" "$P"
          "$PB" -c "Add :Manifest:scope string /" "$P"

          # Optional icon
          ${lib.optionalString (icon != null) ''
        ICON_DST="$APPDIR/Contents/Resources/ApplicationIcon.icns"
        case "$(file -b --mime-type ${builtins.toString icon})" in
          image/png)
            sips -s format icns ${builtins.toString icon} --out "$ICON_DST" >/dev/null 2>&1
            echo "Converted icon to icns"
            ;;
          image/x-icns)
            cp ${builtins.toString icon} "$ICON_DST"
            echo "Copied icns icon"
            ;;
          *)
            echo "Warning: Unsupported icon format for ${name}. Expected PNG or ICNS." >&2
            rm -f "$ICON_DST"
            ;;
        esac
        if [ -f "$ICON_DST" ]; then
          plutil -insert CFBundleIconFile -string "ApplicationIcon" "$P"
        fi
      ''}

          # Ad-hoc sign
          codesign -f -s - "$APPDIR" 2>&1

          mkdir -p "$out/bin"
    '';

    dontFixup = true;

    meta = with lib; {
      description = "Safari web app wrapper for ${name}";
      homepage = url;
      platforms = platforms.darwin;
    };
  }
