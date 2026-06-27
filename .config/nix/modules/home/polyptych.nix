{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  home.activation.registerPolyptych = config.lib.dag.entryAfter ["writeBoundary"] ''
    STORE="${inputs.polyptych.packages.${pkgs.system}.default}"
    APP="$STORE/Applications/polyptych.app"

    # Register with Launch Services so Finder knows about polyptych.app
    if [ -d "$APP" ]; then
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
    fi

    # Set as default handler for video file types
    for ext in mp4 m4v mov mkv avi mpg mpeg webm wmv flv 3gp ts mts; do
      "${pkgs.duti}/bin/duti" -s com.bonds.polyptych ".$ext" all 2>/dev/null || true
    done

    # Restart the watcher LaunchAgent so it picks up the new binary
    NEW_PLIST="$STORE/lib/LaunchAgents/com.polyptych.watcher.plist"
    if [ -f "$NEW_PLIST" ]; then
      mkdir -p "$HOME/Library/LaunchAgents"
      cp "$NEW_PLIST" "$HOME/Library/LaunchAgents/com.polyptych.watcher.plist"
      launchctl bootout "gui/$(id -u)/com.polyptych.watcher" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.polyptych.watcher.plist" 2>/dev/null || true
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
