import Foundation

protocol CodexDeviceAuthorizationTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

/// Application of the official protocol snapshot (no polling or token exchange):
/// openai/codex 165299214855c2e48facf9bb3bc3c0fc277ee639,
/// codex-rs/login/src/device_code_auth.rs and auth/manager.rs.
struct CodexDeviceAuthorizationClient: CodexDeviceAuthorizing {
    static let requestURL = URL(string: "https://auth.openai.com/api/accounts/deviceauth/usercode")!

    private let transport: any CodexDeviceAuthorizationTransport
    private let now: @Sendable () -> Date

    init() {
        self.init(transport: URLSessionCodexDeviceAuthorizationTransport())
    }

    init(transport: any CodexDeviceAuthorizationTransport,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
    }

    func requestAuthorization() async throws -> CodexDeviceAuthorization {
        do {
            try Task.checkCancellation()
            let startedAt = now()
            var request = URLRequest(url: Self.requestURL,
                                     cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: 20)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
            request.httpBody = try JSONEncoder().encode(UserCodeRequest(client_id: CodexDeviceAuthorization.clientID))
            let (data, response) = try await transport.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse,
                  http.url == Self.requestURL else {
                throw CodexDeviceAuthorizationError.invalidResponse
            }
            // Unlike the later token-polling stage, 404 here is a request failure.
            if http.statusCode == 404 { throw CodexDeviceAuthorizationError.unavailable }
            guard (200...299).contains(http.statusCode) else {
                throw CodexDeviceAuthorizationError.requestFailed
            }
            guard !data.isEmpty, data.count <= 64 * 1024,
                  http.mimeType?.lowercased().contains("html") != true else {
                throw CodexDeviceAuthorizationError.invalidResponse
            }
            let payload: UserCodeResponse
            do {
                payload = try JSONDecoder().decode(UserCodeResponse.self, from: data)
            } catch {
                // Never expose raw server bodies or decoder diagnostics containing codes.
                throw CodexDeviceAuthorizationError.invalidResponse
            }
            let authorization = try CodexDeviceAuthorization(
                deviceAuthID: payload.deviceAuthID, userCode: payload.userCode,
                pollInterval: payload.interval, startedAt: startedAt
            )
            guard !authorization.isExpired(at: now()) else {
                throw CodexDeviceAuthorizationError.expired
            }
            try Task.checkCancellation()
            return authorization
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if let failure = error as? CodexDeviceAuthorizationError { throw failure }
            if (error as? URLError)?.code == .timedOut { throw CodexDeviceAuthorizationError.timeout }
            throw CodexDeviceAuthorizationError.requestFailed
        }
    }

    private struct UserCodeRequest: Encodable {
        let client_id: String
    }

    private struct UserCodeResponse: Decodable {
        let deviceAuthID: String
        let userCode: String
        let interval: TimeInterval

        private enum CodingKeys: String, CodingKey {
            case deviceAuthID = "device_auth_id"
            case userCode = "user_code"
            case usercode, interval
        }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            deviceAuthID = try values.decode(String.self, forKey: .deviceAuthID)
            // Both names are documented by the pinned official parser. Ambiguous
            // conflicting aliases must not silently select the wrong displayed code.
            let primary = try values.decodeIfPresent(String.self, forKey: .userCode)
            let alias = try values.decodeIfPresent(String.self, forKey: .usercode)
            guard let code = primary ?? alias,
                  primary == nil || alias == nil || primary == alias else {
                throw CodexDeviceAuthorizationError.invalidResponse
            }
            userCode = code
            if let string = try? values.decode(String.self, forKey: .interval) {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.utf8.allSatisfy({ (48...57).contains($0) }),
                      let integer = UInt64(trimmed) else {
                    throw CodexDeviceAuthorizationError.invalidResponse
                }
                interval = TimeInterval(integer)
            } else {
                // Also accept an integer representation. Missing, null, fractions,
                // booleans, zero and excessive values fail validation, never busy-loop.
                interval = TimeInterval(try values.decode(UInt64.self, forKey: .interval))
            }
            // No server-provided verification URI is part of this protocol snapshot.
            // The model always supplies the exact official HTTPS URL, without a code.
        }
    }
}

/// No disk cache, cookies, shared credential storage, redirects, or diagnostic bodies.
final class URLSessionCodexDeviceAuthorizationTransport: NSObject, CodexDeviceAuthorizationTransport,
    URLSessionTaskDelegate, @unchecked Sendable {
    private let session: URLSession

    override init() {
        session = URLSession(configuration: Self.configuration())
        super.init()
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        return configuration
    }

    deinit { session.invalidateAndCancel() }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request, delegate: self)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
