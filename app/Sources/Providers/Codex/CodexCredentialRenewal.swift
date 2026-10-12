import Foundation

/// These objects live inside the existing Keychain package, never account JSON.
struct CodexRenewalAttempt: Codable, Sendable {
    let id: UUID
    let startedAt: Date
    let trigger: CodexRenewalObservation.Trigger
    var received: CodexTokenResponse?
}

/// No secrets or account identifiers; retained with the same authorization chain.
struct CodexRenewalObservation: Codable, Sendable {
    enum Trigger: String, Codable, Sendable { case expiry, unauthorized }
    let startedAt: Date
    let completedAt: Date
    let previousExpiry: Date?
    let trigger: Trigger
}

protocol CodexTokenRenewing: Sendable {
    func renew(_ tokens: CodexTokenResponse) async throws -> CodexTokenResponse
}

/// Official JSON refresh grant, pinned in docs to the same protocol as login.
/// No automatic retries: any unanswered POST might have consumed the old token.
struct CodexTokenRenewalClient: CodexTokenRenewing {
    private let transport: any CodexDeviceAuthorizationTransport
    private let now: @Sendable () -> Date
    init(transport: any CodexDeviceAuthorizationTransport = URLSessionCodexDeviceAuthorizationTransport(),
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport; self.now = now
    }

