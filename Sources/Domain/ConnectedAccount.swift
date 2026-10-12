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

// Only the current MVP product is implemented; platform identity is not a UI setting.
enum ProviderID: String, Codable, Sendable {
    case openAI = "openai"
}

enum ProductID: String, Codable, Sendable {
    case codexSubscription
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
