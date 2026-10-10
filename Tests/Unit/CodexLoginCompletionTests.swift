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
            if failure == .networkBlocked {
                XCTAssertEqual(removed, 0, "有效令牌遇到网络门控阻止时应保留，供安全重试")
            } else {
                XCTAssertGreaterThanOrEqual(removed, 1)
            }
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

/// T09 exercises recoverable and terminal outcomes with isolated in-memory stores.
/// The barriers deliberately ignore cancellation so late responses are observable.
@MainActor
final class CodexLoginRecoveryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let failed = CodexConnectionFlow.State.failure("登录未完成，请重试")

    func testTemporaryPollingFailureRetriesSameAuthorizationAfterFreshNetworkCheck() async throws {
        let s = try scenario(pollFailures: [.retryable])
        try await XCTUnwrap(s.flow.begin()).value
        await waitUntil { s.flow.state == self.failed }
        let retained = await s.transactions.current
        XCTAssertEqual(retained, s.authorizations[0])
        XCTAssertTrue(s.flow.accounts.isEmpty)

        try await XCTUnwrap(s.flow.begin()).value
        await waitUntil { !s.flow.accounts.isEmpty }

        let requests = await s.authorizer.count
        let checks = await s.scores.count
        let polls = await s.client.polledTransactions
        let exchanges = await s.client.exchangedCodes
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(checks, 2)
        XCTAssertEqual(polls, [s.authorizations[0].transactionID, s.authorizations[0].transactionID])
        XCTAssertEqual(exchanges.count, 1)
        XCTAssertFalse(s.flow.isPresented)
        print("T09 | 有效代码领取暂时失败后重试 | 重新检查网络，复用原事务并成功；未重复申请")
    }

    func testBlockedRetryPreservesValidPollingTransactionWithoutRequestingAnotherCode() async throws {
        let s = try scenario(pollFailures: [.retryable],
                             scores: [.allowed(score: 51), .blocked(score: 50), .allowed(score: 51)])
        try await XCTUnwrap(s.flow.begin()).value
        await waitUntil { s.flow.state == self.failed }
        try await XCTUnwrap(s.flow.begin()).value
        XCTAssertEqual(s.flow.state, .failure("网络不达标，无法连接"))
        let retained = await s.transactions.current
        let requestsWhileBlocked = await s.authorizer.count
        let pollsWhileBlocked = await s.client.polledTransactions.count
        XCTAssertEqual(retained, s.authorizations[0])
        XCTAssertEqual(requestsWhileBlocked, 1)
        XCTAssertEqual(pollsWhileBlocked, 1)

        try await XCTUnwrap(s.flow.begin()).value
        await waitUntil { !s.flow.accounts.isEmpty }
        let requests = await s.authorizer.count
        XCTAssertEqual(requests, 1)
        print("T09 | 重试时网络评分不达标 | 暂停领取，不新申请；网络恢复后原有效事务成功")
    }

    func testRecoverableVerificationRetriesSavedTokensWithoutPollingOrExchangingAgain() async throws {
        for failure in [CodexLoginError.retryable, .networkBlocked] {
            let s = try scenario(verificationFailures: [failure])
            let expected = failure == .networkBlocked
                ? CodexConnectionFlow.State.failure("网络不达标，无法连接") : failed
            try await XCTUnwrap(s.flow.begin()).value
            await waitUntil { s.flow.state == expected }
            let retained = await s.pending.transactionIDs
            XCTAssertEqual(retained, Set([s.authorizations[0].transactionID]))

            try await XCTUnwrap(s.flow.begin()).value
            await waitUntil { !s.flow.accounts.isEmpty }

            let requests = await s.authorizer.count
            let polls = await s.client.polledTransactions.count
            let exchanges = await s.client.exchangedCodes.count
            let verifiedTokens = await s.verifier.receivedTokens
            let checks = await s.scores.count
            XCTAssertEqual(requests, 1)
            XCTAssertEqual(polls, 1)
            XCTAssertEqual(exchanges, 1)
            XCTAssertEqual(verifiedTokens, ["t09-access-1", "t09-access-1"])
            XCTAssertEqual(checks, 2)
        }
        print("T09 | 已取得令牌，核验暂时失败／网络阻止 | 保留有效令牌重试核验；不重放一次性授权码")
    }

    func testRejectedAuthorizationEndsOldTransactionAndRetryCanCompleteNewLogin() async throws {
        let s = try scenario(pollFailures: [.failed])
        try await XCTUnwrap(s.flow.begin()).value
        await waitUntil { s.flow.state == self.failed }
        await assertNoTemporaryData(s)
        XCTAssertTrue(s.flow.accounts.isEmpty)

        try await XCTUnwrap(s.flow.begin()).value
        await waitUntil { !s.flow.accounts.isEmpty }

        let requests = await s.authorizer.count
        let polls = await s.client.polledTransactions
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(polls, [s.authorizations[0].transactionID, s.authorizations[1].transactionID])
        print("T09 | 确定拒绝后重新开始 | 简短失败、清理旧事务；新代码可正常完成登录")
    }

    func testAnyExchangeFailureRestartsAndNeverReplaysSingleUseCode() async throws {
        for failure in [CodexLoginError.failed, .retryable] {
            let s = try scenario(exchangeFailures: [failure])
            try await XCTUnwrap(s.flow.begin()).value
            await waitUntil { s.flow.state == self.failed }
            await assertNoTemporaryData(s)
            XCTAssertTrue(s.flow.accounts.isEmpty)

            try await XCTUnwrap(s.flow.begin()).value
            await waitUntil { !s.flow.accounts.isEmpty }

            let requests = await s.authorizer.count
            let exchanges = await s.client.exchangedCodes
            XCTAssertEqual(requests, 2)
            XCTAssertEqual(exchanges.count, 2)
            XCTAssertEqual(Set(exchanges).count, 2, "交换失败或结果不明时不能重放旧授权码")
        }
        print("T09 | 交换失败／交换结果不明 | 结束旧流程；重试取得新代码，不重放旧授权码")
    }

    func testExpiryDuringVerificationDiscardsLateIdentityAndRestartsWithFreshNetworkGate() async throws {
        let s = try scenario(holdFirstVerification: true,
                             scores: [.allowed(score: 51), .blocked(score: 50), .allowed(score: 51)])
        try await XCTUnwrap(s.flow.begin()).value
        await waitUntil { await s.verifier.entered.isOpen }
        XCTAssertEqual(s.flow.state, .verifying)
        s.clock.set(s.authorizations[0].expiresAt)
        s.flow.expireIfNeeded()
        XCTAssertEqual(s.flow.state, failed)
        await s.verifier.release.open()
        await assertNoTemporaryData(s)

        try await XCTUnwrap(s.flow.begin()).value
        XCTAssertEqual(s.flow.state, .failure("网络不达标，无法连接"))
        let blockedRequests = await s.authorizer.count
        let blockedSaves = await s.bindings.saveCount
        XCTAssertEqual(blockedRequests, 1)
        XCTAssertEqual(blockedSaves, 0, "到期后迟到的核验身份不能正式保存")

        try await XCTUnwrap(s.flow.begin()).value
        await waitUntil { !s.flow.accounts.isEmpty }
        let polls = await s.client.polledTransactions
        let requests = await s.authorizer.count
        let checks = await s.scores.count
        XCTAssertEqual(polls, [s.authorizations[0].transactionID, s.authorizations[1].transactionID])
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(checks, 3)
        print("T09 | 核验期间到期并返回迟到身份 | 不保存；重新评分通过后新事务可成功")
    }

    func testExpiredRecoverableTokensCannotBeReusedOnRetry() async throws {
        let s = try scenario(verificationFailures: [.retryable])
        try await XCTUnwrap(s.flow.begin()).value
        await waitUntil { s.flow.state == self.failed }
        s.clock.set(s.authorizations[0].expiresAt)
        s.flow.expireIfNeeded()
        try await XCTUnwrap(s.flow.begin()).value
        await waitUntil { !s.flow.accounts.isEmpty }

        let requests = await s.authorizer.count
        let tokens = await s.verifier.receivedTokens
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(tokens, ["t09-access-1", "t09-access-2"])
        print("T09 | 可恢复失败等待期间到期 | 不复用过期事务或令牌，重新申请并成功")
    }

    func testCancelDuringExchangeThenImmediateRetryRejectsLateTokensAndCompletesNewLogin() async throws {
        let s = try scenario(holdFirstExchange: true)
        try await XCTUnwrap(s.flow.begin()).value
        await waitUntil { await s.client.exchangeEntered.isOpen }
        s.flow.cancel()
        XCTAssertEqual(s.flow.state, .idle)
        XCTAssertFalse(s.flow.isPresented)
        let retry = try XCTUnwrap(s.flow.begin())
        await s.client.exchangeRelease.open()
        await retry.value
        await waitUntil { !s.flow.accounts.isEmpty }

        let requests = await s.authorizer.count
        let verifiedTokens = await s.verifier.receivedTokens
        let saves = await s.bindings.saveCount
        let opens = s.browser.openCount
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(verifiedTokens, ["t09-access-2"], "取消后迟到的旧令牌不能进入身份核验")
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(opens, 0, "迟到结果不能打开浏览器")
        await assertNoTemporaryData(s)
        print("T09 | 交换中取消后立即重试，旧令牌随后返回 | 旧结果丢弃，新流程只保存一次")
    }

    func testCancelDuringVerificationThenRetryNeverPublishesOldIdentity() async throws {
        let s = try scenario(holdFirstVerification: true)
        try await XCTUnwrap(s.flow.begin()).value
        await waitUntil { await s.verifier.entered.isOpen }
        s.flow.cancel()
        let retry = try XCTUnwrap(s.flow.begin())
        await s.verifier.release.open()
        await retry.value
        await waitUntil { !s.flow.accounts.isEmpty }

        let saves = await s.bindings.saveCount
        let savedUsers = await s.bindings.savedUsers
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(savedUsers, ["t09-access-2"])
        XCTAssertEqual(s.flow.accounts.first?.remoteUserID, "t09-access-2")
        await assertNoTemporaryData(s)
    }

    func testCancellationRejectionAndExpiryPreserveExistingAccountRecords() async throws {
        let original = ConnectedAccount(remoteUserID: "existing-user", verifiedEmail: "existing@example.invalid",
            displayName: "已有测试账户", scope: .init(remoteAccountID: "existing-account", kind: .personal),
            credentialRef: UUID(), generation: 4, quotaState: .notFetched)
        for outcome in ["cancel", "rejected", "expired"] {
            let s = try scenario(pollFailures: outcome == "rejected" ? [.failed] : [], holdFirstPoll: true,
                                 existingAccounts: [original])
            try await XCTUnwrap(s.flow.begin()).value
            await waitUntil { await s.client.pollEntered.isOpen }
            // Loading an existing record while the login is in flight exercises
            // preservation without enabling another-account login in the product.
            await s.flow.loadAccounts()
            XCTAssertEqual(s.flow.accounts, [original])
            if outcome == "cancel" {
                s.flow.cancel()
            } else if outcome == "expired" {
                s.clock.set(s.authorizations[0].expiresAt)
                s.flow.expireIfNeeded()
            }
            await s.client.pollRelease.open()
            if outcome != "cancel" { await waitUntil { s.flow.state == self.failed } }
            await assertNoTemporaryData(s)
            let records = try await s.bindings.load()
            let saves = await s.bindings.saveCount
            XCTAssertEqual(records, [original])
            XCTAssertEqual(s.flow.accounts, [original])
            XCTAssertEqual(saves, 0)
            XCTAssertEqual(s.browser.openCount, 0)
            s.flow.cancel()
        }
        print("T09 | 取消／拒绝／到期与已有测试账户 | 完整身份、位置、连接引用、版本及尚未获取状态不变")
    }

    private func assertNoTemporaryData(_ s: RecoveryScenario,
                                       file: StaticString = #filePath, line: UInt = #line) async {
        await waitUntil(file: file, line: line) {
            let transaction = await s.transactions.current
            let pending = await s.pending.transactionIDs
            return transaction == nil && pending.isEmpty
        }
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () async -> Bool) async {
        for _ in 0..<300 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("隔离流程未在时限内达到预期状态", file: file, line: line)
    }

    private struct RecoveryScenario {
        let flow: CodexConnectionFlow
        let authorizations: [CodexDeviceAuthorization]
        let authorizer: RecoveryAuthorizer
        let client: RecoveryClient
        let verifier: RecoveryVerifier
        let pending: RecoveryPendingStore
        let transactions: CompletionTransactionStub
        let bindings: RecoveryBindings
        let scores: RecoveryScores
        let clock: RecoveryClock
        let browser: RecoveryBrowser
    }

    private func scenario(pollFailures: [CodexLoginError] = [], exchangeFailures: [CodexLoginError] = [],
                          verificationFailures: [CodexLoginError] = [], holdFirstPoll: Bool = false,
                          holdFirstExchange: Bool = false, holdFirstVerification: Bool = false,
                          scores: [NetworkScoreResult] = [.allowed(score: 51)],
                          existingAccounts: [ConnectedAccount] = []) throws -> RecoveryScenario {
        let first = try CodexDeviceAuthorization(deviceAuthID: "t09-device-1", userCode: "T09-FIRST",
                                                 pollInterval: 1, startedAt: start)
        let second = try CodexDeviceAuthorization(deviceAuthID: "t09-device-2", userCode: "T09-SECOND",
                                                  pollInterval: 1, startedAt: first.expiresAt)
        let authorizer = RecoveryAuthorizer([first, second])
        let client = RecoveryClient(start: start, pollFailures: pollFailures, exchangeFailures: exchangeFailures,
                                    holdFirstPoll: holdFirstPoll, holdFirstExchange: holdFirstExchange)
        let verifier = RecoveryVerifier(failures: verificationFailures, holdFirst: holdFirstVerification)
        let pending = RecoveryPendingStore()
        let transactions = CompletionTransactionStub()
        let bindings = RecoveryBindings(accounts: existingAccounts)
        let scoreSource = RecoveryScores(scores)
        let clock = RecoveryClock(start)
        let browser = RecoveryBrowser()
        let flow = CodexConnectionFlow(checkNetwork: { await scoreSource.next() }, authorizer: authorizer,
            transactions: transactions, completer: client, verifier: verifier, bindings: bindings, pending: pending,
            now: { clock.now() }, copyCode: { _, _ in }, openURL: { _ in browser.openCount += 1; return true })
        return .init(flow: flow, authorizations: [first, second], authorizer: authorizer, client: client,
                     verifier: verifier, pending: pending, transactions: transactions, bindings: bindings,
                     scores: scoreSource, clock: clock, browser: browser)
    }
}

