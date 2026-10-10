import Foundation

/// A pending device authorization, never an authenticated account. Encode only into
/// the login-transaction Keychain slot; neither this package nor its codes are logs.
struct CodexDeviceAuthorization: Codable, Equatable, Sendable,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    static let verificationURL = URL(string: "https://auth.openai.com/codex/device")!
    static let maximumLifetime: TimeInterval = 15 * 60

    let transactionID: UUID
    let deviceAuthID: String
    let userCode: String
    let pollInterval: TimeInterval
    let startedAt: Date
    let expiresAt: Date

    var provider: ProviderID { .openAI }
    var product: ProductID { .codexSubscription }
    var clientID: String { Self.clientID }
    var verificationURL: URL { Self.verificationURL }

    init(transactionID: UUID = UUID(), deviceAuthID: String, userCode: String,
         pollInterval: TimeInterval, startedAt: Date) throws {
        // Do not assume a fixed code length not documented by the official protocol.
        // ASCII letters/digits and hyphens cover the human-entered code without
        // allowing whitespace, URL content, or invisible characters.
        guard (1...64).contains(userCode.utf8.count),
              userCode.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || $0 == 45 }),
              userCode.utf8.contains(where: { $0 != 45 }),
              (1...1024).contains(deviceAuthID.utf8.count),
              deviceAuthID.utf8.allSatisfy({ (33...126).contains($0) }),
              pollInterval.isFinite, pollInterval.rounded(.down) == pollInterval,
              (1...Self.maximumLifetime).contains(pollInterval),
              startedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw CodexDeviceAuthorizationError.invalidResponse
        }
        self.transactionID = transactionID
        self.deviceAuthID = deviceAuthID
        self.userCode = userCode
        self.pollInterval = pollInterval
        self.startedAt = startedAt
        // The snapshot does not return expires_in. Preserve this original client
        // deadline across encoding and browser round trips; never renew it on resume.
        self.expiresAt = startedAt.addingTimeInterval(Self.maximumLifetime)
    }

    func isExpired(at date: Date) -> Bool { date >= expiresAt }

    var description: String { "CodexDeviceAuthorization(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    private enum CodingKeys: String, CodingKey {
        case transactionID, deviceAuthID, userCode, pollInterval, startedAt, expiresAt
        case provider, product, clientID, verificationURL
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard try values.decode(ProviderID.self, forKey: .provider) == .openAI,
              try values.decode(ProductID.self, forKey: .product) == .codexSubscription,
              try values.decode(String.self, forKey: .clientID) == Self.clientID,
              try values.decode(URL.self, forKey: .verificationURL) == Self.verificationURL else {
            throw CodexDeviceAuthorizationError.invalidResponse
        }
        try self.init(
            transactionID: values.decode(UUID.self, forKey: .transactionID),
            deviceAuthID: values.decode(String.self, forKey: .deviceAuthID),
            userCode: values.decode(String.self, forKey: .userCode),
            pollInterval: values.decode(TimeInterval.self, forKey: .pollInterval),
            startedAt: values.decode(Date.self, forKey: .startedAt)
        )
        guard try values.decode(Date.self, forKey: .expiresAt) == expiresAt else {
            throw CodexDeviceAuthorizationError.invalidResponse
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(transactionID, forKey: .transactionID)
        try values.encode(deviceAuthID, forKey: .deviceAuthID)
        try values.encode(userCode, forKey: .userCode)
        try values.encode(pollInterval, forKey: .pollInterval)
        try values.encode(startedAt, forKey: .startedAt)
        try values.encode(expiresAt, forKey: .expiresAt)
        try values.encode(provider, forKey: .provider)
        try values.encode(product, forKey: .product)
        try values.encode(clientID, forKey: .clientID)
        try values.encode(verificationURL, forKey: .verificationURL)
    }
}

enum CodexDeviceAuthorizationError: Error, Equatable, Sendable {
    case unavailable
    case invalidResponse
    case requestFailed
    case timeout
    case expired
}

protocol CodexDeviceAuthorizing: Sendable {
    func requestAuthorization() async throws -> CodexDeviceAuthorization
}
