import AppKit
import Carbon
import Combine
import SwiftUI
import RecorderCore
import ScreenshotEditing
import ScreenshotWatching

@main
enum LightRecorderApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let model = RecorderModel()
    private var window: NSWindow!
    private var reviewWindow: NSWindow?
    private let screenshotEditor = ScreenshotEditor()
    private let screenshotWatcher = ScreenshotWatcher()
    private var shelf: FloatingShelf!
    private lazy var recordingHUD = RecordingHUD { [weak self] in self?.model.stop() }
    private var workbenchControl: WorkbenchControl?
    private var statusItem: NSStatusItem!
    private var hotKey: EventHotKeyRef?
    private var alternateHotKey: EventHotKeyRef?
    private var screenshotHotKey: EventHotKeyRef?
    private var familiarScreenshotHotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var heldHotKeys: Set<UInt32> = []
    private var wantsToQuit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 694),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "截录暂存 · 录制设置"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(calibratedWhite: 0.975, alpha: 1)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: RecorderView(model: model))
        window.center()

        shelf = FloatingShelf(model: model, openSettings: { [weak self] in self?.showMain() })

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self; statusItem.button?.action = #selector(statusClicked)
        statusItem.button?.toolTip = "截录暂存 · F3 开始 / 停止"
        model.showReview = { [weak self] recording in self?.presentReview(recording) }
        model.showScreenshotEditor = { [weak self] url in
            guard let self else { return }
            try self.screenshotEditor.open(url, onClose: { [weak self] in self?.shelf.setEditingScreenshot(false) }) { [weak self] saved in
                self?.model.addEditedScreenshot(saved)
            }
            self.shelf.setEditingScreenshot(true)
        }
        model.closeReview = { [weak self] in self?.reviewWindow?.close() }
        model.hideMainWindow = { [weak self] in self?.window.orderOut(nil) }
        model.showMainWindow = { [weak self] in self?.showMain() }
        model.captureActivityChanged = { [weak self] active in self?.shelf.setCaptureActive(active) }
        model.captureReady = { [weak self] in self?.shelf.previewCapture() }
        model.screenshotFailed = { [weak self] in self?.shelf.showScreenshotFailure() }
        screenshotWatcher.onScreenshot = { [weak self] file in self?.model.importSystemScreenshot(file.url) }
        screenshotWatcher.onBaseline = { [weak self] files in self?.model.importScreenshotHistory(files.prefix(20).map(\.url)) }
        screenshotWatcher.onIssue = { [weak self] issue in self?.model.systemScreenshotIssue = issue }
        model.screenshotWatchingChanged = { [weak self] in self?.updateScreenshotWatcher() }
        model.screenshotShortcutChanged = { [weak self] in self?.updateFamiliarScreenshotHotKey() }
        updateScreenshotWatcher()
        model.phaseChanged = { [weak self] in self?.updateStatus() }
        if Bundle.main.bundleIdentifier == "local.jackson.light-recorder" {
            workbenchControl = try? WorkbenchControl()
            workbenchControl?.start { [weak self] command in self?.handleWorkbench(command) ?? "busy" }
        }
        registerHotkey()
        updateStatus()
        if !CommandLine.arguments.contains("--background") { shelf.showShelf() }
    }

    private func updateScreenshotWatcher() {
        if model.autoImportScreenshots { screenshotWatcher.start() }
        else { screenshotWatcher.stop(); model.systemScreenshotIssue = nil }
    }

    private func buildMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem(); menu.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let show = NSMenuItem(title: "打开暂存栏", action: #selector(showShelf), keyEquivalent: "0"); show.target = self
        appMenu.addItem(show); appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出截录暂存", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(); menu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑"); editItem.submenu = editMenu
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = menu
    }

    @objc func showMain() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { shelf.showShelf(); return true }
    func applicationDidBecomeActive(_ notification: Notification) { Task { await model.refreshSources() } }
    func applicationDidChangeScreenParameters(_ notification: Notification) {
        shelf?.screenLayoutChanged()
        updateRecordingHUD(reposition: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        switch model.phase {
        case .idle: return .terminateNow
        case .selecting, .countdown: model.cancelStart(); return .terminateNow
        case .recording:
            let alert = NSAlert()
            alert.messageText = "先保存这段录制？"
            alert.informativeText = "停止并保存视频后，截录暂存会自动退出。"
            alert.addButton(withTitle: "保存并退出"); alert.addButton(withTitle: "继续录制")
            if alert.runModal() == .alertFirstButtonReturn { wantsToQuit = true; model.stop(); return .terminateLater }
            return .terminateCancel
        case .preparing, .finishing:
            showMain()
            return .terminateCancel
        }
    }

    private func presentReview(_ recording: RecentRecording) {
        reviewWindow?.close()
        let review = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 570),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        review.title = "回看录屏"
        review.minSize = CGSize(width: 610, height: 470)
        review.isReleasedWhenClosed = false
        review.delegate = self
        review.contentViewController = NSHostingController(rootView: RecordingReview(
            recording: recording, close: { [weak review] in review?.close() }))
        reviewWindow = review
        review.center()
        NSApp.activate(ignoringOtherApps: true)
        review.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow else { return }
        if closed === reviewWindow {
            closed.contentViewController = nil
            reviewWindow = nil
        }
    }

    private func updateStatus() {
        guard statusItem != nil else { return }
        updateRecordingHUD()
        let isRecording = model.phase == .recording
        let symbol = isRecording ? "stop.circle.fill" : "record.circle"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: isRecording ? "停止录制" : "截录暂存")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.title = isRecording ? " \(durationLabel(model.elapsed))" : ""
        if wantsToQuit && model.phase == .idle {
            wantsToQuit = false
            NSApp.reply(toApplicationShouldTerminate: model.errorMessage == nil)
        }
    }

    private func updateRecordingHUD(reposition: Bool = false) {
        recordingHUD.update(phase: model.phase, elapsed: model.elapsed,
                            displayID: model.mode == .display ? model.selectedDisplayID : nil,
                            region: model.mode == .region ? model.region : nil, reposition: reposition)
    }

    @objc private func statusClicked() {
        let menu = NSMenu()
        menu.addItem(withTitle: "打开暂存栏", action: #selector(showShelf), keyEquivalent: "").target = self
        let autoImport = menu.addItem(withTitle: "自动暂存系统截屏", action: #selector(toggleScreenshotWatcher), keyEquivalent: "")
        autoImport.target = self
        autoImport.state = model.autoImportScreenshots ? .on : .off
        let recordTitle: String? = switch model.phase {
        case .idle: model.loadingSources || model.screenshotBusy ? nil : "开始录屏"
        case .recording: "停止并保存  \(durationLabel(model.elapsed))"
        case .selecting: "取消框选"
        case .countdown: "取消录制"
        case .preparing, .finishing: nil
        }
        if let recordTitle {
            let record = NSMenuItem(title: recordTitle, action: #selector(hotkeyPressed), keyEquivalent: "")
            record.target = self; menu.addItem(record)
        }
        let screenshot = NSMenuItem(title: "区域截图", action: model.canStartScreenshot ? #selector(screenshotPressed) : nil, keyEquivalent: "")
        screenshot.target = self
        screenshot.isEnabled = model.canStartScreenshot
        menu.addItem(screenshot)
        if shelf.isVisible && !model.captureActive {
            let dismiss = NSMenuItem(title: "隐藏暂存栏和浮球", action: #selector(dismissShelf), keyEquivalent: "")
            dismiss.target = self; menu.addItem(dismiss)
        }
        let show = NSMenuItem(title: "录制设置", action: #selector(showMain), keyEquivalent: ""); show.target = self
        menu.addItem(show); menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
    }

    @objc func hotkeyPressed() { model.primaryAction() }
    @objc private func screenshotPressed() { model.screenshotAction() }
    @objc private func dismissShelf() { shelf.dismiss() }

    @objc private func showShelf() { shelf.showShelf() }
    @objc private func toggleScreenshotWatcher() { model.autoImportScreenshots.toggle() }

    private var recordStatus: String {
        switch model.phase {
        case .idle: model.loadingSources || model.screenshotBusy ? "busy" : "idle"
        case .recording: "recording"
        case .selecting, .countdown: "starting"
        case .preparing, .finishing: "busy"
        }
    }

    private func handleWorkbench(_ command: WorkbenchControl.Command) -> String {
        switch command {
        case .status:
            return "\(recordStatus) \(model.canStartScreenshot ? 1 : 0) shelf"
        case .record:
            guard recordStatus != "busy" else { return "busy" }
            // A permission prompt can block the main run loop. Reply before invoking it.
            DispatchQueue.main.async { [weak self] in self?.model.primaryAction() }
        case .screenshot:
            guard model.canStartScreenshot else { return "busy" }
            DispatchQueue.main.async { [weak self] in self?.model.screenshotAction() }
        case .shelf: shelf.showShelf()
        case .settings: showMain()
        }
        return "ok"
    }

    private func handleHotkey(id: UInt32, isPressed: Bool) {
        if isPressed {
            // One physical press produces one action, even when the key is held.
            guard heldHotKeys.insert(id).inserted else { return }
            if id == 3 || id == 4 { model.screenshotAction() }
            else { model.primaryAction() }
        } else {
            heldHotKeys.remove(id)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let alternateHotKey { UnregisterEventHotKey(alternateHotKey) }
        if let screenshotHotKey { UnregisterEventHotKey(screenshotHotKey) }
        if let familiarScreenshotHotKey { UnregisterEventHotKey(familiarScreenshotHotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private func registerHotkey() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == 0x4C524543 else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            let isPressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            let id = identifier.id
            Task { @MainActor in delegate.handleHotkey(id: id, isPressed: isPressed) }
            return noErr
        }, eventTypes.count, &eventTypes, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard handlerStatus == noErr else {
            model.errorMessage = "无法启用快捷键，仍可使用设置窗口和菜单栏录屏、截图。"
            return
        }
        let status = RegisterEventHotKey(UInt32(kVK_F3), 0, EventHotKeyID(signature: 0x4C524543, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        let alternateStatus = RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | cmdKey), EventHotKeyID(signature: 0x4C524543, id: 2), GetApplicationEventTarget(), 0, &alternateHotKey)
        let screenshotStatus = RegisterEventHotKey(UInt32(kVK_ANSI_4), UInt32(controlKey | cmdKey), EventHotKeyID(signature: 0x4C524543, id: 3), GetApplicationEventTarget(), 0, &screenshotHotKey)
        if status != noErr {
            model.errorMessage = alternateStatus == noErr ? "F3 已被其他功能占用，可用 ⌃⌘R 或菜单栏开始、停止录制。" : "录制快捷键被占用，仍可使用设置窗口和菜单栏录制。"
        }
        if screenshotStatus != noErr {
            let message = "⌃⌘4 已被占用，可从设置窗口或菜单栏打开截图。"
            model.errorMessage = [model.errorMessage, message].compactMap { $0 }.joined(separator: "\n")
        }
        updateFamiliarScreenshotHotKey()
    }

    private func updateFamiliarScreenshotHotKey() {
        if let familiarScreenshotHotKey { UnregisterEventHotKey(familiarScreenshotHotKey) }
        familiarScreenshotHotKey = nil
        heldHotKeys.remove(4)
        model.screenshotShortcutIssue = nil
        guard model.useShiftCommand4 else { return }
        guard eventHandler != nil,
              RegisterEventHotKey(UInt32(kVK_ANSI_4), UInt32(shiftKey | cmdKey),
                                  EventHotKeyID(signature: 0x4C524543, id: 4),
                                  GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &familiarScreenshotHotKey) == noErr else {
            model.screenshotShortcutIssue = "⌘⇧4 已被占用。请先在系统设置 → 键盘 → 键盘快捷键 → 截屏中改键或关闭对应的区域截屏快捷键，再重新勾选。"
            return
        }
    }
}
