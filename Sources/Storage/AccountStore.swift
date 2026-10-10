import Foundation

/// One instance per App, assembled at the App boundary when login is connected.
/// Each mutation reads the last committed file, then replaces the whole document atomically.
/// Methods have no suspension points, so read-modify-write stays serialized by this actor.
actor AccountStore {
    enum StoreError: Error, Equatable {
        case unsupportedSchemaVersion(Int)
        case duplicateLocalID
        case accountNotFound
        case accountAlreadyExists
        case invalidOrder
        case staleQuotaContext
        case invalidQuotaSnapshot
    }

    private struct Document: Codable {
        let schemaVersion: Int
        /// Array position is the single source of list order; no competing displayOrder field.
        var accounts: [ConnectedAccount]
    }

    private let fileURL: URL

    /// Explicit URL keeps test data isolated from the App's real account directory.
    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func applicationStore() throws -> AccountStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("SubscriptionUsage", isDirectory: true)
        return AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
    }

    func load() throws -> [ConnectedAccount] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }

        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1 else {
            throw StoreError.unsupportedSchemaVersion(document.schemaVersion)
        }
        try validate(document.accounts)
        return document.accounts
    }

    /// This is local-ID integrity, not email deduplication; successful-login merging belongs to T18/T20.
    func append(_ account: ConnectedAccount) throws {
        var accounts = try load()
        accounts.append(account)
        try commit(accounts)
    }

    /// T08 accepts only the initial binding. The check and atomic replacement share
    /// this actor turn, so two login completions cannot both create the first account.
    /// There is no suspension after the final cancellation check: starting commit
    /// is the save operation's linearization point.
    func appendFirstUnlessCancelled(_ account: ConnectedAccount) throws {
        try Task.checkCancellation()
        guard try load().isEmpty else { throw StoreError.accountAlreadyExists }
        try Task.checkCancellation()
        try commit([account])
    }

    /// Replaces only this local record, keeping its current position and every other record intact.
    func update(_ account: ConnectedAccount) throws {
        var accounts = try load()
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else {
            throw StoreError.accountNotFound
        }
        accounts[index] = account
        try commit(accounts)
    }

    /// Commits quota only to the same verified binding that began the request.
    /// No suspension between the identity check and atomic file replacement.
    func saveQuota(_ snapshot: CodexQuotaSnapshot, for expected: ConnectedAccount) throws -> ConnectedAccount {
        try Task.checkCancellation()
        var accounts = try load()
        guard let index = accounts.firstIndex(where: { $0.id == expected.id }) else {
            throw StoreError.accountNotFound
        }
        let current = accounts[index]
        guard current.provider == expected.provider, current.product == expected.product,
              current.generation == expected.generation, current.scope == expected.scope,
              current.credentialRef == expected.credentialRef,
              current.remoteUserID == expected.remoteUserID, current.verifiedEmail == expected.verifiedEmail,
              current.quotaSnapshot.map({ $0.observedAt <= snapshot.observedAt }) ?? true else {
            throw StoreError.staleQuotaContext
        }
        accounts[index].quotaSnapshot = snapshot
        accounts[index].quotaState = .available
        try Task.checkCancellation()
        try commit(accounts)
        return accounts[index]
    }

    /// Requires an exact permutation: sorting cannot silently add, remove or duplicate accounts.
    func reorder(_ ids: [UUID]) throws {
        let accounts = try load()
        guard ids.count == accounts.count, Set(ids) == Set(accounts.map(\.id)) else {
            throw StoreError.invalidOrder
        }
        let byID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        try commit(ids.compactMap { byID[$0] })
    }

    private func validate(_ accounts: [ConnectedAccount]) throws {
        guard Set(accounts.map(\.id)).count == accounts.count else {
            throw StoreError.duplicateLocalID
        }
        for account in accounts {
            guard let quota = account.quotaSnapshot else {
                guard account.quotaState == .notFetched else { throw StoreError.invalidQuotaSnapshot }
                continue
            }
            guard account.quotaState == .available, quota.hasKnownQuota,
                  quota.accountID == account.id, quota.provider == account.provider,
                  quota.product == account.product, quota.scope == account.scope,
                  quota.generation == account.generation,
                  quota.observedAt.timeIntervalSince1970.isFinite,
                  quota.weekly.window == .weekly, quota.fiveHours.window == .fiveHours,
                  [quota.weekly, quota.fiveHours].allSatisfy({
                      $0.observedAt == quota.observedAt && ($0.resetsAt.map {
                          $0.timeIntervalSince1970.isFinite && (1...253_402_300_799).contains($0.timeIntervalSince1970)
                      } ?? true)
                  }) else { throw StoreError.invalidQuotaSnapshot }
        }
    }

    private func commit(_ accounts: [ConnectedAccount]) throws {
        try validate(accounts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Document(schemaVersion: 1, accounts: accounts))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Failure propagates; there is no optimistic cache or success timestamp to roll back.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
