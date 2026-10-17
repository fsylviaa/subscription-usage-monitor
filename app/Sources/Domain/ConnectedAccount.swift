import Foundation

/// Ordinary account metadata only. Authorization payloads belong in Keychain.
struct ConnectedAccount: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    let provider: ProviderID
    let product: ProductID
    var remoteUserID: String?
    var verifiedEmail: String?
    var displayName: String?
    var scope: AccountScope
    var credentialRef: UUID
    var loginTransactionID: UUID?
    /// Retired Keychain references remain durable until cleanup succeeds.
    var retiredCredentialRefs: [UUID]?
    var generation: UInt64
    var subscription: AccountSubscription?
    var quotaSnapshot: CodexQuotaSnapshot?
    /// Cursor only (D-80); nil until the first Grok Bot query succeeds.
    var grokBot: GrokBotQuota?
    /// OpenRouter / DeepSeek only (D-82): the trusted balance; nil until the first success.
    var balance: APIBalanceSnapshot?
    var deletionPending: Bool?
    var source: Source?
    enum Source: String, Codable, Sendable { case demo }
    var isDemo: Bool { source == .demo }
    var quotaState: AccountQuotaState

    init(
        id: UUID = UUID(),
        provider: ProviderID = .openAI,
        product: ProductID = .codexSubscription,
        remoteUserID: String? = nil,
        verifiedEmail: String? = nil,
        displayName: String? = nil,
        scope: AccountScope,
        credentialRef: UUID,
        generation: UInt64 = 0,
        quotaState: AccountQuotaState = .notFetched,
        quotaSnapshot: CodexQuotaSnapshot? = nil,
        subscription: AccountSubscription? = nil,
        loginTransactionID: UUID? = nil,
        source: Source? = nil
    ) {
        self.source = source
        self.loginTransactionID = loginTransactionID
        self.id = id
        self.provider = provider
        self.product = product
        self.remoteUserID = remoteUserID
        self.verifiedEmail = verifiedEmail
        self.displayName = displayName
        self.scope = scope
        self.credentialRef = credentialRef
        self.generation = generation
        self.quotaState = quotaState
        self.quotaSnapshot = quotaSnapshot
        self.subscription = subscription
    }
    func hasSameConnectionEmail(as other: ConnectedAccount) -> Bool {
        guard !isDemo, !other.isDemo, provider == other.provider, product == other.product,
              let email = verifiedEmail, let otherEmail = other.verifiedEmail,
              !email.isEmpty, !otherEmail.isEmpty else { return false }
        return email.caseInsensitiveCompare(otherEmail) == .orderedSame
    }
}

/// Platform-supplied text, independent of whether this product exposes an applicable quota.
struct AccountSubscription: Codable, Equatable, Sendable {
    let planType: String
    let observedAt: Date
    /// Optional verified inventory metadata, independent of subscription windows.
    /// Nil stays unknown in storage; only the detail presentation defaults it to 0.
    let resetCardCount: Int64?

    init(planType: String, observedAt: Date, resetCardCount: Int64? = nil) {
        self.planType = planType
        self.observedAt = observedAt
        self.resetCardCount = resetCardCount
    }

    var isValid: Bool {
        !planType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && planType.utf8.count <= 256
            && !planType.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            && observedAt.timeIntervalSince1970.isFinite
    }
}

// Platform identity comes from the connection that created the account; it is not a UI setting.
enum ProviderID: String, Codable, Sendable {
    case openAI = "openai"
    /// Cursor personal subscription (D-77).
    case cursor
    /// API balance platforms (D-82), connected with a pasted existing key.
    case openRouter = "openrouter"
    case deepSeek = "deepseek"
}

enum ProductID: String, Codable, Sendable {
    case codexSubscription
    case cursorSubscription
    case openRouterCredits
    case deepSeekBalance
}

extension ConnectedAccount {
    /// Display platform. Unknown pairs never occur: storage validates the pair.
    var platform: QuotaPlatform {
        switch provider {
        case .openAI: .codex
        case .cursor: .cursor
        case .openRouter: .openRouter
        case .deepSeek: .deepSeek
        }
    }
    /// Balance accounts have no quota window (D-82).
    var isBalance: Bool { platform.isBalance }
    /// The single primary window: weekly for Codex, the billing month for Cursor.
    var primaryWindow: QuotaWindow { platform == .cursor ? .monthly : .weekly }
    var hasKnownProductPair: Bool {
        switch (provider, product) {
        case (.openAI, .codexSubscription), (.cursor, .cursorSubscription),
             (.openRouter, .openRouterCredits), (.deepSeek, .deepSeekBalance): true
        default: false
        }
    }
    /// What stands where an e-mail would: the e-mail for subscriptions, the masked key
    /// (“sk-…a1b2”) for balance accounts, which have no e-mail (BAL-07).
    var identityText: String { verifiedEmail ?? displayName ?? remoteUserID ?? "\(platform.displayName) 账户" }
}

struct AccountScope: Codable, Equatable, Sendable {
    /// Codex's verified account_id used for ChatGPT-Account-Id, not the person's user ID.
    let remoteAccountID: String
    let kind: Kind
    var label: String?

    enum Kind: String, Codable, Sendable {
        case personal
        case workspace
    }
}
