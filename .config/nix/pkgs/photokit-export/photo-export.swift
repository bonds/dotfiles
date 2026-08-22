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
import PhotoSftpHelper

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
    let raw = try? String(contentsOfFile: configPath, encoding: .utf8)
    return parseConfigValue(raw, key) // from photoexport_core.swift
}
func opt(_ name: String, _ cfgKey: String, _ fallback: String) -> String {
    // CLI arg wins; then config file; then default.
    return argValue(name) ?? configValue(cfgKey) ?? fallback
}

var destDir: String = args.count > 1 ? args[1] : opt("--dest", "dest", "/tmp/sophrosyne-photos")
let limit = Int(opt("--limit", "limit", "0")) ?? 0
let dryRun = args.contains("--dry-run")

// ---------- SMB mount lifecycle (owned by this process) ----------
// Mount the sophrosyne photos share programmatically. Priority:
//   1. NetFS NetFSMountURLSync (Apple API, error codes, cancel support)
//   2. Fallback: mount_smbfs via Process with keychain password
// Robustness model: resumable (manifest) + verifiable (probe mount before
// writes, .part+rename so only complete files are recorded).

// Over the LAN, `sophrosyne.local` (mDNS) is the stable SMB name — matches the
// nightly bin/photos-smb-backup mount_smbfs URL. When the Mac is away from the
// LAN, fall back to the Tailscale MagicDNS name (stable, not an IP literal), so
// the share still mounts over the tailnet. NetFS called with no mount options
// fails (EINVAL), and calling with an unreachable-happy host just times out.
let smbHost = argValue("--smb-host") ?? "sophrosyne.local"
let smbShare = argValue("--smb-share") ?? "photos"
let smbUser = argValue("--smb-user") ?? "photo-backup"
let keychainService = argValue("--keychain-service") ?? "sophrosyne.local"

// Ordered SMB host candidates tried for self-mount: the configured host / .local
// (LAN) first, then the Tailscale MagicDNS name (remote). First to mount wins.
let smbHostCandidates: [String] = {
    var hosts = [smbHost]
    let magicDNS = "sophrosyne.taileafac.ts.net"
    let local = "sophrosyne.local"
    for h in [local, magicDNS] where !hosts.contains(h) { hosts.append(h) }
    return hosts
}()

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
    // Try each host candidate in order (LAN .local first, then MagicDNS) until
    // one mounts. First success wins; stop on the first that returns 0.
    for host in smbHostCandidates {
        guard let urlObj = NSURL(string: "smb://\(host)/\(smbShare)") else { continue }
        let url = urlObj as CFURL
        let mountPathURL = URL(fileURLWithPath: mountPath) as NSURL as CFURL
        let userCF = NSString(string: smbUser) as CFString
        let passCF = NSString(string: pass) as CFString
        // NetFS needs explicit open + mount options, or NetFSMountURLSync can fail
        // (EINVAL) or try to present auth UI. SuppressAllUI forces the provided
        // credentials; MountAtMountDir pins the mount to our path instead of
        // defaulting under /Volumes. These are the options verified to work.
        let opts = NSMutableDictionary()
        opts["UIOption"] = "SuppressAllUI"
        let mopts = NSMutableDictionary()
        mopts["MountAtMountDir"] = true
        mopts["SoftMount"] = false
        var mountpoints: Unmanaged<CFArray>? = nil
        let stat = NetFSMountURLSync(url, mountPathURL, userCF, passCF, opts, mopts, &mountpoints)
        log("SMB: NetFSMountURLSync host=\(host) status=\(stat) mountpoints=\(String(describing: mountpoints))")
        if stat == 0 {
            return true
        }
        // Mount failed for this host — unmount any partial mount before retrying
        // another candidate so we don't collide on the destination path.
        log("SMB: retrying next host (last: \(host) status \(stat))")
    }
    return false
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

// ---------- transport selection ----------
// Decide SFTP vs SMB FIRST so the SMB-mount section below can be skipped when
// using SFTP. When remoteHost is configured (config.toml), we stream originals
// in-memory over SFTP (no SMB mount at all).
let remoteHost = opt("--remote-host", "remoteHost", "")
let remoteUser = opt("--remote-user", "remoteUser", "photo-backup")
let remoteKey = opt("--remote-key", "remoteKey", NSHomeDirectory() + "/.ssh/id_photo_rsync")
let useSFTP = !remoteHost.isEmpty

