import Foundation
import SwiftUI

@MainActor
enum AppLocalization {
    static func string(_ key: String) -> String {
        string(key, locale: AppSettings.shared.locale)
    }

    nonisolated static func string(_ key: String, locale: Locale) -> String {
        let language = AppLanguage.resourceLanguageCode(for: locale.identifier)
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj")
            .flatMap(Bundle.init(path:)) ?? .main
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    // Error descriptions may be produced off the main actor. Read the persisted
    // preference at the point of presentation without touching UI state.
    nonisolated private static var persistedLocale: Locale {
        let language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .system
        return language.resolvedLocale()
    }

    nonisolated static func runtimeString(_ key: String) -> String {
        string(key, locale: persistedLocale)
    }

    nonisolated static func runtimeFormat(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, arguments: arguments, locale: persistedLocale)
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        format(key, arguments: arguments, locale: AppSettings.shared.locale)
    }

    static func format(_ key: String, _ arguments: CVarArg..., locale: Locale) -> String {
        format(key, arguments: arguments, locale: locale)
    }

    nonisolated private static func format(_ key: String, arguments: [CVarArg], locale: Locale) -> String {
        let format = string(key, locale: locale)
        return String(format: format, locale: locale, arguments: arguments)
    }
}

struct AppLocalizedRootView<Content: View>: View {
    @ObservedObject private var settings = AppSettings.shared
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.locale, settings.locale)
    }
}

extension Text {
    init(appLocalized key: String) {
        self.init(LocalizedStringKey(key))
    }
}
