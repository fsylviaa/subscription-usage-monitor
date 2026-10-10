import Foundation
import Security

/// This capability is only produced after both signed tokens and the live usage
/// endpoint agree on identity/scope. It contains secrets and must never be logged.
struct CodexVerifiedLogin: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let remoteUserID: String
    let email: String
    let scope: AccountScope
    let credentials: CredentialPayload

    fileprivate init(remoteUserID: String, email: String, scope: AccountScope, credentials: CredentialPayload) {
        self.remoteUserID = remoteUserID
        self.email = email
        self.scope = scope
        self.credentials = credentials
    }

    var description: String { "CodexVerifiedLogin(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }

    #if DEBUG
    /// Isolated test builds only; production has no unverified-binding factory.
    static func fixture(remoteUserID: String, email: String, scope: AccountScope,
                        credentials: CredentialPayload) -> Self {
        Self(remoteUserID: remoteUserID, email: email, scope: scope, credentials: credentials)
    }
    #endif
}

protocol CodexIdentityVerifying: Sendable {
    func verify(_ tokens: CodexTokenResponse) async throws -> CodexVerifiedLogin
}

/// Public discovery and JWKS were checked on 2026-10-10. No key or endpoint is
/// accepted from a JWT header. Security.framework performs the RS256 signature
/// verification; claims are not trusted merely because JSON decoding succeeded.
struct CodexIdentityVerifier: CodexIdentityVerifying {
    static let issuer = "https://auth.openai.com"
    static let jwksURL = URL(string: "https://auth.openai.com/.well-known/jwks.json")!
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    private let transport: any CodexDeviceAuthorizationTransport
    private let checkNetwork: @Sendable () async -> NetworkScoreResult
    private let now: @Sendable () -> Date

    init(transport: any CodexDeviceAuthorizationTransport = URLSessionCodexDeviceAuthorizationTransport(),
         checkNetwork: @escaping @Sendable () async -> NetworkScoreResult = { await NetworkScoreChecker().check() },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.checkNetwork = checkNetwork
        self.now = now
    }

