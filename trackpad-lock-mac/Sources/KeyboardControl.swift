import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Darwin
import IOKit
import IOKit.hidsystem
import os

private let keyboardLog = Logger(subsystem: "local.jackson.trackpad-lock", category: "keyboard")

private let mappingKey = "UserKeyMapping" as CFString
private let src = "HIDKeyboardModifierMappingSrc"
private let dst = "HIDKeyboardModifierMappingDst"
private let missionControl: UInt64 = 0xff0100000010
private let standardF3: UInt64 = 0x70000003c
private let f3Swap: [[String: UInt64]] = [
    [src: standardF3, dst: missionControl],
    [src: missionControl, dst: standardF3],
]
private let legacyF3Block = [src: missionControl, dst: UInt64(0)]
private let f3Sources: Set<UInt64> = [standardF3, missionControl]
private let spotlight: UInt64 = 0xc00000221
private let standardF4: UInt64 = 0x70000003d
private let forceQuitTrigger: UInt64 = 0x70000006f // F20, so standard F4 on external keyboards stays available.
private let f4Signature: OSType = 0x46725174 // FrQt
private let f4Map: [[String: UInt64]] = [
    [src: spotlight, dst: forceQuitTrigger],
    [src: standardF4, dst: spotlight],
]
private let f4Sources: Set<UInt64> = [standardF4, spotlight]
private let shortcutSources = f3Sources.union(f4Sources)
private typealias KeyMap = [[String: UInt64]]

private struct KeyboardDevice {
    // Keep the connection alive for the lifetime of the service reference.
    let client: IOHIDEventSystemClient
    let service: IOHIDServiceClient
    let id: UInt64
    let supported: [UInt64]
    let standardFunctionKeys: Bool
    let hasSpotlightF4: Bool

