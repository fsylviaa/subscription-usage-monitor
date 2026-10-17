import Foundation
import WidgetKit

/// One executor for account files and Keychain commits. No network work runs here.
@globalActor
actor AccountPersistenceActor {
    static let shared = AccountPersistenceActor()
}

/// One instance per App, assembled at the App boundary when login is connected.
/// Each mutation reads the last committed file, then replaces the whole document atomically.
/// The actor serializes local calls; a stable file lease also serializes both processes.
@AccountPersistenceActor
final class AccountStore {
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
        // Failure is separate from trusted measurements and their success times.
        var quotaFailures: [UUID: WidgetSnapshot.Failure]? = nil
    }

    private var needsInitialTimelineRequest: Bool
    private let legacyURL: URL?
    private var transactionDepth = 0
    private var transactionLease: SharedFileLease?
    private let fileURL: URL
    private let widgetStore: WidgetSnapshotStore?
    private let reloadWidgets: @Sendable () -> Void
    private(set) var widgetPublicationFailed = false

    /// Explicit URL keeps test data isolated from the App's real account directory.
    nonisolated init(fileURL: URL, legacyURL: URL? = nil, widgetStore: WidgetSnapshotStore? = nil,
                     requestInitialTimeline: Bool = false,
                     reloadWidgets: @escaping @Sendable () -> Void = {}) {
        self.needsInitialTimelineRequest = requestInitialTimeline
        self.legacyURL = legacyURL
        self.fileURL = fileURL
        self.widgetStore = widgetStore
        self.reloadWidgets = reloadWidgets
    }

    nonisolated static func applicationStore() throws -> AccountStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("SubscriptionUsage", isDirectory: true)
        return AccountStore(fileURL: try sharedFileURL(), legacyURL: directory.appendingPathComponent("accounts.json"),
                            widgetStore: .appGroupStore(), requestInitialTimeline: true, reloadWidgets: { WidgetPublicationRequests.shared.changed() })
    }

    nonisolated static func sharedFileURL() throws -> URL {
        try WidgetSnapshotStore.sharedDirectory().deletingLastPathComponent()
            .appendingPathComponent("Accounts/accounts.json")
    }

    nonisolated static func widgetAccountStore() throws -> AccountStore {
        let url = try sharedFileURL()
        // Only the App migrates. An extension launched before that must retain
        // the existing display publication, not publish a fabricated empty list.
        guard FileManager.default.fileExists(atPath: url.path) else { throw StoreError.accountNotFound }
        return AccountStore(fileURL: url, widgetStore: .appGroupStore())
    }

    nonisolated func queryLockURL(for id: UUID) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("query-\(id).lock")
    }

    private func beginTransaction() throws {
        if transactionDepth == 0 {
            transactionLease = try SharedFileLease(url: fileURL.appendingPathExtension("lock"))
        }
        transactionDepth += 1
    }
    private func endTransaction() {
        transactionDepth -= 1
        if transactionDepth == 0 { transactionLease = nil }
    }

    func load() throws -> [ConnectedAccount] {
        try beginTransaction()
        defer { endTransaction() }
        let document = try readDocument()
        let accounts = document.accounts
        // Repairs a missed publication after interruption without changing success times.
        publishWidget(accounts, failures: document.quotaFailures ?? [:])
        // A cold launch/upgrade also wakes widgets whose previous timeline used
        // .never, even when the saved visible data has not changed.
        if needsInitialTimelineRequest { requestWidgetReload() }
        return accounts
    }

    func quotaFailure(for id: UUID) throws -> WidgetSnapshot.Failure? {
        try beginTransaction()
        defer { endTransaction() }
        return try readDocument().quotaFailures?[id]
    }

    private func publishWidget(_ accounts: [ConnectedAccount], failures: [UUID: WidgetSnapshot.Failure]) {
        guard let widgetStore else { return }
        do {
            let previous = try? widgetStore.read()
            var snapshot = WidgetSnapshot.projecting(accounts, failures: failures)
            if snapshot.account != nil {
                snapshot.listRevision = previous?.allAccounts.map(\.id) == snapshot.allAccounts.map(\.id)
                    ? (previous?.listRevision ?? UUID()) : UUID()
            }
            if previous != snapshot {
                try widgetStore.write(snapshot)
                if previous?.hasSameVisibleContent(as: snapshot) != true { requestWidgetReload() }
            }
            widgetPublicationFailed = false
        } catch {
            // The account commit may already be durable. Never report a login failure
            // that would roll back its Keychain entry. Retry from the next trusted load.
            widgetPublicationFailed = true
            // Avoid leaving a removed/replaced identity available to a fresh reader.
            try? widgetStore.remove()
            requestWidgetReload()
        }
    }

    private func requestWidgetReload() {
        needsInitialTimelineRequest = false
        reloadWidgets()
    }

    private func readDocument() throws -> Document {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch CocoaError.fileReadNoSuchFile {
            let document: Document
            if let legacyURL {
                // Only ENOENT is an empty installation. A protected/unreadable
                // legacy file must not be mistaken for no accounts during upgrade.
                let legacyData: Data?
                do { legacyData = try Data(contentsOf: legacyURL) }
                catch CocoaError.fileReadNoSuchFile { legacyData = nil }
                if let legacyData {
                    document = try JSONDecoder().decode(Document.self, from: legacyData)
                    guard document.schemaVersion == 1 else { throw StoreError.unsupportedSchemaVersion(document.schemaVersion) }
                    try validate(document.accounts)
                } else {
                    document = Document(schemaVersion: 1, accounts: [], demoEnabled: false)
                }
            } else {
                document = Document(schemaVersion: 1, accounts: [], demoEnabled: false)
            }
            if legacyURL != nil {
                try JSONEncoder().encode(document).write(to: fileURL,
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            return document
        }

        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1 else {
            throw StoreError.unsupportedSchemaVersion(document.schemaVersion)
        }
        try validate(document.accounts)
        return document
    }

    /// Raw metadata append is retained for isolated setup; verified login uses commitLogin.
    func append(_ account: ConnectedAccount) throws {
        try beginTransaction()
        defer { endTransaction() }
        var accounts = try load()
        accounts.append(account)
        try commit(accounts)
    }

    /// Cancellation is checked immediately before the atomic append. Existing
    /// rows and their order are retained in the same actor turn.
    func appendUnlessCancelled(_ account: ConnectedAccount) throws {
        try beginTransaction()
        defer { endTransaction() }
        try Task.checkCancellation()
        var accounts = try load()
        accounts.append(account)
        try Task.checkCancellation()
        try commit(accounts)
    }

    /// Called only after a verified login's fresh credential has been saved.
    /// Email matching and replacement share one actor turn and one atomic write.
    func commitLogin(_ incoming: ConnectedAccount) throws -> ConnectedAccount {
        try beginTransaction()
        defer { endTransaction() }
        try Task.checkCancellation()
        var accounts = try load()
        let matches = accounts.filter { $0.hasSameConnectionEmail(as: incoming) }
        guard let previous = matches.first else {
            accounts.append(incoming)
            try Task.checkCancellation()
            try commit(accounts)
            return incoming
        }
        guard matches.allSatisfy({ $0.deletionPending != true }), previous.generation < UInt64.max else {
            throw StoreError.staleQuotaContext
        }
        var replacement = previous
        replacement.remoteUserID = incoming.remoteUserID
        replacement.verifiedEmail = incoming.verifiedEmail
        replacement.scope = incoming.scope
        replacement.credentialRef = incoming.credentialRef
        replacement.loginTransactionID = incoming.loginTransactionID
        replacement.generation += 1
        replacement.retiredCredentialRefs = Array(Set(matches.flatMap {
            ($0.retiredCredentialRefs ?? []) + [$0.credentialRef]
        })).filter { $0 != incoming.credentialRef }
        let sameIdentity = previous.remoteUserID != nil
            && previous.remoteUserID == incoming.remoteUserID && previous.scope == incoming.scope
        if sameIdentity, let snapshot = previous.quotaSnapshot {
            // Rebind only the local generation; measurement and success time stay exact.
            replacement.quotaSnapshot = CodexQuotaSnapshot(accountID: previous.id,
                provider: previous.provider, product: previous.product, scope: incoming.scope,
                generation: replacement.generation, planType: snapshot.planType,
                observedAt: snapshot.observedAt, weekly: snapshot.weekly, fiveHours: snapshot.fiveHours)
        } else if !sameIdentity {
            replacement.subscription = nil
            replacement.quotaSnapshot = nil
            replacement.grokBot = nil
            replacement.quotaState = .notFetched
        }
        accounts = accounts.compactMap { account in
            if account.id == previous.id { return replacement }
            return account.hasSameConnectionEmail(as: incoming) ? nil : account
        }
        try Task.checkCancellation()
        try commit(accounts)
        return replacement
    }

    func finishCredentialCleanup(_ refs: [UUID], accountID: UUID) throws {
        try beginTransaction()
        defer { endTransaction() }
        var accounts = try load()
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        let remaining = (accounts[index].retiredCredentialRefs ?? []).filter { !refs.contains($0) }
        accounts[index].retiredCredentialRefs = remaining.isEmpty ? nil : remaining
        try commit(accounts)
    }

    /// Replaces only this local record, keeping its current position and every other record intact.
    func update(_ account: ConnectedAccount) throws {
        try beginTransaction()
        defer { endTransaction() }
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
        try beginTransaction()
        defer { endTransaction() }
        try Task.checkCancellation()
        var accounts = try load()
        guard let index = accounts.firstIndex(where: { $0.id == expected.id }) else {
            throw StoreError.accountNotFound
        }
        let current = accounts[index]
        guard Self.isCurrentBinding(current, expected),
              current.quotaSnapshot.map({ $0.observedAt <= snapshot.observedAt }) ?? true else {
            throw StoreError.staleQuotaContext
        }
        accounts[index].quotaSnapshot = snapshot
        accounts[index].quotaState = .available
        try Task.checkCancellation()
        try commit(accounts, clearingFailures: [expected.id])
        return accounts[index]
    }

    /// A failed query can only annotate the binding and observation it started with.
    /// It must not overwrite a newer success, a reconnected identity, or deletion.
    func saveQuotaFailure(_ failure: WidgetSnapshot.Failure, for expected: ConnectedAccount,
                          validateRequest: @Sendable () throws -> Void = {}) throws {
        try beginTransaction()
        defer { endTransaction() }
        try validateRequest()
        try Task.checkCancellation()
        let document = try readDocument()
        guard let current = document.accounts.first(where: { $0.id == expected.id }),
              Self.isCurrentBinding(current, expected),
              current.quotaSnapshot == expected.quotaSnapshot,
              current.subscription == expected.subscription,
              current.balance == expected.balance else { throw StoreError.staleQuotaContext }
        var failures = document.quotaFailures ?? [:]
        failures[expected.id] = failure
        try Task.checkCancellation()
        try commit(document.accounts, failures: failures)
    }

    private static func isCurrentBinding(_ current: ConnectedAccount, _ expected: ConnectedAccount) -> Bool {
        current.deletionPending != true && current.provider == expected.provider && current.product == expected.product
            && current.generation == expected.generation && current.scope == expected.scope
            && current.credentialRef == expected.credentialRef && current.remoteUserID == expected.remoteUserID
            && current.verifiedEmail == expected.verifiedEmail
    }

    /// Identity/version/deletion check and Keychain CAS execute without suspension.
    /// A failed cleanup may leave an old credential physically present; it still cannot renew.
    func replaceCredential(_ expectedPayload: CredentialPayload, with replacement: CredentialPayload,
                           for expected: ConnectedAccount, vault: CredentialVault) throws -> Bool {
        try beginTransaction()
        defer { endTransaction() }
        guard let current = try load().first(where: { $0.id == expected.id }),
              Self.isCurrentBinding(current, expected) else { throw StoreError.staleQuotaContext }
        return try vault.replace(ifMatching: expectedPayload, with: replacement,
                                 for: .credential(expected.credentialRef))
    }

    enum QuotaObservation: Sendable {
        case available(CodexQuotaSnapshot)
        case notApplicable
        case failed
    }

    /// Commit reliable subscription metadata even when quota interpretation fails.
    /// A plan change invalidates old quota; an ordinary same-plan failure preserves it.
    /// `grokBot`: nil leaves Grok Bot untouched (Codex); `.some(nil)` is a failed Grok Bot
    /// query that keeps its trusted old value and marks the account “刷新失败” (D-80).
    func saveObservation(_ subscription: AccountSubscription, quota: QuotaObservation,
                         grokBot: GrokBotQuota?? = nil,
                         for expected: ConnectedAccount,
                         validateRequest: @Sendable () throws -> Void = {}) throws -> ConnectedAccount {
        try beginTransaction()
        defer { endTransaction() }
        try validateRequest()
        try Task.checkCancellation()
        var accounts = try load()
        guard let index = accounts.firstIndex(where: { $0.id == expected.id }) else {
            throw StoreError.accountNotFound
        }
        var current = accounts[index]
        guard Self.isCurrentBinding(current, expected),
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
        if case let .some(.some(value)) = grokBot { current.grokBot = Self.newer(value, than: current.grokBot) }
        let grokBotFailed = grokBot.map { $0 == nil } ?? false
        accounts[index] = current
        try Task.checkCancellation()
        if case .failed = quota {
            var failures = try readDocument().quotaFailures ?? [:]
            failures[expected.id] = .refresh
            try commit(accounts, failures: failures)
        } else if grokBotFailed {
            var failures = try readDocument().quotaFailures ?? [:]
            failures[expected.id] = .refresh
            try commit(accounts, failures: failures)
        } else {
            try commit(accounts, clearingFailures: [expected.id])
        }
        return current
    }

    /// The monthly query failed but Grok Bot succeeded: save Grok Bot only and keep
    /// the account marked “刷新失败”; the monthly trusted value stays untouched (D-80).
    func saveGrokBot(_ value: GrokBotQuota, for expected: ConnectedAccount,
                     validateRequest: @Sendable () throws -> Void = {}) throws -> ConnectedAccount {
        try beginTransaction()
        defer { endTransaction() }
        try validateRequest()
        try Task.checkCancellation()
        let document = try readDocument()
        var accounts = document.accounts
        guard let index = accounts.firstIndex(where: { $0.id == expected.id }) else {
            throw StoreError.accountNotFound
        }
        guard Self.isCurrentBinding(accounts[index], expected), accounts[index].platform == .cursor,
              accounts[index].quotaSnapshot == expected.quotaSnapshot,
              accounts[index].subscription == expected.subscription else { throw StoreError.staleQuotaContext }
        accounts[index].grokBot = Self.newer(value, than: accounts[index].grokBot)
        var failures = document.quotaFailures ?? [:]
        failures[expected.id] = .refresh
        try Task.checkCancellation()
        try commit(accounts, failures: failures)
        return accounts[index]
    }

    /// An older Grok Bot result arriving late never replaces a newer success.
    private static func newer(_ value: GrokBotQuota, than current: GrokBotQuota?) -> GrokBotQuota {
        if let current, let old = current.window?.observedAt, let new = value.window?.observedAt, old > new { return current }
        return value
    }

    /// A verified key connection (D-82): the same key on the same platform (fingerprint)
    /// updates that account in place with the fresh balance; a different key appends.
    /// Called only after the key was saved under `incoming.credentialRef`.
    func commitBalanceLogin(_ incoming: ConnectedAccount) throws -> ConnectedAccount {
        try beginTransaction()
        defer { endTransaction() }
        try Task.checkCancellation()
        guard incoming.isBalance, !incoming.isDemo, incoming.balance != nil else { throw StoreError.invalidQuotaSnapshot }
        var accounts = try load()
        let matches = accounts.filter { Self.sameKey($0, incoming) }
        guard let previous = matches.first else {
            accounts.append(incoming)
            try Task.checkCancellation()
            try commit(accounts, clearingFailures: [incoming.id])
            return incoming
        }
        guard matches.allSatisfy({ $0.deletionPending != true }), previous.generation < UInt64.max else {
            throw StoreError.staleQuotaContext
        }
        var replacement = previous
        replacement.displayName = incoming.displayName
        replacement.credentialRef = incoming.credentialRef
        replacement.generation += 1
        replacement.retiredCredentialRefs = Array(Set(matches.flatMap {
            ($0.retiredCredentialRefs ?? []) + [$0.credentialRef]
        })).filter { $0 != incoming.credentialRef }
        replacement.balance = incoming.balance
        replacement.quotaState = .available
        accounts = accounts.compactMap { account in
            if account.id == previous.id { return replacement }
            return Self.sameKey(account, incoming) ? nil : account
        }
        try Task.checkCancellation()
        try commit(accounts, clearingFailures: [previous.id])
        return replacement
    }

    private static func sameKey(_ account: ConnectedAccount, _ incoming: ConnectedAccount) -> Bool {
        !account.isDemo && account.provider == incoming.provider && account.product == incoming.product
            && account.remoteUserID != nil && account.remoteUserID == incoming.remoteUserID
    }

    /// Commits a balance only to the binding that began the request; an older result
    /// arriving late never replaces a newer one.
    func saveBalance(_ balance: APIBalanceSnapshot, for expected: ConnectedAccount,
                     validateRequest: @Sendable () throws -> Void = {}) throws -> ConnectedAccount {
        try beginTransaction()
        defer { endTransaction() }
        try validateRequest()
        try Task.checkCancellation()
        var accounts = try load()
        guard let index = accounts.firstIndex(where: { $0.id == expected.id }) else {
            throw StoreError.accountNotFound
        }
        let current = accounts[index]
        guard current.isBalance, balance.isValid, Self.isCurrentBinding(current, expected),
              current.balance.map({ $0.observedAt <= balance.observedAt }) ?? true else {
            throw StoreError.staleQuotaContext
        }
        accounts[index].balance = balance
        accounts[index].quotaState = .available
        try Task.checkCancellation()
        try commit(accounts, clearingFailures: [expected.id])
        return accounts[index]
    }

    /// Requires an exact permutation: sorting cannot silently add, remove or duplicate accounts.
    func reorder(_ ids: [UUID]) throws {
        try beginTransaction()
        defer { endTransaction() }
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
            guard account.hasKnownProductPair else { throw StoreError.invalidQuotaSnapshot }
            // Balance accounts (D-82) carry only a balance; subscriptions never carry one.
            if account.isBalance {
                guard account.quotaSnapshot == nil, account.subscription == nil, account.grokBot == nil,
                      account.verifiedEmail == nil, account.displayName.map({ !$0.isEmpty && $0.utf8.count <= 64 }) == true,
                      account.isDemo || account.remoteUserID?.hasPrefix("keyfp:") == true,
                      account.balance.map(\.isValid) ?? true,
                      account.quotaState == (account.balance == nil ? .notFetched : .available) else {
                    throw StoreError.invalidQuotaSnapshot
                }
                continue
            }
            guard account.balance == nil else { throw StoreError.invalidQuotaSnapshot }
            guard account.subscription?.isValid ?? true else { throw StoreError.invalidQuotaSnapshot }
            if let grokBot = account.grokBot, account.platform != .cursor || !grokBot.isValid {
                throw StoreError.invalidQuotaSnapshot
            }
            guard let quota = account.quotaSnapshot else {
                guard account.quotaState == .notFetched
                    || (account.quotaState == .notApplicable && account.subscription != nil) else {
                    throw StoreError.invalidQuotaSnapshot
                }
                continue
            }
            guard quota.weekly.hasValidApplicability, quota.fiveHours.hasValidApplicability,
                  account.quotaState == .available, quota.hasKnownQuota,
                  account.subscription.map({ $0.planType == quota.planType && $0.observedAt >= quota.observedAt }) ?? true,
                  quota.accountID == account.id, quota.provider == account.provider,
                  quota.product == account.product, quota.scope == account.scope,
                  quota.generation == account.generation,
                  quota.observedAt.timeIntervalSince1970.isFinite,
                  quota.weekly.window == account.primaryWindow, quota.fiveHours.window == .fiveHours,
                  account.platform == .codex || quota.fiveHours.isApplicable == false,
                  [quota.weekly, quota.fiveHours].allSatisfy({
                      $0.observedAt == quota.observedAt && ($0.resetsAt.map {
                          $0.timeIntervalSince1970.isFinite && (1...253_402_300_799).contains($0.timeIntervalSince1970)
                      } ?? true)
                  }) else { throw StoreError.invalidQuotaSnapshot }
        }
    }

    func markForDeletion(_ id: UUID) throws -> ConnectedAccount? {
        try beginTransaction()
        defer { endTransaction() }
        var accounts = try load()
        guard let index = accounts.firstIndex(where: { $0.id == id }) else { return nil }
        accounts[index].deletionPending = true
        try commit(accounts)
        return accounts[index]
    }

    func finishDeletion(_ id: UUID) throws {
        try beginTransaction()
        defer { endTransaction() }
        let accounts = try load()
        guard let account = accounts.first(where: { $0.id == id }) else { return }
        guard account.deletionPending == true else { throw StoreError.staleQuotaContext }
        try commit(accounts.filter { $0.id != id })
    }

    func demoModeEnabled() throws -> Bool {
        try beginTransaction()
        defer { endTransaction() }
        return try readDocument().demoEnabled ?? false
    }

    func setDemoMode(_ enabled: Bool) throws -> [ConnectedAccount] {
        try beginTransaction()
        defer { endTransaction() }
        var accounts = try load().filter { enabled || !$0.isDemo }
        // Turning the switch on provides one Cursor sample (D-77) besides the
        // Codex samples added from the connection entry; it never duplicates.
        if enabled, !accounts.contains(where: { $0.isDemo && $0.platform == .cursor }) {
            accounts.append(try demoSnapshot(Self.newDemo(platform: .cursor), now: Date(), used: 42))
        }
        // One sample per API balance platform (D-82, BAL-11), local amounts only.
        for platform in [QuotaPlatform.openRouter, .deepSeek]
        where enabled && !accounts.contains(where: { $0.isDemo && $0.platform == platform }) {
            accounts.append(try demoSnapshot(Self.newDemo(platform: platform), now: Date(), used: 0))
        }
        // Mode and cleanup commit together: a crash cannot leave disabled samples behind.
        try commit(accounts, demoEnabled: enabled)
        return accounts
    }

    private static func newDemo(platform: QuotaPlatform) -> ConnectedAccount {
        let id = UUID()
        let suffix = id.uuidString.prefix(6).lowercased()
        if platform.isBalance {
            let provider: ProviderID = platform == .openRouter ? .openRouter : .deepSeek
            return ConnectedAccount(id: id, provider: provider,
                product: platform == .openRouter ? .openRouterCredits : .deepSeekBalance,
                displayName: "sk-…" + suffix.suffix(4),
                scope: .init(remoteAccountID: "demo-\(id)", kind: .personal), credentialRef: UUID(), source: .demo)
        }
        return ConnectedAccount(id: id, provider: platform == .cursor ? .cursor : .openAI,
            product: platform == .cursor ? .cursorSubscription : .codexSubscription,
            verifiedEmail: "demo-\(suffix)@example.invalid",
            scope: .init(remoteAccountID: "demo-\(id)", kind: .personal), credentialRef: UUID(), source: .demo)
    }

    func addDemo(now: Date) throws -> ConnectedAccount {
        try beginTransaction()
        defer { endTransaction() }
        guard try demoModeEnabled() else { throw StoreError.accountNotFound }
        var account = Self.newDemo(platform: .codex)
        let count = try load().filter { $0.isDemo && $0.platform == .codex }.count
        account = try demoSnapshot(account, now: now, used: Double((count * 17 + 13) % 80))
        try append(account)
        return account
    }

    func refreshDemo(_ expected: ConnectedAccount, now: Date) throws -> ConnectedAccount {
        try beginTransaction()
        defer { endTransaction() }
        try Task.checkCancellation()
        guard expected.isDemo, try demoModeEnabled(),
              let account = try load().first(where: { $0.id == expected.id && $0.isDemo }) else {
            throw StoreError.accountNotFound
        }
        let used = ((account.quotaSnapshot?.weekly.amount.usedPercent ?? 0) + 7).truncatingRemainder(dividingBy: 95)
        var updated = try demoSnapshot(account, now: now, used: used)
        if account.isBalance, let old = account.balance?.amounts.first {
            // Simulated spending: each refresh lowers the sample, then starts over.
            let spent = old.total - Decimal(string: "1.37")!
            updated = try demoSnapshot(account, now: now, used: 0, total: spent < 0 ? nil : spent)
        }
        try update(updated)
        return updated
    }

    private func demoSnapshot(_ account: ConnectedAccount, now: Date, used: Double,
                              total: Decimal? = nil) throws -> ConnectedAccount {
        var result = account
        if account.isBalance {
            // Local sample amounts only; never a real query or a key.
            result.quotaState = .available
            if account.platform == .openRouter {
                result.balance = APIBalanceSnapshot(amounts: [BalanceAmount(currency: "USD",
                    total: total ?? Decimal(string: "18.42")!)], observedAt: now)
            } else {
                let value = total ?? Decimal(string: "56.80")!
                let granted = min(value, Decimal(string: "6.80")!)
                result.balance = APIBalanceSnapshot(amounts: [BalanceAmount(currency: "CNY", total: value,
                    toppedUp: value - granted, granted: granted)], observedAt: now)
            }
            return result
        }
        if account.platform == .cursor {
            // Local sample only: “本月” plus Grok Bot, no five-hour limit.
            result.subscription = .init(planType: "pro", observedAt: now)
            result.quotaState = .available
            result.quotaSnapshot = CodexQuotaSnapshot(accountID: account.id, provider: account.provider,
                product: account.product, scope: account.scope, generation: account.generation,
                planType: "pro", observedAt: now,
                weekly: .init(window: .monthly, amount: .limited(try .init(used: used)),
                    resetsAt: now.addingTimeInterval(18 * 86400), observedAt: now),
                fiveHours: CodexQuotaSnapshot.absentFiveHours(observedAt: now))
            // Local sample of the Grok Bot weekly row (D-80); no real query or notification.
            result.grokBot = try .available(used: (used + 33).truncatingRemainder(dividingBy: 100),
                                            resetsAt: now.addingTimeInterval(3 * 86400), observedAt: now)
            return result
        }
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

    private func commit(_ accounts: [ConnectedAccount], demoEnabled: Bool? = nil,
                        failures: [UUID: WidgetSnapshot.Failure]? = nil,
                        clearingFailures: Set<UUID> = []) throws {
        try validate(accounts)
        let previous = try readDocument()
        let retainedFailures = (failures ?? previous.quotaFailures ?? [:]).filter { id, _ in
            guard !clearingFailures.contains(id),
                  let current = accounts.first(where: { $0.id == id && $0.deletionPending != true }),
                  let old = previous.accounts.first(where: { $0.id == id }),
                  Self.isCurrentBinding(current, old) else { return false }
            return failures != nil || (current.quotaSnapshot == old.quotaSnapshot && current.subscription == old.subscription
                && current.balance == old.balance)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Document(schemaVersion: 1, accounts: accounts, demoEnabled: demoEnabled ?? previous.demoEnabled, quotaFailures: retainedFailures.isEmpty ? nil : retainedFailures))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Failure propagates; there is no optimistic cache or success timestamp to roll back.
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        publishWidget(accounts, failures: retainedFailures)
    }
}
