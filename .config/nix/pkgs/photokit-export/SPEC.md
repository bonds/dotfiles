# photokit-export

PhotoKit-native photo export for macOS — single binary, no osxphotos.
Exports ALL assets (local + iCloud-only) over **SFTP** (no local copies, no
SMB mount). PhotoKit streams each original in-memory to sophrosyne.

## Status

**SFTP transport (v0.2.5+, current):** photo-export streams originals in-memory
over SFTP as the active path.
- **Active = SFTP** (`remoteHost` in config.toml). Each asset is fetched by
  PhotoKit into RAM, then streamed via libssh2 to sophrosyne as `photo-backup`
  (owner of `/dragon/media/photos`). No temp file on accismus → zero SSD wear
  from photo data. NetFS/SMB remains only as a fallback if `remoteHost` is unset.
- **Skip-verify by remote SFTP stat:** present-with-size ⇒ skip; missing ⇒
  upload. Never treats a missing remote file as "already done" (a correctness
  regression, once a real data-loss bug, is unit-guarded).
- osxphotos fully removed (overlay, package list, bin/photos-smb-backup phase).
- All-assets export: each PHAsset fetched via PhotoKit.
- Basic XMP sidecar (description + create/modify dates) written next to each
  photo — title/keywords/persons/GPS skipped (photos themselves are the backup
  priority).
- Manifest (`~/.cache/photo-export-manifest.txt`) makes runs resumable; it
  tracks UUIDs uploaded successfully (not "expected on disk").
- Scope decisions unchanged: no Developer ID (`com.ggr.photo-export` ad-hoc).

## Identifier

**`com.ggr.photo-export`** (reverse-DNS under a domain Scott controls —
scott@ggr.com is his email, he owns ggr.com). TCC treats a renamed bundle as
a new app, so expect ONE more "Allow" click on first install of the
production bundle. Worth it to lock in a correct stable identity early.

## Transport: SFTP (current, primary)

Stream originals in-memory to sophrosyne over SSH/SFTP — no local temp copy,
no SMB mount, works over LAN *or* tailnet.

- **SSH key:** `~/.ssh/id_photo_rsync` (no passphrase, auto-generated). Its public
  key is deployed on sophrosyne to `/home/photo-backup/.ssh/authorized_keys` with
  `restrict,command="<sftp-server> -d /dragon/media/photos"` — confined to SFTP
  writes in the photos dir.
- **Why `photo-backup`:** it is the owner/user for `/dragon/media/photos`
  (uid 973, in `users`). Authenticating SFTP as it avoids giving scott write
  access or loosening the tree ownership.
- **Config (`config.toml`):** `remoteHost`, `remoteUser=photo-backup`,
  `remoteKey=~/.ssh/id_photo_rsync`. `remoteHost` = `sophrosyne.local` (LAN) or
  the MagicDNS `sophrosyne.<tailnet>.ts.net` when away.
- **Skip-verify (correctness critical):** before upload, photo-export calls
  `stat` on the remote path. Present (size > 0) ⇒ skip. Missing ⇒ upload. The
  C helper returns `-1` for absent and the Swift check requires `> 0`, so a
  missing file is never wrongly skipped.
- **libssh2:** linked via `sftp_helper.c` bridge; Swift `import Photo
  Helper`. One session per run (no per-file reconnect churn).
- **No local originals kept** — matches "Optimize Mac Storage". Each original
  streams through RAM to the socket, freed afterward.
- **Manifest semantics:** records UUIDs uploaded successfully. Re-running then
  skips only those; the remote `stat` re-checks anything not in the manifest.
  (This is why clearing the manifest after the skip bug let the fix re-verify.)

## SMB + mount architecture (legacy / fallback)

This was the original design; still present as a fallback when `remoteHost` is
_empty_ (SMB transport). SFTP is preferred. No raw SMB2/3 client in Swift:
1. `NetFSMountURLSync()` mount with error codes/cancel; removes the
   `mount_smbfs` + expect password dance.
