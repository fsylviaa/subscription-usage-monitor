import Foundation

/// A measured percentage, never a guessed default or a clamped invalid response.
struct QuotaPercentage: Codable, Equatable, Sendable {
    let used: Double

    init(used: Double) throws {
        guard used.isFinite, (0...100).contains(used) else {
            throw QuotaInterpretationError.invalidPercentage
        }
        self.used = used
    }

    private enum CodingKeys: String, CodingKey { case used }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(used: container.decode(Double.self, forKey: .used))
    }

    var remaining: Double { 100 - used }
}

enum QuotaInterpretationError: Error, Equatable {
    case invalidPercentage
    case invalidWindowLength
    case invalidResetTime
    case invalidObservationTime
    case accountMismatch
    case ambiguousWindow
}

enum QuotaAmount: Codable, Equatable, Sendable {
    case unknown
    case limited(QuotaPercentage)
    /// Only for explicit, verified unlimited semantics; absence never means unlimited.
    case unlimited

    var usedPercent: Double? {
        guard case let .limited(value) = self else { return nil }
        return value.used
    }

    var remainingPercent: Double? {
        guard case let .limited(value) = self else { return nil }
        return value.remaining
    }

    /// Both fractions retain their data meaning; renderers emphasize remaining.
    var progress: QuotaProgress? {
        guard case let .limited(value) = self else { return nil }
        return QuotaProgress(usedFraction: value.used / 100, remainingFraction: value.remaining / 100)
    }
}

struct QuotaProgress: Equatable, Sendable {
    let usedFraction: Double
    let remainingFraction: Double
}

enum QuotaWindow: Int, Codable, Equatable, Sendable {
    case fiveHours = 18_000
    case weekly = 604_800
    /// Cursor billing cycle (D-77). A negative tag, never a duration: Codex
    /// identifies windows by exact positive `limit_window_seconds`, and its
    /// 30-day free window must keep failing that lookup.
    case monthly = -1
}

enum QuotaUnit: Equatable, Sendable {
    case percent
}

struct QuotaWindowSnapshot: Codable, Equatable, Sendable {
    let window: QuotaWindow
    let amount: QuotaAmount
    let resetsAt: Date?
    let observedAt: Date
    /// nil preserves legacy / ambiguous missing data; false is verified absence.
    var isApplicable: Bool? = nil
    var unit: QuotaUnit { .percent }

    var hasValidApplicability: Bool {
        guard isApplicable == false else { return true }
        guard window == QuotaWindow.fiveHours else { return false }
        guard amount == QuotaAmount.unknown else { return false }
        return resetsAt == nil
    }

    var shouldDisplay: Bool {
        isApplicable != false && !(window == .fiveHours && amount == .unlimited)
    }

    /// Crossing a reported reset point changes only freshness, never the measured amount.
    func isAwaitingUpdate(at date: Date) -> Bool {
        guard let resetsAt else { return false }
        return date >= resetsAt
    }
}

/// A quota observation persisted only after a gated, successful query.
/// Identity comes from the verified request context, not an untrusted response label.
/// `weekly` is the primary window slot (stored key kept for upgrade compatibility):
/// a weekly window for Codex, the monthly billing window for Cursor. Cursor has no
/// five-hour limit, so its `fiveHours` slot is a verified-absent window.
struct CodexQuotaSnapshot: Codable, Equatable, Sendable {
    let accountID: UUID
    let provider: ProviderID
    let product: ProductID
    let scope: AccountScope
    let generation: UInt64
    let planType: String?
    let observedAt: Date
    let weekly: QuotaWindowSnapshot
    let fiveHours: QuotaWindowSnapshot

    /// Decoding an empty/partial response is not proof that a quota was obtained.
    /// T12 must check this before recording a successful quota query.
    var hasKnownQuota: Bool {
        [weekly, fiveHours].contains { $0.amount != .unknown }
    }

    var primary: QuotaWindowSnapshot { weekly }

    /// Cursor's fiveHours slot is always verified absent.
    static func absentFiveHours(observedAt: Date) -> QuotaWindowSnapshot {
        QuotaWindowSnapshot(window: .fiveHours, amount: .unknown, resetsAt: nil, observedAt: observedAt, isApplicable: false)
    }
}

/// Grok Bot weekly quota bundled with a Cursor subscription (D-80). Kept apart from
/// the monthly snapshot: its own applicability and its own last success time, so a
/// failure of one never overwrites the other. Nil on the account means never fetched.
struct GrokBotQuota: Codable, Equatable, Sendable {
    /// `.available` carries `window`; `.notApplicable` (no included quota, trial only) has none.
    let state: AccountQuotaState
    /// `observedAt` is this window's own last successful query.
    let window: QuotaWindowSnapshot?

    static let notApplicable = GrokBotQuota(state: .notApplicable, window: nil)

    static func available(used: Double, resetsAt: Date?, observedAt: Date) throws -> GrokBotQuota {
        GrokBotQuota(state: .available, window: QuotaWindowSnapshot(window: .weekly,
            amount: .limited(try QuotaPercentage(used: used)), resetsAt: resetsAt, observedAt: observedAt))
    }

    var isValid: Bool {
        switch state {
        case .notFetched: return false
        case .notApplicable: return window == nil
        case .available:
            guard let window, window.window == .weekly, window.isApplicable != false,
                  case .limited = window.amount, window.observedAt.timeIntervalSince1970.isFinite else { return false }
            return window.resetsAt.map { (1...253_402_300_799).contains($0.timeIntervalSince1970) } ?? true
        }
    }

    /// The value shown as the second row; nil hides the row.
    var displayed: QuotaWindowSnapshot? { state == .available ? window : nil }
}
