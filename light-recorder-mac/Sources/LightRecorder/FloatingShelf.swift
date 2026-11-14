import AppKit
import Combine
import QuickLookThumbnailing
import RecorderCore
import SwiftUI

@MainActor
final class FloatingShelf {
    private let model: RecorderModel
    private let openSettings: () -> Void
    private let panel: ShelfPanel
    private let hasUnreadResult = CurrentValueSubject<Bool, Never>(false)
    private var presentation = ShelfPresentation() {
        didSet {
            // Selection belongs to one open shelf session. Ignore layout updates
            // and new captures while the shelf is already expanded.
            if oldValue.appearance != presentation.appearance,
               oldValue.appearance == .expanded || presentation.appearance == .expanded {
                model.clearMediaSelection(resetMessage: false)
            }
        }
    }
    private var anchor: CGPoint?
    private var displayID: UInt32?
    private var preferredEdge: ShelfPlacement.Side = .right
    private var drag: (gesture: ShelfDrag, panelOrigin: CGPoint)?
    private var editingScreenshot = false
    private var pendingCapturePreview = false

    init(model: RecorderModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        panel = ShelfPanel(contentRect: CGRect(x: 0, y: 0, width: 52, height: 52),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    var isVisible: Bool { presentation.appearance != .hidden }

    func setCaptureActive(_ active: Bool) {
        let previous = presentation.appearance
        presentation.setCaptureActive(active)
        if presentation.appearance != previous { render() }
    }

    private func expand() {
        let previous = presentation.appearance
        presentation.open()
        guard presentation.appearance != previous else { return }
        hasUnreadResult.send(false)
        render()
    }

    func dismiss() {
        presentation.dismiss()
        if !isVisible { hasUnreadResult.send(false) }
        render()
    }

    private func collapse() {
        guard presentation.appearance == .expanded else { return }
        presentation.collapse(to: preferredEdge)
        hasUnreadResult.send(false)
        render()
    }

    func showShelf() {
        // An explicit open request starts fresh even if the panel is already visible.
        model.clearMediaSelection(resetMessage: false)
        presentation.showShelf()
        hasUnreadResult.send(false)
        render()
    }

    func previewCapture() {
        if drag != nil {
            pendingCapturePreview = true
            return
        }
        let previous = presentation.appearance
        presentation.showShelf()
        if previous != presentation.appearance { render() }
        else if !editingScreenshot, NSApp.isHidden || !panel.isVisible { orderPanelFront() }
        hasUnreadResult.send(false)
    }

    func showScreenshotFailure() {
        presentation.recordResult()
        if presentation.appearance != .expanded { hasUnreadResult.send(true) }
    }

    func screenLayoutChanged() {
        guard drag == nil else { return }
        if !NSScreen.screens.contains(where: { id(for: $0) == displayID }) { anchor = nil }
        if isVisible { render() }
    }

    func setEditingScreenshot(_ editing: Bool) {
        editingScreenshot = editing
        if editing { panel.orderOut(nil) }
        else { render() }
    }

    private func render() {
        drag = nil
        guard isVisible else {
            panel.orderOut(nil)
            panel.contentView = nil
            return
        }
        guard !editingScreenshot else { return }
        let screen = NSScreen.screens.first { id(for: $0) == displayID } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        displayID = id(for: screen)
        let visible = screen.visibleFrame
        let position = anchor ?? CGPoint(x: visible.maxX - 44, y: visible.midY + 46)
        anchor = position

        let root: AnyView
        let size: CGSize
        let edge: ShelfPlacement.Side?
        switch presentation.appearance {
        case .hidden: return
        case .ball:
            edge = nil
            size = CGSize(width: 52, height: 52)
            root = AnyView(ShelfBall(model: model, hasUnreadResult: hasUnreadResult, handle: handle("打开暂存栏", click: { [weak self] in self?.expand() })))
        case .expanded:
            edge = nil
            size = CGSize(width: min(368, visible.width - 12), height: min(650, visible.height - 18))
            root = AnyView(ShelfContents(model: model, handle: handle("拖动暂存栏，拖到屏幕边缘可隐藏"),
                                         collapse: { [weak self] in self?.collapse() },
                                         settings: openSettings).frame(width: size.width, height: size.height))
        case .edge(let side):
            edge = side
            size = CGSize(width: 20, height: 66)
            root = AnyView(ShelfTab(model: model, hasUnreadResult: hasUnreadResult, side: side, handle: handle("打开暂存栏，拖回屏内恢复浮球", click: { [weak self] in self?.expand() })))
        }

        let frame = ShelfPlacement.frame(size: size, near: position, in: visible, edge: edge)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.setFrame(frame, display: false)
        panel.contentView = host
        orderPanelFront()
    }

    private func orderPanelFront() {
        // LaunchServices' hidden launch can suppress even a nonactivating panel.
        // Wait for a visible shelf state before unhiding, and leave focus alone.
        if NSApp.isHidden { NSApp.unhideWithoutActivation() }
        panel.orderFrontRegardless()
    }

    private func id(for screen: NSScreen) -> UInt32? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func handle(_ label: String, click: (() -> Void)? = nil) -> ShelfHandle {
        ShelfHandle(label: label, click: click, started: { [weak self] point in
            guard let self else { return }
            self.drag = (ShelfDrag(start: point), self.panel.frame.origin)
        }, moved: { [weak self] point in _ = self?.move(to: point) },
        ended: { [weak self] point in
            guard let self, self.drag != nil else { return }
            let moved = self.move(to: point)
            self.drag = nil
            if moved { self.drop(at: point) }
            else { click?() }
            if self.pendingCapturePreview {
                self.pendingCapturePreview = false
                self.previewCapture()
            }
        })
    }

    private func move(to point: CGPoint) -> Bool {
        guard let offset = drag?.gesture.translation(to: point), let origin = drag?.panelOrigin else { return false }
        panel.setFrameOrigin(CGPoint(x: origin.x + offset.x, y: origin.y + offset.y))
        return true
    }

    private func drop(at point: CGPoint) {
        let frame = panel.frame
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) })
                  ?? NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) })
                  ?? NSScreen.main else { return }
        displayID = id(for: screen)
        let visible = screen.visibleFrame
        // The mouse on the grip can reach the physical edge even if the Dock uses that edge.
        let edge = ShelfPlacement.edge(at: point, in: screen.frame)
        switch edge {
        case .some(let side):
            preferredEdge = side
            anchor = CGPoint(x: side == .left ? visible.minX + 46 : visible.maxX - 46, y: frame.midY)
        case nil:
            anchor = CGPoint(x: frame.midX, y: frame.midY)
        }
        presentation.drop(at: edge)
        render()
    }
}

