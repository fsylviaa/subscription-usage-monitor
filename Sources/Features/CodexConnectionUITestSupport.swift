#if DEBUG
import Foundation
import WidgetKit

/// Only explicit DEBUG launches can use test support; no product menu or saved
/// preference enables it. Fixtures make no external requests. The opt-in live
/// flow uses real clients but an entirely separate account directory and vault.
@MainActor
enum CodexConnectionUITestSupport {
    static var preferences: UserDefaults {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--t26-isolated-ui") {
            let preferences = UserDefaults(suiteName: "T26-feedback-fixture")!
            preferences.set(args.contains("--t26-dark") ? "dark" : "light", forKey: "appearance")
            return preferences
        }
        if let marker = args.firstIndex(of: "--t23-card-fixture"), args.indices.contains(marker + 2) {
            let preferences = UserDefaults(suiteName: "T23-card-fixture")!
            preferences.set(args[marker + 2], forKey: "appearance")
            return preferences
        }
        guard let id = managementRunID else { return .standard }
        return UserDefaults(suiteName: "ManagementUI-\(id)")!
    }

    private static var managementRunID: UUID? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--management-ui"), args.indices.contains(index + 1) else { return nil }
        return UUID(uuidString: args[index + 1])
    }

    static func makeFlow() -> CodexConnectionFlow {
        let arguments = ProcessInfo.processInfo.arguments
        // Hosted unit tests assemble their own isolated dependencies. Do not let
        // the host scene silently query or change the user's real account.
        if NSClassFromString("XCTestCase") != nil {
            return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) },
                authorizer: FixtureAuthorizer(fails: true), transactions: FixtureTransactions())
        }
        if let marker = arguments.firstIndex(of: "--t35-widget-fixture") {
            guard arguments.indices.contains(marker + 2), let session = UUID(uuidString: arguments[marker + 2]) else {
                // Malformed isolation arguments must never fall through to real accounts.
                return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) },
                    authorizer: FixtureAuthorizer(fails: true), transactions: FixtureTransactions())
            }
            return widgetValidationFlow(scenario: arguments[marker + 1], session: session)
        }
        // A normal launch restores production widget reads even after an interrupted check.
        if (try? WidgetSnapshotStore.displayStore().resolvedURL()) != (try? WidgetSnapshotStore.appGroupStore().resolvedURL()) {
            try? WidgetSnapshotStore.setValidationSession(nil)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppearance.kind)
        }
        if let marker = arguments.firstIndex(of: "--t23-card-fixture"), arguments.indices.contains(marker + 1) {
            return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) },
                authorizer: FixtureAuthorizer(fails: true), transactions: FixtureTransactions(),
                bindings: T23CardFixture(scenario: arguments[marker + 1]))
        }
        if let marker = arguments.firstIndex(of: "--t26-isolated-ui"), arguments.indices.contains(marker + 1) {
            let fixture = T26BatchFixture(scenario: arguments[marker + 1])
            let flow = CodexConnectionFlow(transactions: FixtureTransactions(), bindings: fixture, quotaUpdater: fixture,
                foregroundRefreshEnabled: arguments.contains("--t27-lifecycle"))
            if arguments.contains("--t26-auto") {
                Task {
                    await flow.loadAccounts()
                    try? await Task.sleep(for: .seconds(2))
                    flow.refreshAllQuota(manually: false)
                }
            }
            return flow
        }
        if let id = managementRunID {
            let store = AccountStore(fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("ManagementUI-\(id)/accounts.json"))
            let vault = CredentialVault(service: "ManagementUI-\(id)")
            return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) },
                authorizer: FixtureAuthorizer(fails: true), transactions: FixtureTransactions(),
                bindings: CodexAccountBindingStore(accountStore: store, vault: vault),
                quotaUpdater: CodexQuotaService(store: store, loadCredential: { _ in nil },
                    checkNetwork: { .unavailable(.transport) }))
        }
        if let marker = arguments.firstIndex(of: "--t16-isolated-ui") {
            let scenario = arguments.indices.contains(marker + 1) ? arguments[marker + 1] : "success"
            let runID = arguments.firstIndex(of: "--t16-run-id").flatMap {
                arguments.indices.contains($0 + 1) ? UUID(uuidString: arguments[$0 + 1]) : nil
            } ?? UUID()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T16-ui-\(runID)")
            return T16MultiAccountFixture(directory: directory, failSecond: scenario == "failure",
                duplicateMode: scenario == "duplicate" ? "same" : nil)
                .makeFlow(orderingFailsOnce: scenario == "order-failure")
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

    private static func widgetValidationFlow(scenario: String, session: UUID) -> CodexConnectionFlow {
        guard scenario != "cleanup", let shared = try? WidgetSnapshotStore.validationStore(session: session) else {
            try? WidgetSnapshotStore.setValidationSession(nil)
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppearance.kind)
            return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) },
                authorizer: FixtureAuthorizer(fails: true), transactions: FixtureTransactions())
        }
        let fixture = T26BatchFixture(scenario: scenario == "failure" ? "blocked" : "success",
            widgetStore: shared, reloadWidgets: {
                print("T35 | 请求组件更新 | \(Date().ISO8601Format())")
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppearance.kind)
            })
        let flow = CodexConnectionFlow(transactions: FixtureTransactions(), bindings: fixture, quotaUpdater: fixture,
                                       foregroundRefreshEnabled: scenario == "foreground")
        Task {
            do {
                let original = try await fixture.load()
                try WidgetSnapshotStore.setValidationSession(session)
                await flow.loadAccounts()
                switch scenario {
                case "single": flow.refreshQuota(for: original[0].id)
                case "all", "failure": flow.refreshAllQuota()
                case "reorder": try await fixture.store.reorder(original.reversed().map(\.id))
                case "remove": try await fixture.removeAccount(original[0].id)
                case "scope":
                    var incoming = original[0]
                    incoming.scope = .init(remoteAccountID: "t35-new-scope", kind: .workspace)
                    incoming.credentialRef = UUID()
                    _ = try await fixture.store.commitLogin(incoming)
                case "empty":
                    for account in original { try await fixture.removeAccount(account.id) }
                    // Late old responses must not repopulate the empty publication.
                    do { _ = try await fixture.store.saveQuota(original[0].quotaSnapshot!, for: original[0]) }
                    catch { }
                    try? await fixture.store.saveQuotaFailure(.refresh, for: original[0])
                case "background":
                    _ = await flow.refreshQuotaInBackground()
                default: break
                }
                await flow.waitForInitialQuota()
                if ["reorder", "remove", "scope", "empty"].contains(scenario) { await flow.loadAccounts() }
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppearance.kind)
                print("T35 | 桌面样例准备完成 | \(scenario) | \(Date().ISO8601Format())")
            } catch { print("T35 | 桌面样例准备失败") }
        }
        return flow
    }

    /// UI-only boundary input. No disk, Keychain, network, or product demo entries.
    /// Unlimited is supplied at the domain boundary; it is not inferred from Codex credits.
    private struct T23CardFixture: CodexAccountBinding {
        let scenario: String
        func load() async throws -> [ConnectedAccount] {
            let now = Date(timeIntervalSince1970: 1_791_590_400)
            let reference = Date()
            func account(_ index: Int, plan: String, weekly: QuotaAmount?, fiveHours: QuotaAmount?) -> ConnectedAccount {
                let observation = scenario == "times" ? now.addingTimeInterval(Double(index - 1) * 3600) : now
                var result = ConnectedAccount(verifiedEmail: "card-\(index)@example.invalid",
                    scope: .init(remoteAccountID: "t23-\(index)", kind: .personal), credentialRef: UUID(),
                    quotaState: weekly == nil ? .notApplicable : .available,
                    subscription: .init(planType: plan, observedAt: now))
                if let weekly, let fiveHours {
                    result.quotaSnapshot = .init(accountID: result.id, provider: result.provider,
                        product: result.product, scope: result.scope, generation: result.generation,
                        planType: plan, observedAt: observation,
                        weekly: .init(window: .weekly, amount: weekly,
                            resetsAt: scenario == "times" ? (index == 1 ? reference.addingTimeInterval(6 * 86400) : now) : nil, observedAt: observation),
                        fiveHours: .init(window: .fiveHours, amount: fiveHours,
                            resetsAt: scenario == "times" && index == 1 ? reference.addingTimeInterval(5640) : nil, observedAt: observation))
                }
                return result
            }
            if scenario == "states" {
                return [account(1, plan: "Pro", weekly: .unknown, fiveHours: .unlimited),
                        account(2, plan: "Free", weekly: nil, fiveHours: nil)]
            }
            return [account(1, plan: "Plus", weekly: .limited(try .init(used: 0)), fiveHours: .limited(try .init(used: 100))),
                    account(2, plan: "Future Official Plan", weekly: .limited(try .init(used: 30)), fiveHours: .limited(try .init(used: 80)))]
        }
        func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount { throw CodexLoginError.failed }
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
        // Persisted reads return identical bytes, including JSON key order.
        // Build once so T14's replacement check sees one stable fixture package.
        let package = CodexIdentityVerifier.CredentialPackage(credentialVersion: 1,
            issuer: CodexIdentityVerifier.issuer, clientID: CodexDeviceAuthorization.clientID,
            subject: "fixture-subject", remoteUserID: "isolated-ui-user",
            scope: .init(remoteAccountID: "isolated-ui-account", kind: .personal),
            tokens: .init(accessToken: "fixture-access", refreshToken: "fixture-refresh", idToken: "fixture-id",
                          obtainedAt: Date(), expiresAt: nil))
        let credential = (try? JSONEncoder().encode(package)).map { CredentialPayload(data: $0) }
        let updater: CodexQuotaService? = includeQuota ? CodexQuotaService(store: store,
            loadCredential: { _ in credential }, transport: retryFixture,
            checkNetwork: {
                if arguments.contains("--t15-offline") { return .unavailable(.transport) }
                return await retryFixture.checkNetwork()
            }) : nil
        return CodexConnectionFlow(
            checkNetwork: { .allowed(score: 51) },
            authorizer: FixtureAuthorizer(fails: false, pollInterval: 1),
            transactions: arguments.contains("--t15-delay-login-read")
                ? T15DelayedTransactions() : FixtureTransactions(),
            completer: completer,
            verifier: FixtureVerifier(fails: scenario == "verification-failure"),
            bindings: FixtureBindings(fileURL: directory.appendingPathComponent("accounts.json")),
            pending: FixturePending(),
            quotaUpdater: arguments.contains("--t15-read-only") ? nil : updater,
            copyCode: { _, _ in },
            openURL: { url in
                guard url == CodexDeviceAuthorization.verificationURL else { return false }
                await completer.websiteOpened()
                return true
            }
        )
    }

    /// Explicit isolated launches only; simulates a slow login/Keychain read.
    private struct T15DelayedTransactions: CodexLoginTransactionStoring {
        func save(_ authorization: CodexDeviceAuthorization) { }
        func remove(transactionID: UUID) { }
        func load() async throws -> CodexDeviceAuthorization? {
            try await Task.sleep(for: .seconds(60))
            return nil
        }
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
            if scenario == "t23-cached-failure" && requests > 1 { throw URLError(.notConnectedToInternet) }
            if scenario == "retry-request" && requests == 1 { throw URLError(.timedOut) }
            let resolved: String
            if scenario == "retry-slow" { resolved = requests == 1 ? "plan-only-failure" : "slow-quota" }
            else if scenario == "retry-twice" { resolved = requests <= 2 ? "plan-only-failure" : "new-plan" }
            else if scenario == "retry-plan" { resolved = requests == 1 ? "plan-only-failure" : "new-plan" }
            else if scenario == "retry-free" { resolved = requests == 1 ? "plan-only-failure" : "free" }
            else { resolved = scenario }
            return try await QuotaFixtureTransport(scenario: resolved).data(for: request)
        }
    }

    private struct QuotaFixtureTransport: CodexDeviceAuthorizationTransport {
        let scenario: String
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            // Keep the query visibly in flight to exercise sheet lifecycle.
            try await Task.sleep(for: .milliseconds(scenario == "slow-quota" ? 4_000 : 500))
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
            try await accounts.appendUnlessCancelled(account)
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

/// Test-only server identities; production binding, Keychain, parsing and files
/// run unchanged in a random namespace. No external request is made.
@MainActor
final class T16MultiAccountFixture {
    let store: AccountStore
    let vault: CredentialVault
    let bindings: CodexAccountBindingStore
    let server: T16MultiAccountServer
    let updater: CodexQuotaService
    let directory: URL

    init(directory: URL, failSecond: Bool = false, duplicateMode: String? = nil) {
        self.directory = directory
        store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        vault = CredentialVault(service: "T16.fixture.\(directory.lastPathComponent)")
        bindings = CodexAccountBindingStore(accountStore: store, vault: vault)
        server = T16MultiAccountServer(store: store, failSecond: failSecond, duplicateMode: duplicateMode)
        let vault = vault
        updater = CodexQuotaService(store: store, loadCredential: { try await vault.load(for: .credential($0)) },
            transport: server, checkNetwork: { .allowed(score: 51) })
    }

    func makeFlow(orderingFailsOnce: Bool = false) -> CodexConnectionFlow {
        let server = server
        let flowBindings: any CodexAccountBinding = orderingFailsOnce ? T17OrderFailureBindings(base: bindings) : bindings
        return CodexConnectionFlow(checkNetwork: { .allowed(score: 51) }, authorizer: server,
            transactions: CodexLoginTransactionStore(vault: vault), completer: server, verifier: server,
            bindings: flowBindings, pending: CodexPendingLoginStore(vault: vault), quotaUpdater: updater,
            copyCode: { _, _ in }, openURL: { _ in await server.openWebsite(); return true })
    }

    func cleanup() async throws {
        let transactions = CodexLoginTransactionStore(vault: vault)
        if let auth = try await transactions.load() {
            try await CodexPendingLoginStore(vault: vault).remove(transactionID: auth.transactionID)
            try await transactions.remove(transactionID: auth.transactionID)
        }
        for account in try await store.load() { try await vault.remove(for: .credential(account.credentialRef)) }
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
}

actor T16MultiAccountServer: CodexDeviceAuthorizing, CodexLoginCompleting, CodexIdentityVerifying, CodexDeviceAuthorizationTransport {
    let store: AccountStore
    let failSecond: Bool
    private var opened = false
    private(set) var requests: [URLRequest] = []
    private var duplicateMode: String?
    init(store: AccountStore, failSecond: Bool, duplicateMode: String? = nil) {
        self.store = store; self.failSecond = failSecond; self.duplicateMode = duplicateMode
    }
    func setDuplicateMode(_ mode: String) { duplicateMode = mode }
    func openWebsite() { opened = true }
    func requestAuthorization() async throws -> CodexDeviceAuthorization {
        opened = false
        let index = try await store.load().count + 1
        return try .init(deviceAuthID: "\(index)", userCode: "TEST-\(index)", pollInterval: 1, startedAt: Date())
    }
    func poll(_ authorization: CodexDeviceAuthorization) async throws -> CodexAuthorizationCode? {
        guard opened else { return nil }
        return .init(code: authorization.deviceAuthID, verifier: String(repeating: "v", count: 43))
    }
    func exchange(_ code: CodexAuthorizationCode) async throws -> CodexTokenResponse {
        .init(accessToken: code.code, refreshToken: "fixture-refresh", idToken: "fixture-id", obtainedAt: Date(), expiresAt: nil)
    }
    func verify(_ tokens: CodexTokenResponse) async throws -> CodexVerifiedLogin {
        let index = tokens.accessToken
        let duplicate = duplicateMode != nil && index == "3"
        if duplicate && duplicateMode == "verify-failure" { throw CodexLoginError.failed }
        let identity = duplicate ? "1" : index
        let scopeIndex = duplicate && duplicateMode != "scope" ? "1" : index
        let scope = AccountScope(remoteAccountID: "t16-\(scopeIndex)", kind: .personal)
        let package = CodexIdentityVerifier.CredentialPackage(credentialVersion: 1,
            issuer: CodexIdentityVerifier.issuer, clientID: CodexDeviceAuthorization.clientID,
            subject: "fixture-subject-\(identity)", remoteUserID: "t16-user-\(identity)", scope: scope, tokens: tokens)
        return .fixture(remoteUserID: package.remoteUserID, email: "account-\(identity)@example.invalid", scope: scope,
            credentials: CredentialPayload(data: try JSONEncoder().encode(package)))
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let scope = request.value(forHTTPHeaderField: "ChatGPT-Account-Id") ?? ""
        let token = request.value(forHTTPHeaderField: "Authorization") ?? ""
        guard let index = Int(token.replacingOccurrences(of: "Bearer ", with: "")) else { throw CodexQuotaError.failed }
        let duplicate = duplicateMode != nil && index == 3
        let scopeIndex = duplicate && duplicateMode != "scope" ? 1 : index
        guard scope == "t16-\(scopeIndex)" else {
            throw CodexQuotaError.failed
        }
        if failSecond && index == 2 { throw URLError(.notConnectedToInternet) }
        if duplicate && (duplicateMode == "quota-failure" || duplicateMode == "scope") { throw URLError(.notConnectedToInternet) }
        let used = duplicate ? 45 : (index == 1 ? 20 : 65)
        let body = """
        {"account_id":"\(scope)","plan_type":"Plus","rate_limit":{"primary_window":{"limit_window_seconds":18000,"used_percent":\(used + 10),"reset_at":1800010000},"secondary_window":{"limit_window_seconds":604800,"used_percent":\(used),"reset_at":1800500000}}}
        """
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                               headerFields: ["Content-Type": "application/json"])!)
    }
}
/// Failure injection is limited to the explicit isolated UI fixture.
@MainActor
private final class T17OrderFailureBindings: CodexAccountBinding, AccountOrdering {
    let base: CodexAccountBindingStore
    var failNext = true
    init(base: CodexAccountBindingStore) { self.base = base }
    func load() async throws -> [ConnectedAccount] { try await base.load() }
    func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount { try await base.save(login) }
    func save(_ login: CodexVerifiedLogin, transactionID: UUID) async throws -> ConnectedAccount {
        try await base.save(login, transactionID: transactionID)
    }
    func reorder(_ ids: [UUID]) async throws {
        if failNext { failNext = false; throw CocoaError(.fileWriteUnknown) }
        try await base.reorder(ids)
    }
}
/// T26 uses synthetic credentials, a temporary file and a fake HTTP transport.
/// Its production service still executes the real network-gate/parse/store path.
actor T26BatchFixture: CodexAccountBinding, CodexQuotaUpdating, CodexDeviceAuthorizationTransport, AccountRemoving {
    nonisolated let directory: URL
    let store: AccountStore
    let scenario: String
    let count: Int
    var seeded = false
    var attempts: [UUID: Int] = [:]
    var checks: [UUID: Int] = [:]
    var requests: [String: Int] = [:]
    var waiting: [CheckedContinuation<Void, Never>] = []
    var released = false
    var active = 0
    var maximumActive = 0
    static let oldTime = Date(timeIntervalSince1970: 1_791_590_400)
    static let newTime = Date(timeIntervalSince1970: 1_791_594_000)

    init(scenario: String, count: Int = 2, widgetStore: WidgetSnapshotStore? = nil,
         reloadWidgets: @escaping @Sendable () -> Void = {}) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("T26-\(UUID())")
        store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"),
                             widgetStore: widgetStore, reloadWidgets: reloadWidgets)
        self.scenario = scenario
        self.count = count
    }

    func load() async throws -> [ConnectedAccount] {
        if !seeded {
            seeded = true
            for index in 0..<count {
                var account = ConnectedAccount(remoteUserID: "t26-user-\(index)", verifiedEmail: "batch-\(index + 1)@example.invalid",
                    scope: .init(remoteAccountID: "t26-account-\(index)", kind: .personal), credentialRef: UUID())
                account.subscription = .init(planType: "Plus", observedAt: Self.oldTime)
                account.quotaState = .available
                account.quotaSnapshot = try CodexUsageParser().parse(Self.body(account.scope.remoteAccountID, used: 10 + index * 20),
                    for: account, observedAt: Self.oldTime)
                try await store.append(account)
            }
        }
        return try await store.load()
    }
    func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount { throw CodexQuotaError.failed }
    func removeAccount(_ id: UUID) async throws {
        _ = try await store.markForDeletion(id)
        try await store.finishDeletion(id)
    }
    func update(_ account: ConnectedAccount) async throws -> ConnectedAccount {
        active += 1; maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        attempts[account.id, default: 0] += 1
        let attempt = attempts[account.id]!
        let tokens = CodexTokenResponse(accessToken: "t26-synthetic-access", refreshToken: "t26-synthetic-refresh",
            idToken: "t26-synthetic-id", obtainedAt: Self.oldTime, expiresAt: nil)
        let package = CodexIdentityVerifier.CredentialPackage(credentialVersion: 1, issuer: CodexIdentityVerifier.issuer,
            clientID: CodexDeviceAuthorization.clientID, subject: "t26-subject", remoteUserID: account.remoteUserID!,
            scope: account.scope, tokens: tokens)
        let payload = CredentialPayload(data: try JSONEncoder().encode(package))
        let service = CodexQuotaService(store: store, loadCredential: { [scenario] _ in
                if scenario == "t31-credential" && attempt == 1 { throw CredentialVault.VaultError.temporarilyUnavailable }
                return payload
            }, transport: self,
            checkNetwork: { await self.check(account) }, now: { Self.newTime.addingTimeInterval(Double(attempt * 60)) })
        return try await service.update(account)
    }
    func check(_ account: ConnectedAccount) async -> NetworkScoreResult {
        checks[account.id, default: 0] += 1
        if (scenario == "t31-expire" && account.scope.remoteAccountID == "t26-account-1" && checks[account.id] == 1) {
            if !released { await withCheckedContinuation { waiting.append($0) } }
        } else if scenario == "cancel" || (scenario == "slow" && account.scope.remoteAccountID == "t26-account-1") {
            if !released { await withCheckedContinuation { waiting.append($0) } }
        } else if scenario == "ui-staggered" || scenario == "ui-single" || scenario == "ui-auto-failure" {
            try? await Task.sleep(for: .seconds(account.scope.remoteAccountID == "t26-account-0" ? 8 : 20))
        } else if scenario == "ui-t31-expire" {
            let seconds = account.scope.remoteAccountID == "t26-account-1" && checks[account.id] == 2 ? 60 : 4
            try? await Task.sleep(for: .seconds(seconds))
        } else if scenario == "ui-foreground" {
            try? await Task.sleep(for: .seconds(4))
        } else if scenario == "ui-cancel" {
            // Deliberately ignore cancellation until the late allowed result.
            await withCheckedContinuation { continuation in
                Task { try? await Task.sleep(for: .seconds(4)); continuation.resume() }
            }
        } else { try? await Task.sleep(for: .milliseconds(200)) }
        if scenario == "blocked" { return .blocked(score: 50) }
        if scenario == "unknown" || (scenario == "t31-unknown" && checks[account.id] == 1) { return .unavailable(.transport) }
        return .allowed(score: 51)
    }
    func release() {
        released = true
        waiting.forEach { $0.resume() }; waiting.removeAll()
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let id = request.value(forHTTPHeaderField: "ChatGPT-Account-Id")!
        requests[id, default: 0] += 1
        let attempt = requests[id]!
        let fails = (scenario == "partial" || scenario == "ui-auto-failure") && id == "t26-account-1" && attempt == 1
        let body = Self.body(id, used: 40 + attempt * 5)
        return (body, HTTPURLResponse(url: request.url!, statusCode: fails ? 500 : 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!)
    }
    private static func body(_ id: String, used: Int) -> Data {
        Data("""
        {"account_id":"\(id)","plan_type":"Plus","rate_limit":{"primary_window":{"limit_window_seconds":18000,"used_percent":\(used),"reset_at":1791604000},"secondary_window":{"limit_window_seconds":604800,"used_percent":\(used),"reset_at":1792100000}}}
        """.utf8)
    }
}
#endif
