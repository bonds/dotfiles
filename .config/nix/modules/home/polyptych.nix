{
  config,
  lib,
  pkgs,
  ...
}: {
  home.activation.registerPolyptych = config.lib.dag.entryAfter ["writeBoundary"] ''
    BIN=$(which polyptych 2>/dev/null || true)
    [ -z "$BIN" ] && exit 0
    APP=$(python3 -c "import os; p=os.path.realpath('$BIN'); print(os.path.dirname(os.path.dirname(os.path.dirname(p))))")
    [ ! -d "$APP" ] && exit 0
    # Register with Launch Services so Finder knows about polyptych.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
    # Set as default handler for video file types
    for ext in mp4 m4v mov mkv avi mpg mpeg webm wmv flv 3gp ts mts; do
      "${pkgs.duti}/bin/duti" -s com.bonds.polyptych ".$ext" all 2>/dev/null || true
    done

    # Restart the watcher LaunchAgent so it picks up the new binary
    launchctl bootout "gui/$(id -u)/com.polyptych.watcher" 2>/dev/null || true
    NEW_PLIST="$APP/../../lib/LaunchAgents/com.polyptych.watcher.plist"
    if [ -f "$NEW_PLIST" ]; then
      mkdir -p "$HOME/Library/LaunchAgents"
      cp "$NEW_PLIST" "$HOME/Library/LaunchAgents/com.polyptych.watcher.plist"
      launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.polyptych.watcher.plist" 2>/dev/null || true
    fi
  '';
}
