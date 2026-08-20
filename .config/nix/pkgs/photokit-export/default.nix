{
  lib,
  mkDarwinPackage,
}: let
  version = "0.2.1";
  bundleId = "com.ggr.photo-export";
in
  mkDarwinPackage rec {
    pname = "photo-export";
    inherit version;

    src = ./.;

    # Build the Swift CLI against the system SDK (Photos.framework is not
    # in nixpkgs). stdenvNoCC from mkDarwinPackage means no strip/fixup,
    # preserving the code signature we apply below.
    nativeBuildInputs = [];

    installPhase = ''
      runHook preInstall

      # Use Xcode's toolchain swiftc directly (xcrun wraps with sandbox-exec
      # which fails in the nix sandbox). Must pass -resource-dir so the
      # stdlib is found, and -sdk for the SDK. Photos.framework ships in
      # the system SDK (not nixpkgs), so we must compile against it.
      mkdir -p $out/libexec/app/Contents/MacOS
      mkdir -p $out/bin

      TOOLCHAIN="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain"
      SWIFTC="$TOOLCHAIN/usr/bin/swiftc"
      RESDIR="$TOOLCHAIN/usr/lib/swift"
      SDKROOT="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
      MODCACHE="$out/libexec/.swiftmodule-cache"
      mkdir -p "$MODCACHE"

      # If MacOSX.sdk doesn't resolve, ask xcrun (rare)
      [ -d "$SDKROOT" ] || SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>/dev/null)"

      "$SWIFTC" -module-cache-path "$MODCACHE" \
        -sdk "$SDKROOT" -resource-dir "$RESDIR" \
        -o "$out/libexec/app/Contents/MacOS/photo-export" \
        "$src/photo-export.swift"

      # Bundle Info.plist — REQUIRED for PhotoKit authorization prompt
      cat > "$out/libexec/app/Contents/Info.plist" <<'PLIST'
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleDisplayName</key><string>photo-export</string>
        <key>CFBundleExecutable</key><string>photo-export</string>
        <key>CFBundleIdentifier</key><string>${bundleId}</string>
        <key>CFBundleName</key><string>photo-export</string>
        <key>CFBundleShortVersionString</key><string>${version}</string>
        <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>LSBackgroundOnly</key><false/>
        <key>NSPhotoLibraryUsageDescription</key>
        <string>Export selected photos from your Photos library to the backup destination.</string>
        <key>NSPhotoLibraryAddUsageDescription</key>
        <string>Access the photo library to copy original photo files during backup.</string>
      </dict>
      </plist>
      PLIST

      # Ad-hoc sign the app bundle with a STABLE identifier so the PhotoKit
      # TCC grant survives nix store-path changes (keys to the identifier,
      # not the path). codesign isn't in the nix PATH; use the system path.
      /usr/bin/codesign -s - -f --identifier "${bundleId}" \
        "$out/libexec/app"

      # Also expose the app at a stable-ish path for LaunchServices/open
      mkdir -p "$out/Applications"
      ln -sfn "$out/libexec/app" "$out/Applications/photo-export.app"

      # CLI wrapper (tracked file, matches osxphotos overlay pattern)
      mkdir -p $out/bin
      cat > $out/bin/photo-export <<'WRAPPER'
      ${builtins.readFile ./wrapper.sh}
      WRAPPER
      substituteInPlace $out/bin/photo-export --replace-fail "@out@" "$out"
      chmod +x $out/bin/photo-export

      runHook postInstall
    '';

    # Fixup/strip would invalidate the ad-hoc signature; mkDarwinPackage
    # already sets these, but be explicit.
    dontFixup = true;
    dontStrip = true;

    meta = {
      description = "PhotoKit-native iCloud photo export (replaces osxphotos --download-missing AppleScript path)";
      homepage = "https://github.com/bonds/dotfiles";
      platforms = ["aarch64-darwin"];
      license = lib.licenses.mit;
      mainProgram = "photo-export";
    };
  }
