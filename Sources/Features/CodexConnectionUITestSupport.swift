#if DEBUG
import Foundation

/// Only explicit DEBUG launches can use test support; no product menu or saved
/// preference enables it. Fixtures make no external requests. The opt-in live
/// flow uses real clients but an entirely separate account directory and vault.
@MainActor
enum CodexConnectionUITestSupport {
    static func makeFlow() -> CodexConnectionFlow {
        let arguments = ProcessInfo.processInfo.arguments
        // Hosted unit tests assemble their own isolated dependencies. Do not let
        // the host scene silently query or change the user's real account.
        if NSClassFromString("XCTestCase") != nil {
            return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) },
                authorizer: FixtureAuthorizer(fails: true), transactions: FixtureTransactions())
        }
        if let marker = arguments.firstIndex(of: "--t12-isolated-ui") {
            let scenario = arguments.indices.contains(marker + 1) ? arguments[marker + 1] : "success"
            return completionFlow(scenario: scenario, arguments: arguments, includeQuota: true)
        }
        if arguments.contains(where: { $0.hasPrefix("--t10-live") }) {
            return isolatedLiveFlow(arguments: arguments, task: "T10")
        }
        if let marker = arguments.firstIndex(of: "--t10-isolated-ui") {
            let scenario = arguments.indices.contains(marker + 1) ? arguments[marker + 1] : "pending"
            return restorationFlow(scenario: scenario, arguments: arguments)
        }
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

    private static func completionFlow(scenario: String, arguments: [String], includeQuota: Bool = false) -> CodexConnectionFlow {
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
        let completer = FixtureCompleter(scenario: includeQuota ? "success" : scenario)
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let retryFixture = QuotaRetryFixture(scenario: scenario)
        let updater: CodexQuotaService? = includeQuota ? CodexQuotaService(store: store,
            loadCredential: { _ in
                let package = CodexIdentityVerifier.CredentialPackage(credentialVersion: 1,
                    issuer: CodexIdentityVerifier.issuer, clientID: CodexDeviceAuthorization.clientID,
                    subject: "fixture-subject", remoteUserID: "isolated-ui-user",
                    scope: .init(remoteAccountID: "isolated-ui-account", kind: .personal),
                    tokens: .init(accessToken: "fixture-access", refreshToken: "fixture-refresh", idToken: "fixture-id",
                                  obtainedAt: Date(), expiresAt: nil))
                return .init(data: try JSONEncoder().encode(package))
            }, transport: retryFixture,
            checkNetwork: { await retryFixture.checkNetwork() }) : nil
        return CodexConnectionFlow(
            checkNetwork: { .allowed(score: 51) },
            authorizer: FixtureAuthorizer(fails: false, pollInterval: 1),
            transactions: FixtureTransactions(),
            completer: completer,
            verifier: FixtureVerifier(fails: scenario == "verification-failure"),
            bindings: FixtureBindings(fileURL: directory.appendingPathComponent("accounts.json")),
            pending: FixturePending(),
            quotaUpdater: updater,
            copyCode: { _, _ in },
            openURL: { url in
                guard url == CodexDeviceAuthorization.verificationURL else { return false }
                await completer.websiteOpened()
                return true
            }
        )
    }

    private actor QuotaRetryFixture: CodexDeviceAuthorizationTransport {
        let scenario: String
        private var checks = 0
        private var requests = 0
        init(scenario: String) { self.scenario = scenario }
        func checkNetwork() -> NetworkScoreResult {
            checks += 1
            if scenario == "blocked" || (scenario == "retry-blocked" && checks == 1) { return .blocked(score: 50) }
            if scenario == "retry-unknown" && checks == 1 { return .unavailable(.transport) }
            return .allowed(score: 51)
        }
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            requests += 1
            if scenario == "retry-request" && requests == 1 { throw URLError(.timedOut) }
            let resolved: String
            if scenario == "retry-plan" { resolved = requests == 1 ? "plan-only-failure" : "new-plan" }
            else if scenario == "retry-free" { resolved = requests == 1 ? "plan-only-failure" : "free" }
            else { resolved = scenario }
            return try await QuotaFixtureTransport(scenario: resolved).data(for: request)
        }
    }

    private struct QuotaFixtureTransport: CodexDeviceAuthorizationTransport {
        let scenario: String
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            // Make sheet dismissal overlap the query to exercise task separation.
            try await Task.sleep(for: .milliseconds(500))
            let partialBody = #"{"account_id":"isolated-ui-account","plan_type":"Plus","rate_limit":{"primary_window":{"limit_window_seconds":604800,"used_percent":30}}}"#
            let completeBody = #"{"account_id":"isolated-ui-account","plan_type":"Plus","rate_limit":{"primary_window":{"limit_window_seconds":18000,"used_percent":80,"reset_at":1791669600},"secondary_window":{"limit_window_seconds":604800,"used_percent":30,"reset_at":1792144800}}}"#
            let freeBody = #"{"account_id":"isolated-ui-account","plan_type":"Free","rate_limit":{"primary_window":{"limit_window_seconds":2592000,"used_percent":0},"secondary_window":null}}"#
            let failedBody = #"{"account_id":"isolated-ui-account","plan_type":"Future Official Plan","rate_limit":"bad"}"#
            let body = switch scenario {
            case "partial": partialBody
            case "free": freeBody
            case "plan-only-failure": failedBody
            case "new-plan": completeBody.replacingOccurrences(of: "Plus", with: "Future Official Plan")
            default: completeBody
            }
            return (Data(body.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
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

    private static func isolatedLiveFlow(arguments: [String], task: String = "T09") -> CodexConnectionFlow {
        let prefix = "--\(task.lowercased())-live"
        let liveFlag = "\(prefix)-ui"
        let runIDFlag = "\(prefix)-run-id"
        let permittedFlags = Set([liveFlag, runIDFlag])
        guard arguments.filter({ $0 == liveFlag }).count == 1,
              arguments.filter({ $0 == runIDFlag }).count == 1,
              arguments.filter({ $0.hasPrefix(prefix) }).allSatisfy(permittedFlags.contains),
              !arguments.contains(where: { $0.hasPrefix(task == "T10" ? "--t09" : "--t10") }),
              !arguments.contains("--t10-isolated-ui"),
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
        let root: URL
        if task == "T10" {
            guard let support = try? FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true) else {
                return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) },
                                           authorizer: FixtureAuthorizer(fails: true),
                                           transactions: FixtureTransactions())
            }
            root = support
        } else {
            root = FileManager.default.temporaryDirectory
        }
        let directory = root.appendingPathComponent("\(task)-live-\(runID.uuidString)", isDirectory: true)
        let accounts = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let vault = CredentialVault(service: "\(task).live.\(runID.uuidString)")
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

    private static func restorationFlow(scenario: String, arguments: [String]) -> CodexConnectionFlow {
        guard let marker = arguments.firstIndex(of: "--t10-run-id"),
              arguments.indices.contains(marker + 1),
              let runID = UUID(uuidString: arguments[marker + 1]),
              let support = try? FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true) else {
            return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) },
                                       authorizer: FixtureAuthorizer(fails: true),
                                       transactions: FixtureTransactions())
        }
        let directory = support.appendingPathComponent("T10-ui-\(runID.uuidString)", isDirectory: true)
        let vault = CredentialVault(service: "T10.ui.\(runID.uuidString)")
        let transactions = CodexLoginTransactionStore(vault: vault)
        let pending = CodexPendingLoginStore(vault: vault)
        let accounts = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let fixture = RestorationFixture(directory: directory,
            completes: scenario == "success" && arguments.contains("--t10-complete-on-reopen"))
        return CodexConnectionFlow(
            checkNetwork: { .allowed(score: 51) },
            authorizer: fixture,
            transactions: transactions,
            completer: fixture,
            verifier: FixtureVerifier(fails: false),
            bindings: RestorationBindings(directory: directory, accounts: accounts, vault: vault,
                transactions: transactions, pending: pending,
                bindings: CodexAccountBindingStore(accountStore: accounts, vault: vault),
                reset: arguments.contains("--t10-reset-storage")),
            pending: pending,
            copyCode: { _, _ in },
            openURL: { $0 == CodexDeviceAuthorization.verificationURL }
        )
    }

    /// Uses the production stores with an isolated vault. Only the server and
    /// identity are fixtures, so a process restart exercises actual persistence.
    private actor RestorationBindings: CodexAccountBinding {
        private let directory: URL
        private let accounts: AccountStore
        private let vault: CredentialVault
        private let transactions: CodexLoginTransactionStore
        private let pending: CodexPendingLoginStore
        private let bindings: CodexAccountBindingStore
        private var reset: Bool

        init(directory: URL, accounts: AccountStore, vault: CredentialVault,
             transactions: CodexLoginTransactionStore, pending: CodexPendingLoginStore,
             bindings: CodexAccountBindingStore, reset: Bool) {
            self.directory = directory
            self.accounts = accounts
            self.vault = vault
            self.transactions = transactions
            self.pending = pending
            self.bindings = bindings
            self.reset = reset
        }

        func load() async throws -> [ConnectedAccount] {
            if reset {
                if let authorization = try await transactions.load() {
                    try await transactions.cancel(transactionID: authorization.transactionID)
                    try await pending.remove(transactionID: authorization.transactionID)
                    try await transactions.remove(transactionID: authorization.transactionID)
                }
                if let cancelledID = try await transactions.loadCancelledTransactionID() {
                    try await pending.remove(transactionID: cancelledID)
                    try await transactions.remove(transactionID: cancelledID)
                }
                for account in try await accounts.load() {
                    try await vault.remove(for: .credential(account.credentialRef))
                }
                if FileManager.default.fileExists(atPath: directory.path) {
                    try FileManager.default.removeItem(at: directory)
                }
                reset = false
            }
            return try await bindings.load()
        }

        func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount {
            try await bindings.save(login)
        }
    }

    private actor RestorationFixture: CodexDeviceAuthorizing, CodexLoginCompleting {
        let directory: URL
        let completes: Bool

        init(directory: URL, completes: Bool) {
            self.directory = directory
            self.completes = completes
        }

        func requestAuthorization() throws -> CodexDeviceAuthorization {
            let counterURL = directory.appendingPathComponent("request-count.json")
            let oldCount = (try? JSONDecoder().decode(Int.self, from: Data(contentsOf: counterURL))) ?? 0
            let requestCount = oldCount + 1
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(requestCount).write(to: counterURL, options: .atomic)
            return try CodexDeviceAuthorization(deviceAuthID: "isolated-t10-request-\(requestCount)",
                userCode: String(format: "TEST-%04d", requestCount), pollInterval: 1, startedAt: Date())
        }

        func poll(_ authorization: CodexDeviceAuthorization) async throws -> CodexAuthorizationCode? {
            try await Task.sleep(for: .milliseconds(150))
            guard completes else { return nil }
            // Success is possible only by restoring the original request.
            guard authorization.userCode == "TEST-0001" else { throw CodexLoginError.failed }
            return CodexAuthorizationCode(code: "isolated-t10-code", verifier: String(repeating: "A", count: 43))
        }

        func exchange(_ code: CodexAuthorizationCode) async throws -> CodexTokenResponse {
            try await Task.sleep(for: .milliseconds(150))
            return CodexTokenResponse(accessToken: "isolated-t10-access", refreshToken: "isolated-t10-refresh",
                                      idToken: "isolated-t10-id", obtainedAt: Date(), expiresAt: nil)
        }
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
