import Foundation

enum TranslationCopyFormat: String, CaseIterable, Identifiable {
    case camel, pascal, snake, kebab, constant
    var id: String { rawValue }
    var title: String {
        switch self {
        case .camel: return AppLocalization.runtimeString("translation.camelcase")
        case .pascal: return AppLocalization.runtimeString("translation.pascalcase")
        case .snake: return AppLocalization.runtimeString("translation.snake_case")
        case .kebab: return AppLocalization.runtimeString("translation.kebab_case")
        case .constant: return AppLocalization.runtimeString("translation.constant_case")
        }
    }
    var example: String { convert("How are you") }
    static func supports(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.letters.contains($0) }
            && text.unicodeScalars.allSatisfy { !CharacterSet.letters.contains($0) || $0.isASCII }
    }
    func convert(_ text: String) -> String {
        let separated = text
            .replacingOccurrences(of: "([A-Z]+)([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
        let words = separated.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.map { $0.lowercased() }
        func upperFirst(_ word: String) -> String { word.prefix(1).uppercased() + word.dropFirst() }
        switch self {
        case .camel: return (words.first ?? "") + words.dropFirst().map(upperFirst).joined()
        case .pascal: return words.map(upperFirst).joined()
        case .snake: return words.joined(separator: "_")
        case .kebab: return words.joined(separator: "-")
        case .constant: return words.joined(separator: "_").uppercased()
        }
    }
}
