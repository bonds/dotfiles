{
  config,
  lib,
  pkgs,
  ...
}: {
  home.activation.registerPolyptych = config.lib.dag.entryAfter ["writeBoundary"] ''
    # Read store path from the nix profile symlink (always points to current build)
    TARGET=$(readlink /run/current-system/sw/bin/polyptych 2>/dev/null || true)
    [ -z "$TARGET" ] && exit 0
    STORE=$(dirname "$TARGET")
    STORE=$(dirname "$STORE")
    [ ! -d "$STORE/Applications/polyptych.app" ] && exit 0

    # Register with Launch Services so Finder knows about polyptych.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$STORE/Applications/polyptych.app" 2>/dev/null || true

    # Set as default handler for video file types
    for ext in mp4 m4v mov mkv avi mpg mpeg webm wmv flv 3gp ts mts; do
      "${pkgs.duti}/bin/duti" -s com.bonds.polyptych ".$ext" all 2>/dev/null || true
    done

    # Restart the watcher LaunchAgent — copy plist FIRST, then bootout
    # (KeepAlive restarts with the already-updated plist → new binary)
    NEW_PLIST="$STORE/lib/LaunchAgents/com.polyptych.watcher.plist"
    if [ -f "$NEW_PLIST" ]; then
      mkdir -p "$HOME/Library/LaunchAgents"
      cp "$NEW_PLIST" "$HOME/Library/LaunchAgents/com.polyptych.watcher.plist"
      launchctl bootout "gui/$(id -u)/com.polyptych.watcher" 2>/dev/null || true
    fi

    # Update native messaging host symlink for Firefox/Zen Browser
    NM_SRC="$STORE/lib/mozilla/native-messaging-hosts/com.polyptych.youtube.json"
    if [ -f "$NM_SRC" ]; then
      NM_DIR="$HOME/Library/Application Support/Mozilla/NativeMessagingHosts"
      mkdir -p "$NM_DIR"
      ln -sf "$NM_SRC" "$NM_DIR/com.polyptych.youtube.json"
    fi
  '';
}
