import AVFoundation

public enum RecordingTrim {
    public static func save(_ source: URL, start: Double, end: Double) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard start.isFinite, end.isFinite, duration.isFinite, start >= 0,
              end <= duration + 0.001, min(end, duration) - start >= 0.10 else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: "请选择至少 0.1 秒的有效片段。"])
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality),
              session.supportedFileTypes.contains(.mp4) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "这个视频无法导出为 MP4。"])
        }
        let folder = source.deletingLastPathComponent()
        let temporary = folder.appendingPathComponent(".轻录剪辑-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let lower = CMTime(seconds: start, preferredTimescale: 60000)
        let upper = CMTime(seconds: min(end, duration), preferredTimescale: 60000)
        session.timeRange = CMTimeRange(start: lower, end: upper)
        session.shouldOptimizeForNetworkUse = true
        try await session.export(to: temporary, as: .mp4)
        try Task.checkCancellation()
        let result = AVURLAsset(url: temporary)
        let resultDuration = try await result.load(.duration).seconds
        let video = try await result.loadTracks(withMediaType: .video)
        guard resultDuration.isFinite, resultDuration > 0, !video.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let stem = source.deletingPathExtension().lastPathComponent + " - 剪辑"
        for index in 1...1000 {
            let suffix = index == 1 ? "" : " \(index)"
            let destination = folder.appendingPathComponent(stem + suffix + ".mp4")
            do {
                try FileManager.default.moveItem(at: temporary, to: destination)
                return destination
            } catch {
                if FileManager.default.fileExists(atPath: destination.path) { continue }
                throw error
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }
}
