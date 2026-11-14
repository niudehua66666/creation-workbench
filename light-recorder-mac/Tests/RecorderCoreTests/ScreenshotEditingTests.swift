import AppKit
import Testing
import ScreenshotEditing

@Test func screenshotCropAndSavePreserveOriginalAndExistingCopies() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let context = try #require(CGContext(data: nil, width: 240, height: 160, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 0, green: 0.8, blue: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
    let image = try #require(context.makeImage())
    let source = directory.appendingPathComponent("截图.png")
    let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    try data.write(to: source)
    let loaded = try ScreenshotEdit.load(source)
    let crop = CGRect(x: 20, y: 30, width: 100, height: 80)
    let edited = try ScreenshotEdit.render(loaded, crop: crop, marks: [
        ScreenshotMark(style: .rectangle, start: CGPoint(x: 30, y: 40), end: CGPoint(x: 100, y: 90)),
        ScreenshotMark(style: .arrow, start: CGPoint(x: 40, y: 50), end: CGPoint(x: 80, y: 70)),
        ScreenshotMark(style: .highlight, start: CGPoint(x: 30, y: 40), end: CGPoint(x: 80, y: 60))])
    #expect(edited.width == 100 && edited.height == 80)
    let a = try ScreenshotEdit.saveCopy(edited, beside: source)
    let b = try ScreenshotEdit.saveCopy(edited, beside: source)
    #expect(a != b)
    #expect(try Data(contentsOf: source) == data)
    #expect(try ScreenshotEdit.load(a).width == 100)
    #expect(try Data(contentsOf: a) == Data(contentsOf: b))
}

@Test func invalidScreenshotCropFailsBeforeCreatingAnOutput() throws {
    let context = try #require(CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let image = try #require(context.makeImage())
    #expect(throws: (any Error).self) {
        try ScreenshotEdit.render(image, crop: CGRect(x: 100, y: 100, width: 50, height: 50), marks: [])
    }
}
