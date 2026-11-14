import AppKit

public enum MediaFileTransfer {
    /// Keep a separate native file URL item per file so mixed attachments stay independent.
    public static func pasteboardItems(for urls: [URL]) -> [NSURL] {
        var seen = Set<URL>()
        return urls.map(\.standardizedFileURL).filter { file in
            file.isFileURL && seen.insert(file).inserted &&
                (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.map { $0 as NSURL }
    }
}
