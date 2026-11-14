import Foundation
import CoreGraphics

public enum CaptureGeometry {
    /// Rectangles are local to the selected display, in points, with a top-left origin.
    public static func selection(from start: CGPoint, to end: CGPoint, bounds: CGRect) -> CGRect? {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(bounds)
        guard !rect.isNull, rect.width >= 32, rect.height >= 32 else { return nil }
        return rect.integral.intersection(bounds)
    }

    public static func videoSize(points: CGSize, scale: CGFloat, maximumEdge: CGFloat) -> CGSize {
        guard points.width.isFinite, points.height.isFinite, scale.isFinite,
              points.width > 0, points.height > 0, scale > 0 else { return CGSize(width: 2, height: 2) }
        let width = points.width * scale, height = points.height * scale
        let factor = min(1, maximumEdge / max(width, height))
        return CGSize(width: max(2, floor(width * factor / 2) * 2),
                      height: max(2, floor(height * factor / 2) * 2))
    }
}

public struct RecordingDestination {
    public let directory: URL
    public let temporaryURL: URL
    public let baseName: String

    public init(directory: URL, date: Date = Date()) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        self.directory = directory
        baseName = "轻录 \(formatter.string(from: date))"
        temporaryURL = directory.appendingPathComponent(".轻录-\(UUID().uuidString).recording.mp4")
        // Fail before capture starts if this destination isn't writable.
        try Data().write(to: temporaryURL, options: .withoutOverwriting)
        try manager.removeItem(at: temporaryURL)
    }

    public func finish() throws -> URL {
        let manager = FileManager.default
        let attributes = try manager.attributesOfItem(atPath: temporaryURL.path)
        guard (attributes[.size] as? NSNumber)?.int64Value ?? 0 > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for index in 1...1000 {
            let suffix = index == 1 ? "" : " (\(index))"
            let url = directory.appendingPathComponent("\(baseName)\(suffix).mp4")
            do {
                // FileManager move refuses to replace an existing destination.
                try manager.moveItem(at: temporaryURL, to: url)
                return url
            } catch {
                if manager.fileExists(atPath: url.path) { continue }
                throw error
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    /// Preserve non-empty interrupted recordings for recovery; never call them complete.
    public func preserveInterrupted() -> URL? {
        let manager = FileManager.default
        guard let size = try? manager.attributesOfItem(atPath: temporaryURL.path)[.size] as? NSNumber else { return nil }
        guard size.int64Value > 0 else {
            try? manager.removeItem(at: temporaryURL)
            return nil
        }
        let target = directory.appendingPathComponent("未完成录制-\(UUID().uuidString.prefix(8)).mp4")
        do { try manager.moveItem(at: temporaryURL, to: target); return target }
        catch { return temporaryURL }
    }
}

public func durationLabel(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.isFinite ? seconds : 0))
    if total >= 3600 { return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60) }
    return String(format: "%02d:%02d", total / 60, total % 60)
}
