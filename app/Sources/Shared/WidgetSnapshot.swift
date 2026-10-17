import Foundation

/// Display platform shared by App and widget (D-77). Only the name and the
/// primary window's label differ; layouts and colours are shared.
enum QuotaPlatform: String, Codable, Equatable, Sendable {
    case codex, cursor

    var displayName: String { self == .cursor ? "Cursor" : "Codex" }
    /// Codex's primary window is weekly; Cursor's is the billing month.
    var primaryWindowID: String { self == .cursor ? "monthly" : "weekly" }
    var primaryWindowTitle: String { self == .cursor ? "本月" : "每周" }
}

/// Display-only contract for the App and future Widget Extension. No account-store
/// record, remote scope, credential reference, or authentication payload crosses it.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let account: Account?
    var accounts: [Account]? = nil
    var listRevision: UUID? = nil

    var allAccounts: [Account] { accounts ?? account.map { [$0] } ?? [] }

    /// The card has no timestamps or countdowns. Keep freshness metadata on disk,
    /// but don't spend a timeline reload when every selectable card looks the same.
    func hasSameVisibleContent(as other: Self) -> Bool {
        schemaVersion == other.schemaVersion && allAccounts.elementsEqual(other.allAccounts) { lhs, rhs in
            lhs.id == rhs.id && lhs.identity == rhs.identity && lhs.plan == rhs.plan
                && lhs.resolvedPlatform == rhs.resolvedPlatform
                && lhs.isDemo == rhs.isDemo && lhs.state == rhs.state && lhs.failure == rhs.failure
                && lhs.weekly?.amount == rhs.weekly?.amount && lhs.fiveHours?.amount == rhs.fiveHours?.amount
                && lhs.fiveHours?.isApplicable == rhs.fiveHours?.isApplicable
                && lhs.grokBot?.amount == rhs.grokBot?.amount
        }
    }

    struct Account: Codable, Equatable, Sendable {
        let id: UUID
        let identity: String
        let plan: String?
        let isDemo: Bool
        let state: State
        let subscriptionObservedAt: Date?
        let quotaObservedAt: Date?
        let weekly: Window?
        let fiveHours: Window?
        var failure: Failure? = nil
        /// Nil in publications written before D-77, which were all Codex.
        var platform: QuotaPlatform? = nil
        /// Cursor's Grok Bot weekly row (D-80); nil hides the row.
        var grokBot: Window? = nil

        var resolvedPlatform: QuotaPlatform { platform ?? .codex }
    }

    enum Failure: String, Codable, Sendable {
        case refresh, networkBlocked

        func message(hasFetched: Bool) -> String {
            self == .networkBlocked ? "网络不达标，无法更新" : (hasFetched ? "刷新失败" : "获取失败")
        }
    }

    enum State: String, Codable, Sendable {
        case notFetched, notApplicable, available
    }

    struct Window: Codable, Equatable, Sendable {
        let amount: Amount
        let resetsAt: Date?
        let observedAt: Date
        var isApplicable: Bool? = nil

        var showsFiveHourLimit: Bool { isApplicable != false && amount != .unlimited }
    }

    enum Amount: Codable, Equatable, Sendable {
        case unknown
        case limited(usedPercent: Double)
        case unlimited

        var remainingPercent: Double? {
            guard case let .limited(used) = self else { return nil }
            return 100 - used
        }
    }

    static let empty = WidgetSnapshot(schemaVersion: 1, account: nil)

    /// Derived from this exact rendered identity, never the latest list index.
    /// The fingerprint prevents an old link from attaching to a different person.
    var clickTarget: URL {
        guard let account else { return URL(string: "subscriptionusage://quota")! }
        return WidgetQuotaRoute.url(accountID: account.id, identity: account.identity, isDemo: account.isDemo,
                                    platform: account.resolvedPlatform)
    }

    var emptyMessage: String? {
        guard let account else { return "添加账户" }
        return account.state == .notFetched ? "尚未获取额度" : nil
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw WidgetSnapshotStore.StoreError.unsupportedSchema }
        if let accounts {
            guard accounts.first == account, Set(accounts.map(\.id)).count == accounts.count else {
                throw WidgetSnapshotStore.StoreError.invalidSnapshot
            }
            for value in accounts {
                try WidgetSnapshot(schemaVersion: schemaVersion, account: value).validate()
            }
        }
        guard let account else { return }
        func validText(_ text: String) -> Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && text.utf8.count <= 1024
                && !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }
        func validDate(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite }
        if let grokBot = account.grokBot {
            guard account.resolvedPlatform == .cursor, case let .limited(used) = grokBot.amount,
                  used.isFinite, (0...100).contains(used), validDate(grokBot.observedAt),
                  grokBot.resetsAt.map({ (1...253_402_300_799).contains($0.timeIntervalSince1970) }) ?? true else {
                throw WidgetSnapshotStore.StoreError.invalidSnapshot
            }
        }
        guard validText(account.identity), account.plan.map(validText) ?? true,
              account.subscriptionObservedAt.map(validDate) ?? true else {
            throw WidgetSnapshotStore.StoreError.invalidSnapshot
        }
        switch account.state {
        case .notFetched, .notApplicable:
            guard account.weekly == nil, account.fiveHours == nil, account.quotaObservedAt == nil,
                  account.state != .notApplicable || (account.plan != nil && account.subscriptionObservedAt != nil) else {
                throw WidgetSnapshotStore.StoreError.invalidSnapshot
            }
        case .available:
            guard let time = account.quotaObservedAt, validDate(time),
                  let weekly = account.weekly, let fiveHours = account.fiveHours,
                  weekly.amount != .unknown || fiveHours.amount != .unknown else {
                throw WidgetSnapshotStore.StoreError.invalidSnapshot
            }
            guard weekly.isApplicable != false else { throw WidgetSnapshotStore.StoreError.invalidSnapshot }
            for window in [weekly, fiveHours] {
                guard window.observedAt == time,
                      window.isApplicable != false || (window == fiveHours && window.amount == .unknown && window.resetsAt == nil),
                      window.resetsAt.map({
                    $0.timeIntervalSince1970.isFinite && (1...253_402_300_799).contains($0.timeIntervalSince1970)
                }) ?? true else { throw WidgetSnapshotStore.StoreError.invalidSnapshot }
                if case let .limited(used) = window.amount, !used.isFinite || !(0...100).contains(used) {
                    throw WidgetSnapshotStore.StoreError.invalidSnapshot
                }
            }
        }
    }
}
