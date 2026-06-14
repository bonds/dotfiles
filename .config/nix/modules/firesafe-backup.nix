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
    To eject: sudo umount $MOUNT_POINT
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

      # 7. Compute total source size (one-time per backup)
      log "--- Computing total source size ---"
      TOTAL_SIZE=0
      ${lib.concatStringsSep "\n" mkTotalSizeCmds}
      echo "$TOTAL_SIZE" > "$MOUNT_POINT/.firesafe-backup-total"
      log "Total source size: $((TOTAL_SIZE / 1024 / 1024 / 1024))GB"

      # 8. Record starting used space for progress tracking
      ${pkgs.coreutils}/bin/df --output=used -B1 "$MOUNT_POINT" 2>/dev/null | tail -1 > "$MOUNT_POINT/.firesafe-df-start"

      # 9. Run rsync for each source
      log "--- Running backups ---"
      BACKUP_DATE=$(date +%Y-%m-%d)
      ${lib.concatStringsSep "\n" mkRsyncCmds}

      # 8. Write completion marker
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

    show_status() {
      MOUNT_POINT="${cfg.mountPoint}"
      LOG_FILE="/var/log/firesafe-backup.log"
      TOTAL_SOURCES=${toString (builtins.length (builtins.attrNames cfg.sources))}

      echo "=== Firesafe Backup Status ==="
      if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo "Status: MOUNTED | Size: $(df -h "$MOUNT_POINT" | tail -1 | awk '{print $2}') | Avail: $(df -h "$MOUNT_POINT" | tail -1 | awk '{print $4}')"
        [ -f "$MOUNT_POINT/.firesafe-id" ] && echo "Drive: $(cat $MOUNT_POINT/.firesafe-id)"
        echo

        if [ -f "$MOUNT_POINT/.firesafe-backup-complete" ]; then
          echo "Backup completed: $(cat $MOUNT_POINT/.firesafe-backup-complete)"
        elif [ -f "$MOUNT_POINT/.firesafe-backup-start" ]; then
          # --- Compute time info ---
          START_TIME=$(cat "$MOUNT_POINT/.firesafe-backup-start")
          NOW=$(date -Iseconds)
          ELAPSED=$(( $(date -d "$NOW" +%s) - $(date -d "$START_TIME" +%s) ))
          ELAPSED_H=$(( ELAPSED / 3600 ))
          ELAPSED_M=$(( (ELAPSED % 3600) / 60 ))
          printf "Backup started: %s  |  Elapsed: %dh %dm\n" "$START_TIME" "$ELAPSED_H" "$ELAPSED_M"

          # --- Overall progress (no rsync detail) ---
          TOTAL_BYTES=$(cat "$MOUNT_POINT/.firesafe-backup-total" 2>/dev/null || echo 0)
          DF_START=$(cat "$MOUNT_POINT/.firesafe-df-start" 2>/dev/null || echo 0)
          if [ "$TOTAL_BYTES" -gt 0 ] && [ "$DF_START" -gt 0 ]; then
            DF_NOW=$(df --output=used -B1 "$MOUNT_POINT" 2>/dev/null | tail -1)
            BYTES_SENT=$((DF_NOW - DF_START))
            [ "$BYTES_SENT" -lt 0 ] && BYTES_SENT=0
            PCT=$(( BYTES_SENT * 100 / TOTAL_BYTES ))
            [ "$PCT" -gt 100 ] && PCT=100
            echo "Progress: ${PCT}% ($((BYTES_SENT / 1024 / 1024 / 1024))GB / $((TOTAL_BYTES / 1024 / 1024 / 1024))GB)"

            if [ "$ELAPSED" -gt 0 ] && [ "$BYTES_SENT" -gt 0 ]; then
              SPEED=$(( BYTES_SENT / ELAPSED ))
              REMAINING=$(( TOTAL_BYTES - BYTES_SENT ))
              [ "$REMAINING" -lt 0 ] && REMAINING=0
              ETA_SEC=$(( REMAINING / (SPEED > 0 ? SPEED : 1) ))
              ETA_H=$(( ETA_SEC / 3600 ))
              ETA_M=$(( (ETA_SEC % 3600) / 60 ))
              if [ "$SPEED" -ge 1073741824 ]; then
                SPEED_STR="$((SPEED / 1073741824)).$(((SPEED % 1073741824) / 107374182)) GB/s"
              elif [ "$SPEED" -ge 1048576 ]; then
                SPEED_STR="$((SPEED / 1048576)).$(((SPEED % 1048576) / 104857)) MB/s"
              else
                SPEED_STR="$((SPEED / 1024)) KB/s"
              fi
              echo "Speed: $SPEED_STR  |  Estimated remaining: ~${ETA_H}h ${ETA_M}m"
            fi
          elif [ -f "$MOUNT_POINT/.firesafe-backup-total" ]; then
            echo "Progress: computing..."
          fi
          echo

          # --- Current task details (rsync detail ok) ---
          CURRENT=$(grep -oE -- '--- [[:alpha:]]+ ---' "$LOG_FILE" 2>/dev/null | tail -1 | sed 's/--- //g; s/ ---//g')
          DONE=$(grep -cE ":( SUCCESS|FAILED)" "$LOG_FILE" 2>/dev/null || true)
          if [ -n "$CURRENT" ]; then
            printf "Current task: %s (%d/%d)" "$CURRENT" "$((DONE + 1))" "$TOTAL_SOURCES"
            REMAINING=$((TOTAL_SOURCES - DONE - 1))
            [ "$REMAINING" -gt 0 ] && printf "  (+%d remaining)" "$REMAINING"
            echo
            LAST_PROGRESS=$(grep -E '[0-9]+\.[0-9]+(MB|GB|KB)/s' "$LOG_FILE" 2>/dev/null | tail -1)
            if [ -n "$LAST_PROGRESS" ]; then
              ETA=$(echo "$LAST_PROGRESS" | awk '{for(i=NF;i>0;i--){if($i~/^[0-9]+:[0-9]+:[0-9]+$/){print $i;break}}}')
              [ -n "$ETA" ] && echo "Rsync ETA for $CURRENT: $ETA"
            fi
          fi
        else
          echo "No backup markers found."
        fi
      else
        echo "Status: NOT MOUNTED"
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

    environment.systemPackages = [statusScript reclaimScript];

    systemd.tmpfiles.rules = [
      "f /var/log/firesafe-backup.log 0640 root users -"
    ];
  };
}
