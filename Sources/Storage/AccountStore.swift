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
        var demoEnabled: Bool?
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

    func load() throws -> [ConnectedAccount] { try readDocument().accounts }

    private func readDocument() throws -> Document {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            return Document(schemaVersion: 1, accounts: [], demoEnabled: false)
        }

        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1 else {
            throw StoreError.unsupportedSchemaVersion(document.schemaVersion)
        }
        try validate(document.accounts)
        return document
    }

    /// This is local-ID integrity, not email deduplication; successful-login merging belongs to T18/T20.
    func append(_ account: ConnectedAccount) throws {
        var accounts = try load()
        accounts.append(account)
        try commit(accounts)
    }

    /// Cancellation is checked immediately before the atomic append. Existing
    /// rows and their order are retained in the same actor turn.
    func appendUnlessCancelled(_ account: ConnectedAccount) throws {
        try Task.checkCancellation()
        var accounts = try load()
        accounts.append(account)
        try Task.checkCancellation()
        try commit(accounts)
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
        guard current.deletionPending != true, current.provider == expected.provider, current.product == expected.product,
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

    enum QuotaObservation: Sendable {
        case available(CodexQuotaSnapshot)
        case notApplicable
        case failed
    }

    /// Commit reliable subscription metadata even when quota interpretation fails.
    /// A plan change invalidates old quota; an ordinary same-plan failure preserves it.
    func saveObservation(_ subscription: AccountSubscription, quota: QuotaObservation,
                         for expected: ConnectedAccount) throws -> ConnectedAccount {
        try Task.checkCancellation()
        var accounts = try load()
        guard let index = accounts.firstIndex(where: { $0.id == expected.id }) else {
            throw StoreError.accountNotFound
        }
        var current = accounts[index]
        guard current.deletionPending != true, current.provider == expected.provider, current.product == expected.product,
              current.generation == expected.generation, current.scope == expected.scope,
              current.credentialRef == expected.credentialRef,
              current.remoteUserID == expected.remoteUserID, current.verifiedEmail == expected.verifiedEmail,
              current.subscription.map({ $0.observedAt <= subscription.observedAt }) ?? true,
              current.quotaSnapshot.map({ $0.observedAt <= subscription.observedAt }) ?? true else {
            throw StoreError.staleQuotaContext
        }
        let previousPlan = current.subscription?.planType ?? current.quotaSnapshot?.planType
        if previousPlan != subscription.planType {
            current.quotaSnapshot = nil
            current.quotaState = .notFetched
        }
        current.subscription = subscription
        switch quota {
        case let .available(snapshot):
            guard snapshot.planType == subscription.planType, snapshot.observedAt == subscription.observedAt else {
                throw StoreError.invalidQuotaSnapshot
            }
            current.quotaSnapshot = snapshot
            current.quotaState = .available
        case .notApplicable:
            current.quotaSnapshot = nil
            current.quotaState = .notApplicable
        case .failed: break
        }
        accounts[index] = current
        try Task.checkCancellation()
        try commit(accounts)
        return current
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
            guard account.subscription?.isValid ?? true else { throw StoreError.invalidQuotaSnapshot }
            guard let quota = account.quotaSnapshot else {
                guard account.quotaState == .notFetched
                    || (account.quotaState == .notApplicable && account.subscription != nil) else {
                    throw StoreError.invalidQuotaSnapshot
                }
                continue
            }
            guard account.quotaState == .available, quota.hasKnownQuota,
                  account.subscription.map({ $0.planType == quota.planType && $0.observedAt >= quota.observedAt }) ?? true,
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

    func markForDeletion(_ id: UUID) throws -> ConnectedAccount? {
        var accounts = try load()
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return nil }
        accounts[index].deletionPending = true
        try commit(accounts)
        return accounts[index]
    }

    func finishDeletion(_ id: UUID) throws {
        let accounts = try load()
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        guard account.deletionPending == true else { throw StoreError.staleQuotaContext }
        try commit(accounts.filter { $0.id != id })
    }

    func demoModeEnabled() throws -> Bool { try readDocument().demoEnabled ?? false }

    func setDemoMode(_ enabled: Bool) throws -> [ConnectedAccount] {
        let accounts = try load().filter { enabled || !$0.isDemo }
        // Mode and cleanup commit together: a crash cannot leave disabled samples behind.
        try commit(accounts, demoEnabled: enabled)
        return accounts
    }

    func addDemo(now: Date) throws -> ConnectedAccount {
        guard try demoModeEnabled() else { throw StoreError.accountNotFound }
        let id = UUID()
        let suffix = id.uuidString.prefix(6).lowercased()
        var account = ConnectedAccount(id: id, verifiedEmail: "demo-\(suffix)@example.invalid",
            scope: .init(remoteAccountID: "demo-\(id)", kind: .personal), credentialRef: UUID(), source: .demo)
        let count = try load().filter(\.isDemo).count
        account = try demoSnapshot(account, now: now, used: Double((count * 17 + 13) % 80))
        try append(account)
        return account
    }

    func refreshDemo(_ expected: ConnectedAccount, now: Date) throws -> ConnectedAccount {
        try Task.checkCancellation()
        guard expected.isDemo, try demoModeEnabled(),
              let account = try load().first(where: { $0.id == expected.id && $0.isDemo }) else {
            throw StoreError.accountNotFound
        }
        let used = ((account.quotaSnapshot?.weekly.amount.usedPercent ?? 0) + 7).truncatingRemainder(dividingBy: 95)
        let updated = try demoSnapshot(account, now: now, used: used)
        try update(updated)
        return updated
    }

    private func demoSnapshot(_ account: ConnectedAccount, now: Date, used: Double) throws -> ConnectedAccount {
        var result = account
        result.subscription = .init(planType: "Plus", observedAt: now)
        result.quotaState = .available
        result.quotaSnapshot = CodexQuotaSnapshot(accountID: account.id, provider: account.provider,
            product: account.product, scope: account.scope, generation: account.generation,
            planType: "Plus", observedAt: now,
            weekly: .init(window: .weekly, amount: .limited(try .init(used: used)),
                resetsAt: now.addingTimeInterval(4 * 86400), observedAt: now),
            fiveHours: .init(window: .fiveHours, amount: .limited(try .init(used: (used + 23).truncatingRemainder(dividingBy: 100))),
                resetsAt: now.addingTimeInterval(3 * 3600), observedAt: now))
        return result
    }

    private func commit(_ accounts: [ConnectedAccount], demoEnabled: Bool? = nil) throws {
        try validate(accounts)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Document(schemaVersion: 1, accounts: accounts, demoEnabled: try demoEnabled ?? demoModeEnabled()))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Failure propagates; there is no optimistic cache or success timestamp to roll back.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
