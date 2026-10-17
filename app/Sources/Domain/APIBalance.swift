import Foundation
import CryptoKit

/// One currency of an API balance account (D-82). Amounts are exact decimals kept as
/// strings on disk; a missing part stays nil (unknown), never 0.
struct BalanceAmount: Codable, Equatable, Sendable {
    /// ISO-like code as returned by the platform, e.g. “USD”, “CNY”.
    let currency: String
    let total: Decimal
    /// DeepSeek only: 充值余额 / 赠送余额.
    var toppedUp: Decimal? = nil
    var granted: Decimal? = nil

    init(currency: String, total: Decimal, toppedUp: Decimal? = nil, granted: Decimal? = nil) {
        self.currency = currency; self.total = total; self.toppedUp = toppedUp; self.granted = granted
    }

    private enum CodingKeys: String, CodingKey { case currency, total, toppedUp, granted }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currency = try container.decode(String.self, forKey: .currency)
        total = try Self.decimal(container.decode(String.self, forKey: .total))
        toppedUp = try container.decodeIfPresent(String.self, forKey: .toppedUp).map(Self.decimal)
        granted = try container.decodeIfPresent(String.self, forKey: .granted).map(Self.decimal)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(currency, forKey: .currency)
        try container.encode(Self.text(total), forKey: .total)
        try container.encodeIfPresent(toppedUp.map(Self.text), forKey: .toppedUp)
        try container.encodeIfPresent(granted.map(Self.text), forKey: .granted)
    }

    static let posix = Locale(identifier: "en_US_POSIX")

    /// Plain decimal text only (“-12.5”, “0.0001”); no exponent, grouping or spaces.
    static func decimal(_ text: String) throws -> Decimal {
        guard (1...64).contains(text.utf8.count),
              text.wholeMatch(of: /-?[0-9]+(\.[0-9]+)?/) != nil,
              let value = Decimal(string: text, locale: posix), !value.isNaN else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "invalid amount"))
        }
        return value
    }

    static func text(_ value: Decimal) -> String {
        var copy = value
        return NSDecimalString(&copy, posix)
    }

    /// “$12.34”, “¥0.00”, other codes as “EUR 5.00”: half-up to two decimals, no grouping (BAL-05).
    static func money(_ value: Decimal, currency: String) -> String {
        var input = value, rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        let negative = rounded < 0
        var plain = Self.text(negative ? -rounded : rounded)
        if !plain.contains(".") { plain += "." }
        let parts = plain.split(separator: ".", omittingEmptySubsequences: false)
        let digits = String(parts[0]) + "." + String(parts[1]).padding(toLength: 2, withPad: "0", startingAt: 0)
        let symbol = ["USD": "$", "CNY": "¥"][currency] ?? currency + " "
        return (negative ? "-" : "") + symbol + digits
    }

    var totalText: String { Self.money(total, currency: currency) }

    var isValid: Bool {
        currency.utf8.count == 3 && currency.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) })
            && [total, toppedUp, granted].allSatisfy { $0.map { !$0.isNaN } ?? true }
    }
}

/// A balance observation persisted only after a gated, successful query.
/// No window, percentage or reset time exists for balances (BAL-05).
struct APIBalanceSnapshot: Codable, Equatable, Sendable {
    /// One row per currency, in the platform's order; never empty.
    let amounts: [BalanceAmount]
    let observedAt: Date

    var isValid: Bool {
        !amounts.isEmpty && amounts.count <= 8 && amounts.allSatisfy(\.isValid)
            && Set(amounts.map(\.currency)).count == amounts.count
            && observedAt.timeIntervalSince1970.isFinite && observedAt.timeIntervalSince1970 > 0
    }
}

/// A pasted API key held in memory only until it is verified and saved to Keychain.
/// Never printed: description and reflection are redacted.
struct APIKeyCredential: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let key: String

    /// Surrounding whitespace / newlines from pasting are dropped; anything else must be a
    /// plain printable token (no spaces), so it can only ever form one Bearer header.
    init?(pasted: String) {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...512).contains(trimmed.utf8.count),
              trimmed.utf8.allSatisfy({ (33...126).contains($0) }) else { return nil }
        key = trimmed
    }

    init(payload: CredentialPayload) throws {
        guard let text = String(data: payload.data, encoding: .utf8), let value = Self(pasted: text),
              value.key == text else { throw CodexQuotaError.failed }
        self = value
    }

    var payload: CredentialPayload { CredentialPayload(data: Data(key.utf8)) }

    /// Same key on the same platform → same account (BAL-07). Hash only; the key never
    /// enters the account file.
    func fingerprint(for provider: ProviderID) -> String {
        "keyfp:" + SHA256.hash(data: Data("\(provider.rawValue):\(key)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Shown where an e-mail would be: “sk-…a1b2” (last four only).
    var masked: String {
        (key.hasPrefix("sk-") ? "sk-" : "") + "…" + key.suffix(4)
    }

    var description: String { "APIKeyCredential(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

/// What a verified key connection hands to storage: never the raw key in a plain field.
struct APIBalanceVerifiedLogin: Sendable {
    let provider: ProviderID
    let credential: APIKeyCredential
    let balance: APIBalanceSnapshot
}
