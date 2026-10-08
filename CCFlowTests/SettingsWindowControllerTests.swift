import AppKit
import Carbon.HIToolbox
import XCTest
@testable import CC_FLOW

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testFloatingPetGuidanceStringsMentionSecondaryClickToReopenSettings() {
        let zhHans = try! localizationFileContents(named: "zh-Hans")
        XCTAssertTrue(
            zhHans.contains("\"settings.after_entering_floating_pet_mode_right_click_the\" = \"进入独立悬浮宠物模式后，右键宠物形象可重新打开设置面板。\";")
        )
        XCTAssertTrue(
            zhHans.contains("\"settings.the_floating_pet_appears_near_the_bottom_right\" = \"独立悬浮宠物默认贴近当前激活窗口右下角显示。拖动后会记住新位置，右键宠物形象可重新打开设置面板。\";")
        )

        let english = try! localizationFileContents(named: "en")
        XCTAssertTrue(
            english.contains("\"settings.after_entering_floating_pet_mode_right_click_the\" = \"After entering floating pet mode, right-click the mascot to reopen the Settings panel.\";")
        )
        XCTAssertTrue(
            english.contains("\"settings.the_floating_pet_appears_near_the_bottom_right\" = \"The floating pet appears near the bottom-right corner of the active window by default. Dragging remembers the new position, and right-clicking the mascot reopens the Settings panel.\";")
        )
        XCTAssertTrue(
            zhHans.contains("\"island.drag_the_mascot_to_let_the_pet_work\" = \"拖动宠物，让宠物离岛工作\";")
        )
        XCTAssertTrue(
            english.contains("\"island.drag_the_mascot_to_let_the_pet_work\" = \"Drag the mascot to let the pet work away from the Island.\";")
        )
        XCTAssertTrue(
            zhHans.contains("\"common.notch_drag_guidance\" = \"刘海拖拽引导\";")
        )
        XCTAssertTrue(
            zhHans.contains("\"common.replay_the_notch_drag_hint_that_returning_users\" = \"重新演示老用户首次打开新版本时看到的刘海拖拽提示。\";")
        )
        XCTAssertTrue(
            zhHans.contains("\"common.replay\" = \"重新演示\";")
        )
        XCTAssertTrue(
            english.contains("\"common.notch_drag_guidance\" = \"Notch drag guidance\";")
        )
        XCTAssertTrue(
            english.contains("\"common.replay_the_notch_drag_hint_that_returning_users\" = \"Replay the notch drag hint that returning users see the first time they open the new version.\";")
        )
        XCTAssertTrue(
            english.contains("\"common.replay\" = \"Replay\";")
        )
        XCTAssertTrue(
            zhHans.contains("\"island.last_step_right_click_the_mascot\" = \"最后一步：右键宠物形象\";")
        )
        XCTAssertTrue(
            zhHans.contains("\"island.when_you_need_the_settings_panel_again_just\" = \"需要重新打开设置面板时，直接右键宠物形象就可以。\";")
        )
        XCTAssertTrue(
            english.contains("\"island.last_step_right_click_the_mascot\" = \"Last step: right-click the mascot\";")
        )
        XCTAssertTrue(
            english.contains("\"island.when_you_need_the_settings_panel_again_just\" = \"When you need the Settings panel again, just right-click the mascot.\";")
        )
        XCTAssertTrue(
            zhHans.contains("\"common.replay_first_run_onboarding\" = \"重新体验首次引导\";")
        )
        XCTAssertTrue(
            zhHans.contains("\"common.manually_open_the_surface_selection_onboarding_after_choosing\" = \"手动打开形态选择引导；选择刘海屏或独立悬浮宠物后，会继续进入 Hooks 演示。\";")
        )
        XCTAssertTrue(
            english.contains("\"common.replay_first_run_onboarding\" = \"Replay first-run onboarding\";")
        )
        XCTAssertTrue(
            english.contains("\"common.manually_open_the_surface_selection_onboarding_after_choosing\" = \"Manually open the surface selection onboarding. After choosing the top Island or floating pet, CC FLOW continues into the Hooks demo.\";")
        )
    }

    func testPresentReusesExistingWindowAndKeepsItVisible() throws {
        let controller = SettingsWindowController.shared
        controller.dismiss()

        controller.present()
        let window = try XCTUnwrap(controller.window)

        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.isMiniaturized)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertGreaterThan(window.level.rawValue, NSWindow.Level.statusBar.rawValue)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size.width, SettingsWindowDefaults.defaultContentSize.width)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size.height, SettingsWindowDefaults.defaultContentSize.height)

        controller.present()

        XCTAssertTrue(window.isVisible)
        XCTAssertIdentical(controller.window, window)
        XCTAssertFalse(window.isMiniaturized)

        controller.dismiss()
    }

    func testResetToDefaultContentSizeRestoresResizedSettingsWindow() throws {
        let controller = SettingsWindowController.shared
        controller.dismiss()
        defer { controller.dismiss() }

        controller.present()
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 1000, height: 600))

        controller.resetToDefaultContentSize()

        let contentSize = window.contentRect(forFrameRect: window.frame).size
        XCTAssertEqual(contentSize.width, SettingsWindowDefaults.defaultContentSize.width)
        XCTAssertEqual(contentSize.height, SettingsWindowDefaults.defaultContentSize.height)
    }

    func testSettingsWindowPublishesVisibilityChanges() {
        let controller = SettingsWindowController.shared
        controller.dismiss()

        var visibilityChanges: [Bool] = []
        let observer = NotificationCenter.default.addObserver(
            forName: .settingsWindowVisibilityDidChange,
            object: controller,
            queue: nil
        ) { notification in
            guard let isVisible = notification.userInfo?[SettingsWindowVisibilityNotification.isVisibleKey] as? Bool else {
                return
            }
            visibilityChanges.append(isVisible)
        }
        defer {
            NotificationCenter.default.removeObserver(observer)
            controller.dismiss()
        }

        controller.present()
        controller.dismiss()

        XCTAssertEqual(visibilityChanges, [true, false])
    }

    func testCommandWClosesSettingsWindow() throws {
        let controller = SettingsWindowController.shared
        controller.dismiss()

        controller.present()
        let window = try XCTUnwrap(controller.window)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_W)
        ))

        XCTAssertTrue(window.performKeyEquivalent(with: event))
        XCTAssertFalse(window.isVisible)
    }

    func testEscapeClosesSettingsWindow() throws {
        let controller = SettingsWindowController.shared
        controller.dismiss()

        controller.present()
        let window = try XCTUnwrap(controller.window)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: UInt16(kVK_Escape)
        ))

        XCTAssertTrue(window.performKeyEquivalent(with: event))
        XCTAssertFalse(window.isVisible)
    }

    func testPresentationModeWelcomeWindowStaysVisibleUntilCompleted() throws {
        let controller = PresentationModeWelcomeWindowController.shared
        controller.dismiss()

        controller.present { _ in }
        let window = try XCTUnwrap(controller.window)

        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(window.isMiniaturized)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size.width, 760)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size.height, 560)

        controller.dismiss()
    }

    private func localizationFileContents(named localeCode: String) throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = testsDirectory.deletingLastPathComponent()
        let fileURL = repoRoot
            .appendingPathComponent("CCFlow")
            .appendingPathComponent("Resources")
            .appendingPathComponent("\(localeCode).lproj")
            .appendingPathComponent("Localizable.strings")
        return try String(contentsOf: fileURL, encoding: .utf8)
    }
}
