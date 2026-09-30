import Foundation

enum TranslationCopyFormat: String, CaseIterable, Identifiable {
    case camel, pascal, snake, kebab, constant
    var id: String { rawValue }
    var title: String {
        switch self {
        case .camel: return "小驼峰命名"
        case .pascal: return "大驼峰命名"
        case .snake: return "下划线命名"
        case .kebab: return "短横线命名"
        case .constant: return "常量命名"
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
