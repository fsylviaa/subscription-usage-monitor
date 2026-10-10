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
    var generation: UInt64
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
        quotaState: AccountQuotaState = .notFetched
    ) {
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
