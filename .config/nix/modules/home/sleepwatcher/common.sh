#!/usr/bin/env bash
# Shared helpers for the sleepwatcher sleep/wake hooks. Sourced, never run.
#
# The volume is resolved by NAME at runtime and never by a hardcoded
# diskN[sM] identifier: those are reassigned every time the drive is
# re-attached, which is exactly how the previous version of these hooks broke
# (it hardcoded disk8s1, so every run took the "already unmounted" branch and
# the drive was never once ejected).

VOL_NAME="Extra Space"
VOL_PATH="/Volumes/${VOL_NAME}"
LOG="${HOME}/Library/Logs/sleepwatcher-hooks.log"
MAX_LOG_BYTES=1048576

# One timestamped line per event; rotate by truncation so the log is bounded.
log() {
  local size
  size=$(/usr/bin/stat -f %z "$LOG" 2>/dev/null || /bin/echo 0)
  if [ "$size" -gt "$MAX_LOG_BYTES" ]; then
    /bin/mv -f "$LOG" "${LOG}.1" 2>/dev/null || true
  fi
  /bin/echo "$(/bin/date '+%Y-%m-%d %H:%M:%S') $*" >>"$LOG"
}

# True while a filesystem is mounted at VOL_PATH.
volume_mounted() {
  /sbin/mount | /usr/bin/grep -qF " on ${VOL_PATH} ("
}

# Device node of the volume at VOL_PATH, e.g. /dev/disk6s1; empty if unmounted.
volume_device() {
  /usr/sbin/diskutil info "$VOL_PATH" 2>/dev/null |
    /usr/bin/awk -F': +' '/^ *Device Node:/ {print $2; exit}'
}

# Whole physical disk behind a device node, e.g. /dev/disk6s1 -> disk5, by
# following volume -> APFS container -> APFS physical store -> whole disk.
whole_disk() {
  local dev="${1:-}" next i
  dev="${dev##*/}"
  for i in 1 2 3 4; do
    next=$(/usr/sbin/diskutil info "$dev" 2>/dev/null |
      /usr/bin/awk -F': +' '/APFS Physical Store:/ {print $2; exit}')
    if [ -z "$next" ]; then
      next=$(/usr/sbin/diskutil info "$dev" 2>/dev/null |
        /usr/bin/awk -F': +' '/Part of Whole:/ {print $2; exit}')
    fi
    [ -n "$next" ] || break
    [ "$next" = "$dev" ] && break
    dev="$next"
  done
  /bin/echo "$dev"
}

# Identifier of an attached but unmounted volume named VOL_NAME; empty if the
# drive is not attached at all. Re-read on every attempt: an eject followed by
# a re-attach hands the drive a fresh diskN.
unmounted_volume_device() {
  /usr/sbin/diskutil list 2>/dev/null |
    /usr/bin/awk -v n="$VOL_NAME" '$0 ~ n && $NF ~ /^disk[0-9]+s[0-9]+$/ {print $NF; exit}'
}

# Bounded graceful unmount. `diskutil unmount` can block for up to a minute
# waiting for Disk Arbitration dissenters (man diskutil), while sleepwatcher
# only gives the sleep hook 15 s before the system forces sleep (man
# sleepwatcher), so cap each attempt and let the caller fall through to a
# forced unmount. Killing the diskutil *client* does not abort the unmount
# itself, it only stops us from waiting for it; 124 is reported as a timeout.
unmount_graceful_bounded() {
  local seconds="$1" pid waited=0
  /usr/sbin/diskutil unmount "$VOL_PATH" >/dev/null 2>&1 &
  pid=$!
  while /bin/kill -0 "$pid" 2>/dev/null && [ "$waited" -lt "$seconds" ]; do
    /bin/sleep 1
    waited=$((waited + 1))
  done
  if /bin/kill -0 "$pid" 2>/dev/null; then
    /bin/kill "$pid" 2>/dev/null || true
    return 124
  fi
  wait "$pid"
}