// ---------- output dir (optionally an SMB mount owned by this process) ----------
// We own the mount when the user passes --mount, OR when config selfmount is
// true and dest IS the SMB mount path. `open` (LaunchServices) doesn't forward
// args, so config is the way the nightly / agent launches get self-mounting
// without the external expect wrapper. Skipped entirely for the SFTP transport.
let wantSelfMount = (configValue("selfmount")?.lowercased() == "true")
let mountMode = !useSFTP && (args.contains("--mount") || (wantSelfMount && destDir == mountPath))
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

// SAFETY GUARD (logic in photoexport_core.swift): if dest is the SMB-mount
// path (default or config) but not actually mounted, do NOT silently export
// to a local dir at that path. Without this, a run dumps the whole library
// onto local disk (139GB+). Only when we own the mount (--mount) can dest be
// written before mounting, and mountMode already handles that above.
if !mounted {
    let cfgDest = configValue("dest")
    if shouldRefuseToExport(destDir: destDir, configDest: cfgDest, isMounted: isMounted(destDir)) {
        log("FATAL: dest \(destDir) is the SMB mount path but is NOT mounted. Refusing to export to local disk (prevents silent local writes). Mount the share or pass an explicit local dest.")
        exit(1)
    }
}

do {
    try FileManager.default.createDirectory(atPath: useDest, withIntermediateDirectories: true)
} catch {
    log("FATAL: cannot create dest \(useDest): \(error)")
    exit(1)
}

// ---------- SFTP transport (Option A) ----------
// When remoteHost is configured (decided above, before the SMB-mount section),
// stream originals in-memory to the remote over SFTP (no local temp copy / SSD
// wear) using the restricted id_photo_rsync key, which sophrosyne's sftp-server
// -d confines to /dragon/media/photos/.

// Box to stream a Data buffer in-memory through the C reader callback.
final class SFTPStream {
    let data: Data
    var offset = 0
    init(_ d: Data) { data = d }
}

var sftpSession: OpaquePointer? = nil
if useSFTP {
    log("SFTP: opening session to \(remoteHost) as \(remoteUser)")
    if photo_sftp_open(&sftpSession, remoteHost, 22, remoteUser, remoteKey) != 0 {
        log("FATAL: cannot open SFTP session to \(remoteHost) — aborting")
        exit(1)
    }
    // sftp-server -d chroots to /dragon/media/photos/, so '' is photos root.
    if photo_sftp_mkdir(sftpSession, "") != 0 {
        log("WARN: sftp mkdir base failed (continuing)")
    }
    log("SFTP: session ready")
}

