#!/usr/bin/env bash
# SleepWatcher display-sleep hook (`sleepwatcher -S`): take the 'Extra Space'
# volume off the bus when the *display* sleeps - which is what happens on lid
# close and on idle display sleep, before the system suspends.
#
# Why display sleep rather than system sleep: sleepwatcher is not reliably told
# about maintenance/dark sleeps (verified 2026-11-15 - no sleep-hook run for a
# 20:31 maintenance sleep). A volume mounted after a dark wake can therefore
# stay mounted across a whole night's sleep and produce "Disk Not Ejected
# Properly" when the USB bus eventually drops. The display-sleep event is
# delivered on the way into every sleep and arrives earlier. The system-sleep
# hook (`-s`) stays as the force-capable backstop.
#
# Graceful only: the display also sleeps during a long copy while the machine
# stays awake, and force-unmounting there would corrupt the transfer. If the
# volume is busy this logs it and leaves it mounted; the system-sleep hook is
# the one that may force it.
set -u
. "${HOME}/.config/sleepwatcher/common.sh"

GRACEFUL_SECONDS=5

if ! volume_mounted; then
  log "display-sleep: ${VOL_NAME} not mounted, nothing to do"
  exit 0
fi

dev=$(volume_device)
whole=$(whole_disk "$dev")
log "display-sleep: ${VOL_NAME} mounted on ${dev:-unknown device} (whole disk ${whole:-unknown}), unmounting gracefully"

/bin/sync

unmount_graceful_bounded "$GRACEFUL_SECONDS"
rc=$?
if volume_mounted; then
  log "display-sleep: graceful unmount failed exit ${rc}, leaving volume mounted for the system-sleep hook"
  exit 0
fi
log "display-sleep: graceful unmount ok"

# Eject the whole device. Unmounting alone leaves the device objects in IOKit,
# and that is the state that still warns when the cable is pulled; the device is
# only safe to remove once it has actually been ejected.
if [ -z "$whole" ] || ! /usr/sbin/diskutil list "$whole" >/dev/null 2>&1; then
  log "display-sleep: no ejectable device (whole disk ${whole:-unknown}); volume left unmounted"
  exit 0
fi

/usr/sbin/diskutil eject "$whole" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
  log "display-sleep: ejected ${whole}"
else
  log "display-sleep: eject ${whole} failed exit ${rc}"
fi

exit 0
