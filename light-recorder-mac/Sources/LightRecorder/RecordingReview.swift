import AppKit
import AVFoundation
import Combine
import SwiftUI
import RecorderCore

struct RecordingReview: View {
    let recording: RecentRecording
    let close: () -> Void
    @State private var player: AVPlayer
    @State private var start = 0.0
    @State private var end: Double
    @State private var message = ""
    @State private var exporting = false
    @State private var playhead = 0.0
    @State private var playing = false
    @State private var exported: (range: ClosedRange<Double>, url: URL)?

    init(recording: RecentRecording, close: @escaping () -> Void) {
        self.recording = recording
        self.close = close
        _player = State(initialValue: AVPlayer(url: recording.url))
        _end = State(initialValue: recording.duration)
    }

    private var changed: Bool { start > 0.001 || end < recording.duration - 0.001 }
    private var validRange: Bool { end - start >= 0.10 }
    private var fullRange: ClosedRange<Double> { 0...max(0.001, recording.duration) }
    private var savedSelection: URL? {
        guard let exported, exported.range == start...end,
              FileManager.default.fileExists(atPath: exported.url.path) else { return nil }
        return exported.url
    }

    private var dragURL: URL? {
        guard !exporting else { return nil }
        return changed ? savedSelection : recording.url
    }

    private var dragHint: String {
        if exporting { return "正在导出选段" }
        if dragURL == nil { return "另存选段后可拖出" }
        return changed ? "拖动画面可拖出选段" : "拖动画面可拖出视频"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("回看录屏").font(.headline)
                    Text(recording.url.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Label(dragHint, systemImage: "hand.draw")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("完成", action: close).disabled(exporting)
            }
            RecordingVideoSurface(player: player, dragURL: dragURL, dragHint: dragHint)
                .frame(minHeight: 220, idealHeight: 305)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 10) {
                Button(playing ? "暂停" : "播放", action: togglePlayback).disabled(exporting)
                Slider(value: Binding(get: { playhead }, set: seek), in: fullRange)
                    .accessibilityLabel("播放进度").disabled(exporting)
                Text(label(playhead)).font(.caption).monospacedDigit()
                    .frame(width: 75, alignment: .trailing)
            }
            VStack(spacing: 8) {
                endpoint("起点", value: start, binding: Binding(get: { start }, set: setStart)) {
                    setStart(player.currentTime().seconds)
                }
                endpoint("终点", value: end, binding: Binding(get: { end }, set: setEnd)) {
                    setEnd(player.currentTime().seconds)
                }
            }.disabled(exporting || recording.duration < 0.10)
            HStack(spacing: 10) {
                Button("预览选段") { preview() }.disabled(exporting || !validRange)
                Button("重置") { start = 0; end = recording.duration; seek(0) }.disabled(exporting || !changed)
                Spacer()
                if exporting { ProgressView().controlSize(.small) }
                Button("另存选段") { save(copy: false) }.disabled(exporting || !changed || !validRange)
                Button(changed ? "裁剪并复制" : "复制视频") { save(copy: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(exporting || (changed && !validRange))
            }
            Text(message.isEmpty ? "选中 \(label(end - start))" : message)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(minWidth: 600, idealWidth: 680, minHeight: 445)
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            let position = player.currentTime().seconds
            if position.isFinite { playhead = max(0, min(recording.duration, position)) }
            playing = player.rate != 0
        }
        .onDisappear { player.pause() }
    }

    private func endpoint(_ title: String, value: Double, binding: Binding<Double>, setCurrent: @escaping () -> Void) -> some View {
        HStack(spacing: 9) {
            Text(title).frame(width: 28, alignment: .leading)
            Slider(value: binding, in: fullRange).accessibilityLabel("裁剪\(title)")
            Text(label(value)).monospacedDigit().font(.caption).frame(width: 75, alignment: .trailing)
            Button("用当前位置") { setCurrent() }.accessibilityLabel("用当前位置设为\(title)")
        }
    }

    private func label(_ seconds: Double) -> String { String(format: "%.2f 秒", seconds) }

    private func togglePlayback() {
        if player.rate != 0 { player.pause(); return }
        player.currentItem?.forwardPlaybackEndTime = .invalid
        if playhead >= recording.duration - 0.02 { seek(0) }
        player.play()
    }

    private func seek(_ seconds: Double) {
        player.pause()
        playhead = seconds
        player.currentItem?.forwardPlaybackEndTime = .invalid
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero)
        message = ""
    }

    private func setStart(_ value: Double) {
        guard value.isFinite else { return }
        start = max(0, min(value, end - 0.10))
        seek(start)
    }

    private func setEnd(_ value: Double) {
        guard value.isFinite else { return }
        end = min(recording.duration, max(start + 0.10, value))
        seek(end)
    }

    private func preview() {
        player.pause()
        player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 60000)
        let time = CMTime(seconds: start, preferredTimescale: 60000)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
            if finished { player.play() }
        }
    }

    private func save(copy: Bool) {
        if !changed {
            if copy { copyVideo(recording.url) }
            return
        }
        guard !exporting, validRange else { return }
        let range = start...end
        if let savedSelection {
            if copy { copyVideo(savedSelection) }
            else { message = "已另存 · \(savedSelection.lastPathComponent)" }
            return
        }
        player.pause()
        exporting = true
        message = "正在导出选段…"
        Task { @MainActor in
            defer { exporting = false }
            do {
                let url = try await RecordingTrim.save(recording.url, start: range.lowerBound, end: range.upperBound)
                exported = (range, url)
                if copy { copyVideo(url) }
                else { message = "已另存 · \(url.lastPathComponent)" }
            } catch { message = "裁剪未完成：\(error.localizedDescription)" }
        }
    }

    private func copyVideo(_ url: URL) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.writeObjects([url as NSURL]) {
            message = "已复制视频文件 · \(url.lastPathComponent)"
        } else { message = "无法复制视频，请重试。" }
    }
}

private struct RecordingVideoSurface: NSViewRepresentable {
    let player: AVPlayer
    let dragURL: URL?
    let dragHint: String

    func makeNSView(context: Context) -> PlayerCanvas {
        let view = PlayerCanvas()
        view.wantsLayer = true
        view.videoLayer.player = player
        view.videoLayer.videoGravity = .resizeAspect
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        view.setAccessibilityLabel("录屏预览")
        return view
    }

    func updateNSView(_ view: PlayerCanvas, context: Context) {
        if view.videoLayer.player !== player { view.videoLayer.player = player }
        view.dragURL = dragURL
        view.toolTip = dragHint
        view.setAccessibilityHelp(dragHint)
    }

    final class PlayerCanvas: NSView, NSDraggingSource {
        let videoLayer = AVPlayerLayer()
        var dragURL: URL? {
            didSet {
                if oldValue != dragURL { window?.invalidateCursorRects(for: self) }
            }
        }

        override func makeBackingLayer() -> CALayer { videoLayer }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            super.resetCursorRects()
            if dragURL != nil { addCursorRect(bounds, cursor: .openHand) }
        }

        override func mouseDown(with event: NSEvent) {
            guard let dragURL, FileManager.default.fileExists(atPath: dragURL.path) else { return }
            let payload = NSPasteboardItem()
            guard payload.setString(URL(fileURLWithPath: dragURL.path).absoluteString, forType: .fileURL) else { return }
            let item = NSDraggingItem(pasteboardWriter: payload)
            let point = convert(event.locationInWindow, from: nil)
            let icon = NSWorkspace.shared.icon(forFile: dragURL.path)
            item.setDraggingFrame(NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48), contents: icon)
            let session = beginDraggingSession(with: [item], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    }
}