    func verify(_ tokens: CodexTokenResponse) async throws -> CodexVerifiedLogin {
        var stage = "令牌结构"
        do {
            try Task.checkCancellation()
            guard Self.safeSecret(tokens.accessToken), Self.safeSecret(tokens.refreshToken),
                  Self.safeSecret(tokens.idToken), tokens.obtainedAt.timeIntervalSince1970.isFinite,
                  tokens.obtainedAt <= now().addingTimeInterval(5),
                  tokens.expiresAt.map({ $0.timeIntervalSince1970.isFinite && $0 > now() }) ?? true else {
                throw CodexLoginError.failed
            }
            let idJWT = try SignedJWT(tokens.idToken)
            let accessJWT = try SignedJWT(tokens.accessToken)
            stage = "公开签名公钥"
            let keys = try JSONDecoder().decode(JWKSet.self, from: await get(Self.jwksURL))
            // Fetch fresh public keys for this login; no stale key cache or token-URL lookup.
            stage = "身份令牌签名与时效"
            let id = try idJWT.verify(using: keys, now: now())
            stage = "访问令牌签名与时效"
            let access = try accessJWT.verify(using: keys, now: now())
            stage = "身份与授权对象"
            guard id.audiences.contains(CodexDeviceAuthorization.clientID),
                  id.authorizedParty == nil || id.authorizedParty == CodexDeviceAuthorization.clientID,
                  id.audiences.count == 1 || id.authorizedParty == CodexDeviceAuthorization.clientID,
                  access.audiences.contains("https://api.openai.com/v1"),
                  access.clientID == CodexDeviceAuthorization.clientID || access.authorizedParty == CodexDeviceAuthorization.clientID,
                  access.clientID == nil || access.clientID == CodexDeviceAuthorization.clientID,
                  access.authorizedParty == nil || access.authorizedParty == CodexDeviceAuthorization.clientID,
                  access.subject == id.subject,
                  let auth = id.auth, Self.safeIdentifier(auth.accountID),
                  let accountID = auth.accountID,
                  id.emailVerified != false, id.profile?.emailVerified != false,
                  let email = id.email ?? id.profile?.email, Self.safeEmail(email),
                  id.email == nil || id.profile?.email == nil || id.email == id.profile?.email else {
                throw CodexLoginError.failed
            }
            let remoteUserID = auth.userID ?? id.subject
            guard Self.safeIdentifier(remoteUserID),
                  auth.chatGPTUserID == nil || auth.legacyUserID == nil || auth.chatGPTUserID == auth.legacyUserID,
                  access.auth?.accountID == nil || access.auth?.accountID == accountID,
                  access.auth?.chatGPTUserID == nil || access.auth?.legacyUserID == nil
                    || access.auth?.chatGPTUserID == access.auth?.legacyUserID,
                  access.auth?.userID == nil || access.auth?.userID == remoteUserID else {
                throw CodexLoginError.failed
            }

            // A signed identity is not proof this credential can query this scope.
            // This request verifies only identity/scope; quota data is never published.
            stage = "查询前网络检查"
            let network = await checkNetwork()
            try Task.checkCancellation()
            switch network {
            case let .allowed(score) where score.isFinite && score > 50: break
            case .blocked: throw CodexLoginError.networkBlocked
            case .cancelled: throw CancellationError()
            case .unavailable: throw CodexLoginError.retryable
            default: throw CodexLoginError.failed
            }
            stage = "服务端作用域请求"
            let usage = try JSONDecoder().decode(UsageIdentity.self,
                from: await get(Self.usageURL, bearer: tokens.accessToken, accountID: accountID))
            stage = "服务端身份与作用域核对"
            guard usage.accountID == accountID,
                  usage.userID == nil || usage.userID == auth.userID,
                  usage.email == nil || usage.email?.lowercased() == email.lowercased() else {
                throw CodexLoginError.failed
            }
            try Task.checkCancellation()
            // A long verification must not publish a token that expired while waiting.
            stage = "保存前时效检查"
            _ = try idJWT.validateClaims(now: now())
            _ = try accessJWT.validateClaims(now: now())
            let scope = AccountScope(remoteAccountID: accountID,
                                     kind: ["team", "business", "enterprise", "edu"].contains(auth.planType ?? "") ? .workspace : .personal,
                                     label: nil)
            let package = CredentialPackage(credentialVersion: 1, issuer: Self.issuer,
                clientID: CodexDeviceAuthorization.clientID, subject: id.subject,
                remoteUserID: remoteUserID, scope: scope, tokens: tokens)
            return CodexVerifiedLogin(remoteUserID: remoteUserID, email: email, scope: scope,
                                      credentials: CredentialPayload(data: try JSONEncoder().encode(package)))
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            #if DEBUG
            // A fixed local stage name only, never a claim, key, URL, response or error.
            print("T08 | 身份核验未通过 | 阶段：\(stage)")
            #endif
            if let failure = error as? CodexLoginError { throw failure }
            if error is URLError { throw CodexLoginError.retryable }
            // Never surface server bodies, token claims, decoder descriptions or Sec errors.
            throw CodexLoginError.failed
        }
    }

