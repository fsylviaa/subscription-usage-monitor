import Foundation
import Security

/// A complete encoded authorization package. Only the provider interprets its fields.
/// Deliberately not Codable: ordinary account files must retain only credentialRef.
struct CredentialPayload: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let data: Data

    init(data: Data) {
        self.data = data
    }

    var description: String { "CredentialPayload(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// One shared instance per App. Calls have no suspension points while touching Keychain.
/// No account metadata, file storage, logging, or automatic deletion on read failure.
@AccountPersistenceActor
final class CredentialVault {
    enum Entry: Sendable {
        case credential(UUID)
        case loginTransaction(UUID)

        fileprivate var namespace: String {
            switch self {
            case .credential: "credentials"
            case .loginTransaction: "login-transactions"
            }
        }

        fileprivate var id: UUID {
            switch self {
            case let .credential(id), let .loginTransaction(id): id
            }
        }
    }

    enum VaultError: Error, Equatable {
        case temporarilyUnavailable
        case keychainFailure(OSStatus)
        case invalidPayload
    }

    private let service: String
    private let client: any KeychainClient

    /// Tests supply a unique service and never access the production namespace.
    nonisolated init(service: String, client: any KeychainClient = SystemKeychainClient()) {
        self.service = service
        self.client = client
    }

    nonisolated static func applicationVault() -> CredentialVault {
        CredentialVault(service: "com.pbpuw6l86s.SubscriptionUsage.authorization")
    }

    /// nil means only errSecItemNotFound. Locked/unavailable storage must be retried.
    func load(for entry: Entry) throws -> CredentialPayload? {
        var query = query(for: entry)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = client.copyMatching(query)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data, !data.isEmpty else { throw VaultError.invalidPayload }
        return CredentialPayload(data: data)
    }

    /// Replaces the entire package in a single Keychain update, never delete then add.
    func save(_ payload: CredentialPayload, for entry: Entry) throws {
        guard !payload.data.isEmpty else { throw VaultError.invalidPayload }
        let query = query(for: entry)
        let attributes: [String: Any] = [
            kSecValueData as String: payload.data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = client.update(query, attributes: attributes)
        if updateStatus == errSecItemNotFound {
            let addStatus = client.add(query.merging(attributes) { _, new in new })
            if addStatus == errSecDuplicateItem {
                // Another vault instance inserted this exact item between update and add.
                try check(client.update(query, attributes: attributes))
            } else {
                try check(addStatus)
            }
        } else {
            try check(updateStatus)
        }
    }

    /// Exact item only. Already absent is success; all other failures remain retryable.
    func remove(for entry: Entry) throws {
        let status = client.delete(query(for: entry))
        if status != errSecItemNotFound { try check(status) }
    }

    /// Compare and remove without suspending between the read and delete. A cancelled
    /// transaction must not delete a replacement written by a newer attempt.
    func remove(ifMatching expected: CredentialPayload, for entry: Entry) throws {
        guard try load(for: entry) == expected else { return }
        try remove(for: entry)
    }

    /// The comparison and replacement run on this vault without suspension. A
    /// stage marker or cancellation must never overwrite a newer package.
    @discardableResult
    func replace(ifMatching expected: CredentialPayload?, with replacement: CredentialPayload,
                 for entry: Entry) throws -> Bool {
        guard try load(for: entry) == expected else { return false }
        try save(replacement, for: entry)
        return true
    }

    private func query(for entry: Entry) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(service).\(entry.namespace)",
            kSecAttrAccount as String: entry.id.uuidString,
            kSecAttrSynchronizable as String: false
        ]
    }

    private func check(_ status: OSStatus) throws {
        switch status {
        case errSecSuccess: return
        case errSecInteractionNotAllowed, errSecNotAvailable:
            throw VaultError.temporarilyUnavailable
        default:
            throw VaultError.keychainFailure(status)
        }
    }
}

/// Narrow synchronous boundary for injecting OS failures without accessing real accounts.
protocol KeychainClient: Sendable {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?)
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemKeychainClient: KeychainClient {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}
