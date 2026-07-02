{
  pkgs,
  lib,
  cfg,
}:
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


  def log_tail(n: int) -> list[str]:
      lines = read_log()
      filtered = [line for line in lines if re.match(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}", line)]
      return filtered[-n:] if n > 0 else []


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
              results.append({"name": m.group(1), "duration": None, "bytes": None, "files": 0})
          sm = re.match(
              r".*: (SUCCESS|FAILED)\s*(?:\((.+)\))?",
              lines[i],
          )
          if sm and results:
              results[-1]["status"] = sm.group(1)
              results[-1]["duration_str"] = sm.group(2)
          fm = re.match(r"^\s*Number of regular files transferred:\s+([\d,]+)", lines[i])
          if fm and results:
              results[-1]["files"] = int(fm.group(1).replace(",", ""))
          tm = re.match(r"^\s*Total transferred file size:\s+([\d,]+)", lines[i])
          if tm and results:
              results[-1]["bytes"] = int(tm.group(1).replace(",", ""))
          bm = re.match(r"^\s*Total bytes sent:\s+([\d,]+)", lines[i])
          if bm and results:
              results[-1]["bytes"] = int(bm.group(1).replace(",", ""))
      if results and results[-1].get("status") is None:
          results.pop()
      return results


  def fmt_source_line(c: dict) -> str:
      parts_list = [c["name"]]
      size = c.get("bytes")
      if size is not None and size > 0:
          parts_list.append(fmt_bytes(size))
      files = c.get("files")
      if files is not None and files > 0:
          parts_list.append(f"{files:,} files")
      dur = c.get("duration_str")
      if dur:
          parts_list.append(f"\u00b7  {dur}")
      return "  \u2713 " + "  ".join(parts_list)


  def make_progress_bar(completed: int, total: int) -> Text:
      frac = completed / total if total > 0 else 0
      term_w = shutil.get_terminal_size((80, 25)).columns
      width = max(10, term_w // 2)
      filled = min(int(width * frac), width)
      t = Text()
      t.append("\u2588" * filled, style="green")
      t.append("\u2591" * (width - filled), style="dim")
      t.append(f"  {int(frac * 100)}%", style="bold")
      return t


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


  def parse_rsync_eta(s: str) -> int:
      parts = s.split(":")
      if len(parts) == 3:
          return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
      if len(parts) == 2:
          return int(parts[0]) * 60 + int(parts[1])
      return 0


  def parse_last_progress(lines: list[str]) -> Optional[dict]:
      for line in reversed(lines):
          m = re.match(
              r"^\s*([\d,]+)\s+(\d+)%\s+([\d.]+)([KMGT]?B/s)\s+"
              r"([\d:]+)(?:\s+\(([^)]*)\))?",
              line,
          )
          if m:
              bytes_val = int(m.group(1).replace(",", ""))
              pct = int(m.group(2))
              speed_str = m.group(3) + " " + m.group(4)
              eta_secs = parse_rsync_eta(m.group(5))
              remaining = m.group(6) or ""
              return {
                  "bytes": bytes_val,
                  "pct": pct,
                  "speed_str": speed_str,
                  "eta_secs": eta_secs,
                  "remaining": remaining,
              }
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
              t.append("\u26a0  Checking filesystem", style="bold yellow")
              if bb > 0:
                  t.append(f"  \u00b7  {fmt_bytes(bb)} read", style="bold")
              parts.append(t)
              if fsck["elapsed_secs"] and bb > 0:
                  speed = fmt_bytes(bb // fsck["elapsed_secs"]) + "/s"
                  parts.append(Text(f"  {speed}  \u00b7  running {fsck['elapsed']}", style="dim"))
              else:
                  parts.append(Text(f"  running {fsck['elapsed']}", style="dim"))
          else:
              parts.append(Text("\u23f3  Starting backup...", style="bold yellow"))
      else:
          parts.append(Text("\u2717  Not mounted", style="bold red"))
      parts.append(Rule(style="dim"))
      for line in log_tail(log_lines_available()):
          parts.append(Text(f"  {line}", style="dim"))
      return Group(*parts)


  def build_scanning(lines: list[str], start_idx: int, did: Optional[str]) -> Group:
      parts = []
      parts.append(Rule(title="[bold cyan]Firesafe Backup[/bold cyan]", style="cyan"))
      mp = MOUNT_POINT
      total, used, avail, pct = get_disk_info(mp)
      t = Text()
      t.append("\u2713  Mounted", style="bold green")
      if did:
          t.append(f"  \u00b7  Drive {did}", style="bold")
      t.append(f"  \u00b7  {total} total  \u00b7  {avail} free", style="dim")
      parts.append(t)
      parts.append(make_progress_bar(pct, 100))

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

      status = Text(f"\u23f3  Scanning ({scanned}/{TOTAL_SOURCES})", style="bold yellow")
      elapsed = 0
      if scanning_idx >= 0:
          try:
              ts_str = lines[scanning_idx][:19]
              ts = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
              elapsed = int((datetime.now() - ts).total_seconds())
              status.append(f"  \u00b7  {fmt_time(elapsed)} elapsed", style="dim")
          except (ValueError, IndexError):
              pass
      if scanned > 0 and elapsed > 10:
          avg = elapsed / scanned
          eta = int(avg * (TOTAL_SOURCES - scanned))
          status.append(f"  \u00b7  ~{fmt_time(eta)} left", style="dim")
      parts.append(status)
      if cur_scan:
          parts.append(Text(f"  scanning: {cur_scan}", style="dim"))

      parts.append(Rule(style="dim"))
      de = get_deleted_summary(Path(mp) / ".deleted")
      if de["count"]:
          dt = Text()
          dt.append(f"  {de['size']}  \u00b7  ", style="dim")
          dt.append(f"{de['count']} snapshots", style="bold")
          if de["oldest"] and de["newest"]:
              dt.append(f"  \u00b7  {de['oldest']} \u2192 {de['newest']}", style="dim")
          parts.append(dt)

      parts.append(Rule(style="dim"))
      for line in log_tail(log_lines_available() - 1):
          parts.append(Text(f"  {line}", style="dim"))
      return Group(*parts)


  def build_backup_in_progress(
      lines: list[str], start_idx: int, elapsed: int, did: Optional[str],
  ) -> Group:
      parts = []
      parts.append(Rule(title="[bold cyan]Firesafe Backup[/bold cyan]", style="cyan"))

      total, used, avail, pct = get_disk_info(MOUNT_POINT)
      t = Text()
      t.append("\u2713  Mounted", style="bold green")
      if did:
          t.append(f"  \u00b7  Drive {did}", style="bold")
      t.append(f"  \u00b7  {total} total  \u00b7  {avail} free", style="dim")
      parts.append(t)
      parts.append(make_progress_bar(pct, 100))

      cur_source = get_current_source(lines, start_idx)
      done = count_cur_run_sources(lines, start_idx)

      status = Text()
      status.append("\u23f3  In progress", style="bold yellow")
      status.append(f"  \u00b7  {fmt_time(elapsed)} elapsed", style="dim")
      if cur_source:
          status.append(f"  \u00b7  {cur_source} ({min(done + 1, TOTAL_SOURCES)}/{TOTAL_SOURCES})", style="bold")
      parts.append(status)

      scan = parse_scan_file(str(Path(MOUNT_POINT) / ".firesafe-scan"))
      completed = get_completed_sources(lines, start_idx)
      completed_bytes = sum(c.get("bytes") or 0 for c in completed)

      progress_info = parse_last_progress(lines)
      current_bytes = progress_info["bytes"] if progress_info else 0
      current_speed = progress_info["speed_str"] if progress_info else ""

      if cur_source:
          src = Text()
          src.append("  \u25b8  ", style="bold")
          src.append(cur_source, style="bold white")
          if current_speed:
              src.append(f"  ({current_speed})", style="dim")
          src.append(f"  [{min(done + 1, TOTAL_SOURCES)}/{TOTAL_SOURCES}]", style="dim")
          parts.append(src)

      if scan and scan["transfer_bytes"] > 0:
          total_xfer = scan["transfer_bytes"]
          xferred = completed_bytes + current_bytes
          parts.append(make_progress_bar(xferred, total_xfer))
          parts.append(Text(f"  {fmt_bytes(xferred)} / {fmt_bytes(total_xfer)}", style="bold"))

          if current_speed:
              parts.append(Text(
                  f"  {current_speed}  \u00b7  ~{fmt_time(max((total_xfer - xferred) * elapsed // max(xferred, 1), 0))} remaining",
                  style="dim",
              ))
          elif xferred > 0 and elapsed > 30:
              parts.append(Text(f"  ~{fmt_time((total_xfer - xferred) * elapsed // xferred)} remaining", style="dim"))
      elif progress_info and progress_info["pct"] > 0:
          pct = progress_info["pct"]
          parts.append(make_progress_bar(pct, 100))
          t_bytes = Text()
          t_bytes.append(f"  {fmt_bytes(current_bytes)} transferred", style="bold")
          remaining_str = progress_info.get("remaining", "")
          if remaining_str:
              m_rem = re.search(r"(?:ir-chk|to-chk)=([\d,]+)/([\d,]+)", remaining_str)
              if m_rem:
                  t_bytes.append(f"  \u00b7  {m_rem.group(1)} / {m_rem.group(2)} files", style="dim")
          parts.append(t_bytes)
          eta = progress_info.get("eta_secs", 0)
          if current_speed and eta > 0:
              parts.append(Text(f"  {current_speed}  \u00b7  ~{fmt_time(eta)} remaining", style="dim"))
          elif current_speed:
              parts.append(Text(f"  {current_speed}", style="dim"))
          elif eta > 0:
              parts.append(Text(f"  ~{fmt_time(eta)} remaining", style="dim"))
      else:
          if done > 0 and elapsed > 30:
              rem = max(0, TOTAL_SOURCES - done)
              est = (elapsed // done) * rem
              parts.append(make_progress_bar(min(done, TOTAL_SOURCES), TOTAL_SOURCES))
              parts.append(Text(f"  {done}/{TOTAL_SOURCES} sources", style="bold"))
              if est > 0:
                  parts.append(Text(f"  ~{fmt_time(est)} remaining", style="dim"))

      parts.append(Rule(style="dim"))
      de = get_deleted_summary(Path(MOUNT_POINT) / ".deleted")
      if de["count"]:
          dt = Text()
          dt.append(f"  {de['size']}  \u00b7  ", style="dim")
          dt.append(f"{de['count']} snapshots", style="bold")
          if de["oldest"] and de["newest"]:
              dt.append(f"  \u00b7  {de['oldest']} \u2192 {de['newest']}", style="dim")
          parts.append(dt)

      parts.append(Rule(style="dim"))
      n = log_lines_available()
      recent = min(len(completed), 5)
      for c in reversed(completed[-recent:]):
          parts.append(Text(fmt_source_line(c), style="dim"))
      remaining_log = max(0, n - recent)
      if remaining_log > 0:
          for line in log_tail(remaining_log):
              parts.append(Text(f"  {line}", style="dim"))
      return Group(*parts)


  def build_complete(lines: list[str], comp: str, did: Optional[str]) -> Group:
      parts = []
      parts.append(Rule(title="[bold cyan]Firesafe Backup[/bold cyan]", style="cyan"))

      total, used, avail, pct = get_disk_info(MOUNT_POINT)
      t = Text()
      t.append("\u2713  Mounted", style="bold green")
      if did:
          t.append(f"  \u00b7  Drive {did}", style="bold")
      t.append(f"  \u00b7  {total} total  \u00b7  {avail} free", style="dim")
      parts.append(t)
      parts.append(make_progress_bar(pct, 100))

      start_idx = find_last_start(lines)
      completed = get_completed_sources(lines, start_idx) if start_idx >= 0 else []
      total_bytes = sum(c.get("bytes") or 0 for c in completed)

      # total elapsed from start to completion marker
      start_marker = Path(MOUNT_POINT) / ".firesafe-backup-start"
      total_dur = ""
      if start_marker.exists():
          try:
              st = start_marker.read_text().strip()
              sd = datetime.fromisoformat(st)
              cd = datetime.fromisoformat(comp) if comp else None
              if cd:
                  td = int((cd - sd).total_seconds())
                  if td > 0:
                      total_dur = f"  \u00b7  {fmt_time(td)}"
          except Exception:
              pass

      t2 = Text()
      t2.append("\u2713  Complete", style="green")
      t2.append(f"  {comp}", style="dim")
      if total_dur:
          t2.append(total_dur, style="dim")
      parts.append(t2)

      if total_bytes > 0:
          parts.append(Text(f"  {fmt_bytes(total_bytes)} total", style="dim"))

      parts.append(Rule(style="dim"))
      for c in completed:
          parts.append(Text(fmt_source_line(c), style="dim"))
      parts.append(Rule(style="dim"))
      de = get_deleted_summary(Path(MOUNT_POINT) / ".deleted")
      if de["count"]:
          dt = Text()
          dt.append(f"  {de['size']}  \u00b7  ", style="dim")
          dt.append(f"{de['count']} snapshots", style="bold")
          if de["oldest"] and de["newest"]:
              dt.append(f"  \u00b7  {de['oldest']} \u2192 {de['newest']}", style="dim")
          parts.append(dt)

      parts.append(Rule(style="dim"))
      spare = max(3, log_lines_available() - len(completed))
      for line in log_tail(spare):
          parts.append(Text(f"  {line}", style="dim"))
      return Group(*parts)


  def build_interrupted(
      lines: list[str], did: Optional[str],
  ) -> Group:
      parts = []
      parts.append(Rule(title="[bold cyan]Firesafe Backup[/bold cyan]", style="cyan"))

      total, used, avail, pct = get_disk_info(MOUNT_POINT)
      t = Text()
      t.append("\u2713  Mounted", style="bold green")
      if did:
          t.append(f"  \u00b7  Drive {did}", style="bold")
      t.append(f"  \u00b7  {total} total  \u00b7  {avail} free", style="dim")
      parts.append(t)
      parts.append(make_progress_bar(pct, 100))

      t2 = Text()
      t2.append("\u23f3  Interrupted \u2014 will resume within 2min", style="bold yellow")
      parts.append(t2)

      parts.append(Rule(style="dim"))
      de = get_deleted_summary(Path(MOUNT_POINT) / ".deleted")
      if de["count"]:
          dt = Text()
          dt.append(f"  {de['size']}  \u00b7  ", style="dim")
          dt.append(f"{de['count']} snapshots", style="bold")
          if de["oldest"] and de["newest"]:
              dt.append(f"  \u00b7  {de['oldest']} \u2192 {de['newest']}", style="dim")
          parts.append(dt)

      parts.append(Rule(style="dim"))
      for line in log_tail(log_lines_available()):
          parts.append(Text(f"  {line}", style="dim"))
      return Group(*parts)


  def build_no_markers(lines: list[str], did: Optional[str]) -> Group:
      parts = []
      parts.append(Rule(title="[bold cyan]Firesafe Backup[/bold cyan]", style="cyan"))

      total, used, avail, pct = get_disk_info(MOUNT_POINT)
      t = Text()
      t.append("\u2713  Mounted", style="bold green")
      if did:
          t.append(f"  \u00b7  Drive {did}", style="bold")
      t.append(f"  \u00b7  {total} total  \u00b7  {avail} free", style="dim")
      parts.append(t)
      parts.append(make_progress_bar(pct, 100))

      t2 = Text()
      t2.append("No backup running", style="bold")
      parts.append(t2)

      parts.append(Rule(style="dim"))
      de = get_deleted_summary(Path(MOUNT_POINT) / ".deleted")
      if de["count"]:
          dt = Text()
          dt.append(f"  {de['size']}  \u00b7  ", style="dim")
          dt.append(f"{de['count']} snapshots", style="bold")
          if de["oldest"] and de["newest"]:
              dt.append(f"  \u00b7  {de['oldest']} \u2192 {de['newest']}", style="dim")
          parts.append(dt)

      parts.append(Rule(style="dim"))
      spare = max(3, log_lines_available() - 2)
      for line in log_tail(spare):
          parts.append(Text(f"  {line}", style="dim"))
      return Group(*parts)


  def main() -> None:
      watch = "-w" in sys.argv[1:] or "--watch" in sys.argv[1:]

      lines = read_log()
      mp = MOUNT_POINT

      if not is_mounted(mp):
          if watch:
              with Live(build_not_mounted(lines), refresh_per_second=4, screen=True) as live:
                  while True:
                      lines = read_log()
                      live.update(build_not_mounted(lines))
                      time.sleep(2)
          else:
              console.print(build_not_mounted(lines))
          return

      did, comp, start = read_markers(mp)

      if not start and not comp:
          if watch:
              with Live(build_no_markers(lines, did), refresh_per_second=4, screen=True) as live:
                  while True:
                      lines = read_log()
                      did, comp, start = read_markers(mp)
                      if start or comp:
                          break
                      live.update(build_no_markers(lines, did))
                      time.sleep(2)
          else:
              console.print(build_no_markers(lines, did))
          return

      if Path(mp / ".firesafe-backup-scanning").exists():
          if watch:
              start_idx = find_last_start(lines)
              with Live(build_scanning(lines, start_idx, did), refresh_per_second=4, screen=True) as live:
                  while True:
                      lines = read_log()
                      start_idx = find_last_start(lines)
                      if comp and not Path(mp / ".firesafe-backup-scanning").exists():
                          break
                      live.update(build_scanning(lines, start_idx, did))
                      time.sleep(2)
          else:
              start_idx = find_last_start(lines)
              console.print(build_scanning(lines, start_idx, did))
          return

      if comp:
          if watch:
              with Live(build_complete(lines, comp, did), refresh_per_second=4, screen=True) as live:
                  while True:
                      lines = read_log()
                      did, comp, start = read_markers(mp)
                      if not comp:
                          break
                      live.update(build_complete(lines, comp, did))
                      time.sleep(2)
          else:
              console.print(build_complete(lines, comp, did))
          return

      if Path(mp / ".firesafe-backup-interrupted").exists():
          if watch:
              with Live(build_interrupted(lines, did), refresh_per_second=4, screen=True) as live:
                  while True:
                      lines = read_log()
                      if not Path(mp / ".firesafe-backup-interrupted").exists():
                          break
                      live.update(build_interrupted(lines, did))
                      time.sleep(2)
          else:
              console.print(build_interrupted(lines, did))
          return

      if start:
          start_idx = find_last_start(lines)
          elapsed = 0
          try:
              sd = datetime.fromisoformat(start)
              elapsed = max(0, int((datetime.now(timezone.utc) - sd).total_seconds()))
          except Exception:
              pass

          if watch:
              with Live(build_backup_in_progress(lines, start_idx, elapsed, did), refresh_per_second=4, screen=True) as live:
                  while True:
                      lines = read_log()
                      did, comp, start = read_markers(mp)
                      if comp:
                          break
                      if start:
                          try:
                              sd = datetime.fromisoformat(start)
                              elapsed = max(0, int((datetime.now(timezone.utc) - sd).total_seconds()))
                          except Exception:
                              pass
                      start_idx = find_last_start(lines)
                      live.update(build_backup_in_progress(lines, start_idx, elapsed, did))
                      time.sleep(2)
          else:
              console.print(build_backup_in_progress(lines, start_idx, elapsed, did))
          return

      console.print(build_no_markers(lines, did))


  if __name__ == "__main__":
      main()
''
