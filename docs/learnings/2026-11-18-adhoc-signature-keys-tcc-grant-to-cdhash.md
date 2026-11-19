# An ad-hoc signature keys the Photos TCC grant to the cdhash, so every rebuild needs a re-grant

**Date:** 2026-11-18

## Symptom

The nightly photo backup died at 02:00 with a local authorization failure, not
a network one:

```
Wed Nov 18 02:00:37 PST 2026 — backup FAILED (exit 1): photo-export exited before SUMMARY —
photo-export: FATAL: not authorized (status=0); open the app once to grant Photos access
```

`/tmp/photo-export.log` showed `auth initial=0`, three `auth attemptN=0`, then
the FATAL — and no `SFTP:` lines at all, so the run never reached sophrosyne.
`/var/lib/photo-backup/last-login` stayed at the previous night's
`2026-11-17T02:03:58`, which tripped the 30h login monitor 35h later. The
nightly job was working fine; the *app* had lost Photos access.

`status=0` is `PHAuthorizationStatus.notDetermined` — not `2`/denied. Nothing
had been *revoked*; TCC had never seen this binary.

## Cause

`pkgs/photokit-export/default.nix` ad-hoc signs the bundle
(`codesign -s - -f --identifier com.ggr.photo-export`) with a comment claiming
the grant therefore survives nix store-path changes because it "keys to the
identifier, not the path". The path half is true and the identity half is not:

```fish
codesign -d -r- ~/Applications/Home\ Manager\ Apps/photo-export.app
# designated => cdhash H"0f9528933ca2e74c0955495cf4976aa81fd779be"
```

With no signing certificate there is no Team ID and no certificate leaf to pin
the designated requirement to, so codesign falls back to the **cdhash** — a hash
of the actual code. Any change to the compiled bytes produces a new cdhash, TCC
sees a different app, and the stored grant no longer matches. The `nr` at
2026-11-17 05:51 (system-866) rebuilt `photo-export` into a new cdhash, so the
02:00 run the next morning got `notDetermined`.

The store even holds ~20 distinct cdhashes across `photo-export-0.2.x` paths, one
per build — each of which would have needed its own grant.

Recovery was not automatic: the 02:00 run's `requestAuthorization` queued a TCC
prompt that nobody was there to answer, and the grant only appeared at
**06:01:10** the same morning when it was clicked — the user TCC row's
`last_modified` and `chronod`'s `[appAuth:com.ggr.photo-export] tcc
authorization(s) changed` agree on that second. So the outage lasts until a
human happens to click Allow, which is why it looked like a transport failure
for 35h.

## Fix

Re-grant after any build that changes the binary:

```fish
open ~/Applications/Home\ Manager\ Apps/photo-export.app   # click Allow
```

Verify without waiting for 02:00 — the app prints its status on launch, and the
wrapper's own run is resumable and cheap:

```fish
~/bin/photos-backup; tail -5 /tmp/photo-export.log   # want: auth initial=3, then SFTP: session ready
ssh sophrosyne 'stat -c %y /var/lib/photo-backup/last-login'
```

Inspect the grant directly — the user TCC db is readable without root and has no
WAL, so a plain copy is a consistent snapshot:

```fish
sqlite3 ~/Library/Application\ Support/com.apple.TCC/TCC.db \
  "select service,auth_value,datetime(last_modified,'unixepoch','localtime'),hex(csreq)
   from access where client like '%photo-export%';"
```

`auth_value` 2 = allowed, 0 = denied; the trailing bytes of `csreq` are the
cdhash it is pinned to — compare with `codesign -dvvv <app> | rg CDHash`.
`auth_value=0` with a matching cdhash means someone clicked Don't Allow and it
needs `tccutil reset Photos com.ggr.photo-export`.

**Durable fix (applied 2026-11-18):** the package now pins an explicit
requirement instead of relying on codesign's default:

```
codesign -s - -f --identifier com.ggr.photo-export \
  -r 'designated => identifier "com.ggr.photo-export"' app
```

`identifier` is build-independent, so rebuilds stop costing a re-grant, and it
needs no certificate in the login keychain (which Developer ID signing would,
and which is not declarative from nix). Two things to know if it is ever
touched: the build now fails if the requirement regresses to cdhash-based, and
`codesign -d -r-` prints a *derived* requirement with a `# ` prefix but an
embedded one bare — the check in `bin/photo-export-grant-check` strips the
prefix rather than assuming it.

**The recorded grant can go stale without the app being blocked.** TCC keeps an
`AdhocSignatureCache` next to `TCC.db`, and on 2026-11-19 02:00 the nightly run
was authorized against a *cdhash-based* stored `csreq` after the binary had been
rebuilt with the new identifier requirement — the row only caught up at 05:11,
when the next launch rewrote it (`auth initial=0`, `attempt1=3`). So
`photo-export-grant-check` is deliberately conservative: a warning means "the
recorded requirement no longer matches this build", which TCC *may* still
tolerate, not "the backup is definitely broken". Treat it as a prompt to click
Allow while you are at the machine, not as a proven outage.

Third gotcha, which cost a build: **`codesign -r` needs a leading `=` for an
inline requirement.** Without it the value is read as a *path to a file*
containing the requirement, so the build fails with

```
designated => identifier "com.ggr.photo-export": No such file or directory
invalid requirement specification
```

Use `-r '=designated => identifier "…"'` (or `-r='designated => …'`).

Related: `2026-11-11-photo-backup-silent-no-op.md` (the same TCC reset, before
the wrapper learned to require a `SUMMARY` line — that fix is what turned this
one into a visible `backup FAILED`).
