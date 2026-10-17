import XCTest
import Security
@testable import SubscriptionUsage

/// T94: Cursor in every existing refresh path and in the widget account choice,
/// mixed with Codex. Isolated store, Keychain service and fake network only.
@MainActor
final class CursorRefreshTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_791_590_400)

    /// Codex double: records calls and fails or succeeds on demand.
    actor CodexDouble: CodexQuotaUpdating {
        var fail = true
        private(set) var calls: [UUID] = []
        func setFail(_ value: Bool) { fail = value }
        func update(_ account: ConnectedAccount) async throws -> ConnectedAccount {
            calls.append(account.id)
            if fail { throw CodexQuotaError.failed }
            return account
        }
    }

    private struct Setup {
        let store: AccountStore
        let flow: CodexConnectionFlow
        let codex: CodexDouble
        let cursorTransport: CursorFakeTransport
        let codexAccount: ConnectedAccount
        let cursorAccount: ConnectedAccount
    }

    private func setup(cursorUsed: Double = 40, network: NetworkScoreResult = .allowed(score: 80)) async throws -> Setup {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T94-\(UUID().uuidString)")
        let service = "com.iceflying.SubscriptionUsage.tests.T94.\(UUID().uuidString)"
        let vault = CredentialVault(service: service)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            for namespace in ["credentials", "login-transactions"] {
                SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: "\(service).\(namespace)"] as CFDictionary)
            }
        }
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let codexAccount = ConnectedAccount(remoteUserID: "u-a", verifiedEmail: "a@example.invalid",
            scope: .init(remoteAccountID: "acct-a", kind: .personal), credentialRef: UUID())
        let cursorAccount = ConnectedAccount(provider: .cursor, product: .cursorSubscription, remoteUserID: "google-oauth2|user_1",
            verifiedEmail: "cursor@example.invalid", scope: .init(remoteAccountID: "google-oauth2|user_1", kind: .personal),
            credentialRef: UUID())
        try await store.append(codexAccount)
        try await store.append(cursorAccount)
        try await vault.save(try CursorCredential(accessToken: CursorConnectionTests.token(), refreshToken: "r").payload,
                             for: .credential(cursorAccount.credentialRef))
        let codex = CodexDouble()
        let transport = CursorFakeTransport(me: CursorConnectionTests.me(), usage: CursorConnectionTests.usage(used: cursorUsed))
        let updater = CoordinatedQuotaUpdater(store: store, service: codex,
            cursorService: CursorQuotaService(store: store, loadCredential: { try await vault.load(for: .credential($0)) },
                transport: transport, checkNetwork: { network }, now: { [time] in time }))
        let flow = CodexConnectionFlow(transactions: CodexLoginTransactionStore(vault: vault),
            bindings: CodexAccountBindingStore(accountStore: store, vault: vault), quotaUpdater: updater,
            foregroundRefreshEnabled: false, now: { [time] in time })
        await flow.loadAccounts()
        await flow.waitForInitialQuota()
        return Setup(store: store, flow: flow, codex: codex, cursorTransport: transport,
                     codexAccount: codexAccount, cursorAccount: cursorAccount)
    }

    func testT94MixedRefreshIsIndependentPerPlatform() async throws {
        let s = try await setup()
        // Cold load already queried both: Codex failed, Cursor succeeded.
        var cursor = try XCTUnwrap(s.flow.accounts.first { $0.id == s.cursorAccount.id })
        XCTAssertEqual(cursor.quotaState, .available)
        XCTAssertEqual(cursor.quotaSnapshot?.weekly.amount.remainingPercent, 60)
        XCTAssertNotNil(s.flow.quotaFailures[s.codexAccount.id]); XCTAssertNil(s.flow.quotaFailures[s.cursorAccount.id])

        // Pull to refresh all: each platform its own service; one failure does not touch the other.
        await s.cursorTransport.setUsage(CursorConnectionTests.usage(used: 55))
        let codexCallsBefore = await s.codex.calls.count
        s.flow.refreshAllQuota()
        XCTAssertEqual(s.flow.quotaUpdatingIDs, [s.codexAccount.id, s.cursorAccount.id], "两张卡各自转圈")
        await s.flow.waitForInitialQuota()
        let codexCalls = await s.codex.calls.count
        XCTAssertEqual(codexCalls, codexCallsBefore + 1, "Codex只走Codex查询")
        cursor = try XCTUnwrap(s.flow.accounts.first { $0.id == s.cursorAccount.id })
        XCTAssertEqual(cursor.quotaSnapshot?.weekly.amount.remainingPercent, 45)
        XCTAssertEqual(s.flow.quotaFailure, "刷新失败"); XCTAssertEqual(s.flow.quotaFailureID, s.codexAccount.id)
        let cursorRequests = await s.cursorTransport.requests.map(\.url)
        XCTAssertEqual(cursorRequests.filter { $0 == CursorAPIClient.usageURL }.count, 2, "Cursor只走cursor.com")

        // Retry keeps the original scope (both accounts) and now both succeed.
        await s.codex.setFail(false)
        s.flow.retryDashboardQuota(for: s.codexAccount.id)
        XCTAssertEqual(s.flow.quotaUpdatingIDs, [s.codexAccount.id, s.cursorAccount.id], "按原范围重试")
        await s.flow.waitForInitialQuota()
        XCTAssertNil(s.flow.quotaFailure)

        // Single-card menu refresh touches only that card.
        let before = await s.codex.calls.count
        s.flow.refreshQuota(for: s.cursorAccount.id)
        XCTAssertEqual(s.flow.quotaUpdatingIDs, [s.cursorAccount.id])
        await s.flow.waitForInitialQuota()
        let after = await s.codex.calls.count
        XCTAssertEqual(after, before)
        print("T94 | 混合刷新 | 冷启动/下拉全部/按原范围重试/单卡刷新：两平台各走各的查询，Codex失败不影响Cursor | passed")
    }

    func testT94CursorFailureKeepsOldValueAndCodexStillUpdates() async throws {
        let s = try await setup()
        await s.codex.setFail(false)
        let old = try XCTUnwrap(s.flow.accounts.first { $0.id == s.cursorAccount.id }?.quotaSnapshot)
        await s.cursorTransport.setUsageStatus(500)
        s.flow.refreshAllQuota()
        await s.flow.waitForInitialQuota()
        let cursor = try XCTUnwrap(s.flow.accounts.first { $0.id == s.cursorAccount.id })
        XCTAssertEqual(cursor.quotaSnapshot, old, "保留可信旧值与原成功时间")
        XCTAssertEqual(s.flow.quotaFailureID, s.cursorAccount.id); XCTAssertEqual(s.flow.quotaFailure, "刷新失败")
        XCTAssertNil(s.flow.quotaFailures[s.codexAccount.id])
        let saved = try await s.store.load()
        let projected = WidgetSnapshot.projecting(saved, failures: [s.cursorAccount.id: .refresh])
        let input = QuotaStyledInput(account: projected.allAccounts.first { $0.id == s.cursorAccount.id })
        XCTAssertEqual(input.windows.first?.amount.nativeText, "60%"); XCTAssertEqual(input.message, "刷新失败")
        print("T94 | Cursor失败 | 保留本月60%与原时间，提示“刷新失败”；Codex照常成功 | passed")
    }

    func testT94BackgroundPathRefreshesCursorToo() async throws {
        let s = try await setup()
        await s.cursorTransport.setUsage(CursorConnectionTests.usage(used: 10))
        let result = await s.flow.refreshQuotaInBackground()
        XCTAssertTrue(result.loaded); XCTAssertEqual(result.total, 2)
        XCTAssertEqual(result.failed, 1, "仅Codex替身失败")
        let all = try await s.store.load()
        let cursor = try XCTUnwrap(all.first { $0.id == s.cursorAccount.id })
        XCTAssertEqual(cursor.quotaSnapshot?.weekly.amount.remainingPercent, 90)
        print("T94 | 后台入口 | 后台刷新同样更新Cursor（本月剩余90%）；自然调度时间不在隔离测试承诺范围 | passed")
    }

    func testT94WidgetCanSelectCursorAndOpensItsDetail() async throws {
        let s = try await setup()
        let saved = try await s.store.load()
        let snapshot = WidgetSnapshot.projecting(saved)
        // “编辑小组件 → 显示账户” lists both accounts with their platform names.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T94-widget-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let widgetStore = WidgetSnapshotStore(fileURL: directory.appendingPathComponent("widget.json"))
        try widgetStore.write(snapshot)
        let options = try await WidgetAccountQuery(store: widgetStore).suggestedEntities()
        XCTAssertEqual(options.map(\.detail), ["", "Codex", "Cursor"])
        XCTAssertEqual(options.last?.identity, "cursor@example.invalid")
        // Selecting the Cursor entity renders Cursor with one “本月” window.
        let selected = QuotaWidgetContent.snapshot(snapshot).selecting(accountID: s.cursorAccount.id.uuidString)
        let input = QuotaStyledInput(account: selected.account)
        XCTAssertEqual(input.platform, .cursor); XCTAssertEqual(input.windows.map(\.title), ["本月"])
        XCTAssertEqual(input.windows.first?.amount.nativeText, "60%")
        // Tapping the widget opens exactly this account's detail; selection survives reordering.
        XCTAssertEqual(WidgetQuotaRoute(url: selected.destinationURL)?.detailTarget(in: saved)?.id, s.cursorAccount.id)
        let reordered = WidgetSnapshot.projecting(saved.reversed())
        XCTAssertEqual(QuotaWidgetContent.snapshot(reordered).selecting(accountID: s.cursorAccount.id.uuidString).account?.id,
                       s.cursorAccount.id)
        // The widget's own refresh of a selected Cursor account goes to Cursor.
        let selectedAccount = try XCTUnwrap(saved.first { $0.id == s.cursorAccount.id })
        let payload = try CursorCredential(accessToken: CursorConnectionTests.token(), refreshToken: "r").payload
        let updater = CoordinatedQuotaUpdater(store: s.store, service: s.codex,
            cursorService: CursorQuotaService(store: s.store, loadCredential: { [payload] _ in payload },
                transport: s.cursorTransport, checkNetwork: { .allowed(score: 80) }, now: { [time] in time.addingTimeInterval(3600) }),
            opportunistic: true, now: { [time] in time.addingTimeInterval(3600) })
        await s.cursorTransport.setUsage(CursorConnectionTests.usage(used: 70))
        let calls = await s.codex.calls.count
        let refreshed = try await updater.update(selectedAccount)
        XCTAssertEqual(refreshed.quotaSnapshot?.weekly.amount.remainingPercent, 30)
        let callsAfter = await s.codex.calls.count
        XCTAssertEqual(callsAfter, calls)
        print("T94 | 组件 | 显示账户列出Codex/Cursor；选Cursor显示“Cursor·本月”；点击进该账户详情；组件自主刷新走Cursor查询 | passed")
    }
}