2. Resumable + verifiable (manifest, probe the mount, `.part`.
3. On disconnect mid-run: abort cleanly, keep manifest, resume next run.

## Why

osxphotos' AppleScript export path (`--download-missing`) has been failing
since 2026-07-26 (`AppleScript export has failed 10 consecutive times…`
— 524+ entries). Root cause: macOS TCC blocks the Photos library and the
Apple Events automation consent. osxphotos ships as a bare Mach-O binary
with no `.app` bundle / `Info.plist` / `NSPhotoLibraryUsageDescription`,
so PhotoKit cannot even present an authorization prompt. A proper signed
`.app` bundle can.

## Architecture (decided)

```
        ┌─────────────────────────── accismus ───────────────────────────┐
        │                                                                │
        │  nix package: photokit-export                                  │
        │  .app bundle (ad-hoc signed, stable identity)                  │
        │  Contents/MacOS/photo-export  (Swift CLI, PhotoKit fetch)      │
        │  + sftp_helper (libssh2) for SFTP streaming                    │
        │  Contents/Info.plist ← NSPhotoLibraryUsageDescription          │
        │                                                                │
        │  PhotoKit fetch → in-memory Data → SFTP stream → freed         │
        │  (no temp file, no SMB mount)                                  │
        └────────────────────────────────────────────────────────────────┘
                            │
                            ▼  ssh/sftp (photo-backup key)
                    ┌────────────── sophrosyne ──────────────┐
                    │ sftp-server -d /dragon/media/photos     │
                    │ (restricted key; photo-backup owns dir) │
                    └─────────────────────────────────────────┘
```

## Key API surface (macOS 15.7, Photos 10.0) — verified working

From `Photos.bridgesupport` (framework v770.0.177) + live probe:

- `PHPhotoLibrary.requestAuthorization(...)` — **VERIFIED** status 3 (authorized)
- `PHAsset.fetchAssets(with:)` — **VERIFIED** 68,333 assets
- **Export (the working one):**
  `PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts, resultHandler:...)` — returns in-memory `Data`.
- Extension from `dataUTI` → UTI preferred ext.
- `writeData(for:toFile:...)` does NOT fire reliably in a CLI; the image path is the proven one.
- Swift module cache be writable (TCC); launch via `open`/LaunchServices for
  the Photos grant (direct exec gets status 2 denied).

## Milestones

- [x] SPEC (this doc)
- [x] Swift probe: import Photos, fetch, auth status
- [x] Signed `.app` probe auth prompt → authorized
- [x] Single PhotoKit export (VERIFIED 2026-08-20, 801,219-byte PNG)
- [x] Production CLI compiles + works end-to-end (2026-08-20) — HEIC/JPG/PNG
- [x] nix `default.nix` packaging, sandboxed `nix build` SUCCEEDS
- [x] Identifier → `com.ggr.photo-export` in bundle (Info.plist + codesign)
- [x] **SFTP transport (Option A)** — libssh2, in-memory streaming, photo-backup key
- [x] Skip-verify by remote stat; fixed the "skip missing file" data-loss bug
- [x] Burn-in: first real SFTP backup (uploaded gaps, skipped present)

## Toil / risks

- PhotoKit auth prompt per signed identity; ad-hoc re-sign = one Allow click.
- Swift/Photos API names differ from docs; match against local overlay.
- SMB path (legacy) requires the mount to be present; SFTP avoids it.
- `nr` activation runs a snippet each switch; keep it idempotent || true so
  switch never aborts (regression: earlier switch failed with exit 2).

## Logging / audit

- `photo-export: SFTP opening/session ready/SKIP-EXISTS/EXPORTED-SFTP` lines to
  `/tmp/photo-export.log`.
- grep for `"AppleScript"` should return nothing in new runs.