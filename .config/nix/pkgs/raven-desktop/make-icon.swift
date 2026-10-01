// Generates a PLACEHOLDER icon for the Raven desktop wrapper.
//
// This exists only because the repo has no Raven icon asset yet. It draws a
// stylised dark bird on a rounded-square background (the macOS app-icon shape)
// with AppKit, so no third-party tool is needed. It is NOT the Raven project's
// own artwork and carries no licence — the owner can replace the generated
// raven-icon.icns with any real icon (just overwrite that file).
//
// Usage: swift make-icon.swift <out.png>
// Then:  sips + iconutil turn the PNG(s) into raven-icon.icns (see the
//        sibling commands run by the developer, or just use the committed icns).

import AppKit

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write("usage: make-icon.swift <out.png>\n".data(using: .utf8)!)
    exit(2)
}
let outPath = args[1]

let size = 1024.0
guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.current = ctx

let rect = NSRect(x: 0, y: 0, width: size, height: size)

// Rounded-square app tile, dark slate to near-black.
let tile = NSBezierPath(roundedRect: rect, xRadius: size * 0.225, yRadius: size * 0.225)
let bg = NSGradient(colors: [
    NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.28, alpha: 1.0),
    NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1.0),
])!
bg.draw(in: tile, angle: -90)

// Simple bird silhouette: body (teardrop), head (circle), beak (triangle),
// tail and wing accents — deliberately a plain glyph, not a real logo.
let ink = NSColor(calibratedRed: 0.93, green: 0.91, blue: 0.86, alpha: 1.0)
ink.setFill()

// Body
let body = NSBezierPath()
body.move(to: NSPoint(x: size * 0.30, y: size * 0.24))
body.curve(to: NSPoint(x: size * 0.58, y: size * 0.62),
           controlPoint1: NSPoint(x: size * 0.30, y: size * 0.46),
           controlPoint2: NSPoint(x: size * 0.42, y: size * 0.60))
body.curve(to: NSPoint(x: size * 0.72, y: size * 0.30),
           controlPoint1: NSPoint(x: size * 0.70, y: size * 0.60),
           controlPoint2: NSPoint(x: size * 0.76, y: size * 0.44))
body.curve(to: NSPoint(x: size * 0.30, y: size * 0.24),
           controlPoint1: NSPoint(x: size * 0.60, y: size * 0.22),
           controlPoint2: NSPoint(x: size * 0.42, y: size * 0.22))
body.fill()

// Head
let head = NSBezierPath(ovalIn: NSRect(
    x: size * 0.55, y: size * 0.56,
    width: size * 0.24, height: size * 0.24))
head.fill()

// Beak
let beak = NSBezierPath()
beak.move(to: NSPoint(x: size * 0.79, y: size * 0.68))
beak.line(to: NSPoint(x: size * 0.94, y: size * 0.63))
beak.line(to: NSPoint(x: size * 0.79, y: size * 0.60))
beak.close()
beak.fill()

// Tail
let tail = NSBezierPath()
tail.move(to: NSPoint(x: size * 0.34, y: size * 0.30))
tail.line(to: NSPoint(x: size * 0.14, y: size * 0.12))
tail.line(to: NSPoint(x: size * 0.46, y: size * 0.24))
tail.close()
tail.fill()

// Eye (cut-out)
NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1.0).setFill()
let eye = NSBezierPath(ovalIn: NSRect(
    x: size * 0.66, y: size * 0.70,
    width: size * 0.055, height: size * 0.055))
eye.fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
do {
    try png.write(to: URL(fileURLWithPath: outPath))
} catch {
    FileHandle.standardError.write("could not write \(outPath): \(error)\n".data(using: .utf8)!)
    exit(1)
}
