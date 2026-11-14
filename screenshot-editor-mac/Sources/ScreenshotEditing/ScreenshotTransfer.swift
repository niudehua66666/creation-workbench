import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Uses the original pixels; the small shelf preview is never used for export.
public enum ScreenshotTransfer {
    @MainActor
    public static func copyImage(at url: URL, to pasteboard: NSPasteboard = .general) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ScreenshotEditError("截图无法读取，请重新截图后再试。")
        }
        try copyImage(image, to: pasteboard)
    }

    @MainActor
    public static func copyImage(_ image: CGImage, to pasteboard: NSPasteboard = .general) throws {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]),
              let tiff = bitmap.tiffRepresentation else {
            throw ScreenshotEditError("无法复制这张图片。")
        }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw ScreenshotEditError("无法写入剪贴板，请再试一次。")
        }
    }
}
