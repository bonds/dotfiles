#!/usr/bin/env bash
set -euo pipefail

# Nightly photo backup to sophrosyne — SFTP transport.
#
# photo-export (PhotoKit-native Swift CLI) streams ALL assets (local + iCloud-only)
# in-memory over SFTP to /dragon/media/photos as photo-backup. No SMB mount, no
# local temp copies (no SSD wear). Config (remoteHost/remoteUser) is written by
# home-manager; the app reads it because `open --args` doesn't forward args.
# Manifest (~/.cache/photo-export-manifest.txt) makes runs resumable; each file
# is verified against the server (size stat) so only genuinely-missing files are
# uploaded.

LOCKDIR="/tmp/photos-backup.lock"
LOGFILE="$HOME/Library/Logs/photos-backup.out.log"
ERRFILE="$HOME/Library/Logs/photos-backup.err.log"
# photo-export appends its own log to /tmp/photo-export.log (fopen(..., "a") at
# the top of pkgs/photokit-export/photo-export.swift, fflush'ed per line), and
# `open -W` does NOT report the app's exit status — so this log is the only place
# a run's real outcome is visible. Copied to RUNCOPY per run because macOS clears
# /tmp at boot.
RUNLOG="/tmp/photo-export.log"
RUNCOPY="$HOME/Library/Logs/photos-backup.run.log"

# The app is installed by home-manager into "Applications/Home Manager Apps/"
# (that's what LaunchServices/`open` resolve). Fall back to a plain
# ~/Applications copy if it exists.
if [ -d "$HOME/Applications/Home Manager Apps/photo-export.app" ]; then
  APP="$HOME/Applications/Home Manager Apps/photo-export.app"
elif [ -d "$HOME/Applications/photo-export.app" ]; then
  APP="$HOME/Applications/photo-export.app"
else
  APP=""
fi

# Robust lock: store our PID inside the lock dir. If the lock exists but the
# PID inside it is no longer a live photo-backup process, the previous run was
# killed (SIGKILL/power loss bypasses `trap ... EXIT`) — reclaim the stale
# lock instead of skipping forever.
acquire_lock() {
  if mkdir "$LOCKDIR" 2>/dev/null; then
    echo $$ > "$LOCKDIR/pid"
    return 0
  fi
  local oldpid
  oldpid=$(cat "$LOCKDIR/pid" 2>/dev/null || echo "")
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    return 1   # genuinely still running
  fi
  # stale lock — remove and retry once
  echo "$(date) — stale lock (pid $oldpid) from a killed run; reclaiming" >> "$LOGFILE"
  rm -rf "$LOCKDIR"
  mkdir "$LOCKDIR" 2>/dev/null || return 1
  echo $$ > "$LOCKDIR/pid"
  return 0
}

if ! acquire_lock; then
  echo "$(date) — backup already running, skipping" >> "$LOGFILE"
  exit 0
fi
trap 'rm -rf "$LOCKDIR"' EXIT

if [ ! -x "$APP/Contents/MacOS/photo-export" ]; then
  echo "$(date) — backup FAILED (exit 1): photo-export.app missing at $APP; nothing to run" >> "$LOGFILE"
  exit 1
fi

# Confirm SFTP is configured (not accidentally falling back to a nonexistent SMB mount).
if [ ! -f "$HOME/Library/Application Support/photo-export/config.toml" ] || \
   ! grep -q '^remoteHost' "$HOME/Library/Application Support/photo-export/config.toml"; then
  echo "$(date) — backup FAILED (exit 1): config.toml missing remoteHost (SFTP not configured); refusing to run" >> "$LOGFILE"
  exit 1
fi

echo "$(date) — launching photo-export over SFTP..." >> "$LOGFILE"

# MUST launch via `open` so macOS registers the app identity with TCC (direct
# exec of the binary gets PHAuthorizationStatusDenied). Use the EXPLICIT app
# path — `open -a photo-export` can resolve to the Home Manager Apps copy
# (stale) instead of the nix-store symlink. -W blocks until photo-export exits.
#
# `open` returns 0 as soon as the app has been launched — it does NOT propagate
# the app's exit status — so the run is judged from photo-export's own log:
# every completed run ends with
#   photo-export: SUMMARY exported=<n> skipped=<n> failed=<n>
# while a fatal error exits(1) before that line (TCC denial, no SFTP session,
# unwritable dest). Nothing else counts as success: an unconditional "backup
# complete" is how a dead backup looked healthy for weeks.
START=$(wc -c < "$RUNLOG" 2>/dev/null || echo 0)
OPEN_RC=0
open -j -W "$APP" 2>>"$ERRFILE" >>"$LOGFILE" || OPEN_RC=$?

RUN_OUT=$(tail -c "+$((START + 1))" "$RUNLOG" 2>/dev/null || true)
printf '%s\n' "$RUN_OUT" > "$RUNCOPY"
SUMMARY=$(printf '%s\n' "$RUN_OUT" | grep -m1 '^photo-export: SUMMARY exported=' || true)
FATAL=$(printf '%s\n' "$RUN_OUT" | grep -m1 'FATAL' || true)

if [ "$OPEN_RC" -ne 0 ]; then
  echo "$(date) — backup FAILED (exit $OPEN_RC): open could not launch or finish $APP; see $ERRFILE" >> "$LOGFILE"
  exit "$OPEN_RC"
fi

if [ -z "$SUMMARY" ]; then
  echo "$(date) — backup FAILED (exit 1): photo-export exited before SUMMARY${FATAL:+ — $FATAL}; see $RUNCOPY" >> "$LOGFILE"
  exit 1
fi

if printf '%s' "$SUMMARY" | grep -qE 'failed=[1-9]'; then
  echo "$(date) — backup FAILED (exit 1): $SUMMARY; see $RUNCOPY" >> "$LOGFILE"
  exit 1
fi

echo "$(date) — backup complete (${SUMMARY#photo-export: })" >> "$LOGFILE"
