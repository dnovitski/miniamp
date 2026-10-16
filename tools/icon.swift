// Renders the Miniamp icon: a database stack on a violet squircle with a green "running" badge.
//   swift icon.swift <out.iconset>     -> all macOS iconset sizes
//   swift icon.swift <out.png> <px>    -> single PNG (e.g. logo.png for the GitLab avatar)
import AppKit

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // Background squircle with soft drop shadow (macOS icon grid: 10% margin).
    let tile = NSRect(x: s * 0.1, y: s * 0.11, width: s * 0.8, height: s * 0.8)
    let squircle = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowColor = color(0x000000, 0.35)
    tileShadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    tileShadow.shadowBlurRadius = s * 0.03
    tileShadow.set()
    color(0x4B3BD6).setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x9384FF), color(0x5B47F0), color(0x3A27B8)])!.draw(in: squircle, angle: -90)

    // Database cylinder.
    let w = s * 0.40, e = s * 0.12, x = (s - w) / 2
    let bottom = s * 0.30, top = s * 0.70  // ellipse centre lines
    let body = NSBezierPath()
    body.append(NSBezierPath(ovalIn: NSRect(x: x, y: bottom - e / 2, width: w, height: e)))
    body.append(NSBezierPath(rect: NSRect(x: x, y: bottom, width: w, height: top - bottom)))
    body.windingRule = .nonZero

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x1A0F66, 0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.015)
    shadow.shadowBlurRadius = s * 0.035
    shadow.set()
    color(0xFFFFFF).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Rounded shading across the body.
    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    NSGradient(colors: [color(0xD9D4FF), color(0xFFFFFF), color(0xF4F2FF), color(0xC9C2FF)],
               atLocations: [0, 0.35, 0.65, 1], colorSpace: .sRGB)!
        .draw(in: NSRect(x: x, y: bottom - e, width: w, height: top - bottom + 2 * e), angle: 0)
    NSGraphicsContext.restoreGraphicsState()

    // Segment separators: front halves of ellipses.
    for y in [bottom + (top - bottom) / 3, bottom + 2 * (top - bottom) / 3] {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: x - 1, y: y - e, width: w + 2, height: e)).addClip()
        let line = NSBezierPath(ovalIn: NSRect(x: x, y: y - e / 2, width: w, height: e))
        line.lineWidth = s * 0.022
        color(0x5B47F0).setStroke()
        line.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    // Top face.
    let lid = NSBezierPath(ovalIn: NSRect(x: x, y: top - e / 2, width: w, height: e))
    NSGradient(colors: [color(0xFFFFFF), color(0xE3DEFF)])!.draw(in: lid, angle: -90)
    lid.lineWidth = s * 0.008
    color(0xB9B0FF).setStroke()
    lid.stroke()

    // Green "running" badge with play glyph.
    let r = s * 0.115
    let c = NSPoint(x: x + w - s * 0.01, y: bottom - s * 0.005)
    let ring = NSBezierPath(ovalIn: NSRect(x: c.x - r - s * 0.018, y: c.y - r - s * 0.018,
                                           width: 2 * (r + s * 0.018), height: 2 * (r + s * 0.018)))
    NSGraphicsContext.saveGraphicsState()
    let badgeShadow = NSShadow()
    badgeShadow.shadowColor = color(0x000000, 0.3)
    badgeShadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    badgeShadow.shadowBlurRadius = s * 0.02
    badgeShadow.set()
    color(0xFFFFFF).setFill()
    ring.fill()
    NSGraphicsContext.restoreGraphicsState()
    let badge = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    NSGradient(colors: [color(0x5EE07F), color(0x28B44E)])!.draw(in: badge, angle: -90)
    let play = NSBezierPath()
    let t = r * 0.95
    play.move(to: NSPoint(x: c.x - t * 0.32, y: c.y + t * 0.45))
    play.line(to: NSPoint(x: c.x + t * 0.5, y: c.y))
    play.line(to: NSPoint(x: c.x - t * 0.32, y: c.y - t * 0.45))
    play.close()
    play.lineJoinStyle = .round
    play.lineWidth = s * 0.012
    color(0xFFFFFF).set()
    play.fill()
    play.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
if CommandLine.arguments.count > 2, let px = Int(CommandLine.arguments[2]) {
    try render(px).write(to: URL(fileURLWithPath: out))
} else {
    try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                       ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512),
                       ("512x512@2x", 1024)] {
        try render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
    }
}
