import SwiftUI
import AppKit
import AVFoundation

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
                        Text("录制列表")
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

                Text("录制偏好设置")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                Button(action: {
                    withAnimation { isShowingSettings = false }
                }) {
                    Text("完成")
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
                        Text("选区录制")
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
                        Text("全屏")
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
                .help("录制偏好设置")

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
                .help("在访达中打开保存文件夹")
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
                    Text("正在后台合成媒体文件...")
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
                            TextField("名称", text: $editingName, onCommit: {
                                store.renameItem(item: item, newName: editingName)
                                editingItemID = nil
                            })
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))

                            Button("保存") {
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
                            Text("另存为 MP4")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("将当前 GIF 另存为高质量 MP4 视频（新增一条独立记录）")
                }

                // 复制按钮
                Button(action: {
                    store.copyMediaToClipboard(item: item)
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
                        Text(copiedItemID == item.id ? "已复制" : "复制")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(copiedItemID == item.id ? Color.green.opacity(0.2) : Color.white.opacity(0.08))
                    .foregroundColor(copiedItemID == item.id ? .green : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("复制文件到剪贴板，可直接在微信/Slack/Finder/终端中粘贴")

                // 定位文件
                Button(action: { store.revealInFinder(item: item) }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .help("在访达中定位文件")

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
                .help("删除")
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
        )
        // 支持直接从列表向外部拖拽文件
        .onDrag {
            NSItemProvider(object: item.fileURL as NSURL)
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.badge.waveform")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.6))

            Text("暂无录制记录")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            Text("按下 ⌥5 选择屏幕区域，或 ⌥6 全屏录制 GIF / MP4")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button(action: { store.triggerSelectionCapture() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "crop")
                        Text("开始选区录制 (⌥5)")
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
                    Text("导出与画质")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    // 目标帧率
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("目标帧率")
                                .font(.system(size: 12, weight: .medium))
                            Text("帧率越高画面越流畅，文件体积相应增加")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Picker("", selection: $store.settings.targetFPS) {
                            Text("10 FPS (轻量)").tag(10)
                            Text("15 FPS (推荐)").tag(15)
                            Text("20 FPS (丝滑)").tag(20)
                            Text("24 FPS (高帧)").tag(24)
                        }
                        .pickerStyle(.menu)
                        .frame(width: 130)
                    }

                    Divider().opacity(0.3)

                    // 分辨率缩放
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("画面清晰度")
                                .font(.system(size: 12, weight: .medium))
                            Text("标准像素体积较小，超清模式保留 Retina 细节")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Picker("", selection: $store.settings.maxScaleFactor) {
                            Text("1.0x 标准").tag(1.0)
                            Text("2.0x Retina 超清").tag(2.0)
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
                    Text("画面特效与 HUD")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    // 鼠标点击红点涟漪开关
                    Toggle(isOn: $store.settings.showClickRipple) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("鼠标点击红点与涟漪动画")
                                .font(.system(size: 12, weight: .medium))
                            Text("录制中自动高亮鼠标左键（红点扩散）与右键（蓝点扩散）")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .toggleStyle(.checkbox)

                    Divider().opacity(0.3)

                    // 键盘 HUD 开关
                    Toggle(isOn: $store.settings.showKeycast) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("底部键盘按键回显 (Keycast)")
                                .font(.system(size: 12, weight: .medium))
                            Text("在画面底部中央展示当前按键组合（每 2 秒平滑轮替）")
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
                    Text("全局快捷键速查")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)

                    HStack {
                        Text("选区录制")
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
                        Text("全屏录制")
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
                        Text("展开录制列表")
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
                GifImageView(url: item.fileURL)
            }
        }
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

private struct GifImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.animates = true
        loadImage(into: iv)
        return iv
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        loadImage(into: nsView)
    }

    private func loadImage(into iv: NSImageView) {
        if let image = NSImage(contentsOf: url) {
            iv.image = image
        }
    }
}
