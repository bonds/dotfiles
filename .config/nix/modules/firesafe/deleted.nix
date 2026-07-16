{
  pkgs,
  cfg,
}:
pkgs.writeShellScriptBin "firesafe-deleted" ''
  set -uo pipefail

  MOUNT_POINT="${cfg.mountPoint}"
  DELETED_DIR="$MOUNT_POINT/.deleted"

  echo "=== Firesafe Deleted Files ==="
  echo

  if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "ERROR: $MOUNT_POINT is not mounted."
    echo "Plug in the fire safe USB drive first."
    exit 1
  fi

  if [ ! -d "$DELETED_DIR" ] || [ -z "$(ls -A "$DELETED_DIR" 2>/dev/null)" ]; then
    echo "No deleted files found."
    exit 0
  fi

  fmt_size() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
      echo "$((bytes / 1073741824)).$(((bytes % 1073741824) / 107374182)) GB"
    elif [ "$bytes" -ge 1048576 ]; then
      echo "$((bytes / 1048576)).$(((bytes % 1048576) / 104857)) MB"
    elif [ "$bytes" -ge 1024 ]; then
      echo "$((bytes / 1024)).$(((bytes % 1024) / 102)) KB"
    else
      echo "$bytes B"
    fi
  }

  browse_date() {
    local date_dir="$1"
    echo "Contents of $(basename "$date_dir")/:"
    ${pkgs.findutils}/bin/find "$date_dir" -type f 2>/dev/null | while read -r f; do
      local size
      size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null)
      local rel
      rel="''${f#$DELETED_DIR/}"
      printf "  %s  %s\n" "$(fmt_size "$size")" "$rel"
    done
  }

  if [ $# -gt 0 ]; then
    target="$DELETED_DIR/$1"
    if [ -d "$target" ]; then
      browse_date "$target"
    else
      echo "Backup date '$1' not found in $DELETED_DIR"
      echo "Available dates:"
      for d in "$DELETED_DIR"/*/; do
        [ -d "$d" ] && echo "  $(basename "$d")"
      done
    fi
    exit 0
  fi

  TOTAL_DELETED=0
  for d in "$DELETED_DIR"/*/; do
    [ -d "$d" ] || continue
    DATE=$(basename "$d")
    DATE_SIZE=$(du -sb "$d" 2>/dev/null | cut -f1)
    TOTAL_DELETED=$((TOTAL_DELETED + DATE_SIZE))
    FILE_COUNT=$(${pkgs.findutils}/bin/find "$d" -type f 2>/dev/null | wc -l)
    printf "%s  (%s, %d files)\n" "$DATE" "$(fmt_size "$DATE_SIZE")" "$FILE_COUNT"
  done

  echo
  echo "Total: $(fmt_size "$TOTAL_DELETED") across $(${pkgs.findutils}/bin/find "$DELETED_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l) backup dates"
''
