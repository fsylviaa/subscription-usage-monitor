import Foundation

enum CodexQuotaError: Error, Equatable {
    case networkBlocked
    case failed

    var message: String {
        self == .networkBlocked ? "网络不达标，无法更新" : "刷新失败"
    }
}

protocol CodexQuotaUpdating: Sendable {
    func update(_ account: ConnectedAccount) async throws -> ConnectedAccount
}

/// Queries only this App's previously verified credential and scope. Each actual
/// request gets a fresh network gate; no cookies, desktop credentials or fallback.
struct CodexQuotaService: CodexQuotaUpdating {
    private let store: AccountStore
    private let loadCredential: @Sendable (UUID) async throws -> CredentialPayload?
    private let renewal: (any CodexCredentialPreparing)?
    private let transport: any CodexDeviceAuthorizationTransport
    private let checkNetwork: @Sendable () async -> NetworkScoreResult
    private let now: @Sendable () -> Date

    init(store: AccountStore,
         loadCredential: @escaping @Sendable (UUID) async throws -> CredentialPayload?,
         renewal: (any CodexCredentialPreparing)? = nil,
         transport: any CodexDeviceAuthorizationTransport = URLSessionCodexDeviceAuthorizationTransport(),
         checkNetwork: @escaping @Sendable () async -> NetworkScoreResult = { await NetworkScoreChecker().check() },
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.loadCredential = loadCredential
        self.renewal = renewal
        self.transport = transport
        self.checkNetwork = checkNetwork
        self.now = now
    }

    func update(_ account: ConnectedAccount) async throws -> ConnectedAccount {
        var stage = "读取本机授权"
        do {
            try Task.checkCancellation()
            guard !account.isDemo else { throw CodexQuotaError.failed }
            guard var credential = try await loadCredential(account.credentialRef) else {
                throw CodexQuotaError.failed
            }
            _ = try CodexCredentialRenewal.package(credential, for: account)
            stage = "查询前网络检查"
            try await requireNetwork()
            var renewed = false
            if let renewal {
                let prepared = try await renewal.credential(for: account, rejected: nil)
                renewed = prepared != credential
                credential = prepared
                if renewed { try await requireNetwork() }
            }
            var data = Data()
            var response: URLResponse?
            for attempt in 0...1 {
                try Task.checkCancellation()
                let package = try CodexCredentialRenewal.package(credential, for: account)
                guard package.renewal == nil,
                      Self.safeHeader(package.scope.remoteAccountID), Self.safeHeader(package.tokens.accessToken),
                      package.tokens.expiresAt.map({ $0 > now() }) ?? true else { throw CodexQuotaError.failed }
                var request = URLRequest(url: CodexIdentityVerifier.usageURL,
                    cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
                request.httpMethod = "GET"
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
                request.setValue("Bearer \(package.tokens.accessToken)", forHTTPHeaderField: "Authorization")
                request.setValue(account.scope.remoteAccountID, forHTTPHeaderField: "ChatGPT-Account-Id")
                stage = "请求真实额度"
                let result = try await transport.data(for: request)
                try Task.checkCancellation()
                data = result.0; response = result.1
                if let http = response as? HTTPURLResponse, http.url == CodexIdentityVerifier.usageURL,
                   http.statusCode == 401, attempt == 0, !renewed, let renewal {
                    stage = "自动续期授权"
                    credential = try await renewal.credential(for: account, rejected: credential)
                    renewed = true
                    // The retry is a new actual quota request, with its own gate.
                    try await requireNetwork()
                    continue
                }
                break
            }
            let url = CodexIdentityVerifier.usageURL
            stage = "核对HTTP响应"
            guard let http = response as? HTTPURLResponse, http.url == url,
                  (200...299).contains(http.statusCode), !data.isEmpty, data.count <= 256 * 1024,
                  http.mimeType?.lowercased().contains("html") != true else {
                throw CodexQuotaError.failed
            }
            // The live path requires the same explicit identity as T08, even
            // though the pure parser can interpret identity-free fixture data.
            stage = "核对返回身份"
            let identity = try JSONDecoder().decode(CodexIdentityVerifier.UsageIdentity.self, from: data)
            guard identity.accountID == account.scope.remoteAccountID,
                  identity.userID == nil || identity.userID == account.remoteUserID,
                  identity.email == nil || identity.email?.lowercased() == account.verifiedEmail?.lowercased() else {
                throw CodexQuotaError.failed
            }
            stage = "解释套餐资料"
            let parser = CodexUsageParser()
            let subscription = try parser.subscription(data, observedAt: now())
            let observation: AccountStore.QuotaObservation
            do {
                stage = "解释额度窗口"
                let snapshot = try parser.parse(data, for: account, observedAt: subscription.observedAt)
                if snapshot.hasKnownQuota {
                    observation = .available(snapshot)
                } else if try parser.hasNoApplicableQuota(data, subscription: subscription) {
                    observation = .notApplicable
                } else {
                    observation = .failed
                }
            } catch {
                observation = .failed
            }
            stage = "保存套餐及额度结果"
            guard try await loadCredential(account.credentialRef) == credential else {
                throw CodexQuotaError.failed
            }
            try Task.checkCancellation()
            let updated = try await store.saveObservation(subscription, quota: observation, for: account)
            // Saving the plan is not proof of quota success. The caller reloads
            // this independently committed metadata while displaying the failure.
            if case .failed = observation { throw CodexQuotaError.failed }
            return updated
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            #if DEBUG
            print("T12 | 查询未完成 | 阶段：\(stage)") // Fixed stage only; never raw responses/errors.
            #endif
            if let failure = error as? CodexQuotaError { throw failure }
            throw CodexQuotaError.failed
        }
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

    private static func safeHeader(_ value: String) -> Bool {
        (1...64 * 1024).contains(value.utf8.count) && value.utf8.allSatisfy { (33...126).contains($0) }
    }
}
