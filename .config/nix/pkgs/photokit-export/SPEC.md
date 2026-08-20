# photokit-export

PhotoKit-native photo export for macOS — single binary, no osxphotos.
Exports ALL assets (local + iCloud-only) directly to an SMB mount.

## Status

**Mono-architecture (v0.2.0):** photo-export is the sole exporter.
- osxphotos fully removed (overlay, package list, bin/photos-smb-backup phase)
- All-assets export: no cloud-only gate; each PHAsset fetched via PhotoKit
- Basic XMP sidecar (description + create/modify dates) written next to each
  photo — title/keywords/persons/GPS intentionally skipped (requires
  Photos.sqlite parsing; photos themselves are the backup priority)
- Manifest (`~/.cache/photo-export-manifest.txt`) makes runs resumable
- Scope decisions unchanged: no Developer ID (`com.ggr.photo-export` ad-hoc),

## Identifier

**`com.ggr.photo-export`** (reverse-DNS under a domain Scott controls —
scott@ggr.com is his email, he owns ggr.com). TCC treats a renamed bundle as
a new app, so expect ONE more "Allow" click on first install of the
production bundle. Worth it to lock in a correct stable identity early.

## SMB + mount architecture (decision)

**Do NOT implement a raw SMB2/3 client in Swift.** Multi-week protocol work
(dialect negotiation, auth, signing, session state) for zero reliability gain —
macOS's own SMB stack is battle-tested. Instead:

1. **Bring the mount lifecycle INTO the app** using Apple's frameworks:
   - `NetFS.NetFSMountURLSync()` — mount SMB URL programmatically with
     proper error codes / cancellation (`NetFSMountURLCancel`)
   - `NSWorkspace.mountVolume()` (AppKit) as the higher-level alternative
   - This removes the fragile `mount_smbfs` + expect-script password dance.
2. **Robustness model: resumable + verifiable, not in-process SMB.**
   - Manifest (UUID-per-line) already gives resume: re-runs skip completed files.
   - Verify the mount is real (probe the target dir) before writing — prevents
     the "silent local writes" failure mode that bit osxphotos.
   - On disconnect/dismount mid-run: **abort cleanly, keep manifest, resume
     next run.** Optionally mark the incomplete file in the manifest.
   - Optional per-file retry loop with backoff *inside* photo-export
     (application-level, on top of the OS SMB stack).
3. **Alternative transport (keep in mind): rsync-over-SSH to sophrosyne** —
   the `rrsync-photos` wrapper + `id_photo_rsync` key already exist, rsync
   handles partial transfers + delta. Trade-off: needs local staging space
   (~200-400 GB); SMB direct-to-server is why we're bleeding edge only on
   mount lifecycle, which is the right shape for "Optimize Mac Storage"
   constraints.

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
        │  .app bundle (ad-hoc signed, stable identifier)                 │
        │  Contents/MacOS/osxphotos   ← from osxphotos-0.76.1 (re-signed) │
        │  Contents/Info.plist        ← NSPhotoLibraryUsageDescription    │
        │  Contents/MacOS/photos-export  (Swift CLI, PhotoKit fetch path)  │
        │                                                                │
        │  osxphotos: local originals + metadata (unchanged)              │
        │  photo-export: iCloud-original fetch (PhotoKit, no AppleScript) │
        │                                                                │
        └────────────────────────────────────────────────────────────────┘
```

## Key API surface (macOS 15.7, Photos 10.0) — verified working

From `Photos.bridgesupport` (framework v770.0.177) + live probe:

- `PHPhotoLibrary.requestAuthorization(for:handler:)` — auth prompt; poll `authorizationStatus(for:)` after (callback is unreliable on first prompt; osxphotos retries 3×). **VERIFIED** status 3 (authorized)
- `PHAsset.fetchAssets(with: PHFetchOptions?)` + `result.enumerateObjects` — **VERIFIED** 68,333 assets
- Cloud-only detection: `PHAssetResource.assetResources(for: asset)` then check for `r.type == .fullSizePhoto || .fullSizeVideo` — **VERIFIED** 65,791 cloud-only / 2,542 local
- **Export (the one that works):** `PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts, resultHandler: { imageData, dataUTI, orientation, info })`
  - opts: `version = .original`, `deliveryMode = .highQualityFormat`, `isNetworkAccessAllowed = true`, `isSynchronous = true`
  - handler unwraps `imageData!` (Data), writes with `data.write(to: URL)` — **VERIFIED** downloaded 801,219 bytes valid PNG of a cloud-only original
- Filename extension from UTI: `dataUTI` → `public.png` → use preferred extension for the UTI (my probe hardcoded `.jpg`; real tool must map UTI→ext, e.g. `public.png`→`.png`, `public.jpeg`→`.jpg`)
- Note: `writeData(for:toFile:...)` (resource manager) does NOT fire its completion handler reliably in a CLI; the `requestImageDataAndOrientation` image path is the proven one.
- Swift module cache must be writable (`-module-cache-path`), else `import Photos` fails in the default `~/Library/Caches/...` (TCC).
- Launch MUST be via `open`/LaunchServices (dock bounce is expected; headless CLI in an .app). Direct binary exec gets `status 2` (denied) because TCC keys the grant to the registered app identity.

## Milestones

- [x] SPEC written (this doc)
- [x] Swift probe compiles: `import Photos`, fetch, auth status
- [x] Signed `.app` probe triggers auth prompt → `authorizationStatus == authorized`
- [x] Single PhotoKit export of a known-missing photo lands on disk (VERIFIED 2026-08-20)
      - `image data callback, uti=public.png count=801219` → valid PNG on disk
- [x] Production CLI `photo-export.swift` compiles + works end-to-end (2026-08-20)
      - VERIFIED: 3,166 files / 5.3 GB real HEIC+JPG+PNG originals in `yyyy/mm` dirs,
        resumable manifest, correct UTI extensions
- [x] nix `default.nix` packaging — sandboxed `nix build` SUCCEEDS (codesign included)
- [ ] Switch identifier to `com.ggr.photo-export` in default.nix bundle
- [ ] Wrap SMB mount lifecycle in the app (NetFS/NSWorkspace) + verifiable mount
- [ ] Integration: `bin/photos-smb-backup` uses PhotoKit path for `--download-missing`
- [ ] Burn-in: 10 → 100 → full missing set
- [ ] Rebuild persistence check (2× `nr switch`)

## Toil / risks

- PhotoKit authorization prompt appears per-binary until granted; the grant
  is per signed identity, so the FIRST run after each ad-hoc re-sign needs
  a human click. Acceptable (no paid Developer ID).
- Swift 6.2/Photos 6/Photos 10 API names differ from docs; method names must
  be matched against the local framework's Swift overlay.

## Logging / audit

- `photos-export` writes its own date-stamped log line to
  `<out>.log` after osxphotos completes: `photokit: exported N, skipped M already-on-disk, failed K`
- no AppleScript involvement — grep for `"AppleScript"` should return nothing in new runs.