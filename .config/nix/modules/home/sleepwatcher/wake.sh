#!/usr/bin/env bash
# SleepWatcher wake hook — remount the 'Extra Space' volume.
# No UUID hardcoded (the Volume UUID changes on reformat); address the
# volume by its mount point "/Volumes/Extra Space" or device disk8s1.
# Only ever touches volume disk8s1 / its mount point, never whole device disk7.
LOG=/tmp/sleepwatcher.log

# Common case: macOS automounts on wake before this hook runs — skip the loop.
if /usr/sbin/diskutil info disk8s1 2>/dev/null | /usr/bin/grep -q "Mounted:"; then
  echo "already mounted (automount) $(date)" >>"$LOG"
  exit 0
fi

# Otherwise retry ~30 attempts at 2s apart (~60s total), trying the mount
# point first, then the device identifier.
for _ in $(seq 1 30); do
  if /usr/sbin/diskutil mount "/Volumes/Extra Space" >/dev/null 2>&1; then
    echo "mounted (via mount point) $(date)" >>"$LOG"
    exit 0
  fi
  if /usr/sbin/diskutil mount disk8s1 >/dev/null 2>&1; then
    echo "mounted (via disk8s1) $(date)" >>"$LOG"
    exit 0
  fi
  sleep 2
done

echo "FAILED to remount $(date)" >>"$LOG"
exit 1