// photoexport_core.swift — pure logic shared by photo-export CLI and its tests
// No Foundation/Photos imports here; must compile in isolation for unit tests.

// UTI -> preferred filename extension (mirror of extForUTI in photo-export.swift).
public func extForUTI(_ uti: String?) -> String {
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
    default: return "jpg"
    }
}

// Parse a newline-separated manifest into a Set of done UUIDs.
func parseManifest(_ raw: String?) -> Set<String> {
    guard let raw = raw, !raw.isEmpty else { return [] }
    return Set(raw.split(separator: "\n").map { String($0) })
}

// Build a yyyy/mm directory path from a date + dest root.
// Not Foundation-dependent (uses tuple year/month strings).
func dateDirPath(_ destRoot: String, _ year: String, _ month: String) -> String {
    return "\(destRoot)/\(year)/\(month)"
}

// Derive a safe base filename from original filename (strip path ext).
func safeBaseName(_ original: String?) -> String? {
    guard let original, !original.isEmpty else { return nil }
    // remove trailing extension:  IMG_1234.HEIC -> IMG_1234, IMG.2024.JPG -> IMG.2024
    let parts = original.split(separator: ".")
    if parts.count > 1 {
        // drop last component (extension), rejoin with dots
        return parts[0..<parts.count - 1].joined(separator: ".")
    }
    return original
}