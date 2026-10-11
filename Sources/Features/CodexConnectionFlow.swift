import Foundation
import SwiftUI
import UIKit

/// The selectable products and their icons; adding a product also requires its
/// explicit connection route below. No unavailable products are advertised.
enum ConnectionPlatform: CaseIterable {
    case codex

    var iconName: String { switch self { case .codex: "Codex" } }
    var accessibilityName: String { switch self { case .codex: "Codex" } }
}

@MainActor
final class CodexConnectionFlow: ObservableObject {
    enum State: Equatable {
        case idle
        case choosingPlatform
        case checking
        case requesting
        case verifying
        case saving
        case quota
        case code(CodexDeviceAuthorization)
        case failure(String)
    }

    @Published private(set) var state: State = .idle
    @Published var isPresented = false
    @Published private(set) var copied = false
    @Published private(set) var browserFailed = false

    @Published private(set) var accounts: [ConnectedAccount] = []
    @Published private(set) var loadingAccounts = false
    @Published private(set) var accountLoadFailed = false
    @Published private(set) var reorderingAccounts = false
    @Published private(set) var accountOrderFailed = false
    @Published private(set) var demoEnabled = false
    @Published private(set) var managingAccounts = false
    @Published var accountActionFailure: String?
    var canManageAccounts: Bool {
        !loadingAccounts && !accountLoadFailed && !restoringLogin && !reorderingAccounts && !managingAccounts && !isPresented
    }

    @discardableResult
    func setDemoMode(_ enabled: Bool) -> Task<Void, Never>? {
        guard canManageAccounts, let manager = bindings as? any DemoAccountManaging else { return nil }
        managingAccounts = true
        return Task {
            defer { managingAccounts = false; refreshPendingForeground() }
            do {
                if !enabled { await cancelDemoQuota() }
                accounts = try await manager.setDemoMode(enabled)
                demoEnabled = enabled
                discardRemovedFeedback()
            } catch { accountActionFailure = "操作未完成，请重试" }
        }
    }

    @discardableResult
    func deleteAccount(_ id: UUID) -> Task<Void, Never>? {
        guard canManageAccounts, let remover = bindings as? any AccountRemoving,
              accounts.contains(where: { $0.id == id }) else { return nil }
        managingAccounts = true
        cancelRequests(where: { $0.id == id })
        return Task {
            defer { managingAccounts = false; refreshPendingForeground() }
            do {
                // Persist deletion before a non-cooperative request can finish.
                try await remover.removeAccount(id)
                accounts.removeAll { $0.id == id }
                discardRemovedFeedback()
            } catch { accountActionFailure = "删除未完成，请重试" }
        }
    }

    private func cancelDemoQuota() async {
        cancelRequests(where: { $0.isDemo })
    }

    private func discardRemovedFeedback() {
        let ids = Set(accounts.map(\.id))
        quotaFailures = quotaFailures.filter { ids.contains($0.key) }
        if let id = quotaFailureID, !ids.contains(id) { quotaFailureID = nil; quotaFailure = nil }
    }

