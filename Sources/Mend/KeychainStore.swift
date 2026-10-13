import Foundation
import Security

enum KeychainError: LocalizedError, Equatable {
    case unexpectedStatus(OSStatus)
    /// The saved keys could not be read, so writing would replace keys that
    /// were never seen.
    case savedKeysUnreadable

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Couldn’t save the API key (Keychain error \(status))"
        case .savedKeysUnreadable:
            return "Couldn’t save the API key. Allow Keychain access when macOS asks"
        }
    }
}

/// What reading a Keychain item found.
enum KeychainRead: Equatable {
    case value(String)
    /// There is no such item.
    case missing
    /// The item could not be read, for example because the prompt was
    /// declined. It may well exist, so it must not be replaced or deleted.
    case unavailable
}

/// Reads and writes generic-password items. Saving an empty value deletes the item.
protocol KeychainAccess {
    func read(service: String, account: String) -> KeychainRead
    func save(_ value: String, service: String, account: String) throws
}

struct SystemKeychain: KeychainAccess {
    func read(service: String, account: String) -> KeychainRead {
        KeychainStore.read(service: service, account: account)
    }

    func save(_ value: String, service: String, account: String) throws {
        try KeychainStore.save(value, service: service, account: account)
    }
}

enum KeychainStore {
    static func read(service: String, account: String) -> KeychainRead {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                return .unavailable
            }
            return .value(value)
        case errSecItemNotFound:
            return .missing
        default:
            // Declined, cancelled, locked: anything but a definite "not there".
            return .unavailable
        }
    }

    static func save(_ value: String, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        if value.isEmpty {
            SecItemDelete(query as CFDictionary)
            return
        }

        let data = Data(value.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }
}
