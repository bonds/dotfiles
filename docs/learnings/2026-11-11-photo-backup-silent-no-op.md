# A nightly photo backup that logs "backup complete" may never have connected

**Date:** 2026-11-11

## Symptom

The nightly `photos-backup` agent on accismus reported success every night, in
five seconds, for 13 days:

```
Fri Oct 30 02:00:52 PDT 2026 — launching photo-export over SFTP...
Fri Oct 30 02:01:22 PDT 2026 — backup complete
```

while no photo had actually arrived on sophrosyne since Oct 27, and
`journalctl -u sshd` on sophrosyne showed the last real login on **Oct 29**
(`Accepted publickey for photo-backup …`). Nothing in
`~/Library/Logs/photos-backup.err.log` mentioned it, and `/tmp/photo-export.log`
— where the app writes its own lines — had no entries for those runs at all.

## Cause

Two independent blind spots:

1. The old wrapper ended with an unconditional `echo "… — backup complete"`.
   `open -j -W "$APP"` returns 0 as soon as LaunchServices has *launched* the
   bundle; it does not propagate the app's exit status. So an app that dies
   before writing a single log line (TCC reset after a nix rebuild, broken
   signature) is indistinguishable from a run with nothing to upload.
2. "No new photos" is invisible from the photo tree alone — `photo-backup-monitor`
   measures freshness with a 14-day threshold, so a dead backup looks healthy
   until the tree goes stale, and it says nothing about *whether the job ran*.

The nightly job's only positive evidence is the SFTP login itself, in sshd's
journal on sophrosyne.

## Fix

Judge the run from the app's own log, not from `open`'s status: the current
wrapper requires a `photo-export: SUMMARY exported=<n> skipped=<n> failed=<n>`
line from `/tmp/photo-export.log` and reports `backup FAILED` otherwise. And
measure the login, not the files: the SFTP forced command stamps
`/var/lib/photo-backup/last-login`, and `photo-backup-login-monitor` alarms when
that stamp is older than 30h.

Diagnostic when a backup looks quiet:

```fish
# did the nightly job actually reach sophrosyne?
ssh sophrosyne "journalctl -u sshd --no-pager | rg 'Accepted publickey for photo-backup' | tail -5"
ssh sophrosyne "cat /var/lib/photo-backup/last-login"
# what did the app itself do on the last run?
tail -30 ~/Library/Logs/photos-backup.run.log
```

Gotcha found the same day: a *missing* stamp is guaranteed for up to 24h after
the wrapper is first deployed, so the monitor false-alarms on a fresh switch.
`system.activationScripts.photoBackupLoginStamp` seeds the stamp (owned
`photo-backup`, or the forced command cannot overwrite it) only when it is
absent, so the monitor measures from the deploy without resetting the clock on
every rebuild.
