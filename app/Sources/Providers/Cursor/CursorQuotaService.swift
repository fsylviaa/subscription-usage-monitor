import Foundation

/// Tokens from Cursor's official browser polling login (T89). Stored only as a
/// Keychain payload; never in account JSON, logs or the widget publication.
struct CursorCredential: Codable, Equatable, Sendable, CustomStringConvertible {
    let accessToken: String
    let refreshToken: String

    var description: String { "CursorCredential(<redacted>)" }

    var payload: CredentialPayload {
        get throws { CredentialPayload(data: try JSONEncoder().encode(self)) }
    }

    init(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken; self.refreshToken = refreshToken
    }

    init(payload: CredentialPayload) throws {
        self = try JSONDecoder().decode(Self.self, from: payload.data)
        guard Self.safe(accessToken), Self.safe(refreshToken), userID != nil else { throw CodexQuotaError.failed }
    }

    /// Last segment of the access token's `sub` (e.g. `google-oauth2|<id>`), as the official CLI does.
    var userID: String? {
        let parts = accessToken.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var text = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text += "=" }
        guard let data = Data(base64Encoded: text),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = claims["sub"] as? String,
              let last = sub.split(separator: "|").last.map(String.init), !last.isEmpty,
              last.utf8.count <= 256,
              last.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(.init(charactersIn: "._-")).contains($0) })
        else { return nil }
        return last
    }

    /// Session cookie accepted by cursor.com (verified in T89).
    var cookie: String? {
        guard let userID else { return nil }
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(accessToken)"
    }

    static func safe(_ value: String) -> Bool {
        (1...64 * 1024).contains(value.utf8.count) && value.utf8.allSatisfy { (33...126).contains($0) && $0 != 59 }
    }
}

/// Authenticated reads from cursor.com for one stored credential. Shared by the
/// login (identity before saving) and by refresh. Never follows another host.
struct CursorAPIClient: Sendable {
    static let meURL = URL(string: "https://cursor.com/api/auth/me")!
    static let usageURL = URL(string: "https://cursor.com/api/usage-summary")!

    let transport: any CodexDeviceAuthorizationTransport

    init(transport: any CodexDeviceAuthorizationTransport = URLSessionCodexDeviceAuthorizationTransport()) {
        self.transport = transport
    }

    /// Grok Bot weekly quota (D-80, verified in T105): POST with an empty JSON body.
    static let grokBotURL = URL(string: "https://cursor.com/api/dashboard/get-sand-usage-status")!

    func get(_ url: URL, credential: CursorCredential) async throws -> Data {
        try await send(url, post: false, credential: credential)
    }

    func post(_ url: URL, credential: CursorCredential) async throws -> Data {
        try await send(url, post: true, credential: credential)
    }

    private func send(_ url: URL, post: Bool, credential: CursorCredential) async throws -> Data {
        guard let cookie = credential.cookie else { throw CodexQuotaError.failed }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = post ? "POST" : "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        if post {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
            request.httpBody = Data("{}".utf8)
        }
        let (data, response) = try await transport.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url == url, http.statusCode == 200,
              !data.isEmpty, data.count <= 256 * 1024,
              http.mimeType?.lowercased().contains("html") != true else { throw CodexQuotaError.failed }
        return data
    }

    func identity(_ credential: CursorCredential) async throws -> CursorUsageParser.Identity {
        try CursorUsageParser().identity(try await get(Self.meURL, credential: credential))
    }
}

/// Refreshes one Cursor account: network gate → identity check → usage summary
/// and Grok Bot weekly quota (D-80).
/// Identity must match the stored account before anything is written. Expired
/// sessions simply fail (“刷新失败”); D-77 does not renew Cursor logins.
struct CursorQuotaService: CodexQuotaUpdating {
    private var validateWrite: @Sendable () throws -> Void = {}
    private let store: AccountStore
    private let loadCredential: @Sendable (UUID) async throws -> CredentialPayload?
    private let client: CursorAPIClient
    private let checkNetwork: @Sendable () async -> NetworkScoreResult
    private let now: @Sendable () -> Date

