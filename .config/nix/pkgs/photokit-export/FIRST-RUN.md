# photo-export first-run setup (TCC / Photos authorization)

`photo-export` needs one-time Photos-library authorization. The Photos
permission is keyed to the **signed bundle identity** (`com.ggr.photo-export`),
so doing this once should cover every future build that keeps that identity
(any ad-hoc re-sign changes bytes → re-grant; see below).

## Steps

1. **Install/rebuild** so the `.app` exists:
   - The package builds `libexec/app` (a proper `.app` bundle with
     `NSPhotoLibraryUsageDescription`) and `bin/photo-export`.
   - Home-manager activation symlinks it into `~/Applications/photo-export.app`
     and runs `lsregister` so LaunchServices sees it.
   - Path check: `ls -la ~/Applications/photo-export.app`

2. **First run via Finder / `open` (NOT direct exec).**
   Direct binary execution gets `PHAuthorizationStatusDenied` (status 2) —
   TCC keys the grant to the app identity registered in LaunchServices.

   ```sh
   open ~/Applications/photo-export.app
   ```
   A dialog will appear:
   > "photo-export" wants to access your photo library.
   Click **Allow**.

3. **Verify the grant:**
   ```sh
   # auth check utility (outside this repo; a one-liner probe in probe/)
   # or just run photo-export and look for 'AUTH CALLBACK: 3' / 'authorized'
   ```

4. **Nightly job (already wired in bin/photos-backup):**
   Uses `open` to launch the .app after osxphotos (Phase 1) completes; the
   manifest makes iCloud-original downloads resumable.

## When you need to re-grant

The bundle is still ad-hoc signed, but the package pins an **explicit
designated requirement** (`-r '=designated => identifier "com.ggr.photo-export"'`;
note the leading `=` — without it codesign reads the value as a path to a file
containing the requirement), so the grant macOS records is keyed to the bundle
identifier rather than to the code bytes. Rebuilds no longer invalidate it.
Confirm what is installed:

```sh
codesign -d -r- ~/Applications/"Home Manager Apps"/photo-export.app
# want: designated => identifier "com.ggr.photo-export"
# if it says: designated => cdhash H"…"  — the -r flag was lost, every
# rebuild will cost a re-grant again
```

- **A re-grant is needed only when the requirement itself changes** — a new
  bundle id, or a signature that drops the `-r` requirement. codesign's default
  is `cdhash H"…"`, which changes on every build; that was the 2026-11-18
  outage (one missed night, discovered 35h later by the login monitor). See
  `docs/learnings/2026-11-18-adhoc-signature-keys-tcc-grant-to-cdhash.md`.
- `~/bin/photo-export-grant-check` compares the recorded grant against the
  installed bundle, and `nr` runs it after a successful switch, so a lost grant
  is reported at rebuild time instead of by the 30h monitor.
- Developer ID signing would also anchor it to a Team ID, but the
  identifier-only requirement removes the per-build churn with no Keychain
  certificate to provision.

## Debugging

- Log: `/tmp/photo-export.log`
- If auth stays `2` (Denied) and no prompt appears:
  1. Did you launch via `open`? Direct exec = denied by design.
  2. Is `~/Applications/photo-export.app` present? (activation symlink)
  3. Check System Settings → Privacy & Security → Photos: is photo-export
     listed? If not, re-run the activation or click the live open to re-trigger.