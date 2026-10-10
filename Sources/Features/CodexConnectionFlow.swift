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
        completionWork?.cancel()
        work?.cancel()
        generation = UUID()
        let attempt = generation
        copied = false
        browserFailed = false
        isPresented = true
        state = .checking
        work = Task { [weak self] in
            guard let self else { return }
            await previousWork?.value
            await previousCompletion?.value
            guard isCurrent(attempt) else { return }
            // Finish failed cleanup before issuing any new authorization.
            do {
                if let pendingID {
                    try await pending?.remove(transactionID: pendingID)
                    try await transactions.remove(transactionID: pendingID)
                    guard isCurrent(attempt) else { return }
                    self.pendingID = nil
                }
                let score = await checkNetwork()
                guard isCurrent(attempt) else { return }
                switch score {
                case .allowed:
                    state = .requesting
                case .blocked:
                    state = .failure("网络不达标，无法连接")
                    return
                case .unavailable:
                    state = .failure("登录未完成，请重试")
                    return
                case .cancelled:
                    cancel()
                    return
                }
                try Task.checkCancellation()
                let authorization = try await authorizer.requestAuthorization()
                guard isCurrent(attempt) else { return }
                guard authorization.expiresAt > now() else {
                    state = .failure("登录未完成，请重试")
                    return
                }
                pendingID = authorization.transactionID
                try await transactions.save(authorization)
                guard isCurrent(attempt) else {
                    // A transport/store can complete after cancellation. Remove only
                    // this transaction, never a newer connection's data.
                    try await transactions.remove(transactionID: authorization.transactionID)
                    return
                }
                guard authorization.expiresAt > now() else {
                    state = .failure("登录未完成，请重试")
                    return
                }
                state = .code(authorization)
                startCompleting(authorization, attempt: attempt)
            } catch {
                guard isCurrent(attempt) else { return }
                state = .failure("登录未完成，请重试")
            }
        }
        return work
    }

    func cancel() {
        guard state != .saving else { return }
        completionWork?.cancel()
        generation = UUID()
        work?.cancel()
        state = .idle
        copied = false
        browserFailed = false
        isPresented = false
        // Keep the reference if removal fails; a subsequent attempt retries it.
        if let id = pendingID {
            Task { [transactions, pending] in
                do {
                    try await pending?.remove(transactionID: id)
                    try await transactions.remove(transactionID: id)
                    // Retain pendingID until prior work has joined in begin(); a
                    // non-cooperative write may finish after this early cleanup.
                } catch { }
            }
        }
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
        _ = validAuthorization()
    }

    private func startCompleting(_ authorization: CodexDeviceAuthorization, attempt: UUID) {
        guard let completer, let verifier, let bindings, let pending else { return }
        completionWork = Task { [weak self] in
            guard let self else { return }
            do {
                while isCurrent(attempt) {
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
                    state = .verifying
                    try await pending.saveCode(code, transactionID: authorization.transactionID)
                    try Task.checkCancellation()
                    let tokens = try await completer.exchange(code)
                    try await pending.saveTokens(tokens, transactionID: authorization.transactionID)
                    try Task.checkCancellation()
                    let verified = try await verifier.verify(tokens)
                    guard isCurrent(attempt), !authorization.isExpired(at: now()) else { throw CancellationError() }
                    // Commit is brief and cannot be dismissed halfway through two stores.
                    state = .saving
                    let account = try await bindings.save(verified)
                    accounts = [account]
                    // A cleanup problem cannot turn a committed account into a fake failure.
                    do {
                        try await pending.remove(transactionID: authorization.transactionID)
                        try await transactions.remove(transactionID: authorization.transactionID)
                        pendingID = nil
                    } catch { /* Kept referenced; T10 handles interrupted cleanup recovery. */ }
                    state = .idle
                    isPresented = false
                    return
                }
            } catch {
                // Clean again after any non-cooperative pending save has finished.
                try? await pending.remove(transactionID: authorization.transactionID)
                guard isCurrent(attempt) else { return }
                state = .failure((error as? CodexLoginError) == .networkBlocked
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
        guard case let .code(authorization) = state else { return nil }
        guard authorization.expiresAt > now() else {
            copied = false
            state = .failure("登录未完成，请重试")
            return nil
        }
        return authorization
    }
}