    private func get(_ url: URL, bearer: String? = nil, accountID: String? = nil) async throws -> Data {
        try Task.checkCancellation()
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let accountID { request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id") }
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url == url else {
            throw CodexLoginError.failed
        }
        if http.statusCode == 429 || (500...599).contains(http.statusCode) {
            throw CodexLoginError.retryable
        }
        guard (200...299).contains(http.statusCode), !data.isEmpty, data.count <= 256 * 1024,
              http.mimeType?.lowercased().contains("html") != true else {
            throw CodexLoginError.failed
        }
        return data
    }

    private static func safeSecret(_ value: String) -> Bool {
        (1...64 * 1024).contains(value.utf8.count) && value.utf8.allSatisfy { (33...126).contains($0) }
    }

    fileprivate static func safeIdentifier(_ value: String?) -> Bool {
        guard let value else { return false }
        return (1...1024).contains(value.utf8.count) && value.utf8.allSatisfy { (33...126).contains($0) }
    }

    private static func safeEmail(_ value: String) -> Bool {
        // Preserve the issuer's spelling. Normalization for deduplication belongs to the store.
        value.utf8.count <= 320 && value.split(separator: "@", omittingEmptySubsequences: false).count == 2
            && !value.hasPrefix("@") && !value.hasSuffix("@")
            && value.unicodeScalars.allSatisfy { !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.controlCharacters.contains($0) }
    }

    private struct CredentialPackage: Encodable {
        let credentialVersion: Int
        let issuer: String
        let clientID: String
        let subject: String
        let remoteUserID: String
        let scope: AccountScope
        let tokens: CodexTokenResponse
    }

    private struct UsageIdentity: Decodable {
        let accountID: String
        let userID: String?
        let email: String?

        enum CodingKeys: String, CodingKey { case accountID = "account_id", accountIDCamel = "accountId", userID = "user_id", email }
        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let primary = try values.decodeIfPresent(String.self, forKey: .accountID)
            let alias = try values.decodeIfPresent(String.self, forKey: .accountIDCamel)
            guard let accountID = primary ?? alias,
                  primary == nil || alias == nil || primary == alias,
                  CodexIdentityVerifier.safeIdentifier(accountID) else { throw CodexLoginError.failed }
            self.accountID = accountID
            self.userID = try values.decodeIfPresent(String.self, forKey: .userID)
            self.email = try values.decodeIfPresent(String.self, forKey: .email)
        }
    }
}

private struct JWKSet: Decodable {
    let keys: [JWK]
}

private struct JWK: Decodable {
    let kty: String
    let kid: String
    let use: String?
    let alg: String?
    let n: String
    let e: String

    func publicKey() throws -> SecKey {
        guard kty == "RSA", use == nil || use == "sig", alg == nil || alg == "RS256",
              let modulus = base64URL(n), let exponent = base64URL(e),
              (256...1024).contains(modulus.count), (1...8).contains(exponent.count),
              modulus.first != 0, exponent.first != 0 else { throw CodexLoginError.failed }
        let der = derValue(0x30, derInteger(modulus) + derInteger(exponent))
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA,
                                           kSecAttrKeyClass: kSecAttrKeyClassPublic]
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil),
              SecKeyIsAlgorithmSupported(key, .verify, .rsaSignatureMessagePKCS1v15SHA256) else {
            throw CodexLoginError.failed
        }
        return key
    }
}

private struct SignedJWT {
    private let signedBytes: Data
    private let signature: Data
    private let claims: Claims
    private let keyID: String

    init(_ token: String) throws {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }),
              let headerData = base64URL(String(parts[0])),
              let claimsData = base64URL(String(parts[1])),
              let signature = base64URL(String(parts[2])) else { throw CodexLoginError.failed }
        let header = try JSONDecoder().decode(Header.self, from: headerData)
        guard header.alg == "RS256", CodexIdentityVerifier.safeIdentifier(header.kid),
              header.crit == nil || header.crit?.isEmpty == true else { throw CodexLoginError.failed }
        self.signedBytes = Data("\(parts[0]).\(parts[1])".utf8)
        self.signature = signature
        self.claims = try JSONDecoder().decode(Claims.self, from: claimsData)
        self.keyID = header.kid
    }

    func verify(using set: JWKSet, now: Date) throws -> Claims {
        let matching = set.keys.filter { $0.kid == keyID }
        guard matching.count == 1, let key = matching.first else { throw CodexLoginError.failed }
        let publicKey = try key.publicKey()
        guard SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                    signedBytes as CFData, signature as CFData, nil) else {
            throw CodexLoginError.failed
        }
        return try validateClaims(now: now)
    }

    func validateClaims(now: Date) throws -> Claims {
        let current = now.timeIntervalSince1970
        guard claims.issuer == CodexIdentityVerifier.issuer,
              CodexIdentityVerifier.safeIdentifier(claims.subject),
              claims.expiration > current - 5, claims.issuedAt <= current + 5,
              claims.expiration > claims.issuedAt,
              claims.notBefore.map({ $0 <= current + 5 }) ?? true,
              !claims.audiences.isEmpty else { throw CodexLoginError.failed }
        return claims
    }

    private struct Header: Decodable {
        let alg: String
        let kid: String
        let crit: [String]?
    }
}

