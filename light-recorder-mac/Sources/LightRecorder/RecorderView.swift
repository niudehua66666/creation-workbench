import SwiftUI
import AppKit
import AVFoundation
import RecorderCore

private let ink = Color(red: 0.14, green: 0.16, blue: 0.19)
private let accent = Color(red: 0.94, green: 0.29, blue: 0.21)
private let secondaryInk = Color(red: 0.47, green: 0.49, blue: 0.52)
private let line = Color.black.opacity(0.07)

struct RecorderView: View {
    @ObservedObject var model: RecorderModel

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    if !model.screenPermission { permissionCard }
                    if let error = model.errorMessage { errorCard(error) }
                    settings
                    recentSection
                }.padding(.horizontal, 28).padding(.top, 4).padding(.bottom, 24)
            }
            footer
        }
        .foregroundStyle(ink)
        .background(Color(red: 0.975, green: 0.975, blue: 0.967))
        .environment(\.colorScheme, .light)
        .frame(minWidth: 640, minHeight: 670)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(accent).frame(width: 45, height: 45)
                Image(systemName: "record.circle").font(.system(size: 27, weight: .medium)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("截录暂存").font(.system(size: 24, weight: .bold))
                Text("选好范围，轻轻一录。").font(.system(size: 12)).foregroundStyle(secondaryInk)
            }
            Spacer()
            Button { model.screenshotAction() } label: {
                Label("区域截图", systemImage: "camera.viewfinder")
            }.controlSize(.small).disabled(!model.canStartScreenshot).help("区域截图  ⌃⌘4")
            VStack(alignment: .trailing, spacing: 4) {
                Text("F3").font(.system(size: 13, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 10).padding(.vertical, 6).background(.white, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(line))
                Text("开始 / 停止").font(.system(size: 10)).foregroundStyle(secondaryInk)
            }
        }.padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 26)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("录制范围", trailing: "01")
            HStack(spacing: 10) {
                ForEach(CaptureMode.allCases) { mode in
                    Button { model.mode = mode } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: mode.icon).font(.system(size: 22, weight: .regular))
                                Spacer()
                                if model.mode == mode { Image(systemName: "checkmark.circle.fill").font(.system(size: 15)) }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.rawValue).font(.system(size: 14, weight: .semibold))
                                Text(mode.detail).font(.system(size: 10)).foregroundStyle(secondaryInk)
                            }
                        }.padding(15).frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(model.mode == mode ? accent : ink)
                            .background(model.mode == mode ? accent.opacity(0.055) : .white, in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(model.mode == mode ? accent.opacity(0.65) : line, lineWidth: model.mode == mode ? 1.5 : 1))
                    }.buttonStyle(.plain)
                }
            }
            targetPicker
            sectionLabel("录入声音", trailing: "02").padding(.top, 6)
            HStack(spacing: 10) {
                audioToggle("系统声音", subtitle: "视频、音乐和应用声音", icon: "speaker.wave.2", value: $model.systemAudio)
                audioToggle("麦克风", subtitle: "同时录下你的讲解", icon: "mic", value: $model.microphone)
            }
            HStack(spacing: 15) {
                Picker("画质", selection: $model.maximumEdge) {
                    Text("高清").tag(1920)
                    Text("超清 4K").tag(3840)
                }.frame(width: 150).help("高清最长边 1920 像素，超清最长边 3840 像素；不会放大原画面。")
                Picker("帧率", selection: $model.fps) {
                    Text("30 fps").tag(30); Text("60 fps").tag(60)
                }.frame(width: 132)
                Spacer(minLength: 0)
                Toggle("鼠标", isOn: $model.showsCursor).toggleStyle(.checkbox)
                    .help("关闭后，整段录屏都不会录入鼠标指针。")
                Toggle("倒计时", isOn: $model.countdownEnabled).toggleStyle(.checkbox)
            }.font(.system(size: 11)).padding(.top, 2)
            Toggle("用 ⌘⇧4 调用轻录截图", isOn: $model.useShiftCommand4)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .help("启用前，请在系统设置的键盘快捷键中改键或关闭系统的 ⌘⇧4。")
            if let issue = model.screenshotShortcutIssue {
                Text(issue).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.disabled(model.phase.isBusy)
    }

    private var targetPicker: some View {
        HStack(spacing: 9) {
            Image(systemName: model.mode == .region ? "arrow.up.left.and.arrow.down.right" : "scope").font(.system(size: 13)).foregroundStyle(secondaryInk)
            switch model.mode {
            case .region:
                Text(model.regionDescription).font(.system(size: 12)).foregroundStyle(secondaryInk)
                Spacer()
                if model.region != nil {
                    Button("重新框选") { model.selectRegion(andStart: false) }.buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 12, weight: .medium))
                } else {
                    Text("松开鼠标后倒计时").font(.system(size: 10)).foregroundStyle(secondaryInk)
                        .opacity(model.countdownEnabled ? 1 : 0)
                }
            case .display:
                Picker("选择屏幕", selection: $model.selectedDisplayID) {
                    if model.displays.isEmpty { Text("授权后显示屏幕").tag(UInt32(0)) }
                    ForEach(model.displays, id: \.displayID) { display in Text(model.displayName(display)).tag(display.displayID) }
                }.labelsHidden()
            case .window:
                Picker("选择窗口", selection: $model.selectedWindowID) {
                    if model.windows.isEmpty { Text(model.screenPermission ? "没有可用窗口" : "授权后显示窗口").tag(UInt32(0)) }
                    ForEach(model.windows, id: \.windowID) { window in Text(model.windowName(window)).tag(window.windowID) }
                }.labelsHidden()
            }
            if model.mode != .region {
                Spacer(minLength: 0)
                Button { Task { await model.refreshSources() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("刷新屏幕和窗口").disabled(model.loadingSources)
            }
        }.frame(height: 22).padding(.horizontal, 2)
    }

    private func audioToggle(_ title: String, subtitle: String, icon: String, value: Binding<Bool>) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(value.wrappedValue ? ink : secondaryInk).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(secondaryInk)
            }
            Spacer(minLength: 2)
            Toggle(title, isOn: value).labelsHidden().toggleStyle(.switch).controlSize(.mini).tint(accent)
        }.padding(13).frame(maxWidth: .infinity).background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(line))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("最近录制", trailing: "自动保存到本机")
            if let latest = model.recent.first {
                HStack(spacing: 13) {
                    RecordingThumbnail(url: latest.url).frame(width: 108, height: 65).clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { model.showReview?(latest) }
                        .onDrag { NSItemProvider(contentsOf: latest.url) ?? NSItemProvider(object: latest.url as NSURL) }
                        .help("拖到聊天或文件夹，也可点击播放")
                    VStack(alignment: .leading, spacing: 7) {
                        Text(latest.url.deletingPathExtension().lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(latest.detail).font(.system(size: 10)).foregroundStyle(secondaryInk)
                        HStack(spacing: 14) {
                            Button("回看 / 裁剪") { model.showReview?(latest) }
                            Button(model.copied ? "已复制" : "复制文件") { model.copy(latest.url) }
                            Button("在访达显示") { model.reveal(latest.url) }
                        }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                    }
                    Spacer(minLength: 0)
                    if model.recent.count > 1 {
                        Menu {
                            ForEach(model.recent.dropFirst()) { recording in
                                Button(recording.url.lastPathComponent) { model.showReview?(recording) }
                            }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
                    }
                }.padding(13).background(.white, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(line))
            } else {
                HStack(spacing: 13) {
                    Image(systemName: "play.rectangle").font(.system(size: 27, weight: .ultraLight)).foregroundStyle(secondaryInk.opacity(0.7))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("录完就出现在这里").font(.system(size: 12, weight: .medium))
                        Text("直接播放，或把视频拖到聊天和文件夹。").font(.system(size: 11)).foregroundStyle(secondaryInk)
                    }
                    Spacer()
                    Text("MP4").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(secondaryInk)
                }.padding(18).frame(maxWidth: .infinity).background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "folder").font(.system(size: 11))
                Text("保存到").font(.system(size: 11))
                Text(model.outputDirectory.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Button("更改") { model.chooseDirectory() }.buttonStyle(.plain).font(.system(size: 11)).disabled(model.phase.isBusy)
            }.foregroundStyle(secondaryInk)
            Button { model.primaryAction() } label: {
                HStack(spacing: 9) {
                    if model.phase == .preparing || model.phase == .finishing { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: model.phase == .recording ? "stop.fill" : "record.circle").font(.system(size: 19)) }
                    Text(actionTitle).font(.system(size: 15, weight: .semibold))
                }.frame(maxWidth: .infinity).frame(height: 48)
                    .foregroundStyle(.white).background(accent, in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).disabled(model.phase == .preparing || model.phase == .finishing || model.loadingSources || (model.phase == .idle && model.screenshotBusy))
            Text(model.phase == .recording ? "⌃⌘4 区域截图 · F3 停止录屏" : "视频自动保存 · 暂存栏和截图框不会录进画面")
                .font(.system(size: 10)).foregroundStyle(secondaryInk)
        }.padding(.horizontal, 28).padding(.top, 17).padding(.bottom, 19)
            .background(.white.opacity(0.7)).overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) }
    }

    private var actionTitle: String {
        switch model.phase {
        case .idle: model.screenPermission ? model.startTitle : "允许屏幕录制"
        case .selecting: "正在框选 · Esc 取消"
        case .countdown(let count): "\(count) 秒后开始 · 点击取消"
        case .preparing: "正在准备录制…"
        case .recording: "停止并保存  \(durationLabel(model.elapsed))"
        case .finishing: "正在保存视频…"
        }
    }

    private var permissionCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "rectangle.dashed.badge.record").font(.system(size: 19)).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 6) {
                Text("第一次使用，允许录制屏幕").font(.system(size: 12, weight: .semibold))
                Text("点击下方按钮授权；若已打开权限，回到轻录即可。系统要求时退出并重新打开。")
                    .font(.system(size: 11)).foregroundStyle(secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("系统设置") { model.openScreenSettings() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(accent)
        }.padding(13).background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorCard(_ error: String) -> some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.circle")
            Text(error).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }.foregroundStyle(Color(red: 0.68, green: 0.28, blue: 0.08)).padding(12)
            .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sectionLabel(_ text: String, trailing: String) -> some View {
        HStack {
            Text(text).font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(trailing).font(.system(size: 10, design: .monospaced)).foregroundStyle(secondaryInk.opacity(0.8))
        }
    }
}

private struct RecordingThumbnail: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        ZStack {
            Color.black.opacity(0.06)
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            Image(systemName: "play.circle.fill").font(.system(size: 25)).foregroundStyle(.white).shadow(radius: 3)
        }.clipped().task(id: url) {
            image = nil
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 180)
            if let result = try? await generator.image(at: .zero) { image = NSImage(cgImage: result.image, size: .zero) }
        }
    }
}
