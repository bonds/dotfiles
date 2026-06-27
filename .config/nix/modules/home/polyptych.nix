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
    LOG() { echo "[polyptych] $*" >&2; }

    # Register with Launch Services so Finder knows about polyptych.app
    if [ -d "$APP" ]; then
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>&1 || LOG "lsregister failed (exit $?)"
    fi

    # Set as default handler for video file types
    for ext in mp4 m4v mov mkv avi mpg mpeg webm wmv flv 3gp ts mts; do
      "${pkgs.duti}/bin/duti" -s com.bonds.polyptych ".$ext" all 2>&1 || LOG "duti .$ext failed (exit $?)"
    done

    # Start the watcher directly (launchctl bootstrap is broken on this macOS version)
    WATCHER_BIN="$STORE/bin/polyptych-yt-watcher"
    if [ -f "$WATCHER_BIN" ]; then
      # Kill previous watcher if any
      if [ -f /tmp/polyptych-watcher.pid ]; then
        kill "$(cat /tmp/polyptych-watcher.pid)" 2>/dev/null || true
      fi
      nohup "$WATCHER_BIN" >/dev/null 2>&1 &
      echo $! > /tmp/polyptych-watcher.pid
    fi

    # Update native messaging host symlink for Firefox/Zen Browser
    NM_SRC="$STORE/lib/mozilla/native-messaging-hosts/com.polyptych.youtube.json"
    if [ -f "$NM_SRC" ]; then
      NM_DIR="$HOME/Library/Application Support/Mozilla/NativeMessagingHosts"
      mkdir -p "$NM_DIR"
      ln -sf "$NM_SRC" "$NM_DIR/com.polyptych.youtube.json" 2>&1 || LOG "NM symlink failed (exit $?)"
    fi
  '';
}