private actor RecoveryAuthorizer: CodexDeviceAuthorizing {
    private var values: [CodexDeviceAuthorization]
    private(set) var count = 0
    init(_ values: [CodexDeviceAuthorization]) { self.values = values }
    func requestAuthorization() async throws -> CodexDeviceAuthorization {
        count += 1
        guard !values.isEmpty else { throw CodexDeviceAuthorizationError.requestFailed }
        return values.removeFirst()
    }
}

private actor RecoveryClient: CodexLoginCompleting {
    let pollEntered = RecoveryGate()
    let pollRelease = RecoveryGate()
    let exchangeEntered = RecoveryGate()
    let exchangeRelease = RecoveryGate()
    private let start: Date
    private var pollFailures: [CodexLoginError]
    private var exchangeFailures: [CodexLoginError]
    private let holdFirstPoll: Bool
    private let holdFirstExchange: Bool
    private(set) var polledTransactions: [UUID] = []
    private(set) var exchangedCodes: [String] = []
    init(start: Date, pollFailures: [CodexLoginError], exchangeFailures: [CodexLoginError],
         holdFirstPoll: Bool, holdFirstExchange: Bool) {
        self.start = start; self.pollFailures = pollFailures; self.exchangeFailures = exchangeFailures
        self.holdFirstPoll = holdFirstPoll; self.holdFirstExchange = holdFirstExchange
    }
    func poll(_ authorization: CodexDeviceAuthorization) async throws -> CodexAuthorizationCode? {
        polledTransactions.append(authorization.transactionID)
        if holdFirstPoll, polledTransactions.count == 1 { await pollEntered.open(); await pollRelease.wait() }
        if !pollFailures.isEmpty { throw pollFailures.removeFirst() }
        return .init(code: authorization.deviceAuthID, verifier: String(repeating: "v", count: 43))
    }
    func exchange(_ code: CodexAuthorizationCode) async throws -> CodexTokenResponse {
        exchangedCodes.append(code.code)
        let index = exchangedCodes.count
        if holdFirstExchange, index == 1 { await exchangeEntered.open(); await exchangeRelease.wait() }
        if !exchangeFailures.isEmpty { throw exchangeFailures.removeFirst() }
        return .init(accessToken: "t09-access-\(index)", refreshToken: "t09-refresh-\(index)",
                     idToken: "t09-id-\(index)", obtainedAt: start, expiresAt: start.addingTimeInterval(3600))
    }
}

