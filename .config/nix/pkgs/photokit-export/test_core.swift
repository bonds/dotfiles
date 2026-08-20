// test_core.swift — comprehensive tests for photoexport_core.swift.
// Compiled with photoexport_core.swift as `main.swift` (top-level code legal
// there in multi-file builds), e.g.:
//   swiftc photoexport_core.swift test_core.swift -o test  # fails (name)
//   cp test_core.swift main.swift && swiftc photoexport_core.swift main.swift
// Exercises the REAL core functions (single source of truth), not copies.
// Exit 0 if all pass, 1 otherwise.

import Foundation

var failures = 0
var passed = 0
func check(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond {
        passed += 1
        print("PASS \(name)")
    } else {
        failures += 1
        print("FAIL \(name)\(detail.isEmpty ? "" : " — \(detail)")")
    }
}
func checkEq(_ name: String, _ got: String, _ want: String) {
    check(name, got == want, "got=\"\(got)\" want=\"\(want)\"")
}
func checkCount(_ name: String, _ got: Int, _ want: Int) {
    check(name, got == want, "got=\(got) want=\(want)")
}

// ================= config parsing =================
let cfg1 = """
# comment
dest = "/tmp/sophrosyne-photos"
limit = 0
manifest = "~/.cache/photo-export-manifest.txt"

"""
checkEq("cfg dest", parseConfigValue(cfg1, "dest") ?? "", "/tmp/sophrosyne-photos")
checkEq("cfg limit", parseConfigValue(cfg1, "limit") ?? "", "0")
checkEq("cfg manifest quoted", parseConfigValue(cfg1, "manifest") ?? "", "~/.cache/photo-export-manifest.txt")
check("cfg missing key", parseConfigValue(cfg1, "nope") == nil)
check("cfg nil raw", parseConfigValue(nil, "dest") == nil)
check("cfg empty raw", parseConfigValue("", "dest") == nil)

// ================= the guard (regression: 139GB silent local writes) =================
// REFUSE when dest is the default SMB path and NOT mounted
check("guard: default SMB dest, not mounted -> refuse",
      shouldRefuseToExport(destDir: "/tmp/sophrosyne-photos", configDest: nil, isMounted: false))
// REFUSE when dest == config dest (a mount path) and NOT mounted
check("guard: config dest, not mounted -> refuse",
      shouldRefuseToExport(destDir: "/mnt/photos", configDest: "/mnt/photos", isMounted: false))
// ALLOW when the mount IS present
check("guard: default SMB dest, mounted -> allow",
      !shouldRefuseToExport(destDir: "/tmp/sophrosyne-photos", configDest: nil, isMounted: true))
check("guard: config dest, mounted -> allow",
      !shouldRefuseToExport(destDir: "/mnt/photos", configDest: "/mnt/photos", isMounted: true))
// ALLOW for a plain local dest that is NOT the SMB path (legit local run)
check("guard: local dest, not mounted -> allow",
      !shouldRefuseToExport(destDir: "/tmp/photokit-local", configDest: nil, isMounted: false))
check("guard: local dest even if config points at SMB -> allow (dest differs)",
      !shouldRefuseToExport(destDir: "/tmp/photokit-local", configDest: "/tmp/sophrosyne-photos", isMounted: false))
// Config dest present + custom dest that matches config but isn't a mount
check("guard: dest equals non-default config dest, unmounted -> refuse",
      shouldRefuseToExport(destDir: "/Volumes/backups/photos", configDest: "/Volumes/backups/photos", isMounted: false))

// ================= UTI -> extension =================
checkEq("uti png", extForUTI("public.png"), "png")
checkEq("uti jpeg", extForUTI("public.jpeg"), "jpg")
checkEq("uti jpg", extForUTI("public.jpg"), "jpg")
checkEq("uti heic", extForUTI("public.heic"), "heic")
checkEq("uti heif", extForUTI("public.heif"), "heic")
checkEq("uti gif", extForUTI("com.compuserve.gif"), "gif")
checkEq("uti tiff", extForUTI("public.tiff"), "tiff")
checkEq("uti mov", extForUTI("com.apple.quicktime-movie"), "mov")
checkEq("uti mp4", extForUTI("public.mpeg-4-video"), "mp4")
checkEq("uti dng", extForUTI("com.adobe.raw-image"), "dng")
checkEq("uti unknown -> jpg", extForUTI("com.example.weird"), "jpg")
checkEq("uti nil -> jpg", extForUTI(nil), "jpg")

// ================= manifest =================
let m = parseManifest("AAA\nBBB\nCCC\n")
checkCount("manifest 3 lines", m.count, 3)
check("manifest has BBB", m.contains("BBB"))
checkCount("manifest empty str", parseManifest("").count, 0)
checkCount("manifest nil", parseManifest(nil).count, 0)
check("manifest dedups", parseManifest("X\nX\n").count == 1)
checkCount("manifest trailing newline only", parseManifest("\n").count, 0)

// ================= date dir =================
checkEq("date dir", dateDirPath("/tmp/photos", "2026", "08"), "/tmp/photos/2026/08")
checkEq("date dir empty month", dateDirPath("/x", "2026", ""), "/x/2026/")

// ================= safe basename =================
checkEq("base no ext", safeBaseName("IMG_1234") ?? "", "IMG_1234")
checkEq("base dotted", safeBaseName("IMG_1234.HEIC") ?? "", "IMG_1234")
checkEq("base multi-dot", safeBaseName("IMG.2024.JPG") ?? "", "IMG.2024")
checkEq("base nil", safeBaseName(nil) ?? "", "")
checkEq("base empty", safeBaseName("") ?? "", "")
checkEq("base leading dot", safeBaseName(".hidden") ?? "", ".hidden")

// ================= summary =================
print("")
print("\(passed) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)