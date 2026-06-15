# == Drive performance notes (WD Game Drive 5TB, WD50NMZW) ==
#
# USB VID:PID 1058:262f — Western Digital proprietary bridge, BOT (Bulk-Only Transport)
# only. No UASP support (bInterfaceProtocol 0x50, no alternate setting 0x62). USB-native
# PCB — cannot shuck or swap enclosure. QD=1 hardware limit.
#
# Sequential write (dd bs=1M, 5GB): ~40-90 MB/s on ext4, ~140-150 MB/s on exFAT
#   (ref: https://unix.stackexchange.com/questions/613223 — same WD NMZW drive family).
# ext4 journal enforces write ordering, serializing at QD=1. exFAT has no journal so it
# appears faster but offers no crash recovery and no POSIX perms (breaks rsync --archive).
#
# Random I/O (journal replay, dirty page flush): ~1 MB/s. With default dirty_ratio=20%
# on a 32GB system, umount can queue ~6.4 GB of dirty pages — a 73-minute wait at QD=1.
#
# Our fix: skip umount in cleanup() on SIGTERM (fast stop in ~1s), keep mount live,
# auto-resume via firesafe-backup-resume.timer (every 2 min). Progress tracking via
# .firesafe-progress skips completed sources on resume.
#
# Future speed options (not needed with fast-stop resume):
#   - `tune2fs -O ^has_journal /dev/sdX` — ~2x ext4 speed, lose crash recovery
#   - Reformat to exFAT — fastest, but no perms/ownership (rsync --archive breaks)
#   - Replace with a 3.5" SATA drive in UASP enclosure (ASMedia 1153e, RTL9210) — 100+ MB/s
{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.programs.firesafe-backup;

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

      # 0a. Hard guard: if backup was completed successfully and not interrupted, skip
      if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        if [ -f "$MOUNT_POINT/.firesafe-backup-complete" ] && [ ! -f "$MOUNT_POINT/.firesafe-backup-interrupted" ]; then
          if [ -f /run/firesafe-resume ]; then
            rm -f /run/firesafe-resume
          fi
          log "Backup already completed. Nothing to do."
          exit 0
        fi
      fi

      # 0b. Resume guard: clean up timer marker
      rm -f /run/firesafe-resume 2>/dev/null || true

      # 0c. Check for stale mount (device removed but mount entry lingers)
      if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        if ! stat "$MOUNT_POINT/.firesafe-id" >/dev/null 2>&1; then
          log "Stale mount detected — force-unmounting"
          umount -l "$MOUNT_POINT" 2>/dev/null || true
        fi
      fi

      log "=== Firesafe Backup Starting ==="

      WE_MOUNTED=false

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
        WE_MOUNTED=true
      fi

      # 1b. Post-mount guard: if backup completed and not interrupted, nothing to do
      if [ -f "$MOUNT_POINT/.firesafe-backup-complete" ] && [ ! -f "$MOUNT_POINT/.firesafe-backup-interrupted" ]; then
        log "Backup already completed. Nothing to do."
        if [ "$WE_MOUNTED" = true ]; then
          umount "$MOUNT_POINT" 2>/dev/null || true
        fi
        exit 0
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
        # Try clean unmount first (5min timeout), fall back to lazy
        if timeout 300 umount "$MOUNT_POINT" 2>/dev/null; then
          log "Drive unmounted — safe to unplug"
          notify "completed"
        else
          umount -l "$MOUNT_POINT" 2>/dev/null || true
          log "Drive unmounted (lazy) — kernel still flushing, wait before unplugging"
          notify "completed (lazy unmount)"
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
  '';

  statusScript =
    pkgs.writers.writePython3Bin "firesafe-status" {
      libraries = [pkgs.python3Packages.rich];
      flakeIgnore = ["E501"];
    } ''
      import os
      import sys
      import time
      import subprocess
      import re
      import shutil
      from pathlib import Path
      from datetime import datetime, timezone
      from typing import Optional

      from rich.console import Console, Group
      from rich.text import Text
      from rich.progress_bar import ProgressBar
      from rich.rule import Rule
      from rich.live import Live

      console = Console()

      MOUNT_POINT = "${cfg.mountPoint}"
      LOG_FILE = "/var/log/firesafe-backup.log"
      TOTAL_SOURCES = ${toString (builtins.length (builtins.attrNames cfg.sources))}
      FIXED_LINES = 7


      def fmt_time(seconds: int) -> str:
          h, m = divmod(seconds // 60, 60)
          return f"{h}h {m}m" if h > 0 else f"{m}m"


      def fmt_bytes(n: int) -> str:
          for unit in ("B", "KB", "MB", "GB", "TB"):
              if abs(n) < 1024:
                  return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
              n //= 1024
          return f"{n:.1f} PB"


      def terminal_height() -> int:
          return shutil.get_terminal_size((80, 25)).lines


      def log_lines_available() -> int:
          return max(3, terminal_height() - FIXED_LINES)


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

          def safe_read(path: Path) -> Optional[str]:
              try:
                  return path.read_text().strip() if path.exists() else None
              except OSError:
                  return None
          did = safe_read(p / ".firesafe-id")
          comp = safe_read(p / ".firesafe-backup-complete")
          start = safe_read(p / ".firesafe-backup-start")
          return did, comp, start


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


      def read_log() -> list[str]:
          if not os.path.isfile(LOG_FILE):
              return []
          with open(LOG_FILE) as f:
              return f.read().splitlines()


      def find_last_start(lines: list[str]) -> int:
          for i in range(len(lines) - 1, -1, -1):
              if "=== Firesafe Backup Starting ===" in lines[i]:
                  return i
          return -1


      def count_cur_run_sources(lines: list[str], start_idx: int) -> int:
          if start_idx < 0:
              return 0
          count = 0
          for i in range(start_idx, len(lines)):
              if ": SUCCESS" in lines[i] or ": FAILED" in lines[i]:
                  count += 1
          return count


      def get_current_source(lines: list[str], start_idx: int) -> Optional[str]:
          if start_idx < 0:
              return None
          cur = None
          for i in range(start_idx, len(lines)):
              m = re.match(r".*--- (.+) ---", lines[i])
              if m:
                  cur = m.group(1)
              if cur and (": SUCCESS" in lines[i] or ": FAILED" in lines[i]):
                  cur = None
          return cur


      def get_completed_sources(lines: list[str], start_idx: int) -> list[dict]:
          results = []
          for i in range(start_idx, len(lines)):
              m = re.match(r".*--- (.+) ---", lines[i])
              if m:
                  results.append({"name": m.group(1), "duration": None, "bytes": None})
              sm = re.match(
                  r".*: (SUCCESS|FAILED)\s*(?:\((.+)\))?",
                  lines[i],
              )
              if sm and results:
                  results[-1]["status"] = sm.group(1)
                  results[-1]["duration_str"] = sm.group(2)
              bm = re.match(r"^\s*Total bytes sent:\s+([\d,]+)", lines[i])
              if bm and results:
                  results[-1]["bytes"] = int(bm.group(1).replace(",", ""))
          if results and results[-1].get("status") is None:
              results.pop()
          return results


      def parse_scan_file(path: str) -> Optional[dict]:
          if not os.path.isfile(path):
              return None
          data = {"total_bytes": 0, "transfer_bytes": 0, "file_count": 0, "sources": []}
          with open(path) as f:
              for line in f:
                  parts = line.strip().split("\t")
                  if len(parts) < 4:
                      continue
                  name, total, transfer, files = parts[0], parts[1], parts[2], parts[3]
                  if name == "total":
                      data["total_bytes"] = int(total or 0)
                      data["transfer_bytes"] = int(transfer or 0)
                      data["file_count"] = int(files or 0)
                  else:
                      if total.isdigit() and transfer.isdigit() and files.isdigit():
                          data["sources"].append({
                              "name": name,
                              "total": int(total),
                              "transfer": int(transfer),
                              "files": int(files),
                          })
          return data


      def parse_last_progress(lines: list[str]) -> Optional[dict]:
          for line in reversed(lines):
              m = re.match(
                  r"^\s*([\d,]+)\s+(\d+)%\s+([\d.]+)\s+([KMGT]?B/s)\s+",
                  line,
              )
              if m:
                  bytes_val = int(m.group(1).replace(",", ""))
                  pct = int(m.group(2))
                  speed_str = m.group(3) + " " + m.group(4)
                  return {"bytes": bytes_val, "pct": pct, "speed_str": speed_str}
          return None


      def build_not_mounted(lines: list[str]) -> Group:
          parts = []
          parts.append(Rule(title="[bold cyan]Firesafe Backup[/bold cyan]", style="cyan"))
          state = get_service_state()
          if state in ("activating", "active"):
              fsck = get_fsck_info()
              if fsck:
                  bb = fsck["sectors"] * 512
                  t = Text()
                  t.append("⚠  Checking filesystem", style="bold yellow")
                  if bb > 0:
                      t.append(f"  ·  {fmt_bytes(bb)} read", style="bold")
                  parts.append(t)
                  if fsck["elapsed_secs"] and bb > 0:
                      speed = fmt_bytes(bb // fsck["elapsed_secs"]) + "/s"
                      parts.append(Text(f"  {speed}  ·  running {fsck['elapsed']}", style="dim"))
                  else:
                      parts.append(Text(f"  running {fsck['elapsed']}", style="dim"))
              else:
                  parts.append(Text("⏳  Starting backup...", style="bold yellow"))
          else:
              parts.append(Text("✗  Not mounted", style="bold red"))
          parts.append(Rule(style="dim"))
          tail = lines[-(log_lines_available()):] if lines else []
          for line in tail:
              parts.append(Text(f"  {line}", style="dim"))
          return Group(*parts)


      def build_scanning(lines: list[str], start_idx: int, did: Optional[str]) -> Group:
          parts = []
          parts.append(Rule(title="[bold cyan]Firesafe Backup[/bold cyan]", style="cyan"))
          mp = MOUNT_POINT
          total, used, avail, pct = get_disk_info(mp)
          t = Text()
          t.append("✓  Mounted", style="bold green")
          if did:
              t.append(f"  ·  Drive {did}", style="bold")
          t.append(f"  ·  {total} total  ·  {avail} free", style="dim")
          parts.append(t)
          parts.append(ProgressBar(total=100, completed=pct, width=30))

          scan_file = Path(mp) / ".firesafe-scan"
          scanned = 0
          if scan_file.exists():
              with open(scan_file) as f:
                  for line in f:
                      if line.strip() and not line.startswith("total"):
                          scanned += 1

          scanning_idx = -1
          for i, line in enumerate(lines):
              if "Scanning:" in line and start_idx >= 0 and i >= start_idx:
                  scanning_idx = i
          cur_scan = ""
          if scanning_idx >= 0:
              m = re.match(r".*Scanning:\s+(.+)", lines[scanning_idx])
              if m:
                  cur_scan = m.group(1).strip()

          status = Text(f"⏳  Scanning ({scanned}/{TOTAL_SOURCES})", style="bold yellow")
          elapsed = 0
          if scanning_idx >= 0:
              try:
                  ts_str = lines[scanning_idx][:19]
                  ts = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
                  elapsed = int((datetime.now() - ts).total_seconds())
                  status.append(f"  ·  {fmt_time(elapsed)} elapsed", style="dim")
              except (ValueError, IndexError):
                  pass
          if scanned > 0 and elapsed > 10:
              avg = elapsed / scanned
              eta = int(avg * (TOTAL_SOURCES - scanned))
              status.append(f"  ·  ~{fmt_time(eta)} left", style="dim")
          parts.append(status)
          if cur_scan:
              parts.append(Text(f"  scanning: {cur_scan}", style="dim"))

          parts.append(Rule(style="dim"))
          de = get_deleted_summary(Path(mp) / ".deleted")
          if de["count"]:
              dt = Text()
              dt.append(f"  {de['size']}  ·  ", style="dim")
              dt.append(f"{de['count']} snapshots", style="bold")
              if de["oldest"] and de["newest"]:
                  dt.append(f"  ·  {de['oldest']} → {de['newest']}", style="dim")
              parts.append(dt)

          parts.append(Rule(style="dim"))
          for line in lines[-(log_lines_available() - 1):]:
              parts.append(Text(f"  {line}", style="dim"))
          return Group(*parts)


      def build_backup_in_progress(
          lines: list[str], start_idx: int, elapsed: int, did: Optional[str],
      ) -> Group:
          parts = []
          parts.append(Rule(title="[bold cyan]Firesafe Backup[/bold cyan]", style="cyan"))

          total, used, avail, pct = get_disk_info(MOUNT_POINT)
          t = Text()
          t.append("✓  Mounted", style="bold green")
          if did:
              t.append(f"  ·  Drive {did}", style="bold")
          t.append(f"  ·  {total} total  ·  {avail} free", style="dim")
          parts.append(t)
          parts.append(ProgressBar(total=100, completed=pct, width=30))

          cur_source = get_current_source(lines, start_idx)
          done = count_cur_run_sources(lines, start_idx)

          status = Text()
          status.append("⏳  In progress", style="bold yellow")
          status.append(f"  ·  {fmt_time(elapsed)} elapsed", style="dim")
          if cur_source:
              status.append(f"  ·  {cur_source} ({min(done + 1, TOTAL_SOURCES)}/{TOTAL_SOURCES})", style="bold")
          parts.append(status)

          scan = parse_scan_file(str(Path(MOUNT_POINT) / ".firesafe-scan"))
          completed = get_completed_sources(lines, start_idx)
          completed_bytes = sum(c.get("bytes") or 0 for c in completed)

          progress_info = parse_last_progress(lines)
          current_bytes = progress_info["bytes"] if progress_info else 0
          current_speed = progress_info["speed_str"] if progress_info else ""

          if scan and scan["transfer_bytes"] > 0:
              total_xfer = scan["transfer_bytes"]
              xferred = completed_bytes + current_bytes
              parts.append(ProgressBar(total=total_xfer, completed=xferred, width=30))
              parts.append(Text(f"  {fmt_bytes(xferred)} / {fmt_bytes(total_xfer)}", style="bold"))

              if current_speed:
                  parts.append(Text(
                      f"  {current_speed}  ·  ~{fmt_time(max((total_xfer - xferred) * elapsed // max(xferred, 1), 0))} remaining",
                      style="dim",
                  ))
              elif xferred > 0 and elapsed > 30:
                  parts.append(Text(f"  ~{fmt_time((total_xfer - xferred) * elapsed // xferred)} remaining", style="dim"))
          else:
              if done > 0 and elapsed > 30:
                  rem = max(0, TOTAL_SOURCES - done)
                  est = (elapsed // done) * rem
                  parts.append(ProgressBar(total=TOTAL_SOURCES, completed=min(done, TOTAL_SOURCES), width=30))
                  parts.append(Text(f"  {done}/{TOTAL_SOURCES} sources", style="bold"))
                  if est > 0:
                      parts.append(Text(f"  ~{fmt_time(est)} remaining", style="dim"))

          parts.append(Rule(style="dim"))
          de = get_deleted_summary(Path(MOUNT_POINT) / ".deleted")
          if de["count"]:
              dt = Text()
              dt.append(f"  {de['size']}  ·  ", style="dim")
              dt.append(f"{de['count']} snapshots", style="bold")
              if de["oldest"] and de["newest"]:
                  dt.append(f"  ·  {de['oldest']} → {de['newest']}", style="dim")
              parts.append(dt)

          parts.append(Rule(style="dim"))
          n = log_lines_available()
          recent = []
          for c in reversed(completed[-5:]):
              dur_str = c.get("duration_str") or ""
              dur = f" ({dur_str})" if dur_str else ""
              recent.append(f"  {c['name']}{dur}")
          remaining_log = max(0, n - len(recent))
          for line in recent[:n]:
              parts.append(Text(line, style="dim"))
          if remaining_log > 0:
              for line in lines[-remaining_log:]:
                  parts.append(Text(f"  {line}", style="dim"))
          return Group(*parts)


      def build_complete(lines: list[str], comp: str, did: Optional[str]) -> Group:
          parts = []
          parts.append(Rule(title="[bold cyan]Firesafe Backup[/bold cyan]", style="cyan"))

          total, used, avail, pct = get_disk_info(MOUNT_POINT)
          t = Text()
          t.append("✓  Mounted", style="bold green")
          if did:
              t.append(f"  ·  Drive {did}", style="bold")
          t.append(f"  ·  {total} total  ·  {avail} free", style="dim")
          parts.append(t)
          parts.append(ProgressBar(total=100, completed=pct, width=30))

          start_idx = find_last_start(lines)
          completed = get_completed_sources(lines, start_idx) if start_idx >= 0 else []
          total_bytes = sum(c.get("bytes") or 0 for c in completed)

          t2 = Text()
          t2.append("✓  Complete", style="green")
          t2.append(f"  {comp}", style="dim")
          parts.append(t2)

          if total_bytes > 0:
              dur = 0
              for c in completed:
                  if c.get("duration_str"):
                      m = re.match(r"(?:(\d+)h)?\s*(?:(\d+)m)?\s*(?:(\d+)s)?", c["duration_str"])
                      if m:
                          dur += int(m.group(1) or 0) * 3600 + int(m.group(2) or 0) * 60 + int(m.group(3) or 0)
              if dur > 0:
                  parts.append(Text(f"  {fmt_bytes(total_bytes)}  ·  {fmt_time(dur)}", style="dim"))

          parts.append(Rule(style="dim"))
          de = get_deleted_summary(Path(MOUNT_POINT) / ".deleted")
          if de["count"]:
              dt = Text()
              dt.append(f"  {de['size']}  ·  ", style="dim")
              dt.append(f"{de['count']} snapshots", style="bold")
              if de["oldest"] and de["newest"]:
                  dt.append(f"  ·  {de['oldest']} → {de['newest']}", style="dim")
              parts.append(dt)

          parts.append(Rule(style="dim"))
          for line in lines[-(log_lines_available()):]:
              parts.append(Text(f"  {line}", style="dim"))
          return Group(*parts)


      def build_interrupted(
          lines: list[str], did: Optional[str],
      ) -> Group:
          parts = []
          parts.append(Rule(title="[bold cyan]Firesafe Backup[/bold cyan]", style="cyan"))

          total, used, avail, pct = get_disk_info(MOUNT_POINT)
          t = Text()
          t.append("✓  Mounted", style="bold green")
          if did:
              t.append(f"  ·  Drive {did}", style="bold")
          t.append(f"  ·  {total} total  ·  {avail} free", style="dim")
          parts.append(t)
          parts.append(ProgressBar(total=100, completed=pct, width=30))

          t2 = Text()
          t2.append("⏳  Interrupted — will resume within 2min", style="bold yellow")
          parts.append(t2)

          parts.append(Rule(style="dim"))
          de = get_deleted_summary(Path(MOUNT_POINT) / ".deleted")
          if de["count"]:
              dt = Text()
              dt.append(f"  {de['size']}  ·  ", style="dim")
              dt.append(f"{de['count']} snapshots", style="bold")
              if de["oldest"] and de["newest"]:
                  dt.append(f"  ·  {de['oldest']} → {de['newest']}", style="dim")
              parts.append(dt)

          parts.append(Rule(style="dim"))
          for line in lines[-(log_lines_available()):]:
              parts.append(Text(f"  {line}", style="dim"))
          return Group(*parts)


      def build_no_markers(lines: list[str], did: Optional[str]) -> Group:
          parts = []
          parts.append(Rule(title="[bold cyan]Firesafe Backup[/bold cyan]", style="cyan"))

          total, used, avail, pct = get_disk_info(MOUNT_POINT)
          t = Text()
          t.append("✓  Mounted", style="bold green")
          if did:
              t.append(f"  ·  Drive {did}", style="bold")
          t.append(f"  ·  {total} total  ·  {avail} free", style="dim")
          parts.append(t)
          parts.append(ProgressBar(total=100, completed=pct, width=30))

          parts.append(Text("No backup in progress", style="dim"))

          parts.append(Rule(style="dim"))
          de = get_deleted_summary(Path(MOUNT_POINT) / ".deleted")
          if de["count"]:
              dt = Text()
              dt.append(f"  {de['size']}  ·  ", style="dim")
              dt.append(f"{de['count']} snapshots", style="bold")
              if de["oldest"] and de["newest"]:
                  dt.append(f"  ·  {de['oldest']} → {de['newest']}", style="dim")
              parts.append(dt)

          parts.append(Rule(style="dim"))
          for line in lines[-(log_lines_available()):]:
              parts.append(Text(f"  {line}", style="dim"))
          return Group(*parts)


      def marker_exists(path_str: str) -> bool:
          try:
              return Path(path_str).exists()
          except OSError:
              return False


      def build_status() -> Group:
          lines = read_log()
          start_idx = find_last_start(lines)

          if not is_mounted(MOUNT_POINT):
              return build_not_mounted(lines)

          # Check if mount is stale (I/O errors on any access → treat as not mounted)
          mp = Path(MOUNT_POINT)
          try:
              next(mp.iterdir(), None)
          except OSError:
              return build_not_mounted(lines)

          did, comp, start = read_markers(MOUNT_POINT)
          scanning_marker = mp / ".firesafe-backup-scanning"
          interrupted_marker = mp / ".firesafe-backup-interrupted"

          if marker_exists(str(scanning_marker)) or (start_idx >= 0 and "Scanning:" in lines[start_idx]):
              return build_scanning(lines, start_idx, did)

          if comp:
              return build_complete(lines, comp, did)

          if marker_exists(str(interrupted_marker)) and get_service_state() not in ("activating", "active"):
              return build_interrupted(lines, did)

          if start:
              try:
                  sd = datetime.fromisoformat(start)
                  elapsed = max(0, int((datetime.now(timezone.utc) - sd).total_seconds()))
              except Exception:
                  elapsed = 0
              return build_backup_in_progress(lines, start_idx, elapsed, did)

          return build_no_markers(lines, did)


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
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${backupScript}";
        TimeoutStopSec = 30;
        StandardOutput = "journal+console";
        StandardError = "journal+console";
        Environment = "PATH=${pkgs.coreutils}/bin:${pkgs.util-linux}/bin:${pkgs.gnused}/bin:${pkgs.gnugrep}/bin:${pkgs.gawk}/bin";
      };
    };

    # Auto-resume: if the backup was interrupted (e.g. by `nr` rebuild), restart it.
    systemd.timers.firesafe-backup-resume = {
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = "2min";
      };
    };

    systemd.services.firesafe-backup-resume = {
      description = "Resume firesafe backup if interrupted";
      # No after/wants — resume script conditionally starts backup via systemctl start
      script = ''
        set -e
        if ! mountpoint -q "${cfg.mountPoint}" 2>/dev/null; then
          exit 0
        fi
        if ! [ -f "${cfg.mountPoint}/.firesafe-backup-interrupted" ]; then
          exit 0
        fi
        if systemctl is-active firesafe-backup.service >/dev/null 2>&1; then
          exit 0
        fi
        # Also check: never resume if complete marker is newer than interrupted
        if [ -f "${cfg.mountPoint}/.firesafe-backup-complete" ] &&
           [ "${cfg.mountPoint}/.firesafe-backup-complete" -nt "${cfg.mountPoint}/.firesafe-backup-interrupted" ]; then
          exit 0
        fi
        touch /run/firesafe-resume
        systemctl start firesafe-backup.service
      '';
      serviceConfig = {
        Type = "oneshot";
        StandardOutput = "journal+console";
        Environment = "PATH=${pkgs.coreutils}/bin:${pkgs.systemd}";
      };
    };

    environment.systemPackages = [statusScript reclaimScript deletedScript ejectScript];

    systemd.tmpfiles.rules = [
      "f /var/log/firesafe-backup.log 0640 root users -"
    ];
  };
}
