import AppKit
import AVFoundation
import Combine
import ScreenCaptureKit
import RecorderCore
import ScreenshotEditing

enum CaptureMode: String, CaseIterable, Identifiable {
    case region = "框选区域", display = "整个屏幕", window = "单个窗口"
    var id: Self { self }
    var icon: String { switch self { case .region: "viewfinder"; case .display: "display"; case .window: "macwindow" } }
    var detail: String { switch self { case .region: "只录想要的部分"; case .display: "完整记录当前屏幕"; case .window: "专注一个应用窗口" } }
}

enum RecorderPhase: Equatable {
    case idle, selecting, countdown(Int), preparing, recording, finishing
    var isBusy: Bool { self != .idle }
}

struct RegionSelection {
    let displayID: CGDirectDisplayID
    let rect: CGRect
}

struct RecentRecording: Identifiable {
    let url: URL
    let duration: Double
    let size: Int64
    var id: URL { url }
    var detail: String { "\(durationLabel(duration)) · \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))" }
}

@MainActor
final class RecorderModel: NSObject, ObservableObject {
    @Published var mode: CaptureMode = .region
    @Published var systemAudio = true { didSet { defaults.set(systemAudio, forKey: "systemAudio") } }
    @Published var microphone = false { didSet { defaults.set(microphone, forKey: "microphone") } }
    @Published var showsCursor = true { didSet { defaults.set(showsCursor, forKey: "showsCursor") } }
    @Published var fps = 30 { didSet { defaults.set(fps, forKey: "fps") } }
    @Published var maximumEdge = 1920 { didSet { defaults.set(maximumEdge, forKey: "maximumEdge") } }
    @Published var countdownEnabled = true { didSet { defaults.set(countdownEnabled, forKey: "countdown") } }
    @Published var useShiftCommand4 = false {
        didSet {
            defaults.set(useShiftCommand4, forKey: "useShiftCommand4")
            screenshotShortcutChanged?()
        }
    }
    @Published var screenshotShortcutIssue: String?
    @Published private(set) var phase: RecorderPhase = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var screenPermission = CGPreflightScreenCaptureAccess()
    @Published var errorMessage: String?
    @Published var displays: [SCDisplay] = []
    @Published var windows: [SCWindow] = []
    @Published var selectedDisplayID: CGDirectDisplayID = 0
    @Published var selectedWindowID: CGWindowID = 0
    @Published var region: RegionSelection?
    @Published var recent: [RecentRecording] = []
    @Published private(set) var screenshots: [URL] = []
    @Published private(set) var focusedScreenshot: URL?
    @Published private(set) var pinnedScreenshots: Set<URL> = []
    @Published var autoImportScreenshots = true {
        didSet {
            defaults.set(autoImportScreenshots, forKey: "autoImportScreenshots")
            screenshotWatchingChanged?()
        }
    }
    @Published var systemScreenshotIssue: String?
    @Published private(set) var selectedMedia: Set<URL> = []
    @Published private(set) var screenshotBusy = false {
        didSet { captureActivityChanged?(captureActive) }
    }
    @Published private(set) var shelfMessage: String?
    @Published var outputDirectory: URL
    @Published var loadingSources = false
    @Published var copied = false

    var showReview: ((RecentRecording) -> Void)?
    var showScreenshotEditor: ((URL) throws -> Void)?
    var closeReview: (() -> Void)?
    var hideMainWindow: (() -> Void)?
    var showMainWindow: (() -> Void)?
    var captureActivityChanged: ((Bool) -> Void)?
    var captureReady: (() -> Void)?
    var screenshotFailed: (() -> Void)?
    var screenshotWatchingChanged: (() -> Void)?
    var screenshotShortcutChanged: (() -> Void)?
    var phaseChanged: (() -> Void)?
    private let defaults = UserDefaults.standard
    private var content: SCShareableContent?
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var destination: RecordingDestination?
    private var startTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var timer: Timer?
    private var startedAt: Date?
    private var regionSelector: RegionSelector?
    private var screenshotSelector: RegionSelector?
    private var selectingSettingsRegion = false
    private var currentRun = UUID()
    private var activeMediaDrags = Set<UUID>()
    private var pendingSystemScreenshots: [URL] = []

