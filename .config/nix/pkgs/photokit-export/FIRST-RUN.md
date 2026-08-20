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

4. **Nightly job (already wired in bin/photos-smb-backup):**
   Uses `open` to launch the .app after osxphotos (Phase 1) completes; the
   manifest makes iCloud-original downloads resumable.

## When you need to re-grant

- **Any binary byte change** — Swift source edit, version bump, or nix rebuild
  that produces a new binary → CDHash changes → macOS treats it as a new app.
  Expect a fresh Allow prompt. That's expected and safe; just click Allow.
- **Developer ID signing would fix this permanently** (Team ID-anchored), but
  the decision is ad-hoc for now.

## Debugging

- Log: `/tmp/photo-export.log`
- If auth stays `2` (Denied) and no prompt appears:
  1. Did you launch via `open`? Direct exec = denied by design.
  2. Is `~/Applications/photo-export.app` present? (activation symlink)
  3. Check System Settings → Privacy & Security → Photos: is photo-export
     listed? If not, re-run the activation or click the live open to re-trigger.