private final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private let panelColor = Color(red: 0.11, green: 0.12, blue: 0.15)
private let signal = Color(red: 1, green: 0.38, blue: 0.31)
private let mint = Color(red: 0.57, green: 0.89, blue: 0.77)

private struct ShelfBall: View {
    @ObservedObject var model: RecorderModel
    let hasUnreadResult: CurrentValueSubject<Bool, Never>
    let handle: ShelfHandle
    @State private var unread = false
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle().fill(panelColor)
            Circle().strokeBorder(.white.opacity(0.18))
            Image(systemName: model.phase == .recording ? "record.circle.fill" : "viewfinder")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(model.phase == .recording ? signal : mint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.screenshotBusy || model.phase == .preparing || model.phase == .finishing {
                ProgressView().controlSize(.mini).padding(4)
            } else if case .countdown(let count) = model.phase {
                Text("\(count)").font(.caption2.bold()).foregroundStyle(.white)
                    .padding(4).background(signal, in: Circle())
            } else if unread {
                Circle().fill(mint).frame(width: 8, height: 8).padding(4)
            }
            handle
        }.frame(width: 52, height: 52).onReceive(hasUnreadResult) { unread = $0 }
    }
}

private struct ShelfTab: View {
    @ObservedObject var model: RecorderModel
    let hasUnreadResult: CurrentValueSubject<Bool, Never>
    let side: ShelfPlacement.Side
    let handle: ShelfHandle
    @State private var unread = false
    var body: some View {
        ZStack {
            Capsule().fill(panelColor).overlay { Capsule().strokeBorder(.white.opacity(0.2)) }
            Image(systemName: side == .left ? "chevron.right" : "chevron.left")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(model.phase == .recording ? signal : mint)
            if unread {
                Circle().fill(mint).frame(width: 5, height: 5).offset(y: -19)
            }
            handle
        }.frame(width: 20, height: 66).onReceive(hasUnreadResult) { unread = $0 }
    }
}

private struct ShelfContents: View {
    @ObservedObject var model: RecorderModel
    let handle: ShelfHandle
    let collapse: () -> Void
    let settings: () -> Void

