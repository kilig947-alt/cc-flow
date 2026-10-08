import AppKit
import Carbon.HIToolbox

struct GlobalShortcut: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt16
    let modifierFlagsRawValue: UInt

    init?(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) {
        let sanitized = Self.sanitizedModifierFlags(modifierFlags)
        guard !sanitized.isEmpty else { return nil }

        self.keyCode = keyCode
        self.modifierFlagsRawValue = sanitized.rawValue
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    var displayParts: [String] {
        modifierSymbols + [keyDisplay]
    }

    var displayString: String {
        displayParts.joined(separator: " ")
    }

    var carbonModifierFlags: UInt32 {
        var flags: UInt32 = 0

        if modifierFlags.contains(.control) {
            flags |= UInt32(controlKey)
        }
        if modifierFlags.contains(.option) {
            flags |= UInt32(optionKey)
        }
        if modifierFlags.contains(.shift) {
            flags |= UInt32(shiftKey)
        }
        if modifierFlags.contains(.command) {
            flags |= UInt32(cmdKey)
        }

        return flags
    }

    private var modifierSymbols: [String] {
        var symbols: [String] = []

        if modifierFlags.contains(.control) {
            symbols.append("\u{2303}")
        }
        if modifierFlags.contains(.option) {
            symbols.append("\u{2325}")
        }
        if modifierFlags.contains(.shift) {
            symbols.append("\u{21E7}")
        }
        if modifierFlags.contains(.command) {
            symbols.append("\u{2318}")
        }

        return symbols
    }

    private var keyDisplay: String {
        if let keyDisplay = Self.keyDisplayMap[Int(keyCode)] {
            return keyDisplay
        }

        return "Key \(keyCode)"
    }

    private static func sanitizedModifierFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.control, .option, .shift, .command])
    }

    private static let keyDisplayMap: [Int: String] = [
        Int(kVK_ANSI_A): "A",
        Int(kVK_ANSI_B): "B",
        Int(kVK_ANSI_C): "C",
        Int(kVK_ANSI_D): "D",
        Int(kVK_ANSI_E): "E",
        Int(kVK_ANSI_F): "F",
        Int(kVK_ANSI_G): "G",
        Int(kVK_ANSI_H): "H",
        Int(kVK_ANSI_I): "I",
        Int(kVK_ANSI_J): "J",
        Int(kVK_ANSI_K): "K",
        Int(kVK_ANSI_L): "L",
        Int(kVK_ANSI_M): "M",
        Int(kVK_ANSI_N): "N",
        Int(kVK_ANSI_O): "O",
        Int(kVK_ANSI_P): "P",
        Int(kVK_ANSI_Q): "Q",
        Int(kVK_ANSI_R): "R",
        Int(kVK_ANSI_S): "S",
        Int(kVK_ANSI_T): "T",
        Int(kVK_ANSI_U): "U",
        Int(kVK_ANSI_V): "V",
        Int(kVK_ANSI_W): "W",
        Int(kVK_ANSI_X): "X",
        Int(kVK_ANSI_Y): "Y",
        Int(kVK_ANSI_Z): "Z",
        Int(kVK_ANSI_0): "0",
        Int(kVK_ANSI_1): "1",
        Int(kVK_ANSI_2): "2",
        Int(kVK_ANSI_3): "3",
        Int(kVK_ANSI_4): "4",
        Int(kVK_ANSI_5): "5",
        Int(kVK_ANSI_6): "6",
        Int(kVK_ANSI_7): "7",
        Int(kVK_ANSI_8): "8",
        Int(kVK_ANSI_9): "9",
        Int(kVK_ANSI_Minus): "-",
        Int(kVK_ANSI_Equal): "=",
        Int(kVK_ANSI_LeftBracket): "[",
        Int(kVK_ANSI_RightBracket): "]",
        Int(kVK_ANSI_Backslash): "\\",
        Int(kVK_ANSI_Semicolon): ";",
        Int(kVK_ANSI_Quote): "'",
        Int(kVK_ANSI_Comma): ",",
        Int(kVK_ANSI_Period): ".",
        Int(kVK_ANSI_Slash): "/",
        Int(kVK_ANSI_Grave): "`",
        Int(kVK_Space): "Space",
        Int(kVK_Return): "Return",
        Int(kVK_Tab): "Tab",
        Int(kVK_Delete): "Delete",
        Int(kVK_ForwardDelete): "Fn-Delete",
        Int(kVK_Escape): "Esc",
        Int(kVK_LeftArrow): "\u{2190}",
        Int(kVK_RightArrow): "\u{2192}",
        Int(kVK_UpArrow): "\u{2191}",
        Int(kVK_DownArrow): "\u{2193}",
        Int(kVK_Home): "Home",
        Int(kVK_End): "End",
        Int(kVK_PageUp): "Page Up",
        Int(kVK_PageDown): "Page Down",
        Int(kVK_F1): "F1",
        Int(kVK_F2): "F2",
        Int(kVK_F3): "F3",
        Int(kVK_F4): "F4",
        Int(kVK_F5): "F5",
        Int(kVK_F6): "F6",
        Int(kVK_F7): "F7",
        Int(kVK_F8): "F8",
        Int(kVK_F9): "F9",
        Int(kVK_F10): "F10",
        Int(kVK_F11): "F11",
        Int(kVK_F12): "F12"
    ]
}

