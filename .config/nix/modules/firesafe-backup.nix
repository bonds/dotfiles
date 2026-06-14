{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.programs.firesafe-backup;

  mkRsyncCmds =
    lib.mapAttrsToList (name: path: ''
      log "--- ${name} ---"
      ${pkgs.rsync}/bin/rsync \
        --archive \
        --delete \
        --backup \
        --backup-dir="${cfg.mountPoint}/.deleted/$BACKUP_DATE" \
        --partial \
        --partial-dir=.rsync-partial \
        --info=progress2 \
        ${lib.concatStringsSep " " (map (p: "--exclude='${p}'") cfg.excludes)} \
        "${path}/" \
        "${cfg.mountPoint}/${name}/" \
        >> "$LOG_FILE" 2>&1
      RC=$?
      if [ $RC -eq 0 ] || [ $RC -eq 24 ]; then
        log "${name}: SUCCESS"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      else
        log "${name}: FAILED (exit code $RC)"
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        FAILURE_NAMES="$FAILURE_NAMES ${name}"
      fi
    '')
    cfg.sources;

  mkTotalSizeCmds =
    lib.mapAttrsToList (name: path: ''
      SIZE=$(${pkgs.coreutils}/bin/du -sb "${path}" 2>/dev/null | cut -f1)
      TOTAL_SIZE=$((TOTAL_SIZE + SIZE))
    '')
    cfg.sources;

  mkSourceChecks =
    lib.mapAttrsToList (name: path: ''
      if [ ! -d "${path}" ]; then
        log "ERROR: Source '${path}' does not exist or is not a directory"
        SOURCES_OK=false
      fi
    '')
    cfg.sources;

  backupScript = pkgs.writeShellScript "firesafe-backup" ''
      set -uo pipefail

      MOUNT_POINT="${cfg.mountPoint}"
      EMAIL="${cfg.emailRecipient}"
      LOG_FILE="/var/log/firesafe-backup.log"
      DRIVE_LABEL="${cfg.driveLabel}"
      THRESHOLD=$(((${toString cfg.spaceThreshold}) * 1024 * 1024 * 1024))
      FAILURE_COUNT=0
      SUCCESS_COUNT=0
      FAILURE_NAMES=""

      log() {
        echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
      }

      notify() {
        local status="$1"
        local summary
        summary=$(tail -30 "$LOG_FILE" 2>/dev/null || echo "No log available")
        local drive_human
        drive_human=$(df -h "$MOUNT_POINT" 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
        ${pkgs.msmtp}/bin/msmtp -t <<EOM || log "WARNING: failed to send email notification"
    To: $EMAIL
    Subject: [firesafe] Backup $status — Drive $DRIVE_ID
    Content-Type: text/plain; charset=UTF-8

    Firesafe backup report
    =======================
    Drive: $DRIVE_ID
    Status: $status
    Date: $(date)
    Free space on drive: $drive_human

    Summary: $SUCCESS_COUNT succeeded, $FAILURE_COUNT failed
    Failed: $FAILURE_NAMES

    Recent log output:
    $summary

    ---
    To check status: firesafe-status
    To reclaim space: firesafe-reclaim
    To eject safely: firesafe-eject
    EOM
      }

      abort() {
        local reason="$1"
        FAILURE_NAMES="$reason"
        FAILURE_COUNT=1
        log "ERROR: $reason"
        notify "failed"
        exit 1
      }

      cleanup() {
        local rc=$?
        log "Backup interrupted"
        date -Iseconds > "$MOUNT_POINT/.firesafe-backup-interrupted" 2>/dev/null || true
        umount "$MOUNT_POINT" 2>/dev/null || true
        exit $rc
      }
      trap cleanup TERM INT

      log "=== Firesafe Backup Starting ==="

      # 1. Ensure mount exists
      if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        log "Mount point $MOUNT_POINT not mounted, attempting to mount..."
        mkdir -p "$MOUNT_POINT"
        DEVICE=$(${pkgs.util-linux}/bin/findfs "LABEL=$DRIVE_LABEL" 2>/dev/null || true)
        if [ -z "$DEVICE" ] && [ -L "/dev/disk/by-label/$DRIVE_LABEL" ]; then
          DEVICE=$(readlink -f "/dev/disk/by-label/$DRIVE_LABEL")
        fi
        if [ -z "$DEVICE" ]; then
          abort "Cannot find drive with label '$DRIVE_LABEL'"
        fi
        log "Found device: $DEVICE"
        log "Checking filesystem..."
        ${pkgs.e2fsprogs}/bin/e2fsck -p "$DEVICE" || log "fsck exit code $? (continuing)"
        mount "$DEVICE" "$MOUNT_POINT" || abort "Failed to mount $DEVICE at $MOUNT_POINT"
        log "Mounted $DEVICE at $MOUNT_POINT"
      fi

      # 2. Read drive ID
      DRIVE_ID="unknown"
      if [ -f "$MOUNT_POINT/.firesafe-id" ]; then
        DRIVE_ID=$(cat "$MOUNT_POINT/.firesafe-id")
      fi
      log "Drive ID: $DRIVE_ID"

      # 3. Check previous backup state
      if [ -f "$MOUNT_POINT/.firesafe-backup-start" ] && [ ! -f "$MOUNT_POINT/.firesafe-backup-complete" ]; then
        PREV_START=$(cat "$MOUNT_POINT/.firesafe-backup-start")
        log "WARNING: Previous backup was interrupted (started: $PREV_START)"
      fi

      # 4. Write start marker
      date -Iseconds > "$MOUNT_POINT/.firesafe-backup-start"

      # 5. Pre-flight: sources exist
      log "--- Pre-flight checks ---"
      SOURCES_OK=true
      ${lib.concatStringsSep "\n" mkSourceChecks}
      if [ "$SOURCES_OK" = false ]; then
        abort "Some source directories missing"
      fi
      log "All source directories exist"

      # 6. Check free space, reclaim if needed
      FREE_BYTES=$(df --output=avail -B1 "$MOUNT_POINT" 2>/dev/null | tail -1)
      log "Free space: $((FREE_BYTES / 1024 / 1024 / 1024))GB"

      if [ "$FREE_BYTES" -lt "$THRESHOLD" ]; then
        log "Free space below threshold (${toString cfg.spaceThreshold}GB). Reclaiming space..."
        if [ -d "$MOUNT_POINT/.deleted" ]; then
          while [ "$FREE_BYTES" -lt "$THRESHOLD" ]; do
            OLDEST=$(ls -1 "$MOUNT_POINT/.deleted/" 2>/dev/null | sort | head -1)
            [ -z "$OLDEST" ] && break
            DIR_SIZE=$(du -sb "$MOUNT_POINT/.deleted/$OLDEST" 2>/dev/null | cut -f1 || echo 0)
            rm -rf "$MOUNT_POINT/.deleted/$OLDEST"
            FREE_BYTES=$((FREE_BYTES + DIR_SIZE))
            log "Reclaimed $((DIR_SIZE / 1024 / 1024 / 1024))GB by deleting '.deleted/$OLDEST'"
          done
        fi
        FREE_BYTES=$(df --output=avail -B1 "$MOUNT_POINT" 2>/dev/null | tail -1)
        if [ "$FREE_BYTES" -lt "$THRESHOLD" ]; then
          abort "Only $((FREE_BYTES / 1024 / 1024 / 1024))GB free after reclaim. Need ${toString cfg.spaceThreshold}GB."
        fi
      fi

      # 7. Compute total source size for ETA estimation (one-time per backup)
      log "--- Computing total source size ---"
      TOTAL_SIZE=0
      ${lib.concatStringsSep "\n" mkTotalSizeCmds}
      echo "$TOTAL_SIZE" > "$MOUNT_POINT/.firesafe-backup-total"
      ${pkgs.coreutils}/bin/df --output=used -B1 "$MOUNT_POINT" 2>/dev/null | tail -1 > "$MOUNT_POINT/.firesafe-df-start"
      log "Total source size: $((TOTAL_SIZE / 1024 / 1024 / 1024))GB"

      # 8. Run rsync for each source
      log "--- Running backups ---"
      BACKUP_DATE=$(date +%Y-%m-%d)
      ${lib.concatStringsSep "\n" mkRsyncCmds}

      # 9. Record deleted files in permanent changelog
      CHANGELOG="/dragon/logs/firesafe-backup-changelog.log"
      if [ -d "$MOUNT_POINT/.deleted/$BACKUP_DATE" ]; then
        touch "$CHANGELOG"
        ${pkgs.findutils}/bin/find "$MOUNT_POINT/.deleted/$BACKUP_DATE" -type f 2>/dev/null | while read -r f; do
          rel="''${f#$MOUNT_POINT/.deleted/$BACKUP_DATE/}"
          printf "%s\t%s\n" "$BACKUP_DATE" "$rel" >> "$CHANGELOG"
        done
        log "Recorded deleted files in '/dragon/logs/firesafe-backup-changelog.log'"
      fi

      # 10. Write completion marker
      if [ "$FAILURE_COUNT" -eq 0 ]; then
        date -Iseconds > "$MOUNT_POINT/.firesafe-backup-complete"
        log "=== Backup Complete ==="
        notify "completed"
      else
        log "=== Backup Partial ($FAILURE_COUNT failures) ==="
        notify "partial"
      fi
      log "Summary: $SUCCESS_COUNT succeeded, $FAILURE_COUNT failed"
      [ -n "$FAILURE_NAMES" ] && log "Failed: $FAILURE_NAMES"
      FREE_BYTES=$(df --output=avail -B1 "$MOUNT_POINT" 2>/dev/null | tail -1)
      log "Free space remaining: $((FREE_BYTES / 1024 / 1024 / 1024))GB"
  '';

  statusScript = pkgs.writeShellScriptBin "firesafe-status" ''
    set -uo pipefail

    WATCH=false
    for arg in "$@"; do
      case "$arg" in -w|--watch) WATCH=true;; esac
    done

    fmt_time() {
      local s=$1
      local h=$(( s / 3600 ))
      local m=$(( (s % 3600) / 60 ))
      [ "$h" -gt 0 ] && printf "%dh %dm" "$h" "$m" || printf "%dm" "$m"
    }

    show_status() {
      MOUNT_POINT="${cfg.mountPoint}"
      LOG_FILE="/var/log/firesafe-backup.log"

      echo "=== Firesafe Backup Status ==="
      if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo "Not mounted"
        return
      fi

      df -h "$MOUNT_POINT" | tail -1 | awk '{print "Status: MOUNTED | Size: "$2" | Avail: "$4}'
      [ -f "$MOUNT_POINT/.firesafe-id" ] && echo "Drive: $(cat $MOUNT_POINT/.firesafe-id)"
      echo

      if [ -f "$MOUNT_POINT/.firesafe-backup-complete" ]; then
        echo "Backup completed: $(cat $MOUNT_POINT/.firesafe-backup-complete)"
      elif [ -f "$MOUNT_POINT/.firesafe-backup-start" ]; then
        START_TIME=$(cat "$MOUNT_POINT/.firesafe-backup-start")
        NOW=$(date -Iseconds)
        ELAPSED=$(( $(date -d "$NOW" +%s) - $(date -d "$START_TIME" +%s) ))
        [ "$ELAPSED" -lt 0 ] && ELAPSED=0
        printf "Backup started: %s  |  Elapsed: %s\n" "$START_TIME" "$(fmt_time $ELAPSED)"

        TOTAL_BYTES=$(cat "$MOUNT_POINT/.firesafe-backup-total" 2>/dev/null || echo 0)
        if [ "$TOTAL_BYTES" -gt 0 ]; then
          DF_START=$(cat "$MOUNT_POINT/.firesafe-df-start" 2>/dev/null || echo 0)
          DF_NOW=$(df --output=used -B1 "$MOUNT_POINT" 2>/dev/null | tail -1)
          BYTES_SENT=$((DF_NOW - DF_START))
          [ "$BYTES_SENT" -lt 1 ] && BYTES_SENT=1
          SPEED=$(( BYTES_SENT / ELAPSED ))
          [ "$SPEED" -lt 1 ] && SPEED=1
          REMAINING_BYTES=$(( TOTAL_BYTES - BYTES_SENT ))
          [ "$REMAINING_BYTES" -lt 0 ] && REMAINING_BYTES=0
          REMAINING_SECS=$(( REMAINING_BYTES / SPEED ))
          echo "Remaining: ~$(fmt_time $REMAINING_SECS)"
        fi
      else
        echo "No backup markers found."
      fi
      echo

      echo "--- Deleted file backups ---"
      if [ -d "$MOUNT_POINT/.deleted" ]; then
        du -sh "$MOUNT_POINT/.deleted/" 2>/dev/null || echo "  (none)"
        echo "Oldest: $(ls -1 "$MOUNT_POINT/.deleted/" 2>/dev/null | sort | head -1)"
        echo "Newest: $(ls -1 "$MOUNT_POINT/.deleted/" 2>/dev/null | sort | tail -1)"
      else
        echo "  No .deleted/ directory found"
      fi

      echo
      echo "--- Last backup log (last 20 lines) ---"
      [ -f "$LOG_FILE" ] && tail -20 "$LOG_FILE" || echo "  No log file found"
    }

    if [ "$WATCH" = true ]; then
      while sleep 2; do clear && show_status; done
    else
      show_status
    fi
  '';

  reclaimScript = pkgs.writeShellScriptBin "firesafe-reclaim" ''
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
  '';

  deletedScript = pkgs.writeShellScriptBin "firesafe-deleted" ''
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
  '';

  ejectScript = pkgs.writeShellScriptBin "firesafe-eject" ''
    set -uo pipefail

    MOUNT_POINT="${cfg.mountPoint}"

    echo "=== Firesafe Eject ==="
    echo

    if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
      echo "$MOUNT_POINT is not mounted."
      echo "Drive is safe to unplug."
      exit 0
    fi

    # 1. Gracefully stop the backup
    if systemctl is-active --quiet firesafe-backup.service 2>/dev/null; then
      echo "Stopping backup..."
      sudo systemctl kill firesafe-backup.service 2>/dev/null || true
      sleep 2
    fi

    # 2. Flush filesystem writes
    echo "Syncing filesystem..."
    sync

    # 3. Unmount
    echo "Unmounting..."
    if sudo umount "$MOUNT_POINT"; then
      echo "Drive unmounted — safe to unplug."
    else
      echo "Failed to unmount. Check if something is using the drive:"
      echo "  lsof $MOUNT_POINT"
    fi
  '';
in {
  options.programs.firesafe-backup = {
    enable = lib.mkEnableOption "firesafe USB backup service";

    sources = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = {};
      example = {
        Archive = "/dragon/archive";
        Media = "/dragon/media";
      };
      description = "Attribute set mapping destination directory names to source paths.";
    };

    driveLabel = lib.mkOption {
      type = lib.types.str;
      default = "firesafe";
      description = "Filesystem label to identify the fire safe USB drive.";
    };

    mountPoint = lib.mkOption {
      type = lib.types.path;
      default = "/mnt/firesafe";
      description = "Mount point for the fire safe USB drive.";
    };

    spaceThreshold = lib.mkOption {
      type = lib.types.int;
      default = 50;
      description = "Minimum free space in GB required before rsync starts.";
    };

    emailRecipient = lib.mkOption {
      type = lib.types.str;
      default = "root";
      description = "Email address for backup notifications (uses msmtp).";
    };

    excludes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["@eaDir" ".DS_Store" "Thumbs.db" ".zfs" "@tmp"];
      description = "rsync exclude patterns.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.udev.extraRules = ''
      ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_LABEL}=="${cfg.driveLabel}", TAG+="systemd", ENV{SYSTEMD_WANTS}+="firesafe-backup.service"
    '';

    systemd.services.firesafe-backup = {
      description = "Firesafe USB backup";
      after = ["dev-disk-by\\x2dlabel-${cfg.driveLabel}.device"];
      wantedBy = [];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${backupScript}";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
        Environment = "PATH=${pkgs.coreutils}/bin:${pkgs.util-linux}/bin:${pkgs.gnused}/bin:${pkgs.gnugrep}/bin";
      };
    };

    environment.systemPackages = [statusScript reclaimScript deletedScript ejectScript];

    systemd.tmpfiles.rules = [
      "f /var/log/firesafe-backup.log 0640 root users -"
    ];
  };
}
