import Foundation
import SwiftUI
import UIKit

@MainActor
final class CodexConnectionFlow: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case requesting
        case code(CodexDeviceAuthorization)
        case failure(String)
    }

    @Published private(set) var state: State = .idle
    @Published var isPresented = false
    @Published private(set) var copied = false
    @Published private(set) var browserFailed = false

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
        now: @escaping @Sendable () -> Date = { Date() },
        copyCode: @escaping @MainActor (String, Date) -> Void = { code, deadline in
            UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: code]],
                                         options: [.localOnly: true, .expirationDate: deadline])
        },
        openURL: @escaping @MainActor (URL) async -> Bool = { url in
            await UIApplication.shared.open(url, options: [:])
        }
    ) {
        self.checkNetwork = checkNetwork
        self.authorizer = authorizer
        self.transactions = transactions
        self.now = now
        self.copyCode = copyCode
        self.openURL = openURL
    }

    @discardableResult
    func begin() -> Task<Void, Never>? {
        guard state == .idle || isFailure else { return nil }
        let previousWork = work
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
            guard isCurrent(attempt) else { return }
            // Finish failed cleanup before issuing any new authorization.
            do {
                if let pendingID {
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
            } catch {
                guard isCurrent(attempt) else { return }
                state = .failure("登录未完成，请重试")
            }
        }
        return work
    }

    func cancel() {
        generation = UUID()
        work?.cancel()
        state = .idle
        copied = false
        browserFailed = false
        isPresented = false
        // Keep the reference if removal fails; a subsequent attempt retries it.
        if let id = pendingID {
            Task { [weak self, transactions] in
                do {
                    try await transactions.remove(transactionID: id)
                    if self?.pendingID == id { self?.pendingID = nil }
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