    static func inspect() -> (device: KeyboardDevice?, external: Bool) {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] ?? []
        var devices: [KeyboardDevice] = []
        var external = false
        for service in services where IOHIDServiceClientConformsTo(service, 1, 6) != 0 {
            let transport = IOHIDServiceClientCopyProperty(service, "Transport" as CFString) as? String
            let builtIn = IOHIDServiceClientCopyProperty(service, "Built-In" as CFString) as? Bool == true
            if !builtIn {
                if let transport, ["USB", "Bluetooth", "Bluetooth Low Energy", "BTLE"].contains(transport) { external = true }
                continue
            }
            guard let id = IOHIDServiceClientGetRegistryID(service) as? UInt64 else { continue }
            let entry = IOServiceGetMatchingService(kIOMainPortDefault, IORegistryEntryIDMatching(id))
            guard entry != IO_OBJECT_NULL else { continue }
            defer { IOObjectRelease(entry) }
            guard IOObjectConformsTo(entry, "AppleHIDKeyboardEventDriverV2") != 0,
                  let supported = IORegistryEntryCreateCFProperty(entry, "SupportedKeyboardUsagePairs" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [UInt64],
                  let fnMap = IORegistryEntryCreateCFProperty(entry, "FnFunctionUsageMap" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                  fnMap.lowercased().contains("0x0007003c,0xff010010") else { continue }
            let items = fnMap.split(separator: ",").compactMap { UInt64($0.dropFirst(2), radix: 16) }
            let extra = items.enumerated().filter { $0.offset % 2 == 1 }.map { ($0.element >> 16) << 32 | ($0.element & 0xffff) }
            let fnNavigation: [UInt64] = [0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x58].map { 0x700000000 | $0 }
            let all = supported + extra + fnNavigation + [0xff00000003, 0xff0100000003]
            let properties = IORegistryEntryCreateCFProperty(entry, "HIDEventServiceProperties" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any]
            let standard = properties?["HIDFKeyMode"] as? Bool ?? UserDefaults.standard.bool(forKey: "com.apple.keyboard.fnState")
            devices.append(KeyboardDevice(client: client, service: service, id: id, supported: Array(Set(all)).sorted(), standardFunctionKeys: standard,
                                          hasSpotlightF4: fnMap.lowercased().contains("0x0007003d,0x000c0221")))
        }
        return (devices.count == 1 ? devices.first : nil, external)
    }

    func setMap(_ map: KeyMap, cliOnly: Bool = false) -> Bool {
        // Prefer the system API. On this macOS version the built-in service can
        // reject writes from a bundled process; hidutil is Apple's supported CLI.
        if !cliOnly && IOHIDServiceClientSetProperty(service, mappingKey, map as CFArray) { return true }
        guard map.allSatisfy({ shortcutSources.contains($0[src] ?? 0) }),
              let data = try? JSONSerialization.data(withJSONObject: ["UserKeyMapping": map]),
              let json = String(data: data, encoding: .utf8) else { return false }
        let selector = "{\"PrimaryUsagePage\":1,\"PrimaryUsage\":6,\"Transport\":\"FIFO\"}"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--matching", selector, "--set", json]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    // The cached property alone can report success even if the system rejected a restricted mapping.
    func appliedMap() -> KeyMap? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["dump", "services", "-f", "xml"]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let dump = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let services = dump["ServiceRecords"] as? [[String: Any]],
              let record = services.first(where: { $0["IORegistryEntryID"] as? UInt64 == id }),
              let filters = record["ServiceFilterDebug"] as? [[String: Any]] else { return nil }
        for filter in filters {
            guard let plugin = filter["plugin"] as? [String: Any], plugin["Class"] as? String == "IOHIDKeyboardFilter",
                  let entries = plugin["UserKeyMapping"] as? [[String: UInt64]] else { continue }
            return entries.compactMap { pair in
                guard let s = pair["Src"], let d = pair["Dst"] else { return nil }
                return [src: s, dst: d]
            }
        }
        return nil
    }

    func verifies(_ expected: KeyMap) -> Bool {
        func sorted(_ entries: KeyMap) -> KeyMap { entries.sorted { ($0[src] ?? 0) < ($1[src] ?? 0) } }
        for _ in 0..<3 {
            if appliedMap().map(sorted) == sorted(expected) { return true }
            usleep(40_000)
        }
        return false
    }
}

final class KeyboardControl {
    private let marker: URL
    private var guardProcess: Process?
    private var input: FileHandle?
    private var deviceInfo = KeyboardDevice.inspect()
    private var state = "ready"
    private var warning: String?
    private var timer: Timer?
    private var f3Applied = false
    private var f3Attempted = false
    private var f3Warning: String?
    private var f3Enabled: Bool { UserDefaults.standard.object(forKey: "PreventF3") as? Bool ?? true }
    private var f4HotKey: EventHotKeyRef?
    private var f4Handler: EventHandlerRef?
    private var f4Applied = false
    private var f4Attempted = false
    private var f4Warning: String?
    private var forceQuitPermission = AXIsProcessTrusted()
    private var f4Enabled: Bool {
        let preferences = UserDefaults.standard
        return preferences.object(forKey: "F4ForceQuit") as? Bool
            ?? preferences.object(forKey: "F4ActivityMonitor") as? Bool
            ?? true
    }
    var didChange: (() -> Void)?

    init(directory: URL) {
        marker = directory.appendingPathComponent("keyboard-recovery.plist")
        if !Self.recover(marker) {
            state = "recovery"
            warning = "键盘恢复未确认，请重试恢复"
        } else { applyF3(); applyF4(enabled: f4Enabled) }
        timer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            let previous = self.deviceInfo.device?.id
            self.deviceInfo = KeyboardDevice.inspect()
            if self.deviceInfo.device?.id != previous {
                self.f3Applied = false
                self.f3Attempted = false
                self.f4Applied = false
                self.f4Attempted = false
                self.unregisterF4()
            }
            if self.f3Applied && self.deviceInfo.device?.standardFunctionKeys == true { self.f3Warning = "请关闭系统设置中的「将 F1、F2 等键用作标准功能键」" }
            else if self.f3Applied { self.f3Warning = nil }
            if self.state == "ready" && !self.f3Attempted && self.f3Enabled { self.applyF3() }
            let allowed = AXIsProcessTrusted()
            if allowed != self.forceQuitPermission {
                self.forceQuitPermission = allowed
                self.f4Attempted = false
            }
            if self.state == "ready" && !self.f4Attempted { self.applyF4(enabled: self.f4Enabled) }
        }
    }

