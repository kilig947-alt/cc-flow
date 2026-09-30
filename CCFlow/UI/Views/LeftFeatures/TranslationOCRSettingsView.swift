import SwiftUI

struct TranslationOCRSettingsView: View {
    @ObservedObject private var settings = TranslationOCRSettings.shared
    @State private var editing: TranslationOCRProvider = .system
    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("一次使用一个识别服务").font(.caption).foregroundStyle(.secondary)
                    ForEach(TranslationOCRProvider.allCases) { provider in
                        Button { editing = provider } label: {
                            HStack {
                                if let brand = provider.brandProvider {
                                    TranslationProviderIcon(provider: brand, size: 22)
                                } else {
                                    Image(systemName: "text.viewfinder").frame(width: 22, height: 22)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(appLocalized: provider.title).font(.system(size: 12, weight: .medium))
                                    Text(appLocalized: provider == .system ? "系统内置 · 默认" : "自备密钥").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if settings.selected == provider { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                            }.padding(10).contentShape(Rectangle())
                                .background(editing == provider ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain)
                    }
                }.padding(8)
            }.frame(width: 230)
            Divider()
            TranslationOCREditor(configuration: settings.configuration(editing)).id(editing)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.onAppear { editing = settings.selected }
    }
}

private struct TranslationOCREditor: View {
    @ObservedObject private var settings = TranslationOCRSettings.shared
    @State var configuration: TranslationOCRConfiguration
    @State private var secret = ""
    @State private var revealing = false
    @State private var message: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(appLocalized: configuration.provider.title).font(.title2.bold())
                Text(appLocalized: configuration.provider == .system ? "使用 macOS Vision 在本机识别，无需密钥，也不会上传图片。识别出的文字按文本翻译服务的启用与展开状态继续翻译。" : "选为当前服务后，截图和剪贴板图片将发送到此服务进行识别。只调用当前服务，失败时不会自动切换。费用以服务方为准。")
                    .font(.callout).foregroundStyle(.secondary)
                if configuration.provider == .tencentImage {
                    Text("此服务一次返回原文与译文，不再自动调用文本翻译服务。目标语言为自动时使用中文；需要英文时请先在翻译页选择英语。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Link("申请与使用说明 ↗", destination: configuration.provider.documentationURL)
                if configuration.provider != .system {
                    if configuration.provider.needsID { field(configuration.provider.credentialLabel, text: $configuration.appID) }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(appLocalized: configuration.provider == .google ? "API Key" : "Secret Key / 应用密钥")
                        HStack {
                            Group {
                                if revealing { TextField("保存在 macOS 钥匙串", text: $secret) }
                                else { SecureField("保存在 macOS 钥匙串", text: $secret) }
                            }.textFieldStyle(.roundedBorder)
                            Button { revealing.toggle() } label: { Image(systemName: revealing ? "eye.slash" : "eye") }.buttonStyle(.borderless)
                        }
                    }
                    if configuration.provider.needsRegion { field("服务区域", text: $configuration.region) }
                }
                if let message { Text(appLocalized: message).font(.callout).foregroundStyle(.secondary) }
                HStack {
                    if configuration.provider != .system {
                        Button("保存配置") { save(use: false) }
                    }
                    Button(settings.selected == configuration.provider ? "保存并继续使用" : "使用此服务") { save(use: true) }
                        .buttonStyle(.borderedProminent)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.onAppear { secret = TranslationKeychain.read(account: configuration.provider.account) }
    }
    private func save(use: Bool) {
        do {
            if configuration.provider != .system {
                if use && (secret.isEmpty || (configuration.provider.needsID && configuration.appID.isEmpty)) {
                    message = "请先填写完整凭据"; return
                }
                try settings.save(configuration, secret: secret)
            }
            if use { settings.select(configuration.provider) }
            message = use ? "✓ 已设为当前识别服务" : "✓ 已保存"
        } catch { message = error.localizedDescription }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(appLocalized: title); TextField(LocalizedStringKey(title), text: text).textFieldStyle(.roundedBorder) }
    }
}