enum GlobalShortcutAction: String, CaseIterable, Identifiable {
    case openActiveSession
    case openLeftFeature
    case openSessionList
    case giflowSelectionCapture
    case giflowFullScreenCapture
    case giflowOpenRecordings
    case translationSelection
    case translationScreenshot
    case translationInput

    var id: String { rawValue }

    var title: String {
        switch self {
        case .translationSelection: return AppLocalization.runtimeString("common.tflow_selection_translation")
        case .translationScreenshot: return AppLocalization.runtimeString("common.tflow_screenshot_translation")
        case .translationInput: return AppLocalization.runtimeString("common.tflow_input_translation")

        case .openActiveSession:
            return AppLocalization.runtimeString("common.show_active_session")
        case .openLeftFeature:
            return AppLocalization.runtimeString("common.open_left_features")
        case .openSessionList:
            return AppLocalization.runtimeString("common.show_session_list")
        case .giflowSelectionCapture:
            return AppLocalization.runtimeString("common.giflow_region_recording")
        case .giflowFullScreenCapture:
            return AppLocalization.runtimeString("common.giflow_full_screen_recording")
        case .giflowOpenRecordings:
            return AppLocalization.runtimeString("common.giflow_recordings")
        }
    }

    var shortTitle: String {
        switch self {
        case .translationSelection: return AppLocalization.runtimeString("common.translate_selection")
        case .translationScreenshot: return AppLocalization.runtimeString("common.translate_screenshot")
        case .translationInput: return AppLocalization.runtimeString("common.translate_input")

        case .openActiveSession:
            return AppLocalization.runtimeString("common.active_session")
        case .openLeftFeature:
            return AppLocalization.runtimeString("settings.left_features")
        case .openSessionList:
            return AppLocalization.runtimeString("common.session_list")
        case .giflowSelectionCapture:
            return AppLocalization.runtimeString("common.giflow_region")
        case .giflowFullScreenCapture:
            return AppLocalization.runtimeString("common.giflow_full_screen")
        case .giflowOpenRecordings:
            return AppLocalization.runtimeString("common.giflow_recordings_2")
        }
    }

