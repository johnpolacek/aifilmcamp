import FilmBrain
import Foundation
import Security

protocol ImageProviderCredentialStore: ImageProviderCredentialSource {
    func set(_ credential: String, providerID: String) async throws
    func remove(providerID: String) async throws
}

actor ImageProviderKeychain: ImageProviderCredentialStore {
    static let shared = ImageProviderKeychain()

    private let service = "com.aifilmcamp.image-provider-key.v1"

    func isConfigured(providerID: String) -> Bool {
        var query = baseQuery(providerID: providerID)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func credential(providerID: String) throws -> Data {
        var query = baseQuery(providerID: providerID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else {
            throw ImageProviderCredentialError.notConfigured
        }
        guard status == errSecSuccess else {
            throw ImageProviderCredentialError.keychainReadFailed(
                code: status,
                systemMessage: SecCopyErrorMessageString(status, nil) as String?
                    ?? "macOS did not provide an error description."
            )
        }
        guard let data = result as? Data, !data.isEmpty else {
            throw ImageProviderCredentialError.invalidStoredCredential
        }
        return data
    }

    func set(_ credential: String, providerID: String) throws {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= 16_384,
              !trimmed.contains("\n"), !trimmed.contains("\r")
        else { throw ImageProviderKeychainError.invalidCredential }
        let data = Data(trimmed.utf8)
        let query = baseQuery(providerID: providerID)
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw ImageProviderKeychainError.storageFailure(code: updateStatus)
        }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ImageProviderKeychainError.storageFailure(code: addStatus)
        }
    }

    func remove(providerID: String) throws {
        let status = SecItemDelete(baseQuery(providerID: providerID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ImageProviderKeychainError.storageFailure(code: status)
        }
    }

    private func baseQuery(providerID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: providerID,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }
}

enum ImageProviderKeychainError: LocalizedError {
    case invalidCredential
    case storageFailure(code: OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            "Enter a valid API key."
        case let .storageFailure(code):
            "Keychain could not update the API key (error \(code))."
        }
    }
}
