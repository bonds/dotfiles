{
  config,
  pkgs,
  ...
}: {
  systemd.services.ddns = {
    startAt = "*:0/15";
    serviceConfig = {
      Type = "oneshot";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectHome = true;
      RestrictNamespaces = true;
    };
    path = [pkgs.curl];
    script = ''
      TOKEN=$(cat ${config.age.secrets.ddns-token.path})
      ACCOUNT_ID="75214"
      ZONE_ID="ggr.com"
      RECORD_ID="47161920"
      IP=$(curl --ipv4 -s http://icanhazip.com/)

      curl -H "Authorization: Bearer $TOKEN" \
           -H "Content-Type: application/json" \
           -H "Accept: application/json" \
           -X "PATCH" \
           -i "https://api.dnsimple.com/v2/$ACCOUNT_ID/zones/$ZONE_ID/records/$RECORD_ID" \
           -d "{\"content\":\"$IP\"}"
    '';
  };

  systemd.services.photo-backup-monitor = let
    monitorScript = pkgs.writeShellScript "photo-backup-monitor" ''
      PHOTO_DIR="/dragon/media/photos"
      THRESHOLD_HOURS=168
      LOG_FILE="/var/log/photo-backup-monitor.log"

      log() {
        echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
      }

      NEWEST=$(find "$PHOTO_DIR" -type f -not -path '*/\.*' -printf '%T@ %p\n' 2>/dev/null | sort -rn 2>/dev/null | head -1)

      if [ -z "$NEWEST" ]; then
        log "ALERT: No photos found in $PHOTO_DIR"
        ${pkgs.msmtp}/bin/msmtp -t <<EOM
      To: root
      Subject: [ALERT] Photo backup — no photos on sophrosyne

      No photos found in $PHOTO_DIR.

      The backup may have never run or photos were deleted.
      Check: ssh accismus "launchctl list | grep photos-backup"
      Logs: cat /tmp/photos-backup.out.log
      EOM
        exit 1
      fi

      NEWEST_TIME=$(echo "$NEWEST" | cut -d' ' -f1)
      NEWEST_FILE=$(echo "$NEWEST" | cut -d' ' -f2-)
      NOW=$(date +%s)
      AGE_HOURS=$(( (NOW - $(printf "%.0f" "$NEWEST_TIME")) / 3600 ))

      if [ "$AGE_HOURS" -gt "$THRESHOLD_HOURS" ]; then
        log "ALERT: newest photo ''${AGE_HOURS}h old (threshold ''${THRESHOLD_HOURS}h) — $NEWEST_FILE"
        ${pkgs.msmtp}/bin/msmtp -t <<EOM
      To: root
      Subject: [ALERT] Photo backup stalled — ''${AGE_HOURS}h since last photo

      The most recent photo on sophrosyne is ''${AGE_HOURS}h old.
      File: $NEWEST_FILE
      Threshold: ''${THRESHOLD_HOURS}h

      Check the backup on accismus:
        ssh accismus "launchctl list | grep photos-backup"
        cat /tmp/photos-backup.out.log
        cat /tmp/photos-backup.err.log

      Or check manually:
        ls -lt /dragon/media/photos/2026/ | head -5
      EOM
        exit 1
      fi

      log "OK: newest photo ''${AGE_HOURS}h old — $NEWEST_FILE"
      exit 0
    '';
  in {
    description = "Check if photo backup is fresh — alert if stalled >48h";
    after = ["network.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = monitorScript;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectHome = true;
      ReadWritePaths = ["/var/log" "/dragon/media/photos"];
      RestrictNamespaces = true;
    };
  };
  systemd.timers.photo-backup-monitor = {
    description = "Daily photo backup freshness check";
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
    wantedBy = ["timers.target"];
  };

  systemd.services.log-temps = let
    logScript = pkgs.writeShellScript "log-temps" ''
      log=/dragon/logs/temps.log
      ts=$(date +%s)
      printf "%s " "$ts" >> "$log"
      for d in /dev/nvme*n1; do
        t=$(${pkgs.nvme-cli}/bin/nvme smart-log "$d" 2>/dev/null | sed -n 's/^temperature.*: *\([0-9]*\).*/\1/p')
        printf "nvme-%s=%s " "$(basename $d)" "$t" >> "$log"
      done
      cpu=$(cat /sys/devices/platform/coretemp.0/hwmon/hwmon9/temp1_input 2>/dev/null)
      printf "cpu=%s " "$((cpu / 1000))" >> "$log"
      f1=$(cat /sys/devices/platform/dell_smm_hwmon/hwmon/hwmon10/fan1_input 2>/dev/null)
      f2=$(cat /sys/devices/platform/dell_smm_hwmon/hwmon/hwmon10/fan2_input 2>/dev/null)
      printf "fan-cpu=%s fan-sys=%s" "$f1" "$f2" >> "$log"
      echo >> "$log"
    '';
  in {
    description = "Log temperatures to /dragon/logs/temps.log";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = logScript;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectHome = true;
      ReadWritePaths = ["/dragon/logs"];
      ReadOnlyPaths = ["/sys" "/dev"];
    };
  };
  systemd.timers.log-temps = {
    description = "Log temperatures every minute";
    timerConfig = {
      OnCalendar = "minutely";
      Persistent = true;
    };
    wantedBy = ["timers.target"];
  };

  systemd.services.accismus-snapshot = let
    snapshotScript = pkgs.writeShellScript "accismus-snapshot" ''
      set -euo pipefail
      LIVE="/dragon/backups/accismus/live"
      SNAPSHOTS="/dragon/backups/accismus/snapshots"
      TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
      NEW_SNAPSHOT="$SNAPSHOTS/$TIMESTAMP"
      CURRENT="$SNAPSHOTS/current"
      LOG_FILE="/var/log/accismus-snapshot.log"

      log() {
        echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
      }

      # Only run if syncthing has synced data
      if [ ! -d "$LIVE" ] || [ -z "$(ls -A "$LIVE" 2>/dev/null)" ]; then
        log "SKIP: live directory empty or missing"
        exit 0
      fi

      mkdir -p "$SNAPSHOTS"
      LINK_DEST=""
      if [ -L "$CURRENT" ] && [ -d "$(readlink -f "$CURRENT" 2>/dev/null)" ]; then
        LINK_DEST="--link-dest=$(readlink -f "$CURRENT")"
      fi

      log "starting snapshot $TIMESTAMP"
      ${pkgs.rsync}/bin/rsync -a --delete $LINK_DEST "$LIVE/" "$NEW_SNAPSHOT/" >> "$LOG_FILE" 2>&1
      ln -snf "$TIMESTAMP" "$CURRENT"
      log "snapshot $TIMESTAMP complete"

      # --- Prune old snapshots ---
      NOW=$(date +%s)
      KEEP=0
      LAST_DAY=""
      LAST_WEEK=""
      LAST_MONTH=""
      LAST_YEAR=""

      for snap in $(ls -1 "$SNAPSHOTS" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{6}$' | sort -r); do
        TS=$(date -d "$(echo "$snap" | sed 's/_/ /')" +%s 2>/dev/null || echo "")
        [ -z "$TS" ] && continue
        AGE=$(( (NOW - TS) / 3600 ))
        DAY=$(date -d "@$TS" +%Y%m%d)
        WEEK=$(date -d "@$TS" +%Y%W)
        MONTH=$(date -d "@$TS" +%Y%m)
        YEAR=$(date -d "@$TS" +%Y)

        DELETE=1
        # hourly: keep first 24
        if [ "$AGE" -le 24 ]; then
          DELETE=0
        # daily: keep 1 per day for days 2-7
        elif [ "$AGE" -le 168 ] && [ "$DAY" != "$LAST_DAY" ]; then
          DELETE=0
          LAST_DAY="$DAY"
        # weekly: keep 1 per week for weeks 2-4
        elif [ "$AGE" -le 672 ] && [ "$WEEK" != "$LAST_WEEK" ]; then
          DELETE=0
          LAST_WEEK="$WEEK"
        # monthly: keep 1 per month for months 2-6
        elif [ "$AGE" -le 4380 ] && [ "$MONTH" != "$LAST_MONTH" ]; then
          DELETE=0
          LAST_MONTH="$MONTH"
        # yearly: keep 1 per year for years 2-4
        elif [ "$AGE" -le 35040 ] && [ "$YEAR" != "$LAST_YEAR" ]; then
          DELETE=0
          LAST_YEAR="$YEAR"
          DELETE=0
          LAST_MONTH="$MONTH"
        fi

        if [ "$DELETE" = 1 ]; then
          rm -rf "$SNAPSHOTS/$snap"
          log "pruned $snap ($AGE hours old)"
        fi
      done
      log "prune complete"
    '';
  in {
    description = "Hourly rsync snapshot of accismus home backup";
    after = ["network.target" "syncthing.service"];
    wants = ["syncthing.service"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = snapshotScript;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectHome = true;
      ReadWritePaths = ["/var/log" "/dragon/backups"];
      RestrictNamespaces = true;
    };
  };
  systemd.timers.accismus-snapshot = {
    description = "Hourly rsync snapshot";
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
    };
    wantedBy = ["timers.target"];
  };

  systemd.services.accismus-backup-monitor = let
    monitorScript = pkgs.writeShellScript "accismus-backup-monitor" ''
      set -euo pipefail
      SNAPSHOTS="/dragon/backups/accismus/snapshots"
      CURRENT="$SNAPSHOTS/current"
      LOG_FILE="/var/log/accismus-backup-monitor.log"
      THRESHOLD_HOURS=26

      log() {
        echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
      }

      if [ ! -L "$CURRENT" ]; then
        log "ALERT: no current snapshot symlink"
        ${pkgs.msmtp}/bin/msmtp -t <<EOM
      To: root
      Subject: [ALERT] Backup — no current snapshot

      No rsync snapshot found at $CURRENT.
      Check: systemctl status accismus-snapshot
      Check: ls -la $SNAPSHOTS
      EOM
        exit 1
      fi

      TARGET=$(readlink "$CURRENT")
      TS=$(date -d "$(echo "$TARGET" | sed 's/_/ /')" +%s 2>/dev/null || echo "")
      if [ -z "$TS" ]; then
        log "ALERT: could not parse snapshot date from $TARGET"
        exit 1
      fi

      NOW=$(date +%s)
      AGE_HOURS=$(( (NOW - TS) / 3600 ))

      if [ "$AGE_HOURS" -gt "$THRESHOLD_HOURS" ]; then
        log "ALERT: last snapshot ''${AGE_HOURS}h old (threshold ''${THRESHOLD_HOURS}h)"
        ${pkgs.msmtp}/bin/msmtp -t <<EOM
      To: root
      Subject: [ALERT] Backup stalled — ''${AGE_HOURS}h since last snapshot

      The most recent snapshot is ''${AGE_HOURS}h old.
      Snapshot: $TARGET
      Threshold: ''${THRESHOLD_HOURS}h

      Check: systemctl status accismus-snapshot
      Check: ls -la $SNAPSHOTS
      EOM
        exit 1
      fi

      log "OK: last snapshot ''${AGE_HOURS}h old — $TARGET"
    '';
  in {
    description = "Check if rsync backup is fresh — alert if stalled >26h";
    after = ["network.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = monitorScript;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectHome = true;
      ReadWritePaths = ["/var/log" "/dragon/backups"];
      RestrictNamespaces = true;
    };
  };
  systemd.timers.accismus-backup-monitor = {
    description = "Daily backup freshness check";
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
    wantedBy = ["timers.target"];
  };

  systemd.services.set-max-fans = let
    fanScript = pkgs.writeShellScript "set-max-fans" ''
      for _ in 1 2 3 4 5; do
        for pwm in /sys/devices/platform/dell_smm_hwmon/hwmon/hwmon*/pwm[12]; do
          if [ -f "$pwm" ]; then
            echo 255 > "$pwm"
          fi
        done
        if [ "$(cat /sys/devices/platform/dell_smm_hwmon/hwmon/hwmon*/fan1_input 2>/dev/null)" -gt 4000 ]; then
          exit 0
        fi
        sleep 2
      done
    '';
  in {
    description = "Pin fans to maximum speed";
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = fanScript;
      RemainAfterExit = true;
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      PrivateTmp = true;
      ProtectHome = true;
      ReadWritePaths = ["/sys/devices/platform/dell_smm_hwmon"];
    };
  };
}
