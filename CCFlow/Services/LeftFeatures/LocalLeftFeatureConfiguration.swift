import AppKit
import Carbon.HIToolbox
import Foundation

struct LocalLeftFeatureConfiguration: Decodable, Equatable {
    struct WebFeature: Decodable, Equatable {
        let id: String
        let name: String
        let url: String
        let icon: String?
        let enabled: Bool
        let keepsCrossDomainLoginInWebView: Bool
        let expandedPinned: Bool
        let shortcut: Shortcut?

        private enum CodingKeys: String, CodingKey {
            case id, name, url, icon, enabled, keepsCrossDomainLoginInWebView, expandedPinned, shortcut
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            url = try container.decode(String.self, forKey: .url)
            icon = try container.decodeIfPresent(String.self, forKey: .icon)
            enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
            keepsCrossDomainLoginInWebView = try container.decodeIfPresent(
                Bool.self,
                forKey: .keepsCrossDomainLoginInWebView
            ) ?? true
            expandedPinned = try container.decodeIfPresent(Bool.self, forKey: .expandedPinned) ?? false
            shortcut = try container.decodeIfPresent(Shortcut.self, forKey: .shortcut)
        }
    }

    struct Shortcut: Decodable, Equatable {
        let key: String
        let modifiers: [String]

        var globalShortcut: GlobalShortcut? {
            guard let keyCode = Self.keyCodes[key.lowercased()] else { return nil }
            let flags = modifiers.reduce(into: NSEvent.ModifierFlags()) { result, modifier in
                switch modifier.lowercased() {
                case "option", "alt": result.insert(.option)
                case "command", "cmd": result.insert(.command)
                case "control", "ctrl": result.insert(.control)
                case "shift": result.insert(.shift)
                default: break
                }
            }
            return GlobalShortcut(keyCode: keyCode, modifierFlags: flags)
        }

        private static let keyCodes: [String: UInt16] = [
            "a": UInt16(kVK_ANSI_A), "b": UInt16(kVK_ANSI_B), "c": UInt16(kVK_ANSI_C),
            "d": UInt16(kVK_ANSI_D), "e": UInt16(kVK_ANSI_E), "f": UInt16(kVK_ANSI_F),
            "g": UInt16(kVK_ANSI_G), "h": UInt16(kVK_ANSI_H), "i": UInt16(kVK_ANSI_I),
            "j": UInt16(kVK_ANSI_J), "k": UInt16(kVK_ANSI_K), "l": UInt16(kVK_ANSI_L),
            "m": UInt16(kVK_ANSI_M), "n": UInt16(kVK_ANSI_N), "o": UInt16(kVK_ANSI_O),
            "p": UInt16(kVK_ANSI_P), "q": UInt16(kVK_ANSI_Q), "r": UInt16(kVK_ANSI_R),
            "s": UInt16(kVK_ANSI_S), "t": UInt16(kVK_ANSI_T), "u": UInt16(kVK_ANSI_U),
            "v": UInt16(kVK_ANSI_V), "w": UInt16(kVK_ANSI_W), "x": UInt16(kVK_ANSI_X),
            "y": UInt16(kVK_ANSI_Y), "z": UInt16(kVK_ANSI_Z),
            "0": UInt16(kVK_ANSI_0), "1": UInt16(kVK_ANSI_1), "2": UInt16(kVK_ANSI_2),
            "3": UInt16(kVK_ANSI_3), "4": UInt16(kVK_ANSI_4), "5": UInt16(kVK_ANSI_5),
            "6": UInt16(kVK_ANSI_6), "7": UInt16(kVK_ANSI_7), "8": UInt16(kVK_ANSI_8),
            "9": UInt16(kVK_ANSI_9), "space": UInt16(kVK_Space)
        ]
    }

    let webFeatures: [WebFeature]

    func merging(into existingFeatures: [LeftFeature]) -> [LeftFeature] {
        var result = existingFeatures
        var nextSortOrder = (result.map(\.sortOrder).max() ?? -1) + 1

        for configured in webFeatures {
            guard Self.validIdentifier(configured.id), Self.validWebURL(configured.url) else { continue }
            let feature = LeftFeature(
                id: configured.id,
                kind: .webURL(url: configured.url),
                isEnabled: configured.enabled,
                sortOrder: result.first(where: { $0.id == configured.id })?.sortOrder ?? nextSortOrder,
                customIconName: configured.icon,
                customDisplayName: configured.name,
                keepsCrossDomainLoginInWebView: configured.keepsCrossDomainLoginInWebView,
                expandedPinned: configured.expandedPinned,
                globalShortcut: configured.shortcut?.globalShortcut
            )
            if let index = result.firstIndex(where: { $0.id == configured.id }) {
                result[index] = feature
            } else {
                result.append(feature)
                nextSortOrder += 1
            }
        }
        return result
    }

    static func load() -> LocalLeftFeatureConfiguration? {
        let environmentPath = Foundation.ProcessInfo.processInfo.environment["CC_FLOW_LEFT_FEATURES_CONFIG"]
        let environmentURL = environmentPath.map { URL(fileURLWithPath: $0) }
        let bundledURL = Bundle.main.url(forResource: "LeftFeatures.local", withExtension: "json")
        guard let url = environmentURL ?? bundledURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.")).contains($0)
        }
    }

    private static func validWebURL(_ value: String) -> Bool {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }
}
