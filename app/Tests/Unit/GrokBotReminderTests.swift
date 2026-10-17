import XCTest
@testable import SubscriptionUsage

/// T108: Grok Bot reset reminder and the demo Cursor sample (D-80). In-memory
/// notification center and a temporary store only; nothing reaches the system.
@MainActor
final class GrokBotReminderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_700_000)

    private func cursor(id: UUID = UUID(), grokReset: TimeInterval? = 3 * 86400, monthlyReset: TimeInterval = 12 * 86400,
                        grokBot: Bool = true) throws -> ConnectedAccount {
        let scope = AccountScope(remoteAccountID: "user-\(id)", kind: .personal)
        let observed = now.addingTimeInterval(-60)
        var account = ConnectedAccount(id: id, provider: .cursor, product: .cursorSubscription, remoteUserID: "user-\(id)",
            verifiedEmail: "c\(id.uuidString.prefix(4))@example.invalid", scope: scope, credentialRef: UUID(),
            quotaState: .available, subscription: .init(planType: "pro", observedAt: observed))
        account.quotaSnapshot = CodexQuotaSnapshot(accountID: id, provider: .cursor, product: .cursorSubscription, scope: scope,
            generation: 0, planType: "pro", observedAt: observed,
            weekly: .init(window: .monthly, amount: .limited(try .init(used: 20)), resetsAt: now.addingTimeInterval(monthlyReset), observedAt: observed),
            fiveHours: CodexQuotaSnapshot.absentFiveHours(observedAt: observed))
        if grokBot {
            account.grokBot = try .available(used: 75, resetsAt: grokReset.map { now.addingTimeInterval($0) }, observedAt: observed)
        }
        return account
    }

    private func codex() throws -> ConnectedAccount {
        let id = UUID(); let scope = AccountScope(remoteAccountID: "codex-\(id)", kind: .personal)
        var account = ConnectedAccount(id: id, remoteUserID: "codex-user", verifiedEmail: "codex@example.invalid", scope: scope,
            credentialRef: UUID(), quotaState: .available, subscription: .init(planType: "plus", observedAt: now))
        account.quotaSnapshot = CodexQuotaSnapshot(accountID: id, provider: .openAI, product: .codexSubscription, scope: scope,
            generation: 0, planType: "plus", observedAt: now,
            weekly: .init(window: .weekly, amount: .limited(try .init(used: 30)), resetsAt: now.addingTimeInterval(86400), observedAt: now),
            fiveHours: .init(window: .fiveHours, amount: .limited(try .init(used: 60)), resetsAt: now.addingTimeInterval(3600), observedAt: now))
        return account
    }

    func testT108GrokBotReminderPlanned() throws {
        let account = try cursor(), codexAccount = try codex()
        let plan = ResetReminderPlan.requests(accounts: [account, codexAccount], wantsReminders: true, authorization: .authorized, now: now)
        XCTAssertEqual(plan.count, 4, "Cursor本月＋Grok Bot、Codex每周＋5小时")
        let grok = try XCTUnwrap(plan.first { $0.body.hasPrefix("Grok Bot") })
        XCTAssertEqual(grok.body, "Grok Bot 本周额度预计重置，打开查看")
        XCTAssertEqual(grok.title, "Cursor · \(try XCTUnwrap(account.verifiedEmail))")
        XCTAssertEqual(grok.resetsAt, now.addingTimeInterval(3 * 86400)); XCTAssertEqual(grok.accountID, account.id)
        let monthly = try XCTUnwrap(plan.first { $0.accountID == account.id && $0.window == .monthly })
        XCTAssertEqual(monthly.body, "本月额度预计重置，打开查看"); XCTAssertNotEqual(monthly.identifier, grok.identifier)
        XCTAssertEqual(plan.filter { $0.accountID == codexAccount.id }.map(\.body).sorted(),
                       ["5 小时额度预计重置，打开查看", "周额度预计重置，打开查看"])
        // Tapping the notification opens this account, like every other reminder.
        let target = try XCTUnwrap(ResetReminderTarget(request: SystemResetReminderNotificationCenter.makeRequest(grok)))
        XCTAssertEqual(target.detailTarget(in: [account])?.resolve(in: [account])?.id, account.id)
        // No row, no reminder: none / never fetched / past or missing reset / demo / switch off.
        var none = account; none.grokBot = .notApplicable
        var demo = account; demo.source = .demo
        for (name, value) in [("无套餐内额度", none), ("从未取得", try cursor(grokBot: false)),
                              ("无重置时间", try cursor(grokReset: nil)), ("重置已过", try cursor(grokReset: -60)), ("演示", demo)] {
            XCTAssertFalse(ResetReminderPlan.requests(accounts: [value], wantsReminders: true, authorization: .authorized, now: now)
                .contains { $0.body.hasPrefix("Grok Bot") }, name)
        }
        XCTAssertTrue(ResetReminderPlan.requests(accounts: [account], wantsReminders: false, authorization: .authorized, now: now).isEmpty)
        // Monthly unavailable does not drop the Grok Bot reminder.
        var monthlyGone = account; monthlyGone.quotaSnapshot = nil; monthlyGone.quotaState = .notApplicable
        XCTAssertEqual(ResetReminderPlan.requests(accounts: [monthlyGone], wantsReminders: true, authorization: .authorized, now: now).map(\.body),
                       ["Grok Bot 本周额度预计重置，打开查看"])
        print("T108 | 提醒计划 | Grok Bot单独一条“Grok Bot 本周额度”、时间=其重置时间、点通知进对应账户；本月与Codex提醒不变；无额度/未取得/无或过期时间/演示/关闭均不安排 | passed")
    }

    func testT108SchedulerAddsOnceUpdatesAndCancels() async throws {
        let center = GrokReminderCenter()
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })
        let id = UUID()
        let account = try cursor(id: id)
        await scheduler.update(accounts: [account], wantsReminders: true, authorization: .authorized)
        await scheduler.update(accounts: [account], wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(center.added.count, 2, "本月＋Grok Bot各一次，重复刷新不重复")
        XCTAssertEqual(center.pending.filter { $0.body.hasPrefix("Grok Bot") }.count, 1)
        // New reset time: the old one is replaced, never duplicated.
        let moved = try cursor(id: id, grokReset: 4 * 86400)
        await scheduler.update(accounts: [moved], wantsReminders: true, authorization: .authorized)
        let grok = center.pending.filter { $0.body.hasPrefix("Grok Bot") }
        XCTAssertEqual(grok.count, 1); XCTAssertEqual(grok.first?.resetsAt, now.addingTimeInterval(4 * 86400))
        // No longer applicable → cancelled; monthly stays.
        var none = moved; none.grokBot = .notApplicable
        await scheduler.update(accounts: [none], wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(center.pending.map(\.window), [.monthly])
        // Switch off / account deleted → all cancelled.
        await scheduler.update(accounts: [moved], wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(center.pending.count, 2)
        await scheduler.update(accounts: [moved], wantsReminders: false, authorization: .authorized)
        XCTAssertTrue(center.pending.isEmpty)
        await scheduler.update(accounts: [moved], wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(center.pending.count, 2)
        await scheduler.update(accounts: [], wantsReminders: true, authorization: .authorized)
        XCTAssertTrue(center.pending.isEmpty)
        print("T108 | 虚拟通知中心 | 安排、重复刷新不重复、改时间替换、无额度取消、关开关取消、删账户取消 | passed")
    }

    func testT108DemoCursorShowsTwoRows() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("T108-\(UUID().uuidString)/accounts.json")
        let store = AccountStore(fileURL: url)
        let accounts = try await store.setDemoMode(true)
        let sample = try XCTUnwrap(accounts.first { $0.isDemo && $0.platform == .cursor })
        let input = QuotaStyledInput(account: WidgetSnapshot.projecting([sample]).account)
        XCTAssertEqual(input.windows.map(\.title), ["本月", "Grok Bot"])
        let before = try XCTUnwrap(sample.grokBot?.window?.amount.usedPercent)
        let refreshed = try await store.refreshDemo(sample, now: Date().addingTimeInterval(1))
        XCTAssertNotEqual(refreshed.grokBot?.window?.amount.usedPercent, before, "模拟刷新也更新Grok Bot")
        XCTAssertTrue(ResetReminderPlan.requests(accounts: [refreshed], wantsReminders: true, authorization: .authorized, now: Date()).isEmpty,
                      "演示不发真实通知")
        let off = try await store.setDemoMode(false)
        XCTAssertTrue(off.isEmpty, "关闭演示清除示例")
        print("T108 | 演示 | Cursor示例显示本月＋Grok Bot两行，模拟刷新两行都更新，不安排通知，关闭后清除 | passed")
    }
}

@MainActor
private final class GrokReminderCenter: ResetReminderNotificationCenter {
    var pending: [ResetReminderRequest] = []
    private(set) var added: [ResetReminderRequest] = []
    func pendingRequests() async -> [ResetReminderRequest] { pending }
    func add(_ request: ResetReminderRequest) async throws {
        added.append(request)
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }
    func removePendingRequests(withIdentifiers identifiers: [String]) {
        pending.removeAll { identifiers.contains($0.identifier) }
    }
}
