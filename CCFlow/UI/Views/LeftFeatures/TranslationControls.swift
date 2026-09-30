import SwiftUI
import AVFoundation

struct TranslationCopyButton: View {
    let text: String
    var title: String? = nil
    @State private var copied = false
    @State private var feedbackGeneration = 0

    @Environment(\.locale) private var localizationLocale

    var body: some View {
        // Recompute formatted strings when the app language changes.
        let _ = localizationLocale
        Button {
            NSPasteboard.general.clearContents()
            copied = NSPasteboard.general.setString(text, forType: .string)
            feedbackGeneration += 1
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: 12))
                    .frame(width: 16, height: 16)
                    .contentTransition(.identity)
                // Keep the title and icon slot stable so ViewThatFits never reflows on success.
                if let title { Text(appLocalized: title).font(.caption).lineLimit(1) }
            }
            .foregroundStyle(copied ? Color.green : Color.secondary)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .fixedSize(horizontal: true, vertical: true)
            .background(copied ? Color.green.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
        .help(Text(appLocalized: copied ? "复制成功" : (title.map { AppLocalization.format("复制为 %@", String(describing: $0)) } ?? "复制完整文本")))
        .accessibilityLabel(Text(appLocalized: copied ? "复制成功" : (title ?? "复制")))
        .task(id: feedbackGeneration) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(1.5)); copied = false } catch { }
        }
        .onChange(of: text) { _, _ in copied = false; feedbackGeneration += 1 }
    }
}

struct TranslationSpeechButton: View {
    let text: String
    let id: String
    @ObservedObject private var speech = TranslationSpeechController.shared
    private var active: Bool { speech.activeID == id }
    @Environment(\.locale) private var localizationLocale

    var body: some View {
        // Recompute formatted strings when the app language changes.
        let _ = localizationLocale
        Button { speech.toggle(text, id: id) } label: {
            HStack(spacing: 4) {
                Image(systemName: active ? "waveform" : "speaker.wave.2")
                    .symbolEffect(.variableColor.iterative, isActive: active && speech.isPlaying)
                if active { Text(appLocalized: speech.isPlaying ? "播放中 · 停止" : "准备中 · 停止").font(.caption) }
            }
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(active ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.borderless)
        .disabled(text.isEmpty || !speech.enabled)
        .help(Text(appLocalized: active ? "停止朗读" : "使用系统语音朗读"))
        .accessibilityLabel(Text(appLocalized: active ? "停止朗读" : "朗读"))
        .onChange(of: text) { _, _ in if active { speech.stop() } }
        .onDisappear { if active { speech.stop() } }
    }
}

struct TranslationCopySettingsView: View {
    @ObservedObject private var store = TranslationStore.shared
    @Environment(\.locale) private var localizationLocale

    var body: some View {
        // Recompute formatted strings when the app language changes.
        let _ = localizationLocale
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label("复制结果", systemImage: "doc.on.doc").font(.title3.bold())
                Text("开启后，英文译文下方会显示对应的复制按钮。普通复制始终保留原文格式。").foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(TranslationCopyFormat.allCases) { format in
                        HStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(appLocalized: format.title).font(.system(size: 13, weight: .medium))
                                Text("How are you → \(format.example)").font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle(LocalizedStringKey(format.title), isOn: Binding(get: { store.copyFormats.contains(format) }, set: { value in
                                if value { store.copyFormats.insert(format) } else { store.copyFormats.remove(format) }
                            }))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .fixedSize()
                        }
                        .frame(minHeight: 38)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        if format != TranslationCopyFormat.allCases.last { Divider().padding(.horizontal, 16) }
                    }
                }.background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                Text("设置自动保存。复制成功后按钮会短暂变为绿色勾选。").font(.caption).foregroundStyle(.secondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TranslationVoiceSettingsView: View {
    @ObservedObject private var speech = TranslationSpeechController.shared
    @Environment(\.locale) private var localizationLocale

    var body: some View {
        // Recompute formatted strings when the app language changes.
        let _ = localizationLocale
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("系统语音", systemImage: "speaker.wave.2.fill").font(.title3.bold())
                Text("默认使用 macOS 系统语音，无需 API Key。自动模式会按文本语言选择声音。").foregroundStyle(.secondary)
                Toggle("启用朗读", isOn: $speech.enabled).toggleStyle(.switch)
                VStack(alignment: .leading, spacing: 10) {
                    Picker("声音", selection: $speech.voiceID) {
                        Text("自动 · 跟随文本语言").tag("")
                        ForEach(speech.voices, id: \.identifier) { voice in
                            Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                        }
                    }
                    if !speech.voiceID.isEmpty, !speech.voices.contains(where: { $0.identifier == speech.voiceID }) {
                        Text("此前的声音当前不可用，朗读时自动选择匹配语言的声音。").font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Text("语速")
                        Text("慢").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $speech.rate, in: 0.3...0.65, step: 0.01)
                        Text("快").font(.caption).foregroundStyle(.secondary)
                        Button("重置") { speech.rate = 0.5 }
                    }
                }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                TranslationSpeechButton(text: "你好，这是系统语音试听。Hello, welcome to Tflow.", id: "voice-preview")
                Text("点击扬声器开始朗读，再次点击停止；播放结束后自动恢复。可在 macOS 系统设置中下载更多声音。").font(.caption).foregroundStyle(.secondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
