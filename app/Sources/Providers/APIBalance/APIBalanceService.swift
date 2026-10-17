import Foundation

/// Internal outcome of one balance query (D-82). People only ever see “获取失败” /
/// “刷新失败” (or the connection prompt); the kind never reaches the interface.
enum APIBalanceQueryError: Error, Equatable {
    /// 401 / 403: the platform refused this key (OpenRouter: not a management key).
    case rejected
    /// Network, timeout, non-200 or an unusable body.
    case failed
}

/// Field rules verified in T111 and the official docs (technical plan §13 / §13a).
/// Amounts are exact decimals; a missing amount is never 0.
struct APIBalanceParser {
    private struct OpenRouterBody: Decodable {
        struct Credits: Decodable {
            let total_credits: Decimal
            let total_usage: Decimal
        }
        let data: Credits
    }

    /// `GET /api/v1/credits`: balance = max(0, total_credits − total_usage), US dollars.
    func openRouter(_ data: Data, observedAt: Date) throws -> APIBalanceSnapshot {
        // Numbers only: strings, booleans or null fail decoding instead of becoming 0.
        guard let body = try? JSONDecoder().decode(OpenRouterBody.self, from: data),
              !body.data.total_credits.isNaN, !body.data.total_usage.isNaN else { throw APIBalanceQueryError.failed }
        let balance = max(0, body.data.total_credits - body.data.total_usage)
        return try valid(APIBalanceSnapshot(amounts: [BalanceAmount(currency: "USD", total: balance)], observedAt: observedAt))
    }

    /// `GET /user/balance`: string amounts per currency. `is_available == false` only means
    /// the balance is too low for API calls; it is still a successful query.
    func deepSeek(_ data: Data, observedAt: Date) throws -> APIBalanceSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["is_available"] is Bool,
              let infos = root["balance_infos"] as? [[String: Any]], !infos.isEmpty else { throw APIBalanceQueryError.failed }
        let amounts = try infos.map { info -> BalanceAmount in
            guard let currency = (info["currency"] as? String)?.uppercased(),
                  let total = try amount(info["total_balance"]) else { throw APIBalanceQueryError.failed }
            return BalanceAmount(currency: currency, total: total,
                                 toppedUp: try amount(info["topped_up_balance"]), granted: try amount(info["granted_balance"]))
        }
        return try valid(APIBalanceSnapshot(amounts: amounts, observedAt: observedAt))
    }

    /// Absent → nil (unknown); present but not a plain decimal string → the whole query fails.
    private func amount(_ value: Any?) throws -> Decimal? {
        guard let value, !(value is NSNull) else { return nil }
        guard let text = value as? String, let parsed = try? BalanceAmount.decimal(text) else { throw APIBalanceQueryError.failed }
        return parsed
    }

    private func valid(_ snapshot: APIBalanceSnapshot) throws -> APIBalanceSnapshot {
        guard snapshot.isValid else { throw APIBalanceQueryError.failed }
        return snapshot
    }
}

/// Authenticated balance read for one pasted key. Fixed hosts only: the management
/// key never follows a redirect or a configurable address.
struct APIBalanceClient: Sendable {
    static let openRouterURL = URL(string: "https://openrouter.ai/api/v1/credits")!
    static let deepSeekURL = URL(string: "https://api.deepseek.com/user/balance")!

    let transport: any CodexDeviceAuthorizationTransport

    init(transport: any CodexDeviceAuthorizationTransport = URLSessionCodexDeviceAuthorizationTransport()) {
        self.transport = transport
    }

    func balance(_ provider: ProviderID, key: APIKeyCredential, observedAt: Date) async throws -> APIBalanceSnapshot {
        let url: URL
        switch provider {
        case .openRouter: url = Self.openRouterURL
        case .deepSeek: url = Self.deepSeekURL
        default: throw APIBalanceQueryError.failed
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("Bearer \(key.key)", forHTTPHeaderField: "Authorization")
        let data: Data, response: URLResponse
        do { (data, response) = try await transport.data(for: request) } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw APIBalanceQueryError.failed
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.url == url else { throw APIBalanceQueryError.failed }
        if http.statusCode == 401 || http.statusCode == 403 { throw APIBalanceQueryError.rejected }
        guard http.statusCode == 200, !data.isEmpty, data.count <= 64 * 1024,
              http.mimeType?.lowercased().contains("html") != true else { throw APIBalanceQueryError.failed }
        let parser = APIBalanceParser()
        return try provider == .openRouter ? parser.openRouter(data, observedAt: observedAt)
                                           : parser.deepSeek(data, observedAt: observedAt)
    }
}

/// Refreshes one balance account: Keychain key → network gate → balance query → save.
/// Every failure keeps the trusted old balance and its success time (BAL-09); a refused
/// key simply fails too (D-59: no replace-key entry).
struct APIBalanceService: CodexQuotaUpdating {
    private var validateWrite: @Sendable () throws -> Void = {}
    private let store: AccountStore
    private let loadCredential: @Sendable (UUID) async throws -> CredentialPayload?
    private let client: APIBalanceClient
    private let checkNetwork: @Sendable () async -> NetworkScoreResult
    private let now: @Sendable () -> Date

    init(store: AccountStore,
         loadCredential: @escaping @Sendable (UUID) async throws -> CredentialPayload?,
         transport: any CodexDeviceAuthorizationTransport = URLSessionCodexDeviceAuthorizationTransport(),
         checkNetwork: @escaping @Sendable () async -> NetworkScoreResult = { await NetworkScoreChecker().check() },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.loadCredential = loadCredential
        self.client = APIBalanceClient(transport: transport)
        self.checkNetwork = checkNetwork
        self.now = now
    }

    func validatingWrites(_ validate: @escaping @Sendable () throws -> Void) -> Self {
        var service = self
        service.validateWrite = validate
        return service
    }

    func update(_ account: ConnectedAccount) async throws -> ConnectedAccount {
        do {
            try Task.checkCancellation()
            guard !account.isDemo, account.isBalance,
                  let payload = try await loadCredential(account.credentialRef) else { throw CodexQuotaError.failed }
            let key = try APIKeyCredential(payload: payload)
            guard key.fingerprint(for: account.provider) == account.remoteUserID else { throw CodexQuotaError.failed }
            switch await checkNetwork() {
            case let .allowed(score) where score.isFinite && score > 50: break
            case .blocked: throw CodexQuotaError.networkBlocked
            case .cancelled: throw CancellationError()
            default: throw CodexQuotaError.failed
            }
            try Task.checkCancellation()
            let balance = try await client.balance(account.provider, key: key, observedAt: now())
            // The key must not have been replaced or removed while the request ran.
            guard try await loadCredential(account.credentialRef) == payload else { throw CodexQuotaError.failed }
            try Task.checkCancellation()
            return try await store.saveBalance(balance, for: account, validateRequest: validateWrite)
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            let failure = error as? CodexQuotaError ?? .failed
            try? await store.saveQuotaFailure(failure == .networkBlocked ? .networkBlocked : .refresh,
                                              for: account, validateRequest: validateWrite)
            try Task.checkCancellation()
            throw failure
        }
    }
}