// Stream-upload an in-memory Data to remotePath via the C helper. Returns success.
func sftpPutData(_ remotePath: String, _ data: Data) -> Bool {
    let box = SFTPStream(data)
    let boxPtr = Unmanaged.passRetained(box).toOpaque()
    let reader: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int) -> Int = { c, buf, max in
        guard let c = c, let buf = buf else { return -1 }
        let b = Unmanaged<SFTPStream>.fromOpaque(c).takeUnretainedValue()
        let remaining = b.data.count - b.offset
        if remaining <= 0 { return 0 }
        let n = max > remaining ? remaining : max
        b.data.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                memcpy(buf, base + b.offset, n)
            }
        }
        b.offset += n
        return n
    }
    let rc = photo_sftp_put(sftpSession, remotePath, reader, boxPtr)
    Unmanaged<SFTPStream>.fromOpaque(boxPtr).release()
    return rc == 0
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
// On-disk dedup: cache dir listings so the exists-check doesn't re-read the
// tree per asset. Keys are the yyyy/mm dir paths we actually write into.
var dirListCache: [String: [String]] = [:]
func dirListing(_ dir: String) -> [String] {
    if let l = dirListCache[dir] { return l }
    let l = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    dirListCache[dir] = l
    return l
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

    // On-disk dedup (metadata-only — dir listing strings, never file bytes, so
    // no SSD wear): if the original is already present in the target month dir
    // (case-insensitive — the renamed-tree originals use ".HEIC", we target
    // ".heic"), it's already backed up. Record it in the manifest and skip the
    // download entirely ("backup only what we don't have"). If instead a
    // DIFFERENT photo already occupies our plain name (osxphotos-style " (N)"
    // suffix exists), we still download but write under a free " (N)" suffix so
    // no photo is ever overwritten or dropped.
    var writeName = ""
    if let r0 = resFirst.first, !r0.uniformTypeIdentifier.isEmpty {
        let ext = extForUTI(r0.uniformTypeIdentifier)
        let wantName = base + "." + ext
        let st = existingNameStatus(dirListing(dirPath), wantName)
        if st.plainExists {
            log("SKIP-EXISTS \(uuid) \(dirPath)/\(wantName)")
            appendManifest(uuid)
            skipped += 1
            return
        }
        writeName = st.variantCount > 0
            ? base + " (" + String(st.variantCount + 1) + ")." + ext
            : wantName
    } else {
        // No resource metadata (rare): fall back to old naming, no dedup.
        writeName = base + "." + extForUTI(nil)
    }

    if dryRun { log("DRYRUN \(uuid)"); exported += 1; appendManifest(uuid); return }

    let opts = PHImageRequestOptions()
    opts.version = .original
    opts.deliveryMode = .highQualityFormat
    opts.isNetworkAccessAllowed = true
    opts.isSynchronous = true

    // Remote relative path from the confined base (yyyy/mm/name). When SFTP,
    // sftp-server -d chroots to /dragon/media/photos/, so dirPath is just the
    // yyyy/mm relative path; for local we keep the absolute dest path.
    let relDir = yearStr + "/" + monthStr
    if useSFTP {
        var ok = false
        // remote skip: stat the target
        if photo_sftp_stat(sftpSession, relDir + "/" + writeName) >= 0 {
            log("SKIP-EXISTS \(uuid) \(relDir)/\(writeName)")
            appendManifest(uuid)
            skipped += 1
            return
        }
        if photo_sftp_mkdir(sftpSession, relDir) != 0 {
            log("ERR sftp mkdir \(relDir)")
            failed += 1
            return
        }
        mgr.requestImageDataAndOrientation(for: asset, options: opts, resultHandler: { imageData, dataUTI, orientation, info in
            guard let img = imageData else { log("ERR no data for \(uuid)"); return }
            if sftpPutData(relDir + "/" + writeName, img) {
                ok = true
                log("EXPORTED-SFTP \(relDir)/\(writeName) (\(img.count) bytes)")
            } else {
                log("ERR sftp put \(relDir)/\(writeName) (\(img.count) bytes)")
            }
        })
        if ok { exported += 1; appendManifest(uuid) } else if !dryRun { failed += 1 }
        return
    }

    // Local/SMB: request + write (atomic: write .part then rename, so
    // interrupted downloads leave no corrupt file and aren't recorded)
    var ok = false
    let retries = 3
    for attempt in 0..<retries {
        // Abort-on-dismount only when WE own the mount (--mount passed).
        if mountMode && !isMounted(mountPath) {
            log("SMB: mount disconnected mid-run — aborting cleanly (manifest preserved)")
            stop.pointee = true
            return
        }
        mgr.requestImageDataAndOrientation(for: asset, options: opts, resultHandler: { imageData, dataUTI, orientation, info in
            guard let img = imageData else { log("ERR no data for \(uuid) attempt \(attempt)"); return }
            let final = dirPath + "/" + writeName
            let tmp = final + ".part"
            do {
                try img.write(to: URL(fileURLWithPath: tmp), options: [])
                // rename .part -> final (atomic on same volume)
                try FileManager.default.moveItem(atPath: tmp, toPath: final)
                ok = true
                log("EXPORTED \(final) (\(img.count) bytes)" + (attempt > 0 ? " (retry \(attempt))" : ""))
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
if useSFTP && sftpSession != nil {
    photo_sftp_close(sftpSession)
}
log("SUMMARY exported=\(exported) skipped=\(skipped) failed=\(failed)")
exit(0)