import XCTest
@testable import CC_FLOW

final class AppLanguageTests: XCTestCase {
    func testSystemLanguagePrefersSimplifiedChineseForChineseLocales() {
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["zh-Hans-CN"]),
            "zh-Hans"
        )
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["zh-TW"]),
            "zh-Hans"
        )
    }

    func testSystemLanguageFallsBackToEnglishForNonChineseLocales() {
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["en-US"]),
            "en"
        )
        XCTAssertEqual(
            AppLanguage.system.resolvedLanguageCode(preferredLanguages: ["ja-JP"]),
            "en"
        )
    }

    func testExplicitLanguageSelectionsStayStable() {
        XCTAssertEqual(AppLanguage.simplifiedChinese.resolvedLanguageCode(), "zh-Hans")
        XCTAssertEqual(AppLanguage.english.resolvedLanguageCode(), "en")
    }
    func testRegionalIdentifiersUseTheSameSupportedResources() {
        for identifier in ["zh-CN", "zh_CN", "zh-Hans-CN", "zh-TW"] {
            XCTAssertEqual(AppLanguage.resourceLanguageCode(for: identifier), "zh-Hans")
        }
        for identifier in ["en-US", "en_US", "ja-JP", "", "zhinvalid"] {
            XCTAssertEqual(AppLanguage.resourceLanguageCode(for: identifier), "en")
        }
        XCTAssertEqual(AppLanguage.english.resolvedLanguageCode(preferredLanguages: ["zh-CN"]), "en")
        XCTAssertEqual(AppLanguage.simplifiedChinese.resolvedLanguageCode(preferredLanguages: ["en-US"]), "zh-Hans")
    }

    @MainActor
    func testStableKeysDoNotTranslateUserTextThatMatchesOldCopy() {
        XCTAssertEqual(AppLocalization.string("语言", locale: Locale(identifier: "en")), "语言")
        XCTAssertEqual(AppLocalization.string("settings.missing_key", locale: Locale(identifier: "en")), "settings.missing_key")
    }

    @MainActor
    func testDynamicDisplayKeysDoNotChangeStoredValues() {
        XCTAssertEqual(NewFeatureType.localDirectory.rawValue, "本地目录")
        XCTAssertEqual(AppLocalization.string(NewFeatureType.localDirectory.titleKey, locale: Locale(identifier: "en")), "Local directory")
        XCTAssertEqual(MascotPetKind.animal.rawValue, "animal")
        XCTAssertEqual(AppLocalization.string(MascotPetKind.animal.titleKey, locale: Locale(identifier: "en")), "Animal")
        XCTAssertTrue(SessionDetailDisplayStrings.truncationNoticeKey.hasPrefix("session."))
    }

    @MainActor
    func testStoredStatusAndLegacySnapshotsRenderInEitherLanguage() throws {
        let english = Locale(identifier: "en")
        let chinese = Locale(identifier: "zh-Hans")
        let statusKey = GitHubService.shared.status
        XCTAssertEqual(statusKey, "github.not_connected")
        XCTAssertEqual(AppLocalization.string(statusKey, locale: english), "Not connected")
        XCTAssertEqual(AppLocalization.string(statusKey, locale: chinese), "尚未连接")
        let oldJSON = Data(#"{"id":"primary","label":"主要限额","usedPercentage":25}"#.utf8)
        var window = try JSONDecoder().decode(UsageWindow.self, from: oldJSON)
        XCTAssertEqual(window.localizedLabel(locale: english), "Primary limit")
        XCTAssertEqual(window.localizedLabel(locale: chinese), "主要限额")
        window.label = "usage.primary_limit"
        XCTAssertEqual(window.localizedLabel(locale: english), "Primary limit")
        XCTAssertEqual(window.localizedLabel(locale: chinese), "主要限额")
        window.id = "antigravity-gemini-five-hour"
        window.label = "Gemini Models · 5 小时限额"
        XCTAssertEqual(window.localizedLabel(locale: english), "Gemini Models · 5-hour quota")
        XCTAssertEqual(window.localizedLabel(locale: chinese), "Gemini Models · 5 小时限额")
        let record = SessionAuditRecord(sessionId: "test", kind: .approval, platformName: "Codex",
                                        requestTitle: "用户标题", requestContent: "用户内容", submittedMessage: "已确认",
                                        resultLabel: "允许相同操作")
        XCTAssertEqual(AppLocalization.string(record.resultLabelKey, locale: english), "Allow matching actions · Manual")
        XCTAssertEqual(AppLocalization.string(record.resultLabelKey, locale: chinese), "允许相同操作 · 手动")
        XCTAssertEqual(record.requestTitle, "用户标题")
    }

    @MainActor
    func testExplicitLocaleSelectsResourceBundle() {
        for (key, chinese) in [
            ("session.tool_approval", "工具审批"),
            ("calendar.title", "日历"),
            ("settings.left_features", "左侧功能"),
            ("calendar.no_reminders_due_today", "今天没有到期的待办"),
            ("translation.configure_translation_services", "配置翻译服务")
        ] {
            XCTAssertNotEqual(AppLocalization.string(key, locale: Locale(identifier: "en")), key)
            XCTAssertEqual(AppLocalization.string(key, locale: Locale(identifier: "zh-Hans")), chinese)
        }
        XCTAssertEqual(AppLocalization.string("settings.language", locale: Locale(identifier: "en")), "Language")
        XCTAssertEqual(AppLocalization.string("settings.language", locale: Locale(identifier: "zh-Hans")), "语言")
        XCTAssertEqual(AppLocalization.string("session.tool_approval", locale: Locale(identifier: "en")), "Tool approval")
        XCTAssertEqual(AppLocalization.string("calendar.title", locale: Locale(identifier: "ja")), "Calendar")
    }

    @MainActor
    func testLocalizedFormattingKeepsDynamicValues() {
        XCTAssertEqual(
            AppLocalization.format("calendar.all_day_2", "我的日历", locale: Locale(identifier: "en")),
            "All day · 我的日历"
        )
        XCTAssertEqual(
            AppLocalization.format("%@ reminders missing", "42", locale: Locale(identifier: "en")),
            "42 reminders missing"
        )
    }

    @MainActor
    func testUnknownContentRemainsVerbatim() {
        let text = "用户自定义内容 🐱 %@"
        XCTAssertEqual(AppLocalization.string(text, locale: Locale(identifier: "en")), text)
    }

    func testLocalizationCatalogsHaveMatchingKeysAndFormatArguments() throws {
        let englishURL = try XCTUnwrap(Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "en"))
        let chineseURL = try XCTUnwrap(Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "zh-Hans"))
        let english = try XCTUnwrap(NSDictionary(contentsOf: englishURL) as? [String: String])
        let chinese = try XCTUnwrap(NSDictionary(contentsOf: chineseURL) as? [String: String])
        XCTAssertEqual(Set(english.keys), Set(chinese.keys))
        let pattern = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:lld|ld|d|u|@|(?:\.\d+)?f)"#)
        for (key, value) in english {
            XCTAssertNotNil(key.range(of: #"^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$"#, options: .regularExpression), key)
            let chineseValue = try XCTUnwrap(chinese[key])
            let source = pattern.matches(in: chineseValue, range: NSRange(chineseValue.startIndex..., in: chineseValue)).map { String(chineseValue[Range($0.range, in: chineseValue)!]) }
            let target = pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { String(value[Range($0.range, in: value)!]) }
            XCTAssertEqual(source.sorted(), target.sorted(), key)
        }
    }
}
