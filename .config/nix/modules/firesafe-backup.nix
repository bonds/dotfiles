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

  statusScript =
    pkgs.writers.writePython3Bin "firesafe-status" {
      libraries = [pkgs.python3Packages.rich];
      flakeIgnore = ["E501"];
    } ''
      import os, sys, time, subprocess, re
      from pathlib import Path
      from datetime import datetime, timezone
      from typing import Optional

      from rich.console import Console, Group
      from rich.text import Text
      from rich.table import Table
      from rich.progress_bar import ProgressBar
      from rich.rule import Rule
      from rich.live import Live

      console = Console()

      MOUNT_POINT = "${cfg.mountPoint}"
      LOG_FILE = "/var/log/firesafe-backup.log"
      TOTAL_SOURCES = ${toString (builtins.length (builtins.attrNames cfg.sources))}


      def fmt_time(seconds: int) -> str:
          h, m = divmod(seconds // 60, 60)
          return f"{h}h {m}m" if h > 0 else f"{m}m"


      def fmt_bytes(n: int) -> str:
          for unit in ("B", "KB", "MB", "GB", "TB"):
              if abs(n) < 1024:
                  return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
              n //= 1024
          return f"{n:.1f} PB"


      def is_mounted(path: str) -> bool:
          try:
              return subprocess.run(["mountpoint", "-q", path], timeout=5).returncode == 0
          except (FileNotFoundError, subprocess.TimeoutExpired):
              return False


      def get_service_state() -> str:
          try:
              r = subprocess.run(
                  ["systemctl", "is-active", "firesafe-backup.service"],
                  capture_output=True, text=True, timeout=5,
              )
              return r.stdout.strip()
          except (FileNotFoundError, subprocess.TimeoutExpired):
              return "unknown"


      def parse_etime(etime: str) -> int:
          if not etime or etime == "?":
              return 0
          if "-" in etime:
              ds, rest = etime.split("-", 1)
              parts = rest.split(":")
              if len(parts) == 3:
                  return int(ds) * 86400 + int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
              return int(ds) * 86400
          parts = etime.split(":")
          if len(parts) == 3:
              return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
          elif len(parts) == 2:
              return int(parts[0]) * 60 + int(parts[1])
          return int(parts[0]) if parts[0].isdigit() else 0


      def get_fsck_info() -> Optional[dict]:
          try:
              ps = subprocess.run(["ps", "aux"], capture_output=True, text=True, timeout=5)
          except (FileNotFoundError, subprocess.TimeoutExpired):
              return None
          for line in ps.stdout.splitlines():
              if "e2fsck" in line and "grep" not in line:
                  fields = line.split()
                  if len(fields) < 11:
                      continue
                  pid, dev = fields[1], fields[-1]
                  dev_name = re.sub(r"\d+$", "", os.path.basename(dev))
                  etime = subprocess.run(
                      ["ps", "-p", pid, "-o", "etime="],
                      capture_output=True, text=True, timeout=5,
                  ).stdout.strip()
                  elapsed = parse_etime(etime)
                  sectors = 0
                  stat = f"/sys/block/{dev_name}/stat"
                  if os.access(stat, os.R_OK):
                      with open(stat) as f:
                          parts = f.read().split()
                      if len(parts) >= 3 and parts[2].isdigit():
                          sectors = int(parts[2])
                  return {"elapsed": etime, "elapsed_secs": elapsed, "sectors": sectors, "dev": dev}
          return None


      def read_markers(mp: str) -> tuple[Optional[str], Optional[str], Optional[str]]:
          p = Path(mp)
          did = (p / ".firesafe-id").read_text().strip() if (p / ".firesafe-id").exists() else None
          comp = (p / ".firesafe-backup-complete").read_text().strip() if (p / ".firesafe-backup-complete").exists() else None
          start = (p / ".firesafe-backup-start").read_text().strip() if (p / ".firesafe-backup-start").exists() else None
          return did, comp, start


      def count_completed_sources(logpath: str) -> int:
          if not os.path.isfile(logpath):
              return 0
          with open(logpath) as f:
              return len(re.findall(r": (?:SUCCESS|FAILED)", f.read()))


      def get_disk_info(path: str) -> tuple[str, str, str, int]:
          try:
              r = subprocess.run(["df", "-h", path], capture_output=True, text=True, timeout=5)
          except (FileNotFoundError, subprocess.TimeoutExpired):
              return "?", "?", "?", 0
          lines = r.stdout.strip().splitlines()
          if len(lines) >= 2:
              parts = lines[-1].split()
              if len(parts) >= 5:
                  pct = int(parts[4].rstrip("%"))
                  return parts[1], parts[2], parts[3], pct
          return "?", "?", "?", 0


      def get_deleted_summary(dd: Path) -> dict:
          if not dd.is_dir():
              return {"size": "?", "oldest": None, "newest": None, "count": 0}
          du = subprocess.run(["du", "-sh", str(dd)], capture_output=True, text=True, timeout=5)
          size = du.stdout.split()[0] if du.stdout else "?"
          entries = sorted([d.name for d in dd.iterdir() if d.is_dir()])
          return {"size": size, "count": len(entries), "oldest": entries[0] if entries else None, "newest": entries[-1] if entries else None}


      def log_tail(logpath: str, n: int = 20) -> list[str]:
          if not os.path.isfile(logpath):
              return []
          with open(logpath) as f:
              return f.read().splitlines()[-n:]


      def build_status() -> Group:
          parts = []

          parts.append(Rule(title="[bold cyan]Firesafe Backup[/bold cyan]", style="cyan"))
          parts.append("")

          if not is_mounted(MOUNT_POINT):
              if get_service_state() in ("activating", "active"):
                  fsck = get_fsck_info()
                  if fsck:
                      bb = fsck["sectors"] * 512
                      t = Text()
                      t.append("⚠  Checking filesystem", style="bold yellow")
                      t.append(f"  ·  {fmt_bytes(bb)} read", style="bold")
                      parts.append(t)
                      if fsck["elapsed_secs"]:
                          parts.append(Text(
                              f"  {fmt_bytes(bb // fsck['elapsed_secs'])}/s  ·  running {fsck['elapsed']}",
                              style="dim",
                          ))
                      else:
                          parts.append(Text(f"  running {fsck['elapsed']}", style="dim"))
                      parts.append("")
                      parts.append(Rule(style="dim"))
                      parts.append(Text("Last backup log:", style="bold"))
                      for l in log_tail(LOG_FILE, 5):
                          parts.append(Text(f"  {l}", style="dim"))
                  else:
                      parts.append(Text("⏳  Starting backup...", style="bold yellow"))
                      parts.append("")
                      parts.append(Rule(style="dim"))
                      parts.append(Text("Last backup log:", style="bold"))
                      for l in log_tail(LOG_FILE, 3):
                          parts.append(Text(f"  {l}", style="dim"))
              else:
                  parts.append(Text("✗  Not mounted", style="bold red"))
                  parts.append("")
                  parts.append(Rule(style="dim"))
                  parts.append(Text("Last backup log:", style="bold"))
                  for l in log_tail(LOG_FILE, 20):
                      parts.append(Text(f"  {l}", style="dim"))
              return Group(*parts)

          did, comp, start = read_markers(MOUNT_POINT)
          total, used, avail, pct = get_disk_info(MOUNT_POINT)

          t = Text()
          t.append("✓  Mounted", style="bold green")
          if did:
              t.append(f"  ·  Drive {did}", style="bold")
          parts.append(t)
          parts.append("")

          g = Table.grid(padding=(0, 2))
          g.add_column(style="dim")
          g.add_column()
          g.add_row("Disk:", f"{total} total  ·  {used} used  ·  {avail} free")
          parts.append(g)

          barrow = Table.grid(padding=(0, 1))
          barrow.add_column()
          barrow.add_column()
          barrow.add_row(
              ProgressBar(total=100, completed=pct, width=40),
              Text(f"{pct}%", style="bold"),
          )
          parts.append(barrow)
          parts.append("")

          if comp:
              t2 = Text()
              t2.append("✓  Backup complete", style="green")
              t2.append(f"  {comp}", style="dim")
              parts.append(t2)
          elif start:
              try:
                  sd = datetime.fromisoformat(start)
                  elapsed = max(0, int((datetime.now(timezone.utc) - sd).total_seconds()))
              except Exception:
                  elapsed = 0
              t2 = Text()
              t2.append("⏳  In progress", style="bold yellow")
              t2.append(f"  ·  {fmt_time(elapsed)} elapsed", style="dim")
              parts.append(t2)

              done = count_completed_sources(LOG_FILE)
              if done > 0 and elapsed > 30:
                  rem = max(0, TOTAL_SOURCES - done)
                  est = (elapsed // done) * rem
                  srow = Table.grid(padding=(0, 1))
                  srow.add_column()
                  srow.add_column()
                  srow.add_row(
                      ProgressBar(total=TOTAL_SOURCES, completed=done, width=40),
                      Text(f"{done}/{TOTAL_SOURCES} sources", style="bold"),
                  )
                  parts.append(srow)
                  if est > 0:
                      parts.append(Text(f"  ~{fmt_time(est)} remaining  ({done} done)", style="dim"))
          else:
              parts.append(Text("No backup markers found", style="dim"))

          parts.append("")
          parts.append(Rule(title="[bold]Deleted Backups[/bold]", style="dim"))
          parts.append("")

          d = Path(MOUNT_POINT) / ".deleted"
          de = get_deleted_summary(d)
          if de["count"]:
              dg = Table.grid(padding=(0, 2))
              dg.add_column(style="dim")
              dg.add_column(style="bold")
              dg.add_row("Size:", de["size"])
              dg.add_row("Snapshots:", str(de["count"]))
              if de["oldest"]:
                  dg.add_row("Oldest:", de["oldest"])
              if de["newest"]:
                  dg.add_row("Newest:", de["newest"])
              parts.append(dg)
          else:
              parts.append(Text("No .deleted/ directory found", style="dim"))

          parts.append("")
          parts.append(Rule(title="[bold]Last Backup Log[/bold]", style="dim"))
          for l in log_tail(LOG_FILE, 20):
              parts.append(Text(f"  {l}", style="dim"))

          return Group(*parts)


      def main():
          try:
              if "-w" in sys.argv or "--watch" in sys.argv:
                  with Live(console=console, refresh_per_second=0.5, screen=False) as live:
                      while True:
                          live.update(build_status())
                          time.sleep(2)
              else:
                  console.print(build_status())
          except KeyboardInterrupt:
              pass


      if __name__ == "__main__":
          main()
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

    # 1. Kill all backup and rsync processes
    PIDS=$(pgrep -f "firesafe-backup|rsync.*$MOUNT_POINT" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
      echo "Stopping backup processes..."
      echo "$PIDS" | sudo xargs kill 2>/dev/null || true
      sleep 2
      # Force kill any remaining
      echo "$PIDS" | sudo xargs kill -9 2>/dev/null || true
    fi

    # 2. Flush filesystem writes
    echo "Syncing filesystem..."
    sync

    # 3. Unmount
    echo "Unmounting..."
    if sudo umount "$MOUNT_POINT"; then
      echo "Drive unmounted — safe to unplug."
    else
      # Try lazy unmount if regular unmount fails
      echo "Trying lazy unmount..."
      sudo umount -l "$MOUNT_POINT" 2>/dev/null && echo "Drive unmounted (lazy) — safe to unplug." || echo "Failed to unmount."
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