private actor RecoveryVerifier: CodexIdentityVerifying {
    let entered = RecoveryGate()
    let release = RecoveryGate()
    private var failures: [CodexLoginError]
    private let holdFirst: Bool
    private(set) var receivedTokens: [String] = []
    init(failures: [CodexLoginError], holdFirst: Bool) { self.failures = failures; self.holdFirst = holdFirst }
    func verify(_ tokens: CodexTokenResponse) async throws -> CodexVerifiedLogin {
        receivedTokens.append(tokens.accessToken)
        if holdFirst, receivedTokens.count == 1 { await entered.open(); await release.wait() }
        if !failures.isEmpty { throw failures.removeFirst() }
        return .fixture(remoteUserID: tokens.accessToken, email: "t09@example.invalid",
                        scope: .init(remoteAccountID: "t09-account", kind: .personal),
                        credentials: .init(data: Data("t09-verified-package".utf8)))
    }
}

private actor RecoveryBindings: CodexAccountBinding {
    private var accounts: [ConnectedAccount]
    private(set) var saveCount = 0
    private(set) var savedUsers: [String] = []
    init(accounts: [ConnectedAccount]) { self.accounts = accounts }
    func load() async throws -> [ConnectedAccount] { accounts }
    func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount {
        saveCount += 1
        guard accounts.isEmpty else { throw CodexLoginError.failed }
        savedUsers.append(login.remoteUserID)
        let account = ConnectedAccount(remoteUserID: login.remoteUserID, verifiedEmail: login.email,
                                       scope: login.scope, credentialRef: UUID())
        accounts = [account]
        return account
    }
}

private actor RecoveryPendingStore: CodexPendingLoginStoring {
    private(set) var transactionIDs: Set<UUID> = []
    func saveCode(_ code: CodexAuthorizationCode, transactionID: UUID) async throws { transactionIDs.insert(transactionID) }
    func saveTokens(_ tokens: CodexTokenResponse, transactionID: UUID) async throws { transactionIDs.insert(transactionID) }
    func remove(transactionID: UUID) async throws { transactionIDs.remove(transactionID) }
}

private actor RecoveryScores {
    private var values: [NetworkScoreResult]
    private(set) var count = 0
    init(_ values: [NetworkScoreResult]) { self.values = values }
    func next() -> NetworkScoreResult {
        count += 1
        return values.isEmpty ? .allowed(score: 51) : values.removeFirst()
    }
}

private actor RecoveryGate {
    private(set) var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        let ready = waiters
        waiters.removeAll()
        for waiter in ready { waiter.resume() }
    }
}

private final class RecoveryClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    func now() -> Date { lock.withLock { date } }
    func set(_ date: Date) { lock.withLock { self.date = date } }
}

@MainActor
private final class RecoveryBrowser {
    var openCount = 0
}
