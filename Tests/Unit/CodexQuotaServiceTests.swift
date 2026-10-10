import Combine
import Foundation
import XCTest
@testable import SubscriptionUsage

@MainActor
final class CodexQuotaServiceTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_800_000_000)
    private var directories: [URL] = []

    override func tearDownWithError() throws {
        for directory in directories { try FileManager.default.removeItem(at: directory) }
        directories = []
    }

    func testGatedQueryStoresCorrectScopeWindowsAndResponseTimeWithoutSecrets() async throws {
        let setup = try await self.setup()
        let before = time.addingTimeInterval(-60)
        let clock = QuotaTestClock(before)
        let transport = QuotaTestTransport(data: Self.complete) { [time] in clock.set(time) }
        let updated = try await service(setup, transport: transport, now: { clock.get() }).update(setup.account)
        let quota = try XCTUnwrap(updated.quotaSnapshot)
        XCTAssertEqual(quota.weekly.amount.remainingPercent, 70)
        XCTAssertEqual(quota.fiveHours.amount.remainingPercent, 20)
        XCTAssertEqual(quota.weekly.resetsAt, Date(timeIntervalSince1970: 1_800_500_000))
        XCTAssertEqual(quota.fiveHours.resetsAt, Date(timeIntervalSince1970: 1_800_010_000))
        XCTAssertEqual(quota.observedAt, time, "成功时间在响应取得后，不是请求开始时间")
        XCTAssertEqual(quota.scope, setup.account.scope)
        XCTAssertEqual(quota.generation, setup.account.generation)
        let reopened = try await AccountStore(fileURL: setup.url).load()
        XCTAssertEqual(reopened, [updated])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url, CodexIdentityVerifier.usageURL)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "ChatGPT-Account-Id"), "quota-test-account")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer quota-test-access")
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Cookie"))
        let file = try String(contentsOf: setup.url, encoding: .utf8)
        for secret in ["quota-test-access", "quota-test-refresh", "quota-test-id", "accessToken", "refreshToken"] {
            XCTAssertFalse(file.contains(secret))
        }
        print("T12 | 成功保存重读 | 周剩余70%、5小时20%，各自真实重置、响应后成功时间与账户作用域一致；普通文件无授权")
    }

    func testNetwork50UnknownAndCancellationSendNoUsageAndKeepBinding() async throws {
        for result in [NetworkScoreResult.blocked(score: 50), .blocked(score: 49), .unavailable(.transport), .cancelled, .allowed(score: 50)] {
            let setup = try await self.setup()
            let transport = QuotaTestTransport(data: Self.complete)
            do {
                _ = try await service(setup, transport: transport, gate: { result }).update(setup.account)
                XCTFail("未通过的网络检查不得查询")
            } catch { }
            let count = await transport.requests.count
            let saved = try await setup.store.load()
            XCTAssertEqual(count, 0)
            XCTAssertEqual(saved, [setup.account])
        }
        print("T12 | 查询前50分/49分/未知/取消 | 请求0次；账户保留；没有成功快照和时间")
    }

    func testPartialResponsePreservesKnownWindowAndMissingReset() async throws {
        let setup = try await self.setup()
        let data = Data(#"{"account_id":"quota-test-account","plan_type":"plus","rate_limit":{"primary_window":{"limit_window_seconds":604800,"used_percent":30}}}"#.utf8)
        let updated = try await service(setup, transport: QuotaTestTransport(data: data)).update(setup.account)
        let quota = try XCTUnwrap(updated.quotaSnapshot)
        XCTAssertEqual(quota.weekly.amount.remainingPercent, 70)
        XCTAssertNil(quota.weekly.resetsAt)
        XCTAssertEqual(quota.fiveHours.amount, .unknown)
        XCTAssertNil(quota.fiveHours.resetsAt)
        XCTAssertEqual(updated.quotaState, .available)
        let reread = try await setup.store.load()
        XCTAssertEqual(reread, [updated])
        print("T12 | 部分响应 | 周70%保留，5小时未知，两窗口无重置时间；不填余额或假0%")
    }

    func testUnknownMalformedMismatchedAndHTTPFailuresPreserveOldValuesAndTime() async throws {
        let setup = try await self.setup()
        let old = try await service(setup, transport: QuotaTestTransport(data: Self.complete)).update(setup.account)
        let cases: [(Data, Int, String)] = [
            (Data(#"{"account_id":"quota-test-account","credits":{"unlimited":true}}"#.utf8), 200, "application/json"),
            (Data(#"{"account_id":"other","rate_limit":{}}"#.utf8), 200, "application/json"),
            (Self.complete, 401, "application/json"), (Self.complete, 403, "application/json"),
            (Self.complete, 429, "application/json"), (Self.complete, 500, "application/json"),
            (Self.complete, 200, "text/html"), (Data("invalid".utf8), 200, "application/json"),
            (Data(), 204, "application/json"),
            (Data(String(repeating: "a", count: 256 * 1024 + 1).utf8), 200, "application/json"),
            (Data(String(data: Self.complete, encoding: .utf8)!.replacingOccurrences(of: "\"account_id\"", with: "\"omitted_id\"").utf8), 200, "application/json"),
            (Data(String(data: Self.complete, encoding: .utf8)!.replacingOccurrences(of: "\"plan_type\"", with: "\"user_id\"").utf8), 200, "application/json")
        ]
        for (body, status, mime) in cases {
            do {
                _ = try await service(setup, transport: QuotaTestTransport(data: body, status: status, mime: mime), now: { [time] in time.addingTimeInterval(100) }).update(old)
                XCTFail("失败不能成为成功")
            } catch { XCTAssertEqual(error as? CodexQuotaError, .failed) }
            let reread = try await setup.store.load()
            XCTAssertEqual(reread, [old])
        }
        print("T12 | 无有效窗口/身份错误/HTTP与解析失败 | 原快照及成功时间不变")
    }

    func testRealObservedThirtyDayWindowIsNotRenamedToWeekOrFiveHours() async throws {
        let setup = try await self.setup()
        // Actual field shape observed on 2026-10-10; identity and reset are synthetic.
        let body = Data(#"{"account_id":"quota-test-account","rate_limit":{"primary_window":{"limit_window_seconds":2592000,"used_percent":0,"reset_at":1800500000},"secondary_window":null},"additional_rate_limits":null}"#.utf8)
        let transport = QuotaTestTransport(data: body)
        do {
            _ = try await service(setup, transport: transport).update(setup.account)
            XCTFail("30天不能冒充周或5小时成功")
        } catch { XCTAssertEqual(error as? CodexQuotaError, .failed) }
        let saved = try await setup.store.load()
        XCTAssertEqual(saved, [setup.account])
        XCTAssertNil(saved.first?.quotaSnapshot)
        print("T12 | 真实结构回归（脱敏固定输入） | 2592000秒/已用0；不改名为周或5小时，不生成成功快照")
    }

    func testCredentialMismatchAndMissingCredentialNeverQuery() async throws {
        let setup = try await self.setup()
        for payload in [Optional<CredentialPayload>.none, try payload(for: ConnectedAccount(remoteUserID: "other", scope: setup.account.scope, credentialRef: UUID()))] {
            let transport = QuotaTestTransport(data: Self.complete)
            let service = CodexQuotaService(store: setup.store, loadCredential: { _ in payload }, transport: transport,
                                           checkNetwork: { .allowed(score: 51) }, now: { [time] in time })
            do { _ = try await service.update(setup.account); XCTFail("不匹配授权不得查询") } catch { }
            let count = await transport.requests.count
            XCTAssertEqual(count, 0)
        }
    }

    func testCancellationAfterResponseCannotPublish() async throws {
        let setup = try await self.setup()
        let gate = QuotaTestGate()
        let transport = QuotaTestTransport(data: Self.complete, beforeResponse: { await gate.wait() })
        let work = Task { try await service(setup, transport: transport).update(setup.account) }
        while await transport.requests.isEmpty { await Task.yield() }
        work.cancel()
        await gate.open()
        do { _ = try await work.value; XCTFail("取消不得发布") } catch { XCTAssertTrue(error is CancellationError) }
        let saved = try await setup.store.load()
        XCTAssertEqual(saved, [setup.account])
    }

    func testChangedBindingDuringRequestRejectsLateSnapshot() async throws {
        let setup = try await self.setup()
        let gate = QuotaTestGate()
        let transport = QuotaTestTransport(data: Self.complete, beforeResponse: { await gate.wait() })
        let work = Task { try await service(setup, transport: transport).update(setup.account) }
        while await transport.requests.isEmpty { await Task.yield() }
        var replacement = setup.account
        replacement.generation += 1
        replacement.credentialRef = UUID()
        try await setup.store.update(replacement)
        await gate.open()
        do { _ = try await work.value; XCTFail("旧请求不得覆盖新绑定") } catch { }
        let saved = try await setup.store.load()
        XCTAssertEqual(saved, [replacement])
    }

    func testFailedDiskCommitDoesNotPublishSuccess() async throws {
        let setup = try await self.setup()
        let backup = setup.url.deletingLastPathComponent().appendingPathComponent("backup.json")
        let transport = QuotaTestTransport(data: Self.complete, beforeResponse: {
            try! FileManager.default.moveItem(at: setup.url, to: backup)
            try! FileManager.default.createDirectory(at: setup.url, withIntermediateDirectories: false)
        })
        do { _ = try await service(setup, transport: transport).update(setup.account); XCTFail("保存失败不得返回成功") } catch { }
        let original = try await AccountStore(fileURL: backup).load()
        XCTAssertEqual(original, [setup.account])
    }

    func testPreT12AccountFileRemainsReadable() async throws {
        let setup = try await self.setup()
        let text = try String(contentsOf: setup.url, encoding: .utf8)
        XCTAssertFalse(text.contains("quotaSnapshot"))
        let reopened = try await AccountStore(fileURL: setup.url).load()
        XCTAssertEqual(reopened.first?.quotaState, .notFetched)
        XCTAssertNil(reopened.first?.quotaSnapshot)
    }

    func testLoginCompletionAutomaticallyQueriesAfterBindingAndDismissal() async throws {
        let setup = try await self.setup(save: false)
        let transport = QuotaTestTransport(data: Self.complete)
        let binding = QuotaTestBinding(account: setup.account, store: setup.store)
        let login = QuotaTestLogin(account: setup.account, payload: try payload(for: setup.account))
        let flow = CodexConnectionFlow(checkNetwork: { .allowed(score: 51) }, authorizer: login,
            transactions: QuotaTestTransactions(), completer: login, verifier: login, bindings: binding,
            pending: QuotaTestPending(), quotaUpdater: try service(setup, transport: transport), copyCode: { _, _ in }, openURL: { _ in true })
        let finished = expectation(description: "额度自动出现")
        let observation = flow.$accounts.sink { if $0.first?.quotaState == .available { finished.fulfill() } }
        try await XCTUnwrap(flow.begin()).value
        await fulfillment(of: [finished], timeout: 5)
        observation.cancel()
        XCTAssertFalse(flow.isPresented)
        XCTAssertEqual(flow.accounts.first?.quotaSnapshot?.weekly.amount.remainingPercent, 70)
        XCTAssertEqual(flow.accounts.first?.quotaSnapshot?.fiveHours.amount.remainingPercent, 20)
        flow.cancel() // Mirrors sheet onDismiss: it must not undo quota or binding.
        let saved = try await setup.store.load()
        XCTAssertEqual(saved, flow.accounts)
        print("T12 | 登录后自动查询 | 无刷新操作，绑定完成后自动显示70%/20%，关闭登录弹层不撤销结果")
    }

    func testLoginGatePassesButQuotaGate50KeepsSuccessfulAccountWithSimpleMessage() async throws {
        let setup = try await self.setup(save: false)
        let transport = QuotaTestTransport(data: Self.complete)
        let login = QuotaTestLogin(account: setup.account, payload: try payload(for: setup.account))
        let flow = CodexConnectionFlow(checkNetwork: { .allowed(score: 51) }, authorizer: login,
            transactions: QuotaTestTransactions(), completer: login, verifier: login,
            bindings: QuotaTestBinding(account: setup.account, store: setup.store), pending: QuotaTestPending(),
            quotaUpdater: try service(setup, transport: transport, gate: { .blocked(score: 50) }),
            copyCode: { _, _ in }, openURL: { _ in true })
        let finished = expectation(description: "查询前门控阻止")
        let observation = flow.$quotaFailure.sink { if $0 != nil { finished.fulfill() } }
        try await XCTUnwrap(flow.begin()).value
        await fulfillment(of: [finished], timeout: 5)
        observation.cancel()
        XCTAssertEqual(flow.quotaFailure, "网络不达标，无法更新")
        XCTAssertFalse(flow.isPresented)
        XCTAssertEqual(flow.accounts, [setup.account])
        let saved = try await setup.store.load()
        let count = await transport.requests.count
        XCTAssertEqual(saved, [setup.account])
        XCTAssertEqual(count, 0)
        print("T12 | 新增前51、实际查询前50 | 绑定成功保留，请求0次，显示网络不达标，无法更新")
    }

    func testExistingNotFetchedBindingQueriesOnceButSavedSnapshotDoesNotStartNewQuery() async throws {
        let setup = try await self.setup()
        let transport = QuotaTestTransport(data: Self.complete)
        let binding = QuotaTestBinding(account: setup.account, store: setup.store)
        let updater = try service(setup, transport: transport)
        let flow = CodexConnectionFlow(transactions: QuotaTestTransactions(), bindings: binding, quotaUpdater: updater)
        await flow.loadAccounts()
        await flow.waitForInitialQuota()
        await flow.loadAccounts()
        let reopenedFlow = CodexConnectionFlow(transactions: QuotaTestTransactions(), bindings: binding, quotaUpdater: updater)
        await reopenedFlow.loadAccounts()
        await reopenedFlow.waitForInitialQuota()
        let count = await transport.requests.count
        XCTAssertEqual(count, 1, "首次查询兼容已有绑定；不提前实现每次前台刷新")
        XCTAssertEqual(reopenedFlow.accounts, flow.accounts)
    }

    func testSavedSnapshotCannotBelongToAnotherScopeOrBeEntirelyUnknown() async throws {
        let setup = try await self.setup()
        var other = setup.account
        other.scope = .init(remoteAccountID: "other", kind: .personal)
        for snapshot in [try CodexUsageParser().parse(Data("{}".utf8), for: setup.account, observedAt: time),
                         try CodexUsageParser().parse(Data(#"{"rate_limit":{"primary_window":{"limit_window_seconds":18000,"used_percent":20}}}"#.utf8), for: other, observedAt: time)] {
            do { _ = try await setup.store.saveQuota(snapshot, for: setup.account); XCTFail("不得保存假成功或错账户") }
            catch { XCTAssertEqual(error as? AccountStore.StoreError, .invalidQuotaSnapshot) }
        }
        let saved = try await setup.store.load()
        XCTAssertEqual(saved, [setup.account])
    }

    func testFreeThirtyDayResponseSavesSubscriptionWithoutQuotaOrFailureAndReopens() async throws {
        let setup = try await self.setup()
        let transport = QuotaTestTransport(data: Self.free)
        let binding = QuotaTestBinding(account: setup.account, store: setup.store)
        let updater = try service(setup, transport: transport)
        let flow = CodexConnectionFlow(transactions: QuotaTestTransactions(), bindings: binding, quotaUpdater: updater)
        await flow.loadAccounts()
        await flow.waitForInitialQuota()
        let account = try XCTUnwrap(flow.accounts.first)
        XCTAssertEqual(account.subscription, AccountSubscription(planType: "Free", observedAt: time))
        XCTAssertEqual(account.quotaState, .notApplicable)
        XCTAssertNil(account.quotaSnapshot)
        XCTAssertNil(flow.quotaFailure)
        let reopened = CodexConnectionFlow(transactions: QuotaTestTransactions(), bindings: binding, quotaUpdater: updater)
        await reopened.loadAccounts()
        await reopened.waitForInitialQuota()
        XCTAssertEqual(reopened.accounts, [account])
        XCTAssertNil(reopened.quotaFailure)
        let count = await transport.requests.count
        XCTAssertEqual(count, 1)
        print("T12 | Free真实结构固定输入 | 独立保存Free，无适用额度正常成功，重开一致，无额度快照和失败")
    }

    func testNewPlanNameAndCaseArePreservedWithoutWhitelist() async throws {
        for name in ["Next Plan 2030", "free", "Free"] {
            let setup = try await self.setup()
            let data = Data(String(decoding: Self.complete, as: UTF8.self).replacingOccurrences(of: "plus", with: name).utf8)
            let updated = try await service(setup, transport: QuotaTestTransport(data: data)).update(setup.account)
            XCTAssertEqual(updated.subscription?.planType, name)
            XCTAssertEqual(updated.quotaState, .available, "有真实支持窗口时Free也显示额度，不能仅靠套餐跳过")
        }
    }

    func testExplicitNullWindowsForFreeAreNormalButMissingOrMalformedAreNot() async throws {
        let setup = try await self.setup()
        let data = Data(#"{"account_id":"quota-test-account","plan_type":"free","rate_limit":{"primary_window":null,"secondary_window":null}}"#.utf8)
        let updated = try await service(setup, transport: QuotaTestTransport(data: data)).update(setup.account)
        XCTAssertEqual(updated.quotaState, .notApplicable)
        XCTAssertEqual(updated.subscription?.planType, "free")
        for rate in ["null", "{}", #"{"primary_window":null}"#, #"{"primary_window":{},"secondary_window":null}"#,
                     #"{"primary_window":{"limit_window_seconds":2592000,"used_percent":101},"secondary_window":null}"#,
                     #"{"primary_window":{"limit_window_seconds":18000},"secondary_window":null}"#] {
            let setup = try await self.setup()
            let body = Data((#"{"account_id":"quota-test-account","plan_type":"Free","rate_limit":REPLACE}"#).replacingOccurrences(of: "REPLACE", with: rate).utf8)
            do { _ = try await service(setup, transport: QuotaTestTransport(data: body)).update(setup.account); XCTFail("不能把坏响应默认无额度") }
            catch { XCTAssertEqual(error as? CodexQuotaError, .failed) }
            let saved = try await setup.store.load()
            XCTAssertEqual(saved.first?.subscription?.planType, "Free")
            XCTAssertEqual(saved.first?.quotaState, .notFetched)
        }
    }

    func testMissingEmptyOrInvalidPlanDoesNotBecomeFree() async throws {
        for plan in ["null", "123", #""""#, #""   ""#, #""bad\nname""#] {
            let setup = try await self.setup()
            let data = Data(String(decoding: Self.free, as: UTF8.self).replacingOccurrences(of: #""Free""#, with: plan).utf8)
            do { _ = try await service(setup, transport: QuotaTestTransport(data: data)).update(setup.account); XCTFail("无可靠套餐必须失败") }
            catch { XCTAssertEqual(error as? CodexQuotaError, .failed) }
            let saved = try await setup.store.load()
            XCTAssertEqual(saved, [setup.account])
        }
    }

    func testPlanSurvivesMalformedQuotaAndFlowReportsFirstFetchFailure() async throws {
        let setup = try await self.setup()
        let data = Data(#"{"account_id":"quota-test-account","plan_type":"New Official Plan","rate_limit":"malformed"}"#.utf8)
        let flow = CodexConnectionFlow(transactions: QuotaTestTransactions(),
            bindings: QuotaTestBinding(account: setup.account, store: setup.store),
            quotaUpdater: try service(setup, transport: QuotaTestTransport(data: data)))
        await flow.loadAccounts()
        await flow.waitForInitialQuota()
        XCTAssertEqual(flow.accounts.first?.subscription?.planType, "New Official Plan")
        XCTAssertEqual(flow.quotaFailure, "获取失败")
        XCTAssertNil(flow.accounts.first?.quotaSnapshot)
        let saved = try await setup.store.load()
        XCTAssertEqual(saved, flow.accounts)
    }

    func testSamePlanQuotaFailureUpdatesOnlySubscriptionTimeAndNewPlanClearsOldQuota() async throws {
        let setup = try await self.setup()
        let old = try await service(setup, transport: QuotaTestTransport(data: Self.complete)).update(setup.account)
        let later = time.addingTimeInterval(100)
        for plan in ["plus", "Future Plan"] {
            let body = Data((#"{"account_id":"quota-test-account","plan_type":"PLAN","rate_limit":{}}"#).replacingOccurrences(of: "PLAN", with: plan).utf8)
            do { _ = try await service(setup, transport: QuotaTestTransport(data: body), now: { later }).update(old); XCTFail("套餐成功不能冒充额度成功") }
            catch { XCTAssertEqual(error as? CodexQuotaError, .failed) }
            let records = try await setup.store.load()
            let saved = try XCTUnwrap(records.first)
            XCTAssertEqual(saved.subscription?.observedAt, later)
            XCTAssertEqual(saved.subscription?.planType, plan)
            if plan == "plus" { XCTAssertEqual(saved.quotaSnapshot, old.quotaSnapshot) }
            else { XCTAssertNil(saved.quotaSnapshot); XCTAssertEqual(saved.quotaState, .notFetched) }
        }
    }

    func testDowngradeToFreeClearsOldQuotaAndLaterSupportedQuotaIsQueried() async throws {
        let setup = try await self.setup()
        let old = try await service(setup, transport: QuotaTestTransport(data: Self.complete)).update(setup.account)
        let free = try await service(setup, transport: QuotaTestTransport(data: Self.free)).update(old)
        XCTAssertNil(free.quotaSnapshot)
        XCTAssertEqual(free.quotaState, .notApplicable)
        let upgraded = try await service(setup, transport: QuotaTestTransport(data: Self.complete)).update(free)
        XCTAssertEqual(upgraded.quotaState, .available)
        XCTAssertEqual(upgraded.subscription?.planType, "plus")
    }

    func testLegacySnapshotAutomaticallyFetchesMissingSubscription() async throws {
        let setup = try await self.setup()
        let snapshot = try CodexUsageParser().parse(Self.complete, for: setup.account, observedAt: time)
        _ = try await setup.store.saveQuota(snapshot, for: setup.account)
        let transport = QuotaTestTransport(data: Self.free)
        let flow = CodexConnectionFlow(transactions: QuotaTestTransactions(),
            bindings: QuotaTestBinding(account: setup.account, store: setup.store),
            quotaUpdater: try service(setup, transport: transport))
        await flow.loadAccounts()
        await flow.waitForInitialQuota()
        XCTAssertEqual(flow.accounts.first?.subscription?.planType, "Free")
        XCTAssertEqual(flow.accounts.first?.quotaState, .notApplicable)
        XCTAssertNil(flow.quotaFailure)
    }

    func testOlderSubscriptionResponseCannotOverwriteNewerObservation() async throws {
        let setup = try await self.setup()
        let later = time.addingTimeInterval(100)
        let newer = try await service(setup, transport: QuotaTestTransport(data: Self.free), now: { later }).update(setup.account)
        do { _ = try await service(setup, transport: QuotaTestTransport(data: Self.complete)).update(setup.account); XCTFail("旧响应不得覆盖新套餐") }
        catch { XCTAssertEqual(error as? CodexQuotaError, .failed) }
        let saved = try await setup.store.load()
        XCTAssertEqual(saved, [newer])
    }

    private static let free = Data(#"{"account_id":"quota-test-account","plan_type":"Free","rate_limit":{"primary_window":{"limit_window_seconds":2592000,"used_percent":0,"reset_at":1800500000},"secondary_window":null}}"#.utf8)

    private typealias Setup = (store: AccountStore, account: ConnectedAccount, url: URL)
    private func setup(save: Bool = true) async throws -> Setup {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T12-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directories.append(directory)
        let url = directory.appendingPathComponent("accounts.json")
        let store = AccountStore(fileURL: url)
        let account = ConnectedAccount(remoteUserID: "quota-test-user", verifiedEmail: "quota@example.invalid",
                                       scope: .init(remoteAccountID: "quota-test-account", kind: .personal), credentialRef: UUID())
        if save { try await store.append(account) }
        return (store, account, url)
    }
    private func payload(for account: ConnectedAccount) throws -> CredentialPayload {
        let tokens = CodexTokenResponse(accessToken: "quota-test-access", refreshToken: "quota-test-refresh",
            idToken: "quota-test-id", obtainedAt: time.addingTimeInterval(-100), expiresAt: nil)
        let package = CodexIdentityVerifier.CredentialPackage(credentialVersion: 1, issuer: CodexIdentityVerifier.issuer,
            clientID: CodexDeviceAuthorization.clientID, subject: "test-subject", remoteUserID: account.remoteUserID!,
            scope: account.scope, tokens: tokens)
        return .init(data: try JSONEncoder().encode(package))
    }
    private func service(_ setup: Setup, transport: any CodexDeviceAuthorizationTransport,
                         gate: @escaping @Sendable () async -> NetworkScoreResult = { .allowed(score: 51) },
                         now: (@Sendable () -> Date)? = nil) throws -> CodexQuotaService {
        let payload = try payload(for: setup.account)
        return CodexQuotaService(store: setup.store, loadCredential: { _ in payload }, transport: transport,
                                checkNetwork: gate, now: now ?? { [time] in time })
    }
    private static let complete = Data(#"{"account_id":"quota-test-account","plan_type":"plus","rate_limit":{"primary_window":{"limit_window_seconds":18000,"used_percent":80,"reset_at":1800010000},"secondary_window":{"limit_window_seconds":604800,"used_percent":30,"reset_at":1800500000}}}"#.utf8)
}

private actor QuotaTestTransport: CodexDeviceAuthorizationTransport {
    let body: Data
    let status: Int
    let mime: String
    let beforeResponse: @Sendable () async -> Void
    private(set) var requests: [URLRequest] = []
    init(data: Data, status: Int = 200, mime: String = "application/json", beforeResponse: @escaping @Sendable () async -> Void = {}) {
        body = data; self.status = status; self.mime = mime; self.beforeResponse = beforeResponse
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        await beforeResponse()
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": mime])!)
    }
}
private final class QuotaTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    func get() -> Date { lock.withLock { date } }
    func set(_ date: Date) { lock.withLock { self.date = date } }
}
private actor QuotaTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var ready = false
    func wait() async { if !ready { await withCheckedContinuation { continuation = $0 } } }
    func open() { ready = true; continuation?.resume(); continuation = nil }
}
private actor QuotaTestBinding: CodexAccountBinding {
    let account: ConnectedAccount
    let store: AccountStore
    init(account: ConnectedAccount, store: AccountStore) { self.account = account; self.store = store }
    func load() async throws -> [ConnectedAccount] { try await store.load() }
    func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount {
        try await store.appendFirstUnlessCancelled(account)
        return account
    }
}
private struct QuotaTestLogin: CodexDeviceAuthorizing, CodexLoginCompleting, CodexIdentityVerifying {
    let account: ConnectedAccount
    let payload: CredentialPayload
    func requestAuthorization() throws -> CodexDeviceAuthorization {
        try .init(deviceAuthID: "t12-device", userCode: "TEST-CODE", pollInterval: 1, startedAt: Date())
    }
    func poll(_ authorization: CodexDeviceAuthorization) -> CodexAuthorizationCode? {
        .init(code: "test-code", verifier: String(repeating: "a", count: 43))
    }
    func exchange(_ code: CodexAuthorizationCode) -> CodexTokenResponse {
        .init(accessToken: "test-access", refreshToken: "test-refresh", idToken: "test-id", obtainedAt: Date(), expiresAt: nil)
    }
    func verify(_ tokens: CodexTokenResponse) -> CodexVerifiedLogin {
        .fixture(remoteUserID: account.remoteUserID!, email: account.verifiedEmail!, scope: account.scope, credentials: payload)
    }
}
private actor QuotaTestTransactions: CodexLoginTransactionStoring {
    func save(_ authorization: CodexDeviceAuthorization) { }
    func remove(transactionID: UUID) { }
}
private actor QuotaTestPending: CodexPendingLoginStoring {
    func saveCode(_ code: CodexAuthorizationCode, transactionID: UUID) { }
    func saveTokens(_ tokens: CodexTokenResponse, transactionID: UUID) { }
    func remove(transactionID: UUID) { }
}