    var subtitle: String {
        switch self {
        case .translationSelection: return AppLocalization.runtimeString("common.translate_selected_text_or_clipboard_text_images")
        case .translationScreenshot: return AppLocalization.runtimeString("common.select_a_screen_region_recognize_text_locally_and")
        case .translationInput: return AppLocalization.runtimeString("common.open_tflow_in_the_left_panel_and_focus")

        case .openActiveSession:
            return AppLocalization.runtimeString("common.open_the_most_relevant_active_or_attention_needed")
        case .openLeftFeature:
            return AppLocalization.runtimeString("common.open_the_most_recently_previewed_or_active_left")
        case .openSessionList:
            return AppLocalization.runtimeString("common.open_island_s_full_session_list_view")
        case .giflowSelectionCapture:
            return AppLocalization.runtimeString("common.drag_to_select_a_screen_region_to_record")
        case .giflowFullScreenCapture:
            return AppLocalization.runtimeString("common.record_the_full_screen_as_gif_press_again")
        case .giflowOpenRecordings:
            return AppLocalization.runtimeString("common.open_giflow_recording_history_in_island")
        }
    }

    var defaultShortcut: GlobalShortcut? {
        switch self {
        case .translationSelection: return GlobalShortcut(keyCode: UInt16(kVK_ANSI_D), modifierFlags: [.option])
        case .translationScreenshot: return GlobalShortcut(keyCode: UInt16(kVK_ANSI_S), modifierFlags: [.option])
        case .translationInput: return GlobalShortcut(keyCode: UInt16(kVK_ANSI_A), modifierFlags: [.option])

        case .openActiveSession:
            return GlobalShortcut(
                keyCode: UInt16(kVK_ANSI_J),
                modifierFlags: [.option]
            )
        case .openLeftFeature:
            return GlobalShortcut(
                keyCode: UInt16(kVK_ANSI_K),
                modifierFlags: [.option]
            )
        case .openSessionList:
            return GlobalShortcut(
                keyCode: UInt16(kVK_ANSI_L),
                modifierFlags: [.option]
            )
        case .giflowSelectionCapture:
            return GlobalShortcut(
                keyCode: UInt16(kVK_ANSI_5),
                modifierFlags: [.option]
            )
        case .giflowFullScreenCapture:
            return GlobalShortcut(
                keyCode: UInt16(kVK_ANSI_6),
                modifierFlags: [.option]
            )
        case .giflowOpenRecordings:
            return GlobalShortcut(
                keyCode: UInt16(kVK_ANSI_7),
                modifierFlags: [.option]
            )
        }
    }

    var legacyDefaultShortcuts: [GlobalShortcut] {
        switch self {
        case .translationSelection: return []
        case .translationScreenshot: return []
        case .translationInput: return []

        case .openActiveSession:
            return [
                GlobalShortcut(
                    keyCode: UInt16(kVK_ANSI_J),
                    modifierFlags: [.option, .command]
                ),
                GlobalShortcut(
                    keyCode: UInt16(kVK_ANSI_J),
                    modifierFlags: [.control, .option, .command]
                )
            ].compactMap { $0 }
        case .openLeftFeature:
            return [
                GlobalShortcut(
                    keyCode: UInt16(kVK_ANSI_K),
                    modifierFlags: [.option, .command]
                ),
                GlobalShortcut(
                    keyCode: UInt16(kVK_ANSI_K),
                    modifierFlags: [.control, .option, .command]
                )
            ].compactMap { $0 }
        case .openSessionList:
            return [
                GlobalShortcut(
                    keyCode: UInt16(kVK_ANSI_L),
                    modifierFlags: [.option, .command]
                ),
                GlobalShortcut(
                    keyCode: UInt16(kVK_ANSI_L),
                    modifierFlags: [.control, .option, .command]
                )
            ].compactMap { $0 }
        case .giflowSelectionCapture, .giflowFullScreenCapture, .giflowOpenRecordings:
            return []
        }
    }

    var carbonID: UInt32 {
        switch self {
        case .translationSelection: return 20
        case .translationScreenshot: return 21
        case .translationInput: return 22

        case .openActiveSession:
            return 1
        case .openLeftFeature:
            return 3
        case .openSessionList:
            return 2
        case .giflowSelectionCapture:
            return 10
        case .giflowFullScreenCapture:
            return 11
        case .giflowOpenRecordings:
            return 12
        }
    }
}
