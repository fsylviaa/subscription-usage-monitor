import Foundation
#if DEBUG
import Security
#endif

/// App and widget share the same gate, renewal and parser. The lease prevents
/// simultaneous token renewal and duplicate queries across processes/sizes.
struct CoordinatedQuotaUpdater: CodexQuotaUpdating {
    let store: AccountStore
    let service: any CodexQuotaUpdating
    /// Cursor accounts use their own query (D-77); the same lease, interval and
    /// stale-binding checks apply to both platforms.
    var cursorService: (any CodexQuotaUpdating)? = nil
    /// OpenRouter / DeepSeek balance accounts (D-82): same lease, interval and checks.
    var balanceService: (any CodexQuotaUpdating)? = nil
    var opportunistic = false
    var now: @Sendable () -> Date = { Date() }
    static let interval: TimeInterval = 30 * 60

    private struct Attempt: Codable {
        let generation: UInt64
        let credentialRef: UUID
        let date: Date
    }

    func update(_ expected: ConnectedAccount) async throws -> ConnectedAccount {
        let lockURL = store.queryLockURL(for: expected.id).appendingPathExtension("claim")
        var lease: SharedQueryLease?
        var waited = false
        for _ in 0..<100 {
            try Task.checkCancellation()
            do { lease = try SharedQueryLease(url: lockURL, at: now()); break }
            catch SharedFileLease.LockError.busy {
                waited = true
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        guard let lease else { throw CodexQuotaError.failed }
        defer { withExtendedLifetime(lease) {} }
        guard let current = try await store.load().first(where: { $0.id == expected.id }),
              current.deletionPending != true, current.generation == expected.generation,
              current.credentialRef == expected.credentialRef, current.scope == expected.scope else {
            throw AccountStore.StoreError.staleQuotaContext
        }
        if waited, current.subscription != expected.subscription || current.quotaSnapshot != expected.quotaSnapshot
            || current.balance != expected.balance,
           try await store.quotaFailure(for: current.id) == nil {
            return current
        }
        let attemptURL = lockURL.appendingPathExtension("attempt")
        if opportunistic {
            if let observed = current.subscription?.observedAt ?? current.balance?.observedAt, now().timeIntervalSince(observed) >= 0,
               now().timeIntervalSince(observed) < Self.interval { return current }
            if let data = try? Data(contentsOf: attemptURL), let attempt = try? JSONDecoder().decode(Attempt.self, from: data),
               attempt.generation == current.generation, attempt.credentialRef == current.credentialRef,
               (0..<Self.interval).contains(now().timeIntervalSince(attempt.date)) { return current }
        }
        // The attempt time only suppresses duplicate automatic work. It is never
        // a success timestamp or a displayed observation, including after a crash.
        try JSONEncoder().encode(Attempt(generation: current.generation, credentialRef: current.credentialRef, date: now()))
            .write(to: attemptURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        if current.isBalance {
            guard let balanceService else { throw CodexQuotaError.failed }
            if let query = balanceService as? APIBalanceService {
                return try await query.validatingWrites { try lease.validate(at: now()) }.update(current)
            }
            return try await balanceService.update(current)
        }
        if current.platform == .cursor {
            guard let cursorService else { throw CodexQuotaError.failed }
            if let query = cursorService as? CursorQuotaService {
                return try await query.validatingWrites { try lease.validate(at: now()) }.update(current)
            }
            return try await cursorService.update(current)
        }
        if let query = service as? CodexQuotaService {
            return try await query.validatingWrites { try lease.validate(at: now()) }.update(current)
        }
        return try await service.update(current)
    }

    static func live(store: AccountStore, opportunistic: Bool = false) -> Self {
        let vault = CredentialVault.applicationVault()
        return Self(store: store, service: CodexQuotaService(store: store,
            loadCredential: { try await vault.load(for: .credential($0)) },
            renewal: CodexCredentialRenewal(vault: vault, store: store)),
            cursorService: CursorQuotaService(store: store, loadCredential: { try await vault.load(for: .credential($0)) }),
            balanceService: APIBalanceService(store: store, loadCredential: { try await vault.load(for: .credential($0)) }),
            opportunistic: opportunistic)
    }
}

enum AutomaticWidgetRefresh {
    static func refresh(accountID: String?) async {
        #if DEBUG
        // Old T35 fixtures must never query or alter production accounts.
        if (try? WidgetSnapshotStore.displayStore().resolvedURL()) != (try? WidgetSnapshotStore.appGroupStore().resolvedURL()) {
            await refreshIsolated(accountID: accountID)
            return
        }
        #endif
        do {
            let store = try AccountStore.widgetAccountStore()
            let accounts = try await store.load().filter { $0.deletionPending != true && !$0.isDemo }
            let selected = accounts.first { $0.id.uuidString == accountID } ?? accounts.first
            guard let selected else { return }
            _ = try await CoordinatedQuotaUpdater.live(store: store, opportunistic: true).update(selected)
        } catch {
            // The service persists a simple failure without replacing trusted
            // values. Locked storage or expiration of execution keeps the cache.
        }
        await SharedResetReminderRuntime.reconcile()
    }
}


#if DEBUG
extension AutomaticWidgetRefresh {
    /// Explicit, isolated device acceptance only. No production file/Keychain/network.
    private static func refreshIsolated(accountID: String?) async {
        do {
            let display = WidgetSnapshotStore.displayStore()
            let directory = try display.resolvedURL().deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("T61-enabled").path) else { return }
            let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"), widgetStore: display)
            let accounts = try await store.load()
            guard let account = accounts.first(where: { $0.id.uuidString == accountID }) ?? accounts.first else { return }
            let vault = WidgetFixtureCredentials.vault(in: directory)
            let service = CodexQuotaService(store: store, loadCredential: { id in
                let payload = try await vault.load(for: .credential(id))
                WidgetSnapshotStore.traceValidation("widget.keychain", detail: "isolated=true found=\(payload != nil)")
                return payload
            },
                transport: WidgetFixtureTransport(), checkNetwork: {
                    WidgetSnapshotStore.traceValidation("widget.networkGate", detail: "isolated=true")
                    return .allowed(score: 51)
                })
            _ = try await CoordinatedQuotaUpdater(store: store, service: service, opportunistic: true).update(account)
            WidgetSnapshotStore.traceValidation("widget.queryFinished", detail: "isolated=true")
        } catch { WidgetSnapshotStore.traceValidation("widget.queryFailed", detail: "isolated=true") }
    }
}
enum WidgetFixtureCredentials {
    static func service(in directory: URL) -> String {
        "com.pbpuw6l86s.SubscriptionUsage.T61.\(directory.lastPathComponent)"
    }
    static func vault(in directory: URL) -> CredentialVault { CredentialVault(service: service(in: directory)) }
    static func prepare(_ account: ConnectedAccount, in directory: URL) async throws {
        let tokens = CodexTokenResponse(accessToken: "t61-synthetic", refreshToken: "t61-synthetic-refresh",
            idToken: "t61-synthetic-id", obtainedAt: Date(), expiresAt: nil)
        let package = CodexIdentityVerifier.CredentialPackage(credentialVersion: 1, issuer: CodexIdentityVerifier.issuer,
            clientID: CodexDeviceAuthorization.clientID, subject: "t61", remoteUserID: account.remoteUserID!, scope: account.scope, tokens: tokens)
        try await vault(in: directory).save(CredentialPayload(data: JSONEncoder().encode(package)), for: .credential(account.credentialRef))
    }
    static func remove(in directory: URL) throws {
        let prefix = "T35-validation-"
        guard directory.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(directory.lastPathComponent.dropFirst(prefix.count))) != nil else { return }
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword,
            kSecAttrService: service(in: directory) + ".credentials", kSecAttrSynchronizable: false] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialVault.VaultError.keychainFailure(status) }
    }
}
private struct WidgetFixtureTransport: CodexDeviceAuthorizationTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let id = request.value(forHTTPHeaderField: "ChatGPT-Account-Id") ?? ""
        let body: [String: Any] = ["account_id": id, "plan_type": "Plus", "rate_limit": [
            "primary_window": ["limit_window_seconds": 18000, "used_percent": 45, "reset_at": 1791604000],
            "secondary_window": ["limit_window_seconds": 604800, "used_percent": 45, "reset_at": 1792100000]]]
        WidgetSnapshotStore.traceValidation("widget.transport", detail: "isolated=true used=45")
        return (try JSONSerialization.data(withJSONObject: body), HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }
}
#endif
