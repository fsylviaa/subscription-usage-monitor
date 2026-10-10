import Foundation
import SwiftUI
import UIKit

@MainActor
final class CodexConnectionFlow: ObservableObject {
    enum State: Equatable {
        case idle
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
    @Published private(set) var quotaUpdatingID: UUID?
    @Published private(set) var quotaFailure: String?
    @Published private(set) var quotaFailureID: UUID?
    enum QuotaFeedbackLocation { case connection, dashboard }
    @Published private(set) var quotaFeedbackLocation: QuotaFeedbackLocation = .dashboard
    @Published private(set) var quotaFeedbackHidden = false
    private let quotaUpdater: (any CodexQuotaUpdating)?
    private var quotaWork: Task<Void, Never>?
    private let completer: (any CodexLoginCompleting)?
    private let verifier: (any CodexIdentityVerifying)?
    private let bindings: (any CodexAccountBinding)?
    private let pending: (any CodexPendingLoginStoring)?
    private var completionWork: Task<Void, Never>?
    private var isActive = true
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
            let updater = CodexQuotaService(store: accounts, loadCredential: { try await vault.load(for: .credential($0)) })
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

    var canConnect: Bool { accounts.isEmpty && !loadingAccounts && !accountLoadFailed }

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
        let attempt = generation
        defer { loadingAccounts = false }
        do {
            accounts = try await bindings.load()
            accountLoadFailed = false
        } catch {
            accountLoadFailed = true
            return
        }
        // T12 also completes the first query for an existing T08 binding on
        // upgrade/relaunch. Regular foreground refresh remains a later task.
        if let account = accounts.first, account.quotaState == .notFetched || account.subscription == nil {
            startInitialQuota(for: account)
        }
        // A committed account wins over leftover temporary data after a crash.
        // T10 only binds the first account; it never reconnects an existing one.
        do {
            needsPersistentRestore = true
            let found = try await readPersistedRecovery()
            guard found, accounts.isEmpty else { return }
            loadingAccounts = false
            await begin()?.value
        } catch {
            guard generation == attempt, !Task.isCancelled, accounts.isEmpty else { return }
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
        if !accounts.isEmpty {
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
        now: @escaping @Sendable () -> Date = { Date() },
        copyCode: @escaping @MainActor (String, Date) -> Void = { code, deadline in
            UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: code]],
                                         options: [.localOnly: true, .expirationDate: deadline])
        },
        openURL: @escaping @MainActor (URL) async -> Bool = { url in
            await UIApplication.shared.open(url, options: [:])
        }
    ) {
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

    @discardableResult
    func begin() -> Task<Void, Never>? {
        guard canConnect, state == .idle || isFailure else { return nil }
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
                let account = try await bindings.save(verified)
                accounts = [account]
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

    /// First-fetch recovery only; this does not enable regular manual refresh.
    func retryInitialQuota(for accountID: UUID, location: QuotaFeedbackLocation = .dashboard) {
        guard quotaFailureID == accountID,
              let account = accounts.first(where: { $0.id == accountID }),
              account.quotaState == .notFetched else { return }
        startInitialQuota(for: account, location: location)
    }

    func hideQuotaFeedback() {
        guard quotaUpdatingID == nil else { return }
        quotaFeedbackHidden = true
    }

    /// Separate from login: dismissing its sheet cannot cancel the quota query.
    private func startInitialQuota(for account: ConnectedAccount, location: QuotaFeedbackLocation = .dashboard) {
        guard let quotaUpdater, quotaWork == nil else { return }
        quotaFeedbackLocation = location
        quotaFeedbackHidden = false
        quotaUpdatingID = account.id
        quotaFailure = nil
        quotaFailureID = nil
        quotaWork = Task { [weak self] in
            guard let self else { return }
            defer { quotaUpdatingID = nil; quotaWork = nil }
            do {
                let updated = try await quotaUpdater.update(account)
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
                // A validated plan can have been saved despite a quota failure.
                if let saved = try? await bindings?.load(),
                   let updated = saved.first(where: { $0.id == account.id && $0.generation == account.generation
                       && $0.credentialRef == account.credentialRef && $0.scope == account.scope }),
                   let index = accounts.firstIndex(where: { $0.id == account.id && $0.generation == account.generation }) {
                    accounts[index] = updated
                }
                quotaFailure = (error as? CodexQuotaError) == .networkBlocked
                    ? "网络不达标，无法更新"
                    : (account.quotaState == .notFetched ? "获取失败" : "刷新失败")
                quotaFailureID = account.id
            }
        }
    }

    func waitForInitialQuota() async { await quotaWork?.value }

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