    override init() {
        let savedFolder = UserDefaults.standard.url(forKey: "outputDirectory")
        outputDirectory = savedFolder ?? FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("轻录")
        super.init()
        defaults.register(defaults: ["systemAudio": true, "microphone": false, "showsCursor": true,
                                     "fps": 30, "maximumEdge": 1920, "countdown": true,
                                     "autoImportScreenshots": UserDefaults(suiteName: "local.jackson.recent-files")?.object(forKey: "screenshotShelfEnabled") as? Bool ?? true])
        systemAudio = defaults.bool(forKey: "systemAudio")
        microphone = defaults.bool(forKey: "microphone")
        showsCursor = defaults.bool(forKey: "showsCursor")
        fps = [30, 60].contains(defaults.integer(forKey: "fps")) ? defaults.integer(forKey: "fps") : 30
        maximumEdge = defaults.integer(forKey: "maximumEdge") == 3840 ? 3840 : 1920
        countdownEnabled = defaults.bool(forKey: "countdown")
        useShiftCommand4 = defaults.bool(forKey: "useShiftCommand4")
        screenshots = (defaults.stringArray(forKey: "screenshotPaths") ?? []).prefix(20)
            .filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
        focusedScreenshot = screenshots.first
        pinnedScreenshots = Set((defaults.stringArray(forKey: "pinnedScreenshotPaths") ?? []).map { URL(fileURLWithPath: $0) })
            .intersection(screenshots)
        autoImportScreenshots = defaults.bool(forKey: "autoImportScreenshots")
        Task { await restoreRecent(); if screenPermission { await refreshSources() } }
    }

    var startTitle: String { mode == .region && region == nil ? "框选并开始录制" : "开始录制" }
    var regionDescription: String {
        guard let region else { return "拖出一个矩形，就能开始" }
        return "已选择 \(Int(region.rect.width)) × \(Int(region.rect.height)) 区域"
    }

    func refreshSources() async {
        guard !loadingSources, phase == .idle else { return }
        screenPermission = CGPreflightScreenCaptureAccess()
        guard screenPermission else { return }
        loadingSources = true
        defer { loadingSources = false }
        do {
            let available = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            content = available
            displays = available.displays
            windows = available.windows.filter {
                $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier &&
                $0.windowLayer == 0 && $0.frame.width > 80 && $0.frame.height > 60 && !($0.title ?? "").isEmpty
            }.sorted { windowName($0).localizedStandardCompare(windowName($1)) == .orderedAscending }
            if !displays.contains(where: { $0.displayID == selectedDisplayID }) {
                selectedDisplayID = displays.first?.displayID ?? 0
            }
            if !windows.contains(where: { $0.windowID == selectedWindowID }) {
                selectedWindowID = windows.first?.windowID ?? 0
            }
            if let region, !displays.contains(where: { $0.displayID == region.displayID }) { self.region = nil }
        } catch { errorMessage = "读取屏幕失败：\(error.localizedDescription)" }
    }

    func requestScreenPermission() {
        if CGPreflightScreenCaptureAccess() { Task { await refreshSources() }; return }
        let granted = CGRequestScreenCaptureAccess()
        screenPermission = granted
        if granted { Task { await refreshSources() } }
    }

    func openScreenSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    func windowName(_ window: SCWindow) -> String {
        "\(window.owningApplication?.applicationName ?? "窗口") · \(window.title ?? "未命名")"
    }

