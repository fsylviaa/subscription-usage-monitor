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
    private let completer: (any CodexLoginCompleting)?
    private let verifier: (any CodexIdentityVerifying)?
    private let bindings: (any CodexAccountBinding)?
    private let pending: (any CodexPendingLoginStoring)?
    private var completionWork: Task<Void, Never>?
    private var isActive = true
    private var expiryWork: Task<Void, Never>?
    private var cleanupWork: Task<Void, Never>?
    // In-process recovery only. Persistent interruption recovery belongs to T10.
    private enum Recovery {
        case polling(CodexDeviceAuthorization)
        case tokens(CodexDeviceAuthorization, CodexTokenResponse)
        var authorization: CodexDeviceAuthorization {
            switch self {
            case let .polling(value), let .tokens(value, _): return value
            }
        }
    }
    private var recovery: Recovery?
    private var authorization: CodexDeviceAuthorization?

    static func live() -> CodexConnectionFlow {
        do {
            let flow = CodexConnectionFlow(completer: CodexLoginClient(), verifier: CodexIdentityVerifier(),
                                           bindings: try CodexAccountBindingStore.applicationStore(),
                                           pending: CodexPendingLoginStore())
            flow.loadingAccounts = true
            return flow
        } catch {
            let flow = CodexConnectionFlow()
            flow.accountLoadFailed = true
            return flow
        }
    }

    var canConnect: Bool { accounts.isEmpty && !loadingAccounts && !accountLoadFailed }

    func loadAccounts() async {
        guard let bindings else { return }
        loadingAccounts = true
        defer { loadingAccounts = false }
        do {
            accounts = try await bindings.load()
            accountLoadFailed = false
        } catch { accountLoadFailed = true }
    }

    func setActive(_ active: Bool) { isActive = active }

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
                recovery = nil
                try? await removePending()
                guard isCurrent(attempt) else { return }
                state = .failure("登录未完成，请重试")
            }
        }
        return work
    }

    func cancel() {
        guard state != .saving else { return }
        invalidate()
        state = .idle
        isPresented = false
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
            await previousWork?.value
            await previousCompletion?.value
            await previousCleanup?.value
            guard let self else { return }
            do {
                try await pending?.remove(transactionID: id)
                try await transactions.remove(transactionID: id)
                if pendingID == id { pendingID = nil }
            } catch { }
        }
    }

    private func removePending() async throws {
        guard let id = pendingID else { return }
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
        case .tokens: state = .verifying
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
        completionWork = Task { [weak self] in
            guard let self else { return }
            // Non-nil only at stages that can be retried without replaying a code.
            var safeRecovery: Recovery? = initial
            do {
                var tokens: CodexTokenResponse?
                if case let .tokens(_, saved) = initial { tokens = saved }
                while tokens == nil, isCurrent(attempt) {
                    guard !authorization.isExpired(at: now()) else { throw CodexLoginError.failed }
                    if !isActive {
                        try await Task.sleep(for: .seconds(1))
                        continue
                    }
                    guard let code = try await completer.poll(authorization) else {
                        try await Task.sleep(for: .seconds(authorization.pollInterval))
                        continue
                    }
                    guard isCurrent(attempt), !authorization.isExpired(at: now()) else { throw CancellationError() }
                    // Once a one-time code is received, a failed/uncertain exchange
                    // must restart authorization. Never poll or exchange it again.
                    safeRecovery = nil
                    recovery = nil
                    state = .verifying
                    try await pending.saveCode(code, transactionID: authorization.transactionID)
                    try Task.checkCancellation()
                    let received = try await completer.exchange(code)
                    try Task.checkCancellation()
                    guard isCurrent(attempt), !authorization.isExpired(at: now()) else { throw CancellationError() }
                    try await pending.saveTokens(received, transactionID: authorization.transactionID)
                    try Task.checkCancellation()
                    tokens = received
                    safeRecovery = .tokens(authorization, received)
                }
                guard let tokens, isCurrent(attempt) else { throw CancellationError() }
                let verified = try await verifier.verify(tokens)
                guard isCurrent(attempt), !authorization.isExpired(at: now()) else { throw CancellationError() }
                safeRecovery = nil
                recovery = nil
                state = .saving
                let account = try await bindings.save(verified)
                accounts = [account]
                expiryWork?.cancel()
                self.authorization = nil
                // A cleanup problem cannot turn a committed account into a failure.
                try? await removePending()
                state = .idle
                isPresented = false
            } catch {
                guard isCurrent(attempt) else {
                    // A non-cooperative pending write may have finished after cancel.
                    try? await pending.remove(transactionID: authorization.transactionID)
                    return
                }
                let failure = error as? CodexLoginError
                let canResume = !authorization.isExpired(at: now())
                    && (failure == .retryable || failure == .networkBlocked)
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
            }
        }
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
