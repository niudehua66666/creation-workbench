import AppKit
import SwiftUI

@MainActor
public final class ScreenshotEditor: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onClose: (() -> Void)?

    public func open(_ url: URL, onClose: (() -> Void)? = nil, onSave: @escaping (URL) -> Void) throws {
        let image = try ScreenshotEdit.load(url)
        window?.close()
        let editorWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 920, height: 650),
                                    styleMask: [.titled, .closable, .resizable, .miniaturizable],
                                    backing: .buffered, defer: false)
        editorWindow.title = "编辑截图"
        editorWindow.minSize = CGSize(width: 640, height: 430)
        editorWindow.isReleasedWhenClosed = false
        editorWindow.delegate = self
        editorWindow.contentView = NSHostingView(rootView: ScreenshotEditorView(
            image: image, url: url, onSave: { [weak editorWindow] saved in
                editorWindow?.close()
                onSave(saved)
            }))
        window = editorWindow
        self.onClose = onClose
        editorWindow.center()
        NSApp.activate(ignoringOtherApps: true)
        editorWindow.makeKeyAndOrderFront(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        guard let closed = notification.object as? NSWindow, closed === window else { return }
        window = nil
        let completion = onClose
        onClose = nil
        completion?()
    }
}

private struct ScreenshotEditorView: View {
    struct EditState {
        var crop: CGRect
        var marks: [ScreenshotMark] = []
    }

    let image: CGImage
    let url: URL
    let onSave: (URL) -> Void
    @State private var tool = ScreenshotMarkStyle.crop
    @State private var edit: EditState
    @State private var history: [EditState] = []
    @State private var drag: ScreenshotMark?
    @State private var cropSelection: CGRect?
    @State private var message = ""

    init(image: CGImage, url: URL, onSave: @escaping (URL) -> Void) {
        self.image = image
        self.url = url
        self.onSave = onSave
        _edit = State(initialValue: EditState(crop: CGRect(x: 0, y: 0, width: image.width, height: image.height)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("编辑工具", selection: $tool) {
                    ForEach(ScreenshotMarkStyle.allCases) { style in
                        Label(style.rawValue, systemImage: style.symbol).tag(style)
                    }
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)
                    .onChange(of: tool) { _, _ in cropSelection = nil; drag = nil }
                Button("应用裁剪", action: applyCrop).disabled(cropSelection == nil)
                    .keyboardShortcut(.return, modifiers: [])
                Spacer()
                Button("撤销", action: undo).disabled(history.isEmpty && cropSelection == nil)
                    .keyboardShortcut("z")
            }
            GeometryReader { geometry in
                let scale = min(geometry.size.width / edit.crop.width, geometry.size.height / edit.crop.height)
                if scale > 0, let bitmap = image.cropping(to: edit.crop) {
                    imageCanvas(bitmap, scale: scale)
                        .frame(width: edit.crop.width * scale, height: edit.crop.height * scale)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(message.isEmpty ? hint : message).font(.callout).lineLimit(2)
                    Text("\(Int(edit.crop.width)) × \(Int(edit.crop.height)) 像素")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("保存副本") { output(copy: false) }
                Button("复制图片") { output(copy: true) }
                    .buttonStyle(.borderedProminent).keyboardShortcut("c")
            }
        }.padding(16)
    }

    private var hint: String {
        switch tool {
        case .crop: "拖出要保留的区域，再点「应用裁剪」。"
        case .rectangle: "拖动矩形框出重点。"
        case .arrow: "从箭尾拖到要标记的位置。"
        case .highlight: "拖出需要高亮的区域。"
        }
    }

    private func imageCanvas(_ bitmap: CGImage, scale: CGFloat) -> some View {
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                          tx: -edit.crop.minX * scale, ty: -edit.crop.minY * scale)
        return ZStack {
            Image(decorative: bitmap, scale: 1).resizable()
            Canvas { context, _ in
                for mark in edit.marks + (drag.map { [$0] } ?? []) {
                    let path = Path(mark.path).applying(transform)
                    if mark.style == .highlight {
                        context.fill(path, with: .color(Color(red: 1, green: 0.8, blue: 0.1).opacity(0.35)))
                    } else if mark.style == .crop {
                        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    } else {
                        let width = max(1.5, max(3, min(10, CGFloat(max(image.width, image.height)) / 320)) * scale)
                        context.stroke(path, with: .color(Color(red: 1, green: 0.26, blue: 0.2)),
                                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
                    }
                }
                if let cropSelection {
                    let path = Path(cropSelection).applying(transform)
                    context.stroke(path, with: .color(.black.opacity(0.65)), lineWidth: 3)
                    context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                }
            }.allowsHitTesting(false)
        }
        .clipped()
        .contentShape(Rectangle())
        .accessibilityLabel("截图编辑画布")
        .gesture(DragGesture(minimumDistance: 3)
            .onChanged { value in
                if tool == .crop { cropSelection = nil }
                drag = makeMark(value, scale: scale)
                message = ""
            }
            .onEnded { value in
                let mark = makeMark(value, scale: scale)
                drag = nil
                let size = mark.bounds.size
                if tool == .arrow {
                    guard hypot(size.width, size.height) > 4 else { return }
                } else {
                    guard size.width > 4, size.height > 4 else { return }
                }
                if tool == .crop {
                    cropSelection = mark.bounds.integral.intersection(edit.crop)
                } else {
                    history.append(edit)
                    edit.marks.append(mark)
                }
            })
    }

    private func makeMark(_ value: DragGesture.Value, scale: CGFloat) -> ScreenshotMark {
        func point(_ value: CGPoint) -> CGPoint {
            CGPoint(x: min(edit.crop.maxX, max(edit.crop.minX, edit.crop.minX + value.x / scale)),
                    y: min(edit.crop.maxY, max(edit.crop.minY, edit.crop.minY + value.y / scale)))
        }
        return ScreenshotMark(style: tool, start: point(value.startLocation), end: point(value.location))
    }

    private func applyCrop() {
        guard let selection = cropSelection, !selection.isEmpty else { return }
        history.append(edit)
        edit.crop = selection
        cropSelection = nil
        message = ""
    }

    private func undo() {
        if cropSelection != nil { cropSelection = nil }
        else if let previous = history.popLast() { edit = previous }
        message = ""
    }

    private func output(copy: Bool) {
        applyCrop()
        do {
            let result = try ScreenshotEdit.render(image, crop: edit.crop, marks: edit.marks)
            if copy {
                try ScreenshotTransfer.copyImage(result)
                message = "已复制编辑后的图片。"
            } else {
                let saved = try ScreenshotEdit.saveCopy(result, beside: url)
                onSave(saved)
            }
        } catch { message = error.localizedDescription }
    }
}
