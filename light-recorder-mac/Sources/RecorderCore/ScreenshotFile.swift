import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ScreenshotFile {
    public static func save(_ image: CGImage, in directory: URL, at date: Date = Date()) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporary = directory.appendingPathComponent(".轻录截图-\(UUID().uuidString).png")
            defer { try? manager.removeItem(at: temporary) }
            guard let encoder = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImage(encoder, image, nil)
            guard CGImageDestinationFinalize(encoder) else { throw CocoaError(.fileWriteUnknown) }

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let name = "轻录截图 \(formatter.string(from: date))"
            for index in 1...1000 {
                let suffix = index == 1 ? "" : " (\(index))"
                let url = directory.appendingPathComponent("\(name)\(suffix).png")
                // Publish the encoded PNG atomically without replacing another capture.
                let result = temporary.withUnsafeFileSystemRepresentation { source in
                    url.withUnsafeFileSystemRepresentation { destination in
                        renamex_np(source, destination, UInt32(RENAME_EXCL)) == 0 ? 0 : errno
                    }
                }
                if result == 0 { return url }
                if result == EEXIST { continue }
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(result), userInfo: [NSFilePathErrorKey: url.path])
            }
            throw CocoaError(.fileWriteFileExists)
        }.value
    }
}
