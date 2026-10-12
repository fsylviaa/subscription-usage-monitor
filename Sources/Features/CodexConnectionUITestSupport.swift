#if DEBUG
import Foundation
import WidgetKit
import UserNotifications

/// Only explicit DEBUG launches can use test support; no product menu or saved
/// preference enables it. Fixtures make no external requests. The opt-in live
/// flow uses real clients but an entirely separate account directory and vault.
@MainActor
enum CodexConnectionUITestSupport {
    // Explicit DEBUG event injection only; native objects stay in memory.
    static func injectNotificationLaunchIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--t41-notification-ui"), !args.contains("--t41-warm-only") else { return }
        injectNotificationFixture(target: args.contains("--t41-empty") ? "deleted" : "second")
    }

    static func injectNotificationURLIfRequested(_ url: URL) -> Bool {
        guard ProcessInfo.processInfo.arguments.contains("--t41-notification-ui"),
              url.scheme == "subscriptionusage", url.host == "notification-fixture" else { return false }
        let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
            .first(where: { $0.name == "target" })?.value ?? "second"
        injectNotificationFixture(target: target)
        return true
    }

    private static func injectNotificationFixture(target: String) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--t26-isolated-ui") || args.contains("--management-ui") else { return }
        let index = target == "first" ? 0 : 1
        let ids: [UUID]
        if let marker = args.firstIndex(of: "--t36-account-ids"), args.indices.contains(marker + 2) {
            ids = [args[marker + 1], args[marker + 2]].compactMap(UUID.init(uuidString:))
        } else { ids = [] }
        let account = ConnectedAccount(id: target == "deleted" ? UUID() : (ids.indices.contains(index) ? ids[index] : UUID()),
            remoteUserID: target == "replaced" ? "old-user" : "t26-user-\(index)",
            verifiedEmail: "batch-\(index + 1)@example.invalid",
            scope: .init(remoteAccountID: "t26-account-\(index)", kind: .personal), credentialRef: UUID())
        let date = Date().addingTimeInterval(-60)
        let identifier = "quota-reset.v1.\(account.id.uuidString.lowercased()).\(ResetReminderPlan.bindingKey(account)).\(QuotaWindow.weekly.rawValue).\(date.timeIntervalSince1970)"
        let request = ResetReminderRequest(identifier: target == "malformed" ? "quota-reset.v1.invalid" : identifier,
            accountID: account.id, window: .weekly, resetsAt: date,
            title: "Codex · 隔离账户", body: "周额度预计重置，打开查看")
        if let event = ResetReminderOpenEvent(request: SystemResetReminderNotificationCenter.makeRequest(request),
                                              actionIdentifier: UNNotificationDefaultActionIdentifier) {
            ResetReminderNavigation.shared.receive(event)
        }
    }

    private struct RouteValidationSession: Codable {
        let id: UUID
        let expiresAt: Date
    }
    private static var routeValidationMarker: URL? {
        try? WidgetSnapshotStore.sharedDirectory().appendingPathComponent("T36-route-session.json")
    }
    private static var routeValidationSession: UUID? {
        guard let marker = routeValidationMarker, let data = try? Data(contentsOf: marker),
              let session = try? JSONDecoder().decode(RouteValidationSession.self, from: data),
              session.expiresAt > Date(), session.expiresAt.timeIntervalSinceNow <= 1_200,
              (try? WidgetSnapshotStore.displayStore().resolvedURL()) == (try? WidgetSnapshotStore.validationStore(session: session.id).resolvedURL())
        else { return nil }
        return session.id
    }
    static var isWidgetRouteValidationActive: Bool { routeValidationSession != nil }

    static var preferences: UserDefaults {
        let args = ProcessInfo.processInfo.arguments
        if let session = routeValidationSession {
            return UserDefaults(suiteName: "T36-route-\(session)")!
        }
        if args.contains("--t26-isolated-ui") {
            let preferences = UserDefaults(suiteName: "T26-feedback-fixture")!
            preferences.set(args.contains("--t26-dark") ? "dark" : "light", forKey: "appearance")
            return preferences
        }
        if let marker = args.firstIndex(of: "--t37-widget-fixture"), args.indices.contains(marker + 3),
           let session = UUID(uuidString: args[marker + 2]) {
            let preferences = UserDefaults(suiteName: "T37-widget-\(session)")!
            if args[marker + 1] != "cleanup" { preferences.set(args[marker + 3] == "dark" ? "dark" : "light", forKey: "appearance") }
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
        if let marker = arguments.firstIndex(of: "--t37-widget-fixture") {
            guard arguments.indices.contains(marker + 3), let session = UUID(uuidString: arguments[marker + 2]) else {
                return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) }, authorizer: FixtureAuthorizer(fails: true), transactions: FixtureTransactions())
            }
            let scenario = arguments[marker + 1], appearance = arguments[marker + 3]
            if scenario == "cleanup" {
                let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
                let files = (try? FileManager.default.contentsOfDirectory(at: library.appendingPathComponent("Preferences"), includingPropertiesForKeys: nil)) ?? []
                for file in files where file.pathExtension == "plist" {
                    let name = file.deletingPathExtension().lastPathComponent
                    if name.hasPrefix("T37-widget-"), UUID(uuidString: String(name.dropFirst("T37-widget-".count))) != nil {
                        UserDefaults.standard.removePersistentDomain(forName: name)
                    }
                }
                UserDefaults.standard.removePersistentDomain(forName: "T37-widget-\(session)")
                return widgetValidationFlow(scenario: "cleanup", session: session, useConfiguredAccount: false)
            }
            return t37WidgetValidationFlow(scenario: scenario, session: session, appearance: appearance)
        }
        if let marker = arguments.firstIndex(of: "--t36-desktop-fixture") {
            guard arguments.indices.contains(marker + 2), let session = UUID(uuidString: arguments[marker + 2]),
                  let file = routeValidationMarker else {
                return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) }, authorizer: FixtureAuthorizer(fails: true), transactions: FixtureTransactions())
            }
            let scenario = arguments[marker + 1]
            if scenario == "cleanup" {
                try? FileManager.default.removeItem(at: file)
                UserDefaults.standard.removePersistentDomain(forName: "T36-route-\(session)")
                return widgetValidationFlow(scenario: "cleanup", session: session, useConfiguredAccount: false)
            }
            do {
                try WidgetSnapshotStore.setValidationSession(session)
                try JSONEncoder().encode(RouteValidationSession(id: session, expiresAt: Date().addingTimeInterval(1_200)))
                    .write(to: file, options: .atomic)
            } catch { return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) }, authorizer: FixtureAuthorizer(fails: true), transactions: FixtureTransactions()) }
            return widgetValidationFlow(scenario: scenario, session: session, useConfiguredAccount: true)
        }
        // Explicit, time-bounded developer session also survives a real widget
        // cold launch, whose process receives no test launch arguments.
        if let session = routeValidationSession {
            return widgetValidationFlow(scenario: "baseline", session: session, useConfiguredAccount: true)
        }
        if let marker = arguments.firstIndex(of: "--t35-widget-fixture") {
            guard arguments.indices.contains(marker + 2), let session = UUID(uuidString: arguments[marker + 2]) else {
                // Malformed isolation arguments must never fall through to real accounts.
                return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) },
                    authorizer: FixtureAuthorizer(fails: true), transactions: FixtureTransactions())
            }
            return widgetValidationFlow(scenario: arguments[marker + 1], session: session, useConfiguredAccount: arguments.contains("--t35-configured-account"))
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
            let ids: [UUID]
            if let index = arguments.firstIndex(of: "--t36-account-ids"), arguments.indices.contains(index + 2) {
                ids = [arguments[index + 1], arguments[index + 2]].compactMap(UUID.init(uuidString:))
            } else { ids = [] }
            let fixture = T26BatchFixture(scenario: arguments[marker + 1], widgetAccountIDs: ids)
            let flow = CodexConnectionFlow(transactions: arguments.contains("--t36-delay-login-read")
                    ? T15DelayedTransactions() : FixtureTransactions(), bindings: fixture, quotaUpdater: fixture,
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

    /// Reuses the T35 namespace and actual AccountStore failure publication. No real data or settings writes.
    private static func t37WidgetValidationFlow(scenario: String, session: UUID, appearance: String) -> CodexConnectionFlow {
        guard let shared = try? WidgetSnapshotStore.validationStore(session: session) else {
            return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) }, authorizer: FixtureAuthorizer(fails: true), transactions: FixtureTransactions())
        }
        let fixture = T26BatchFixture(scenario: "t37-" + scenario, count: 1, widgetAccountIDs: [session], widgetStore: shared)
        let flow = CodexConnectionFlow(transactions: FixtureTransactions(), bindings: fixture, quotaUpdater: fixture, foregroundRefreshEnabled: false)
        Task {
            do {
                try WidgetSnapshotStore.setValidationSession(session)
                let directory = try shared.resolvedURL().deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data(appearance.utf8).write(to: directory.appendingPathComponent("T37-appearance"), options: .atomic)
                let original = try await fixture.load()
                let before = try shared.read()
                await flow.loadAccounts()
                if scenario == "empty" { try await fixture.removeAccount(original[0].id); await flow.loadAccounts() }
                if scenario == "failure" || scenario == "blocked" {
                    flow.refreshAllQuota()
                    await flow.waitForInitialQuota()
                    guard let after = try shared.read(), let old = before?.account, let current = after.account,
                          old.id == current.id, old.identity == current.identity,
                          old.weekly == current.weekly, old.fiveHours == current.fiveHours,
                          old.quotaObservedAt == current.quotaObservedAt,
                          old.subscriptionObservedAt == current.subscriptionObservedAt,
                          current.failure == (scenario == "blocked" ? .networkBlocked : .refresh) else { throw CodexQuotaError.failed }
                    print("T37 | failure oldValuesAndSuccessTimePreserved=true | \(scenario)")
                }
                if scenario == "updating" { flow.refreshAllQuota() }
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppearance.kind)
                print("T37 | ready | \(scenario) | \(appearance) | \(Date().ISO8601Format())")
            } catch { print("T37 | preparation failed | \(scenario)") }
        }
        return flow
    }

    private static func widgetValidationFlow(scenario: String, session: UUID, useConfiguredAccount: Bool) -> CodexConnectionFlow {
        guard scenario != "cleanup", let shared = try? WidgetSnapshotStore.validationStore(session: session) else {
            do {
                try WidgetSnapshotStore.setValidationSession(nil)
                if scenario == "cleanup" {
                    let journal = FileManager.default.temporaryDirectory.appendingPathComponent("T30-debug")
                    if FileManager.default.fileExists(atPath: journal.path) {
                        try FileManager.default.removeItem(at: journal)
                    }
                    // T35 uses T26BatchFixture; remove only its synthetic UUID directories.
                    let temporary = FileManager.default.temporaryDirectory
                    let batches = try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil).filter {
                        $0.lastPathComponent.hasPrefix("T26-")
                            && UUID(uuidString: String($0.lastPathComponent.dropFirst(4))) != nil
                    }
                    for batch in batches { try FileManager.default.removeItem(at: batch) }
                    print("T35 CLEANUP | isolatedBackgroundJournalRemoved=true | removedBatchFixtures=\(batches.count)")
                }
            } catch { print("T35 CLEANUP | failed") }
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppearance.kind)
            return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) },
                authorizer: FixtureAuthorizer(fails: true), transactions: FixtureTransactions())
        }
        if scenario == "reloadOnly" {
            // A diagnostic control: reuse exactly the background publication.
            // No fixture seeding, account writes or quota query is allowed here.
            try? WidgetSnapshotStore.setValidationSession(session)
            let amounts = (try? shared.read()?.allAccounts.map { $0.weekly?.amount.remainingPercent ?? -1 }) ?? []
            WidgetSnapshotStore.traceValidation("foreground.reloadOnly", detail: "remaining=\(amounts)")
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppearance.kind)
            return CodexConnectionFlow(checkNetwork: { .unavailable(.transport) },
                authorizer: FixtureAuthorizer(fails: true), transactions: FixtureTransactions())
        }
        // Keep synthetic identities stable across this session's app relaunches,
        // so the system's per-widget account choice can be tested across sorting.
        var accountIDs = [0, 1].map { index -> UUID in
            var bytes = session.uuid
            bytes.15 = UInt8(index)
            return UUID(uuid: bytes)
        }
        // An unresolved saved widget selection may be absent from getCurrentConfigurations.
        // A diagnostic can explicitly preserve that observed local UUID in synthetic data.
        let arguments = ProcessInfo.processInfo.arguments
        if scenario == "backgroundBaseline", let index = arguments.firstIndex(of: "--t35-preserved-account-id"),
           arguments.indices.contains(index + 1), let id = UUID(uuidString: arguments[index + 1]) {
            accountIDs[1] = id
        }
        let fixture = T26BatchFixture(scenario: scenario == "failure" ? "blocked" : (["backgroundBaseline", "autonomous"].contains(scenario) ? "widget-background" : "success"),
            widgetAccountIDs: accountIDs, useConfiguredAccount: useConfiguredAccount, widgetStore: shared, reloadWidgets: {
                let amounts = (try? shared.read()?.allAccounts.map { "\($0.identity)=\($0.weekly?.amount.remainingPercent ?? -1)" }) ?? []
                print("T35 | 请求组件更新 | \(Date().ISO8601Format()) | \(amounts.joined(separator: ","))")
                WidgetSnapshotStore.traceValidation("reload.request", detail: amounts.joined(separator: ","))
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppearance.kind)
                WidgetSnapshotStore.traceValidation("reload.return")
            })
        let flow = CodexConnectionFlow(transactions: FixtureTransactions(), bindings: fixture, quotaUpdater: fixture,
                                       foregroundRefreshEnabled: scenario == "foreground")
        Task {
            do {
                let original = try await fixture.load()
                try WidgetSnapshotStore.setValidationSession(session)
                await flow.loadAccounts()
                switch scenario {
                case "autonomous":
                    let directory = try shared.resolvedURL().deletingLastPathComponent()
                    let widgetAccounts = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"), widgetStore: shared)
                    for account in original {
                        try await widgetAccounts.append(account)
                        try await WidgetFixtureCredentials.prepare(account, in: directory)
                    }
                    try Data("T61".utf8).write(to: directory.appendingPathComponent("T61-enabled"), options: .atomic)
                case "single": flow.refreshQuota(for: original[0].id)
                case "all", "failure": flow.refreshAllQuota()
                case "reorder": try await fixture.store.reorder(original.reversed().map(\.id))
                case "reorderRefresh":
                    try await fixture.store.reorder(original.reversed().map(\.id))
                    await flow.loadAccounts()
                    flow.refreshAllQuota()
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
                if ["reorder", "reorderRefresh", "remove", "scope", "empty"].contains(scenario) { await flow.loadAccounts() }
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
                    subscription: .init(planType: plan, observedAt: now,
                        resetCardCount: scenario == "resetCards" && index == 1 ? 2 : nil))
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
            if scenario == "noFive" {
                var pro = account(1, plan: "Pro", weekly: .limited(try .init(used: 30)), fiveHours: .unknown)
                let body = #"{"plan_type":"pro","rate_limit":{"primary_window":{"limit_window_seconds":604800,"used_percent":30},"secondary_window":null}}"#
                let parsed = try CodexUsageParser().parse(Data(body.utf8), for: pro, observedAt: now)
                pro.subscription = .init(planType: "pro", observedAt: now)
                pro.quotaSnapshot = parsed
                return [pro, account(2, plan: "Plus", weekly: .limited(try .init(used: 30)), fiveHours: .unknown)]
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
    private var seedTask: Task<Void, Error>?
    var attempts: [UUID: Int] = [:]
    var checks: [UUID: Int] = [:]
    var requests: [String: Int] = [:]
    var waiting: [CheckedContinuation<Void, Never>] = []
    var released = false
    var active = 0
    var maximumActive = 0
    static let oldTime = Date(timeIntervalSince1970: 1_791_590_400)
    static let newTime = Date(timeIntervalSince1970: 1_791_594_000)

    private let widgetAccountIDs: [UUID]
    private let useConfiguredAccount: Bool

    init(scenario: String, count: Int = 2, widgetAccountIDs: [UUID] = [], useConfiguredAccount: Bool = false, widgetStore: WidgetSnapshotStore? = nil,
         reloadWidgets: @escaping @Sendable () -> Void = {}) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("T26-\(UUID())")
        store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"),
                             widgetStore: widgetStore, reloadWidgets: reloadWidgets)
        self.scenario = scenario
        self.count = count
        self.widgetAccountIDs = widgetAccountIDs
        self.useConfiguredAccount = useConfiguredAccount
    }

    func load() async throws -> [ConnectedAccount] {
        if seedTask == nil {
            seedTask = Task {
                var ids = widgetAccountIDs
                if useConfiguredAccount, !ids.isEmpty {
                    let configurations: [WidgetInfo] = try await withCheckedThrowingContinuation { continuation in
                        WidgetCenter.shared.getCurrentConfigurations { continuation.resume(with: $0) }
                    }
                    let configured = configurations.filter { $0.kind == WidgetAppearance.kind }
                        .compactMap { $0.widgetConfigurationIntent(of: QuotaWidgetConfiguration.self)?.account?.id }
                        .compactMap(UUID.init(uuidString:)).sorted { $0.uuidString < $1.uuidString }
                    let unique = Array(Set(configured)).sorted { $0.uuidString < $1.uuidString }
                    if scenario == "widget-background" {
                        guard unique.count <= ids.count else { throw CodexQuotaError.failed }
                        for (index, id) in unique.enumerated() { ids[index] = id }
                    } else if let pinned = unique.first { ids[0] = pinned }
                    print("T35 | 已有固定账户配置 | \(!configured.isEmpty) | configured=\(configurations.count) uniquePinned=\(unique.count)")
                }
                for index in 0..<count {
                    var account = ConnectedAccount(id: ids.indices.contains(index) ? ids[index] : UUID(),
                        remoteUserID: "t26-user-\(index)", verifiedEmail: "batch-\(index + 1)@example.invalid",
                        scope: .init(remoteAccountID: "t26-account-\(index)", kind: .personal), credentialRef: UUID())
                    account.subscription = .init(planType: "Plus", observedAt: Self.oldTime)
                    account.quotaState = .available
                    account.quotaSnapshot = try CodexUsageParser().parse(Self.body(account.scope.remoteAccountID, used: scenario == "widget-background" ? 10 : 10 + index * 20),
                        for: account, observedAt: Self.oldTime)
                    if scenario.hasPrefix("t37-") {
                        let name = String(scenario.dropFirst(4))
                        account.verifiedEmail = "t37-\(name)@example.invalid"
                        if name == "long" { account.verifiedEmail = "t37-long-account-identifier-with-many-parts-and-very-long-name@example.invalid" }
                        let weekly: QuotaAmount = name == "endpoints" ? .limited(try .init(used: 100)) : (name == "unknown" ? .unknown : .limited(try .init(used: 30)))
                        let five: QuotaAmount = name == "endpoints" ? .limited(try .init(used: 0)) : (name == "unknown" ? .unlimited : .limited(try .init(used: 15)))
                        account.quotaSnapshot = .init(accountID: account.id, provider: account.provider, product: account.product,
                            scope: account.scope, generation: account.generation, planType: "Plus", observedAt: Self.oldTime,
                            weekly: .init(window: .weekly, amount: weekly, resetsAt: nil, observedAt: Self.oldTime),
                            fiveHours: .init(window: .fiveHours, amount: five, resetsAt: nil, observedAt: Self.oldTime))
                        if name == "free" { account.subscription = .init(planType: "Free", observedAt: Self.oldTime); account.quotaState = .notApplicable; account.quotaSnapshot = nil }
                        if name == "notFetched" { account.subscription = nil; account.quotaState = .notFetched; account.quotaSnapshot = nil }
                    }
                    try await store.append(account)
                }
            }
        }
        // A second caller must await the complete seed, not observe a partial list.
        try await seedTask?.value
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
        if scenario == "t37-updating" || scenario == "t37-notFetched" {
            if !released { await withCheckedContinuation { waiting.append($0) } }
        } else if (scenario == "t31-expire" && account.scope.remoteAccountID == "t26-account-1" && checks[account.id] == 1) {
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
        if scenario == "blocked" || scenario == "t37-blocked" { return .blocked(score: 50) }
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
        let fails = scenario == "t37-failure" || ((scenario == "partial" || scenario == "ui-auto-failure") && id == "t26-account-1" && attempt == 1)
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
