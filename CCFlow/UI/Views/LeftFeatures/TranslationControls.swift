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
        .help(Text(appLocalized: copied ? AppLocalization.runtimeString("translation.copied") : (title.map { AppLocalization.format("translation.copy_as", String(describing: $0)) } ?? AppLocalization.runtimeString("translation.copy_full_text"))))
        .accessibilityLabel(Text(appLocalized: copied ? AppLocalization.runtimeString("translation.copied") : (title ?? AppLocalization.runtimeString("common.copy"))))
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
                if active { Text(appLocalized: speech.isPlaying ? AppLocalization.runtimeString("translation.playing_stop") : AppLocalization.runtimeString("translation.preparing_stop")).font(.caption) }
            }
            .foregroundStyle(active ? Color.accentColor : Color.secondary)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(active ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.borderless)
        .disabled(text.isEmpty || !speech.enabled)
        .help(Text(appLocalized: active ? AppLocalization.runtimeString("translation.stop_reading") : AppLocalization.runtimeString("translation.read_aloud_with_system_voice")))
        .accessibilityLabel(Text(appLocalized: active ? AppLocalization.runtimeString("translation.stop_reading") : AppLocalization.runtimeString("translation.read_aloud")))
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
                Label("translation.copy_results", systemImage: "doc.on.doc").font(.title3.bold())
                Text("translation.show_copy_buttons_below_english_translations_standard_copy").foregroundStyle(.secondary)
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
                Text("translation.settings_save_automatically_a_green_checkmark_briefly_confirms").font(.caption).foregroundStyle(.secondary)
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
                Label("translation.system_voice", systemImage: "speaker.wave.2.fill").font(.title3.bold())
                Text("translation.uses_macos_system_voices_by_default_no_api").foregroundStyle(.secondary)
                Toggle("translation.enable_read_aloud", isOn: $speech.enabled).toggleStyle(.switch)
                VStack(alignment: .leading, spacing: 10) {
                    Picker("settings.sound", selection: $speech.voiceID) {
                        Text("translation.automatic_match_text_language").tag("")
                        ForEach(speech.voices, id: \.identifier) { voice in
                            Text("\(voice.name) · \(voice.language)").tag(voice.identifier)
                        }
                    }
                    if !speech.voiceID.isEmpty, !speech.voices.contains(where: { $0.identifier == speech.voiceID }) {
                        Text("translation.the_previously_selected_voice_is_unavailable_a_matching").font(.caption).foregroundStyle(.orange)
                    }
                    HStack {
                        Text("translation.speech_rate")
                        Text("translation.slow").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $speech.rate, in: 0.3...0.65, step: 0.01)
                        Text("translation.fast").font(.caption).foregroundStyle(.secondary)
                        Button("settings.reset") { speech.rate = 0.5 }
                    }
                }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                TranslationSpeechButton(text: AppLocalization.runtimeString("translation.hello_this_is_a_system_voice_preview_hello"), id: "voice-preview")
                Text("translation.click_the_speaker_to_read_aloud_and_click").font(.caption).foregroundStyle(.secondary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
