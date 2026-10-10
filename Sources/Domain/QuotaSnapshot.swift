import Foundation

/// A measured percentage, never a guessed default or a clamped invalid response.
struct QuotaPercentage: Equatable, Sendable {
    let used: Double

    init(used: Double) throws {
        guard used.isFinite, (0...100).contains(used) else {
            throw QuotaInterpretationError.invalidPercentage
        }
        self.used = used
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

enum QuotaAmount: Equatable, Sendable {
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

    /// Future UI: left is used, right is remaining. No bar for unknown/unlimited.
    var progress: QuotaProgress? {
        guard case let .limited(value) = self else { return nil }
        return QuotaProgress(usedFraction: value.used / 100, remainingFraction: value.remaining / 100)
    }
}

struct QuotaProgress: Equatable, Sendable {
    let usedFraction: Double
    let remainingFraction: Double
}

enum QuotaWindow: Int, Equatable, Sendable {
    case fiveHours = 18_000
    case weekly = 604_800
}

enum QuotaUnit: Equatable, Sendable {
    case percent
}

struct QuotaWindowSnapshot: Equatable, Sendable {
    let window: QuotaWindow
    let amount: QuotaAmount
    let resetsAt: Date?
    let observedAt: Date
    var unit: QuotaUnit { .percent }

    /// Crossing a reported reset point changes only freshness, never the measured amount.
    func isAwaitingUpdate(at date: Date) -> Bool {
        guard let resetsAt else { return false }
        return date >= resetsAt
    }
}

/// Pure interpretation result. T12 will connect successful results to storage.
/// Identity comes from the verified request context, not an untrusted response label.
struct CodexQuotaSnapshot: Equatable, Sendable {
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
}