    @discardableResult
    func addDemoAccount() -> Task<Void, Never>? {
        guard demoEnabled, canConnect, let manager = bindings as? any DemoAccountManaging else { return nil }
        managingAccounts = true
        return Task {
            defer { managingAccounts = false; refreshPendingForeground() }
            do { accounts.append(try await manager.addDemo(now: now())) }
            catch { accountActionFailure = "添加失败，请重试" }
        }
    }
    @Published private(set) var manualQuotaInProgress = false
    @Published private(set) var quotaUpdatingID: UUID?
    @Published private(set) var quotaUpdatingIDs: Set<UUID> = []
    var visibleQuotaUpdatingIDs: Set<UUID> { manualQuotaIDs.intersection(quotaUpdatingIDs) }
    private var manualQuotaIDs: Set<UUID> = []
    private var batchQuotaIDs: [UUID]?
    var canRefreshAll: Bool { canManageAccounts && !Set(accounts.map(\.id)).isSubset(of: manualQuotaIDs) && !accounts.isEmpty && quotaUpdater != nil }
    @Published private(set) var quotaFailure: String?
    @Published private(set) var quotaFailureID: UUID?
    @Published private(set) var quotaFailures: [UUID: String] = [:]
    enum QuotaFeedbackLocation { case connection, dashboard }
    @Published private(set) var quotaFeedbackLocation: QuotaFeedbackLocation = .dashboard
    @Published private(set) var quotaFeedbackHidden = false
    private let quotaUpdater: (any CodexQuotaUpdating)?
    private struct QuotaKey: Hashable {
        let id: UUID
        let generation: UInt64
        let credential: UUID
        init(_ account: ConnectedAccount) {
            id = account.id; generation = account.generation; credential = account.credentialRef
        }
    }
    private struct QuotaRequest {
        let executionID = UUID()
        let account: ConnectedAccount
        var connection: Bool
        var work: Task<Void, Never>?
    }
    private var quotaRequests: [QuotaKey: QuotaRequest] = [:]
    private var quotaQueue: [QuotaKey] = []
    private var refreshTargets: [ConnectedAccount] = []
    private var hiddenQuotaFailures: Set<UUID> = []
    private var failureScopes: [UUID: [UUID]] = [:]
    @Published private(set) var restoringLogin = false
    private let completer: (any CodexLoginCompleting)?
    private let verifier: (any CodexIdentityVerifying)?
    private let bindings: (any CodexAccountBinding)?
    private let pending: (any CodexPendingLoginStoring)?
    private var completionWork: Task<Void, Never>?
    private var isActive = true
    private let foregroundRefreshEnabled: Bool
    private var observesSceneActivity = false
    private var sceneIsActive = false
    private var cachedAccountsLoaded = false
    private var pendingForegroundRefresh = false
    private var expiryWork: Task<Void, Never>?
    private var cleanupWork: Task<Void, Never>?
    private var startupWork: Task<Void, Never>?
    private var needsPersistentRestore = false
    private var interruptedCompletion = false
    private enum Recovery {
        case polling(CodexDeviceAuthorization)
        case code(CodexDeviceAuthorization, CodexAuthorizationCode)
        case tokens(CodexDeviceAuthorization, CodexTokenResponse)
        var authorization: CodexDeviceAuthorization {
            switch self {
            case let .polling(value), let .code(value, _), let .tokens(value, _): return value
            }
        }
    }
    private var recovery: Recovery?
    private var authorization: CodexDeviceAuthorization?

    static func live() -> CodexConnectionFlow {
        do {
            let accounts = try AccountStore.applicationStore()
            let vault = CredentialVault.applicationVault()
            let updater = CoordinatedQuotaUpdater.live(store: accounts)
            let flow = CodexConnectionFlow(completer: CodexLoginClient(), verifier: CodexIdentityVerifier(),
                                           bindings: CodexAccountBindingStore(accountStore: accounts, vault: vault),
                                           pending: CodexPendingLoginStore(), quotaUpdater: updater)
            flow.loadingAccounts = true
            return flow
        } catch {
            let flow = CodexConnectionFlow()
            flow.accountLoadFailed = true
            return flow
        }
    }

    var canConnect: Bool { !loadingAccounts && !accountLoadFailed && !restoringLogin && !reorderingAccounts && !managingAccounts && quotaUpdatingID == nil }

    var canReorderAccounts: Bool {
        accounts.count > 1 && bindings is any AccountOrdering && !loadingAccounts
            && !accountLoadFailed && !restoringLogin && !reorderingAccounts && !managingAccounts && !isPresented
            && state == .idle
    }

    func dismissAccountOrderFailure() { accountOrderFailed = false }

    @discardableResult
    func moveAccounts(from offsets: IndexSet, to destination: Int) -> Task<Void, Never>? {
        guard canReorderAccounts, let ordering = bindings as? any AccountOrdering,
              !offsets.isEmpty, offsets.allSatisfy({ accounts.indices.contains($0) }),
              (0...accounts.count).contains(destination) else { return nil }
        var ids = accounts.map(\.id)
        ids.move(fromOffsets: offsets, toOffset: destination)
        guard ids != accounts.map(\.id) else { return nil }
        reorderingAccounts = true
        accountOrderFailed = false
        return Task {
            defer { reorderingAccounts = false; refreshPendingForeground() }
            do {
                try await ordering.reorder(ids)
                // Publish only after durable success. Use the latest in-memory
                // records so a quota response during saving cannot be undone.
                let current = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
                accounts = ids.compactMap { current[$0] }
            } catch {
                accountOrderFailed = true
            }
        }
    }

    /// RootView can appear more than once; restoration is one serialized operation.
    func loadAccounts() async {
        if let startupWork { await startupWork.value; return }
        let task = Task { [weak self] in await self?.loadAndRestore() }
        startupWork = Task { await task.value }
        await startupWork?.value
    }

