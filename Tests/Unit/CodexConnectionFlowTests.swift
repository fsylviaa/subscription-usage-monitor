import Foundation
import XCTest
@testable import SubscriptionUsage

/// Fixed authorizations and in-memory storage only. No network, account or clipboard access.
@MainActor
final class CodexConnectionFlowTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    func testT16OpeningAndClosingPlatformPickerDoesNotCheckNetworkOrStartLogin() async throws {
        let authorization = try fixture()
        let authorizer = FlowAuthorizerStub(authorization)
        let transactions = FlowTransactionStub()
        let scores = FlowScoreStub([.allowed(score: 51)])
        let flow = makeFlow(authorization, authorizer: authorizer, store: transactions,
                            checkNetwork: { await scores.next() })
        flow.showPlatformPicker()
        flow.showPlatformPicker()
        XCTAssertEqual(flow.state, .choosingPlatform)
        XCTAssertTrue(flow.isPresented)
        flow.cancel()
        XCTAssertEqual(flow.state, .idle)
        XCTAssertFalse(flow.isPresented)
        XCTAssertNil(flow.selectPlatform(.codex), "关闭后迟到的图标点击不能发起登录")
        let checks = await scores.count
        let requests = await authorizer.requestCount
        let saves = await transactions.saveCount
        XCTAssertEqual(checks, 0)
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(saves, 0)
        XCTAssertTrue(flow.accounts.isEmpty)
    }

    func testT16PlatformSelectionStartsExactlyOneGatedLogin() async throws {
        let authorization = try fixture()
        let authorizer = FlowAuthorizerStub(authorization)
        let scores = FlowScoreStub([.allowed(score: 51)])
        let flow = makeFlow(authorization, authorizer: authorizer, checkNetwork: { await scores.next() })
        flow.showPlatformPicker()
        let work = try XCTUnwrap(flow.selectPlatform(.codex))
        XCTAssertNil(flow.selectPlatform(.codex))
        flow.showPlatformPicker()
        XCTAssertEqual(flow.state, .checking)
        await work.value
        XCTAssertEqual(flow.state, .code(authorization))
        let checks = await scores.count
        let requests = await authorizer.requestCount
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(requests, 1)
        flow.cancel()
    }

    func testT16SelectionStillBlocksLowNetworkScoreBeforeAuthorization() async throws {
        let authorization = try fixture()
        let authorizer = FlowAuthorizerStub(authorization)
        let flow = makeFlow(authorization, authorizer: authorizer, checkNetwork: { .blocked(score: 50) })
        flow.showPlatformPicker()
        try await XCTUnwrap(flow.selectPlatform(.codex)).value
        XCTAssertEqual(flow.state, .failure("网络不达标，无法连接"))
        let requests = await authorizer.requestCount
        XCTAssertEqual(requests, 0)
        flow.cancel()
    }

    func test50BlocksBeforeRequestingOrOpeningAuthorization() async throws {
        let authorization = try fixture()
        let authorizer = FlowAuthorizerStub(authorization)
        let store = FlowTransactionStub()
        var opened = 0
        let flow = CodexConnectionFlow(
            checkNetwork: { .blocked(score: 50) }, authorizer: authorizer,
            transactions: store, now: { authorization.startedAt },
            copyCode: { _, _ in XCTFail("阻止后不能复制") },
            openURL: { _ in opened += 1; return true }
        )

        try await XCTUnwrap(flow.begin()).value
        flow.copy()
        await flow.openWebsite()

        XCTAssertEqual(flow.state, .failure("网络不达标，无法连接"))
        let requests = await authorizer.requestCount
        let saves = await store.saveCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(saves, 0)
        XCTAssertEqual(opened, 0)
        print("T07 | 固定评分 50 | 网络不达标；申请 0 次、打开 0 次")
    }

    func test51AutomaticallyRequestsExactlyOnceAndSavesBeforeShowingCode() async throws {
        let authorization = try fixture()
        let authorizer = FlowAuthorizerStub(authorization)
        let store = FlowTransactionStub()
        let check = FlowScoreStub([.allowed(score: 51)])
        let flow = makeFlow(authorization, authorizer: authorizer, store: store,
                            checkNetwork: { await check.next() })

        let work = try XCTUnwrap(flow.begin())
        XCTAssertEqual(flow.state, .checking)
        XCTAssertTrue(flow.isPresented)
        XCTAssertNil(flow.begin(), "连续点击不能重复启动申请")
        await work.value

        XCTAssertEqual(flow.state, .code(authorization))
        XCTAssertNil(flow.begin(), "已有代码时不重新申请")
        let requests = await authorizer.requestCount
        let checks = await check.count
        let saved = await store.current
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(saved, authorization)
        print("T07 | 固定评分 51 | 自动进入代码步骤；申请 1 次，事务已保存")
    }

    func testUnknownScoreUsesBriefFailureAndDoesNotInventLowScore() async throws {
        for reason in [NetworkScoreFailure.timeout, .invalidScore, .transport] {
            let authorization = try fixture()
            let authorizer = FlowAuthorizerStub(authorization)
            let store = FlowTransactionStub()
            let flow = makeFlow(authorization, authorizer: authorizer, store: store,
                                checkNetwork: { .unavailable(reason) })

            try await XCTUnwrap(flow.begin()).value

            XCTAssertEqual(flow.state, .failure("登录未完成，请重试"))
            let requests = await authorizer.requestCount
            let saves = await store.saveCount
            XCTAssertEqual(requests, 0)
            XCTAssertEqual(saves, 0)
        }
        print("T07 | 评分未知 | 简短失败；不报低分，不申请代码")
    }

    func testRequestFailureDoesNotDisplayCodeOrSaveTransaction() async throws {
        let authorization = try fixture()
        let authorizer = FlowAuthorizerStub(authorization, fails: true)
        let store = FlowTransactionStub()
        let flow = makeFlow(authorization, authorizer: authorizer, store: store)

        try await XCTUnwrap(flow.begin()).value

        XCTAssertEqual(flow.state, .failure("登录未完成，请重试"))
        let requests = await authorizer.requestCount
        let saves = await store.saveCount
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(saves, 0)
        print("T07 | 申请代码失败 | 登录未完成；无代码、无有效账户")
    }

    func testCancellingSlowCheckRejectsLate51WithoutRequestingCode() async throws {
        let authorization = try fixture()
        let authorizer = FlowAuthorizerStub(authorization)
        let store = FlowTransactionStub()
        let entered = FlowTestGate()
        let release = FlowTestGate()
        let flow = makeFlow(authorization, authorizer: authorizer, store: store) {
            await entered.open()
            await release.wait()
            return .allowed(score: 51) // Deliberately ignores cancellation.
        }

        let work = try XCTUnwrap(flow.begin())
        await entered.wait()
        flow.cancel()
        await release.open()
        await work.value

        XCTAssertEqual(flow.state, .idle)
        XCTAssertFalse(flow.isPresented)
        let requests = await authorizer.requestCount
        let saves = await store.saveCount
        XCTAssertEqual(requests, 0)
        XCTAssertEqual(saves, 0)
        print("T07 | 慢检查期间取消，随后返回 51 | 返回原页；迟到结果不申请代码")
    }

    func testCancellingRequestRejectsLateCodeWithoutSavingIt() async throws {
        let authorization = try fixture()
        let authorizer = FlowAuthorizerStub(authorization, suspended: true)
        let store = FlowTransactionStub()
        let flow = makeFlow(authorization, authorizer: authorizer, store: store)

        let work = try XCTUnwrap(flow.begin())
        await authorizer.entered.wait()
        XCTAssertEqual(flow.state, .requesting)
        flow.cancel()
        await authorizer.release.open()
        await work.value

        XCTAssertEqual(flow.state, .idle)
        XCTAssertFalse(flow.isPresented)
        let saves = await store.saveCount
        XCTAssertEqual(saves, 0)
    }

    func testCancellingDuringSaveRemovesLateTransaction() async throws {
        let authorization = try fixture()
        let store = FlowTransactionStub(suspended: true)
        let flow = makeFlow(authorization, store: store)

        let work = try XCTUnwrap(flow.begin())
        await store.entered.wait()
        flow.cancel()
        await store.release.open()
        await work.value

        XCTAssertEqual(flow.state, .idle)
        XCTAssertFalse(flow.isPresented)
        let saved = await store.current
        XCTAssertNil(saved, "取消时正在保存的临时事务必须清除")
    }

    func testStorageFailurePreventsPresentingOrCopyingCode() async throws {
        let authorization = try fixture()
        let store = FlowTransactionStub(fails: true)
        var copies = 0
        let flow = CodexConnectionFlow(
            checkNetwork: { .allowed(score: 51) },
            authorizer: FlowAuthorizerStub(authorization), transactions: store,
            now: { authorization.startedAt }, copyCode: { _, _ in copies += 1 },
            openURL: { _ in XCTFail("保存失败时不能打开官网"); return true }
        )

        try await XCTUnwrap(flow.begin()).value
        flow.copy()
        await flow.openWebsite()

        XCTAssertEqual(flow.state, .failure("登录未完成，请重试"))
        XCTAssertEqual(copies, 0)
        let saved = await store.current
        XCTAssertNil(saved)
    }

    func testAuthorizationExpiringWhileSaveIsSuspendedIsNeverDisplayed() async throws {
        let authorization = try fixture()
        let store = FlowTransactionStub(suspended: true)
        let clock = FlowClock(authorization.startedAt)
        var copies = 0
        var opens = 0
        let flow = CodexConnectionFlow(
            checkNetwork: { .allowed(score: 51) },
            authorizer: FlowAuthorizerStub(authorization), transactions: store,
            now: { clock.now() }, copyCode: { _, _ in copies += 1 },
            openURL: { _ in opens += 1; return true }
        )

        let work = try XCTUnwrap(flow.begin())
        await store.entered.wait()
        clock.set(authorization.expiresAt)
        await store.release.open()
        await work.value
        flow.copy()
        await flow.openWebsite()

        XCTAssertEqual(flow.state, .failure("登录未完成，请重试"))
        XCTAssertEqual(copies, 0)
        XCTAssertEqual(opens, 0)
        let saved = await store.current
        XCTAssertNil(saved, "到期流程结束后清除短期事务")
        print("T07 | 保存期间到期 | 不显示或使用到期代码，不延长期限")
    }

    func testNewAttemptWaitsForCancelledSaveAndKeepsOnlyNewTransaction() async throws {
        let oldAuthorization = try fixture()
        let newAuthorization = try fixture()
        let store = FlowTransactionStub(suspended: true)
        let prematureRequest = XCTestExpectation(description: "旧保存结束前不能开始下一次申请")
        prematureRequest.isInverted = true
        let authorizer = FlowSequenceAuthorizer([oldAuthorization, newAuthorization]) { count in
            if count > 1, await store.finishedSaveCount == 0 { prematureRequest.fulfill() }
        }
        let flow = makeFlow(oldAuthorization, authorizer: authorizer, store: store)

        let oldWork = try XCTUnwrap(flow.begin())
        await store.entered.wait()
        flow.cancel()
        let newWork = try XCTUnwrap(flow.begin())
        // An inverted expectation gives the new task time to run while the old
        // save is deliberately held. Gates, rather than timing, control completion.
        let waiting = await XCTWaiter.fulfillment(of: [prematureRequest], timeout: 0.1)
        XCTAssertEqual(waiting, .completed)
        XCTAssertEqual(flow.state, .checking)
        let requestsBeforeRelease = await authorizer.requestCount
        XCTAssertEqual(requestsBeforeRelease, 1)
        await store.release.open()
        await oldWork.value
        await newWork.value

        XCTAssertEqual(flow.state, .code(newAuthorization))
        XCTAssertTrue(flow.isPresented)
        let saved = await store.current
        let requests = await authorizer.requestCount
        XCTAssertEqual(saved?.transactionID, newAuthorization.transactionID)
        XCTAssertEqual(requests, 2)
        print("T07 | 保存期间取消并立即重试 | 先完成旧清理，再申请；仅保留新事务")
    }

    func testCopyRequiresUserActionAndPreservesOriginalExpiry() async throws {
        let authorization = try fixture()
        var copiedValues: [(String, Date)] = []
        let flow = CodexConnectionFlow(
            checkNetwork: { .allowed(score: 51) },
            authorizer: FlowAuthorizerStub(authorization), transactions: FlowTransactionStub(),
            now: { authorization.startedAt.addingTimeInterval(60) },
            copyCode: { copiedValues.append(($0, $1)) }, openURL: { _ in true }
        )

        flow.copy()
        try await XCTUnwrap(flow.begin()).value
        XCTAssertTrue(copiedValues.isEmpty, "代码出现时不能自动写剪贴板")
        XCTAssertFalse(flow.copied)
        flow.copy()

        XCTAssertTrue(flow.copied)
        XCTAssertEqual(copiedValues.count, 1)
        XCTAssertTrue(copiedValues.first?.0 == authorization.userCode, "复制内容必须与显示代码一致")
        XCTAssertEqual(copiedValues.first?.1, authorization.expiresAt)
        print("T07 | 主动复制固定测试代码 | 内容一致，保留原始到期时间；未自动复制")
    }

    func testOpenUsesOfficialHTTPSURLWithoutCodeAndDoesNotCompleteLogin() async throws {
        let authorization = try fixture()
        var openedURLs: [URL] = []
        let flow = CodexConnectionFlow(
            checkNetwork: { .allowed(score: 51) },
            authorizer: FlowAuthorizerStub(authorization), transactions: FlowTransactionStub(),
            now: { authorization.startedAt }, copyCode: { _, _ in },
            openURL: { openedURLs.append($0); return true }
        )

        try await XCTUnwrap(flow.begin()).value
        XCTAssertTrue(openedURLs.isEmpty, "显示代码不会自动打开浏览器")
        await flow.openWebsite()

        XCTAssertEqual(openedURLs, [URL(string: "https://auth.openai.com/codex/device")!])
        XCTAssertEqual(flow.state, .code(authorization), "打开网页不等于登录完成")
        XCTAssertTrue(flow.isPresented)
        XCTAssertFalse(flow.browserFailed)
        print("T07 | 打开官网 | 官方 HTTPS 设备页，不拼接代码，不显示连接成功")
    }

    func testFailedBrowserOpeningStaysPendingAndCanRetry() async throws {
        let authorization = try fixture()
        var opens = 0
        let flow = CodexConnectionFlow(
            checkNetwork: { .allowed(score: 51) },
            authorizer: FlowAuthorizerStub(authorization), transactions: FlowTransactionStub(),
            now: { authorization.startedAt }, copyCode: { _, _ in },
            openURL: { _ in opens += 1; return opens > 1 }
        )

        try await XCTUnwrap(flow.begin()).value
        await flow.openWebsite()
        XCTAssertTrue(flow.browserFailed)
        XCTAssertEqual(flow.state, .code(authorization))
        await flow.openWebsite()
        XCTAssertFalse(flow.browserFailed)
        XCTAssertEqual(flow.state, .code(authorization))
        XCTAssertEqual(opens, 2)
    }

    func testLateBrowserResultAfterCancellationCannotRestoreSheetOrFailure() async throws {
        let authorization = try fixture()
        let entered = FlowTestGate()
        let release = FlowTestGate()
        let flow = CodexConnectionFlow(
            checkNetwork: { .allowed(score: 51) },
            authorizer: FlowAuthorizerStub(authorization), transactions: FlowTransactionStub(),
            now: { authorization.startedAt }, copyCode: { _, _ in }, openURL: { _ in
                await entered.open()
                await release.wait()
                return false
            }
        )

        try await XCTUnwrap(flow.begin()).value
        let opening = Task { await flow.openWebsite() }
        await entered.wait()
        flow.cancel()
        await release.open()
        await opening.value

        XCTAssertEqual(flow.state, .idle)
        XCTAssertFalse(flow.isPresented)
        XCTAssertFalse(flow.browserFailed)
    }

    func testAlreadyExpiredResponseIsNotSavedOrDisplayed() async throws {
        let authorization = try fixture()
        let store = FlowTransactionStub()
        let flow = CodexConnectionFlow(
            checkNetwork: { .allowed(score: 51) },
            authorizer: FlowAuthorizerStub(authorization), transactions: store,
            now: { authorization.expiresAt }, copyCode: { _, _ in }, openURL: { _ in true }
        )

        try await XCTUnwrap(flow.begin()).value

        XCTAssertEqual(flow.state, .failure("登录未完成，请重试"))
        let saves = await store.saveCount
        XCTAssertEqual(saves, 0)
    }

    func testBrowserAndCopyDoNotExtendDeadlineAndExpiredCodeCannotBeUsed() async throws {
        let authorization = try fixture()
        let clock = FlowClock(authorization.startedAt)
        let authorizer = FlowAuthorizerStub(authorization)
        let store = FlowTransactionStub()
        var opens = 0
        var copies = 0
        let flow = CodexConnectionFlow(
            checkNetwork: { .allowed(score: 51) }, authorizer: authorizer,
            transactions: store, now: { clock.now() }, copyCode: { _, _ in copies += 1 },
            openURL: { _ in opens += 1; return true }
        )

        try await XCTUnwrap(flow.begin()).value
        clock.set(authorization.expiresAt.addingTimeInterval(-1))
        flow.copy()
        await flow.openWebsite()
        let saved = await store.current
        XCTAssertEqual(saved?.expiresAt, authorization.expiresAt)
        clock.set(authorization.expiresAt)
        flow.expireIfNeeded()
        flow.copy()
        await flow.openWebsite()

        XCTAssertEqual(flow.state, .failure("登录未完成，请重试"))
        XCTAssertFalse(flow.copied)
        XCTAssertEqual(copies, 1)
        XCTAssertEqual(opens, 1)
        let requests = await authorizer.requestCount
        XCTAssertEqual(requests, 1)
        print("T07 | 官网往返与复制、随后原期限到期 | 不延长期限，不继续使用到期代码")
    }

    func testRetryPerformsFreshNetworkCheck() async throws {
        let authorization = try fixture()
        let authorizer = FlowAuthorizerStub(authorization)
        let check = FlowScoreStub([.blocked(score: 50), .allowed(score: 51)])
        let flow = makeFlow(authorization, authorizer: authorizer,
                            checkNetwork: { await check.next() })

        try await XCTUnwrap(flow.begin()).value
        XCTAssertEqual(flow.state, .failure("网络不达标，无法连接"))
        try await XCTUnwrap(flow.begin()).value

        XCTAssertEqual(flow.state, .code(authorization))
        let checks = await check.count
        let requests = await authorizer.requestCount
        XCTAssertEqual(checks, 2)
        XCTAssertEqual(requests, 1)
    }

    private func fixture() throws -> CodexDeviceAuthorization {
        try CodexDeviceAuthorization(deviceAuthID: "synthetic-device", userCode: "TEST-1234",
                                     pollInterval: 5, startedAt: start)
    }

    private func makeFlow(
        _ authorization: CodexDeviceAuthorization,
        authorizer: (any CodexDeviceAuthorizing)? = nil,
        store: any CodexLoginTransactionStoring = FlowTransactionStub(),
        checkNetwork: @escaping @Sendable () async -> NetworkScoreResult = { .allowed(score: 51) }
    ) -> CodexConnectionFlow {
        CodexConnectionFlow(checkNetwork: checkNetwork,
                            authorizer: authorizer ?? FlowAuthorizerStub(authorization),
                            transactions: store, now: { authorization.startedAt },
                            copyCode: { _, _ in }, openURL: { _ in true })
    }
}

