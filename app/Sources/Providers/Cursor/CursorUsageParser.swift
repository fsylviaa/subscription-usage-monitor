import Foundation

/// Pure interpretation of Cursor's `/api/auth/me` and `/api/usage-summary`
/// (field shape verified on device in T89). No network, credentials or clock.
///
/// Units: `*PercentUsed` are already percentages (0.36 means 0.36%, never ×100);
/// money fields are cents and are not shown in this release (D-77).
struct CursorUsageParser {
    struct Identity: Equatable, Sendable {
        let email: String
        /// Cursor's stable subject, e.g. `google-oauth2|…`; the account's remote user ID.
        let subject: String
    }

    enum Interpretation: Equatable, Sendable {
        case available(AccountSubscription, usedPercent: Double, resetsAt: Date?)
        /// Verified response without a personal plan quota (team, free without data…).
        case notApplicable(AccountSubscription)
    }

    enum ParseError: Error, Equatable {
        case malformed
        case missingQuota
        case invalidPercentage
    }

    func identity(_ data: Data) throws -> Identity {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = (root["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let subject = root["sub"] as? String,
              Self.validText(email), email.contains("@"), Self.validText(subject) else {
            throw ParseError.malformed
        }
        return Identity(email: email, subject: subject)
    }

    /// Missing values are never read as 0: an enabled plan without any usable
    /// percentage is a parse failure (the caller keeps the trusted old value).
    func interpret(_ data: Data, observedAt: Date) throws -> Interpretation {
        guard observedAt.timeIntervalSince1970.isFinite,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.malformed
        }
        let membership = (root["membershipType"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        // Internal only (plans are never displayed); a stable value keeps plan-change detection sane.
        let planType = membership.flatMap { Self.validText($0) ? $0 : nil } ?? "unknown"
        let subscription = AccountSubscription(planType: planType, observedAt: observedAt)
        guard subscription.isValid else { throw ParseError.malformed }

        // Team / enterprise quotas are out of scope for now (D-77): shown as “无适用额度”.
        let limitType = (root["limitType"] as? String)?.lowercased()
        if ["enterprise", "business", "team", "teams"].contains(planType.lowercased()) || limitType == "team" {
            return .notApplicable(subscription)
        }
        let individual = root["individualUsage"]
        guard let individualObject = individual as? [String: Any] else {
            if individual == nil || individual is NSNull { return .notApplicable(subscription) }
            throw ParseError.malformed
        }
        let planValue = individualObject["plan"]
        guard let plan = planValue as? [String: Any] else {
            if planValue == nil || planValue is NSNull { return .notApplicable(subscription) }
            throw ParseError.malformed
        }
        if Self.bool(plan["enabled"]) == false { return .notApplicable(subscription) }

        let used: Double
        if let total = Self.number(plan["totalPercentUsed"]) {
            used = try Self.clampedPercentage(total)
        } else if let usedCents = Self.number(plan["used"]), let limit = Self.number(plan["limit"]) {
            if limit == 0 { return .notApplicable(subscription) }
            guard limit > 0, usedCents >= 0 else { throw ParseError.invalidPercentage }
            used = try Self.clampedPercentage(usedCents / limit * 100)
        } else if Self.number(plan["limit"]) == 0 {
            return .notApplicable(subscription)
        } else {
            throw ParseError.missingQuota
        }
        let resetsAt = (root["billingCycleEnd"] as? String).flatMap(Self.date).flatMap { date in
            (1...253_402_300_799).contains(date.timeIntervalSince1970) ? date : nil
        }
        return .available(subscription, usedPercent: used, resetsAt: resetsAt)
    }

    /// Grok Bot weekly quota from `get-sand-usage-status` (field shape verified on device
    /// in T105). `usagePercent` is already a percentage. Plan names are never read (D-77).
    /// No included quota — including a free trial only — hides the row (D-80);
    /// a missing or invalid percentage is a failure, never 0 or full.
    func grokBot(_ data: Data, observedAt: Date) throws -> GrokBotQuota {
        guard observedAt.timeIntervalSince1970.isFinite,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.malformed
        }
        let included: Bool? = Self.bool(root["includedLimitZero"]).map { !$0 } ?? Self.bool(root["hasNonZeroIncludedLimit"])
        if included == false { return .notApplicable }
        guard let used = Self.number(root["usagePercent"]) else { throw ParseError.missingQuota }
        let resetsAt = (root["nextResetTimestampUtc"] as? String).flatMap(Self.date).flatMap { date in
            (1...253_402_300_799).contains(date.timeIntervalSince1970) ? date : nil
        }
        return try .available(used: try Self.clampedPercentage(used), resetsAt: resetsAt, observedAt: observedAt)
    }

    /// The single “本月” snapshot for a verified account and its request context.
    func snapshot(usedPercent: Double, resetsAt: Date?, subscription: AccountSubscription,
                  for account: ConnectedAccount) throws -> CodexQuotaSnapshot {
        CodexQuotaSnapshot(accountID: account.id, provider: account.provider, product: account.product,
            scope: account.scope, generation: account.generation, planType: subscription.planType,
            observedAt: subscription.observedAt,
            weekly: QuotaWindowSnapshot(window: .monthly, amount: .limited(try QuotaPercentage(used: usedPercent)),
                                        resetsAt: resetsAt, observedAt: subscription.observedAt),
            fiveHours: CodexQuotaSnapshot.absentFiveHours(observedAt: subscription.observedAt))
    }

    /// Used up with on-demand billing may exceed 100: shown truthfully as 0% remaining.
    private static func clampedPercentage(_ value: Double) throws -> Double {
        guard value.isFinite, value >= 0 else { throw ParseError.invalidPercentage }
        return min(value, 100)
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    private static func bool(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { return nil }
        return number.boolValue
    }

    private static func date(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    static func validText(_ text: String) -> Bool {
        !text.isEmpty && text.utf8.count <= 256
            && !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}
