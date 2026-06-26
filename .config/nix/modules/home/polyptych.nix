{
  config,
  lib,
  pkgs,
  ...
}: {
  home.activation.registerPolyptych = config.lib.dag.entryAfter ["writeBoundary"] ''
    # Find the .app bundle via Launch Services (works even during system switch)
    APP=$(/usr/bin/mdfind "kMDItemCFBundleIdentifier == 'com.bonds.polyptych'" | head -1)
    [ -z "$APP" ] || [ ! -d "$APP" ] && exit 0

    # Register with Launch Services so Finder knows about polyptych.app
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
    # Set as default handler for video file types
    for ext in mp4 m4v mov mkv avi mpg mpeg webm wmv flv 3gp ts mts; do
      "${pkgs.duti}/bin/duti" -s com.bonds.polyptych ".$ext" all 2>/dev/null || true
    done

    # Restart the watcher LaunchAgent so it picks up the new binary
    NEW_PLIST="$APP/../../lib/LaunchAgents/com.polyptych.watcher.plist"
    if [ -f "$NEW_PLIST" ]; then
      mkdir -p "$HOME/Library/LaunchAgents"
      cp "$NEW_PLIST" "$HOME/Library/LaunchAgents/com.polyptych.watcher.plist"
      launchctl bootout "gui/$(id -u)/com.polyptych.watcher" 2>/dev/null || true
      launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.polyptych.watcher.plist" 2>/dev/null || true
    fi

    # Update native messaging host symlink for Firefox/Zen Browser
    NM_LINK="$HOME/Library/Application Support/Mozilla/NativeMessagingHosts/com.polyptych.youtube.json"
    NM_SRC="$APP/../../lib/mozilla/native-messaging-hosts/com.polyptych.youtube.json"
    if [ -f "$NM_SRC" ]; then
      mkdir -p "$(dirname "$NM_LINK")"
      ln -sf "$NM_SRC" "$NM_LINK"
    fi
  '';
}
