{
  config,
  pkgs,
  lib,
  ...
}: let
  rsync-tmbackup = pkgs.callPackage ../../pkgs/rsync-tmbackup {};
in {
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

      if [ ! -d "$LIVE" ] || [ -z "$(ls -A "$LIVE" 2>/dev/null)" ]; then
        exit 0
      fi

      exec ${rsync-tmbackup}/bin/rsync-tmbackup \
        --strategy "1:1 7:7 28:30 180:365" \
        --log-dir /var/log/rsync-tmbackup \
        "$LIVE/" \
        /dragon/backups/accismus/
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
      ReadWritePaths = ["/var/log" "/dragon/backups"];
      RestrictNamespaces = true;
    };
    path = [pkgs.rsync];
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
      BACKUP_DIR="/dragon/backups/accismus"
      LATEST="$BACKUP_DIR/latest"
      LOG_FILE="/var/log/accismus-backup-monitor.log"
      THRESHOLD_HOURS=26

      log() {
        echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
      }

      if [ ! -L "$LATEST" ]; then
        log "ALERT: no latest snapshot symlink"
        ${pkgs.msmtp}/bin/msmtp -t <<EOM
      To: root
      Subject: [ALERT] Backup — no latest snapshot

      No rsync snapshot found at $LATEST.
      Check: systemctl status accismus-snapshot
      Check: ls -la $BACKUP_DIR
      EOM
        exit 1
      fi

      TARGET=$(readlink "$LATEST")
      TS=$(date -d "$(echo "$TARGET" | sed 's/^\(....\)-\(..\)-\(..\)-\(..\)\(..\)\(..\).*$/\1-\2-\3 \4:\5:\6/')" +%s 2>/dev/null || echo "")
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
      Check: ls -la $BACKUP_DIR
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

  # IRC bouncer. Holds the upstream connection to Libera.Chat open, buffers
  # messages while clients are offline, and replays them on reconnect (IRCv3
  # chathistory). Reachable from accismus over the tailnet — WireGuard already
  # encrypts the wire, so plain IRC on 6667 is fine.
  #
  # soju's listen scheme defaults to ircs:// (TLS). Use irc+insecure://
  # explicitly for plaintext — the tailnet provides the encrypted transport.
  services.soju = {
    enable = true;
    hostName = "sophrosyne";
    listen = ["irc+insecure://:6667"];
    # Firewall opened on the tailnet interface only in ./networking.nix.
  };

  # Seed/keep in sync the soju bouncer user `scott` with the agenix secret.
  # soju stores the bouncer password in its SQLite DB (set via `sojuctl`, not
  # a config file), so we drive sojuctl over its unix admin socket after
  # soju.service is up. Runs as root (root can reach the socket regardless of
  # soju's dynamic-user uid). Idempotent: if the user exists, update the
  # password on every switch so it always matches secrets/soju-password.age
  # (which accismus' Halloy also reads). `-realname` is only settable on the
  # current user, so it's omitted from `user create`.
  #
  # Use the full nix-store path for sojuctl — systemd units don't inherit
  # environment.systemPackages PATH.
  systemd.services.soju-user = {
    description = "Seed soju bouncer user from agenix secret";
    after = ["soju.service"];
    requires = ["soju.service"];
    wantedBy = ["multi-user.target"];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "soju-seed-user" ''
        set -e
        SOJU_PW="$(cat ${config.age.secrets.soju-password.path})"
        if ${pkgs.soju}/bin/sojuctl user status scott >/dev/null 2>&1; then
          ${pkgs.soju}/bin/sojuctl user update scott -password "$SOJU_PW"
        else
          ${pkgs.soju}/bin/sojuctl user create -username scott -password "$SOJU_PW" -nick scott
        fi
      '';
    };
  };
}
