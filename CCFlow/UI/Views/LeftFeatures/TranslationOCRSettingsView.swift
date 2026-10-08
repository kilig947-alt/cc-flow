import SwiftUI

struct TranslationOCRSettingsView: View {
    @ObservedObject private var settings = TranslationOCRSettings.shared
    @State private var editing: TranslationOCRProvider = .system
    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("translation.use_one_recognition_service_at_a_time").font(.caption).foregroundStyle(.secondary)
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
                                    Text(appLocalized: provider == .system ? AppLocalization.runtimeString("translation.built_in_default") : AppLocalization.runtimeString("translation.bring_your_own_key")).font(.caption2).foregroundStyle(.secondary)
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
                Text(appLocalized: configuration.provider == .system ? AppLocalization.runtimeString("translation.recognize_text_locally_with_macos_vision_no_key") : AppLocalization.runtimeString("translation.screenshots_and_clipboard_images_are_sent_to_the"))
                    .font(.callout).foregroundStyle(.secondary)
                if configuration.provider == .tencentImage {
                    Text("translation.this_service_returns_both_source_text_and_translation")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Link(AppLocalization.runtimeString("translation.setup_and_usage_guide"), destination: configuration.provider.documentationURL)
                if configuration.provider != .system {
                    if configuration.provider.needsID { field(configuration.provider.credentialLabel, text: $configuration.appID) }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(appLocalized: configuration.provider == .google ? "API Key" : AppLocalization.runtimeString("translation.secret_key_app_secret"))
                        HStack {
                            Group {
                                if revealing { TextField("translation.stored_in_macos_keychain", text: $secret) }
                                else { SecureField("translation.stored_in_macos_keychain", text: $secret) }
                            }.textFieldStyle(.roundedBorder)
                            Button { revealing.toggle() } label: { Image(systemName: revealing ? "eye.slash" : "eye") }.buttonStyle(.borderless)
                        }
                    }
                    if configuration.provider.needsRegion { field(AppLocalization.runtimeString("translation.service_region"), text: $configuration.region) }
                }
                if let message { Text(appLocalized: message).font(.callout).foregroundStyle(.secondary) }
                HStack {
                    if configuration.provider != .system {
                        Button("translation.save_configuration") { save(use: false) }
                    }
                    Button(settings.selected == configuration.provider ? AppLocalization.runtimeString("translation.save_and_continue") : AppLocalization.runtimeString("translation.use_this_service")) { save(use: true) }
                        .buttonStyle(.borderedProminent)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }.onAppear { secret = TranslationKeychain.read(account: configuration.provider.account) }
    }
    private func save(use: Bool) {
        do {
            if configuration.provider != .system {
                if use && (secret.isEmpty || (configuration.provider.needsID && configuration.appID.isEmpty)) {
                    message = AppLocalization.runtimeString("translation.enter_all_required_credentials_first"); return
                }
                try settings.save(configuration, secret: secret)
            }
            if use { settings.select(configuration.provider) }
            message = use ? AppLocalization.runtimeString("translation.set_as_current_recognition_service") : AppLocalization.runtimeString("translation.saved")
        } catch { message = error.localizedDescription }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(appLocalized: title); TextField(LocalizedStringKey(title), text: text).textFieldStyle(.roundedBorder) }
    }
}
