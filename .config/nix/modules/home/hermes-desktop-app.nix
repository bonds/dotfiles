{
  pkgs,
  lib,
  inputs,
  ...
}: let
  inherit (pkgs) stdenvNoCC;
  electronPkg = pkgs.symlinkJoin {
    name = "electron-hermes";
    paths = [pkgs.electron];
    buildInputs = [pkgs.electron];
    postBuild = ''
      # Make a writable copy of Electron.app with the executable renamed
      # so macOS shows "Hermes" in the menu bar instead of "Electron".
      mkdir -p "$out/Applications/Hermes.app/Contents/MacOS"
      cp "${pkgs.electron}/Applications/Electron.app/Contents/Info.plist" "$out/Applications/Hermes.app/Contents/Info.plist"
      cp "${pkgs.electron}/Applications/Electron.app/Contents/PkgInfo" "$out/Applications/Hermes.app/Contents/PkgInfo" 2>/dev/null || true
      cp -r "${pkgs.electron}/Applications/Electron.app/Contents/Frameworks" "$out/Applications/Hermes.app/Contents/Frameworks"
      cp -r "${pkgs.electron}/Applications/Electron.app/Contents/Resources" "$out/Applications/Hermes.app/Contents/Resources"
      # Rename the executable to match the app name
      cp "${pkgs.electron}/Applications/Electron.app/Contents/MacOS/Electron" \
        "$out/Applications/Hermes.app/Contents/MacOS/Hermes"
    '';
  };
  # Custom icon, baked straight into the bundle (replacing the apple-touch-icon
  # .icns the old systemPackages copy generated) so the .app is self-contained
  # when Home Manager copies it to ~/Applications/Home Manager Apps. The bundle
  # is an unsigned Electron skeleton that Gatekeeper already rejects, so
  # rewriting Contents costs nothing — unlike osaurus, whose notarized signature
  # a baked icon would invalidate (see macos-apps.nix).
  hermesIcon = ../overlays/hermes-icon.icns;
  # TODO(anyio-overlay): the desktop embeds hermesAgent's wrapped runtime; pass
  # the anyio-overlaid build (same binding as hosts/accismus/configuration.nix)
  # so this .app's closure doesn't rebuild anyio 4.14.2's failing test suite.
  hermesUnstablePkgs = import inputs.nixpkgs-unstable.outPath {
    system = pkgs.stdenv.hostPlatform.system;
    overlays = [(import ../overlays/anyio/default.nix)];
  };
  hermesOverlaid = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    callPackage = hermesUnstablePkgs.callPackage;
    python312 = hermesUnstablePkgs.python312;
  };
  hermesDesktopApp = stdenvNoCC.mkDerivation rec {
    pname = "hermes-desktop-app";
    version = "0.17.0";
    phases = ["installPhase"];
    # BUG-001 workaround (upstream #61443) — see ../packages/hermes-desktop-fixed.nix
    hermesDesktop = import ../packages/hermes-desktop-fixed.nix {
      inherit pkgs inputs;
      hermesAgent = hermesOverlaid;
    };
    inherit electronPkg hermesIcon;
    installPhase = ''
      # Copy the renamed Electron.app structure
      mkdir -p "$out/Applications"
      cp -r "${electronPkg}/Applications/Hermes.app" "$out/Applications/Hermes.app"
      # Make the bundle writable (nix store files are read-only)
      chmod -R u+w "$out/Applications/Hermes.app"

      # Override Info.plist with our own
      cat > "$out/Applications/Hermes.app/Contents/Info.plist" <<'PLIST'
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
        <key>CFBundleDisplayName</key><string>Hermes</string>
        <key>CFBundleExecutable</key><string>Hermes</string>
        <key>CFBundleIdentifier</key><string>com.nousresearch.hermes-desktop</string>
        <key>CFBundleName</key><string>Hermes</string>
        <key>CFBundleIconFile</key><string>hermes.icns</string>
        <key>CFBundleShortVersionString</key><string>${version}</string>
        <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>LSBackgroundOnly</key><false/>
        <key>NSHighResolutionCapable</key><true/>
      </dict>
      </plist>
      PLIST

      cp "${hermesIcon}" "$out/Applications/Hermes.app/Contents/Resources/hermes.icns"

      # Remove Electron's default icon to avoid conflicts
      rm -f "$out/Applications/Hermes.app/Contents/Resources/electron.icns"

      # Copy (not symlink) the app resources into the .app bundle. A symlink
      # pointing outside a signed bundle is an "invalid destination for
      # symbolic link in bundle" and makes codesign --verify --strict fail, so
      # the bundle could never carry a coherent seal. Copies are what Home
      # Manager's copyApps would materialise anyway.
      mkdir -p "$out/Applications/Hermes.app/Contents/Resources/app"
      cp -R "${hermesDesktop}/share/hermes-desktop/dist" \
        "$out/Applications/Hermes.app/Contents/Resources/app/dist"
      cp "${hermesDesktop}/share/hermes-desktop/package.json" \
        "$out/Applications/Hermes.app/Contents/Resources/app/package.json"

      # Re-sign ad-hoc. Electron's own skeleton signature is invalidated by the
      # Info.plist/icon rewrites above, which makes macOS report the bundle as
      # "damaged". The bundle is unsigned upstream (Gatekeeper already rejects
      # it), so an ad-hoc signature costs nothing and leaves a coherent seal.
      /usr/bin/codesign --force --deep --sign - "$out/Applications/Hermes.app"
    '';
    meta = {
      description = "Hermes Desktop - Electron desktop app for Hermes Agent";
      platforms = ["aarch64-darwin"];
      license = lib.licenses.mit;
    };
  };
in {
  # Hermes Desktop .app wrapper for Spotlight/LaunchServices. home.packages so
  # Home Manager stages it to ~/Applications/Home Manager Apps rather than the
  # nix-darwin stager's /Applications/Nix Apps (AGENTS.md §B). The Hermes
  # *agent* service (programs/services.hermes-agent) is untouched.
  home.packages = [hermesDesktopApp];
}
