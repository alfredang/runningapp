// Generates the RunTrack GPS 1024×1024 App Store icon.
// App Store compliant: opaque, NO alpha channel (CGContext with .noneSkipLast).
// Design: a bold white runner (SF Symbol) with motion lines + a GPS route arc,
// on a deep-navy → vivid-blue gradient.
// Usage:  swift scripts/make_app_icon.swift [outputPath]
import AppKit
import UniformTypeIdentifiers

let px = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/AppIcon-1024.png"
let S = CGFloat(px)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let cg = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                         bytesPerRow: 0, space: cs,
                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("could not create CGContext")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
let ctx = cg
let full = NSRect(x: 0, y: 0, width: S, height: S)

// --- Background: deep navy → vivid blue diagonal gradient ---
let navy = NSColor(srgbRed: 0.04, green: 0.10, blue: 0.30, alpha: 1)
let blue = NSColor(srgbRed: 0.16, green: 0.46, blue: 0.97, alpha: 1)
NSGradient(starting: navy, ending: blue)!.draw(in: full, angle: -55)
// Soft radial highlight (upper-left) for depth.
let hi = NSGradient(colors: [NSColor(white: 1, alpha: 0.20), NSColor(white: 1, alpha: 0)])!
hi.draw(in: full, relativeCenterPosition: NSPoint(x: -0.35, y: 0.45))

// --- GPS route arc sweeping under the runner ---
ctx.saveGState()
let arc = NSBezierPath()
arc.lineWidth = S * 0.035
arc.lineCapStyle = .round
arc.move(to: NSPoint(x: S*0.16, y: S*0.30))
arc.curve(to: NSPoint(x: S*0.84, y: S*0.34),
          controlPoint1: NSPoint(x: S*0.36, y: S*0.16),
          controlPoint2: NSPoint(x: S*0.66, y: S*0.18))
NSColor(white: 1, alpha: 0.30).setStroke()
arc.stroke()
// Start dot + end pin on the route.
NSColor(white: 1, alpha: 0.9).setFill()
let r = S*0.028
NSBezierPath(ovalIn: NSRect(x: S*0.16 - r, y: S*0.30 - r, width: r*2, height: r*2)).fill()
NSBezierPath(ovalIn: NSRect(x: S*0.84 - r, y: S*0.34 - r, width: r*2, height: r*2)).fill()
ctx.restoreGState()

// --- Motion / speed lines behind the runner (left side) ---
ctx.saveGState()
NSColor(white: 1, alpha: 0.55).setStroke()
let speeds: [(y: CGFloat, x0: CGFloat, x1: CGFloat, a: CGFloat)] = [
    (0.66, 0.10, 0.30, 0.65),
    (0.56, 0.07, 0.31, 0.45),
    (0.46, 0.12, 0.32, 0.30),
]
for s in speeds {
    let p = NSBezierPath()
    p.lineWidth = S * 0.028
    p.lineCapStyle = .round
    NSColor(white: 1, alpha: s.a).setStroke()
    p.move(to: NSPoint(x: S*s.x0, y: S*s.y))
    p.line(to: NSPoint(x: S*s.x1, y: S*s.y))
    p.stroke()
}
ctx.restoreGState()

// --- Runner (SF Symbol "figure.run"), tinted white, centered-right ---
func tintedSymbol(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
    let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .black)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else { return nil }
    let img = NSImage(size: base.size)
    img.lockFocus()
    base.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    color.set()
    NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
    img.unlockFocus()
    img.isTemplate = false
    return img
}

if let runner = tintedSymbol("figure.run", pointSize: 600, color: .white) {
    let targetH = S * 0.60
    let scale = targetH / runner.size.height
    let w = runner.size.width * scale
    let rect = NSRect(x: S*0.55 - w/2, y: S*0.30, width: w, height: targetH)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30,
                  color: NSColor(white: 0, alpha: 0.22).cgColor)
    runner.draw(in: rect)
    ctx.restoreGState()
} else {
    // Fallback: a simple white circle if the symbol is unavailable.
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: S*0.40, y: S*0.40, width: S*0.20, height: S*0.20)).fill()
}

NSGraphicsContext.restoreGraphicsState()

guard let image = cg.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil) else {
    fatalError("could not encode PNG")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out) (\(px)×\(px), no alpha)")
