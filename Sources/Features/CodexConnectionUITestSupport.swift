#if DEBUG
import Foundation

/// Only explicit DEBUG launches can use test support; no product menu or saved
/// preference enables it. Fixtures make no external requests. The opt-in live
/// flow uses real clients but an entirely separate account directory and vault.
@MainActor
enum CodexConnectionUITestSupport {
    static func makeFlow() -> CodexConnectionFlow {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(where: { $0.hasPrefix("--t09-live") }) {
            return isolatedLiveFlow(arguments: arguments)
        }
        if let marker = arguments.firstIndex(of: "--t09-isolated-ui") {
            let scenario = arguments.indices.contains(marker + 1) ? arguments[marker + 1] : "cancel"
            return recoveryFlow(scenario: scenario, arguments: arguments)
        }
        if let marker = arguments.firstIndex(of: "--t08-isolated-ui") {
            let scenario = arguments.indices.contains(marker + 1) ? arguments[marker + 1] : "pending"
            return completionFlow(scenario: scenario, arguments: arguments)
        }
        guard let marker = arguments.firstIndex(of: "--t07-isolated-ui"),
              arguments.indices.contains(marker + 1) else { return CodexConnectionFlow.live() }
        let scenario = arguments[marker + 1]
        return CodexConnectionFlow(
            checkNetwork: {
                switch scenario {
                case "50": return .blocked(score: 50)
                case "unknown": return .unavailable(.transport)
                case "slow":
                    // Intentionally ignores cancellation to exercise stale-result guards.
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                            continuation.resume()
                        }
                    }
                    return .allowed(score: 51)
                default: return .allowed(score: 51)
                }
            },
            authorizer: FixtureAuthorizer(fails: scenario == "request-failure"),
            transactions: FixtureTransactions(),
            openURL: { $0 == CodexDeviceAuthorization.verificationURL }
        )
    }

    private struct FixtureAuthorizer: CodexDeviceAuthorizing {
        let fails: Bool
        var pollInterval: TimeInterval = 5
        func requestAuthorization() async throws -> CodexDeviceAuthorization {
            if fails { throw CodexDeviceAuthorizationError.requestFailed }
            return try CodexDeviceAuthorization(deviceAuthID: "isolated-ui-transaction",
                                                userCode: "TEST-CODE", pollInterval: pollInterval,
                                                startedAt: Date())
        }
    }

    private actor FixtureTransactions: CodexLoginTransactionStoring {
        func save(_ authorization: CodexDeviceAuthorization) { }
        func remove(transactionID: UUID) { }
    }

    private static func completionFlow(scenario: String, arguments: [String]) -> CodexConnectionFlow {
        let runID: UUID
        if let marker = arguments.firstIndex(of: "--t08-run-id"),
           arguments.indices.contains(marker + 1), let supplied = UUID(uuidString: arguments[marker + 1]) {
            runID = supplied
        } else {
            runID = UUID()
        }
        // Canonical UUID paths cannot escape the isolated temporary directory.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("T08-ui-\(runID.uuidString)", isDirectory: true)
        if arguments.contains("--t08-reset-storage") {
            try? FileManager.default.removeItem(at: directory)
        }
        let completer = FixtureCompleter(scenario: scenario)
        return CodexConnectionFlow(
            checkNetwork: { .allowed(score: 51) },
            authorizer: FixtureAuthorizer(fails: false, pollInterval: 1),
            transactions: FixtureTransactions(),
            completer: completer,
            verifier: FixtureVerifier(fails: scenario == "verification-failure"),
            bindings: FixtureBindings(fileURL: directory.appendingPathComponent("accounts.json")),
            pending: FixturePending(),
            copyCode: { _, _ in },
            openURL: { url in
                guard url == CodexDeviceAuthorization.verificationURL else { return false }
                await completer.websiteOpened()
                return true
            }
        )
    }

    private actor FixtureCompleter: CodexLoginCompleting {
        let scenario: String
        private var didOpenWebsite = false
        init(scenario: String) { self.scenario = scenario }

        func websiteOpened() { didOpenWebsite = true }

        func poll(_ authorization: CodexDeviceAuthorization) async throws -> CodexAuthorizationCode? {
            try await Task.sleep(for: .milliseconds(150))
            guard didOpenWebsite, ["success", "verification-failure"].contains(scenario) else { return nil }
            return CodexAuthorizationCode(code: "isolated-ui-code", verifier: String(repeating: "A", count: 43))
        }

        func exchange(_ code: CodexAuthorizationCode) async throws -> CodexTokenResponse {
            try await Task.sleep(for: .milliseconds(150))
            return CodexTokenResponse(accessToken: "isolated-ui-access", refreshToken: "isolated-ui-refresh",
                                      idToken: "isolated-ui-id", obtainedAt: Date(), expiresAt: nil)
        }
    }

    private struct FixtureVerifier: CodexIdentityVerifying {
        let fails: Bool
        func verify(_ tokens: CodexTokenResponse) async throws -> CodexVerifiedLogin {
            try await Task.sleep(for: .milliseconds(150))
            if fails { throw CodexLoginError.failed }
            return .fixture(remoteUserID: "isolated-ui-user", email: "test-user@example.invalid",
                            scope: AccountScope(remoteAccountID: "isolated-ui-account", kind: .personal),
                            credentials: CredentialPayload(data: Data("isolated-ui-credentials".utf8)))
        }
    }

    /// These UI fixtures verify presentation/relaunch only. Production Keychain
    /// persistence is covered by CodexAccountBindingStoreTests, never by this fake.
    private actor FixtureBindings: CodexAccountBinding {
        let accounts: AccountStore
        private var credentials: [UUID: CredentialPayload] = [:]
        init(fileURL: URL) { accounts = AccountStore(fileURL: fileURL) }

        func load() async throws -> [ConnectedAccount] { try await accounts.load() }

        func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount {
            try Task.checkCancellation()
            let account = ConnectedAccount(remoteUserID: login.remoteUserID, verifiedEmail: login.email,
                                           scope: login.scope, credentialRef: UUID())
            try await accounts.appendFirstUnlessCancelled(account)
            credentials[account.credentialRef] = login.credentials
            return account
        }
    }

    private actor FixturePending: CodexPendingLoginStoring {
        func saveCode(_ code: CodexAuthorizationCode, transactionID: UUID) { }
        func saveTokens(_ tokens: CodexTokenResponse, transactionID: UUID) { }
        func remove(transactionID: UUID) { }
    }

    private static func isolatedLiveFlow(arguments: [String]) -> CodexConnectionFlow {
        let liveFlag = "--t09-live-ui"
        let runIDFlag = "--t09-live-run-id"
        let permittedFlags = Set([liveFlag, runIDFlag])
        guard arguments.filter({ $0 == liveFlag }).count == 1,
              arguments.filter({ $0 == runIDFlag }).count == 1,
              arguments.filter({ $0.hasPrefix("--t09-live") }).allSatisfy(permittedFlags.contains),
              !arguments.contains("--t09-isolated-ui"),
              !arguments.contains("--t08-isolated-ui"),
              !arguments.contains("--t07-isolated-ui"),
              let marker = arguments.firstIndex(of: runIDFlag),
              arguments.indices.contains(marker + 1),
              let runID = UUID(uuidString: arguments[marker + 1]),
              arguments[marker + 1].uppercased() == runID.uuidString else {
            // Invalid or conflicting explicit test arguments must never fall back
            // to the normal account, network, or production Keychain namespace.
            return CodexConnectionFlow(
                checkNetwork: { .unavailable(.transport) },
                authorizer: FixtureAuthorizer(fails: true),
                transactions: FixtureTransactions()
            )
        }

        // Only a validated, caller-supplied canonical UUID selects this storage.
        // Reuse that UUID to reopen this run; remove its exact items after review.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("T09-live-\(runID.uuidString)", isDirectory: true)
        let accounts = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let vault = CredentialVault(service: "T09.live.\(runID.uuidString)")
        return CodexConnectionFlow(
            checkNetwork: { await NetworkScoreChecker().check() },
            authorizer: CodexDeviceAuthorizationClient(),
            transactions: CodexLoginTransactionStore(vault: vault),
            completer: CodexLoginClient(),
            verifier: CodexIdentityVerifier(),
            bindings: CodexAccountBindingStore(accountStore: accounts, vault: vault),
            pending: CodexPendingLoginStore(vault: vault)
        )
    }

    private static func recoveryFlow(scenario: String, arguments: [String]) -> CodexConnectionFlow {
        let runID: UUID
        if let marker = arguments.firstIndex(of: "--t09-run-id"),
           arguments.indices.contains(marker + 1), let supplied = UUID(uuidString: arguments[marker + 1]) {
            runID = supplied
        } else {
            runID = UUID()
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("T09-ui-\(runID.uuidString)", isDirectory: true)
        if arguments.contains("--t09-reset-storage") {
            try? FileManager.default.removeItem(at: directory)
        }
        let recovery = RecoveryFixture(scenario: scenario)
        return CodexConnectionFlow(
            checkNetwork: { .allowed(score: 51) },
            authorizer: recovery,
            transactions: FixtureTransactions(),
            completer: recovery,
            verifier: FixtureVerifier(fails: false),
            bindings: FixtureBindings(fileURL: directory.appendingPathComponent("accounts.json")),
            pending: FixturePending(),
            copyCode: { _, _ in },
            openURL: { url in
                guard url == CodexDeviceAuthorization.verificationURL else { return false }
                await recovery.websiteOpened()
                return true
            }
        )
    }

    /// Starts with one controlled failure/cancellation opportunity, then permits a
    /// normal fixture login. Displayed codes identify fresh transactions without
    /// exposing any production secret or making an external request.
    private actor RecoveryFixture: CodexDeviceAuthorizing, CodexLoginCompleting {
        private let scenario: String
        private var requestCount = 0
        private var websiteOpenedForRequest: Int?

        init(scenario: String) { self.scenario = scenario }

        func requestAuthorization() throws -> CodexDeviceAuthorization {
            requestCount += 1
            websiteOpenedForRequest = nil
            let startedAt = scenario == "expired" && requestCount == 1
                ? Date().addingTimeInterval(-CodexDeviceAuthorization.maximumLifetime + 6)
                : Date()
            return try CodexDeviceAuthorization(
                deviceAuthID: "isolated-t09-request-\(requestCount)",
                userCode: String(format: "TEST-%04d", requestCount),
                pollInterval: 1,
                startedAt: startedAt
            )
        }

        func websiteOpened() { websiteOpenedForRequest = requestCount }

        func poll(_ authorization: CodexDeviceAuthorization) async throws -> CodexAuthorizationCode? {
            try await Task.sleep(for: .milliseconds(150))
            guard let openedRequest = websiteOpenedForRequest,
                  authorization.deviceAuthID == "isolated-t09-request-\(openedRequest)" else { return nil }
            if openedRequest == 1 {
                switch scenario {
                case "denied": throw CodexLoginError.failed
                case "expired", "cancel": return nil
                default: break
                }
            }
            return CodexAuthorizationCode(code: "isolated-t09-code-\(openedRequest)",
                                          verifier: String(repeating: "A", count: 43))
        }

        func exchange(_ code: CodexAuthorizationCode) async throws -> CodexTokenResponse {
            try await Task.sleep(for: .milliseconds(150))
            if scenario == "exchange-failure", code.code == "isolated-t09-code-1" {
                throw CodexLoginError.failed
            }
            return CodexTokenResponse(accessToken: "isolated-t09-access", refreshToken: "isolated-t09-refresh",
                                      idToken: "isolated-t09-id", obtainedAt: Date(), expiresAt: nil)
        }
    }
}
#endif