    var body: some View {
        let urls = model.selectedMediaURLs
        VStack(spacing: 0) {
            header
            actions.padding(.horizontal, 13).padding(.bottom, 11)
            Divider().overlay(.white.opacity(0.08))
            ScreenshotShelfSection(model: model)
            Divider().overlay(.white.opacity(0.08))
            ShelfMediaSection(title: "录屏", symbol: "film", emptyMessage: "还没有录屏", items: model.recent, id: \.id) { recording in
                let review = { model.showReview?(recording) }
                ShelfMediaRow(url: recording.url, detail: recording.detail, actionTitle: "回看", actionSymbol: "play.circle",
                              model: model, isVideo: true, open: { review() }, action: { review() })
            }
            Divider().overlay(.white.opacity(0.08))
            footer(urls)
        }
        .foregroundStyle(.white)
        .background(panelColor, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.13)).allowsHitTesting(false) }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                Text("截录暂存").font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 6)
                if model.phase == .recording {
                    Text(durationLabel(model.elapsed)).font(.caption.monospacedDigit()).foregroundStyle(signal)
                }
            }
            .frame(maxWidth: .infinity)
            .overlay { handle }
            Button(action: settings) { Image(systemName: "gearshape").frame(width: 25, height: 25) }
                .buttonStyle(.plain).help("录制设置").accessibilityLabel("录制设置")
            Button(action: collapse) { Image(systemName: "xmark").frame(width: 25, height: 25) }
                .buttonStyle(.plain).help("收起到屏幕边缘").accessibilityLabel("收起到屏幕边缘")
        }.padding(.horizontal, 13).padding(.vertical, 11)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { model.primaryAction() } label: {
                Label(recordLabel, systemImage: model.phase == .recording ? "stop.fill" : "record.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .foregroundStyle(model.phase == .recording ? .white : signal)
                    .background(model.phase == .recording ? signal.opacity(0.8) : signal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(model.phase == .preparing || model.phase == .finishing || (model.screenshotBusy && model.phase == .idle))
            Button { model.screenshotAction() } label: {
                Label(model.screenshotBusy ? "截图中…" : "区域截图", systemImage: "camera.viewfinder")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .foregroundStyle(mint)
                    .background(mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }.buttonStyle(.plain).disabled(!model.canStartScreenshot).help("区域截图  ⌃⌘4")
        }
    }

    private var recordLabel: String {
        switch model.phase {
        case .idle: "录屏"
        case .recording: "停止录屏"
        case .countdown(let count): "取消 · \(count) 秒"
        case .selecting: "取消框选"
        case .preparing: "准备录制…"
        case .finishing: "保存视频…"
        }
    }

    private func footer(_ urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(model.shelfMessage ?? (urls.isEmpty ? "拖动缩略图取单个文件，勾选后可一起拖出" : "已选 \(urls.count) 个文件"))
                    .lineLimit(2).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if !urls.isEmpty {
                    Button("清空") { model.clearMediaSelection() }.buttonStyle(.plain).font(.caption)
                }
            }
            HStack(spacing: 8) {
                Label("一起拖出", systemImage: "hand.draw").font(.system(size: 11, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 29)
                    .foregroundStyle(urls.isEmpty ? Color.secondary : mint)
                    .background(mint.opacity(urls.isEmpty ? 0.06 : 0.14), in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        if !urls.isEmpty { ShelfFileDrag(urls: urls, model: model, onAccepted: collapse) }
                    }
                    .help("按住这里拖到聊天输入框或文件夹")
                Button { model.copySelectedMedia() } label: { Label("复制", systemImage: "document.on.document") }
                    .disabled(urls.isEmpty).help("复制所选文件")
                if urls.isEmpty {
                    Button {} label: { Label("分享", systemImage: "square.and.arrow.up") }.disabled(true)
                } else {
                    ShareLink(items: urls) { Label("分享", systemImage: "square.and.arrow.up") }
                }
            }.font(.system(size: 11))
        }.padding(13)
    }
}

