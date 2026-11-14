import Foundation
import Darwin
import ImageIO

public enum ScreenshotFiles {
    public static func defaultDirectory() -> URL {
        if let path = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    public static func isScreenshot(_ url: URL) -> Bool {
        guard ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(url.pathExtension.lowercased()) else { return false }
        let attribute = "com.apple.metadata:kMDItemIsScreenCapture"
        let size = getxattr(url.path, attribute, nil, 0, 0, XATTR_NOFOLLOW)
        if size > 0 && size < 4096 {
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { getxattr(url.path, attribute, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
            if read == size, let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? Bool, value {
                return true
            }
        }
        let name = url.lastPathComponent.lowercased()
        return ["截屏", "屏幕快照", "screenshot", "screen shot", "螢幕快照", "螢幕截圖"].contains { name.hasPrefix($0) }
    }

    public static func isCompleteImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { return false }
        return CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
    }
}

/// Emits after a short quiet interval and a readable, complete image.
/// Existing files are a baseline, and changing/incomplete files stay pending.
public struct ScreenshotTracker: Sendable {
    private struct Pending: Sendable {
        let file: RecentFile
        let stableSince: Date
    }
    private var previous: [String: FileFingerprint]?
    private var pending: [String: Pending] = [:]
    public var hasPending: Bool { !pending.isEmpty }
    public var hasBaseline: Bool { previous != nil }
    public init() {}

    public mutating func ingest(_ files: [RecentFile], now: Date = Date(),
                                isReady: (RecentFile) -> Bool = { _ in true }) -> RecentFile? {
        ingestAll(files, now: now, isReady: isReady).last
    }

    public mutating func ingestAll(_ files: [RecentFile], now: Date = Date(),
                                isReady: (RecentFile) -> Bool = { _ in true }) -> [RecentFile] {
        let current = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.fingerprint) })
        guard let previous else { self.previous = current; return [] }
        pending = pending.filter { current[$0.key] != nil }
        for file in files where previous[file.id] != file.fingerprint {
            pending[file.id] = Pending(file: file, stableSince: now)
        }
        self.previous = current
        let ready = pending.values.filter { item in
            current[item.file.id] == item.file.fingerprint && item.file.size > 0
                && now.timeIntervalSince(item.stableSince) >= 0.15 && isReady(item.file)
        }
        for item in ready { pending.removeValue(forKey: item.file.id) }
        return ready.map(\.file).sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }
}
