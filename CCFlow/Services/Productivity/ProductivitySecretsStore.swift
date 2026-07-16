import Foundation
import Security

enum ProductivitySecret: String {
    case githubPAT = "github-pat"
    case openAIAPIKey = "openai-api-key"
    case browserPairingToken = "browser-pairing-token"
}

nonisolated struct ProductivitySecretsStore: Sendable {
    static let shared = ProductivitySecretsStore()
    private let service = "ai.ccflow.app.productivity"

    func set(_ value: String, for secret: ProductivitySecret) throws {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: secret.rawValue,
        ] as CFDictionary
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(query, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus)) }
        let status = SecItemAdd([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: secret.rawValue,
            kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ] as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    func value(for secret: ProductivitySecret) -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: secret.rawValue,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete(_ secret: ProductivitySecret) throws {
        let status = SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: secret.rawValue,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
