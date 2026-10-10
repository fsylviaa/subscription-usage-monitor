import Foundation

protocol CodexAccountBinding: Sendable {
    func load() async throws -> [ConnectedAccount]
    func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount
}

/// Accepts the verifier's result type only. Raw tokens and decoded claims never
/// enter the account store through this boundary.
@MainActor
final class CodexAccountBindingStore: CodexAccountBinding {
    enum BindingError: Error, Equatable {
        case credentialCleanupFailed
    }

    private let accountStore: AccountStore
    private let vault: CredentialVault

    init(accountStore: AccountStore, vault: CredentialVault) {
        self.accountStore = accountStore
        self.vault = vault
    }

    static func applicationStore() throws -> CodexAccountBindingStore {
        CodexAccountBindingStore(
            accountStore: try .applicationStore(),
            vault: .applicationVault()
        )
    }

    func load() async throws -> [ConnectedAccount] {
        try await accountStore.load()
    }

    func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount {
        try Task.checkCancellation()
        // Fail before creating a credential when an established account already
        // exists. The atomic first-append check below also covers a competing save.
        guard try await accountStore.load().isEmpty else {
            throw AccountStore.StoreError.accountAlreadyExists
        }
        try Task.checkCancellation()

        let account = ConnectedAccount(
            remoteUserID: login.remoteUserID,
            verifiedEmail: login.email,
            scope: login.scope,
            credentialRef: UUID()
        )
        let entry = CredentialVault.Entry.credential(account.credentialRef)
        try await vault.save(login.credentials, for: entry)
        do {
            try Task.checkCancellation()
            try await accountStore.appendFirstUnlessCancelled(account)
        } catch {
            // This random reference belongs only to this attempted binding. Never
            // delete or replace an established account or a different payload.
            do {
                try await vault.remove(ifMatching: login.credentials, for: entry)
            } catch {
                throw BindingError.credentialCleanupFailed
            }
            throw error
        }
        // Do not check cancellation after commit: the account is already durable.
        // The coordinator can dismiss UI, but must retain this successful binding.
        return account
    }
}
