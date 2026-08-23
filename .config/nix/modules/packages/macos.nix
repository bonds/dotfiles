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
  hermesDesktopApp = stdenvNoCC.mkDerivation rec {
    pname = "hermes-desktop-app";
    version = "0.17.0";
    phases = ["installPhase"];
    hermesDesktop = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.desktop;
    iconPng = "${hermesDesktop}/share/hermes-desktop/dist/apple-touch-icon.png";
    inherit electronPkg;
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
        <key>CFBundleIconFile</key><string>icon</string>
        <key>CFBundleShortVersionString</key><string>${version}</string>
        <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
        <key>CFBundlePackageType</key><string>APPL</string>
        <key>LSBackgroundOnly</key><false/>
        <key>NSHighResolutionCapable</key><true/>
      </dict>
      </plist>
      PLIST

      # Generate .icns from apple-touch-icon.png using macOS built-in tools
      ICONSET="$TMPDIR/hermes.iconset"
      mkdir -p "$ICONSET"
      for size in 16 32 128 256 512; do
        /usr/bin/sips -z ''$size ''$size "${iconPng}" --out "$ICONSET/icon_''${size}x''${size}.png" > /dev/null
        /usr/bin/sips -z $((size*2)) $((size*2)) "${iconPng}" --out "$ICONSET/icon_''${size}x''${size}@2x.png" > /dev/null
      done
      /usr/bin/iconutil -c icns -o "$out/Applications/Hermes.app/Contents/Resources/icon.icns" "$ICONSET"

      # Remove Electron's default icon to avoid conflicts
      rm -f "$out/Applications/Hermes.app/Contents/Resources/electron.icns"

      # Symlink the app resources into the .app bundle
      mkdir -p "$out/Applications/Hermes.app/Contents/Resources/app"
      ln -sfn "${hermesDesktop}/share/hermes-desktop/dist" \
        "$out/Applications/Hermes.app/Contents/Resources/app/dist"
      ln -sfn "${hermesDesktop}/share/hermes-desktop/package.json" \
        "$out/Applications/Hermes.app/Contents/Resources/app/package.json"
    '';
    meta = {
      description = "Hermes Desktop - Electron desktop app for Hermes Agent";
      platforms = ["aarch64-darwin"];
      license = lib.licenses.mit;
    };
  };
in {
  environment.systemPackages = with pkgs; [
    age-plugin-yubikey # age encryption with YubiKey support
    angband # best cli game ever
    bun # javascript runtime
    caffeine # don't go to sleep
    clamav # antivirus
    cloc # count lines of code
    coconutbattery # battery health monitor
    colima # docker for mac
    coreutils # for timeout for athome script
    cowsay # cli to print stuff with a pic of a cow saying it
    daisydisk # disk usage visualizer
    delta # git delta syntax highlighter
    docker # docker
    duti # set default file handlers for macOS
    flux # blue light filter for sleep
    fortune # random quotes
    google-cloud-sdk # google cloud CLI and friends
    hugo # blog engine
    ice-bar # menu bar organizer
    idris2Packages.idris2Lsp # language service provider for idris2
    idris2Packages.pack # packages manager for idris2
    inputs.neocode.packages.${pkgs.stdenv.hostPlatform.system}.default # Native macOS SwiftUI client for OpenCode (community, flake, nr --update)
    inputs.polyptych.packages.${pkgs.stdenv.hostPlatform.system}.default # spanned fullscreen video player
    jujutsu # git alternative
    libreoffice-bin # office suite
    lima # vms for mac
    mpv # minimalist media player
    mtr # better traceroute
    nh # nix helper for rebuilds and garbage collection (darwin, no programs.nh module)
    nodejs # needed for hihello development
    opencode # AI coding agent (CLI, binary overlay, nr --update)
    opencode-desktop # OpenCode Electron desktop app (binary overlay, auto-updater disabled)
    osaurus # native macOS AI agent harness (binary overlay, nr --update)
    oxillama # pure Rust LLM inference engine (experimental, pkgs/oxillama/update.sh, nr --update)
    openssh # macos ssh doesn't come with resident ssh support
    passage # age-based password manager
    (pkgs.callPackage ../../pkgs/ghosttile {}) # hide apps from Dock/Cmd+Tab
    hermesDesktopApp # Hermes Desktop .app wrapper for Spotlight/LaunchServices
    (python3.withPackages (p:
      with p; [
        python-kasa # control TP-Link smart home devices
      ]))
    rage # encryption tool (age alternative)
    rustup # rust installer
    syncthing # peer-to-peer file synchronization
    tailscale # tailnet CLI
    the-powder-toy # physics simulation game
    typescript # javascript dialect
    utm # virtual machine manager for macOS
    whisper-cpp # cli tool for converting audio to text
    xclip # for copying from terminal to clipboard
    yt-dlp # download videos from YouTube and more
    zen-browser # firefox fork with vertical tabs
  ];
}
