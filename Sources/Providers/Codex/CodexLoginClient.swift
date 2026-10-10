import Foundation
import CryptoKit

/// Never log the server response or a decoding error: both may contain login secrets.
enum CodexLoginError: Error, Equatable { case failed, networkBlocked }

struct CodexTokenResponse: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let accessToken: String
    let refreshToken: String
    let idToken: String
    let obtainedAt: Date
    let expiresAt: Date?
    var description: String { "CodexTokenResponse(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

struct CodexAuthorizationCode: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    let code: String
    let verifier: String
    var description: String { "CodexAuthorizationCode(<redacted>)" }
    var debugDescription: String { description }
    var customMirror: Mirror { Mirror(self, children: [:]) }
}

protocol CodexLoginCompleting: Sendable {
    /// nil means the official 403/404 pending response, never a successful account.
    func poll(_ authorization: CodexDeviceAuthorization) async throws -> CodexAuthorizationCode?
    func exchange(_ code: CodexAuthorizationCode) async throws -> CodexTokenResponse
}

struct CodexLoginClient: CodexLoginCompleting {
    static let pollURL = URL(string: "https://auth.openai.com/api/accounts/deviceauth/token")!
    static let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let transport: any CodexDeviceAuthorizationTransport
    private let now: @Sendable () -> Date

    init(transport: any CodexDeviceAuthorizationTransport = URLSessionCodexDeviceAuthorizationTransport(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }

    func poll(_ authorization: CodexDeviceAuthorization) async throws -> CodexAuthorizationCode? {
        guard !authorization.isExpired(at: now()) else { throw CodexLoginError.failed }
        var request = request(Self.pollURL, contentType: "application/json")
        request.httpBody = try JSONEncoder().encode(PollRequest(device_auth_id: authorization.deviceAuthID,
                                                               user_code: authorization.userCode))
        let (data, status) = try await send(request)
        if status == 403 || status == 404 { return nil }
        guard status == 200, !authorization.isExpired(at: now()),
              let value = try? JSONDecoder().decode(PollResponse.self, from: data),
              Self.validSecret(value.authorization_code),
              (43...128).contains(value.code_verifier.utf8.count),
              value.code_verifier.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                  || (97...122).contains($0) || [45, 46, 95, 126].contains($0) }) else {
            throw CodexLoginError.failed
        }
        let challenge = Data(SHA256.hash(data: Data(value.code_verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard challenge == value.code_challenge else { throw CodexLoginError.failed }
        return CodexAuthorizationCode(code: value.authorization_code, verifier: value.code_verifier)
    }

    func exchange(_ code: CodexAuthorizationCode) async throws -> CodexTokenResponse {
        var request = request(Self.tokenURL, contentType: "application/x-www-form-urlencoded")
        let fields = [("grant_type", "authorization_code"), ("client_id", CodexDeviceAuthorization.clientID),
                      ("code", code.code), ("code_verifier", code.verifier),
                      ("redirect_uri", "https://auth.openai.com/deviceauth/callback")]
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = fields.map { key, value in
            key + "=" + (value.addingPercentEncoding(withAllowedCharacters: safe) ?? "")
        }.joined(separator: "&").data(using: .utf8)
        let (data, status) = try await send(request)
        guard status == 200, let value = try? JSONDecoder().decode(TokenBody.self, from: data),
              Self.validSecret(value.access_token), Self.validSecret(value.refresh_token),
              Self.validSecret(value.id_token),
              value.token_type == nil || value.token_type?.lowercased() == "bearer" else {
            throw CodexLoginError.failed
        }
        if let expiry = value.expires_in, !expiry.isFinite || expiry <= 0 { throw CodexLoginError.failed }
        let obtained = now()
        return CodexTokenResponse(accessToken: value.access_token, refreshToken: value.refresh_token,
                                  idToken: value.id_token, obtainedAt: obtained,
                                  expiresAt: value.expires_in.map { obtained.addingTimeInterval($0) })
    }

    private func request(_ url: URL, contentType: String) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            try Task.checkCancellation()
            let (data, response) = try await transport.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, http.url == request.url,
                  data.count <= 256 * 1024, http.mimeType?.contains("html") != true else {
                throw CodexLoginError.failed
            }
            return (data, http.statusCode)
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            throw CodexLoginError.failed
        }
    }

    private static func validSecret(_ value: String) -> Bool {
        (1...64 * 1024).contains(value.utf8.count) && value.utf8.allSatisfy { (33...126).contains($0) }
    }
    private struct PollRequest: Encodable { let device_auth_id: String; let user_code: String }
    private struct PollResponse: Decodable { let authorization_code: String; let code_verifier: String; let code_challenge: String }
    private struct TokenBody: Decodable {
        let access_token: String; let refresh_token: String; let id_token: String
        let expires_in: Double?; let token_type: String?
    }
}

/// Sensitive intermediate responses live only in memory and this App's Keychain.
/// Process-interruption recovery is T10; a code exchange is never blindly repeated here.
protocol CodexPendingLoginStoring: Sendable {
    func saveCode(_ code: CodexAuthorizationCode, transactionID: UUID) async throws
    func saveTokens(_ tokens: CodexTokenResponse, transactionID: UUID) async throws
    func remove(transactionID: UUID) async throws
}

actor CodexPendingLoginStore: CodexPendingLoginStoring {
    private let vault: CredentialVault
    init(vault: CredentialVault = .applicationVault()) { self.vault = vault }
    private struct Pending: Encodable {
        let phase: String
        let code: CodexAuthorizationCode?
        let tokens: CodexTokenResponse?
    }
    func saveCode(_ code: CodexAuthorizationCode, transactionID: UUID) async throws {
        try await save(Pending(phase: "codeReceived", code: code, tokens: nil), id: transactionID)
    }
    func saveTokens(_ tokens: CodexTokenResponse, transactionID: UUID) async throws {
        try await save(Pending(phase: "tokensReceived", code: nil, tokens: tokens), id: transactionID)
    }
    func remove(transactionID: UUID) async throws {
        try await vault.remove(for: .loginTransaction(transactionID))
    }
    private func save(_ pending: Pending, id: UUID) async throws {
        try Task.checkCancellation()
        try await vault.save(CredentialPayload(data: JSONEncoder().encode(pending)), for: .loginTransaction(id))
    }
}
