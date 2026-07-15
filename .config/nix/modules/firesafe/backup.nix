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
        rsync \
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
      STATS=$(rsync --dry-run --stats --quiet --archive \
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

  script = builtins.readFile ./backup.sh;
  script' =
    builtins.replaceStrings
    ["@mountPoint@" "@email@" "@threshold@" "@label@" "@logFile@" "@sourceChecks@" "@scanCmds@" "@rsyncCmds@"]
    [
      cfg.mountPoint
      cfg.emailRecipient
      (toString cfg.spaceThreshold)
      cfg.driveLabel
      "/var/log/firesafe-backup.log"
      (lib.concatStringsSep "\n" mkSourceChecks)
      (lib.concatStringsSep "\n" mkScanCmds)
      (lib.concatStringsSep "\n" mkRsyncCmds)
    ]
    script;
in
  pkgs.writeShellScriptBin "firesafe-backup" ''
    export PATH="${lib.makeBinPath (with pkgs; [
      rsync
      util-linux
      e2fsprogs
      msmtp
      findutils
      gnugrep
      gnused
      gawk
      coreutils
    ])}:$PATH"
    ${script'}
  ''
