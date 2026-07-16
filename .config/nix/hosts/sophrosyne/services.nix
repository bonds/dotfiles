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
      THRESHOLD_HOURS=48
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
