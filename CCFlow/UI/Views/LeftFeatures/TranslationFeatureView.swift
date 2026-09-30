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
                Label("Tflow 翻译", systemImage: "character.bubble")
                    .font(.headline)
                Spacer()
                Button { store.clipboardTranslation() } label: { Image(systemName: "doc.on.clipboard") }.help("翻译剪贴板文字或图片")
                Button { store.screenshotTranslation() } label: { Image(systemName: "viewfinder") }.help("截图翻译 · ⌥S")
                Button { store.showingServices = true } label: { Image(systemName: "slider.horizontal.3") }.help("配置翻译服务")
            }.buttonStyle(.borderless)
            VStack(alignment: .leading, spacing: 4) {
                TextEditor(text: $store.text)
                    .font(.system(size: 15))
                    .scrollContentBackground(.hidden)
                    .focused($inputFocused)
                    .disabled(store.recognizing || store.readingInput)
                    .frame(minHeight: 70, idealHeight: 96, maxHeight: 140)
                    .accessibilityLabel("待翻译原文")
                HStack {
                    TranslationSpeechButton(text: store.text, id: "translation-source")
                    TranslationCopyButton(text: store.text)
                    Spacer()
                    Text("⌘↩ 翻译").font(.caption).foregroundStyle(.secondary)
                    Button("翻译") { store.translate() }.keyboardShortcut(.return, modifiers: .command)
                        .disabled(store.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.recognizing || store.readingInput)
                }.buttonStyle(.borderless)
            }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            HStack {
                Picker("源语言", selection: $store.source) {
                    ForEach(TranslationLanguage.allCases) { Text(appLocalized: $0.title).tag($0) }
                }.labelsHidden()
                Spacer()
                Button {
                    let source = store.source == .auto ? TranslationClient.detectedLanguage(store.text) : store.source
                    let target = store.target == .auto ? (source == .zh ? TranslationLanguage.en : .zh) : store.target
                    store.source = target
                    store.target = source
                } label: { Image(systemName: "arrow.left.arrow.right") }.buttonStyle(.borderless).help("交换语言")
                Spacer()
                Picker("目标语言", selection: $store.target) {
                    ForEach(TranslationLanguage.allCases) { Text(appLocalized: $0 == .auto ? "自动选择（中 / 英）" : $0.title).tag($0) }
                }.labelsHidden()
            }.disabled(store.recognizing || store.readingInput).padding(6).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let notice = store.notice {
                        Label(LocalizedStringKey(notice), systemImage: "info.circle").font(.callout).padding(10)
                    }
                    if store.readingInput || store.recognizing {
                        TranslationLoadingView(message: store.readingInput ? "正在读取文字或图片…" : "识别中…")
                            .padding(12)
                            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    } else if store.results.isEmpty && store.imageTranslation == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("⌥D 选词 / 剪贴板 · ⌥S 截图 · ⌥A 输入")
                            Text("未选择文字时读取剪贴板文字或图片；默认本地识别，可在设置切换 OCR。只向已启用且展开的翻译服务发送原文。")
                                .foregroundStyle(.secondary)
                            HStack {
                                Button("配置服务") { store.showingServices = true }
                                Button("开启选词权限") { store.requestAccessibility() }
                            }
                        }.font(.callout).padding(12)
                    }
                    if let translation = store.imageTranslation {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("腾讯图片翻译", systemImage: "photo.badge.checkmark").font(.headline)
                            Text(SessionTextSanitizer.boundedDisplayText(translation, maxCharacters: 20000, truncationNotice: AppLocalization.string("\n…可复制完整译文")) ?? "").textSelection(.enabled)
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
                            Text("展开后翻译").font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: result.expanded ? "chevron.down" : "chevron.left").foregroundStyle(.secondary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                Menu {
                    Button { store.setDefaultExpanded(result.provider, expanded: true) } label: {
                        Label("默认展开 · 自动翻译", systemImage: defaultExpanded ? "checkmark.circle.fill" : "circle")
                    }
                    Button { store.setDefaultExpanded(result.provider, expanded: false) } label: {
                        Label("默认折叠 · 展开时翻译", systemImage: defaultExpanded ? "circle" : "checkmark.circle.fill")
                    }
                } label: { Image(systemName: "slider.horizontal.3") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help(AppLocalization.format("设置 %@ 的默认展开方式", AppLocalization.string(result.provider.title)))
            }
            if result.expanded {
                if result.loading {
                    TranslationLoadingView(message: "翻译中…")
                } else if let error = result.error {
                    Text(appLocalized: error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
                } else {
                    Text(SessionTextSanitizer.boundedDisplayText(result.text, maxCharacters: 20000, truncationNotice: AppLocalization.string("\n…可复制完整译文")) ?? "").font(.system(size: 15)).textSelection(.enabled)
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
            Text(appLocalized: store.readingInput ? "正在读取文字或图片…" : (store.recognizing ? "识别中…" : (store.results.contains(where: \.loading) ? "翻译中…" : "Tflow 翻译")))
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
                Button(action: onBack) { Label("返回", systemImage: "chevron.left") }
                    .buttonStyle(.borderless).help("返回翻译")
                Text("翻译设置").font(.headline)
                Spacer()
                Picker("设置分类", selection: $tab) {
                    Text("翻译服务").tag(0)
                    Text("复制结果").tag(1)
                    Text("系统语音").tag(2)
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
                        TextField("搜索服务", text: $query).textFieldStyle(.roundedBorder)
                        Toggle("只看已启用", isOn: $enabledOnly).font(.caption).toggleStyle(.checkbox)
                        ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(["已启用", "通用翻译", "AI 模型", "本地服务"], id: \.self) { group in
                                    let items = store.configurations.filter {
                                        (group == "已启用" ? $0.enabled : (!$0.enabled && $0.provider.group == group)) && (!enabledOnly || $0.enabled) &&
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
                Text(appLocalized: configuration.enabled ? "停用" : "启用")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(configuration.enabled ? Color.red : Color.blue, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(Text(AppLocalization.string(configuration.enabled ? "停用" : "启用") + " " + AppLocalization.string(configuration.provider.title)))

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
                Link("申请与使用说明 ↗", destination: configuration.provider.documentationURL)
                Text("左侧「启用 / 停用」即时生效；下方配置修改后点击保存。").font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Text("结果展示方式").font(.system(size: 13, weight: .medium))
                    Picker("结果展示方式", selection: Binding(
                        get: { store.configurations.first { $0.provider == configuration.provider }?.expandsByDefault ?? true },
                        set: { store.setDefaultExpanded(configuration.provider, expanded: $0) }
                    )) {
                        Text("默认展开 · 自动翻译").tag(true)
                        Text("默认折叠 · 展开时翻译").tag(false)
                    }.labelsHidden().pickerStyle(.segmented)
                    Text("仅对已启用的服务生效；默认折叠时，展开结果才发起请求。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if configuration.provider.needsAppID {
                    field([TranslationProvider.baidu, .youdao].contains(configuration.provider) ? "应用 ID" : "Access Key ID", text: $configuration.appID)
                }
                if configuration.provider != .myMemory && configuration.provider != .dictionary {
                    VStack(alignment: .leading) {
                        Text("API Key / 应用密钥")
                        HStack {
                            Group {
                                if revealingSecret { TextField("保存在 macOS 钥匙串", text: $secret) }
                                else { SecureField("保存在 macOS 钥匙串", text: $secret) }
                            }.textFieldStyle(.roundedBorder)
                            Button { revealingSecret.toggle() } label: { Image(systemName: revealingSecret ? "eye.slash" : "eye") }
                                .buttonStyle(.borderless).help(Text(appLocalized: revealingSecret ? "隐藏密钥" : "显示密钥"))
                        }
                    }
                }
                if configuration.provider.needsRegion { field("服务区域", text: $configuration.region) }
                if configuration.provider.usesChatAPI {
                    field("API Base URL", text: $configuration.baseURL)
                    field("API Path", text: $configuration.apiPath)
                    field(configuration.provider == .azureOpenAI ? "模型部署名称" : "模型名称（填写平台中已开通的模型）", text: $configuration.model)
                    if configuration.provider == .zhipu || configuration.provider == .siliconFlow {
                        Button("恢复预设免费模型") {
                            let preset = TranslationServiceConfiguration.preset(configuration.provider)
                            configuration.model = preset.model
                            configuration.baseURL = preset.baseURL
                            configuration.apiPath = preset.apiPath
                        }.font(.caption)
                        Text("免费模型仍需自己的 API Key，不能使用 Bob 专属的免密钥通道。修改模型前请确认价格。").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("翻译提示词 · 支持 {source} 和 {target}").font(.caption)
                    TextEditor(text: $configuration.prompt).font(.system(size: 12)).frame(height: 90)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                }
                if let message { Text(appLocalized: message).font(.callout).foregroundStyle(.secondary) }
                Button("保存") {
                    do {
                        configuration.enabled = store.configurations.first { $0.provider == configuration.provider }?.enabled ?? false
                        configuration.expandedByDefault = store.configurations.first { $0.provider == configuration.provider }?.expandedByDefault
                        try store.save(configuration, secret: secret)
                        message = "✓ 已保存"
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
