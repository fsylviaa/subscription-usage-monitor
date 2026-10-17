import CryptoKit
import Foundation
import Security

/// One login attempt of Cursor's official browser polling (verified in T89):
/// the browser opens `loginDeepControl` with a one-time challenge; the App then
/// polls `api2.cursor.sh/auth/poll` with the matching verifier until confirmed.
struct CursorLoginRequest: Sendable, CustomStringConvertible {
    let uuid: String
    let verifier: String
    let browserURL: URL

    var description: String { "CursorLoginRequest(<redacted>)" }

    static func make() throws -> CursorLoginRequest {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CodexLoginError.failed
        }
        let verifier = base64url(Data(bytes))
        let challenge = base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let uuid = UUID().uuidString.lowercased()
        var url = URLComponents(string: "https://cursor.com/loginDeepControl")!
        url.queryItems = [.init(name: "challenge", value: challenge), .init(name: "uuid", value: uuid),
                          .init(name: "mode", value: "login"), .init(name: "redirectTarget", value: "cli"),
                          .init(name: "supportsSelectedTeamLogin", value: "true")]
        return CursorLoginRequest(uuid: uuid, verifier: verifier, browserURL: url.url!)
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

enum CursorPollOutcome: Sendable, Equatable {
    /// Not yet confirmed in the browser (HTTP 404).
    case waiting
    case confirmed(CursorCredential)
    case failed
}

protocol CursorLoginPolling: Sendable {
    func poll(_ request: CursorLoginRequest) async -> CursorPollOutcome
}

struct CursorLoginClient: CursorLoginPolling {
    static let pollURL = URL(string: "https://api2.cursor.sh/auth/poll")!
    /// Official CLI limits: start 1 s, ×1.5 each time, at most 10 s, 150 polls,
    /// stop after 3 consecutive errors.
    static let maxPolls = 150
    static let maxConsecutiveErrors = 3

    private let transport: any CodexDeviceAuthorizationTransport
    init(transport: any CodexDeviceAuthorizationTransport = URLSessionCodexDeviceAuthorizationTransport()) {
        self.transport = transport
    }

    static func delay(afterPoll index: Int) -> Double {
        min(pow(1.5, Double(max(0, index))), 10)
    }

    func poll(_ request: CursorLoginRequest) async -> CursorPollOutcome {
        var components = URLComponents(url: Self.pollURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [.init(name: "uuid", value: request.uuid), .init(name: "verifier", value: request.verifier)]
        var urlRequest = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        do {
            let (data, response) = try await transport.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse, http.url?.host == Self.pollURL.host else { return .failed }
            if http.statusCode == 404 { return .waiting }
            struct Body: Decodable { let accessToken: String; let refreshToken: String }
            guard http.statusCode == 200, data.count <= 256 * 1024,
                  let body = try? JSONDecoder().decode(Body.self, from: data) else { return .failed }
            let credential = CursorCredential(accessToken: body.accessToken, refreshToken: body.refreshToken)
            guard CursorCredential.safe(body.accessToken), CursorCredential.safe(body.refreshToken),
                  credential.userID != nil else { return .failed }
            return .confirmed(credential)
        } catch {
            return .failed
        }
    }
}

/// A Cursor identity confirmed by cursor.com for exactly these tokens.
struct CursorVerifiedLogin: Sendable, CustomStringConvertible {
    let email: String
    let subject: String
    let credentials: CredentialPayload
    var description: String { "CursorVerifiedLogin(<redacted>)" }
}
