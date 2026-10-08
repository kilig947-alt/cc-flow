import SwiftUI

struct TranslationFeatureView: View {
    @ObservedObject private var store = TranslationStore.shared
    @FocusState private var inputFocused: Bool

    @Environment(\.locale) private var localizationLocale

    var body: some View {
        // Recompute formatted strings when the app language changes.
        let _ = localizationLocale
        Group {
            if store.showingServices {
                TranslationServicesView {
                    store.showingServices = false
                }
            } else {
                translationContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var translationContent: some View {
        VStack(spacing: 10) {
            HStack {
                Label("translation.tflow_translation", systemImage: "character.bubble")
                    .font(.headline)
                Spacer()
                Button { store.clipboardTranslation() } label: { Image(systemName: "doc.on.clipboard") }.help("translation.translate_clipboard_text_or_image")
                Button { store.screenshotTranslation() } label: { Image(systemName: "viewfinder") }.help("translation.screenshot_translation_s")
                Button { store.showingServices = true } label: { Image(systemName: "slider.horizontal.3") }.help("translation.configure_translation_services")
            }.buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 4) {
                TextEditor(text: $store.text)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .focused($inputFocused)
                    .disabled(store.recognizing || store.readingInput)
                    .frame(minHeight: 70, idealHeight: 96, maxHeight: 140)
                    .accessibilityLabel("translation.source_text")
                HStack {
                    TranslationSpeechButton(text: store.text, id: "translation-source")
                    TranslationCopyButton(text: store.text)
                    Spacer()
                    Text("translation.translate").font(.caption).foregroundStyle(.secondary)
                    Button("translation.translate_2") { store.translate() }.keyboardShortcut(.return, modifiers: .command)
                        .disabled(store.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.recognizing || store.readingInput)
                }.buttonStyle(.borderless)
            }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Picker("translation.source_language", selection: $store.source) {
                    ForEach(TranslationLanguage.allCases) { Text(appLocalized: $0.title).tag($0) }
                }.labelsHidden()
                Spacer()
                if !store.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let sourceTitle = AppLocalization.string(store.effectiveSourceLanguage?.title ?? AppLocalization.runtimeString("translation.language.unrecognized"))
                    Text(verbatim: sourceTitle + " → " + AppLocalization.string(store.effectiveTargetLanguage.title))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button {
                    let source = store.source == .auto ? TranslationClient.detectedLanguage(store.text) : store.source
                    let target = store.target == .auto ? (source == .zh ? TranslationLanguage.en : .zh) : store.target
                    store.source = target
                    store.target = source
                } label: { Image(systemName: "arrow.left.arrow.right") }.buttonStyle(.borderless).help("translation.swap_languages")
                Spacer()
                Picker("translation.target_language", selection: $store.target) {
                    ForEach(TranslationLanguage.allCases) { Text(appLocalized: $0 == .auto ? AppLocalization.runtimeString("translation.automatic_chinese_english") : $0.title).tag($0) }
                }.labelsHidden()
            }.disabled(store.recognizing || store.readingInput).padding(6).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let notice = store.notice {
                        Label(LocalizedStringKey(notice), systemImage: "info.circle").font(.callout).padding(10)
                    }
                    if store.readingInput || store.recognizing {
                        TranslationLoadingView(message: store.readingInput ? AppLocalization.runtimeString("translation.reading_text_or_image") : AppLocalization.runtimeString("translation.recognizing"))
                            .padding(12)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    } else if store.results.isEmpty && store.imageTranslation == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("translation.d_selection_clipboard_s_screenshot_a_input")
                            Text("translation.reads_clipboard_text_or_images_when_no_text")
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("translation.configure_services") { store.showingServices = true }
                                Button("translation.enable_selection_permission") { store.requestAccessibility() }
                            }
                        }.font(.callout).padding(12)
                    }
                    if let translation = store.imageTranslation {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("translation.tencent_image_translation", systemImage: "photo.badge.checkmark").font(.headline)
                            Text(SessionTextSanitizer.boundedDisplayText(translation, maxCharacters: 20000, truncationNotice: AppLocalization.string("translation.n_copy_to_get_the_full_translation")) ?? "").textSelection(.enabled)
                            HStack {
                                TranslationSpeechButton(text: translation, id: "ocr-image-translation")
                                TranslationCopyButton(text: translation)
                            }
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    }
                    ForEach(store.results) { result in
                        TranslationResultCard(result: result)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { inputFocused = !store.readingInput }
        .onChange(of: store.focusGeneration) { _, _ in inputFocused = true }
    }
}