    private func applyF3() {
        guard let device = deviceInfo.device, let old = device.appliedMap() else { return }
        f3Attempted = true
        f3Warning = nil
        let hasSwap = f3Swap.allSatisfy(old.contains)
        let remaining = old.filter { entry in
            entry != legacyF3Block && !(hasSwap && f3Swap.contains(entry))
        }
        if f3Enabled && remaining.contains(where: { f3Sources.contains($0[src] ?? 0) }) {
            f3Applied = false
            f3Warning = "F3 已由其他工具设置"
            return
        }
        let target = remaining + (f3Enabled ? f3Swap : [])
        let written = target == old || device.setMap(target, cliOnly: target.allSatisfy { shortcutSources.contains($0[src] ?? 0) })
        let verified = written && device.verifies(target)
        keyboardLog.notice("F3 mapping write: \(written); verified: \(verified)")
        if verified {
            f3Applied = f3Enabled
            if f3Enabled && device.standardFunctionKeys { f3Warning = "请关闭系统设置中的「将 F1、F2 等键用作标准功能键」" }
        } else {
            f3Applied = hasSwap
            _ = device.setMap(old, cliOnly: old.allSatisfy { shortcutSources.contains($0[src] ?? 0) })
            f3Warning = "未能应用 F3 设置"
        }
    }

