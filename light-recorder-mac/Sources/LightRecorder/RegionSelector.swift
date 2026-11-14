import AppKit
import RecorderCore

@MainActor
final class RegionSelector {
    enum Purpose {
        case startRecording, setRecordingRegion, screenshot

        var hint: String {
            switch self {
            case .startRecording: "拖动框选，松开开始录制    ·    Esc 取消"
            case .setRecordingRegion: "拖动框选，松开确认范围    ·    Esc 取消"
            case .screenshot: "拖动框选，松开保存截图    ·    Esc 取消"
            }
        }
    }

    private var panels: [NSPanel] = []
    private var keyMonitor: Any?
    private var completed = false
    private let purpose: Purpose
    private let completion: (RegionSelection?) -> Void

    init(purpose: Purpose, completion: @escaping (RegionSelection?) -> Void) {
        self.purpose = purpose
        self.completion = completion
    }

    func present() {
        let passive = purpose == .screenshot
        if !passive { NSApp.activate(ignoringOtherApps: true) }
        for screen in NSScreen.screens {
            guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
            let panel = SelectionPanel(contentRect: screen.frame, styleMask: passive ? [.borderless, .nonactivatingPanel] : [.borderless], backing: .buffered, defer: false)
            panel.setFrame(screen.frame, display: false)
            panel.level = .screenSaver
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size), hint: purpose.hint,
                                     drawsCrosshair: passive) { [weak self] rect in
                self?.finish(RegionSelection(displayID: displayID, rect: rect))
            }
            panel.contentView = view; panel.makeFirstResponder(view)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        (panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? panels.first)?.makeKey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel(); return nil }
            return event
        }
        if panels.isEmpty { cancel() }
    }

    func cancel() { finish(nil) }

    private func finish(_ selection: RegionSelection?) {
        guard !completed else { return }; completed = true
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }; keyMonitor = nil
        for panel in panels { panel.orderOut(nil); panel.close() }
        panels.removeAll()
        completion(selection)
    }
}

final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class SelectionView: NSView {
    private var start: CGPoint?
    private var current: CGPoint?
    private var pointer: CGPoint?
    private var completion: (CGRect) -> Void
    private let hint: String
    private let drawsCrosshair: Bool
    private static let transparentCursor = NSCursor(image: NSImage(size: NSSize(width: 16, height: 16)), hotSpot: .zero)
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    init(frame: CGRect, hint: String, drawsCrosshair: Bool, completion: @escaping (CGRect) -> Void) {
        self.completion = completion
        self.hint = hint
        self.drawsCrosshair = drawsCrosshair
        super.init(frame: frame)
        if drawsCrosshair {
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                                           owner: self, userInfo: nil))
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: drawsCrosshair ? Self.transparentCursor : .crosshair)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if drawsCrosshair, let window {
            let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            pointer = bounds.contains(location) ? location : nil
        }
    }

    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) { pointer = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        start = location; current = location; pointer = location; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        current = location; pointer = location; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        if let rect = CaptureGeometry.selection(from: start, to: end, bounds: bounds) { completion(rect) }
        else { self.start = nil; current = nil; needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let shade = NSBezierPath(rect: bounds)
        shade.windingRule = .evenOdd
        var selection: CGRect?
        if let start, let current {
            let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(start.x - current.x), height: abs(start.y - current.y)).intersection(bounds)
            if !rect.isNull { shade.appendRect(rect); selection = rect }
        }
        NSColor.black.withAlphaComponent(0.42).setFill(); shade.fill()
        let accent = NSColor(calibratedRed: 1, green: 0.34, blue: 0.25, alpha: 1)
        if let selection {
            accent.setStroke()
            let border = NSBezierPath(rect: selection); border.lineWidth = 2; border.stroke()
            for point in [CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.maxX, y: selection.minY), CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.maxX, y: selection.maxY)] {
                NSColor.white.setFill(); NSBezierPath(roundedRect: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8), xRadius: 2, yRadius: 2).fill()
            }
            drawPill("\(Int(selection.width)) × \(Int(selection.height))", at: CGPoint(x: selection.midX, y: min(bounds.height - 44, selection.maxY + 12)), font: 13)
        }
        drawPill(hint, at: CGPoint(x: bounds.midX, y: 48), font: 15)
        if drawsCrosshair, let pointer {
            let crosshair = NSBezierPath()
            crosshair.move(to: CGPoint(x: pointer.x - 9, y: pointer.y))
            crosshair.line(to: CGPoint(x: pointer.x + 9, y: pointer.y))
            crosshair.move(to: CGPoint(x: pointer.x, y: pointer.y - 9))
            crosshair.line(to: CGPoint(x: pointer.x, y: pointer.y + 9))
            NSColor.black.setStroke(); crosshair.lineWidth = 3; crosshair.stroke()
            NSColor.white.setStroke(); crosshair.lineWidth = 1; crosshair.stroke()
        }
    }

    private func drawPill(_ text: String, at point: CGPoint, font: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: font, weight: .medium), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        let box = CGRect(x: max(8, min(bounds.width - size.width - 32, point.x - size.width / 2 - 16)), y: point.y, width: size.width + 32, height: size.height + 20)
        NSColor(white: 0.12, alpha: 0.96).setFill(); NSBezierPath(roundedRect: box, xRadius: 12, yRadius: 12).fill()
        (text as NSString).draw(at: CGPoint(x: box.minX + 16, y: box.minY + 10), withAttributes: attributes)
    }
}
