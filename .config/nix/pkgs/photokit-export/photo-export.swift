// photo-export.swift — PhotoKit CLI for macOS photo backup (v0.2.0, mono-arch)
// Sole exporter for the nightly backup: fetches ALL assets (local + iCloud-
// only) via PhotoKit and writes them to an SMB mount. No osxphotos.
//
// Usage:
//   photo-export <dest-dir> [--limit N] [--dry-run] [--manifest /path/state.json]
//
// Behavior:
//   1. Request/resolve PhotoKit auth (once; user clicks Allow on first prompt)
//   2. Enumerate all assets via PHAsset (local + iCloud-optimized)
//   3. For each asset: fetch original via
//      PHImageManager.requestImageDataAndOrientation (proven path from probe)
//   4. Write to <dest>/<yyyy>/<mm>/<SafeFilename>.<utiext> (atomic .part+rename)
//   5. Write a basic XMP sidecar (description + create/modify dates)
//   6. Append localIdentifier to the manifest so re-runs skip completed files
// Logs to /tmp/photo-export.log (lines "photo-export: ..." for grepping).

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

// Config file override — `open --args` doesn't reliably forward args to a
// LaunchServices-registered app, so the nightly writes config here instead.
// Simple KEY = VALUE lines (no sections). CLI args, when present, take
// precedence over config values (for direct exec / testing).
let configPath = NSHomeDirectory() + "/Library/Application Support/photo-export/config.toml"
func configValue(_ key: String) -> String? {
    guard let raw = try? String(contentsOfFile: configPath, encoding: .utf8) else { return nil }
    for lineObj in raw.split(separator: "\n") {
        let line = String(lineObj).trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.split(separator: "=")
        if parts.count >= 2 && parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == key {
            return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    return nil
}
func opt(_ name: String, _ cfgKey: String, _ fallback: String) -> String {
    // CLI arg wins; then config file; then default.
    return argValue(name) ?? configValue(cfgKey) ?? fallback
}

var destDir: String = args.count > 1 ? args[1] : "/tmp/sophrosyne-photos"
let limit = Int(opt("--limit", "limit", "0")) ?? 0
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

let mountPath = opt("--mount", "mount", "/tmp/sophrosyne-photos")
var mounted = false

// ---------- manifest (resume support, plain text UUID-per-line) ----------
let manifestPath = opt("--manifest", "manifest", NSHomeDirectory() + "/.cache/photo-export-manifest.txt")
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

// ---------- basic XMP sidecar (description + dates from PhotoKit) ----------
func writeXmpSidecar(_ finalPath: String, _ photo: PHAsset) {
    // Minimal XMP sidecar: description + create/modify dates (what PhotoKit
    // exposes). Title/keywords/persons/GPS need Photos.sqlite parsing — skipped
    // (photos themselves are the backup priority; sidecar is a nice-to-have).
    let desc = photo.description
    var dateStr = ""
    if let cd = photo.creationDate {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        dateStr = f.string(from: cd)
    }

    let ext = finalPath.split(separator: ".").last.map(String.init) ?? ""
    let xmpPath = finalPath + ".xmp"

    var xml = "<?xpacket begin=\"\u{FEFF}\" id=\"W5M0MpCehiHzreSzNTczkc9d\"?>\n"
    xml += "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\" x:xmptk=\"photo-export\">\n"
    xml += "<rdf:RDF xmlns:rdf=\"http://www.w3.org/1999/02/22-rdf-syntax-ns#\">\n"
    xml += "<rdf:Description rdf:about=\"\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:photoshop=\"http://ns.adobe.com/photoshop/1.0/\">\n"
    xml += " <photoshop:SidecarForExtension>" + ext + "</photoshop:SidecarForExtension>\n"
    xml += " <dc:description>\n  <rdf:Alt>\n"
    if desc.isEmpty {
        xml += "   <rdf:li xml:lang='x-default'/>\n"
    } else {
        xml += "   <rdf:li xml:lang='x-default'>" + desc + "</rdf:li>\n"
    }
    xml += "  </rdf:Alt>\n </dc:description>\n"
    xml += " <dc:title>\n  <rdf:Alt>\n   <rdf:li xml:lang='x-default'/>\n  </rdf:Alt>\n </dc:title>\n"
    xml += "</rdf:Description>\n"
    xml += "<rdf:Description rdf:about=\"\" xmlns:xmp=\"http://ns.adobe.com/xap/1.0/\">\n"
    if !dateStr.isEmpty {
        xml += " <xmp:CreateDate>" + dateStr + "</xmp:CreateDate>\n"
        xml += " <xmp:ModifyDate>" + dateStr + "</xmp:ModifyDate>\n"
    }
    xml += "</rdf:Description>\n"
    xml += "</rdf:RDF>\n</x:xmpmeta>\n<?xpacket end=\"w\"?>"

    do {
        try xml.write(toFile: xmpPath, atomically: true, encoding: .utf8)
    } catch {
        log("WARN: could not write sidecar \(xmpPath): \(error)")
    }
    log("SIDECAR \(xmpPath)")
}
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
        // Abort-on-dismount only when WE own the mount (--mount passed).
        // When running against an external/local dir, don't require it to be
        // a mount at all — just let the write fail and retry if it's broken.
        if mountMode && !isMounted(mountPath) {
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
                // basic XMP sidecar (description + dates) — nice-to-have
                writeXmpSidecar(final, asset)
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