// photo-export.swift — PhotoKit CLI for iCloud-original export (Phase 3, v8)
// Target: replace osxphotos' --download-missing AppleScript path with PhotoKit-native.
//
// Usage:
//   photo-export <dest-dir> [--limit N] [--dry-run] [--manifest /path/state.json]
//
// Behavior:
//   1. Request/resolve PhotoKit auth (once; user clicks Allow on first prompt)
//   2. Enumerate all assets; detect cloud-only (no .fullSizePhoto/.fullSizeVideo resource)
//   3. For each cloud-only asset: download original via
//      PHImageManager.requestImageDataAndOrientation (proven path from Phase 2)
//   4. Write to <dest>/<yyyy>/<mm>/<SafeFilename>.<utiext> (matches osxphotos date schema)
//   5. Append localIdentifier to the manifest JSON so re-runs skip already-downloaded
//
// Logs to stdout AND /tmp/photos-export.log (lines "photo-export: ..." for grepping).

import Photos
import Foundation
import Darwin
import UniformTypeIdentifiers
import NetFS
import CoreFoundation
import AppKit

// ---------- logging ----------
let logStdout = stdout
let logFile = fopen("/tmp/photo-export.log", "a")
func log(_ s: String) {
    let line = "photo-export: \(s)"
    fputs(line + "\n", stderr)
    if logFile != nil { fputs(line + "\n", logFile); fflush(logFile) }
}

// ---------- args ----------
let args = CommandLine.arguments
func argValue(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name) else { return nil }
    if i + 1 < args.count { return args[i + 1] }
    return nil
}
var destDir: String = args.count > 1 ? args[1] : "/tmp/photokit-export"
let limit = Int(argValue("--limit") ?? "0") ?? 0
let dryRun = args.contains("--dry-run")

// ---------- SMB mount lifecycle (owned by this process) ----------
// Mount the sophrosyne photos share programmatically. Priority:
//   1. NetFS NetFSMountURLSync (Apple API, error codes, cancel support)
//   2. Fallback: mount_smbfs via Process with keychain password
// Robustness model: resumable (manifest) + verifiable (probe mount before
// writes, .part+rename so only complete files are recorded).

// Over the tailnet, `sophrosyne` resolves (sophrosyne.local is LAN-only and
// not resolvable from my sandbox). Keychain service stays sophrosyne.local to
// match the existing `security find-internet-password -s sophrosyne.local`.
let smbHost = argValue("--smb-host") ?? "sophrosyne"
let smbShare = argValue("--smb-share") ?? "photos"
let smbUser = argValue("--smb-user") ?? "photo-backup"
let keychainService = argValue("--keychain-service") ?? "sophrosyne.local"

func keychainPassword() -> String? {
    // security find-internet-password -s <service> -a <user> -w
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    p.arguments = ["find-internet-password", "-s", keychainService, "-a", smbUser, "-w"]
    let pipe = Pipe()
    // security writes password to stderr when -w; capture both
    let errPipe = Pipe()
    p.standardOutput = pipe
    p.standardError = errPipe
    do { try p.run() } catch { return nil }
    p.waitUntilExit()
    if p.terminationStatus != 0 { return nil }
    let data = errPipe.fileHandleForReading.readDataToEndOfFile() + pipe.fileHandleForReading.readDataToEndOfFile()
    let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    return s?.isEmpty ?? true ? nil : s
}

func mountViaProcess(mountPath: String) -> Bool {
    guard let pass = keychainPassword() else {
        log("SMB: no keychain password for \(smbHost)/\(smbUser)")
        return false
    }
    // Use NetFS when we have credentials (avoids password-in-process-args).
    return mountViaNetFS(mountPath: mountPath, pass: pass)
}

func mountViaNetFS(mountPath: String, pass: String) -> Bool {
    guard let urlObj = NSURL.init(string: "smb://\(smbHost)/\(smbShare)") else { return false }
    let url = urlObj as CFURL
    let mountPathURL = URL(fileURLWithPath: mountPath) as NSURL as CFURL
    let userCF = NSString(string: smbUser) as CFString
    let passCF = NSString(string: pass) as CFString
    let opts = NSMutableDictionary() as CFMutableDictionary
    let mopts = NSMutableDictionary() as CFMutableDictionary
    var mountpoints: Unmanaged<CFArray>? = nil
    let stat = NetFSMountURLSync(url, mountPathURL, userCF, passCF, opts, mopts, &mountpoints)
    log("SMB: NetFSMountURLSync status=\(stat) mountpoints=\(String(describing: mountpoints))")
    return stat == 0
}

func isMounted(_ mountPath: String) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/sbin/mount")
    let pipe = Pipe()
    p.standardOutput = pipe
    do { try p.run() } catch { return false }
    p.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return out.contains(mountPath)
}

let mountPath = argValue("--mount") ?? "/tmp/sophrosyne-photos"
var mounted = false

// ---------- manifest (resume support, plain text UUID-per-line) ----------
let manifestPath = (argValue("--manifest") ?? "/tmp/photo-export-manifest.txt")
func loadManifestTxt() -> Set<String> {
    guard let raw = try? String(contentsOfFile: manifestPath, encoding: .utf8) else { return [] }
    return Set(raw.split(separator: "\n").map { String($0) })
}
func appendManifest(_ uuid: String) {
    let fh = fopen(manifestPath, "a")
    if fh != nil { fputs(uuid + "\n", fh); fclose(fh) }
}
var done = loadManifestTxt()