    func renew(_ tokens: CodexTokenResponse) async throws -> CodexTokenResponse {
        guard Self.safe(tokens.refreshToken) else { throw CodexQuotaError.failed }
        var request = URLRequest(url: CodexLoginClient.tokenURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = try JSONEncoder().encode(Grant(client_id: CodexDeviceAuthorization.clientID,
            grant_type: "refresh_token", refresh_token: tokens.refreshToken))
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url == CodexLoginClient.tokenURL,
              http.statusCode == 200, !data.isEmpty, data.count <= 256 * 1024,
              http.mimeType?.lowercased().contains("html") != true,
              let body = try? JSONDecoder().decode(Body.self, from: data),
              body.token_type == nil || body.token_type?.lowercased() == "bearer",
              body.expires_in.map({ $0.isFinite && $0 > 0 }) ?? true else { throw CodexQuotaError.failed }
        // Optional replacement fields follow the official protocol. An unchanged
        // access token cannot restore an expired/rejected credential, so fail closed.
        let access = body.access_token ?? tokens.accessToken
        let refresh = body.refresh_token ?? tokens.refreshToken
        let id = body.id_token ?? tokens.idToken
        guard Self.safe(access), Self.safe(refresh), Self.safe(id), access != tokens.accessToken else {
            throw CodexQuotaError.failed
        }
        let obtained = now()
        return .init(accessToken: access, refreshToken: refresh, idToken: id, obtainedAt: obtained,
                     expiresAt: body.expires_in.map { obtained.addingTimeInterval($0) })
    }
    private static func safe(_ value: String) -> Bool {
        (1...64 * 1024).contains(value.utf8.count) && value.utf8.allSatisfy { (33...126).contains($0) }
    }
    private struct Grant: Encodable { let client_id: String; let grant_type: String; let refresh_token: String }
    private struct Body: Decodable {
        let access_token: String?; let refresh_token: String?; let id_token: String?
        let expires_in: Double?; let token_type: String?
    }
}

protocol CodexCredentialPreparing: Sendable {
    func credential(for account: ConnectedAccount, rejected: CredentialPayload?) async throws -> CredentialPayload
}

/// One shared actor per App. A durable claim and Keychain compare-and-swap also
/// prevent a second instance or restarted process from replaying the same grant.
actor CodexCredentialRenewal: CodexCredentialPreparing {
    typealias Package = CodexIdentityVerifier.CredentialPackage
    private let vault: CredentialVault
    private let store: AccountStore
    private let client: any CodexTokenRenewing
    private let verify: @Sendable (CodexTokenResponse, Package) async throws -> CodexTokenResponse
    private let now: @Sendable () -> Date
    private var flights: [UUID: (id: UUID, task: Task<CredentialPayload, Error>)] = [:]
    // If persisting a received response fails, retry that save in this process;
    // never resend the grant. A restart still sees the durable no-replay marker.
    private var received: [UUID: (expected: CredentialPayload, candidate: CredentialPayload)] = [:]

    init(vault: CredentialVault, store: AccountStore,
         client: any CodexTokenRenewing = CodexTokenRenewalClient(),
         now: @escaping @Sendable () -> Date = { Date() },
         verify: @escaping @Sendable (CodexTokenResponse, Package) async throws -> CodexTokenResponse = {
             try await CodexIdentityVerifier().verifyRenewal($0, replacing: $1)
         }) {
        self.vault = vault; self.store = store; self.client = client; self.now = now; self.verify = verify
    }

    func credential(for account: ConnectedAccount, rejected: CredentialPayload? = nil) async throws -> CredentialPayload {
        try Task.checkCancellation()
        let ref = account.credentialRef
        let flight: (id: UUID, task: Task<CredentialPayload, Error>)
        if let existing = flights[ref] { flight = existing }
        else {
            let id = UUID()
            // Once claimed, finish persisting a response even if the UI caller
            // goes away. Its cancelled quota query must not publish a snapshot.
            let task = Task { try await self.prepare(account, rejected: rejected) }
            flight = (id, task)
            flights[ref] = flight
        }
        defer { if flights[ref]?.id == flight.id { flights[ref] = nil } }
        let payload = try await flight.task.value
        try Task.checkCancellation()
        _ = try Self.package(payload, for: account)
        // A 401 arriving while a non-refreshing reader was in flight must not
        // mistake that reader's unchanged credential for a completed renewal.
        if let rejected, payload == rejected {
            if flights[ref]?.id == flight.id { flights[ref] = nil }
            return try await credential(for: account, rejected: rejected)
        }
        return payload
    }

    private func prepare(_ account: ConnectedAccount, rejected: CredentialPayload?) async throws -> CredentialPayload {
        let ref = account.credentialRef
        let entry = CredentialVault.Entry.credential(ref)
        guard var payload = try await vault.load(for: entry) else { throw CodexQuotaError.failed }
        if let pending = received[ref] {
            if payload == pending.expected {
                guard try await store.replaceCredential(payload, with: pending.candidate, for: account, vault: vault) else {
                    throw CodexQuotaError.failed
                }
                payload = pending.candidate
            }
            received[ref] = nil
        }
        var package = try Self.package(payload, for: account)
        if package.renewal == nil {
            let nearExpiry = CodexIdentityVerifier.expirationForScheduling(package.tokens)
                .map { $0 <= now().addingTimeInterval(60) } ?? false
            // A late 401 for an old version reuses the newer, already saved one.
            guard nearExpiry || (rejected != nil && rejected == payload) else { return payload }
            package.renewal = .init(id: UUID(), startedAt: now(),
                trigger: nearExpiry ? .expiry : .unauthorized, received: nil)
            let marker = try Self.encode(package)
            guard try await store.replaceCredential(payload, with: marker, for: account, vault: vault) else {
                throw CodexQuotaError.failed
            }
            payload = marker
            // Any error leaves the marker intact. It keeps the original tokens
            // and binding, but cannot repeat an uncertain/explicitly rejected POST.
            let tokens = try await client.renew(package.tokens)
            package.renewal?.received = tokens
            let candidate = try Self.encode(package)
            received[ref] = (expected: marker, candidate: candidate)
            guard try await store.replaceCredential(marker, with: candidate, for: account, vault: vault) else {
                received[ref] = nil
                throw CodexQuotaError.failed
            }
            received[ref] = nil
            payload = candidate
        }
        guard let attempt = package.renewal, let candidate = attempt.received else {
            throw CodexQuotaError.failed
        }
        // Public-key transport failures can resume from the persisted response.
        // Never refresh again merely because verification or its save failed.
        let verified = try await verify(candidate, package)
        let previousExpiry = CodexIdentityVerifier.expirationForScheduling(package.tokens)
        package.tokens = verified
        package.renewal = nil
        package.renewalHistory = Array(((package.renewalHistory ?? []) + [
            .init(startedAt: attempt.startedAt, completedAt: now(), previousExpiry: previousExpiry, trigger: attempt.trigger)
        ]).suffix(2))
        let committed = try Self.encode(package)
        guard try await store.replaceCredential(payload, with: committed, for: account, vault: vault) else {
            throw CodexQuotaError.failed
        }
        return committed
    }

    static func package(_ payload: CredentialPayload, for account: ConnectedAccount) throws -> Package {
        let value = try JSONDecoder().decode(Package.self, from: payload.data)
        guard value.credentialVersion == 1, value.issuer == CodexIdentityVerifier.issuer,
              value.clientID == CodexDeviceAuthorization.clientID, !value.subject.isEmpty,
              value.remoteUserID == account.remoteUserID, value.scope == account.scope,
              value.tokens.obtainedAt.timeIntervalSince1970.isFinite,
              value.tokens.expiresAt.map({ $0.timeIntervalSince1970.isFinite && $0 > value.tokens.obtainedAt }) ?? true else {
            throw CodexQuotaError.failed
        }
        return value
    }
    private static func encode(_ package: Package) throws -> CredentialPayload {
        .init(data: try JSONEncoder().encode(package))
    }
}
