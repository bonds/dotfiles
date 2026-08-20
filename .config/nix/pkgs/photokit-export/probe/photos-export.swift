// photo-export.swift — PhotoKit export probe (Phase 2, bundle v7)
// Uses the PROVEN osxphotos approach: PHImageManager.requestImageDataAndOrientationForAsset
// with setSynchronous(true) + networkAccessAllowed(true) + version original + highQuality.
// The resultHandler receives (imageData, dataUTI, orientation, info); we write bytes to /tmp.

import Photos
import Foundation
import Darwin

let logFH = fopen("/tmp/photos-export-probe.log", "w")
if logFH == nil { exit(2) }
func logLine(_ s: String) {
    fputs("\(s)\n", logFH)
    fflush(logFH)
}

func authStatus() -> Int {
    return PHPhotoLibrary.authorizationStatus(for: .readWrite).rawValue
}

logLine("probe start")

// --- AUTH (mirrors osxphotos request_photokit_authorization) ---
var status = authStatus()
logLine("initial status: \(status)")
if status != 3 {
    for i in 0..<3 {
        logLine("requesting authorization (attempt \(i + 1))...")
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
            logLine("auth callback fired")
        }
        let deadline = Foundation.ProcessInfo.processInfo.systemUptime + 10.0
        while Foundation.ProcessInfo.processInfo.systemUptime < deadline {
            Foundation.Thread.sleep(forTimeInterval: 0.5)
            status = authStatus()
            if status == 3 { break }
        }
        logLine("status after attempt \(i + 1): \(status)")
        if status == 3 { break }
    }
}
logLine("final auth status: \(status)")
if status != 3 {
    logLine("NOT AUTHORIZED — aborting")
    fclose(logFH)
    exit(1)
}
logLine("AUTHORIZED")

// --- FETCH ASSETS, count cloud-only, export ONE ---
let result = PHAsset.fetchAssets(with: nil)
logLine("asset count: \(result.count)")

var localCount = 0
var cloudCount = 0
var firstCloudId: String = ""

result.enumerateObjects { asset, index, stop in
    var hasFull = false
    let res = PHAssetResource.assetResources(for: asset)
    for r in res {
        if r.type == PHAssetResourceType.fullSizePhoto || r.type == PHAssetResourceType.fullSizeVideo {
            hasFull = true
        }
    }
    if hasFull { localCount += 1 } else { cloudCount += 1 }
    if firstCloudId.isEmpty && !hasFull { firstCloudId = asset.localIdentifier }
}
logLine("local: \(localCount) cloud-only: \(cloudCount) firstCloud: \(firstCloudId)")

// --- EXPORT FIRST CLOUD ASSET via PHImageManager (proven path) ---
if !firstCloudId.isEmpty {
    logLine("EXPORTING \(firstCloudId)")
    let result2 = PHAsset.fetchAssets(withLocalIdentifiers: [firstCloudId], options: nil)
    let mgr = PHImageManager.default()

    result2.enumerateObjects { asset, index, stop in
        let opts = PHImageRequestOptions()
        opts.isNetworkAccessAllowed = true
        opts.isSynchronous = true
        opts.version = .original
        opts.deliveryMode = .highQualityFormat

        var gotData = false
        var gotUTI = ""
        var writeFailed = ""

        mgr.requestImageDataAndOrientation(for: asset, options: opts, resultHandler: { imageData, dataUTI, orientation, info in
            gotData = true
            gotUTI = String(dataUTI ?? "")
            let img = imageData!
            logLine("image data callback, uti=\(gotUTI) count=\(img.count)")
            // write bytes
            let destPath = "/tmp/photokit-export-test.jpg"
            let destURL = NSURL.fileURL(withPath: destPath)
            let werr = try? img.write(to: destURL)
            if werr == nil {
                logLine("WROTE \(destPath) count=\(img.count)")
            } else {
                logLine("WRITE ERR \(destPath)")
            }
        })

        // give the synchronous request a moment; poll for file
        let deadline = Foundation.ProcessInfo.processInfo.systemUptime + 30.0
        while Foundation.ProcessInfo.processInfo.systemUptime < deadline {
            Foundation.Thread.sleep(forTimeInterval: 0.5)
            let probeFH = fopen("/tmp/photokit-export-test.jpg", "r")
            if probeFH != nil {
                fclose(probeFH)
                break
            }
        }
        stop.pointee = true
    }
}

logLine("DONE")
fflush(logFH)
fclose(logFH)
exit(0)