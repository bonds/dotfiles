// test_core.swift — self-contained unit tests for photo-export pure logic
// (UTI map, manifest parse, date-dir, safe basename). Compiled as ONE file
// because Swift 6 only allows top-level script code in a single primary
// source. Keep these mirrors in sync with photoexport_core.swift.
import Foundation

// ---- mirrors of photoexport_core.swift ----
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
    default: return "jpg"
    }
}

func parseManifest(_ raw: String?) -> Set<String> {
    guard let raw = raw, !raw.isEmpty else { return [] }
    return Set(raw.split(separator: "\n").map { String($0) })
}

func dateDirPath(_ destRoot: String, _ year: String, _ month: String) -> String {
    return "\(destRoot)/\(year)/\(month)"
}

func safeBaseName(_ original: String?) -> String? {
    guard let original, !original.isEmpty else { return nil }
    let parts = original.split(separator: ".")
    if parts.count > 1 {
        return parts[0..<parts.count - 1].joined(separator: ".")
    }
    return original
}

// ---- test helpers ----
var failures = 0
func check(_ name: String, _ got: String, _ want: String) {
    let ok = got == want
    print((ok ? "PASS " : "FAIL ") + name + " — got=" + got + " want=" + want)
    if !ok { failures += 1 }
}
func checkCount(_ name: String, _ got: Int, _ want: Int) {
    let ok = got == want
    print((ok ? "PASS " : "FAIL ") + name + " — got=" + String(got) + " want=" + String(want))
    if !ok { failures += 1 }
}

// ---- tests ----
check("UTI png", extForUTI("public.png"), "png")
check("UTI jpeg", extForUTI("public.jpeg"), "jpg")
check("UTI heic", extForUTI("public.heic"), "heic")
check("UTI mov", extForUTI("com.apple.quicktime-movie"), "mov")
check("UTI unknown -> jpg", extForUTI("com.example.weird"), "jpg")
check("UTI nil -> jpg", extForUTI(nil), "jpg")

let m1 = parseManifest("AAA\nBBB\nCCC\n")
checkCount("manifest 3 lines", m1.count, 3)
check("manifest contains BBB", m1.contains("BBB") ? "yes" : "no", "yes")
checkCount("manifest empty", parseManifest("").count, 0)
checkCount("manifest nil", parseManifest(nil).count, 0)

check("date dir 2026/08", dateDirPath("/tmp/photos", "2026", "08"), "/tmp/photos/2026/08")

check("base no ext", safeBaseName("IMG_1234") ?? "", "IMG_1234")
check("base dotted", safeBaseName("IMG_1234.HEIC") ?? "", "IMG_1234")
check("base multi-dot", safeBaseName("IMG.2024.JPG") ?? "", "IMG.2024")
check("base nil", safeBaseName(nil) ?? "", "")

print(failures == 0 ? "ALL TESTS PASSED" : "TESTS FAILED: \(failures)")
Foundation.exit(failures == 0 ? 0 : 1)