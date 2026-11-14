import Foundation
import Darwin
import RecentFilesCore

@MainActor
public final class ScreenshotWatcher {
    public var onScreenshot: ((RecentFile) -> Void)?
    public var onIssue: ((String?) -> Void)?
    public var onBaseline: (([RecentFile]) -> Void)?
    public var currentDirectory: () -> URL = { ScreenshotFiles.defaultDirectory() }
    private var timer: Timer?
    private var retryTimer: Timer?
    private var directoryEvents: DispatchSourceFileSystemObject?
    private var scanning = false
    private var scanRequested = false
    private var rapidChecksRemaining = 0
    private var generation = UUID()
    private var tracker = ScreenshotTracker()
    private var observedPath: String?

    public init() {}

    public func start() {
        stop()
        // Directory notifications handle new files immediately. This slow timer
        // recovers if a folder is replaced or the system screenshot path changes.
        let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        poll()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        retryTimer?.invalidate()
        retryTimer = nil
        directoryEvents?.cancel()
        directoryEvents = nil
        generation = UUID()
        tracker = ScreenshotTracker()
        observedPath = nil
        scanning = false
        scanRequested = false
        rapidChecksRemaining = 0
    }

    private func watchDirectory(_ directory: URL) {
        guard directoryEvents == nil else { return }
        let descriptor = open(directory.path, O_EVTONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return }
        let token = generation
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                let flags = self.directoryEvents?.data ?? []
                if !flags.intersection([.rename, .delete, .revoke]).isEmpty {
                    self.directoryEvents?.cancel()
                    self.directoryEvents = nil
                }
                self.rapidChecksRemaining = 12
                self.poll()
            }
        }
        source.setCancelHandler { close(descriptor) }
        directoryEvents = source
        source.resume()
    }

    private func checkAgain(after interval: TimeInterval) {
        retryTimer?.invalidate()
        let token = generation
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.poll()
            }
        }
        retryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func poll() {
        guard !scanning else { scanRequested = true; return }
        retryTimer?.invalidate()
        retryTimer = nil
        scanning = true
        let token = generation
        let directory = currentDirectory()
        if observedPath != directory.path {
            directoryEvents?.cancel()
            directoryEvents = nil
            tracker = ScreenshotTracker()
            observedPath = directory.path
        }
        watchDirectory(directory)
        let needsBaseline = !tracker.hasBaseline && onBaseline != nil
        Task {
            let (files, issue, baseline) = await Task.detached(priority: .utility) {
                let result = RecentFileScanner.scan(folders: [directory], limit: Int.max)
                let files = result.files.filter { ScreenshotFiles.isScreenshot($0.url) }
                let issue = result.issues.first?.message
                let baseline = needsBaseline && issue == nil
                    ? files.prefix(20).filter { ScreenshotFiles.isCompleteImage($0.url) } : []
                return (files, issue, baseline)
            }.value
            guard token == generation else { return }
            scanning = false
            onIssue?(issue)
            guard issue == nil else { scanRequested = false; return }
            if needsBaseline { onBaseline?(baseline) }
            let hadPending = tracker.hasPending
            for file in tracker.ingestAll(files, isReady: { ScreenshotFiles.isCompleteImage($0.url) }) {
                onScreenshot?(file)
            }
            if !hadPending && tracker.hasPending { rapidChecksRemaining = 12 }
            if scanRequested {
                scanRequested = false
                checkAgain(after: 0.02)
            } else if tracker.hasPending && rapidChecksRemaining > 0 {
                rapidChecksRemaining -= 1
                checkAgain(after: 0.10)
            }
        }
    }
}