    func displayName(_ display: SCDisplay) -> String {
        let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }
        return screen?.localizedName ?? "屏幕 \(displays.firstIndex(where: { $0.displayID == display.displayID }).map { $0 + 1 } ?? 1)"
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.prompt = "保存到这里"; panel.directoryURL = outputDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputDirectory = url; defaults.set(url, forKey: "outputDirectory")
    }

    func primaryAction() {
        switch phase {
        case .recording: stop()
        case .selecting, .countdown: cancelStart()
        case .idle: begin()
        case .preparing, .finishing: break
        }
    }

    func begin() {
        guard phase == .idle, !loadingSources, !screenshotBusy else { return }
        errorMessage = nil
        guard CGPreflightScreenCaptureAccess() else { requestScreenPermission(); return }
        closeReview?()
        if mode == .region && region == nil { selectRegion(andStart: true) }
        else { runCountdownAndRecord() }
    }

    func selectRegion(andStart: Bool) {
        guard phase == .idle, !screenshotBusy else { return }
        errorMessage = nil
        selectingSettingsRegion = !andStart
        setPhase(.selecting); hideMainWindow?()
        regionSelector = RegionSelector(purpose: andStart ? .startRecording : .setRecordingRegion) { [weak self] selection in
            guard let self else { return }
            self.regionSelector = nil
            if let selection { self.region = selection }
            if selection != nil && andStart {
                self.runCountdownAndRecord()
            } else {
                self.setPhase(.idle)
                self.showMainWindow?()
            }
        }
        regionSelector?.present()
    }

    func cancelStart() {
        if phase == .selecting { regionSelector?.cancel(); return }
        guard case .countdown = phase else { return }
        startTask?.cancel(); startTask = nil
        setPhase(.idle); showMainWindow?()
    }

    private func runCountdownAndRecord() {
        // Lock settings before any asynchronous permission check or countdown.
        setPhase(.preparing)
        currentRun = UUID()
        let run = currentRun
        startTask = Task {
            if microphone {
                let status = AVCaptureDevice.authorizationStatus(for: .audio)
                let allowed: Bool
                if status == .authorized { allowed = true }
                else if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .audio) }
                else { allowed = false }
                guard allowed else {
                    errorMessage = "麦克风尚未授权。请在系统设置 → 隐私与安全性 → 麦克风中允许「截录暂存」，或关闭麦克风开关。"
                    setPhase(.idle); showMainWindow?(); return
                }
            }
            hideMainWindow?()
            if countdownEnabled {
                for count in stride(from: 3, through: 1, by: -1) {
                    guard !Task.isCancelled, currentRun == run else { return }
                    setPhase(.countdown(count))
                    do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
                }
            }
            guard !Task.isCancelled, currentRun == run else { return }
            setPhase(.preparing)
            do { try await startCapture() }
            catch { await fail(error.localizedDescription) }
        }
    }

    private func startCapture() async throws {
        // Fetch fresh sources: a chosen window may have closed or a display disconnected.
        let available = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let filter: SCContentFilter
        let config = SCStreamConfiguration()
        var pointSize: CGSize
        if mode == .window {
            guard let window = available.windows.first(where: {
                $0.windowID == selectedWindowID && $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier
            }) else {
                throw RecorderError.message("这个窗口已关闭，请重新选择窗口。")
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            config.ignoreShadowsSingleWindow = true
            pointSize = filter.contentRect.size
        } else {
            let displayID = mode == .region ? region?.displayID : selectedDisplayID
            guard let display = available.displays.first(where: { $0.displayID == displayID }) else {
                region = nil
                throw RecorderError.message("屏幕已断开，请重新选择录制范围。")
            }
            filter = try selfExcludingFilter(for: display, in: available)
            pointSize = filter.contentRect.size
            if mode == .region, let region {
                let bounds = CGRect(origin: .zero, size: pointSize)
                guard bounds.contains(region.rect), region.rect.width >= 32, region.rect.height >= 32 else {
                    self.region = nil
                    throw RecorderError.message("屏幕尺寸发生了变化，请重新框选区域。")
                }
                config.sourceRect = region.rect
                pointSize = region.rect.size
            }
        }
        let size = CaptureGeometry.videoSize(points: pointSize, scale: CGFloat(filter.pointPixelScale), maximumEdge: CGFloat(maximumEdge))
        config.width = Int(size.width); config.height = Int(size.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 5
        config.showsCursor = showsCursor
        config.showMouseClicks = false
        config.capturesAudio = systemAudio; config.excludesCurrentProcessAudio = true
        config.captureMicrophone = microphone
        config.sampleRate = 48000; config.channelCount = 2
        config.captureDynamicRange = .SDR
        let target = try RecordingDestination(directory: outputDirectory)
        let recordingConfig = SCRecordingOutputConfiguration()
        recordingConfig.outputURL = target.temporaryURL
        recordingConfig.videoCodecType = .h264; recordingConfig.outputFileType = .mp4
        let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        self.destination = target; self.stream = stream; self.output = output
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        if phase == .preparing {
            timeoutTask = Task { [weak self, weak output] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled, let self, self.output === output, self.phase == .preparing else { return }
                await self.fail("录制未能开始，请重试。")
            }
        }
    }

    func stop() {
        guard phase == .recording, let stream else { return }
        timer?.invalidate(); timer = nil
        setPhase(.finishing)
        screenshotSelector?.cancel()
        Task {
            do { try await stream.stopCapture() }
            catch { if phase == .finishing { await fail("结束录制失败：\(error.localizedDescription)") } }
        }
    }

    private func didStart(_ recordingOutput: SCRecordingOutput) {
        guard output === recordingOutput, phase == .preparing else { return }
        timeoutTask?.cancel(); timeoutTask = nil
        elapsed = 0; startedAt = Date(); setPhase(.recording)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
                self.phaseChanged?()
            }
        }
    }

    private func didFinish(_ recordingOutput: SCRecordingOutput) async {
        guard output === recordingOutput, let destination else { return }
        timer?.invalidate(); timer = nil; timeoutTask?.cancel()
        setPhase(.finishing)
        screenshotSelector?.cancel()
        do {
            let asset = AVURLAsset(url: destination.temporaryURL)
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard duration.isFinite, duration > 0, !tracks.isEmpty else { throw RecorderError.message("视频没有有效画面。") }
            let url = try destination.finish()
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            let recording = RecentRecording(url: url, duration: duration, size: size)
            recent.insert(recording, at: 0)
            recent = Array(recent.prefix(8))
            selectedMedia.formIntersection(Set(recent.map(\.url) + screenshots))
            defaults.set(recent.map { $0.url.path }, forKey: "recentPaths")
            shelfMessage = "录屏已保存"
            captureReady?()
            cleanUp(); setPhase(.idle)
        } catch { await fail("视频保存未完成：\(error.localizedDescription)") }
    }

    private func fail(_ message: String) async {
        let oldStream = stream
        // Clear identity before awaiting stop so late delegates cannot report success.
        output = nil; stream = nil
        if phase == .recording { setPhase(.finishing) }
        screenshotSelector?.cancel()
        timer?.invalidate(); timer = nil; timeoutTask?.cancel(); timeoutTask = nil
        if let oldStream { try? await oldStream.stopCapture() }
        let recovered = destination?.preserveInterrupted()
        destination = nil
        errorMessage = message + (recovered == nil ? "" : " 已保留未完成文件：\(recovered!.lastPathComponent)")
        setPhase(.idle); showMainWindow?()
    }

    private func cleanUp() {
        timer?.invalidate(); timer = nil; timeoutTask?.cancel(); timeoutTask = nil
        stream = nil; output = nil; destination = nil; startedAt = nil
    }

    private func setPhase(_ value: RecorderPhase) {
        if value != .selecting { selectingSettingsRegion = false }
        phase = value
        captureActivityChanged?(captureActive)
        phaseChanged?()
        if value == .idle { importPendingSystemScreenshots() }
    }

    var captureActive: Bool { (phase.isBusy && !selectingSettingsRegion) || screenshotBusy }
    var canStartScreenshot: Bool { !screenshotBusy && (phase == .idle || phase == .recording) }

    func screenshotAction() {
        if let screenshotSelector { screenshotSelector.cancel(); return }
        guard canStartScreenshot else { return }
        guard CGPreflightScreenCaptureAccess() else {
            shelfMessage = "请在截录暂存中允许屏幕录制后再截图。"
            showMainWindow?()
            requestScreenPermission()
            return
        }
        shelfMessage = nil
        screenshotBusy = true
        screenshotSelector = RegionSelector(purpose: .screenshot) { [weak self] selection in
            guard let self else { return }
            self.screenshotSelector = nil
            guard let selection else {
                self.screenshotBusy = false
                return
            }
            Task { await self.captureScreenshot(selection) }
        }
        screenshotSelector?.present()
    }

    private func captureScreenshot(_ selection: RegionSelection) async {
        defer { screenshotBusy = false }
        do {
            let url = try await saveScreenshot(selection)
            addScreenshot(url)
            if shelfMessage == nil { shelfMessage = "截图已保存" }
            captureReady?()
        } catch {
            shelfMessage = "截图未保存：\(error.localizedDescription)"
            screenshotFailed?()
        }
    }

    private func addScreenshot(_ url: URL) {
        updateScreenshots([url] + screenshots.filter { $0 != url })
        if activeMediaDrags.isEmpty { focusedScreenshot = url }
    }

    private func updateScreenshots(_ candidates: [URL]) {
        let existing = candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
        pinnedScreenshots.formIntersection(existing)
        let unpinned = Set(existing.lazy.filter { !self.pinnedScreenshots.contains($0) }.prefix(20 - pinnedScreenshots.count))
        screenshots = existing.filter { pinnedScreenshots.contains($0) || unpinned.contains($0) }
        if focusedScreenshot.map({ !screenshots.contains($0) }) ?? true { focusedScreenshot = screenshots.first }
        selectedMedia.formIntersection(Set(recent.map(\.url) + screenshots))
        defaults.set(screenshots.map(\.path), forKey: "screenshotPaths")
        defaults.set(pinnedScreenshots.map(\.path), forKey: "pinnedScreenshotPaths")
    }

    func importScreenshotHistory(_ urls: [URL]) {
        var seen = Set(screenshots)
        let additions = urls.filter { seen.insert($0).inserted }
        guard !additions.isEmpty else { return }
        let merged = (screenshots + additions).map { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            return (url, values?.contentModificationDate ?? values?.creationDate ?? .distantPast)
        }.sorted { $0.1 > $1.1 }.map(\.0)
        updateScreenshots(merged)
        if activeMediaDrags.isEmpty { focusedScreenshot = screenshots.first }
    }

    func importSystemScreenshot(_ url: URL) {
        guard phase == .idle, activeMediaDrags.isEmpty else {
            if !pendingSystemScreenshots.contains(url) { pendingSystemScreenshots.append(url) }
            return
        }
        guard !screenshots.contains(url) else { return }
        addScreenshot(url)
        shelfMessage = "截屏已暂存"
        captureReady?()
    }

    func focusScreenshot(_ url: URL) { focusedScreenshot = url }

    func toggleScreenshotPin(_ url: URL) {
        guard screenshots.contains(url) else { return }
        if pinnedScreenshots.remove(url) == nil {
            guard pinnedScreenshots.count < 9 else { shelfMessage = "最多固定 9 张截图"; return }
            pinnedScreenshots.insert(url)
        }
        defaults.set(pinnedScreenshots.map(\.path), forKey: "pinnedScreenshotPaths")
    }

    func editScreenshot(_ url: URL) {
        do { try showScreenshotEditor?(url) }
        catch { shelfMessage = "无法编辑截图：\(error.localizedDescription)" }
    }

    func addEditedScreenshot(_ url: URL) {
        addScreenshot(url)
        shelfMessage = "编辑副本已保存"
    }

    private func saveScreenshot(_ selection: RegionSelection) async throws -> URL {
        let available = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let display = available.displays.first(where: { $0.displayID == selection.displayID }) else {
            throw RecorderError.message("选中的屏幕已断开。")
        }
        let filter = try selfExcludingFilter(for: display, in: available)
        let bounds = CGRect(origin: .zero, size: filter.contentRect.size)
        guard bounds.contains(selection.rect) else { throw RecorderError.message("屏幕尺寸已变化，请重新截图。") }
        let config = SCStreamConfiguration()
        config.sourceRect = selection.rect
        let scale = CGFloat(filter.pointPixelScale)
        config.width = max(1, Int((selection.rect.width * scale).rounded()))
        config.height = max(1, Int((selection.rect.height * scale).rounded()))
        config.showsCursor = false
        config.captureDynamicRange = .SDR
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return try await ScreenshotFile.save(image, in: outputDirectory.appendingPathComponent("截图", isDirectory: true))
    }

    private func selfExcludingFilter(for display: SCDisplay, in content: SCShareableContent) throws -> SCContentFilter {
        // Exclude the process, not just its current windows: the recording HUD
        // can appear after SCStream has already started.
        guard let ownApp = content.applications.first(where: { $0.processID == ProcessInfo.processInfo.processIdentifier }) else {
            // Do not fall back to capturing a display that can include our own overlays.
            throw RecorderError.message("暂时无法排除截录暂存窗口，请重试。")
        }
        return SCContentFilter(display: display, excludingApplications: [ownApp], exceptingWindows: [])
    }

    var selectedMediaURLs: [URL] {
        (recent.map(\.url) + screenshots).filter {
            selectedMedia.contains($0) && FileManager.default.fileExists(atPath: $0.path)
        }
    }

    func toggleMedia(_ url: URL) {
        if selectedMedia.contains(url) { selectedMedia.remove(url) }
        else if FileManager.default.fileExists(atPath: url.path) { selectedMedia.insert(url) }
        shelfMessage = nil
    }

    func clearMediaSelection(resetMessage: Bool = true) {
        if !selectedMedia.isEmpty { selectedMedia.removeAll() }
        if resetMessage { shelfMessage = nil }
    }

    func mediaDragStarted(_ id: UUID) { activeMediaDrags.insert(id) }

    func mediaDragCompleted(_ id: UUID? = nil, accepted: Bool?) {
        if let id { activeMediaDrags.remove(id) }
        if accepted == true { clearMediaSelection(resetMessage: false) }
        if let accepted { shelfMessage = accepted ? "已拖出文件" : "目标未接收文件" }
        importPendingSystemScreenshots()
    }

    private func importPendingSystemScreenshots() {
        guard phase == .idle, activeMediaDrags.isEmpty, !pendingSystemScreenshots.isEmpty else { return }
        let pending = pendingSystemScreenshots
        pendingSystemScreenshots.removeAll()
        for url in pending where FileManager.default.fileExists(atPath: url.path) {
            importSystemScreenshot(url)
        }
    }

    func copyScreenshot(_ url: URL) {
        do {
            try ScreenshotTransfer.copyImage(at: url)
            shelfMessage = "已复制图片"
        } catch { shelfMessage = error.localizedDescription }
    }

    func copySelectedMedia() {
        let urls = selectedMediaURLs
        guard !urls.isEmpty else { return }
        let items = MediaFileTransfer.pasteboardItems(for: urls)
        guard !items.isEmpty else { shelfMessage = "所选文件已移走，请重新勾选。"; return }
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.writeObjects(items)
        shelfMessage = copied ? "已复制 \(items.count) 个文件" : "复制未完成，请重试。"
    }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        copied = true
        Task { try? await Task.sleep(nanoseconds: 2_000_000_000); copied = false }
    }

    private func restoreRecent() async {
        let paths = defaults.stringArray(forKey: "recentPaths") ?? []
        var restored: [RecentRecording] = []
        for path in paths.prefix(8) {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path),
                  let duration = try? await AVURLAsset(url: url).load(.duration).seconds,
                  duration.isFinite else { continue }
            let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.int64Value ?? 0
            restored.append(RecentRecording(url: url, duration: duration, size: size))
        }
        let currentURLs = Set(recent.map(\.url))
        recent = Array((recent + restored.filter { !currentURLs.contains($0.url) }).prefix(8))
    }
}

extension RecorderModel: SCRecordingOutputDelegate, SCStreamDelegate {
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.didStart(recordingOutput) }
    }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in await self.didFinish(recordingOutput) }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in guard self.output === recordingOutput else { return }; await self.fail(error.localizedDescription) }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream, self.phase != .finishing else { return }
            await self.fail("录制意外中断：\(error.localizedDescription)")
        }
    }
}

enum RecorderError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
