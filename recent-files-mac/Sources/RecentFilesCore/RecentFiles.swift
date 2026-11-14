import Foundation
import Darwin

public struct FileFingerprint: Equatable, Sendable {
    public let device: Int32
    public let inode: UInt64
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let changedSeconds: Int64
    public let changedNanoseconds: Int64

    init(_ info: stat) {
        device = info.st_dev
        inode = info.st_ino
        size = info.st_size
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec)
        modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
        changedSeconds = Int64(info.st_ctimespec.tv_sec)
        changedNanoseconds = Int64(info.st_ctimespec.tv_nsec)
    }

    static func read(_ url: URL) throws -> FileFingerprint {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw FileActionError.sourceUnavailable }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw FileActionError.notRegularFile }
        return FileFingerprint(info)
    }
}

public struct RecentFile: Identifiable, Sendable, Equatable {
    public var id: String { url.path }
    public let url: URL
    public let sourceFolder: URL
    public let date: Date
    public let fingerprint: FileFingerprint
    public var name: String { url.lastPathComponent }
    public var size: Int64 { fingerprint.size }
    public var fileExtension: String { url.pathExtension }
    public var baseName: String { fileExtension.isEmpty ? name : url.deletingPathExtension().lastPathComponent }
}

public struct ScanIssue: Identifiable, Sendable {
    public var id: String { folder.path }
    public let folder: URL
    public let message: String
}

public struct ScanResult: Sendable {
    public let files: [RecentFile]
    public let issues: [ScanIssue]
}

public enum RecentFileScanner {
    private static let temporaryExtensions: Set<String> = [
        "download", "crdownload", "part", "partial", "tmp", "temp", "filepart", "opdownload"
    ]

    public static func scan(folders: [URL], limit: Int = 20) -> ScanResult {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isSymbolicLinkKey, .isHiddenKey, .contentModificationDateKey,
            .addedToDirectoryDateKey, .creationDateKey
        ]
        var files: [RecentFile] = []
        var issues: [ScanIssue] = []
        var visited = Set<String>()
        for folder in folders {
            let folder = folder.standardizedFileURL.resolvingSymlinksInPath()
            guard visited.insert(folder.path).inserted else { continue }
            do {
                let children = try FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
                )
                for url in children {
                    guard !url.lastPathComponent.hasPrefix("."),
                          !temporaryExtensions.contains(url.pathExtension.lowercased()),
                          !url.lastPathComponent.hasSuffix("~"),
                          let values = try? url.resourceValues(forKeys: keys),
                          values.isRegularFile == true, values.isSymbolicLink != true,
                          values.isHidden != true,
                          let fingerprint = try? FileFingerprint.read(url) else { continue }
                    let fallback = values.creationDate ?? .distantPast
                    let date = max(values.addedToDirectoryDate ?? fallback, values.contentModificationDate ?? fallback)
                    files.append(RecentFile(url: url, sourceFolder: folder, date: date, fingerprint: fingerprint))
                }
            } catch {
                issues.append(ScanIssue(folder: folder, message: "无法读取「\(folder.lastPathComponent)」。文件夹可能已被移走，或需要重新选择以取得访问权限。"))
            }
        }
        files.sort { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
        return ScanResult(files: Array(files.prefix(max(0, limit))), issues: issues)
    }
}

public enum FileActionError: LocalizedError, Equatable {
    case invalidName(String)
    case sourceUnavailable
    case notRegularFile
    case sourceChanged
    case stillWriting
    case destinationUnavailable
    case permissionDenied
    case insufficientSpace
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidName(let reason): return reason
        case .sourceUnavailable: return "原文件已被移动、删除或暂时无法读取。请刷新列表后再试。"
        case .notRegularFile: return "这个项目不是可复制的普通文件。请刷新后选择其他文件。"
        case .sourceChanged: return "文件已发生变化。请回到列表刷新，再选择一次。"
        case .stillWriting: return "这个文件可能还在下载或导出。请等它完成，刷新后再试。"
        case .destinationUnavailable: return "目标文件夹不可用。请重新选择项目文件夹。"
        case .permissionDenied: return "无法写入这个项目文件夹。请选择有写入权限的文件夹。"
        case .insufficientSpace: return "目标磁盘空间不足。请释放空间或更换项目文件夹。"
        case .failed(let detail): return "复制没有完成：\(detail)"
        }
    }
}

