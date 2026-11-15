#!/usr/bin/env bash
# SleepWatcher sleep hook (`sleepwatcher -s`): get the 'Extra Space' volume
# cleanly off the bus before the Mac suspends, so unplugging the drive while
# the machine is asleep cannot produce "Disk Not Ejected Properly".
#
# Backstop, not the primary trigger: the display-sleep hook (`-S`) normally
# ejects first, but sleepwatcher is not reliably told about maintenance/dark
# sleeps, so this hook also runs (and may force-unmount) on the system-sleep
# event it does get. See display-sleep.sh for the full reasoning.
#
# Budget: man sleepwatcher gives the sleep script 15 s before the system forces
# sleep, so this hook is capped at ~12 s of unmounting before it ejects.
#
# Idempotent and quiet: with nothing mounted at /Volumes/Extra Space (drive not
# attached, or already ejected) it logs one line and exits 0.
set -u
. "${HOME}/.config/sleepwatcher/common.sh"

GRACEFUL_ATTEMPTS=2
GRACEFUL_SECONDS=4

if ! volume_mounted; then
  log "sleep: ${VOL_NAME} not mounted, nothing to do"
  exit 0
fi

dev=$(volume_device)
whole=$(whole_disk "$dev")
log "sleep: ${VOL_NAME} mounted on ${dev:-unknown device} (whole disk ${whole:-unknown}), unmounting"

/bin/sync

# 1. Graceful unmount, retried. Bounded per attempt (see common.sh).
attempt=0
while [ "$attempt" -lt "$GRACEFUL_ATTEMPTS" ] && volume_mounted; do
  attempt=$((attempt + 1))
  unmount_graceful_bounded "$GRACEFUL_SECONDS"
  rc=$?
  if volume_mounted; then
    log "sleep: graceful unmount failed exit ${rc} (attempt ${attempt})"
  else
    log "sleep: graceful unmount ok (attempt ${attempt})"
  fi
done

# 2. Forced unmount if something still holds the volume.
if volume_mounted; then
  /usr/sbin/diskutil unmount force "$VOL_PATH" >/dev/null 2>&1
  rc=$?
  if volume_mounted; then
    log "sleep: unmount force failed exit ${rc}, ejecting anyway"
  else
    log "sleep: unmount force ok"
  fi
fi

# 3. Eject the whole device. Unmounting alone leaves the device objects in
#    IOKit, and that is the state that still warns when the cable is pulled;
#    the device is only safe to remove once it has actually been ejected.
if [ -z "$whole" ] || ! /usr/sbin/diskutil list "$whole" >/dev/null 2>&1; then
  log "sleep: no ejectable device (whole disk ${whole:-unknown}); volume left unmounted"
  exit 0
fi

/usr/sbin/diskutil eject "$whole" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  log "sleep: ejected ${whole}"
else
  log "sleep: eject ${whole} failed exit ${rc}"
fi

# 4. Some USB enclosures re-enumerate immediately after an eject, and macOS
#    auto-mounts the APFS volume again - which is exactly the mounted state that
#    warns when the bus later drops. Re-check once and eject a second time if it
#    came back. Bounded to ~2 s so the 15 s sleep budget stays safe.
if [ "$rc" -eq 0 ]; then
  /bin/sleep 1
  if volume_mounted; then
    dev=$(volume_device)
    whole=$(whole_disk "$dev")
    log "sleep: ${VOL_NAME} remounted after eject (${dev:-unknown device}), ejecting again"
    /usr/sbin/diskutil unmount force "$VOL_PATH" >/dev/null 2>&1 || true
    if [ -n "$whole" ] && /usr/sbin/diskutil list "$whole" >/dev/null 2>&1; then
      /usr/sbin/diskutil eject "$whole" >/dev/null 2>&1
      rc=$?
      if [ "$rc" -eq 0 ]; then
        log "sleep: re-ejected ${whole}"
      else
        log "sleep: re-eject ${whole} failed exit ${rc}"
      fi
    fi
  fi
fi

exit 0
