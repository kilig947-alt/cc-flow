import SwiftUI
import AppKit
import AVFoundation
import ImageIO

/// 灵动岛展开态 Giflow 录制结果列表与控制面板（全岛内原生交互，不依赖外部弹窗）
struct GiflowExpandedView: View {
    @ObservedObject private var store = GiflowStore.shared
    @State private var isShowingSettings = false
    @State private var copiedItemID: String?
    @State private var editingItemID: String?
    @State private var editingName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            headerBar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))

            Divider().opacity(0.4)

            if isShowingSettings {
                settingsInlineView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                mainContentView
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: isShowingSettings)
        .onAppear {
            store.loadRecordings()
        }
    }

    // MARK: - 主内容区 (进度条 + 列表 / 空状态)

    private var mainContentView: some View {
        VStack(spacing: 0) {
            if let error = store.actionError {
                HStack {
                    Label(LocalizedStringKey(error), systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Spacer()
                    Button("common.close") { store.actionError = nil }
                        .buttonStyle(.plain)
                }
                .padding(10)
            }

            if store.isExporting {
                exportingBanner
            }

            if store.recordings.isEmpty {
                emptyState
            } else {
                recordingsList
            }
        }
    }

    // MARK: - 顶部工具栏

    private var headerBar: some View {
        HStack(spacing: 8) {
            if isShowingSettings {
                // 设置界面顶部：返回按钮 + 标题
                Button(action: {
                    withAnimation { isShowingSettings = false }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("features.recordings")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Spacer()

                Text("features.recording_preferences")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                Button(action: {
                    withAnimation { isShowingSettings = false }
                }) {
                    Text("completion.completed")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            } else {
                // 默认列表顶部：应用 Logo + 录制入口 + 设置
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                    Text("Giflow")
                        .font(.system(size: 13, weight: .bold))
                }

                Spacer()

                // 区域录制按钮
                Button(action: { store.triggerSelectionCapture() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "crop")
                            .font(.system(size: 11))
                        Text("features.record_region")
                            .font(.system(size: 11, weight: .medium))
                        Text("⌥5")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.85))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                // 全屏录制按钮
                Button(action: { store.triggerFullScreenCapture() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 11))
                        Text("features.full_screen")
                            .font(.system(size: 11, weight: .medium))
                        Text("⌥6")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.12))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                // 岛内设置切换按钮
                Button(action: {
                    withAnimation { isShowingSettings = true }
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("features.recording_preferences")

                // 打开目录按钮
                Button(action: {
                    store.openSaveDirectory()
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("features.open_save_folder_in_finder")
            }
        }
    }

    // MARK: - 导出进度条

    private var exportingBanner: some View {
        VStack(spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                    Text("features.rendering_media_in_background")
                        .font(.system(size: 11, weight: .medium))
                }
                Spacer()
                Text("\(Int(store.exportProgress * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            ProgressView(value: store.exportProgress, total: 1.0)
                .progressViewStyle(.linear)
                .accentColor(.red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
        .overlay(Divider(), alignment: .bottom)
    }

    // MARK: - 录制列表

    private var recordingsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(store.recordings) { item in
                    recordingRow(for: item)
                }
            }
            .padding(12)
        }
    }

    private func recordingRow(for item: GiflowRecordingItem) -> some View {
        HStack(spacing: 12) {
            // 媒体缩略图 / 动图预览
            MediaThumbnailView(item: item)
                .frame(width: 80, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .contentShape(Rectangle())
                // Keep the drag recognizer away from the row's action buttons.
                .onDrag { NSItemProvider(object: item.fileURL as NSURL) }

            // 信息与名称
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // 格式徽标 (GIF / MP4)
                    Text(item.format.title)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(item.format == .mp4 ? .blue : .purple)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            (item.format == .mp4 ? Color.blue : Color.purple).opacity(0.15)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    if editingItemID == item.id {
                        HStack {
                            TextField("custom_area.name", text: $editingName, onCommit: {
                                store.renameItem(item: item, newName: editingName)
                                editingItemID = nil
                            })
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))

                            Button("common.save") {
                                store.renameItem(item: item, newName: editingName)
                                editingItemID = nil
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                        }
                    } else {
                        Text(item.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .onTapGesture(count: 2) {
                                editingItemID = item.id
                                editingName = item.name
                            }
                    }
                }

                HStack(spacing: 8) {
                    Text(item.formattedDuration)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(item.formattedResolution)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(item.formattedFileSize)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // 快捷操作按钮组
            HStack(spacing: 6) {
                // 如果是 GIF 动图，提供「另存为 MP4」操作（新增独立任务，不覆盖旧项）
                if item.format == .gif {
                    Button(action: {
                        store.convertItemToMP4(item)
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "video.badge.plus")
                                .font(.system(size: 10))
                            Text(appLocalized: store.convertingItemID == item.id ? AppLocalization.runtimeString("features.converting") : AppLocalization.runtimeString("features.save_as_mp4"))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isExporting)
                    .help("features.save_this_gif_as_a_high_quality_mp4")
                }

                // 复制按钮
                Button(action: {
                    guard store.copyMediaToClipboard(item: item) else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        copiedItemID = item.id
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if copiedItemID == item.id {
                                copiedItemID = nil
                            }
                        }
                    }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: copiedItemID == item.id ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(appLocalized: copiedItemID == item.id ? AppLocalization.runtimeString("settings.copied") : AppLocalization.runtimeString("common.copy"))
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(copiedItemID == item.id ? Color.green.opacity(0.2) : Color.white.opacity(0.08))
                    .foregroundColor(copiedItemID == item.id ? .green : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("features.copy_the_file_to_paste_into_wechat_slack")

                // 定位文件
                Button(action: { store.revealInFinder(item: item) }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("features.show_file_in_finder")

                // 删除
                Button(action: { store.deleteItem(item: item) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("common.delete")
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
        )
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.badge.waveform")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.6))

            Text("features.no_recordings_yet")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            Text("features.press_5_to_select_a_screen_region_or")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button(action: { store.triggerSelectionCapture() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "crop")
                        Text("features.record_region_5")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - 灵动岛内原生设置面板 (Inline Settings)

    private var settingsInlineView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 录制参数卡片
                VStack(alignment: .leading, spacing: 12) {
                    Text("features.export_and_quality")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    // 目标帧率
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("features.target_frame_rate")
                                .font(.system(size: 12, weight: .medium))
                            Text("features.higher_frame_rates_produce_smoother_video_and_larger")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Picker("", selection: $store.settings.targetFPS) {
                            Text("features.duration_10_fps_lightweight").tag(10)
                            Text("features.duration_15_fps_recommended").tag(15)
                            Text("features.duration_20_fps_smooth").tag(20)
                            Text("features.duration_24_fps_high_frame_rate").tag(24)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }

                    Divider().opacity(0.3)

                    // 分辨率缩放
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("features.resolution")
                                .font(.system(size: 12, weight: .medium))
                            Text("features.standard_resolution_creates_smaller_files_retina_preserves_more")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Picker("", selection: $store.settings.maxScaleFactor) {
                            Text("features.duration_1_0x_standard").tag(1.0)
                            Text("features.duration_2_0x_retina").tag(2.0)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.35))
                )

                // 交互特效卡片
                VStack(alignment: .leading, spacing: 12) {
                    Text("features.effects_and_hud")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    // 鼠标点击红点涟漪开关
                    Toggle(isOn: $store.settings.showClickRipple) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("features.mouse_click_dots_and_ripple_animations")
                                .font(.system(size: 12, weight: .medium))
                            Text("features.highlight_left_clicks_in_red_and_right_clicks")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    Divider().opacity(0.3)

                    // 键盘 HUD 开关
                    Toggle(isOn: $store.settings.showKeycast) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("features.keyboard_overlay_keycast")
                                .font(.system(size: 12, weight: .medium))
                            Text("features.show_current_key_combinations_at_the_bottom_center")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.35))
                )

                // 快捷键速查卡片
                VStack(alignment: .leading, spacing: 10) {
                    Text("features.global_shortcuts")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    HStack {
                        Text("features.record_region")
                            .font(.system(size: 11))
                        Spacer()
                        Text("⌥ + 5")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    HStack {
                        Text("features.record_full_screen")
                            .font(.system(size: 11))
                        Spacer()
                        Text("⌥ + 6")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    HStack {
                        Text("features.open_recordings")
                            .font(.system(size: 11))
                        Spacer()
                        Text("⌥ + 7")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.2))
                )
            }
            .padding(14)
        }
    }
}

// MARK: - 媒体缩略图组件 (GIF 动图与 MP4 视频帧预览)

private struct MediaThumbnailView: View {
    let item: GiflowRecordingItem
    @State private var mp4Thumbnail: NSImage?
    @State private var isHovering = false

    var body: some View {
        Group {
            if item.format == .mp4 {
                ZStack {
                    if let image = mp4Thumbnail {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Color.black.opacity(0.6)
                    }

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.85))
                        .shadow(radius: 2)
                }
                .onAppear {
                    loadMP4Thumbnail()
                }
            } else {
                GifImageView(url: item.fileURL, isPlaying: isHovering)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onDisappear { isHovering = false }
    }

    private func loadMP4Thumbnail() {
        Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: item.fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 160, height: 100)
            if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                await MainActor.run {
                    self.mp4Thumbnail = nsImage
                }
            }
        }
    }
}

// MARK: - GIF 动图播放视图 (AppKit NSImageView 原生播放)

/// The native image can extend beyond SwiftUI's clipped thumbnail bounds. It is
/// decorative: leave all mouse handling (including dragging) to the SwiftUI host.
private final class GiflowThumbnailImageView: NSImageView {
    var loadedURL: URL?
    var firstFrame: NSImage?
    var isPlaying = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct GifImageView: NSViewRepresentable {
    let url: URL
    var isPlaying = false

    func makeNSView(context: Context) -> NSImageView {
        makeImageView()
    }

    func makeImageView() -> NSImageView {
        let iv = GiflowThumbnailImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.animates = false
        loadImage(into: iv)
        return iv
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        loadImage(into: nsView)
    }

    func loadImage(into iv: NSImageView) {
        guard let thumbnail = iv as? GiflowThumbnailImageView else { return }
        if thumbnail.loadedURL != url {
            thumbnail.animates = false
            thumbnail.isPlaying = false
            thumbnail.loadedURL = url
            thumbnail.firstFrame = Self.loadFirstFrame(url: url)
            thumbnail.image = thumbnail.firstFrame
        }
        // Preserve playback across unrelated parent updates. Loading an animated
        // representation is deferred until hover; idle rows hold only a small bitmap.
        guard thumbnail.isPlaying != isPlaying else { return }
        thumbnail.isPlaying = isPlaying
        thumbnail.animates = false
        thumbnail.image = isPlaying ? NSImage(contentsOf: url) : thumbnail.firstFrame
        thumbnail.animates = isPlaying
    }

    static func dismantleNSView(_ nsView: NSImageView, coordinator: ()) {
        nsView.animates = false
        nsView.image = nil
    }

    private static func loadFirstFrame(url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
    }
}
