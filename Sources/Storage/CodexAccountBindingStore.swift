import Foundation

/// Shared list order is independent of provider login and credential storage.
protocol AccountOrdering: Sendable {
    func reorder(_ ids: [UUID]) async throws
}

protocol CodexAccountBinding: Sendable {
    func load() async throws -> [ConnectedAccount]
    func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount
    func save(_ login: CodexVerifiedLogin, transactionID: UUID) async throws -> ConnectedAccount
}

extension CodexAccountBinding {
    func save(_ login: CodexVerifiedLogin, transactionID: UUID) async throws -> ConnectedAccount {
        try await save(login)
    }
}

/// Accepts the verifier's result type only. Raw tokens and decoded claims never
/// enter the account store through this boundary.
@MainActor
final class CodexAccountBindingStore: CodexAccountBinding, AccountOrdering {
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

    func reorder(_ ids: [UUID]) async throws {
        try await accountStore.reorder(ids)
    }

    func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount {
        try await save(login, transactionID: UUID())
    }

    func save(_ login: CodexVerifiedLogin, transactionID: UUID) async throws -> ConnectedAccount {
        try Task.checkCancellation()
        let existing = try await accountStore.load()
        // A committed login can survive a crash before temporary cleanup.
        if let committed = existing.first(where: { $0.loginTransactionID == transactionID }) {
            return committed
        }
        try Task.checkCancellation()

        let account = ConnectedAccount(
            remoteUserID: login.remoteUserID,
            verifiedEmail: login.email,
            scope: login.scope,
            credentialRef: UUID(),
            loginTransactionID: transactionID
        )
        let entry = CredentialVault.Entry.credential(account.credentialRef)
        try await vault.save(login.credentials, for: entry)
        do {
            try Task.checkCancellation()
            try await accountStore.appendUnlessCancelled(account)
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
