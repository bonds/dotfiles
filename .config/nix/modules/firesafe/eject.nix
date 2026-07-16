{
  pkgs,
  cfg,
}:
pkgs.writeShellScriptBin "firesafe-eject" ''
  set -uo pipefail

  MOUNT_POINT="${cfg.mountPoint}"

  echo "=== Firesafe Eject ==="
  echo

  if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "$MOUNT_POINT is not mounted."
    echo "Drive is safe to unplug."
    exit 0
  fi

  # 1. Kill all backup and rsync processes
  PIDS=$(pgrep -f "firesafe-backup|rsync.*$MOUNT_POINT" 2>/dev/null || true)
  if [ -n "$PIDS" ]; then
    echo "Stopping backup processes..."
    echo "$PIDS" | doas xargs kill 2>/dev/null || true
    sleep 2
    # Force kill any remaining
    echo "$PIDS" | doas xargs kill -9 2>/dev/null || true
  fi

  # 2. Flush filesystem writes
  echo "Syncing filesystem..."
  sync

  # 3. Unmount
  echo "Unmounting..."
  if doas umount "$MOUNT_POINT"; then
    echo "Drive unmounted — safe to unplug."
  else
    # Try lazy unmount if regular unmount fails
    echo "Trying lazy unmount..."
    doas umount -l "$MOUNT_POINT" 2>/dev/null && echo "Drive unmounted (lazy) — safe to unplug." || echo "Failed to unmount."
  fi
''
