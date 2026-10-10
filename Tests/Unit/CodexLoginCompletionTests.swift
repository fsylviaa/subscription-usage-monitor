import Combine
import Foundation
import XCTest
@testable import SubscriptionUsage

@MainActor
final class CodexLoginCompletionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    func testOnlyReturningFromOfficialPageNeverSavesAnAccount() async throws {
        let scenario = try scenario(pollPending: true, pollSuspended: true)
        try await XCTUnwrap(scenario.flow.begin()).value
        await scenario.completer.pollEntered.wait()
        await scenario.flow.openWebsite()
        scenario.flow.setActive(false)
        scenario.flow.setActive(true)
        scenario.flow.expireIfNeeded()

        XCTAssertEqual(scenario.flow.state, .code(scenario.authorization))
        XCTAssertTrue(scenario.flow.accounts.isEmpty)
        let saves = await scenario.bindings.saveCount
        let verifies = await scenario.verifier.count
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(verifies, 0)
        scenario.flow.cancel()
        await scenario.completer.pollRelease.open()
        await scenario.pending.waitForRemovals(2)
        print("T08 | 仅打开官网并返回 | 保持等待；没有账户，也不宣称连接成功")
    }

    func testUnverifiedTokensStayPendingAndLateVerificationAfterCancelCannotSave() async throws {
        let scenario = try scenario(verificationSuspended: true)
        try await XCTUnwrap(scenario.flow.begin()).value
        await scenario.verifier.entered.wait()

        XCTAssertEqual(scenario.flow.state, .verifying)
        XCTAssertTrue(scenario.flow.accounts.isEmpty)
        let savesBefore = await scenario.bindings.saveCount
        let phasesBefore = await scenario.pending.phases
        XCTAssertEqual(savesBefore, 0)
        XCTAssertEqual(phasesBefore, ["code", "tokens"])
        scenario.flow.cancel()
        await scenario.verifier.release.open()
        await scenario.pending.waitForRemovals(2)

        XCTAssertEqual(scenario.flow.state, .idle)
        XCTAssertFalse(scenario.flow.isPresented)
        XCTAssertTrue(scenario.flow.accounts.isEmpty)
        let savesAfter = await scenario.bindings.saveCount
        XCTAssertEqual(savesAfter, 0)
        print("T08 | 仅领到令牌／验证中取消 | 尚未形成账户；迟到的核验结果不保存")
    }

    func testVerificationFailureAndNetworkBlockNeverSaveFormalBinding() async throws {
        for failure in [CodexLoginError.failed, .networkBlocked] {
            let scenario = try scenario(verificationFailure: failure)
            let expected = CodexConnectionFlow.State.failure(failure == .networkBlocked
                ? "网络不达标，无法连接" : "登录未完成，请重试")
            let state = observe(scenario.flow, state: expected)
            try await XCTUnwrap(scenario.flow.begin()).value
            await assertObserved(state)

            XCTAssertEqual(scenario.flow.state, expected)
            XCTAssertTrue(scenario.flow.accounts.isEmpty)
            let saves = await scenario.bindings.saveCount
            let removed = await scenario.pending.removalCount
            XCTAssertEqual(saves, 0)
            XCTAssertEqual(removed, 1)
            scenario.flow.cancel()
        }
        print("T08 | 身份核验失败／核验网络未通过 | 不提交账户；显示简短失败")
    }

    func testVerifiedLoginSavesOnceAndDisplaysIdentityWithNotFetchedQuota() async throws {
        let scenario = try scenario()
        let finished = observe(scenario.flow, state: .idle, requireAccount: true)
        try await XCTUnwrap(scenario.flow.begin()).value
        await assertObserved(finished)

        let account = try XCTUnwrap(scenario.flow.accounts.first)
        XCTAssertEqual(account.verifiedEmail, "verified@example.invalid")
        XCTAssertEqual(account.remoteUserID, "synthetic-user")
        XCTAssertEqual(account.scope.remoteAccountID, "synthetic-account")
        XCTAssertEqual(account.quotaState, .notFetched)
        XCTAssertNil(account.displayName)
        XCTAssertFalse(scenario.flow.isPresented)
        XCTAssertFalse(scenario.flow.canConnect)
        let saveCount = await scenario.bindings.saveCount
        let verifyCount = await scenario.verifier.count
        let pendingRemovals = await scenario.pending.removalCount
        let transaction = await scenario.transactions.current
        XCTAssertEqual(saveCount, 1)
        XCTAssertEqual(verifyCount, 1)
        XCTAssertEqual(pendingRemovals, 1)
        XCTAssertNil(transaction)
        XCTAssertNil(scenario.flow.begin())
        print("T08 | 已核验的固定账户 | 仅保存一次；显示身份，额度保持尚未获取")
    }

    func testFormalSaveFailureDoesNotPublishVerifiedButUnsavedAccount() async throws {
        let scenario = try scenario(bindingFailure: true)
        let failed = observe(scenario.flow, state: .failure("登录未完成，请重试"))
        try await XCTUnwrap(scenario.flow.begin()).value
        await assertObserved(failed)

        XCTAssertTrue(scenario.flow.accounts.isEmpty)
        XCTAssertTrue(scenario.flow.isPresented)
        let saveCount = await scenario.bindings.saveCount
        XCTAssertEqual(saveCount, 1)
        scenario.flow.cancel()
    }

    func testSensitivePendingSaveFailurePreventsVerificationAndFormalSave() async throws {
        let scenario = try scenario(pendingFailure: true)
        let failed = observe(scenario.flow, state: .failure("登录未完成，请重试"))
        try await XCTUnwrap(scenario.flow.begin()).value
        await assertObserved(failed)

        let verifies = await scenario.verifier.count
        let saves = await scenario.bindings.saveCount
        XCTAssertEqual(verifies, 0)
        XCTAssertEqual(saves, 0)
        XCTAssertTrue(scenario.flow.accounts.isEmpty)
        scenario.flow.cancel()
    }

    func testCommittedAccountSurvivesTemporaryCleanupFailure() async throws {
        let scenario = try scenario(cleanupFailure: true)
        let finished = observe(scenario.flow, state: .idle, requireAccount: true)
        try await XCTUnwrap(scenario.flow.begin()).value
        await assertObserved(finished)

        XCTAssertEqual(scenario.flow.accounts.count, 1)
        XCTAssertFalse(scenario.flow.isPresented)
        let saves = await scenario.bindings.saveCount
        XCTAssertEqual(saves, 1)
        print("T08 | 正式保存后临时清理失败 | 保留已提交账户，不误报登录失败")
    }

    func testFreshFlowLoadsSavedIdentityWithoutInventingQuota() async throws {
        let scenario = try scenario()
        let finished = observe(scenario.flow, state: .idle, requireAccount: true)
        try await XCTUnwrap(scenario.flow.begin()).value
        await assertObserved(finished)
        let reloaded = CodexConnectionFlow(bindings: scenario.bindings, pending: CompletionPendingStub())
        await reloaded.loadAccounts()

        XCTAssertEqual(reloaded.accounts, scenario.flow.accounts)
        XCTAssertEqual(reloaded.accounts.first?.quotaState, .notFetched)
        XCTAssertFalse(reloaded.accountLoadFailed)
        XCTAssertFalse(reloaded.canConnect)
    }

    private struct Observation {
        let expectation: XCTestExpectation
        let subscription: AnyCancellable
    }

    private func observe(_ flow: CodexConnectionFlow, state target: CodexConnectionFlow.State,
                         requireAccount: Bool = false) -> Observation {
        let expected = XCTestExpectation(description: "流程到达预期状态")
        var fulfilled = false
        let subscription = flow.$state.sink { state in
            if state == target, (!requireAccount || !flow.accounts.isEmpty), !fulfilled {
                fulfilled = true
                expected.fulfill()
            }
        }
        return Observation(expectation: expected, subscription: subscription)
    }

    private func assertObserved(_ observation: Observation, file: StaticString = #filePath, line: UInt = #line) async {
        let result = await XCTWaiter.fulfillment(of: [observation.expectation], timeout: 3)
        XCTAssertEqual(result, .completed, file: file, line: line)
        observation.subscription.cancel()
    }

    private struct Scenario {
        let flow: CodexConnectionFlow
        let authorization: CodexDeviceAuthorization
        let completer: CompletionClientStub
        let verifier: CompletionVerifierStub
        let bindings: CompletionBindingStub
        let pending: CompletionPendingStub
        let transactions: CompletionTransactionStub
    }

    private func scenario(pollPending: Bool = false, pollSuspended: Bool = false,
                          verificationSuspended: Bool = false, verificationFailure: CodexLoginError? = nil,
                          bindingFailure: Bool = false, pendingFailure: Bool = false,
                          cleanupFailure: Bool = false) throws -> Scenario {
        let authorization = try CodexDeviceAuthorization(deviceAuthID: "synthetic-device", userCode: "TEST-1234",
                                                        pollInterval: 5, startedAt: start)
        let token = CodexTokenResponse(accessToken: "synthetic-access", refreshToken: "synthetic-refresh",
                                      idToken: "synthetic-id", obtainedAt: start, expiresAt: start.addingTimeInterval(3600))
        let verified = CodexVerifiedLogin.fixture(remoteUserID: "synthetic-user", email: "verified@example.invalid",
            scope: AccountScope(remoteAccountID: "synthetic-account", kind: .personal, label: nil),
            credentials: CredentialPayload(data: Data("synthetic-verified-package".utf8)))
        let completer = CompletionClientStub(tokens: token, pending: pollPending, suspended: pollSuspended)
        let verifier = CompletionVerifierStub(verified: verified, suspended: verificationSuspended, failure: verificationFailure)
        let bindings = CompletionBindingStub(fails: bindingFailure)
        let pending = CompletionPendingStub(saveFails: pendingFailure, cleanupFails: cleanupFailure)
        let transactions = CompletionTransactionStub()
        let flow = CodexConnectionFlow(checkNetwork: { .allowed(score: 51) },
            authorizer: CompletionAuthorizerStub(authorization: authorization), transactions: transactions,
            completer: completer, verifier: verifier, bindings: bindings, pending: pending,
            now: { authorization.startedAt }, copyCode: { _, _ in }, openURL: { _ in true })
        return .init(flow: flow, authorization: authorization, completer: completer, verifier: verifier,
                     bindings: bindings, pending: pending, transactions: transactions)
    }
}

