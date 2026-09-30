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
    @MainActor
    func testExplicitLocaleSelectsResourceBundle() {
        for key in ["工具审批", "日历", "左侧功能", "今天没有到期的待办", "配置翻译服务"] {
            XCTAssertNotEqual(AppLocalization.string(key, locale: Locale(identifier: "en")), key)
            XCTAssertEqual(AppLocalization.string(key, locale: Locale(identifier: "zh-Hans")), key)
        }
        XCTAssertEqual(AppLocalization.string("工具审批", locale: Locale(identifier: "en")), "Tool approval")
        XCTAssertEqual(AppLocalization.string("日历", locale: Locale(identifier: "ja")), "Calendar")
    }

    @MainActor
    func testLocalizedFormattingKeepsDynamicValues() {
        XCTAssertEqual(
            AppLocalization.format("全天 · %@", "我的日历", locale: Locale(identifier: "en")),
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
            let source = pattern.matches(in: key, range: NSRange(key.startIndex..., in: key)).map { String(key[Range($0.range, in: key)!]) }
            let target = pattern.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { String(value[Range($0.range, in: value)!]) }
            XCTAssertEqual(source.sorted(), target.sorted(), key)
        }
    }
}
