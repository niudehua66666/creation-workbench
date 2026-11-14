import AppKit
import Carbon.HIToolbox
import ServiceManagement
import os

private let appName = "触控板锁"
private let shortcutSignature: OSType = 0x54704C6B // TpLk
private let logger = Logger(subsystem: "local.jackson.trackpad-lock", category: "app")
private let modifiers = UInt32(controlKey | optionKey | cmdKey)

final class TrackpadLockApp: NSObject, NSApplicationDelegate {
    private enum State { case ready, locking, locked, unlocking }
    private var state = State.ready
    private var guardProcess: Process?
    private var guardInput: FileHandle?
    private var supportFile: URL?
    private var control: TrackpadControl?
    private var keyboard: KeyboardControl?
    private var keyboardItem: NSMenuItem!
    private var available = false
    private var warning: String?
    private var shortcut: String?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var status: NSStatusItem!
    private var stateItem: NSMenuItem!
    private var actionItem: NSMenuItem!
    private var shortcutItem: NSMenuItem!
    private var warningItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var recoveryFailed = false

    private var helper: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/TrackpadGuard")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let directory = root.appendingPathComponent("TrackpadLock", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            // Claim the controller before touching the driver or the shortcut.
            guard let control = try TrackpadControl(directory: directory) else { exit(0) }
            self.control = control
            keyboard = KeyboardControl(directory: directory)
            let marker = directory.appendingPathComponent("recovery.lock")
            supportFile = marker
            let recovery = try runHelper(["recover", marker.path])
            if recovery == 0 {
                available = try runHelper(["probe"]) == 0
                if !available { warning = "未找到可控制的内置触控板" }
            } else if recovery == 7 || recovery == 4 {
                recoveryFailed = true
                warning = "触控板尚未恢复，请按快捷键重试"
            } else {
                warning = recovery == 2 ? "未找到可控制的内置触控板" : "初始化失败，请重新打开应用"
            }
        } catch {
            warning = "初始化失败，请重新打开应用"
        }
        makeMenu()
        keyboard?.didChange = { [weak self] in self?.refresh() }
        registerShortcut()
        control?.start { [weak self] command in self?.handleControl(command) ?? ["error": "触控板锁已退出"] }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(restoreOnSessionChange), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(restoreOnSessionChange), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(restoreOnSessionChange), name: NSWorkspace.didWakeNotification, object: nil)
        refresh()
        #if TRACKPAD_QA
        DispatchQueue.main.async { self.verifyShortcutHandler() }
        #endif
    }

    #if TRACKPAD_QA
    private func sendTestHotKey() -> Bool {
        var event: EventRef?
        guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyReleased), GetCurrentEventTime(),
                          EventAttributes(kEventAttributeUserEvent), &event) == noErr, let event else { return false }
        defer { ReleaseEvent(event) }
        var id = EventHotKeyID(signature: shortcutSignature, id: 1)
        return SetEventParameter(event, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID),
                                 MemoryLayout<EventHotKeyID>.size, &id) == noErr
            && SendEventToEventTarget(event, GetEventDispatcherTarget()) == noErr
    }

    private func verifyShortcutHandler() {
        guard shortcut == "⌃⌥⌘T", available, sendTestHotKey(), state == .locking else { exit(10) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard self.state == .locked, self.stateItem.title.contains("已锁定"), self.sendTestHotKey() else { exit(11) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                guard self.state == .ready, self.stateItem.title.contains("可用"), self.warning == nil else { exit(12) }
                print("PASS: registered global shortcut handler drives lock and unlock and updates menu")
                NSApp.terminate(nil)
            }
        }
    }
    #endif

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if state == .locked || state == .locking || recoveryFailed { toggle() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        releaseTrackpad()
        keyboard?.shutDown()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }

    private func handleControl(_ command: String) -> [String: Any] {
        if command.hasPrefix("keyboard-") || command.hasPrefix("f3-") || command.hasPrefix("f4-") {
            return keyboard?.command(command) ?? ["error": "内置键盘控制不可用"]
        }
        switch command {
        case "status": break
        case "lock":
            guard available, shortcut != nil, !recoveryFailed else {
                return ["error": warning ?? "快捷键不可用，暂时无法锁定触控板"]
            }
            if state == .ready { holdTrackpad() }
        case "unlock":
            if recoveryFailed { retryRecovery() }
            else { releaseTrackpad() }
        default: return ["error": "未知操作"]
        }
        let label: String
        switch state {
        case .ready: label = recoveryFailed ? "recovery" : (available ? "ready" : "unavailable")
        case .locking: label = "locking"
        case .locked: label = "locked"
        case .unlocking: label = "unlocking"
        }
        return ["state": label, "shortcut": shortcut as Any? ?? NSNull(), "warning": warning as Any? ?? NSNull()]
    }

    private func runHelper(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = helper
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func makeMenu() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        shortcutItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        warningItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        for item in [stateItem!, shortcutItem!, warningItem!] { menu.addItem(item) }
        menu.addItem(.separator())
        actionItem = NSMenuItem(title: "", action: #selector(toggle), keyEquivalent: "")
        actionItem.target = self
        menu.addItem(actionItem)
        keyboardItem = NSMenuItem(title: "内置键盘", action: #selector(toggleKeyboard), keyEquivalent: "")
        keyboardItem.target = self
        menu.addItem(keyboardItem)
        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "登录时打开", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.isEnabled = true
        menu.addItem(loginItem)
        let quit = NSMenuItem(title: "退出触控板锁", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        quit.isEnabled = true
        menu.addItem(quit)
        status.menu = menu
    }

    private func refresh() {
        let locked = state == .locked || state == .unlocking || recoveryFailed
        let title: String
        switch state {
        case .ready: title = recoveryFailed ? "恢复未确认" : (available ? "可用" : "不可用")
        case .locking: title = "正在锁定…"
        case .locked: title = "已锁定"
        case .unlocking: title = "正在恢复…"
        }
        stateItem.title = "内置触控板：\(title)"
        shortcutItem.title = shortcut.map { "切换快捷键：\($0)" } ?? "切换快捷键无法注册"
        warningItem.title = warning ?? ""
        warningItem.isHidden = warning == nil
        actionItem.title = recoveryFailed ? "重试恢复触控板" : (locked ? "恢复触控板" : "锁定触控板")
        // Never lock out a user if there is no working keyboard recovery shortcut.
        actionItem.isEnabled = recoveryFailed || state == .locked || (available && state == .ready && shortcut != nil)
        let keyboardStatus = keyboard?.status()
        let keyboardState = keyboardStatus?["state"] as? String
        let keyboardLocked = ["locking", "locked", "unlocking", "recovery"].contains(keyboardState ?? "")
        keyboardItem.title = keyboardLocked ? "恢复内置键盘" : "锁定内置键盘"
        keyboardItem.isEnabled = keyboardLocked || (keyboardState == "ready" && keyboardStatus?["external"] as? Bool == true && keyboardStatus?["permission"] as? Bool == true)
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let symbol = locked || keyboardLocked ? "lock.fill" : "lock.open"
        status.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: appName)
        let description = "\(appName)：\(title)" + (shortcut.map { " · \($0) 切换" } ?? "")
        status.button?.toolTip = description
        status.button?.setAccessibilityLabel(description)
    }

    private func registerShortcut() {
        let specs = [kEventHotKeyPressed, kEventHotKeyReleased].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
        }
        let target = GetEventDispatcherTarget()
        let result = InstallEventHandler(target, { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr && id.signature == shortcutSignature && id.id == 1 else { return OSStatus(eventNotHandledErr) }
            if GetEventKind(event) == kEventHotKeyReleased {
                Unmanaged<TrackpadLockApp>.fromOpaque(context).takeUnretainedValue().toggle()
            }
            return noErr
        }, specs.count, specs, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        guard result == noErr else { logger.error("Hot key handler failed: \(result)"); return }
        for (key, label) in [(kVK_ANSI_T, "⌃⌥⌘T"), (kVK_ANSI_L, "⌃⌥⌘L")] {
            if RegisterEventHotKey(UInt32(key), modifiers, EventHotKeyID(signature: shortcutSignature, id: 1),
                                   target, UInt32(kEventHotKeyExclusive), &hotKey) == noErr, hotKey != nil {
                shortcut = label
                logger.notice("Registered \(label, privacy: .public)")
                return
            }
        }
    }

    @objc private func toggle() {
        logger.notice("Toggle requested")
        switch state {
        case .locked, .locking:
            releaseTrackpad()
        case .unlocking:
            return
        case .ready:
            if recoveryFailed { retryRecovery() }
            else if available && shortcut != nil { holdTrackpad() }
        }
    }

    private func holdTrackpad() {
        guard let supportFile else { return }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = helper
        process.arguments = ["hold", supportFile.path]
        process.standardInput = input
        process.standardOutput = output
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async { [weak self] in self?.guardFinished(finished) }
        }
        do {
            try process.run()
            guardProcess = process
            guardInput = input.fileHandleForWriting
            state = .locking
            warning = nil
            refresh()
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let ready = output.fileHandleForReading.readData(ofLength: 7) == Data("locked\n".utf8)
                DispatchQueue.main.async { [weak self] in
                    guard let self, ready, self.guardProcess === process, self.state == .locking else { return }
                    self.state = .locked
                    self.refresh()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.guardProcess === process, self.state == .locking else { return }
                self.warning = "锁定超时，请重试"
                self.releaseTrackpad()
            }
        } catch {
            warning = "无法启动触控板控制，请重试"
            refresh()
        }
    }

    @objc private func toggleKeyboard() {
        let state = keyboard?.status()["state"] as? String
        if state == "recovery" { _ = keyboard?.command("keyboard-unlock") }
        else { keyboard?.toggle() }
    }

    @objc private func restoreOnSessionChange() { releaseTrackpad(); keyboard?.release() }

    private func releaseTrackpad() {
        guard let input = guardInput else { return }
        guardInput = nil
        try? input.close()
        state = .unlocking
        refresh()
    }

    private func guardFinished(_ finished: Process) {
        guard guardProcess === finished else { return }
        let wasUnlocking = state == .unlocking
        guardProcess = nil
        if let input = guardInput { try? input.close(); guardInput = nil }
        state = .ready
        if finished.terminationReason != .exit || finished.terminationStatus == 7 {
            retryRecovery()
            return
        }
        if finished.terminationStatus != 0 || !wasUnlocking {
            warning = finished.terminationStatus == 5 ? "系统已经停用了触控板" : "未能锁定触控板，请重试"
        }
        refresh()
    }

    private func retryRecovery() {
        guard let supportFile else { return }
        recoveryFailed = (try? runHelper(["recover", supportFile.path])) != 0
        available = !recoveryFailed && (try? runHelper(["probe"])) == 0
        warning = recoveryFailed ? "触控板尚未恢复，请按快捷键重试" : (available ? nil : "未找到可控制的内置触控板")
        refresh()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled: try service.unregister()
            case .requiresApproval: SMAppService.openSystemSettingsLoginItems()
            default: try service.register()
            }
            warning = service.status == .requiresApproval ? "请在系统设置中允许登录时打开" : nil
        } catch {
            warning = "无法更改登录项，请在系统设置中调整"
        }
        refresh()
    }
}

if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--keyboard-guard" {
    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let marker = directory.appendingPathComponent("TrackpadLock/keyboard-recovery.plist")
    guard marker.path == CommandLine.arguments[2] else { exit(1) }
    exit(KeyboardControl.guardKeyboard(marker: marker))
}

let app = NSApplication.shared
let delegate = TrackpadLockApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
