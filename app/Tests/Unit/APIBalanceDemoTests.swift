import XCTest
import Security
@testable import SubscriptionUsage

/// T116: demo balance samples and reset-reminder exclusion (D-82, BAL-10/11).
@MainActor
final class APIBalanceDemoTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_791_590_400)

    private func store() -> AccountStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T116-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
    }

    func testDemoSwitchAddsOneSamplePerBalancePlatformAndClearsThem() async throws {
        let store = store()
        let real = ConnectedAccount(verifiedEmail: "real@example.invalid",
            scope: .init(remoteAccountID: "acc", kind: .personal), credentialRef: UUID())
        try await store.append(real)
        let enabled = try await store.setDemoMode(true)
        XCTAssertEqual(enabled.map(\.platform), [.codex, .cursor, .openRouter, .deepSeek])
        let or = try XCTUnwrap(enabled.first { $0.platform == .openRouter })
        let ds = try XCTUnwrap(enabled.first { $0.platform == .deepSeek })
        XCTAssertTrue(or.isDemo && ds.isDemo)
        XCTAssertTrue(or.identityText.hasPrefix("sk-…"))
        XCTAssertEqual(or.balance?.amounts, [BalanceAmount(currency: "USD", total: Decimal(string: "18.42")!)])
        XCTAssertEqual(ds.balance?.amounts, [BalanceAmount(currency: "CNY", total: Decimal(string: "56.80")!,
                                                          toppedUp: 50, granted: Decimal(string: "6.80")!)])
        let input = QuotaStyledInput(account: WidgetSnapshot.projecting([ds]).account)
        XCTAssertEqual(input.windows.map(\.amount.nativeText), ["¥56.80"])
        let again = try await store.setDemoMode(true)
        XCTAssertEqual(again, enabled, "再次打开不重复追加")

        // Simulated refresh: local only, lowers the amount and moves the time.
        let refreshed = try await store.refreshDemo(or, now: time)
        XCTAssertEqual(refreshed.balance?.amounts.first?.total, Decimal(string: "17.05"))
        XCTAssertEqual(refreshed.balance?.observedAt, time)
        let dsRefreshed = try await store.refreshDemo(ds, now: time)
        XCTAssertEqual(dsRefreshed.balance?.amounts.first?.total, Decimal(string: "55.43"))
        XCTAssertEqual(dsRefreshed.balance?.amounts.first?.granted, Decimal(string: "6.80"))

        // Same ordering and deletion as every other account.
        try await store.reorder([ds.id, real.id, enabled[1].id, or.id])
        _ = try await store.markForDeletion(or.id); try await store.finishDeletion(or.id)
        let afterDelete = try await store.load()
        XCTAssertEqual(afterDelete.map(\.platform), [.deepSeek, .codex, .cursor])
        let off = try await store.setDemoMode(false)
        XCTAssertEqual(off, [real], "关闭演示一并清除")
        print("T116 | 演示示例 | 打开：OpenRouter $18.42、DeepSeek ¥56.80（充值50/赠送6.80）；模拟刷新各减1.37；可排序、删除；关闭全部清除 | passed")
    }

    func testDemoRefreshThroughTheDashboardNeverQueries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T116-flow-\(UUID().uuidString)")
        let service = "com.iceflying.SubscriptionUsage.tests.T116.\(UUID().uuidString)"
        let vault = CredentialVault(service: service)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: "\(service).credentials"] as CFDictionary)
        }
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let transport = BalanceFakeTransport(openRouter: BalanceFakeTransport.openRouter(credits: 1, usage: 0))
        let updater = CoordinatedQuotaUpdater(store: store, service: FailingCodexService(), cursorService: FailingCodexService(),
            balanceService: APIBalanceService(store: store, loadCredential: { try await vault.load(for: .credential($0)) },
                                              transport: transport, checkNetwork: { .allowed(score: 80) }))
        let flow = CodexConnectionFlow(transactions: CodexLoginTransactionStore(vault: vault),
            bindings: CodexAccountBindingStore(accountStore: store, vault: vault), quotaUpdater: updater,
            foregroundRefreshEnabled: false, now: { [time] in time })
        await flow.loadAccounts()
        try await XCTUnwrap(flow.setDemoMode(true)).value
        let or = try XCTUnwrap(flow.accounts.first { $0.platform == .openRouter })
        flow.refreshQuota(for: or.id)
        await flow.waitForInitialQuota()
        XCTAssertEqual(flow.accounts.first { $0.id == or.id }?.balance?.amounts.first?.total, Decimal(string: "17.05"))
        XCTAssertNil(flow.quotaFailures[or.id])
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty, "演示刷新不发真实请求")
    }

    func testBalanceAccountsNeverScheduleResetReminders() throws {
        let codexID = UUID()
        let scope = AccountScope(remoteAccountID: "acc", kind: .personal)
        var codex = ConnectedAccount(id: codexID, remoteUserID: "u", verifiedEmail: "c@example.invalid",
                                     scope: scope, credentialRef: UUID(), quotaState: .available)
        codex.subscription = .init(planType: "Plus", observedAt: time)
        codex.quotaSnapshot = CodexQuotaSnapshot(accountID: codexID, provider: .openAI, product: .codexSubscription,
            scope: scope, generation: 0, planType: "Plus", observedAt: time,
            weekly: .init(window: .weekly, amount: .limited(try .init(used: 30)), resetsAt: time.addingTimeInterval(86400), observedAt: time),
            fiveHours: .init(window: .fiveHours, amount: .limited(try .init(used: 10)), resetsAt: time.addingTimeInterval(3600), observedAt: time))
        let key = APIBalanceStoreTests.key()
        var or = ConnectedAccount(provider: .openRouter, product: .openRouterCredits, remoteUserID: key.fingerprint(for: .openRouter),
            displayName: key.masked, scope: .init(remoteAccountID: key.fingerprint(for: .openRouter), kind: .personal),
            credentialRef: UUID(), quotaState: .available)
        or.balance = APIBalanceStoreTests.usd("3.00", at: time)
        var ds = or
        ds = ConnectedAccount(provider: .deepSeek, product: .deepSeekBalance, remoteUserID: key.fingerprint(for: .deepSeek),
            displayName: key.masked, scope: .init(remoteAccountID: key.fingerprint(for: .deepSeek), kind: .personal),
            credentialRef: UUID(), quotaState: .available)
        ds.balance = APIBalanceSnapshot(amounts: [BalanceAmount(currency: "CNY", total: 0)], observedAt: time)

        let only = ResetReminderPlan.requests(accounts: [codex], wantsReminders: true, authorization: .authorized, now: time)
        let mixed = ResetReminderPlan.requests(accounts: [or, codex, ds], wantsReminders: true, authorization: .authorized, now: time)
        XCTAssertEqual(only.count, 2)
        XCTAssertEqual(mixed, only, "余额账户不产生提醒，原提醒数量与内容不变")
        XCTAssertTrue(ResetReminderPlan.requests(accounts: [or, ds], wantsReminders: true, authorization: .authorized, now: time).isEmpty)
        XCTAssertTrue(ResetReminderPlan.requests(accounts: [or, ds], wantsReminders: false, authorization: .authorized, now: time).isEmpty)
        print("T116 | 重置提醒 | Codex两条提醒不变；加入OpenRouter与DeepSeek后仍为同样两条；只有余额账户时开关开/关都为0条 | passed")
    }
}
