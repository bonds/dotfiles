#!/usr/bin/env bash
# SleepWatcher wake hook (`sleepwatcher -w`): bring 'Extra Space' back if the
# drive is still attached. If it was unplugged while the Mac slept - the normal
# case - no device shows up and this exits 0 quietly.
#
# The volume is looked up by name on every attempt rather than remembered by
# diskN: after the sleep hook's eject the drive is re-enumerated with a fresh
# identifier, and USB devices take a moment to come back. Bounded at ~10 s so
# wake is never held up on a device that is not coming back, and it always
# exits 0 - a detached drive is not an error.
set -u
. "${HOME}/.config/sleepwatcher/common.sh"

MAX_ATTEMPTS=10

# An unclean removal can leave an empty /Volumes/Extra Space behind, and macOS
# then mounts the returning volume as "/Volumes/Extra Space 1". rmdir only ever
# removes an empty directory, and fails harmlessly on a real mount point.
if [ -d "$VOL_PATH" ]; then
  /bin/rmdir "$VOL_PATH" 2>/dev/null && log "wake: removed stale mount point ${VOL_PATH}"
fi

attempt=0
while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
  attempt=$((attempt + 1))
  if volume_mounted; then
    log "wake: ${VOL_NAME} mounted (attempt ${attempt})"
    exit 0
  fi
  dev=$(unmounted_volume_device)
  if [ -n "$dev" ]; then
    /usr/sbin/diskutil mount "$dev" >/dev/null 2>&1
    rc=$?
    if volume_mounted; then
      log "wake: mounted ${dev} (attempt ${attempt})"
      exit 0
    fi
    log "wake: mount ${dev} failed exit ${rc} (attempt ${attempt})"
  fi
  /bin/sleep 1
done

log "wake: ${VOL_NAME} not remounted after ${MAX_ATTEMPTS}s (drive detached during sleep, or not mountable)"
exit 0