    init(store: AccountStore,
         loadCredential: @escaping @Sendable (UUID) async throws -> CredentialPayload?,
         transport: any CodexDeviceAuthorizationTransport = URLSessionCodexDeviceAuthorizationTransport(),
         checkNetwork: @escaping @Sendable () async -> NetworkScoreResult = { await NetworkScoreChecker().check() },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.loadCredential = loadCredential
        self.client = CursorAPIClient(transport: transport)
        self.checkNetwork = checkNetwork
        self.now = now
    }

    func validatingWrites(_ validate: @escaping @Sendable () throws -> Void) -> Self {
        var service = self
        service.validateWrite = validate
        return service
    }

    func update(_ account: ConnectedAccount) async throws -> ConnectedAccount {
        var stage = "读取本机授权"
        do {
            try Task.checkCancellation()
            guard !account.isDemo, account.platform == .cursor,
                  let payload = try await loadCredential(account.credentialRef) else { throw CodexQuotaError.failed }
            let credential = try CursorCredential(payload: payload)
            stage = "查询前网络检查"
            try await requireNetwork()
            stage = "核对返回身份"
            let identity = try await client.identity(credential)
            guard Self.matches(identity, account) else { throw CodexQuotaError.failed }
            // The two quotas are separate pools (D-80): each keeps its own trusted
            // value, and a failure of either one is reported as “刷新失败”.
            stage = "请求真实额度"
            let parser = CursorUsageParser()
            let monthly: (AccountSubscription, AccountStore.QuotaObservation)?
            do {
                let data = try await client.get(CursorAPIClient.usageURL, credential: credential)
                stage = "解释额度"
                switch try parser.interpret(data, observedAt: now()) {
                case let .available(value, used, resetsAt):
                    monthly = (value, .available(try parser.snapshot(usedPercent: used, resetsAt: resetsAt,
                                                                      subscription: value, for: account)))
                case let .notApplicable(value):
                    monthly = (value, .notApplicable)
                }
            } catch {
                try Self.rethrowCancellation(error)
                monthly = nil
            }
            stage = "请求Grok Bot额度"
            let grokBot: GrokBotQuota?
            do {
                grokBot = try parser.grokBot(try await client.post(CursorAPIClient.grokBotURL, credential: credential),
                                             observedAt: now())
            } catch {
                try Self.rethrowCancellation(error)
                grokBot = nil
            }
            guard monthly != nil || grokBot != nil else { throw CodexQuotaError.failed }
            stage = "保存额度结果"
            guard try await loadCredential(account.credentialRef) == payload else { throw CodexQuotaError.failed }
            try Task.checkCancellation()
            let saved: ConnectedAccount
            if let monthly {
                saved = try await store.saveObservation(monthly.0, quota: monthly.1, grokBot: .some(grokBot),
                                                        for: account, validateRequest: validateWrite)
            } else {
                saved = try await store.saveGrokBot(grokBot!, for: account, validateRequest: validateWrite)
            }
            // Partial success is already saved together with its failure mark.
            if monthly == nil || grokBot == nil { throw PartialFailure() }
            return saved
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            if error is PartialFailure { throw CodexQuotaError.failed }
            #if DEBUG
            print("T92 | Cursor查询未完成 | 阶段：\(stage)") // Fixed stage only; never raw responses/errors.
            #endif
            let failure = error as? CodexQuotaError ?? .failed
            try? await store.saveQuotaFailure(failure == .networkBlocked ? .networkBlocked : .refresh,
                                              for: account, validateRequest: validateWrite)
            try Task.checkCancellation()
            throw failure
        }
    }

    private struct PartialFailure: Error {}

    private static func rethrowCancellation(_ error: any Error) throws {
        if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
            throw CancellationError()
        }
    }

    /// Same person: the stored subject and e-mail must both match what cursor.com returns.
    static func matches(_ identity: CursorUsageParser.Identity, _ account: ConnectedAccount) -> Bool {
        identity.subject == account.remoteUserID
            && identity.email.caseInsensitiveCompare(account.verifiedEmail ?? "") == .orderedSame
    }

    private func requireNetwork() async throws {
        let network = await checkNetwork()
        try Task.checkCancellation()
        switch network {
        case let .allowed(score) where score.isFinite && score > 50: return
        case .blocked: throw CodexQuotaError.networkBlocked
        case .cancelled: throw CancellationError()
        default: throw CodexQuotaError.failed
        }
    }
}