public enum SafeFileCopier {
    /// Copy through open file descriptors, then publish with an exclusive atomic rename.
    /// The original is never renamed, edited or removed.
    public static func copy(_ file: RecentFile, baseName: String, to destination: URL) throws -> URL {
        let filename = try validatedFilename(baseName: baseName, fileExtension: file.fileExtension)
        let sourceFD = open(file.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard sourceFD >= 0 else { throw FileActionError.sourceUnavailable }
        defer { close(sourceFD) }
        let before = try fingerprint(sourceFD)
        guard before == file.fingerprint else { throw FileActionError.sourceChanged }
        let modified = Double(before.modifiedSeconds) + Double(before.modifiedNanoseconds) / 1_000_000_000
        guard Date().timeIntervalSince1970 - modified >= 1 else { throw FileActionError.stillWriting }
        // Catch downloads/exports with a final extension before any destination is created.
        Thread.sleep(forTimeInterval: 0.35)
        guard try fingerprint(sourceFD) == before else { throw FileActionError.stillWriting }

        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        let directoryFD = open(destination.path, O_RDONLY | O_DIRECTORY)
        guard directoryFD >= 0 else { throw destinationError(errno) }
        defer { close(directoryFD) }
        var directoryInfo = stat()
        guard fstat(directoryFD, &directoryInfo) == 0 else { throw FileActionError.destinationUnavailable }

        let temporaryName = ".recent-files-\(UUID().uuidString).partial"
        let outputFD = openat(directoryFD, temporaryName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard outputFD >= 0 else { throw destinationError(errno) }
        var committed = false
        defer {
            close(outputFD)
            if !committed { unlinkat(directoryFD, temporaryName, 0) }
        }
        guard fcopyfile(sourceFD, outputFD, nil, copyfile_flags_t(COPYFILE_ALL)) == 0 else {
            throw destinationError(errno)
        }
        guard fsync(outputFD) == 0 else { throw destinationError(errno) }
        guard try fingerprint(sourceFD) == before,
              (try? FileFingerprint.read(file.url)) == before else { throw FileActionError.sourceChanged }
        var afterDirectory = stat()
        guard stat(destination.path, &afterDirectory) == 0,
              afterDirectory.st_dev == directoryInfo.st_dev,
              afterDirectory.st_ino == directoryInfo.st_ino else { throw FileActionError.destinationUnavailable }

        let ext = file.fileExtension
        let stem = ext.isEmpty ? filename : String(filename.dropLast(ext.count + 1))
        var number = 1
        while number < 100_000 {
            let candidate = number == 1 ? filename : "\(stem) (\(number))" + (ext.isEmpty ? "" : ".\(ext)")
            guard candidate.utf8.count <= 255 else { throw FileActionError.invalidName("文件名太长，请缩短一些后再试。") }
            if renameatx_np(directoryFD, temporaryName, directoryFD, candidate, UInt32(RENAME_EXCL)) == 0 {
                committed = true
                // Directory fsync is best effort: the file itself is already complete and committed.
                _ = fsync(directoryFD)
                return destination.appendingPathComponent(candidate)
            }
            let code = errno
            guard code == EEXIST else { throw destinationError(code) }
            number += 1
        }
        throw FileActionError.failed("同名文件过多，请换一个名称。")
    }

    public static func validatedFilename(baseName: String, fileExtension: String) throws -> String {
        var name = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Pasting the original full name should not duplicate the fixed extension shown in the UI.
        if !fileExtension.isEmpty, name.lowercased().hasSuffix(".\(fileExtension.lowercased())") {
            name.removeLast(fileExtension.count + 1)
        }
        guard !name.isEmpty else { throw FileActionError.invalidName("请先输入文件名称。") }
        guard !name.hasPrefix(".") else { throw FileActionError.invalidName("名称不能以点开头，请换一个容易识别的名称。") }
        guard name.rangeOfCharacter(from: .controlCharacters) == nil,
              !name.contains("/"), !name.contains(":") else {
            throw FileActionError.invalidName("名称不能包含斜杠、冒号或换行。")
        }
        let filename = name + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
        guard filename.utf8.count <= 255 else { throw FileActionError.invalidName("文件名太长，请缩短一些后再试。") }
        return filename
    }

    private static func fingerprint(_ fd: Int32) throws -> FileFingerprint {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw FileActionError.sourceUnavailable }
        guard (info.st_mode & S_IFMT) == S_IFREG else { throw FileActionError.notRegularFile }
        return FileFingerprint(info)
    }

    private static func destinationError(_ code: Int32) -> FileActionError {
        switch code {
        case EACCES, EPERM, EROFS: return .permissionDenied
        case ENOSPC, EDQUOT: return .insufficientSpace
        case ENOENT, ENOTDIR: return .destinationUnavailable
        default: return .failed(String(cString: strerror(code)))
        }
    }
}