    private func registerF4() -> Bool {
        if f4HotKey != nil { return true }
        let target = GetEventDispatcherTarget()
        let events = [kEventHotKeyPressed, kEventHotKeyReleased].map {
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32($0))
        }
        let handler = InstallEventHandler(target, { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard result == noErr, id.signature == f4Signature, id.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            if GetEventKind(event) == kEventHotKeyReleased {
                KeyboardControl.showForceQuitWindow()
            }
            return noErr
        }, events.count, events, nil, &f4Handler)
        guard handler == noErr else { return false }
        let registered = RegisterEventHotKey(UInt32(kVK_F20), 0, EventHotKeyID(signature: f4Signature, id: 1),
                                             target, UInt32(kEventHotKeyExclusive), &f4HotKey)
        if registered == noErr && f4HotKey != nil { return true }
        unregisterF4()
        return false
    }

    private static func showForceQuitWindow() {
        guard AXIsProcessTrusted(),
              let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        else { return }

        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.4)

        func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value as? T
        }

        func children(_ element: AXUIElement) -> [AXUIElement] {
            attribute(element, "AXChildren") ?? []
        }

        guard let bars = attribute(app, "AXMenuBar") as CFTypeRef?,
              CFGetTypeID(bars) == AXUIElementGetTypeID(),
              let appleMenu = children(unsafeDowncast(bars, to: AXUIElement.self)).first
        else { return }
        // Command is implicit in AX modifiers. Exactly Option + Command
        // excludes the alternate menu item that force-quits the frontmost app.
        for item in children(appleMenu).flatMap(children) {
            let modifiers: Int? = attribute(item, "AXMenuItemCmdModifiers")
            guard modifiers == Int(kMenuOptionModifier) else { continue }
            let key: Int? = attribute(item, "AXMenuItemCmdVirtualKey")
            let glyph: Int? = attribute(item, "AXMenuItemCmdGlyph")
            if key == Int(kVK_Escape) || glyph == Int(kMenuEscapeGlyph) {
                let result = AXUIElementPerformAction(item, "AXPress" as CFString)
                if result != .success { keyboardLog.error("Cannot open Force Quit window: \(result.rawValue)") }
                return
            }
        }
        keyboardLog.error("Could not find the Force Quit window command in the Apple menu")
    }

    private func unregisterF4() {
        if let f4HotKey { UnregisterEventHotKey(f4HotKey) }
        if let f4Handler { RemoveEventHandler(f4Handler) }
        f4HotKey = nil
        f4Handler = nil
    }

    private func applyF4(enabled requested: Bool) {
        guard let device = deviceInfo.device, let old = device.appliedMap() else { return }
        f4Attempted = true
        f4Warning = nil
        let enabled = requested && forceQuitPermission
        let hasMap = f4Map.allSatisfy(old.contains)
        let remaining = hasMap ? old.filter { !f4Map.contains($0) } : old
        if enabled {
            guard device.hasSpotlightF4 else { f4Warning = "当前内置键盘没有 F4 聚焦键"; return }
            guard !remaining.contains(where: { f4Sources.contains($0[src] ?? 0) || $0[dst] == forceQuitTrigger }) else {
                f4Warning = "F4 已由其他工具设置"
                return
            }
            guard registerF4() else { f4Warning = "F4 快捷键无法注册，可能被其他工具占用"; return }
        }
        let target = remaining + (enabled ? f4Map : [])
        let written = target == old || device.setMap(target, cliOnly: target.allSatisfy { shortcutSources.contains($0[src] ?? 0) })
        if written && device.verifies(target) {
            f4Applied = enabled
            if !enabled { unregisterF4() }
        } else {
            _ = device.setMap(old, cliOnly: old.allSatisfy { shortcutSources.contains($0[src] ?? 0) })
            f4Applied = hasMap && f4HotKey != nil
            if !f4Applied { unregisterF4() }
            f4Warning = "未能应用 F4 设置"
        }
    }

    func shutDown() {
        let guardToStop = guardProcess
        guardProcess = nil
        release()
        if f4Applied {
            // The guard restores its saved map after the pipe closes. Clear F4
            // only after that restoration so it cannot put the shortcut back.
            guardToStop?.waitUntilExit()
            if Self.recover(marker) { applyF4(enabled: false) }
        }
        unregisterF4()
    }

    func release() {
        if let input {
            self.input = nil
            try? input.close()
            state = "unlocking"
        }
    }

    func toggle() {
        if state == "locked" || state == "locking" { release() }
        else if state == "ready" { try? lock() }
        didChange?()
    }

    func command(_ command: String) -> [String: Any] {
        switch command {
        case "keyboard-status": break
        case "keyboard-lock":
            do { try lock() } catch { return ["error": error.localizedDescription] }
        case "keyboard-unlock":
            if state == "recovery" {
                if Self.recover(marker) {state = "ready"; warning = nil; applyF3(); applyF4(enabled: f4Enabled)}
            } else { release() }
        case "keyboard-permission":
            _ = CGRequestListenEventAccess()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
        case "f3-on", "f3-off":
            guard state == "ready" else { return ["error": "请先恢复内置键盘"] }
            UserDefaults.standard.set(command == "f3-on", forKey: "PreventF3")
            applyF3()
        case "f4-permission":
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        case "f4-on", "f4-off":
            guard state == "ready" else { return ["error": "请先恢复内置键盘"] }
            let enabled = command == "f4-on"
            forceQuitPermission = AXIsProcessTrusted()
            applyF4(enabled: enabled)
            if f4Warning == nil {
                UserDefaults.standard.set(enabled, forKey: "F4ForceQuit")
            }
        default: return ["error": "未知操作"]
        }
        if command != "keyboard-status" { didChange?() }
        return status()
    }

    func status() -> [String: Any] {
        let allowed = CGPreflightListenEventAccess()
        let present = deviceInfo.device != nil
        let displayF4Warning = f4Applied && deviceInfo.device?.standardFunctionKeys == true
            ? "当前为标准功能键模式，按 Fn + F4 打开强制退出窗口" : f4Warning
        return ["state": present || state != "ready" ? state : "unavailable", "external": deviceInfo.external,
                "permission": allowed, "warning": warning as Any? ?? NSNull(),
                "f3": f3Applied, "f3Warning": f3Warning as Any? ?? NSNull(),
                "f4Action": "force-quit", "f4Permission": forceQuitPermission, "f4": f4Applied, "f4Warning": displayF4Warning as Any? ?? NSNull()]
    }

    private func lock() throws {
        guard state == "ready" else { return }
        deviceInfo = KeyboardDevice.inspect()
        guard deviceInfo.device != nil else { throw failure("找不到可控制的 Mac 内置键盘") }
        guard deviceInfo.external else { throw failure("请先连接外接键盘") }
        guard CGPreflightListenEventAccess() else { throw failure("请先允许触控板锁访问「输入监控」") }
        guard let executable = Bundle.main.executableURL else { throw failure("无法启动键盘锁") }
        let process = Process(), pipe = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["--keyboard-guard", marker.path]
        process.standardInput = pipe
        process.standardOutput = output
        process.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async {
                guard let self, self.guardProcess === ended else { return }
                self.release()
                self.guardProcess = nil
                let recovered = Self.recover(self.marker)
                self.state = recovered ? "ready" : "recovery"
                if recovered && self.f3Enabled && !self.f3Applied { self.applyF3() }
                if recovered { self.applyF4(enabled: self.f4Enabled) }
                if !recovered {self.warning = "键盘恢复未确认，请重试恢复"}
                else if ended.terminationStatus != 0 {self.warning = "macOS 未能锁定键盘；请检查输入监控授权"}
                self.didChange?()
            }
        }
        try process.run()
        guardProcess = process
        input = pipe.fileHandleForWriting
        state = "locking"
        warning = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = output.fileHandleForReading.readData(ofLength: 7) == Data("locked\n".utf8)
            DispatchQueue.main.async { [weak self] in
                guard let self, ok, self.guardProcess === process, self.state == "locking" else { return }
                self.state = "locked"
                self.didChange?()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.guardProcess === process, self.state == "locking" else { return }
            self.release()
            self.didChange?()
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "TrackpadLock.Keyboard", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    // Keep the recovery file until the old map is actually back in the system filter.
    private static func recover(_ file: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: file.path) else { return true }
        guard let data = try? Data(contentsOf: file), let record = try? PropertyListDecoder().decode(Recovery.self, from: data),
              let device = KeyboardDevice.inspect().device else { return false }
        if device.id == record.id && !device.verifies(record.previous) {
            let restored = device.setMap(record.previous) && device.verifies(record.previous)
            if !restored {
                guard device.setMap(record.previous, cliOnly: true), device.verifies(record.previous) else { return false }
            }
        }
        do { try FileManager.default.removeItem(at: file); return true }
        catch { return false }
    }

    private struct Recovery: Codable { let id: UInt64; let previous: KeyMap }

    static func guardKeyboard(marker: URL) -> Int32 {
        var stdinInfo = stat()
        var fd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        guard fstat(STDIN_FILENO, &stdinInfo) == 0, (stdinInfo.st_mode & S_IFMT) == S_IFIFO,
              poll(&fd, 1, 0) == 0, recover(marker) else { return 1 }
        let (device, external) = KeyboardDevice.inspect()
        guard let device, external, let old = device.appliedMap(), CGPreflightListenEventAccess() else { return 2 }
        let target = device.supported.map { [src: $0, dst: UInt64(0)] }
        guard let data = try? PropertyListEncoder().encode(Recovery(id: device.id, previous: old)),
              (try? data.write(to: marker, options: .atomic)) != nil else { return 3 }
        signal(SIGPIPE, SIG_IGN)
        guard poll(&fd, 1, 0) == 0 else { _ = recover(marker); return 1 }
        let locked = device.setMap(target) && device.verifies(target)
        if locked {
            FileHandle.standardOutput.write(Data("locked\n".utf8))
            while poll(&fd, 1, 400) == 0 {
                let info = KeyboardDevice.inspect()
                if !info.external || info.device?.id != device.id { break }
            }
        }
        return recover(marker) && locked ? 0 : 4
    }
}
