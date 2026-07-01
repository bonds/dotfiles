{
  pkgs,
  lib,
  cfg,
}: let
  mkRsyncCmds =
    lib.mapAttrsToList (name: path: ''
      if echo "$SKIP_SOURCES" | grep -qw "${name}"; then
        log "Skipping ${name} (already completed)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
      else
        START_TS=$(date +%s)
        log "--- ${name} ---"
        ${pkgs.rsync}/bin/rsync \
          --archive \
          --delete \
          --backup \
          --backup-dir="${cfg.mountPoint}/.deleted/$BACKUP_DATE" \
          --partial \
          --partial-dir=.rsync-partial \
          --info=progress2 \
          --stats \
          ${lib.concatStringsSep " " (map (p: "--exclude='${p}'") cfg.excludes)} \
          "${path}/" \
          "${cfg.mountPoint}/${name}/" \
          >> "$LOG_FILE" 2>&1
        RC=$?
        END_TS=$(date +%s)
        ELAPSED=$(( END_TS - START_TS ))
        ELAPSED_STR=""
        if [ "$ELAPSED" -ge 3600 ]; then
          ELAPSED_STR="$((ELAPSED / 3600))h $(( (ELAPSED % 3600) / 60 ))m"
        elif [ "$ELAPSED" -ge 60 ]; then
          ELAPSED_STR="$((ELAPSED / 60))m $((ELAPSED % 60))s"
        else
          ELAPSED_STR="''${ELAPSED}s"
        fi
        if [ $RC -eq 0 ] || [ $RC -eq 24 ]; then
          log "${name}: SUCCESS (''${ELAPSED_STR})"
          SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
          echo "${name}" >> "$PROGRESS_FILE"
        else
          log "${name}: FAILED (exit code $RC, ''${ELAPSED_STR})"
          FAILURE_COUNT=$((FAILURE_COUNT + 1))
          FAILURE_NAMES="$FAILURE_NAMES ${name}"
        fi
      fi
    '')
    cfg.sources;

  mkScanCmds =
    lib.mapAttrsToList (name: path: ''
      log "Scanning: ${name}"
      STATS=$(${pkgs.rsync}/bin/rsync --dry-run --stats --quiet --archive \
        ${lib.concatStringsSep " " (map (p: "--exclude='${p}'") cfg.excludes)} \
        "${path}/" \
        "${cfg.mountPoint}/${name}/" 2>&1)
      TOTAL=$(echo "$STATS" | sed -n 's/Total file size: //p' | sed 's/ bytes//;s/,//g')
      TRANSFER=$(echo "$STATS" | sed -n 's/Total transferred file size: //p' | sed 's/ bytes//;s/,//g')
      FILES=$(echo "$STATS" | sed -n 's/Number of regular files transferred: //p' | sed 's/,//g')
      SCAN_TOTAL=$((SCAN_TOTAL + TOTAL))
      SCAN_TRANSFER=$((SCAN_TRANSFER + TRANSFER))
      SCAN_FILE_COUNT=$((SCAN_FILE_COUNT + FILES))
      printf "%s\t%s\t%s\t%s\n" "${name}" "$TOTAL" "$TRANSFER" "$FILES" >> "$SCAN_LOG"
      log "Scan: ${name} ($((TRANSFER / 1048576)) MB to transfer over $FILES files)"
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
in
  pkgs.writeShellScript "firesafe-backup" ''
    set -uo pipefail

    MOUNT_POINT="${cfg.mountPoint}"
    EMAIL="${cfg.emailRecipient}"
    LOG_FILE="/var/log/firesafe-backup.log"
    DRIVE_LABEL="${cfg.driveLabel}"
    THRESHOLD=$(((${toString cfg.spaceThreshold}) * 1024 * 1024 * 1024))
    FAILURE_COUNT=0
    SUCCESS_COUNT=0
    FAILURE_NAMES=""
    PROGRESS_FILE="$MOUNT_POINT/.firesafe-progress"
    SKIP_SOURCES=""

    log() {
      echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG_FILE"
    }

    notify() {
      local status="$1"
      local summary
      summary=$(${pkgs.gnugrep}/bin/grep -E "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}" "$LOG_FILE" 2>/dev/null | tail -10 || echo "No log available")
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
    Failed: ''${FAILURE_NAMES:-none}

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
      rm -f "$MOUNT_POINT/.firesafe-backup-scanning" "$MOUNT_POINT/.firesafe-scan" "$MOUNT_POINT/.firesafe-backup-interrupted" "$MOUNT_POINT/.firesafe-progress"
      log "ERROR: $reason"
      notify "failed"
      exit 1
    }

    cleanup() {
      local rc=$?
      log "Backup interrupted — stopping"
      rm -f "$MOUNT_POINT/.firesafe-backup-scanning" "$MOUNT_POINT/.firesafe-scan"
      date -Iseconds > "$MOUNT_POINT/.firesafe-backup-interrupted" 2>/dev/null || true
      # DON'T umount — mount stays live for fast resume via timer
      exit 0
    }
    trap cleanup TERM INT

    # 0a. Clean up timer resume marker (created by firesafe-backup-resume.service)
    rm -f /run/firesafe-resume 2>/dev/null || true

    # 0b. Check for stale mount (device removed but mount entry lingers)
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
      if ! stat "$MOUNT_POINT/.firesafe-id" >/dev/null 2>&1; then
        log "Stale mount detected — force-unmounting"
        umount -l "$MOUNT_POINT" 2>/dev/null || true
      fi
    fi

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
      ${pkgs.e2fsprogs}/bin/e2fsck -p "$DEVICE" 2>&1 | tee -a "$LOG_FILE" || log "fsck exit code $? (continuing)"
      mount "$DEVICE" "$MOUNT_POINT" || abort "Failed to mount $DEVICE at $MOUNT_POINT"
      log "Mounted $DEVICE at $MOUNT_POINT"
    fi

    # 2. Read drive ID
    DRIVE_ID="unknown"
    if [ -f "$MOUNT_POINT/.firesafe-id" ]; then
      DRIVE_ID=$(cat "$MOUNT_POINT/.firesafe-id")
    fi
    log "Drive ID: $DRIVE_ID"

    # 3. Check previous backup state and resume markers
    if [ -f "$MOUNT_POINT/.firesafe-backup-interrupted" ]; then
      log "Previous backup was interrupted — resuming"
      if [ -f "$MOUNT_POINT/.firesafe-progress" ]; then
        SKIP_SOURCES=$(cat "$MOUNT_POINT/.firesafe-progress")
        log "Skipping completed sources: $(echo "$SKIP_SOURCES" | tr '\n' ' ')"
      fi
    elif [ -f "$MOUNT_POINT/.firesafe-backup-start" ] && [ ! -f "$MOUNT_POINT/.firesafe-backup-complete" ]; then
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

    # 5b. Scan sources: dry-run to estimate total transfer size
    log "--- Scanning sources (dry-run) ---"
    touch "$MOUNT_POINT/.firesafe-backup-scanning"
    SCAN_TOTAL=0
    SCAN_TRANSFER=0
    SCAN_FILE_COUNT=0
    SCAN_LOG="$MOUNT_POINT/.firesafe-scan"
    > "$SCAN_LOG"
    ${lib.concatStringsSep "\n" mkScanCmds}
    printf "total\t%s\t%s\t%s\n" "$SCAN_TOTAL" "$SCAN_TRANSFER" "$SCAN_FILE_COUNT" >> "$SCAN_LOG"
    log "Scan complete: $((SCAN_TRANSFER / 1048576)) MB to transfer over $SCAN_FILE_COUNT files"
    rm -f "$MOUNT_POINT/.firesafe-backup-scanning"

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

    # 7. Run rsync for each source
    log "--- Running backups ---"
    BACKUP_DATE=$(date +%Y-%m-%d)
    ${lib.concatStringsSep "\n" mkRsyncCmds}

    # 8. Record deleted files in permanent changelog
    CHANGELOG="/dragon/logs/firesafe-backup-changelog.log"
    if [ -d "$MOUNT_POINT/.deleted/$BACKUP_DATE" ]; then
      touch "$CHANGELOG"
      ${pkgs.findutils}/bin/find "$MOUNT_POINT/.deleted/$BACKUP_DATE" -type f 2>/dev/null | while read -r f; do
        rel="''${f#$MOUNT_POINT/.deleted/$BACKUP_DATE/}"
        printf "%s\t%s\n" "$BACKUP_DATE" "$rel" >> "$CHANGELOG"
      done
      log "Recorded deleted files in '/dragon/logs/firesafe-backup-changelog.log'"
    fi

    # 9. Write completion marker
    if [ "$FAILURE_COUNT" -eq 0 ]; then
      date -Iseconds > "$MOUNT_POINT/.firesafe-backup-complete"
      rm -f "$MOUNT_POINT/.firesafe-backup-interrupted" "$MOUNT_POINT/.firesafe-progress"
      log "=== Backup Complete ==="
      log "Unmounting drive..."
      if timeout 300 umount "$MOUNT_POINT" 2>/dev/null; then
        log "Drive unmounted — safe to unplug"
        notify "completed"
      else
        umount -l "$MOUNT_POINT" 2>/dev/null || true
        log "Flushing data to drive..."
        sync
        log "Data flushed — safe to unplug"
        notify "completed"
      fi
    else
      log "=== Backup Partial ($FAILURE_COUNT failures) ==="
      # Keep progress and interrupted markers so auto-resume retries failed sources
      notify "partial"
    fi
    log "Summary: $SUCCESS_COUNT succeeded, $FAILURE_COUNT failed"
    [ -n "$FAILURE_NAMES" ] && log "Failed: $FAILURE_NAMES"
    FREE_BYTES=$(df --output=avail -B1 "$MOUNT_POINT" 2>/dev/null | tail -1)
    log "Free space remaining: $((FREE_BYTES / 1024 / 1024 / 1024))GB"
  ''
