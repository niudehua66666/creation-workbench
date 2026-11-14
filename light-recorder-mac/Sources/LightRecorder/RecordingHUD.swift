import AppKit
import RecorderCore

@MainActor
final class RecordingHUD: NSObject {
    private enum Kind { case countdown, controls }
    private static let countdownSize = CGSize(width: 120, height: 114)
    private static let controlsSize = CGSize(width: 238, height: 48)

    private var panel: NSPanel?
    private var kind: Kind?
    private var value: NSTextField?
    private let stop: () -> Void

    init(stop: @escaping () -> Void) { self.stop = stop }

    func update(phase: RecorderPhase, elapsed: TimeInterval, displayID: CGDirectDisplayID?, region: RegionSelection?, reposition: Bool = false) {
        let next: Kind
        let text: String
        switch phase {
        case .countdown(let count): next = .countdown; text = String(count)
        case .recording: next = .controls; text = durationLabel(elapsed)
        default:
            panel?.orderOut(nil)
            kind = nil
            return
        }

        if kind == next, panel?.isVisible == true, !reposition {
            if value?.stringValue != text { value?.stringValue = text }
            return
        }

        let screens = NSScreen.screens
        let targetID = region?.displayID ?? displayID
        let target = targetID.flatMap { id in screens.first { screenID($0) == id } }
        guard let screen = target ?? screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else {
            panel?.orderOut(nil)
            return
        }
        let selection = region.flatMap { region in
            target.map { RecordingHUDPlacement.screenRect(for: region.rect, on: $0.frame) }
        }
        let frame = switch next {
        case .countdown: RecordingHUDPlacement.countdownFrame(size: Self.countdownSize, in: screen.visibleFrame, selection: selection)
        case .controls: RecordingHUDPlacement.controlsFrame(size: Self.controlsSize, in: screen.visibleFrame, selection: selection)
        }

        let panel = self.panel ?? makePanel()
        panel.setFrame(frame, display: false)
        if kind != next { panel.contentView = makeContent(next, size: frame.size) }
        kind = next
        value?.stringValue = text
        panel.ignoresMouseEvents = next == .countdown
        // This stays above the floating shelf, without activating the recorder.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = RecordingHUDPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        self.panel = panel
        return panel
    }

    private func makeContent(_ kind: Kind, size: CGSize) -> NSView {
        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(white: 0.10, alpha: 0.98).cgColor
        view.layer?.cornerRadius = kind == .countdown ? 22 : 14
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        view.appearance = NSAppearance(named: .darkAqua)

        switch kind {
        case .countdown:
            let count = label("", size: 62, weight: .bold, monospaced: true)
            count.alignment = .center
            count.frame = CGRect(x: 0, y: 29, width: size.width, height: 76)
            let caption = label("即将录制", size: 13, weight: .medium)
            caption.alignment = .center
            caption.frame = CGRect(x: 0, y: 13, width: size.width, height: 17)
            view.addSubview(count); view.addSubview(caption)
            value = count
        case .controls:
            let indicator = NSView(frame: CGRect(x: 13, y: 20, width: 8, height: 8))
            indicator.wantsLayer = true
            indicator.layer?.cornerRadius = 4
            indicator.layer?.backgroundColor = NSColor.systemRed.cgColor
            let elapsed = label("", size: 14, weight: .semibold, monospaced: true)
            elapsed.frame = CGRect(x: 28, y: 14, width: 78, height: 20)
            elapsed.setAccessibilityLabel("录制时长")
            let button = RecordingStopButton(title: "停止并保存", target: self, action: #selector(stopClicked))
            button.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.frame = CGRect(x: size.width - 131, y: 7, width: 123, height: 34)
            button.toolTip = "停止录制并保存 MP4（F3）"
            view.addSubview(indicator); view.addSubview(elapsed); view.addSubview(button)
            value = elapsed
        }
        return view
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, monospaced: Bool = false) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.textColor = .white
        field.font = monospaced ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        return field
    }

    private func screenID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    @objc private func stopClicked() { stop() }
}

private final class RecordingHUDPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }
}

private final class RecordingStopButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
