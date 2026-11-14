import AppKit
import ImageIO

struct ScreenshotEditError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) { errorDescription = message }
}

public enum ScreenshotMarkStyle: String, CaseIterable, Identifiable {
    case crop = "裁剪", rectangle = "框选", arrow = "箭头", highlight = "高亮"
    public var id: Self { self }
    public var symbol: String {
        switch self {
        case .crop: "crop"
        case .rectangle: "rectangle"
        case .arrow: "arrow.up.right"
        case .highlight: "highlighter"
        }
    }
}

public struct ScreenshotMark {
    public let style: ScreenshotMarkStyle
    public let start: CGPoint
    public let end: CGPoint

    public init(style: ScreenshotMarkStyle, start: CGPoint, end: CGPoint) {
        self.style = style
        self.start = start
        self.end = end
    }

    public var bounds: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    public var path: CGPath {
        if style != .arrow { return CGPath(rect: bounds, transform: nil) }
        let line = CGMutablePath()
        line.move(to: start)
        line.addLine(to: end)
        let length = hypot(end.x - start.x, end.y - start.y)
        let head = min(max(12, length * 0.19), 45)
        let angle = atan2(end.y - start.y, end.x - start.x)
        for offset: CGFloat in [-0.55, 0.55] {
            line.move(to: end)
            line.addLine(to: CGPoint(x: end.x - head * cos(angle + offset),
                                      y: end.y - head * sin(angle + offset)))
        }
        return line
    }
}

public enum ScreenshotEdit {
    public static func load(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: max(width, height),
              ] as CFDictionary) else { throw ScreenshotEditError("无法打开截图。") }
        return image
    }

    public static func render(_ original: CGImage, crop: CGRect, marks: [ScreenshotMark]) throws -> CGImage {
        let frame = CGRect(x: 0, y: 0, width: original.width, height: original.height)
        let region = crop.integral.intersection(frame)
        guard !region.isEmpty, let cropped = original.cropping(to: region) else {
            throw ScreenshotEditError("请选择有效的裁剪范围。")
        }
        guard !marks.isEmpty else { return cropped }
        let colorSpace = original.colorSpace?.model == .rgb ? original.colorSpace! : CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: cropped.width, height: cropped.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ScreenshotEditError("无法生成编辑结果。")
        }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        context.translateBy(x: -region.minX, y: region.maxY)
        context.scaleBy(x: 1, y: -1)
        context.setLineWidth(max(3, min(10, CGFloat(max(original.width, original.height)) / 320)))
        context.setLineJoin(.round)
        context.setLineCap(.round)
        for mark in marks {
            context.addPath(mark.path)
            if mark.style == .highlight {
                context.setFillColor(red: 1, green: 0.80, blue: 0.10, alpha: 0.35)
                context.fillPath()
            } else {
                context.setStrokeColor(red: 1, green: 0.26, blue: 0.20, alpha: 1)
                context.strokePath()
            }
        }
        guard let output = context.makeImage() else { throw ScreenshotEditError("无法生成编辑结果。") }
        return output
    }

    public static func saveCopy(_ image: CGImage, beside original: URL) throws -> URL {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw ScreenshotEditError("无法生成 PNG。")
        }
        let folder = original.deletingLastPathComponent()
        let temporary = folder.appendingPathComponent(".编辑-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary)
        let stem = original.deletingPathExtension().lastPathComponent + " - 编辑"
        for index in 1...1000 {
            let suffix = index == 1 ? "" : " \(index)"
            let destination = folder.appendingPathComponent(stem + suffix + ".png")
            do {
                try FileManager.default.linkItem(at: temporary, to: destination)
                return destination
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                continue
            }
        }
        throw ScreenshotEditError("同名副本过多，请移动已有副本后再试。")
    }
}
