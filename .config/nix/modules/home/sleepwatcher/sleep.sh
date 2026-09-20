#!/usr/bin/env bash
# SleepWatcher sleep hook — eject the 'Extra Space' volume before the Mac sleeps.
# Only ever ejects VOLUME disk8s1 (never the whole device /dev/disk7).
LOG=/tmp/sleepwatcher.log
VOL="disk8s1"

if ! /usr/sbin/diskutil list "$VOL" >/dev/null 2>&1; then
  echo "already unmounted $(date)" >>"$LOG"
  exit 0
fi

if /usr/sbin/diskutil info "$VOL" 2>/dev/null | /usr/bin/grep -q "Mounted:"; then
  /usr/sbin/diskutil eject "$VOL" >/dev/null 2>&1
  echo "ejected $(date)" >>"$LOG"
else
  echo "already unmounted $(date)" >>"$LOG"
fi
exit 0
