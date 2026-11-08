// Renders the app icon: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

func render(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size / 1024
    ctx.scaleBy(x: s, y: s)

    let gold = NSColor(red: 0.91, green: 0.75, blue: 0.47, alpha: 1)
    let goldDeep = NSColor(red: 0.62, green: 0.46, blue: 0.22, alpha: 1)
    let mint = NSColor(red: 0.38, green: 0.93, blue: 0.70, alpha: 1)

    // Squircle body
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor.black.withAlphaComponent(0.5).cgColor)
    NSGradient(colors: [NSColor(red: 0.13, green: 0.12, blue: 0.15, alpha: 1), NSColor(red: 0.03, green: 0.03, blue: 0.04, alpha: 1)])!
        .draw(in: body, angle: -90)
    ctx.restoreGState()
    body.addClip()

    // Warm glow
    NSGradient(colors: [gold.withAlphaComponent(0.28), .clear])!
        .draw(fromCenter: NSPoint(x: 512, y: 470), radius: 0, toCenter: NSPoint(x: 512, y: 470), radius: 520, options: [])

    // Keys along the bottom
    let keyTop: CGFloat = 330
    let keyW: CGFloat = 824 / 7
    for i in 0..<7 {
        let r = NSRect(x: 100 + CGFloat(i) * keyW + 3, y: 100, width: keyW - 6, height: keyTop - 100)
        NSGradient(colors: [NSColor(red: 0.97, green: 0.94, blue: 0.89, alpha: 1), NSColor(red: 0.82, green: 0.78, blue: 0.70, alpha: 1)])!
            .draw(in: NSBezierPath(rect: r), angle: -90)
    }
    for i in [1, 2, 4, 5, 6] {
        let x = 100 + CGFloat(i) * keyW - keyW * 0.3
        let r = NSRect(x: x, y: 190, width: keyW * 0.6, height: keyTop - 190)
        NSGradient(colors: [NSColor(white: 0.18, alpha: 1), NSColor(white: 0.03, alpha: 1)])!.draw(in: NSBezierPath(rect: r), angle: -90)
    }
    NSColor(red: 0.42, green: 0.07, blue: 0.10, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 100, y: keyTop, width: 824, height: 12)).fill()

    // Gauge arc
    let center = NSPoint(x: 512, y: 400)
    let radius: CGFloat = 400
    func pt(_ deg: CGFloat, _ r: CGFloat) -> NSPoint {
        let a = deg * .pi / 180
        return NSPoint(x: center.x + r * sin(a), y: center.y + r * cos(a))
    }
    let arc = NSBezierPath()
    arc.appendArc(withCenter: center, radius: radius, startAngle: 140, endAngle: 40, clockwise: true)
    arc.lineWidth = 26
    arc.lineCapStyle = .round
    goldDeep.withAlphaComponent(0.55).setStroke()
    arc.stroke()
    let zone = NSBezierPath()
    zone.appendArc(withCenter: center, radius: radius, startAngle: 95, endAngle: 85, clockwise: true)
    zone.lineWidth = 26
    zone.lineCapStyle = .round
    mint.setStroke()
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 30, color: mint.cgColor)
    zone.stroke()
    ctx.restoreGState()
    for d in stride(from: -50, through: 50, by: 10) {
        let t = NSBezierPath()
        t.move(to: pt(CGFloat(d), radius + 30))
        t.line(to: pt(CGFloat(d), radius + (d == 0 ? 80 : 60)))
        t.lineWidth = d == 0 ? 10 : 6
        t.lineCapStyle = .round
        (d == 0 ? gold : NSColor.white.withAlphaComponent(0.4)).setStroke()
        t.stroke()
    }

    // Needle
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: mint.cgColor)
    let needle = NSBezierPath()
    needle.move(to: pt(4, radius + 10))
    needle.line(to: NSPoint(x: center.x + 16, y: center.y))
    needle.line(to: NSPoint(x: center.x - 16, y: center.y))
    needle.close()
    NSGradient(colors: [mint, .white])!.draw(in: needle, angle: 90)
    ctx.restoreGState()

    let cap = NSBezierPath(ovalIn: NSRect(x: center.x - 44, y: center.y - 44, width: 88, height: 88))
    NSGradient(colors: [gold, goldDeep])!.draw(in: cap, angle: -60)
    NSColor.black.setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = CGFloat(base * scale)
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(size: px).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
try! render(size: 1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "docs/icon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out]
try! p.run()
p.waitUntilExit()
print("Wrote \(out)")
