# sleepwatcher's wake hook can remount a drive across a sleep it never hears about

**Date:** 2026-11-15

## Symptom

"Disk Not Ejected Properly — Eject 'Extra Space' before disconnecting or turning
it off" appeared again even though the sleepwatcher hooks had been ejecting
cleanly for a month. The 2026-11-15 incident:

```
20:29:57  dark wake, then full wake (USB-C_plug)
20:30:04  wake hook mounts Extra Space (disk7s1, whole disk disk6)
20:30:04  sleep hook unmounts + ejects disk6            <- clean
20:30:49  another dark wake (wifibt / USB wakeup)
20:30:53  volume mounted again (mount_apfs)             <- no hook log line
20:31:34  system enters maintenance sleep               <- NO sleep-hook run
06:10:41  enclosure drops off the USB bus; diskarbitrationd logs the unclean
          unmount (volume was still mounted)
06:29:49  full wake -> "Disk Not Ejected Properly"
```

The `sleepwatcher-hooks.log` has no entry at 20:31:34 or 06:24, and
`sleepwatcher.out.log`'s last sleep invocation before the 06:30 wake is the
20:30:04 one - the sleep script never ran for the maintenance sleeps.

## Cause

The hooks were asymmetric. sleepwatcher delivers **wake** events for every wake,
including dark/maintenance wakes, so `wake.sh` (`-w`) remounted the volume. It
does **not** reliably deliver a **sleep** event for maintenance/dark sleeps, so
the `-s` hook had no chance to eject again. A volume mounted after a dark wake
was therefore left mounted across a whole night's sleep, and when the USB bus
finally dropped the enclosure, macOS reported an unclean removal.

`diskutil eject` is not a guarantee either: some USB enclosures re-enumerate
right after the eject, and macOS auto-mounts the APFS volume again.

## Fix

Trigger on **display** sleep/wake instead of system sleep/wake, and keep the
system-sleep hook as a force-capable backstop:

```
sleepwatcher -S ~/.config/sleepwatcher/display-sleep.sh   # graceful eject
sleepwatcher -s ~/.config/sleepwatcher/sleep.sh           # force backstop
sleepwatcher -W ~/.config/sleepwatcher/wake.sh            # remount
```

- `-S` fires on lid close and idle display sleep, before the system suspends,
  and is delivered on every descent into sleep.
- `-W` fires only when the *display* wakes, i.e. on a wake the user caused -
  not on a dark wake - so the remount can no longer outrun the sleep hook.
- `display-sleep.sh` never force-unmounts (the display also sleeps during a long
  copy); `sleep.sh` keeps the force fallback and re-checks once after eject,
  re-ejecting if the volume came straight back.

Do not go back to `-w` for the remount. It is the dark-wake remount that turns a
missing sleep event into an unclean removal.
