import Foundation

/// Pure wham/usage interpretation; no network, credentials, storage or current clock.
/// Field shape checked against the pinned CodexBar source documented in README.md.
struct CodexUsageParser {
    func parse(_ data: Data, for account: ConnectedAccount, observedAt: Date) throws -> CodexQuotaSnapshot {
        guard observedAt.timeIntervalSince1970.isFinite else {
            throw QuotaInterpretationError.invalidObservationTime
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        // No response identity is also a supported shape: the caller must have queried
        // the verified scope. Any explicitly returned conflicting identity is rejected.
        for returnedID in [response.accountID, response.accountIDCamel].compactMap({ $0 }) {
            guard returnedID == account.scope.remoteAccountID else {
                throw QuotaInterpretationError.accountMismatch
            }
        }

        var windows: [QuotaWindow: QuotaWindowSnapshot] = [:]
        for raw in [response.rateLimit?.primaryWindow, response.rateLimit?.secondaryWindow].compactMap({ $0 }) {
            guard let seconds = raw.seconds else { continue }
            guard seconds > 0 else { throw QuotaInterpretationError.invalidWindowLength }
            // Duration, not position or a plan name, identifies the two MVP windows.
            guard let window = QuotaWindow(rawValue: seconds) else { continue }
            guard windows[window] == nil else { throw QuotaInterpretationError.ambiguousWindow }

            let amount: QuotaAmount
            if let used = raw.usedPercent {
                amount = .limited(try QuotaPercentage(used: used))
            } else {
                amount = .unknown
            }
            let reset: Date?
            if let seconds = raw.resetAt {
                // Unix seconds. Zero/negative, fractional, milliseconds and unrepresentable
                // calendar dates are invalid, never coerced into plausible reset times.
                guard (1...253_402_300_799).contains(seconds) else {
                    throw QuotaInterpretationError.invalidResetTime
                }
                reset = Date(timeIntervalSince1970: Double(seconds))
            } else {
                reset = nil
            }
            windows[window] = QuotaWindowSnapshot(
                window: window, amount: amount, resetsAt: reset, observedAt: observedAt
            )
        }

        func snapshot(_ window: QuotaWindow) -> QuotaWindowSnapshot {
            windows[window] ?? QuotaWindowSnapshot(
                window: window, amount: .unknown, resetsAt: nil, observedAt: observedAt
            )
        }
        return CodexQuotaSnapshot(
            accountID: account.id, provider: account.provider, product: account.product,
            scope: account.scope, generation: account.generation,
            planType: response.planType, observedAt: observedAt,
            weekly: snapshot(.weekly), fiveHours: snapshot(.fiveHours)
        )
    }

    // Optional means missing/null, not malformed. Invalid known fields fail decoding;
    // callers can then preserve the previous successful snapshot and timestamp.
    // Extra model limits, credits (including credits.unlimited), balances and flags
    // such as allowed/limit_reached do not supply either subscription percentage.
    private struct Response: Decodable {
        let accountID: String?
        let accountIDCamel: String?
        let planType: String?
        let rateLimit: RateLimit?

        enum CodingKeys: String, CodingKey {
            case accountID = "account_id"
            case accountIDCamel = "accountId"
            case planType = "plan_type"
            case rateLimit = "rate_limit"
        }
    }

    private struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    private struct Window: Decodable {
        let usedPercent: Double?
        let resetAt: Int64?
        let seconds: Int?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case seconds = "limit_window_seconds"
        }
    }
}
