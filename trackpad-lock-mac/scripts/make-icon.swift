import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for nominal in [16, 32, 128, 256, 512] {
    for scale in 1...2 {
        let size = nominal * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.scaleBy(x: CGFloat(size) / 128, y: CGFloat(size) / 128)
        let tile = NSBezierPath(roundedRect: NSRect(x: 9, y: 9, width: 110, height: 110), xRadius: 25, yRadius: 25)
        NSGradient(starting: NSColor(srgbRed: 0.20, green: 0.50, blue: 0.95, alpha: 1),
                   ending: NSColor(srgbRed: 0.10, green: 0.19, blue: 0.43, alpha: 1))!.draw(in: tile, angle: -75)
        let trackpad = NSBezierPath(roundedRect: NSRect(x: 29, y: 33, width: 70, height: 61), xRadius: 13, yRadius: 13)
        NSColor.white.withAlphaComponent(0.42).setStroke()
        trackpad.lineWidth = 3
        trackpad.stroke()
        let shackle = NSBezierPath(roundedRect: NSRect(x: 55, y: 60, width: 18, height: 20), xRadius: 9, yRadius: 9)
        NSColor.white.setStroke()
        shackle.lineWidth = 4
        shackle.stroke()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 50, y: 48, width: 28, height: 18), xRadius: 5, yRadius: 5).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(nominal)x\(nominal)\(suffix).png"))
    }
}
