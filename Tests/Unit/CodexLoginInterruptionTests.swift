import Foundation
import XCTest
@testable import SubscriptionUsage

/// T10 uses a new Keychain reader and a new flow for each cold restoration.
/// All identities and secrets are fixed fixtures in a unique test service.
@MainActor
final class CodexLoginInterruptionTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let failed = CodexConnectionFlow.State.failure("登录未完成，请重试")

    func testColdPollingRecoveryKeepsOriginalCodeAndDeadlineWithoutRequestingAgain() async throws {
        let s = try scenario(holdPoll: true)
        try await seed(s, phase: nil)
        let flow = s.makeFlow()
        await flow.loadAccounts()
        await waitUntil { await s.client.pollCount == 1 }

        XCTAssertEqual(flow.state, .code(s.original))
        XCTAssertTrue(flow.accounts.isEmpty)
        let polled = await s.client.authorizations
        XCTAssertEqual(polled, [s.original])
        XCTAssertEqual(polled.first?.startedAt, start)
        XCTAssertEqual(polled.first?.expiresAt, start.addingTimeInterval(900))
        let requests = await s.authorizer.count
        let checks = await s.scores.count
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(checks, 1)

        flow.cancel()
        await s.client.pollRelease.open()
        await waitForCleanup(s)
        print("T10 | 等待授权时冷恢复 | 保持原代码、原开始与到期时间；未重新申请，也未假成功")
    }

    func testColdCodeReadyRecoveryExchangesOnlyOnceAndPersistsUncertainBoundary() async throws {
        let s = try scenario(holdExchange: true)
        try await seed(s, phase: .codeReady(s.code))
        let flow = s.makeFlow()
        await flow.loadAccounts()
        await waitUntil { await s.client.exchangeCount == 1 }
        let intermediate = try await s.pending.load(transactionID: s.original.transactionID)
        guard case .exchangeStarted = intermediate else {
            XCTFail("发出一次性代码交换前必须先持久标记已开始")
            flow.cancel()
            await s.client.exchangeRelease.open()
            return
        }
        XCTAssertEqual(flow.state, .verifying)
        XCTAssertTrue(flow.accounts.isEmpty)
        for _ in 0..<3 {
            flow.setActive(false)
            flow.setActive(true)
            await flow.loadAccounts()
        }
        await s.client.exchangeRelease.open()
        await waitUntil { flow.accounts.count == 1 }

        let requests = await s.authorizer.count
        let polls = await s.client.pollCount
        let exchanges = await s.client.exchangedCodes
        let verifies = await s.verifier.tokens
        let saves = await s.bindings.saveCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(polls, 0)
        XCTAssertEqual(exchanges, [s.code.code])
        XCTAssertEqual(verifies, [s.tokens.accessToken])
        XCTAssertEqual(saves, 1)
        XCTAssertEqual(flow.accounts.first?.quotaState, .notFetched)
        await waitForCleanup(s)
        print("T10 | 已领取代码冷恢复及重复返回 | 只交换一次、只保存一个账户；交换前保留不明结果标记")
    }

    func testBackgroundPollingRecoveryWaitsForForegroundThenContinuesAutomatically() async throws {
        let s = try scenario()
        try await seed(s, phase: nil)
        let flow = s.makeFlow()
        flow.setActive(false)
        await flow.loadAccounts()
        XCTAssertEqual(flow.state, .code(s.original))
        let pollsBefore = await s.client.pollCount
        XCTAssertEqual(pollsBefore, 0)
        XCTAssertTrue(flow.accounts.isEmpty)

        flow.setActive(true)
        await waitUntil { flow.accounts.count == 1 }
        let requests = await s.authorizer.count
        let polled = await s.client.authorizations
        let saves = await s.bindings.saveCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(polled, [s.original])
        XCTAssertEqual(saves, 1)
        await waitForCleanup(s)
        print("T10 | 后台恢复等待中的授权，随后回前台 | 后台不轮询；返回后自动继续原事务，无额外确认")
    }

    func testColdTokensReadyRecoveryOnlyVerifiesAndSavesOnce() async throws {
        let s = try scenario(holdVerification: true)
        try await seed(s, phase: .tokensReady(s.tokens))
        let flow = s.makeFlow()
        await flow.loadAccounts()
        await waitUntil { await s.verifier.tokens.count == 1 }
        XCTAssertEqual(flow.state, .verifying)
        XCTAssertTrue(flow.accounts.isEmpty)
        for _ in 0..<3 {
            await flow.loadAccounts()
            flow.setActive(true)
        }
        await s.verifier.release.open()
        await waitUntil { flow.accounts.count == 1 }

        let requests = await s.authorizer.count
        let polls = await s.client.pollCount
        let exchanges = await s.client.exchangeCount
        let verified = await s.verifier.tokens
        let saves = await s.bindings.saveCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(polls, 0)
        XCTAssertEqual(exchanges, 0)
        XCTAssertEqual(verified, [s.tokens.accessToken])
        XCTAssertEqual(saves, 1)
        XCTAssertFalse(flow.isPresented)
        await waitForCleanup(s)
        print("T10 | 待核验令牌冷恢复 | 只核验原令牌；不领取、不交换、不重复保存")
    }

    func testUncertainExchangeFailsBrieflyAndRetryUsesFreshAuthorization() async throws {
        let s = try scenario()
        try await seed(s, phase: .exchangeStarted)
        let flow = s.makeFlow()
        await flow.loadAccounts()
        await waitUntil { flow.state == self.failed }
        XCTAssertTrue(flow.accounts.isEmpty)
        let pollsBefore = await s.client.pollCount
        let exchangesBefore = await s.client.exchangeCount
        let verifiesBefore = await s.verifier.tokens.count
        XCTAssertEqual(pollsBefore, 0)
        XCTAssertEqual(exchangesBefore, 0)
        XCTAssertEqual(verifiesBefore, 0)
        await waitForCleanup(s)

        try await XCTUnwrap(flow.begin()).value
        await waitUntil { flow.accounts.count == 1 }
        let requests = await s.authorizer.count
        let polled = await s.client.authorizations
        let exchanged = await s.client.exchangedCodes
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(polled, [s.replacement])
        XCTAssertEqual(exchanged, [s.replacement.deviceAuthID])
        XCTAssertFalse(exchanged.contains(s.code.code))
        await waitForCleanup(s)
        print("T10 | 交换结果不明冷恢复 | 简短失败；重试可成功且不重放旧代码")
    }

    func testExpiredPersistedTokensCannotCreateAccountAndRetryStartsFresh() async throws {
        let s = try scenario(expired: true)
        try await seed(s, phase: .tokensReady(s.tokens))
        let flow = s.makeFlow()
        await flow.loadAccounts()
        await waitUntil { flow.state == self.failed }
        let verifiesBefore = await s.verifier.tokens.count
        XCTAssertEqual(verifiesBefore, 0)
        XCTAssertTrue(flow.accounts.isEmpty)
        await waitForCleanup(s)

        try await XCTUnwrap(flow.begin()).value
        await waitUntil { flow.accounts.count == 1 }
        let requests = await s.authorizer.count
        let polled = await s.client.authorizations
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(polled, [s.replacement])
        await waitForCleanup(s)
        print("T10 | 已到期事务冷恢复 | 不延长原期限、不使用旧令牌；重新开始可用")
    }

    func testCancellationFollowedByNewFlowNeverRestoresOldLogin() async throws {
        let s = try scenario(holdPoll: true)
        try await seed(s, phase: nil)
        let first = s.makeFlow()
        await first.loadAccounts()
        await waitUntil { await s.client.pollCount == 1 }
        first.cancel()
        await s.client.pollRelease.open()
        await waitForCleanup(s)

        let reopened = s.makeFlow()
        await reopened.loadAccounts()
        XCTAssertEqual(reopened.state, .idle)
        XCTAssertFalse(reopened.isPresented)
        XCTAssertTrue(reopened.accounts.isEmpty)
        XCTAssertTrue(reopened.canConnect)
        let requests = await s.authorizer.count
        let polls = await s.client.pollCount
        let saves = await s.bindings.saveCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(polls, 1)
        XCTAssertEqual(saves, 0)
        print("T10 | 取消后创建新流程 | 原事务不恢复，迟到结果不保存")
    }

    func testPersistedCancellationWithResidualTokensNeverResumesVerification() async throws {
        let s = try scenario()
        try await seed(s, phase: .tokensReady(s.tokens))
        try await s.transactions.cancel(transactionID: s.original.transactionID)
        let flow = s.makeFlow()
        await flow.loadAccounts()
        await waitForCleanup(s)

        XCTAssertEqual(flow.state, .idle)
        XCTAssertFalse(flow.isPresented)
        XCTAssertTrue(flow.accounts.isEmpty)
        let verifies = await s.verifier.tokens.count
        let saves = await s.bindings.saveCount
        XCTAssertEqual(verifies, 0)
        XCTAssertEqual(saves, 0)
        print("T10 | 取消已落盘但令牌尚未清理时冷恢复 | 清理残留；不恢复已取消事务")
    }

    func testCommittedAccountAndResidualTransactionDoNotSaveAgain() async throws {
        let original = ConnectedAccount(remoteUserID: "t10-existing-user", verifiedEmail: "existing@example.invalid",
            displayName: "已有测试账户", scope: .init(remoteAccountID: "t10-existing-account", kind: .personal),
            credentialRef: UUID(), generation: 4, quotaState: .notFetched)
        let s = try scenario(existing: [original])
        try await seed(s, phase: .tokensReady(s.tokens))
        let flow = s.makeFlow()
        await flow.loadAccounts()
        await waitForCleanup(s)

        XCTAssertEqual(flow.accounts, [original])
        XCTAssertEqual(flow.state, .idle)
        XCTAssertFalse(flow.isPresented)
        XCTAssertFalse(flow.canConnect)
        let verifies = await s.verifier.tokens.count
        let saves = await s.bindings.saveCount
        let stored = try await s.bindings.load()
        XCTAssertEqual(verifies, 0)
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(stored, [original])
        print("T10 | 账户已提交但事务尚未清理时冷恢复 | 保留完整原账户，只清理残留，不重复保存")
    }

    func testConcurrentLoadsAndForegroundEventsShareOneRecoveryChain() async throws {
        let s = try scenario(holdExchange: true, holdNetwork: true)
        try await seed(s, phase: .codeReady(s.code))
        let flow = s.makeFlow()
        let firstLoad = Task { await flow.loadAccounts() }
        await waitUntil { await s.scores.count == 1 }
        let secondLoad = Task { await flow.loadAccounts() }
        flow.setActive(false)
        flow.setActive(true)
        flow.setActive(true)
        await s.scores.release.open()
        await firstLoad.value
        await secondLoad.value
        await waitUntil { await s.client.exchangeCount == 1 }
        await s.client.exchangeRelease.open()
        await waitUntil { flow.accounts.count == 1 }

        let checks = await s.scores.count
        let exchanges = await s.client.exchangeCount
        let saves = await s.bindings.saveCount
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(exchanges, 1)
        XCTAssertEqual(saves, 1)
        await waitForCleanup(s)
        print("T10 | 重复加载与连续前台事件 | 网络检查、交换、账户提交各一次")
    }

    func testNetworkBlockedColdRecoveryRetainsEachSafePhaseForNextLaunch() async throws {
        for index in 0..<3 {
            let s = try scenario(scores: [.blocked(score: 50), .allowed(score: 51)])
            let phase: CodexPendingLoginState? = index == 0 ? nil
                : (index == 1 ? .codeReady(s.code) : .tokensReady(s.tokens))
            try await seed(s, phase: phase)
            let blocked = s.makeFlow()
            await blocked.loadAccounts()
            await waitUntil { blocked.state == .failure("网络不达标，无法连接") }
            let retained = try await s.transactions.load()
            let retainedPhase = try await s.pending.load(transactionID: s.original.transactionID)
            XCTAssertEqual(retained, s.original)
            assertPhase(retainedPhase, matches: phase)
            let pollsBefore = await s.client.pollCount
            let exchangesBefore = await s.client.exchangeCount
            let verifiesBefore = await s.verifier.tokens.count
            XCTAssertEqual(pollsBefore, 0)
            XCTAssertEqual(exchangesBefore, 0)
            XCTAssertEqual(verifiesBefore, 0)

            let reopened = s.makeFlow()
            await reopened.loadAccounts()
            await waitUntil { reopened.accounts.count == 1 }
            let requests = await s.authorizer.count
            let polls = await s.client.pollCount
            let exchanges = await s.client.exchangeCount
            let verifies = await s.verifier.tokens.count
            XCTAssertEqual(requests, 0)
            XCTAssertEqual(polls, index == 0 ? 1 : 0)
            XCTAssertEqual(exchanges, index == 2 ? 0 : 1)
            XCTAssertEqual(verifies, 1)
            await waitForCleanup(s)
            blocked.cancel()
        }
        print("T10 | 恢复网络门控未通过 | 三种安全阶段均原样保留；下次启动从原阶段继续")
    }

    func testDamagedOrUnknownPendingStateFailsBrieflyThenAllowsFreshLogin() async throws {
        for damaged in [true, false] {
            let s = try scenario()
            try await seed(s, phase: nil)
            let vault = CredentialVault(service: s.service)
            let payload: Data
            if damaged {
                payload = Data("invalid-pending-package".utf8)
            } else {
                payload = try JSONSerialization.data(withJSONObject: ["version": 1, "phase": "unknown-stage",
                                                                       "transactionID": s.original.transactionID.uuidString])
            }
            try await vault.save(CredentialPayload(data: payload), for: .loginTransaction(s.original.transactionID))
            let flow = s.makeFlow()
            await flow.loadAccounts()
            await waitUntil { flow.state == self.failed }
            XCTAssertTrue(flow.accounts.isEmpty)
            let pollsBefore = await s.client.pollCount
            let exchangesBefore = await s.client.exchangeCount
            XCTAssertEqual(pollsBefore, 0)
            XCTAssertEqual(exchangesBefore, 0)

            try await XCTUnwrap(flow.begin()).value
            await waitUntil { flow.accounts.count == 1 }
            let requests = await s.authorizer.count
            let polled = await s.client.authorizations
            let saves = await s.bindings.saveCount
            XCTAssertEqual(requests, 1)
            XCTAssertEqual(polled, [s.replacement])
            XCTAssertEqual(saves, 1)
            await waitForCleanup(s)
        }
        print("T10 | 损坏或未知恢复阶段 | 简短失败后可重新申请；不反复读取坏数据，不猜测旧阶段")
    }

    func testCancelWhileRetryReadsUnknownTransactionRejectsAndCleansLateRecovery() async throws {
        let s = try scenario()
        try await seed(s, phase: .tokensReady(s.tokens))
        let interruptedStore = InterruptionReadStore(underlying: s.transactions)
        let flow = s.makeFlow(transactionStore: interruptedStore)
        await flow.loadAccounts()
        XCTAssertEqual(flow.state, failed)
        XCTAssertTrue(flow.accounts.isEmpty)
        let retained = try await s.transactions.load()
        XCTAssertEqual(retained, s.original, "第一次临时不可读不能误删原事务")

        let retry = try XCTUnwrap(flow.begin())
        await waitUntil { await interruptedStore.readCount == 2 }
        flow.cancel()
        XCTAssertEqual(flow.state, .checking)
        XCTAssertTrue(flow.isPresented)
        await interruptedStore.release.open()
        await retry.value
        await waitForCleanup(s)
        await waitUntil { flow.state == .idle && !flow.isPresented }

        let reopened = s.makeFlow()
        await reopened.loadAccounts()
        XCTAssertEqual(reopened.state, .idle)
        XCTAssertFalse(reopened.isPresented)
        XCTAssertTrue(reopened.accounts.isEmpty)
        XCTAssertTrue(reopened.canConnect)
        let requests = await s.authorizer.count
        let verifies = await s.verifier.tokens.count
        let saves = await s.bindings.saveCount
        let cancelledIDs = await interruptedStore.cancelledIDs
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(verifies, 0)
        XCTAssertEqual(saves, 0)
        XCTAssertTrue(cancelledIDs.contains(s.original.transactionID), "迟到读出的事务应先记录取消，再清理秘密")
        print("T10 | 恢复读取暂时失败，重试读取挂起时取消 | 迟到事务安全取消并清理；再次启动不恢复、不保存")
    }

    func testDirectCancelAfterUnavailableStartupReadCleansUnknownTransactionBeforeDismissal() async throws {
        let s = try scenario()
        try await seed(s, phase: .tokensReady(s.tokens))
        let interruptedStore = InterruptionReadStore(underlying: s.transactions)
        let flow = s.makeFlow(transactionStore: interruptedStore)
        await flow.loadAccounts()
        XCTAssertEqual(flow.state, failed)

        flow.cancel()
        await waitUntil { await interruptedStore.readCount == 2 }
        XCTAssertTrue(flow.isPresented, "尚未读取并持久取消原事务时不能假称已取消")
        await interruptedStore.release.open()
        await waitUntil { flow.state == .idle && !flow.isPresented }
        await waitForCleanup(s)

        let reopened = s.makeFlow()
        await reopened.loadAccounts()
        XCTAssertEqual(reopened.state, .idle)
        XCTAssertFalse(reopened.isPresented)
        XCTAssertTrue(reopened.accounts.isEmpty)
        let verifies = await s.verifier.tokens.count
        let saves = await s.bindings.saveCount
        let cancelledIDs = await interruptedStore.cancelledIDs
        XCTAssertEqual(verifies, 0)
        XCTAssertEqual(saves, 0)
        XCTAssertTrue(cancelledIDs.contains(s.original.transactionID))
        print("T10 | 首次恢复暂时不可读后直接取消 | 先安全取消并清理未知事务，再关闭；重开不恢复")
    }

    func testUnavailableStorageKeepsCancellationVisibleUntilItCanBeSaved() async throws {
        let s = try scenario()
        try await seed(s, phase: .tokensReady(s.tokens))
        let interruptedStore = InterruptionReadStore(underlying: s.transactions, failedReads: Int.max, suspendSecondRead: false)
        let flow = s.makeFlow(transactionStore: interruptedStore)
        await flow.loadAccounts()
        XCTAssertEqual(flow.state, failed)

        for expectedReads in 2...3 {
            flow.cancel()
            await waitUntil { await interruptedStore.readCount == expectedReads && flow.state == self.failed }
            XCTAssertTrue(flow.isPresented)
            XCTAssertTrue(flow.accounts.isEmpty)
            let retained = try await s.transactions.load()
            let pending = try await s.pending.load(transactionID: s.original.transactionID)
            XCTAssertEqual(retained, s.original)
            assertPhase(pending, matches: .tokensReady(s.tokens))
        }

        await interruptedStore.allowReads()
        flow.cancel()
        await waitUntil { flow.state == .idle && !flow.isPresented }
        await waitForCleanup(s)
        let reopened = s.makeFlow()
        await reopened.loadAccounts()
        XCTAssertEqual(reopened.state, .idle)
        XCTAssertFalse(reopened.isPresented)
        XCTAssertTrue(reopened.accounts.isEmpty)
        let verifies = await s.verifier.tokens.count
        let saves = await s.bindings.saveCount
        XCTAssertEqual(verifies, 0)
        XCTAssertEqual(saves, 0)
        print("T10 | 存储持续不可读时取消 | 保持简短失败；恢复可读后再次取消成功，重开不恢复")
    }

    private func assertPhase(_ actual: CodexPendingLoginState?, matches expected: CodexPendingLoginState?,
                             file: StaticString = #filePath, line: UInt = #line) {
        switch (actual, expected) {
        case (nil, nil): break
        case let (.codeReady(actual), .codeReady(expected)):
            XCTAssertTrue(actual.code == expected.code && actual.verifier == expected.verifier, file: file, line: line)
        case let (.tokensReady(actual), .tokensReady(expected)):
            XCTAssertTrue(actual.accessToken == expected.accessToken && actual.idToken == expected.idToken
                          && actual.refreshToken == expected.refreshToken, file: file, line: line)
        default: XCTFail("应保持原安全阶段", file: file, line: line)
        }
    }

    private func seed(_ s: InterruptionScenario, phase: CodexPendingLoginState?) async throws {
        let writerVault = CredentialVault(service: s.service)
        let writer = CodexLoginTransactionStore(vault: writerVault)
        let pending = CodexPendingLoginStore(vault: writerVault)
        try await writer.save(s.original)
        switch phase {
        case let .codeReady(code): try await pending.saveCode(code, transactionID: s.original.transactionID)
        case .exchangeStarted:
            try await pending.saveCode(s.code, transactionID: s.original.transactionID)
            try await pending.markExchangeStarted(transactionID: s.original.transactionID)
        case let .tokensReady(tokens): try await pending.saveTokens(tokens, transactionID: s.original.transactionID)
        case nil: break
        }
    }

    private func waitForCleanup(_ s: InterruptionScenario, file: StaticString = #filePath, line: UInt = #line) async {
        await waitUntil(file: file, line: line) {
            do {
                let transaction = try await s.transactions.load()
                let cancelled = try await s.transactions.loadCancelledTransactionID()
                let original = try await s.pending.load(transactionID: s.original.transactionID)
                let replacement = try await s.pending.load(transactionID: s.replacement.transactionID)
                return transaction == nil && cancelled == nil && original == nil && replacement == nil
            } catch { return false }
        }
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () async -> Bool) async {
        for _ in 0..<300 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("恢复流程未在时限内达到预期状态", file: file, line: line)
    }

    private func scenario(holdPoll: Bool = false, holdExchange: Bool = false, holdVerification: Bool = false,
                          holdNetwork: Bool = false, expired: Bool = false, existing: [ConnectedAccount] = [],
                          scores: [NetworkScoreResult] = [.allowed(score: 51)]) throws -> InterruptionScenario {
        let service = "com.iceflying.SubscriptionUsage.tests.T10.Flow.\(UUID().uuidString)"
        let original = try CodexDeviceAuthorization(deviceAuthID: "t10-original-device", userCode: "T10-ORIGINAL",
            pollInterval: 1, startedAt: start)
        let now = expired ? original.expiresAt : start.addingTimeInterval(10)
        let replacement = try CodexDeviceAuthorization(deviceAuthID: "t10-replacement-device", userCode: "T10-REPLACEMENT",
            pollInterval: 1, startedAt: now)
        let tokens = CodexTokenResponse(accessToken: "t10-access", refreshToken: "t10-refresh", idToken: "t10-id",
            obtainedAt: start, expiresAt: start.addingTimeInterval(3600))
        let vault = CredentialVault(service: service)
        let transactions = CodexLoginTransactionStore(vault: vault)
        let pending = CodexPendingLoginStore(vault: vault)
        let scenario = InterruptionScenario(service: service, original: original, replacement: replacement,
            code: .init(code: "t10-unused-code", verifier: String(repeating: "v", count: 43)), tokens: tokens,
            authorizer: InterruptionAuthorizer(authorization: replacement),
            client: InterruptionClient(tokens: tokens, holdPoll: holdPoll, holdExchange: holdExchange),
            verifier: InterruptionVerifier(hold: holdVerification), bindings: InterruptionBindings(accounts: existing),
            scores: InterruptionScores(values: scores, hold: holdNetwork), transactions: transactions, pending: pending, now: now)
        addTeardownBlock {
            await scenario.client.pollRelease.open()
            await scenario.client.exchangeRelease.open()
            await scenario.verifier.release.open()
            await scenario.scores.release.open()
            for id in [original.transactionID, replacement.transactionID] {
                try await pending.remove(transactionID: id)
                try await transactions.remove(transactionID: id)
            }
        }
        return scenario
    }
}

