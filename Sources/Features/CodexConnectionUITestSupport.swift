#if DEBUG
import Foundation

/// Only explicit UI test launches can use these fixtures; no product menu or saved
/// preference enables them, and neither requests nor storage touch a real account.
@MainActor
enum CodexConnectionUITestSupport {
    static func makeFlow() -> CodexConnectionFlow {
        let arguments = ProcessInfo.processInfo.arguments
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
}
#endif