private struct CompletionAuthorizerStub: CodexDeviceAuthorizing {
    let authorization: CodexDeviceAuthorization
    func requestAuthorization() async throws -> CodexDeviceAuthorization { authorization }
}

private actor CompletionClientStub: CodexLoginCompleting {
    let pollEntered = CompletionTestGate()
    let pollRelease = CompletionTestGate()
    private let tokens: CodexTokenResponse
    private let pending: Bool
    private let suspended: Bool
    init(tokens: CodexTokenResponse, pending: Bool, suspended: Bool) {
        self.tokens = tokens; self.pending = pending; self.suspended = suspended
    }
    func poll(_ authorization: CodexDeviceAuthorization) async throws -> CodexAuthorizationCode? {
        if suspended { await pollEntered.open(); await pollRelease.wait() }
        return pending ? nil : .init(code: "synthetic-code", verifier: String(repeating: "v", count: 43))
    }
    func exchange(_ code: CodexAuthorizationCode) async throws -> CodexTokenResponse { tokens }
}

private actor CompletionVerifierStub: CodexIdentityVerifying {
    let entered = CompletionTestGate()
    let release = CompletionTestGate()
    private let verified: CodexVerifiedLogin
    private let suspended: Bool
    private let failure: CodexLoginError?
    private(set) var count = 0
    init(verified: CodexVerifiedLogin, suspended: Bool, failure: CodexLoginError?) {
        self.verified = verified; self.suspended = suspended; self.failure = failure
    }
    func verify(_ tokens: CodexTokenResponse) async throws -> CodexVerifiedLogin {
        count += 1
        if suspended { await entered.open(); await release.wait() }
        if let failure { throw failure }
        return verified // Deliberately non-cooperative with cancellation to test the flow guard.
    }
}