private struct InterruptionScenario {
    let service: String
    let original: CodexDeviceAuthorization
    let replacement: CodexDeviceAuthorization
    let code: CodexAuthorizationCode
    let tokens: CodexTokenResponse
    let authorizer: InterruptionAuthorizer
    let client: InterruptionClient
    let verifier: InterruptionVerifier
    let bindings: InterruptionBindings
    let scores: InterruptionScores
    let transactions: CodexLoginTransactionStore
    let pending: CodexPendingLoginStore
    let now: Date

    @MainActor
    func makeFlow(transactionStore: (any CodexLoginTransactionStoring)? = nil) -> CodexConnectionFlow {
        // Recreate the storage objects as happens in a new process, using only
        // the persisted service; no prior flow's in-memory recovery is shared.
        let vault = CredentialVault(service: service)
        return CodexConnectionFlow(checkNetwork: { await scores.next() }, authorizer: authorizer,
            transactions: transactionStore ?? CodexLoginTransactionStore(vault: vault), completer: client, verifier: verifier,
            bindings: bindings, pending: CodexPendingLoginStore(vault: vault), now: { now },
            copyCode: { _, _ in }, openURL: { _ in true })
    }
}

/// By default, the first read is unavailable and the second deliberately returns
/// a late result after cancellation. Tests can retain the failure until allowReads().
private actor InterruptionReadStore: CodexLoginTransactionStoring {
    let release = InterruptionGate()
    private let underlying: CodexLoginTransactionStore
    private var failedReads: Int
    private let suspendSecondRead: Bool
    private(set) var readCount = 0
    private(set) var cancelledIDs: [UUID] = []
    init(underlying: CodexLoginTransactionStore, failedReads: Int = 1, suspendSecondRead: Bool = true) {
        self.underlying = underlying
        self.failedReads = failedReads
        self.suspendSecondRead = suspendSecondRead
    }
    func allowReads() { failedReads = 0 }
    func save(_ authorization: CodexDeviceAuthorization) async throws { try await underlying.save(authorization) }
    func load() async throws -> CodexDeviceAuthorization? {
        readCount += 1
        if failedReads > 0 {
            failedReads -= 1
            throw CredentialVault.VaultError.temporarilyUnavailable
        }
        if suspendSecondRead, readCount == 2 { await release.wait() }
        return try await underlying.load()
    }
    func loadCancelledTransactionID() async throws -> UUID? { try await underlying.loadCancelledTransactionID() }
    func cancel(transactionID: UUID) async throws {
        cancelledIDs.append(transactionID)
        try await underlying.cancel(transactionID: transactionID)
    }
    func remove(transactionID: UUID) async throws { try await underlying.remove(transactionID: transactionID) }
}

