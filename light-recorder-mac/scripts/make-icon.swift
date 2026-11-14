import AppKit
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16",16), ("icon_16x16@2x",32), ("icon_32x32",32), ("icon_32x32@2x",64), ("icon_128x128",128), ("icon_128x128@2x",256), ("icon_256x256",256), ("icon_256x256@2x",512), ("icon_512x512",512), ("icon_512x512@2x",1024)] {
    let size = CGFloat(pixels)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedRed: 0.95, green: 0.30, blue: 0.22, alpha: 1).setFill()
    NSBezierPath(roundedRect: CGRect(x: size * 0.07, y: size * 0.07, width: size * 0.86, height: size * 0.86), xRadius: size * 0.20, yRadius: size * 0.20).fill()
    NSColor.white.setStroke()
    let frame = NSBezierPath(roundedRect: CGRect(x: size * 0.245, y: size * 0.245, width: size * 0.51, height: size * 0.51), xRadius: size * 0.11, yRadius: size * 0.11)
    frame.lineWidth = size * 0.045; frame.stroke()
    NSColor.white.setFill(); NSBezierPath(ovalIn: CGRect(x: size * 0.37, y: size * 0.37, width: size * 0.26, height: size * 0.26)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
}
