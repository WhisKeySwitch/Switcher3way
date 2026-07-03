#!/usr/bin/env swift
import AppKit

// Switcher3way icon — "Triadic Rotation":
// three iconic script letters (A / Я / Ї) on a shared orbit, bound by a gold cycle arc.

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.rounded) {
        return NSFont(descriptor: d, size: size) ?? base
    }
    return base
}

/// Draw one glyph optically centered on point p.
func drawGlyph(_ s: String, at p: NSPoint, fontSize: CGFloat, color: NSColor) {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: roundedFont(fontSize, .bold),
        .foregroundColor: color,
    ]
    let sz = s.size(withAttributes: attrs)
    // cap-height optical nudge so the letter sits visually centered, not baseline-centered
    let origin = NSPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2 + fontSize * 0.02)
    s.draw(at: origin, withAttributes: attrs)
}

func generateIcon(size: Int) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = CGFloat(size)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // ── Background superellipse-ish rounded tile ──
    let inset = s * 0.045
    let bgRect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = bgRect.width * 0.2237   // macOS-style continuous corner
    let bg = NSBezierPath(roundedRect: bgRect, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(colors: [
        NSColor(red: 0.16, green: 0.40, blue: 0.86, alpha: 1.0),  // azure (top)
        NSColor(red: 0.36, green: 0.20, blue: 0.78, alpha: 1.0),  // violet (bottom)
    ])!
    gradient.draw(in: bg, angle: -90)

    // Soft top highlight for depth
    bg.addClip()
    let hi = NSGradient(colors: [
        NSColor(white: 1.0, alpha: 0.14),
        NSColor(white: 1.0, alpha: 0.0),
    ])!
    hi.draw(in: NSRect(x: inset, y: s * 0.5, width: s - 2 * inset, height: s * 0.5 - inset), angle: -90)
    NSGraphicsContext.current!.cgContext.resetClip()

    // ── Orbit geometry ──
    let cx = s / 2, cy = s / 2
    let R = s * 0.235
    let letterAngles: [CGFloat] = [90, 210, 330]   // equilateral: top, lower-left, lower-right
    let glyphs = ["S", "Э", "Є"]                    // Latin/English · Russian-only (Э) · Ukrainian-only (Є)

    // ── Three-fold cycle: an arc between each pair of letters, each ending in an
    //    arrowhead pointing CCW → continuous rotation among the three (subtle blue+gold nod). ──
    let gold = NSColor(red: 1.0, green: 0.80, blue: 0.32, alpha: 0.95)
    let lw = s * 0.028
    let gap: CGFloat = 36            // degrees of clear space around each letter
    let ah = s * 0.05                // arrowhead length
    let spread: CGFloat = 0.46
    gold.setStroke(); gold.setFill()
    for a in letterAngles {
        let start = a + gap
        let end = a + 120 - gap      // sweep toward the next letter (CCW)
        let arc = NSBezierPath()
        arc.lineWidth = lw
        arc.lineCapStyle = .round
        arc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: R,
                      startAngle: start, endAngle: end, clockwise: false)
        arc.stroke()
        // arrowhead at the leading end, tip along the CCW tangent (angle + 90°)
        let er = end * .pi / 180
        let hx = cx + R * CGFloat(cos(er))
        let hy = cy + R * CGFloat(sin(er))
        let td = er + .pi / 2
        let back = td + .pi
        let head = NSBezierPath()
        head.move(to: NSPoint(x: hx + ah * CGFloat(cos(td)), y: hy + ah * CGFloat(sin(td))))            // tip
        head.line(to: NSPoint(x: hx + ah * CGFloat(cos(back - spread)), y: hy + ah * CGFloat(sin(back - spread))))
        head.line(to: NSPoint(x: hx + ah * CGFloat(cos(back + spread)), y: hy + ah * CGFloat(sin(back + spread))))
        head.close()
        head.fill()
    }

    // ── Glyphs on the orbit (drawn last, sitting in the gaps) ──
    let fs = s * 0.22
    for (i, angDeg) in letterAngles.enumerated() {
        let a = angDeg * .pi / 180.0
        let p = NSPoint(x: cx + R * CGFloat(cos(a)), y: cy + R * CGFloat(sin(a)))
        drawGlyph(glyphs[i].uppercased(), at: p, fontSize: fs, color: .white)
    }

    img.unlockFocus()
    return img
}

func saveAsPNG(_ image: NSImage, path: String, size: Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: path))
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconset = "\(outDir)/Switcher3way.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

// Preview at 1024 for review
saveAsPNG(generateIcon(size: 1024), path: "\(outDir)/preview_1024.png", size: 1024)

let iconsetSizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, size) in iconsetSizes {
    saveAsPNG(generateIcon(size: size), path: "\(iconset)/\(name)", size: size)
}
print("wrote \(iconset) and preview_1024.png")