    private func loadAndRestore() async {
        guard let bindings else { return }
        loadingAccounts = true
        restoringLogin = true
        let attempt = generation
        defer { loadingAccounts = false; restoringLogin = false }
        do {
            accounts = try await bindings.load()
            demoEnabled = try await (bindings as? any DemoAccountManaging)?.demoModeEnabled() ?? false
            accountLoadFailed = false
            // An existing account is readable before pending login/Keychain
            // recovery finishes. New connections stay gated independently until
            // restoration resolves, even when the cached list is already visible.
            if !accounts.isEmpty { loadingAccounts = false }
        } catch {
            accountLoadFailed = true
            return
        }
        cachedAccountsLoaded = true
        if observesSceneActivity && foregroundRefreshEnabled {
            // Publish trusted cache first. Login recovery may wait on storage or
            // browser authorization, so it must not hold up existing accounts.
            refreshPendingForeground()
        } else {
            for account in accounts where account.quotaState == .notFetched || account.subscription == nil {
                startInitialQuota(for: account)
            }
        }
        // Resume an unfinished addition even when other accounts are present.
        do {
            needsPersistentRestore = true
            let found = try await readPersistedRecovery()
            guard found else { return }
            // Legacy first-fetch restoration used one feedback slot. Foreground
            // batches use the dashboard and must not delay the login's resumption.
            if !observesSceneActivity || !foregroundRefreshEnabled {
                await waitForInitialQuota()
            }
            guard generation == attempt, !Task.isCancelled else { return }
            loadingAccounts = false
            restoringLogin = false
            await begin()?.value
        } catch {
            guard generation == attempt, !Task.isCancelled else { return }
            isPresented = true
            state = .failure("登录未完成，请重试")
        }
    }

    private func readPersistedRecovery() async throws -> Bool {
        let attempt = generation
        let saved: CodexDeviceAuthorization?
        do {
            if let cancelledID = try await transactions.loadCancelledTransactionID() {
                try await checkRestoration(attempt, transactionID: cancelledID)
                pendingID = cancelledID
                try await removePending()
                needsPersistentRestore = false
                return false
            }
            saved = try await transactions.load()
        } catch CodexLoginError.failed {
            // An undecodable header cannot safely resume. Discard only that
            // invalid fixed slot; temporary Keychain availability is retryable.
            try await transactions.discardInvalidRecord()
            needsPersistentRestore = false
            throw CodexLoginError.failed
        }
        try await checkRestoration(attempt, transactionID: saved?.transactionID)
        guard let saved else {
            needsPersistentRestore = false
            return false
        }
        pendingID = saved.transactionID
        if accounts.contains(where: { $0.loginTransactionID == saved.transactionID }) {
            try await removePending()
            needsPersistentRestore = false
            return false
        }
        let phase: CodexPendingLoginState?
        do {
            phase = try await pending?.load(transactionID: saved.transactionID)
        } catch CodexLoginError.failed {
            try await removePending()
            needsPersistentRestore = false
            throw CodexLoginError.failed
        }
        try await checkRestoration(attempt, transactionID: saved.transactionID)
        guard !saved.isExpired(at: now()) else {
            try await removePending()
            needsPersistentRestore = false
            throw CodexLoginError.failed
        }
        switch phase {
        case nil: recovery = .polling(saved)
        case let .codeReady(code): recovery = .code(saved, code)
        case let .tokensReady(tokens): recovery = .tokens(saved, tokens)
        case .exchangeStarted:
            try await removePending()
            needsPersistentRestore = false
            throw CodexLoginError.failed
        }
        authorization = saved
        needsPersistentRestore = false
        return true
    }

    private func checkRestoration(_ attempt: UUID, transactionID: UUID?) async throws {
        guard generation == attempt, !Task.isCancelled else {
            // Cancel may arrive before a suspended read reveals its transaction ID.
            // Invalidate that exact late result before allowing another attempt.
            if let transactionID {
                try await transactions.cancel(transactionID: transactionID)
                try await pending?.remove(transactionID: transactionID)
                try await transactions.remove(transactionID: transactionID)
            }
            needsPersistentRestore = false
            throw CancellationError()
        }
    }

    func setActive(_ active: Bool) {
        let returned = active && !isActive
        isActive = active
        if !active { interruptedCompletion = true }
        guard returned else { return }
        expireIfNeeded()
        // The existing task wakes at its next safe stage. Only a recoverable
        // interrupted failure needs a fresh gate; foreground events never fork it.
        if isFailure, recovery != nil { begin() }
    }

    /// One request for each transition to active, including cold launch. This
    /// is distinct from login polling and never uses cache age as a throttle.
    func sceneActivityChanged(_ active: Bool) {
        observesSceneActivity = true
        let entered = active && !sceneIsActive
        sceneIsActive = active
        setActive(active)
        if entered { pendingForegroundRefresh = true }
        refreshPendingForeground()
    }

    private func refreshPendingForeground() {
        guard foregroundRefreshEnabled, pendingForegroundRefresh, sceneIsActive,
              cachedAccountsLoaded, !accountLoadFailed,
              !managingAccounts, !reorderingAccounts else { return }
        pendingForegroundRefresh = false
        refreshAllQuota(manually: false)
    }

