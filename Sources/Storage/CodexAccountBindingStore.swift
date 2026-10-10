import Foundation

/// Shared list order is independent of provider login and credential storage.
protocol AccountOrdering: Sendable {
    func reorder(_ ids: [UUID]) async throws
}

protocol AccountRemoving: Sendable {
    func removeAccount(_ id: UUID) async throws
}

protocol DemoAccountManaging: Sendable {
    func demoModeEnabled() async throws -> Bool
    func setDemoMode(_ enabled: Bool) async throws -> [ConnectedAccount]
    func addDemo(now: Date) async throws -> ConnectedAccount
    func refreshDemo(_ account: ConnectedAccount, now: Date) async throws -> ConnectedAccount
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
final class CodexAccountBindingStore: CodexAccountBinding, AccountOrdering, DemoAccountManaging, AccountRemoving {
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
        // Retain the exact references until all cleanup succeeds; restart retries them.
        for account in try await accountStore.load() where account.deletionPending == true {
            try await removeAccount(account.id)
        }
        for account in try await accountStore.load() { await cleanupRetiredCredentials(account) }
        return try await accountStore.load()
    }

    private func cleanupRetiredCredentials(_ account: ConnectedAccount) async {
        guard let refs = account.retiredCredentialRefs, !refs.isEmpty else { return }
        do {
            for ref in refs where ref != account.credentialRef {
                try await vault.remove(for: .credential(ref))
            }
            try await accountStore.finishCredentialCleanup(refs, accountID: account.id)
        } catch {
            // The new connection is already durable. Retry cleanup on the next load.
        }
    }

    func removeAccount(_ id: UUID) async throws {
        guard let account = try await accountStore.markForDeletion(id) else { return }
        if !account.isDemo {
            if let transactionID = account.loginTransactionID {
                let transactions = CodexLoginTransactionStore(vault: vault)
                try await transactions.cancel(transactionID: transactionID)
                try await vault.remove(for: .loginTransaction(transactionID))
                try await transactions.remove(transactionID: transactionID)
            }
            for ref in (account.retiredCredentialRefs ?? []) + [account.credentialRef] {
                try await vault.remove(for: .credential(ref))
            }
        }
        try await accountStore.finishDeletion(id)
    }

    func reorder(_ ids: [UUID]) async throws {
        try await accountStore.reorder(ids)
    }

    func demoModeEnabled() async throws -> Bool { try await accountStore.demoModeEnabled() }
    func setDemoMode(_ enabled: Bool) async throws -> [ConnectedAccount] { try await accountStore.setDemoMode(enabled) }
    func addDemo(now: Date) async throws -> ConnectedAccount { try await accountStore.addDemo(now: now) }
    func refreshDemo(_ account: ConnectedAccount, now: Date) async throws -> ConnectedAccount {
        try await accountStore.refreshDemo(account, now: now)
    }

    func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount {
        try await save(login, transactionID: UUID())
    }

    func save(_ login: CodexVerifiedLogin, transactionID: UUID) async throws -> ConnectedAccount {
        try Task.checkCancellation()
        _ = try await load()
        let committed = try await commit(login, transactionID: transactionID)
        await cleanupRetiredCredentials(committed)
        return (try? await accountStore.load().first { $0.id == committed.id }) ?? committed
    }

    /// Commit verified identity and its credential in one persistence turn.
    @AccountPersistenceActor
    private func commit(_ login: CodexVerifiedLogin, transactionID: UUID) throws -> ConnectedAccount {
        try Task.checkCancellation()
        let existing = try accountStore.load()
        if let committed = existing.first(where: { $0.loginTransactionID == transactionID && $0.deletionPending != true }) {
            return committed
        }
        guard try !CodexLoginTransactionStore.isCancelled(transactionID, vault: vault) else { throw CancellationError() }

        let account = ConnectedAccount(
            remoteUserID: login.remoteUserID,
            verifiedEmail: login.email,
            scope: login.scope,
            credentialRef: UUID(),
            loginTransactionID: transactionID
        )
        let entry = CredentialVault.Entry.credential(account.credentialRef)
        try vault.save(login.credentials, for: entry)
        let committed: ConnectedAccount
        do {
            try Task.checkCancellation()
            committed = try accountStore.commitLogin(account)
        } catch {
            // This random reference belongs only to this attempted binding. Never
            // delete or replace an established account or a different payload.
            do {
                try vault.remove(ifMatching: login.credentials, for: entry)
            } catch {
                throw BindingError.credentialCleanupFailed
            }
            throw error
        }
        // Cancellation after the atomic commit cannot undo a successful login.
        return committed
    }
}
