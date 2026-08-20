// photo-export-probe.swift — minimal PhotoKit probe (Phase 2)
// Build: swiftc -module-cache-path /tmp/swiftcache -o photo-export-probe probe.swift
// In an .app bundle with NSPhotoLibraryUsageDescription, this should:
//   1) authorize (first run prompts human)
//   2) enumerate assets
//   3) count missing (cloud) assets
import Photos
import Foundation

// 1. AUTHORIZATION STATUS
let status = PHPhotoLibrary.authorizationStatus()
print("authorizationStatus:", status.rawValue, "authorized:", status == PHAuthorizationStatus.authorized)

// 2. If not authorized, REQUEST it (prompts the user ONCE)
//    Without a bundled Info.plist usage key this may fail as "not authorized".
if status != PHAuthorizationStatus.authorized {
    print("REQUESTING authorization...")
    let granted = PHPhotoLibrary.requestAuthorizationForAccessLevel(.readWrite, PHAuthorizationHandler { })
    print("request sent, waiting for UI...")
}

// 3. Wait a moment for the async auth callback; then re-check status
//    (the handler runs on the Photos process side; we poll once)
Foundation.RunLoop = Foundation.RunLoop ?? 0
Photos.PHPhotoLibrary.runLoopOnce()

let status2 = PHPhotoLibrary.authorizationStatus()
print("authorizationStatus after request:", status2.rawValue, "authorized:", status2 == PHAuthorizationStatus.authorized)

// 4. Enumerate assets
let result = PHAsset.fetchAssets(with: nil)
print("asset count:", result.count)

if result.count > 0 {
    var cloudCount = 0
    var localCount = 0
    result.enumerateObjects { asset, index, stop in
        // Fetch original file path — nil if iCloud-optimized (missing from disk)
        let path = asset.originalFilename
        if path.isEmpty { cloudCount += 1 } else { localCount += 1 }
        if index < 3 {
            print("asset[", index, "]: localId=", asset.localIdentifier, " name=", asset.originalFilename)
        }
    }
    print("local:", localCount, "cloud-only:", cloudCount)
}
print("DONE")