// ---------- UTI -> extension ----------
func extForUTI(_ uti: String?) -> String {
    guard let uti = uti, !uti.isEmpty else { return "jpg" }
    switch uti {
    case "public.png": return "png"
    case "public.jpeg", "public.jpg": return "jpg"
    case "public.heic", "public.heif": return "heic"
    case "com.compuserve.gif": return "gif"
    case "public.tiff": return "tiff"
    case "public.mpeg-4", "com.apple.quicktime-movie": return "mov"
    case "public.mpeg-4-video": return "mp4"
    case "com.adobe.raw-image": return "dng"
    default:
        // try UTI preferred extension via UTType
        if let type = UTType(uti), let ext = type.preferredFilenameExtension {
            return ext
        }
        return "jpg"
    }
}

// ---------- auth ----------
func authStatus() -> Int {
    return PHPhotoLibrary.authorizationStatus(for: .readWrite).rawValue
}
var status = authStatus()
log("auth initial=\(status)")
if status != 3 {
    for i in 0..<3 {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
            status = authStatus()
            if status == 3 { break }
        }
        log("auth attempt\(i+1)=\(status)")
        if status == 3 { break }
    }
}
if status != 3 {
    log("FATAL: not authorized (status=\(status)); open the app once to grant Photos access")
    exit(1)
}
log("authorized")

// ---------- output dir (optionally an SMB mount owned by this process) ----------
let mountMode = args.contains("--mount")   // give --mount → we own the mount
mounted = isMounted(mountPath)

if mountMode && !isMounted(mountPath) {
    log("SMB: mounting \(smbHost)/\(smbShare) at \(mountPath)")
    do { try FileManager.default.createDirectory(atPath: mountPath, withIntermediateDirectories: true, attributes: nil) } catch {}
    if mountViaProcess(mountPath: mountPath) {
        mounted = isMounted(mountPath)
    } else {
        log("SMB: NetFS mount failed")
        mounted = false
    }
    log("SMB: mounted=\(mounted)")
    if !mounted {
        log("FATAL: cannot mount \(smbHost)/\(smbShare) — aborting (manifest preserved)")
        exit(1)
    }
}

// When mounting, export into a subdir of the mount (keep the manifest on local disk)
var useDest = destDir
if mounted {
    useDest = destDir
    let probeFile = useDest + "/.probe"
    do {
        try "ok".write(toFile: probeFile, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(atPath: probeFile)
    } catch {
        log("FATAL: mount \(useDest) not writable — \(error)")
        exit(1)
    }
}

do {
    try FileManager.default.createDirectory(atPath: useDest, withIntermediateDirectories: true)
} catch {
    log("FATAL: cannot create dest \(useDest): \(error)")
    exit(1)
}

// ---------- enumerate + export cloud-only ----------
let all = PHAsset.fetchAssets(with: nil)
log("assets=\(all.count) dryRun=\(dryRun) limit=\(limit)")

var exported = 0
var skipped = 0
var failed = 0
let mgr = PHImageManager.default()

all.enumerateObjects { asset, index, stop in
    if limit > 0 && exported + skipped >= limit { stop.pointee = true; return }

    let uuid = asset.localIdentifier
    if done.contains(uuid) { skipped += 1; return }

    // cloud-only detection
    var isCloud = true
    let res = PHAssetResource.assetResources(for: asset)
    for r in res {
        if r.type == PHAssetResourceType.fullSizePhoto || r.type == PHAssetResourceType.fullSizeVideo {
            isCloud = false
            break
        }
    }
    if !isCloud { skipped += 1; return }

    // date schema yyyy/mm
    var yearStr = "unknown"; var monthStr = "xx"
    if let cd = asset.creationDate {
        let f = DateFormatter(); f.dateFormat = "yyyy"; yearStr = f.string(from: cd)
        let fm = DateFormatter(); fm.dateFormat = "MM"; monthStr = fm.string(from: cd)
    }
    let dirPath = destDir + "/" + yearStr + "/" + monthStr
    do { try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true) } catch {}

    // original filename (from first resource)
    var base = uuid.split(separator: "/").first.map(String.init) ?? uuid
    let resFirst = PHAssetResource.assetResources(for: asset)
    if let r0 = resFirst.first, !r0.originalFilename.isEmpty {
        base = (r0.originalFilename as NSString).deletingPathExtension
    }

    if dryRun { log("DRYRUN \(uuid)"); exported += 1; appendManifest(uuid); return }

    // request + write (atomic: write .part then rename, so interrupted
    // downloads leave no corrupt file and aren't recorded in the manifest)
    let opts = PHImageRequestOptions()
    opts.version = .original
    opts.deliveryMode = .highQualityFormat
    opts.isNetworkAccessAllowed = true
    opts.isSynchronous = true

    var ok = false
    let retries = 3
    for attempt in 0..<retries {
        if !isMounted(mountPath) {
            log("SMB: mount disconnected mid-run — aborting cleanly (manifest preserved)")
            stop.pointee = true
            return
        }
        mgr.requestImageDataAndOrientation(for: asset, options: opts, resultHandler: { imageData, dataUTI, orientation, info in
            guard let img = imageData else { log("ERR no data for \(uuid) attempt \(attempt)"); return }
            let ext = extForUTI(dataUTI)
            let final = dirPath + "/" + base + "." + ext
            let tmp = final + ".part"
            do {
                try img.write(to: URL(fileURLWithPath: tmp), options: [])
                // rename .part -> final (atomic on same volume)
                try FileManager.default.moveItem(atPath: tmp, toPath: final)
                ok = true
                log("EXPORTED \(final) (\(img.count) bytes)" + (attempt > 0 ? " (retry \(attempt))" : ""))
            } catch {
                log("ERR write \(final): \(error)")
                try? FileManager.default.removeItem(atPath: tmp)
            }
        })
        if ok { break }
    }

    if ok { exported += 1; appendManifest(uuid) } else if !dryRun { failed += 1 }
}
log("SUMMARY exported=\(exported) skipped=\(skipped) failed=\(failed)")
exit(0)