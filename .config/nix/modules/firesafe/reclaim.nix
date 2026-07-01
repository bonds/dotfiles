{
  pkgs,
  lib,
  cfg,
}:
pkgs.writeShellScriptBin "firesafe-reclaim" ''
  set -uo pipefail

  MOUNT_POINT="${cfg.mountPoint}"
  DRY_RUN=false

  for arg in "$@"; do
    case "$arg" in --dry-run) DRY_RUN=true;; esac
  done

  if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "ERROR: $MOUNT_POINT is not mounted."
    echo "Plug in the fire safe USB drive first."
    exit 1
  fi

  if [ ! -d "$MOUNT_POINT/.deleted" ]; then
    echo "No .deleted/ directory found. Nothing to reclaim."
    exit 0
  fi

  echo "=== Firesafe Reclaim ==="
  [ "$DRY_RUN" = true ] && echo "DRY RUN -- no files will be deleted"
  echo

  TOTAL=0
  for d in "$MOUNT_POINT/.deleted"/*/; do
    [ -d "$d" ] || continue
    DIR_NAME=$(basename "$d")
    DIR_SIZE=$(du -sb "$d" 2>/dev/null | cut -f1)
    echo "  $DIR_NAME: $((DIR_SIZE / 1024 / 1024 / 1024))GB"
    TOTAL=$((TOTAL + DIR_SIZE))
    if [ "$DRY_RUN" = false ]; then
      rm -rf "$d"
      echo "    -> Deleted"
    fi
  done

  echo
  echo "Total reclaimable: $((TOTAL / 1024 / 1024 / 1024))GB"
  [ "$DRY_RUN" = true ] && echo "Run without --dry-run to actually delete."
''