private struct ScreenshotShelfSection: View {
    @ObservedObject var model: RecorderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Label("截图", systemImage: "photo")
                    .font(.system(size: 12, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 2)
                if let url = model.focusedScreenshot {
                    Button { model.copyScreenshot(url) } label: { Image(systemName: "doc.on.doc") }
                        .help("复制图片").accessibilityLabel("复制当前截图")
                    Button { model.toggleScreenshotPin(url) } label: {
                        Image(systemName: model.pinnedScreenshots.contains(url) ? "pin.fill" : "pin")
                    }.help(model.pinnedScreenshots.contains(url) ? "取消固定截图" : "固定截图")
                        .accessibilityLabel(model.pinnedScreenshots.contains(url) ? "取消固定截图" : "固定截图")
                    Button { model.editScreenshot(url) } label: { Label("编辑", systemImage: "pencil") }
                        .help("裁剪、箭头和高亮").accessibilityLabel("编辑当前截图")
                }
            }.buttonStyle(.plain)
            if let url = model.focusedScreenshot {
                ShelfThumbnail(url: url, isVideo: false, size: nil)
                    .overlay { ShelfFileDrag(urls: [url], model: model, click: { model.open(url) }) }
                    .id(url)
                    .frame(minHeight: 48, maxHeight: 178)
                    .help("直接拖出当前截图，单击打开原图")
                Text(url.lastPathComponent).font(.system(size: 10)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 6) {
                            ForEach(model.screenshots, id: \.self) { imageURL in thumbnail(imageURL).id(imageURL) }
                        }
                        // The horizontal scroller can overlay the scroll content.
                        .padding(.top, 2)
                        .padding(.bottom, 16)
                    }
                    .frame(height: 88)
                    .onChange(of: url, initial: true) { _, focused in proxy.scrollTo(focused) }
                }
            } else {
                Text(model.systemScreenshotIssue ?? "系统截屏或区域截图会显示在这里")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.padding(.horizontal, 13).padding(.vertical, 8)
    }

    private func thumbnail(_ url: URL) -> some View {
        let selected = model.selectedMedia.contains(url)
        return VStack(spacing: 4) {
            ShelfThumbnail(url: url, isVideo: false, size: CGSize(width: 62, height: 39))
                .overlay {
                    ShelfFileDrag(urls: [url], model: model, click: { model.focusScreenshot(url) })
                        .accessibilityLabel("预览或拖出 \(url.lastPathComponent)")
                }
                .overlay {
                    if model.focusedScreenshot == url {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(mint, lineWidth: 2).allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if model.pinnedScreenshots.contains(url) {
                        Image(systemName: "pin.fill").font(.system(size: 8))
                            .padding(4).background(panelColor, in: Circle()).padding(3)
                            .allowsHitTesting(false)
                    }
                }
            Button { model.toggleMedia(url) } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selected ? mint : .white.opacity(0.9))
                    .frame(width: 62, height: 27)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel(selected ? "取消勾选 \(url.lastPathComponent)" : "勾选 \(url.lastPathComponent)")
        }
    }
}

private struct ShelfMediaSection<Item, Row: View>: View {
    let title: String
    let symbol: String
    let emptyMessage: String
    let items: [Item]
    let id: KeyPath<Item, URL>
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 13)
            if items.isEmpty {
                Text(emptyMessage).font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(items, id: id, content: row)
                    }.padding(.horizontal, 9)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity)
    }
}

private struct ShelfMediaRow: View {
    let url: URL
    let detail: String
    let actionTitle: String
    let actionSymbol: String
    @ObservedObject var model: RecorderModel
    var isVideo = false
    let open: () -> Void
    let action: () -> Void

    var body: some View {
        let isSelected = model.selectedMedia.contains(url)
        return HStack(spacing: 8) {
            Button { model.toggleMedia(url) } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16)).frame(width: 27, height: 34)
                    .foregroundStyle(isSelected ? mint : .secondary)
            }.buttonStyle(.plain).accessibilityLabel(isSelected ? "取消勾选 \(url.lastPathComponent)" : "勾选 \(url.lastPathComponent)")
            ShelfThumbnail(url: url, isVideo: isVideo)
                .overlay { ShelfFileDrag(urls: [url], model: model, click: open) }
                .help(isVideo ? "拖动导出这段录屏，单击回看" : "拖动导出这张截图，单击预览")
            Button(action: open) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button(action: action) {
                Label(actionTitle, systemImage: actionSymbol).font(.system(size: 11, weight: .medium))
            }.help(isVideo ? "回看或裁剪录屏" : "编辑截图：裁剪、箭头、高亮")
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(isSelected ? mint.opacity(0.1) : .white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ShelfThumbnail: View {
    let url: URL
    let isVideo: Bool
    var size: CGSize? = CGSize(width: 48, height: 32)
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
            if let thumbnail { Image(nsImage: thumbnail).resizable().scaledToFit() }
            else { Image(systemName: isVideo ? "film" : "photo").font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .frame(width: size?.width, height: size?.height)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: size ?? CGSize(width: 352, height: 200), scale: 2, representationTypes: .thumbnail)
            if let image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request), !Task.isCancelled {
                thumbnail = image.nsImage
            }
        }
    }
}