    private let checkNetwork: @Sendable () async -> NetworkScoreResult
    private let authorizer: any CodexDeviceAuthorizing
    private let transactions: any CodexLoginTransactionStoring
    private let now: @Sendable () -> Date
    private let copyCode: @MainActor (String, Date) -> Void
    private let openURL: @MainActor (URL) async -> Bool
    private var work: Task<Void, Never>?
    private var generation = UUID()
    private var pendingID: UUID?

    init(
        checkNetwork: @escaping @Sendable () async -> NetworkScoreResult = { await NetworkScoreChecker().check() },
        authorizer: any CodexDeviceAuthorizing = CodexDeviceAuthorizationClient(),
        transactions: any CodexLoginTransactionStoring = CodexLoginTransactionStore(),
        completer: (any CodexLoginCompleting)? = nil,
        verifier: (any CodexIdentityVerifying)? = nil,
        bindings: (any CodexAccountBinding)? = nil,
        pending: (any CodexPendingLoginStoring)? = nil,
        quotaUpdater: (any CodexQuotaUpdating)? = nil,
        foregroundRefreshEnabled: Bool = true,
        now: @escaping @Sendable () -> Date = { Date() },
        copyCode: @escaping @MainActor (String, Date) -> Void = { code, deadline in
            UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: code]],
                                         options: [.localOnly: true, .expirationDate: deadline])
        },
        openURL: @escaping @MainActor (URL) async -> Bool = { url in
            await UIApplication.shared.open(url, options: [:])
        }
    ) {
        self.foregroundRefreshEnabled = foregroundRefreshEnabled
        self.completer = completer
        self.verifier = verifier
        self.bindings = bindings
        self.pending = pending
        self.quotaUpdater = quotaUpdater
        self.checkNetwork = checkNetwork
        self.authorizer = authorizer
        self.transactions = transactions
        self.now = now
        self.copyCode = copyCode
        self.openURL = openURL
    }

    func showPlatformPicker() {
        guard canConnect, state == .idle, !isPresented else { return }
        if demoEnabled { addDemoAccount(); return }
        state = .choosingPlatform
        isPresented = true
    }

    @discardableResult
    func selectPlatform(_ platform: ConnectionPlatform) -> Task<Void, Never>? {
        guard isPresented, state == .choosingPlatform else { return nil }
        switch platform {
        case .codex: return begin()
        }
    }

    @discardableResult
    func begin() -> Task<Void, Never>? {
        guard !loadingAccounts, !accountLoadFailed, !restoringLogin, !reorderingAccounts, !managingAccounts,
              (quotaUpdatingID == nil || recovery != nil), state == .idle || state == .choosingPlatform || isFailure else { return nil }
        let previousWork = work
        let previousCompletion = completionWork
        let previousCleanup = cleanupWork
        completionWork?.cancel()
        work?.cancel()
        expiryWork?.cancel()
        generation = UUID()
        let attempt = generation
        copied = false
        browserFailed = false
        isPresented = true
        state = .checking
        if let authorization { armExpiry(authorization, attempt: attempt) }
        work = Task { [weak self] in
            guard let self else { return }
            await previousWork?.value
            await previousCompletion?.value
            await previousCleanup?.value
            guard isCurrent(attempt) else { return }
            do {
                if needsPersistentRestore { _ = try await readPersistedRecovery() }
                guard isCurrent(attempt) else { return }
                if recovery?.authorization.isExpired(at: now()) == true { recovery = nil }
                if recovery == nil {
                    authorization = nil
                    expiryWork?.cancel()
                    try await removePending()
                }
                guard isCurrent(attempt) else { return }
                let score = await checkNetwork()
                guard isCurrent(attempt) else { return }
                switch score {
                case let .allowed(value) where value.isFinite && value > 50: break
                case .blocked:
                    state = .failure("网络不达标，无法连接")
                    return
                case .cancelled:
                    cancel()
                    return
                default:
                    state = .failure("登录未完成，请重试")
                    return
                }
                if let recovery, !recovery.authorization.isExpired(at: now()) {
                    activate(recovery, attempt: attempt)
                    return
                }
                // A retained transaction may expire while the fresh gate runs.
                recovery = nil
                authorization = nil
                expiryWork?.cancel()
                try await removePending()
                guard isCurrent(attempt) else { return }
                state = .requesting
                let authorization = try await authorizer.requestAuthorization()
                guard isCurrent(attempt) else { return }
                guard !authorization.isExpired(at: now()) else { throw CodexLoginError.failed }
                pendingID = authorization.transactionID
                try await transactions.save(authorization)
                guard isCurrent(attempt) else {
                    try await transactions.remove(transactionID: authorization.transactionID)
                    return
                }
                guard !authorization.isExpired(at: now()) else { throw CodexLoginError.failed }
                activate(.polling(authorization), attempt: attempt)
            } catch {
                guard isCurrent(attempt) else { return }
                if !needsPersistentRestore {
                    recovery = nil
                    try? await removePending()
                }
                guard isCurrent(attempt) else { return }
                state = .failure("登录未完成，请重试")
            }
        }
        return work
    }

    func cancel() {
        guard state != .saving else { return }
        if needsPersistentRestore, pendingID == nil {
            cancelUnresolvedRecovery()
            return
        }
        invalidate()
        state = .idle
        isPresented = false
    }

    /// A failed Keychain read may hide the ID of an existing transaction. Resolve
    /// and cancel it before dismissing, so a later launch cannot resurrect it.
    private func cancelUnresolvedRecovery() {
        let previousWork = work
        let previousCompletion = completionWork
        let previousCleanup = cleanupWork
        generation = UUID()
        let attempt = generation
        work?.cancel()
        completionWork?.cancel()
        expiryWork?.cancel()
        recovery = nil
        authorization = nil
        copied = false
        browserFailed = false
        state = .checking
        isPresented = true
        cleanupWork = Task { [weak self] in
            await previousWork?.value
            await previousCompletion?.value
            await previousCleanup?.value
            guard let self else { return }
            do {
                let cancelledID = try await transactions.loadCancelledTransactionID()
                let saved = try await transactions.load()
                pendingID = cancelledID ?? saved?.transactionID
                try await removePending()
                needsPersistentRestore = false
                guard generation == attempt else { return }
                state = .idle
                isPresented = false
            } catch {
                guard generation == attempt else { return }
                // Do not claim cancellation is durable while its storage is unreadable.
                state = .failure("登录未完成，请重试")
            }
        }
    }

    /// Invalidate first, then join old writes before removing their exact IDs.
    /// A failed cleanup retains pendingID so the next attempt can retry it.
    private func invalidate() {
        generation = UUID()
        completionWork?.cancel()
        work?.cancel()
        expiryWork?.cancel()
        recovery = nil
        authorization = nil
        copied = false
        browserFailed = false
        guard let id = pendingID else { return }
        let previousWork = work
        let previousCompletion = completionWork
        let previousCleanup = cleanupWork
        cleanupWork = Task { [weak self] in
            guard let self else { return }
            // Make cancellation durable before waiting on a non-cooperative request.
            try? await transactions.cancel(transactionID: id)
            await previousWork?.value
            await previousCompletion?.value
            await previousCleanup?.value
            do {
                try await transactions.cancel(transactionID: id)
                try await pending?.remove(transactionID: id)
                try await transactions.remove(transactionID: id)
                if pendingID == id { pendingID = nil }
            } catch { }
        }
    }

    private func removePending() async throws {
        guard let id = pendingID else { return }
        try await transactions.cancel(transactionID: id)
        try await pending?.remove(transactionID: id)
        try await transactions.remove(transactionID: id)
        if pendingID == id { pendingID = nil }
    }

    func copy() {
        guard let authorization = validAuthorization() else { return }
        copyCode(authorization.userCode, authorization.expiresAt)
        copied = true
    }

    func openWebsite() async {
        guard let authorization = validAuthorization() else { return }
        let attempt = generation
        let opened = await openURL(authorization.verificationURL)
        guard isCurrent(attempt) else { return }
        browserFailed = !opened
    }

    func expireIfNeeded() {
        guard state != .saving, let authorization, authorization.isExpired(at: now()) else { return }
        invalidate()
        state = .failure("登录未完成，请重试")
    }

    private func activate(_ phase: Recovery, attempt: UUID) {
        let authorization = phase.authorization
        self.authorization = authorization
        recovery = phase
        switch phase {
        case .polling: state = .code(authorization)
        case .code, .tokens: state = .verifying
        }
        armExpiry(authorization, attempt: attempt)
        startCompleting(phase, attempt: attempt)
    }

    private func armExpiry(_ authorization: CodexDeviceAuthorization, attempt: UUID) {
        // Applies during verification, retry checks and recoverable failure too.
        expiryWork?.cancel()
        expiryWork = Task { [weak self] in
            let remaining = authorization.expiresAt.timeIntervalSince(self?.now() ?? Date())
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard let self, isCurrent(attempt) else { return }
            expireIfNeeded()
        }
    }

    private func startCompleting(_ initial: Recovery, attempt: UUID) {
        guard let completer, let verifier, let bindings, let pending else { return }
        let authorization = initial.authorization
        interruptedCompletion = false
        completionWork = Task { [weak self] in
            guard let self else { return }
            // Non-nil only at stages that can be retried without replaying a code.
            var safeRecovery: Recovery? = initial
            do {
                var tokens: CodexTokenResponse?
                var code: CodexAuthorizationCode?
                if case let .tokens(_, saved) = initial { tokens = saved }
                if case let .code(_, saved) = initial { code = saved }
                while tokens == nil, code == nil, isCurrent(attempt) {
                    try await waitUntilActive(authorization, attempt: attempt)
                    guard let received = try await completer.poll(authorization) else {
                        try await Task.sleep(for: .seconds(authorization.pollInterval))
                        continue
                    }
                    guard isCurrent(attempt), !authorization.isExpired(at: now()) else { throw CancellationError() }
                    // A received code is recoverable only after this durable write.
                    safeRecovery = nil
                    recovery = nil
                    try await pending.saveCode(received, transactionID: authorization.transactionID)
                    try Task.checkCancellation()
                    code = received
                    safeRecovery = .code(authorization, received)
                    recovery = safeRecovery
                    state = .verifying
                }
                if let code, tokens == nil {
                    try await waitUntilActive(authorization, attempt: attempt)
                    // Persist uncertainty BEFORE sending the single-use exchange.
                    // A crash after this marker must never send the same code twice.
                    safeRecovery = nil
                    recovery = nil
                    try await pending.markExchangeStarted(transactionID: authorization.transactionID)
                    try Task.checkCancellation()
                    let received = try await completer.exchange(code)
                    try Task.checkCancellation()
                    guard isCurrent(attempt), !authorization.isExpired(at: now()) else { throw CancellationError() }
                    try await pending.saveTokens(received, transactionID: authorization.transactionID)
                    try Task.checkCancellation()
                    tokens = received
                    safeRecovery = .tokens(authorization, received)
                    recovery = safeRecovery
                }
                guard let tokens, isCurrent(attempt) else { throw CancellationError() }
                try await waitUntilActive(authorization, attempt: attempt)
                let verified = try await verifier.verify(tokens)
                try await waitUntilActive(authorization, attempt: attempt)
                safeRecovery = nil
                recovery = nil
                state = .saving
                let account = try await bindings.save(verified, transactionID: authorization.transactionID)
                accounts.removeAll { $0.id != account.id && $0.hasSameConnectionEmail(as: account) }
                if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                    accounts[index] = account
                } else {
                    accounts.append(account)
                }
                expiryWork?.cancel()
                self.authorization = nil
                // A cleanup problem cannot turn a committed account into a failure.
                try? await removePending()
                if quotaUpdater != nil {
                    state = .quota
                    startInitialQuota(for: account, location: .connection)
                } else {
                    state = .idle
                    isPresented = false
                }
            } catch {
                guard isCurrent(attempt) else {
                    // A non-cooperative pending write may have finished after cancel.
                    try? await pending.remove(transactionID: authorization.transactionID)
                    return
                }
                let failure = error as? CodexLoginError
                let canResume = !authorization.isExpired(at: now())
                    && (failure == .retryable || failure == .networkBlocked || error is CancellationError)
                if canResume, let safeRecovery {
                    recovery = safeRecovery
                } else {
                    recovery = nil
                    self.authorization = nil
                    expiryWork?.cancel()
                    try? await removePending()
                    guard isCurrent(attempt) else { return }
                    generation = UUID() // Ignore an outstanding browser-open callback.
                }
                copied = false
                browserFailed = false
                state = .failure(failure == .networkBlocked
                    ? "网络不达标，无法连接" : "登录未完成，请重试")
                if canResume, recovery != nil, interruptedCompletion, isActive {
                    begin()
                }
            }
        }
    }

    func refreshQuota(for id: UUID) {
        guard canManageAccounts,
              let account = accounts.first(where: { $0.id == id && $0.deletionPending != true }) else { return }
        enqueueQuota([account], manually: true, location: .dashboard)
    }

    func refreshAllQuota(manually: Bool = true) {
        startQuotaBatch(ids: accounts.filter { $0.deletionPending != true }.map(\.id), manually: manually)
    }

    func retryDashboardQuota(for id: UUID) {
        guard quotaFailureID == id else { return }
        startQuotaBatch(ids: batchQuotaIDs ?? [id])
    }

    private func startQuotaBatch(ids: [UUID], manually: Bool = true) {
        guard manually ? canRefreshAll : (cachedAccountsLoaded && !accountLoadFailed
            && !managingAccounts && !reorderingAccounts && quotaUpdater != nil) else { return }
        let targets = ids.compactMap { id in accounts.first { $0.id == id && $0.deletionPending != true } }
        enqueueQuota(targets, manually: manually, location: .dashboard)
    }

    // Internal interruption only; the dashboard has no cancellation action.
    func cancelQuotaUpdate() {
        guard manualQuotaInProgress else { return }
        cancelRequests(where: { _ in true })
    }

    func retryInitialQuota(for accountID: UUID, location: QuotaFeedbackLocation = .dashboard) {
        guard quotaFailureID == accountID, !managingAccounts,
              let account = accounts.first(where: { $0.id == accountID && $0.deletionPending != true }) else { return }
        enqueueQuota([account], manually: false, location: location)
    }

    func hideQuotaFeedback() {
        guard quotaUpdatingID == nil else { return }
        quotaFeedbackHidden = true
        hiddenQuotaFailures.formUnion(quotaFailures.keys)
    }

    private func startInitialQuota(for account: ConnectedAccount, location: QuotaFeedbackLocation = .dashboard) {
        enqueueQuota([account], manually: false, location: location)
    }

    private func enqueueQuota(_ targets: [ConnectedAccount], manually: Bool, location: QuotaFeedbackLocation) {
        guard quotaUpdater != nil, !targets.isEmpty else { return }
        if quotaRequests.isEmpty {
            refreshTargets = []
            manualQuotaIDs = []
            quotaFailure = nil
            quotaFailureID = nil
            quotaFeedbackHidden = false
            quotaFeedbackLocation = location
        }
        for account in targets {
            let key = QuotaKey(account)
            hiddenQuotaFailures.remove(account.id)
            if quotaRequests[key] == nil || manually {
                failureScopes[account.id] = targets.map(\.id)
            }
            if !refreshTargets.contains(where: { QuotaKey($0) == key }) { refreshTargets.append(account) }
            if manually { manualQuotaIDs.insert(account.id) }
            if quotaRequests[key] != nil {
                // A connection query can join the exact same binding. A new
                // binding has a new key and can never reuse an old response.
                if location == .connection { quotaRequests[key]?.connection = true }
            } else {
                quotaRequests[key] = QuotaRequest(account: account, connection: location == .connection)
                quotaQueue.append(key)
            }
        }
        batchQuotaIDs = refreshTargets.map(\.id)
        updateQuotaActivity()
        startQueuedQuota()
    }

    private func updateQuotaActivity() {
        quotaUpdatingIDs = Set(quotaRequests.keys.map(\.id))
        quotaUpdatingID = refreshTargets.first { quotaUpdatingIDs.contains($0.id) }?.id
        manualQuotaInProgress = !manualQuotaIDs.intersection(quotaUpdatingIDs).isEmpty
    }

    private func startQueuedQuota() {
        while quotaRequests.values.filter({ $0.work != nil }).count < 3, !quotaQueue.isEmpty {
            let key = quotaQueue.removeFirst()
            guard let request = quotaRequests[key] else { continue }
            quotaRequests[key]?.work = Task { [weak self] in
                guard let self else { return }
                await performQuotaUpdate(request.account, location: request.connection ? .connection : .dashboard)
                // An expired request must not remove a newer request for the same binding.
                guard quotaRequests[key]?.executionID == request.executionID else { return }
                // The connection listener may have joined while the request waited.
                if quotaRequests[key]?.connection == true, state == .quota,
                   accounts.contains(where: { QuotaKey($0) == key }), quotaFailures[key.id] == nil {
                    state = .idle
                    isPresented = false
                }
                quotaRequests.removeValue(forKey: key)
                if !quotaRequests.keys.contains(where: { $0.id == key.id }) { manualQuotaIDs.remove(key.id) }
                updateQuotaActivity()
                startQueuedQuota()
                if quotaRequests.isEmpty { finishQuotaRefresh() }
            }
        }
    }

    private func finishQuotaRefresh() {
        let failures = refreshTargets.filter { target in
            accounts.contains { QuotaKey($0) == QuotaKey(target) } && quotaFailures[target.id] != nil
        }
        var failureID = failures.first?.id
        var message = failures.first.flatMap { quotaFailures[$0.id] }
        if failures.contains(where: { quotaFailures[$0.id] == "网络不达标，无法更新" }) {
            message = "网络不达标，无法更新"
        }
        if failureID == nil, !isPresented, let failed = accounts.first(where: { quotaFailures[$0.id] != nil && !hiddenQuotaFailures.contains($0.id) }) {
            failureID = failed.id
            message = quotaFailures[failed.id]
            batchQuotaIDs = failureScopes[failed.id] ?? [failed.id]
        }
        quotaFailureID = failureID
        if let failureID { batchQuotaIDs = failureScopes[failureID] ?? [failureID] }
        if quotaFailure != message { quotaFailure = message }
        if !isPresented { quotaFeedbackLocation = .dashboard }
        manualQuotaIDs = []
    }

    private func cancelRequests(where matches: (ConnectedAccount) -> Bool) {
        for (key, request) in quotaRequests where matches(request.account) {
            if let work = request.work { work.cancel() }
            quotaRequests.removeValue(forKey: key)
            quotaQueue.removeAll { $0 == key }
            manualQuotaIDs.remove(key.id)
        }
        updateQuotaActivity()
    }

    private func performQuotaUpdate(_ account: ConnectedAccount, location: QuotaFeedbackLocation) async {
        guard let quotaUpdater else { return }
        do {
            try Task.checkCancellation()
            guard accounts.contains(where: { $0.id == account.id && $0.generation == account.generation && $0.deletionPending != true }) else { return }
            let updated: ConnectedAccount
            if account.isDemo, let manager = bindings as? any DemoAccountManaging {
                try await Task.sleep(for: .milliseconds(350))
                updated = try await manager.refreshDemo(account, now: now())
            } else {
                updated = try await quotaUpdater.update(account)
            }
            try Task.checkCancellation()
            guard accounts.contains(where: { QuotaKey($0) == QuotaKey(account) }) else { return }
            quotaFailures.removeValue(forKey: account.id)
            if let index = accounts.firstIndex(where: { $0.id == updated.id && $0.generation == updated.generation }) {
                accounts[index] = updated
            }
            if location == .connection, state == .quota {
                state = .idle
                isPresented = false
            }
        } catch is CancellationError {
            // Cancellation never becomes a successful observation.
        } catch {
            guard !Task.isCancelled else { return }
            // A superseded/deleted request must not publish failure against a new binding.
            guard accounts.contains(where: { $0.id == account.id && $0.generation == account.generation
                && $0.credentialRef == account.credentialRef && $0.deletionPending != true }) else { return }
            // A validated plan can have been saved despite a quota failure.
            if let saved = try? await bindings?.load(), !Task.isCancelled,
               let updated = saved.first(where: { $0.id == account.id && $0.generation == account.generation
                   && $0.credentialRef == account.credentialRef && $0.scope == account.scope }),
               let index = accounts.firstIndex(where: { $0.id == account.id && $0.generation == account.generation }) {
                accounts[index] = updated
            }
            guard !Task.isCancelled, accounts.contains(where: { QuotaKey($0) == QuotaKey(account) }) else { return }
            quotaFailure = (error as? CodexQuotaError) == .networkBlocked
                ? "网络不达标，无法更新"
                : (account.quotaState == .notFetched && location == .connection ? "获取失败" : "刷新失败")
            quotaFailureID = account.id
            quotaFailures[account.id] = quotaFailure
        }
    }

    /// Background launch reads trusted bindings only. It must never restore or
    /// start an interactive login; the foreground keeps its own restoration.
    func refreshQuotaInBackground() async -> BackgroundQuotaResult {
        do {
            if !cachedAccountsLoaded {
                guard let bindings else { return .init(total: 0, succeeded: 0, failed: 0, loaded: false) }
                let saved = try await bindings.load()
                if !cachedAccountsLoaded {
                    accounts = saved
                    cachedAccountsLoaded = true
                    loadingAccounts = false
                    accountLoadFailed = false
                }
            }
            try Task.checkCancellation()
            let targets = accounts.filter { $0.deletionPending != true }
            guard quotaUpdater != nil, !accountLoadFailed, !managingAccounts, !reorderingAccounts else {
                return .init(total: targets.count, succeeded: 0, failed: targets.count, loaded: false)
            }
            enqueueQuota(targets, manually: false, location: .dashboard)
            await waitForInitialQuota()
            try Task.checkCancellation()
            let current = targets.filter { target in accounts.contains { QuotaKey($0) == QuotaKey(target) } }
            let failures = current.filter { quotaFailures[$0.id] != nil }.count
            return .init(total: current.count, succeeded: current.count - failures, failed: failures, loaded: true)
        } catch {
            return .init(total: 0, succeeded: 0, failed: 0, loaded: false)
        }
    }

    func interruptBackgroundQuota() { cancelRequests(where: { _ in true }) }

    func waitForInitialQuota() async {
        while !Task.isCancelled, let work = quotaRequests.values.compactMap(\.work).first { await work.value }
    }

    private func waitUntilActive(_ authorization: CodexDeviceAuthorization, attempt: UUID) async throws {
        while !isActive {
            guard isCurrent(attempt), !authorization.isExpired(at: now()) else { throw CancellationError() }
            try await Task.sleep(for: .seconds(1))
        }
        guard isCurrent(attempt), !authorization.isExpired(at: now()) else { throw CancellationError() }
    }

    private var isFailure: Bool {
        if case .failure = state { return true }
        return false
    }

    private func isCurrent(_ attempt: UUID) -> Bool {
        generation == attempt && !Task.isCancelled && isPresented
    }

    private func validAuthorization() -> CodexDeviceAuthorization? {
        expireIfNeeded()
        guard case let .code(authorization) = state else { return nil }
        return authorization
    }
}