private actor InterruptionAuthorizer: CodexDeviceAuthorizing {
    private let authorization: CodexDeviceAuthorization
    private(set) var count = 0
    init(authorization: CodexDeviceAuthorization) { self.authorization = authorization }
    func requestAuthorization() async throws -> CodexDeviceAuthorization { count += 1; return authorization }
}

private actor InterruptionClient: CodexLoginCompleting {
    let pollRelease = InterruptionGate()
    let exchangeRelease = InterruptionGate()
    private let tokens: CodexTokenResponse
    private let holdPoll: Bool
    private let holdExchange: Bool
    private(set) var authorizations: [CodexDeviceAuthorization] = []
    private(set) var exchangedCodes: [String] = []
    var pollCount: Int { authorizations.count }
    var exchangeCount: Int { exchangedCodes.count }
    init(tokens: CodexTokenResponse, holdPoll: Bool, holdExchange: Bool) {
        self.tokens = tokens; self.holdPoll = holdPoll; self.holdExchange = holdExchange
    }
    func poll(_ authorization: CodexDeviceAuthorization) async throws -> CodexAuthorizationCode? {
        authorizations.append(authorization)
        if holdPoll { await pollRelease.wait() }
        return .init(code: authorization.deviceAuthID, verifier: String(repeating: "v", count: 43))
    }
    func exchange(_ code: CodexAuthorizationCode) async throws -> CodexTokenResponse {
        exchangedCodes.append(code.code)
        if holdExchange { await exchangeRelease.wait() }
        return tokens
    }
}