private actor FlowAuthorizerStub: CodexDeviceAuthorizing {
    let entered = FlowTestGate()
    let release = FlowTestGate()
    private let authorization: CodexDeviceAuthorization
    private let fails: Bool
    private let suspended: Bool
    private(set) var requestCount = 0

    init(_ authorization: CodexDeviceAuthorization, fails: Bool = false, suspended: Bool = false) {
        self.authorization = authorization
        self.fails = fails
        self.suspended = suspended
    }

    func requestAuthorization() async throws -> CodexDeviceAuthorization {
        requestCount += 1
        if suspended {
            await entered.open()
            await release.wait()
        }
        if fails { throw CodexDeviceAuthorizationError.requestFailed }
        return authorization
    }
}

private actor FlowTransactionStub: CodexLoginTransactionStoring {
    let entered = FlowTestGate()
    let release = FlowTestGate()
    private let fails: Bool
    private let suspended: Bool
    private(set) var saveCount = 0
    private(set) var finishedSaveCount = 0
    private(set) var current: CodexDeviceAuthorization?

    init(fails: Bool = false, suspended: Bool = false) {
        self.fails = fails
        self.suspended = suspended
    }

    func save(_ authorization: CodexDeviceAuthorization) async throws {
        saveCount += 1
        if suspended {
            await entered.open()
            await release.wait()
        }
        if fails { throw CodexDeviceAuthorizationError.requestFailed }
        current = authorization
        finishedSaveCount += 1
    }

    func remove(transactionID: UUID) async throws {
        if current?.transactionID == transactionID { current = nil }
    }
}

private actor FlowSequenceAuthorizer: CodexDeviceAuthorizing {
    private var authorizations: [CodexDeviceAuthorization]
    private let onRequest: @Sendable (Int) async -> Void
    private(set) var requestCount = 0

    init(_ authorizations: [CodexDeviceAuthorization],
         onRequest: @escaping @Sendable (Int) async -> Void) {
        self.authorizations = authorizations
        self.onRequest = onRequest
    }

    func requestAuthorization() async throws -> CodexDeviceAuthorization {
        requestCount += 1
        await onRequest(requestCount)
        guard !authorizations.isEmpty else { throw CodexDeviceAuthorizationError.requestFailed }
        return authorizations.removeFirst()
    }
}

private actor FlowScoreStub {
    private var results: [NetworkScoreResult]
    private(set) var count = 0

    init(_ results: [NetworkScoreResult]) { self.results = results }

    func next() -> NetworkScoreResult {
        count += 1
        guard !results.isEmpty else { return .unavailable(.invalidScore) }
        return results.removeFirst()
    }
}

private actor FlowTestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private final class FlowClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }
    func now() -> Date { lock.withLock { value } }
    func set(_ value: Date) { lock.withLock { self.value = value } }
}