private struct Claims: Decodable {
    let issuer: String
    let subject: String
    let audiences: [String]
    let authorizedParty: String?
    let clientID: String?
    let expiration: Double
    let issuedAt: Double
    let notBefore: Double?
    let email: String?
    let emailVerified: Bool?
    let profile: Profile?
    let auth: Auth?

    enum CodingKeys: String, CodingKey {
        case issuer = "iss", subject = "sub", audiences = "aud", authorizedParty = "azp", clientID = "client_id"
        case expiration = "exp", issuedAt = "iat", notBefore = "nbf", email, emailVerified = "email_verified"
        case profile = "https://api.openai.com/profile", auth = "https://api.openai.com/auth"
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        issuer = try values.decode(String.self, forKey: .issuer)
        subject = try values.decode(String.self, forKey: .subject)
        if let single = try? values.decode(String.self, forKey: .audiences) { audiences = [single] }
        else { audiences = try values.decode([String].self, forKey: .audiences) }
        authorizedParty = try values.decodeIfPresent(String.self, forKey: .authorizedParty)
        clientID = try values.decodeIfPresent(String.self, forKey: .clientID)
        // Integer NumericDate claims only; booleans, strings, NaN and fractions fail closed.
        expiration = Double(try values.decode(Int64.self, forKey: .expiration))
        issuedAt = Double(try values.decode(Int64.self, forKey: .issuedAt))
        notBefore = try values.decodeIfPresent(Int64.self, forKey: .notBefore).map(Double.init)
        email = try values.decodeIfPresent(String.self, forKey: .email)
        emailVerified = try values.decodeIfPresent(Bool.self, forKey: .emailVerified)
        profile = try values.decodeIfPresent(Profile.self, forKey: .profile)
        auth = try values.decodeIfPresent(Auth.self, forKey: .auth)
    }

    struct Profile: Decodable {
        let email: String?
        let emailVerified: Bool?
        enum CodingKeys: String, CodingKey { case email, emailVerified = "email_verified" }
    }

    struct Auth: Decodable {
        let accountID: String?
        let chatGPTUserID: String?
        let legacyUserID: String?
        let planType: String?
        var userID: String? { chatGPTUserID ?? legacyUserID }
        enum CodingKeys: String, CodingKey {
            case accountID = "chatgpt_account_id", chatGPTUserID = "chatgpt_user_id"
            case legacyUserID = "user_id", planType = "chatgpt_plan_type"
        }
    }
}

private func base64URL(_ value: String) -> Data? {
    guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
        || (97...122).contains($0) || $0 == 45 || $0 == 95 }), value.count % 4 != 1 else { return nil }
    let padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        + String(repeating: "=", count: (4 - value.count % 4) % 4)
    return Data(base64Encoded: padded)
}

private func derInteger(_ value: Data) -> Data {
    derValue(0x02, value.first.map({ $0 & 0x80 != 0 }) == true ? Data([0]) + value : value)
}

private func derValue(_ tag: UInt8, _ value: Data) -> Data {
    var length = value.count
    var bytes: [UInt8] = []
    if length < 128 { bytes = [UInt8(length)] }
    else {
        while length > 0 { bytes.insert(UInt8(length & 0xff), at: 0); length >>= 8 }
        bytes.insert(0x80 | UInt8(bytes.count), at: 0)
    }
    return Data([tag] + bytes) + value
}