private struct ShelfHandle: NSViewRepresentable {
    let label: String
    let click: (() -> Void)?
    let started: (CGPoint) -> Void
    let moved: (CGPoint) -> Void
    let ended: (CGPoint) -> Void

    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ view: HandleView, context: Context) {
        view.click = click; view.started = started; view.moved = moved; view.ended = ended
        view.toolTip = label
        view.setAccessibilityElement(true)
        view.setAccessibilityLabel(label)
        view.setAccessibilityRole(click == nil ? .group : .button)
    }

    final class HandleView: NSView {
        var click: (() -> Void)?
        var started: ((CGPoint) -> Void)?
        var moved: ((CGPoint) -> Void)?
        var ended: ((CGPoint) -> Void)?
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        private func screenLocation(of event: NSEvent) -> CGPoint {
            if let cgEvent = event.cgEvent { return cgEvent.unflippedLocation }
            return window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
        }

        override func mouseDown(with event: NSEvent) { started?(screenLocation(of: event)) }
        override func mouseDragged(with event: NSEvent) { moved?(screenLocation(of: event)) }
        override func mouseUp(with event: NSEvent) { ended?(screenLocation(of: event)) }
        override func accessibilityPerformPress() -> Bool {
            guard let click else { return false }; click(); return true
        }
    }
}

private struct ShelfFileDrag: NSViewRepresentable {
    let urls: [URL]
    let model: RecorderModel
    var click: (() -> Void)? = nil
    var onAccepted: (() -> Void)? = nil

    func makeNSView(context: Context) -> DragView { DragView() }

    func updateNSView(_ view: DragView, context: Context) {
        view.urls = urls
        view.click = click
        view.onAccepted = onAccepted
        view.model = model
        view.setAccessibilityElement(click != nil)
        view.setAccessibilityRole(.button)
        view.setAccessibilityLabel(urls.first?.lastPathComponent)
        view.setAccessibilityHelp("按住拖出文件")
    }

    @MainActor
    final class DragView: NSView, NSDraggingSource {
        var urls: [URL] = []
        weak var model: RecorderModel?
        var click: (() -> Void)?
        var onAccepted: (() -> Void)?
        private var activeDrag: (id: UUID, gesture: ShelfDrag, click: (() -> Void)?, onAccepted: (() -> Void)?)?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        override func accessibilityPerformPress() -> Bool {
            guard let click else { return false }
            click()
            return true
        }

        override func mouseDown(with event: NSEvent) {
            guard activeDrag == nil else { return }
            let point = convert(event.locationInWindow, from: nil)
            let items = MediaFileTransfer.pasteboardItems(for: urls).enumerated().map { index, writer in
                let item = NSDraggingItem(pasteboardWriter: writer)
                let offset = CGFloat(min(index, 3)) * 4
                item.setDraggingFrame(CGRect(x: point.x - 20 + offset, y: point.y - 20 - offset, width: 40, height: 40),
                                      contents: NSWorkspace.shared.icon(forFile: writer.path ?? ""))
                return item
            }
            guard !items.isEmpty else {
                model?.mediaDragCompleted(accepted: false)
                return
            }
            let id = UUID()
            let start = window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            activeDrag = (id, ShelfDrag(start: start), click, onAccepted)
            model?.mediaDragStarted(id)
            // As in the original screenshot shelf, AppKit owns the entire mouse sequence.
            let session = beginDraggingSession(with: items, event: event, source: self)
            session.draggingFormation = .stack
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

        func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
            _ = activeDrag?.gesture.translation(to: screenPoint)
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            guard var drag = activeDrag else { return }
            activeDrag = nil
            let moved = drag.gesture.translation(to: screenPoint) != nil
            let wasClick = !moved && operation.isEmpty
            if !operation.isEmpty, let onAccepted = drag.onAccepted {
                // Collapse after AppKit finishes the callback, then import any
                // screenshots that arrived during the drag so they can reopen the shelf.
                DispatchQueue.main.async { [weak model] in
                    onAccepted()
                    model?.mediaDragCompleted(drag.id, accepted: true)
                }
            } else {
                model?.mediaDragCompleted(drag.id, accepted: wasClick ? nil : !operation.isEmpty)
                if wasClick { drag.click?() }
            }
        }
    }
}