private actor InterruptionVerifier: CodexIdentityVerifying {
    let release = InterruptionGate()
    private let hold: Bool
    private(set) var tokens: [String] = []
    init(hold: Bool) { self.hold = hold }
    func verify(_ token: CodexTokenResponse) async throws -> CodexVerifiedLogin {
        tokens.append(token.accessToken)
        if hold { await release.wait() }
        return .fixture(remoteUserID: "t10-verified-user", email: "verified@example.invalid",
            scope: .init(remoteAccountID: "t10-account", kind: .personal),
            credentials: .init(data: Data("t10-verified-package".utf8)))
    }
}

private actor InterruptionBindings: CodexAccountBinding {
    private var accounts: [ConnectedAccount]
    private(set) var saveCount = 0
    init(accounts: [ConnectedAccount]) { self.accounts = accounts }
    func load() async throws -> [ConnectedAccount] { accounts }
    func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount {
        saveCount += 1
        guard accounts.isEmpty else { throw CodexLoginError.failed }
        let account = ConnectedAccount(remoteUserID: login.remoteUserID, verifiedEmail: login.email,
            scope: login.scope, credentialRef: UUID())
        accounts = [account]
        return account
    }
}

private actor InterruptionScores {
    let release = InterruptionGate()
    private var values: [NetworkScoreResult]
    private let hold: Bool
    private(set) var count = 0
    init(values: [NetworkScoreResult], hold: Bool) { self.values = values; self.hold = hold }
    func next() async -> NetworkScoreResult {
        count += 1
        if hold { await release.wait() }
        return values.isEmpty ? .allowed(score: 51) : values.removeFirst()
    }
}

private actor InterruptionGate {
    private var isOpen = false
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