private actor CompletionBindingStub: CodexAccountBinding {
    private let fails: Bool
    private var accounts: [ConnectedAccount] = []
    private(set) var saveCount = 0
    init(fails: Bool) { self.fails = fails }
    func load() async throws -> [ConnectedAccount] { accounts }
    func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount {
        saveCount += 1
        if fails { throw CodexLoginError.failed }
        let account = ConnectedAccount(remoteUserID: login.remoteUserID, verifiedEmail: login.email,
                                       scope: login.scope, credentialRef: UUID())
        accounts = [account]
        return account
    }
}

private actor CompletionPendingStub: CodexPendingLoginStoring {
    private let saveFails: Bool
    private let cleanupFails: Bool
    private(set) var phases: [String] = []
    private(set) var removalCount = 0
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    init(saveFails: Bool = false, cleanupFails: Bool = false) {
        self.saveFails = saveFails; self.cleanupFails = cleanupFails
    }
    func saveCode(_ code: CodexAuthorizationCode, transactionID: UUID) async throws {
        if saveFails { throw CodexLoginError.failed }
        phases.append("code")
    }
    func saveTokens(_ tokens: CodexTokenResponse, transactionID: UUID) async throws {
        if saveFails { throw CodexLoginError.failed }
        phases.append("tokens")
    }
    func remove(transactionID: UUID) async throws {
        removalCount += 1
        let ready = waiters.filter { $0.0 <= removalCount }
        waiters.removeAll { $0.0 <= removalCount }
        for (_, waiter) in ready { waiter.resume() }
        if cleanupFails { throw CodexLoginError.failed }
    }
    func waitForRemovals(_ count: Int) async {
        guard removalCount < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
}

private actor CompletionTransactionStub: CodexLoginTransactionStoring {
    private(set) var current: CodexDeviceAuthorization?
    func save(_ authorization: CodexDeviceAuthorization) async throws { current = authorization }
    func remove(transactionID: UUID) async throws {
        if current?.transactionID == transactionID { current = nil }
    }
}

private actor CompletionTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        let pending = waiters; waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
