// photoexport_core.swift — PURE logic for photo-export (no top-level code, no
// Photos/SMB dependencies). This is the SINGLE SOURCE OF TRUTH compiled into
// both the app binary and the test driver, so tests exercise the real code —
// not a mirror. Never put top-level executable statements here.
import Foundation
import UniformTypeIdentifiers

// ---- config parsing ----
// Parse a KEY=VALUE line list (the photo-export config.toml format).
// Returns the value for `key`, or nil if absent. Pure (takes raw string).
func parseConfigValue(_ raw: String?, _ key: String) -> String? {
    guard let raw = raw else { return nil }
    for lineObj in raw.split(separator: "\n") {
        let line = String(lineObj).trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || line.hasPrefix("#") { continue }
        let parts = line.split(separator: "=")
        if parts.count >= 2 && parts[0].trimmingCharacters(in: .whitespacesAndNewlines) == key {
            var v = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            // strip surrounding quotes so `dest = "/tmp/x"` → /tmp/x
            if v.count >= 2, v.first == "\"", v.last == "\"" {
                v.removeFirst()
                v.removeLast()
            }
            return v
        }
    }
    return nil
}

// ---- guard: refuse to export to SMB mount path when not mounted ----
// This prevents the "silent local writes" failure mode (139GB dumped locally).
// Pure: callers supply the mounted probe result.
func shouldRefuseToExport(destDir: String, configDest: String?, isMounted: Bool) -> Bool {
    if isMounted { return false }
    // If dest is the default SMB mount path, OR equals the config's dest
    // (which is normally the mount), and the destination isn't mounted,
    // refuse — this dest is meant to be an SMB share.
    let destIsDefaultSMB = destDir == "/tmp/sophrosyne-photos"
        || (configDest != nil && destDir == configDest)
    return destIsDefaultSMB
}

// ---- UTI -> extension ----
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
        if let t = UTType(uti), let ext = t.preferredFilenameExtension {
            return ext
        }
        return "jpg"
    }
}

// ---- manifest ----
// Parse a newline-separated manifest into a Set of done UUIDs.
func parseManifest(_ raw: String?) -> Set<String> {
    guard let raw = raw, !raw.isEmpty else { return [] }
    return Set(raw.split(separator: "\n").map { String($0) })
}

// ---- date dir ----
func dateDirPath(_ destRoot: String, _ year: String, _ month: String) -> String {
    return "\(destRoot)/\(year)/\(month)"
}

// ---- on-disk dedup ----
// Examine a dir listing (metadata strings only — never file contents, so no
// SSD wear) and classify how the target filename relates to what's on disk.
// Returns whether a plain (case-insensitive) name match exists, and how many
// osxphotos-style suffix variants ("name (1)", "name (2)", …) already exist.
// Used to (a) skip photos already in the old tree, and (b) write same-name
// collisions under a free " (N)" suffix instead of overwriting or dropping.
func existingNameStatus(_ existing: [String], _ wantName: String) -> (plainExists: Bool, variantCount: Int) {
    let base = wantName.lowercased()
    var plain = false
    var variants = 0
    for e in existing {
        let el = e.lowercased()
        if el == base { plain = true; continue }
        // osxphotos-style suffix: "name (1)", "name (12)" — digits only
        if el.hasPrefix(base + " (") && el.hasSuffix(")") {
            let inner = String(el.dropFirst(base.count + 2).dropLast())
            if !inner.isEmpty, inner.allSatisfy({ $0.isNumber }) { variants += 1 }
        }
    }
    return (plain, variants)
}

// ---- safe basename (strip trailing extension) ----
func safeBaseName(_ original: String?) -> String? {
    guard let original, !original.isEmpty else { return nil }
    let parts = original.split(separator: ".")
    if parts.count > 1 {
        return parts[0..<parts.count - 1].joined(separator: ".")
    }
    return original
}