private struct TranslationLoadingView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(appLocalized: message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct TranslationResultCard: View {
    let result: TranslationResult
    @ObservedObject private var store = TranslationStore.shared
    @Environment(\.locale) private var localizationLocale

    var body: some View {
        // Recompute formatted strings when the app language changes.
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button { store.setResultExpanded(result.provider, expanded: !result.expanded) } label: {
                    HStack {
                        TranslationProviderIcon(provider: result.provider, size: 18)
                        Text(appLocalized: result.provider.title).font(.system(size: 13, weight: .medium))
                        Spacer()
                        if !result.expanded && result.text.isEmpty {
                            Text("translation.expand_to_translate").font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: result.expanded ? "chevron.down" : "chevron.left").foregroundStyle(.secondary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                Menu {
                    Button { store.setDefaultExpanded(result.provider, expanded: true) } label: {
                        Label("translation.expanded_by_default_translate_automatically", systemImage: defaultExpanded ? "checkmark.circle.fill" : "circle")
                    }
                    Button { store.setDefaultExpanded(result.provider, expanded: false) } label: {
                        Label("translation.collapsed_by_default_translate_on_expand", systemImage: defaultExpanded ? "circle" : "checkmark.circle.fill")
                    }
                } label: { Image(systemName: "slider.horizontal.3") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(AppLocalization.format("translation.set_default_expansion_for", AppLocalization.string(result.provider.title)))
            }
            if result.expanded {
                if result.loading {
                    TranslationLoadingView(message: AppLocalization.runtimeString("translation.translating"))
                } else if let error = result.error {
                    Text(appLocalized: error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                } else {
                    Text(SessionTextSanitizer.boundedDisplayText(result.text, maxCharacters: 20000, truncationNotice: AppLocalization.string("translation.n_copy_to_get_the_full_translation")) ?? "").font(.system(size: 15)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            standardButtons
                            if TranslationCopyFormat.supports(result.text) { formatButtons }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            standardButtons
                            if TranslationCopyFormat.supports(result.text) {
                                ScrollView(.horizontal, showsIndicators: false) { formatButtons }
                            }
                        }
                    }.buttonStyle(.borderless)
                }
            }
        }.padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
    private var defaultExpanded: Bool {
        store.configurations.first { $0.provider == result.provider }?.expandsByDefault ?? true
    }

    private var standardButtons: some View {
        HStack(spacing: 6) {
            TranslationSpeechButton(text: result.text, id: "translation-result-" + result.id)
            TranslationCopyButton(text: result.text)
        }
    }

    private var formatButtons: some View {
        HStack(spacing: 6) {
            ForEach(TranslationCopyFormat.allCases.filter { store.copyFormats.contains($0) }) { format in
                TranslationCopyButton(text: format.convert(result.text), title: format.title)
            }
        }
    }
}

struct TranslationCompactView: View {
    @ObservedObject private var store = TranslationStore.shared
    @Environment(\.locale) private var localizationLocale

    var body: some View {
        // Recompute formatted strings when the app language changes.
        let _ = localizationLocale
        HStack(spacing: 6) {
            Image(systemName: "character.bubble")
            Text(appLocalized: store.readingInput ? AppLocalization.runtimeString("translation.reading_text_or_image") : (store.recognizing ? AppLocalization.runtimeString("translation.recognizing") : (store.results.contains(where: \.loading) ? AppLocalization.runtimeString("translation.translating") : AppLocalization.runtimeString("translation.tflow_translation"))))
                .font(.system(size: 11)).lineLimit(1)
        }
    }
}

struct TranslationServicesView: View {
    @ObservedObject private var store = TranslationStore.shared
    let onBack: () -> Void
    @State private var selected: TranslationProvider = .zhipu
    @State private var tab = 0
    @State private var query = ""
    @State private var enabledOnly = false
    @State private var scrollTarget: TranslationProvider?
    @Environment(\.locale) private var localizationLocale

    var body: some View {
        // Recompute formatted strings when the app language changes.
        let _ = localizationLocale
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) { Label("translation.back", systemImage: "chevron.left") }
                    .buttonStyle(.borderless).help("translation.back_to_translation")
                Text("translation.translation_settings").font(.headline)
                Spacer()
                Picker("translation.settings_categories", selection: $tab) {
                    Text("settings.translation_services").tag(0)
                    Text("translation.copy_results").tag(1)
                    Text("translation.system_voice").tag(2)
                    Text("OCR").tag(3)
                }.labelsHidden().pickerStyle(.segmented).frame(maxWidth: 400)
            }.padding(14)
            Divider()
            if tab == 1 {
                TranslationCopySettingsView()
            } else if tab == 2 {
                TranslationVoiceSettingsView()
            } else if tab == 3 {
                TranslationOCRSettingsView()
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 8) {
                        TextField("translation.search_services", text: $query).textFieldStyle(.roundedBorder)
                        Toggle("translation.enabled_only", isOn: $enabledOnly).font(.caption).toggleStyle(.checkbox)
                        ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach([AppLocalization.runtimeString("translation.enabled_2"), AppLocalization.runtimeString("translation.general_translation"), AppLocalization.runtimeString("translation.ai_models"), AppLocalization.runtimeString("translation.local_services")], id: \.self) { group in
                                    let items = store.configurations.filter {
                                        (group == AppLocalization.runtimeString("translation.enabled_2") ? $0.enabled : (!$0.enabled && $0.provider.group == group)) && (!enabledOnly || $0.enabled) &&
                                        (query.isEmpty || $0.provider.title.localizedCaseInsensitiveContains(query) || $0.provider.rawValue.localizedCaseInsensitiveContains(query))
                                    }
                                    if !items.isEmpty {
                                        Text(appLocalized: group).font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                                        ForEach(items) { configuration in serviceRow(configuration).id(configuration.provider) }
                                    }
                                }
                            }
                        }
                        .task(id: scrollTarget) {
                            guard let target = scrollTarget else { return }
                            await Task.yield()
                            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .top) }
                            scrollTarget = nil
                        }
                        }
                    }.padding(8).frame(width: 230)
                    Divider()
                    if let configuration = store.configurations.first(where: { $0.provider == selected }) {
                        TranslationServiceEditor(configuration: configuration).id(selected)
                            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func serviceRow(_ configuration: TranslationServiceConfiguration) -> some View {
        HStack(spacing: 8) {
            Button { selected = configuration.provider } label: {
                HStack(spacing: 8) {
                    TranslationProviderIcon(provider: configuration.provider, size: 22)
                        .frame(width: 24, height: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appLocalized: configuration.provider.title).font(.system(size: 12, weight: .medium))
                        Text(appLocalized: configuration.badge).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button {
                let enabled = !configuration.enabled
                selected = configuration.provider
                store.setServiceEnabled(configuration.provider, enabled: enabled)
                query = ""
                if !enabled { enabledOnly = false }
                scrollTarget = configuration.provider
            } label: {
                Text(appLocalized: configuration.enabled ? AppLocalization.runtimeString("translation.disable") : AppLocalization.runtimeString("translation.enabled"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(configuration.enabled ? Color.red : Color.blue, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(Text(AppLocalization.string(configuration.enabled ? AppLocalization.runtimeString("translation.disable") : AppLocalization.runtimeString("translation.enabled")) + " " + AppLocalization.string(configuration.provider.title)))

        }
        .padding(8)
        .background(selected == configuration.provider ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct TranslationServiceEditor: View {
    @ObservedObject private var store = TranslationStore.shared
    @State var configuration: TranslationServiceConfiguration
    @State private var secret = ""
    @State private var message: String?
    @State private var revealingSecret = false
    @Environment(\.locale) private var localizationLocale

    var body: some View {
        // Recompute formatted strings when the app language changes.
        let _ = localizationLocale
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(appLocalized: configuration.provider.title).font(.title2.bold())
                Text(appLocalized: configuration.provider.detail).font(.callout).foregroundStyle(.secondary)
                Link(AppLocalization.runtimeString("translation.setup_and_usage_guide"), destination: configuration.provider.documentationURL)
                Text("translation.enable_or_disable_services_on_the_left_immediately").font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("translation.result_display").font(.system(size: 13, weight: .medium))
                    Picker("translation.result_display", selection: Binding(
                        get: { store.configurations.first { $0.provider == configuration.provider }?.expandsByDefault ?? true },
                        set: { store.setDefaultExpanded(configuration.provider, expanded: $0) }
                    )) {
                        Text("translation.expanded_by_default_translate_automatically").tag(true)
                        Text("translation.collapsed_by_default_translate_on_expand").tag(false)
                    }.labelsHidden().pickerStyle(.segmented)
                    Text("translation.applies_to_enabled_services_only_collapsed_results_send")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if configuration.provider.needsAppID {
                    field([TranslationProvider.baidu, .youdao].contains(configuration.provider) ? AppLocalization.runtimeString("translation.app_id") : "Access Key ID", text: $configuration.appID)
                }
                if configuration.provider != .myMemory && configuration.provider != .dictionary {
                    VStack(alignment: .leading) {
                        Text("translation.api_key_app_secret")
                        HStack {
                            Group {
                                if revealingSecret { TextField("translation.stored_in_macos_keychain", text: $secret) }
                                else { SecureField("translation.stored_in_macos_keychain", text: $secret) }
                            }.textFieldStyle(.roundedBorder)
                            Button { revealingSecret.toggle() } label: { Image(systemName: revealingSecret ? "eye.slash" : "eye") }
                                .buttonStyle(.borderless).help(Text(appLocalized: revealingSecret ? AppLocalization.runtimeString("translation.hide_key") : AppLocalization.runtimeString("translation.show_key")))
                        }
                    }
                }
                if configuration.provider.needsRegion { field(AppLocalization.runtimeString("translation.service_region"), text: $configuration.region) }
                if configuration.provider.usesChatAPI {
                    field("API Base URL", text: $configuration.baseURL)
                    field("API Path", text: $configuration.apiPath)
                    field(configuration.provider == .azureOpenAI ? AppLocalization.runtimeString("translation.model_deployment_name") : AppLocalization.runtimeString("translation.model_name_must_be_enabled_in_your_account"), text: $configuration.model)
                    if configuration.provider == .zhipu || configuration.provider == .siliconFlow {
                        Button("translation.restore_preset_free_model") {
                            let preset = TranslationServiceConfiguration.preset(configuration.provider)
                            configuration.model = preset.model
                            configuration.baseURL = preset.baseURL
                            configuration.apiPath = preset.apiPath
                        }.font(.caption)
                        Text("translation.free_models_still_require_your_own_api_key").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("translation.translation_prompt_supports_source_and_target").font(.caption)
                    TextEditor(text: $configuration.prompt).font(.system(size: 12)).frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                }
                if let message { Text(appLocalized: message).font(.callout).foregroundStyle(.secondary) }
                Button("common.save") {
                    do {
                        configuration.enabled = store.configurations.first { $0.provider == configuration.provider }?.enabled ?? false
                        configuration.expandedByDefault = store.configurations.first { $0.provider == configuration.provider }?.expandedByDefault
                        try store.save(configuration, secret: secret)
                        message = AppLocalization.runtimeString("translation.saved")
                    }
                    catch { message = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
        }.onAppear { secret = TranslationKeychain.read(configuration.provider) }
    }
    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(appLocalized: label); TextField(LocalizedStringKey(label), text: text).textFieldStyle(.roundedBorder) }
    }
}
