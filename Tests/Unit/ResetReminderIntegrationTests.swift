import SwiftUI
import UIKit
import XCTest
@testable import SubscriptionUsage

/// Hosts the actual RootView while every account, preference and notification
/// dependency remains isolated from the user's data and notification center.
final class ResetReminderIntegrationTests: XCTestCase {
    @MainActor
    func testRootWaitsForSavedAccountsThenReconcilesReminderSwitchChanges() async throws {
        let now = Date(timeIntervalSince1970: 1_791_700_000)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T39-root-\(UUID())")
        let fileURL = directory.appendingPathComponent("accounts.json")
        let store = AccountStore(fileURL: fileURL)
        let account = try makeAccount(now: now)
        try await store.append(account)
        let originalFile = try Data(contentsOf: fileURL)
        defer { try? FileManager.default.removeItem(at: directory) }

        let suite = "T39-root-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        preferences.set(true, forKey: ResetReminderSettings.preferenceKey)
        defer { preferences.removePersistentDomain(forName: suite) }
        let authorization = IntegrationAuthorizationService()
        let reminders = ResetReminderSettings(defaults: preferences, authorizationService: authorization)
        // A previously confirmed permission must not allow the initial empty
        // in-memory list to invalidate notifications before disk restoration.
        await reminders.refreshAuthorization()
        XCTAssertTrue(reminders.isEnabled)

        let bindings = IntegrationAccountBindings(store: store)
        let flow = CodexConnectionFlow(checkNetwork: {
            XCTFail("提醒安排与恢复不能额外查询网络评分")
            return .blocked(score: 0)
        }, transactions: IntegrationTransactions(), bindings: bindings,
           quotaUpdater: IntegrationFailedQuotaUpdater(), foregroundRefreshEnabled: false, now: { now })
        let center = IntegrationNotificationCenter()
        let existing = ResetReminderPlan.requests(accounts: [account], wantsReminders: true,
                                                  authorization: .authorized, now: now)
        XCTAssertEqual(existing.count, 2)
        center.pending = existing
        let scheduler = ResetReminderScheduler(center: center, now: { now })
        let host = UIHostingController(rootView: RootView(connection: flow, preferences: preferences,
            reminders: reminders, reminderScheduler: scheduler))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 414, height: 896)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            bindings.finishLoading()
            window.isHidden = true
            window.rootViewController = nil
        }

        try await eventually("RootView 应开始读取隔离账户文件") { bindings.loadStarted }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertTrue(flow.loadingAccounts)
        XCTAssertTrue(flow.accounts.isEmpty)
        XCTAssertEqual(center.pending, existing, "初次加载不能被当成用户已删除全部账户")
        XCTAssertTrue(center.removedIdentifiers.isEmpty)
        XCTAssertTrue(center.added.isEmpty)

        bindings.finishLoading()
        try await eventually("账户读取与权限确认后应自动核对两个重置提醒") {
            flow.accounts == [account] && scheduler.lastResult?.accepted.count == 2
        }
        XCTAssertEqual(center.pending, existing)
        XCTAssertTrue(center.removedIdentifiers.isEmpty)
        XCTAssertTrue(center.added.isEmpty, "已存在的本轮提醒无须重复提交")
        XCTAssertGreaterThanOrEqual(center.readCount, 2)
        XCTAssertFalse(flow.accountLoadFailed)

        await reminders.setEnabled(false)
        try await eventually("关闭全局开关应通过 RootView 接线清理待发提醒") {
            center.pending.isEmpty && scheduler.lastResult?.planned.isEmpty == true
        }
        XCTAssertFalse(preferences.bool(forKey: ResetReminderSettings.preferenceKey))
        XCTAssertEqual(Set(center.removedIdentifiers), Set(existing.map(\.identifier)))

        await reminders.setEnabled(true)
        try await eventually("重新开启后应按已保存的可信时间自动恢复两个提醒") {
            center.added.count == 2 && scheduler.lastResult?.accepted.count == 2
        }
        XCTAssertTrue(reminders.isEnabled)
        XCTAssertTrue(preferences.bool(forKey: ResetReminderSettings.preferenceKey))
        XCTAssertEqual(center.pending, existing)
        XCTAssertEqual(authorization.requestCount, 0, "已有权限不能再次申请系统授权")
        XCTAssertEqual(try Data(contentsOf: fileURL), originalFile,
                       "提醒接线不能改写账户额度或原成功时间")
        let restored = try await AccountStore(fileURL: fileURL).load()
        XCTAssertEqual(restored, [account])

        authorization.status = .denied
        await reminders.refreshAuthorization()
        try await eventually("撤权应通过已有接线取消全部未发提醒") { center.pending.isEmpty }
        flow.refreshQuota(for: account.id)
        await flow.waitForInitialQuota()
        XCTAssertNotNil(flow.quotaFailure, "本次查询失败只保留可信旧快照")
        authorization.status = .authorized
        await reminders.refreshAuthorization()
        try await eventually("恢复许可后即使刷新失败，也应按旧有效时间自动重新安排") {
            center.pending.count == 2 && scheduler.lastResult?.accepted.count == 2
        }
        XCTAssertEqual(center.pending, existing)
        XCTAssertEqual(flow.accounts, [account])
        XCTAssertEqual(try Data(contentsOf: fileURL), originalFile)
        XCTAssertEqual(authorization.requestCount, 0)
        authorization.status = .denied
        await reminders.refreshAuthorization()
        try await eventually("再次撤权取消待发") { center.pending.isEmpty }
        print("T40 TABLE | A | 周/5小时 | 系统拒绝0→允许2，刷新失败旧值保留→拒绝0 | pending=0")
    }

    @MainActor
    func testT40BackgroundFailureStillReconcilesSavedRemindersWithoutRootView() async throws {
        let now = Date(timeIntervalSince1970: 1_791_700_000)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T40-background-\(UUID())")
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let account = try makeAccount(now: now)
        try await store.append(account)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bindings = IntegrationAccountBindings(store: store)
        bindings.finishLoading()
        let flow = CodexConnectionFlow(checkNetwork: {
            XCTFail("提醒协调不新增网络检查")
            return .blocked(score: 0)
        }, transactions: IntegrationTransactions(), bindings: bindings,
            quotaUpdater: IntegrationFailedQuotaUpdater(), foregroundRefreshEnabled: false, now: { now })
        let center = IntegrationNotificationCenter()
        let scheduler = ResetReminderScheduler(center: center, now: { now }, currentInput: {
            .init(accounts: try await store.load(), wantsReminders: true, authorization: .authorized)
        })
        var coordinated = 0
        let background = BackgroundQuotaRefresh(flow: flow, journalURL: directory.appendingPathComponent("events.json"),
            enabled: false, now: { now }, reconcileReminders: {
                coordinated += 1
                await scheduler.reconcileSavedInput()
            })
        let result = await background.execute(source: "isolated", wasInBackground: true)
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(coordinated, 1)
        XCTAssertEqual(center.pending.count, 2)
        let saved = try await store.load()
        XCTAssertEqual(saved, [account])
        print("T40 TABLE | A | 周/5小时 | 无前台页面的后台刷新失败，依据可信旧数据恢复 | pending=2")
    }

    @MainActor
    private func eventually(_ message: String, condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail(message)
        throw IntegrationFailure.timedOut
    }

    private func makeAccount(now: Date) throws -> ConnectedAccount {
        var account = ConnectedAccount(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000139")!,
            remoteUserID: "t39-isolated-user", verifiedEmail: "t39-root@example.invalid",
            scope: .init(remoteAccountID: "t39-isolated-scope", kind: .personal),
            credentialRef: UUID(), generation: 3, quotaState: .available)
        let observed = now.addingTimeInterval(-120)
        account.subscription = .init(planType: "plus", observedAt: observed)
        account.quotaSnapshot = .init(accountID: account.id, provider: account.provider,
            product: account.product, scope: account.scope, generation: account.generation,
            planType: "plus", observedAt: observed,
            weekly: .init(window: .weekly, amount: .limited(try .init(used: 20)),
                          resetsAt: now.addingTimeInterval(600), observedAt: observed),
            fiveHours: .init(window: .fiveHours, amount: .limited(try .init(used: 55)),
                             resetsAt: now.addingTimeInterval(300), observedAt: observed))
        return account
    }
}

private enum IntegrationFailure: Error { case timedOut, unexpectedLogin }

@MainActor
private final class IntegrationAuthorizationService: ResetReminderAuthorizationServing {
    private(set) var requestCount = 0
    var status: ResetReminderAuthorizationStatus = .authorized
    func authorizationStatus() async throws -> ResetReminderAuthorizationStatus { status }
    func requestAuthorization() async throws {
        requestCount += 1
        XCTFail("隔离授权服务不应收到系统申请")
    }
}

@MainActor
private final class IntegrationAccountBindings: CodexAccountBinding {
    private let store: AccountStore
    private var mayLoad = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var loadStarted = false

    init(store: AccountStore) { self.store = store }

    func load() async throws -> [ConnectedAccount] {
        loadStarted = true
        if !mayLoad { await withCheckedContinuation { continuation = $0 } }
        return try await store.load()
    }

    func finishLoading() {
        mayLoad = true
        continuation?.resume()
        continuation = nil
    }

    func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount {
        XCTFail("提醒集成测试不应开始登录")
        throw IntegrationFailure.unexpectedLogin
    }
}

private actor IntegrationTransactions: CodexLoginTransactionStoring {
    func save(_ authorization: CodexDeviceAuthorization) { }
    func remove(transactionID: UUID) { }
}

@MainActor
private final class IntegrationNotificationCenter: ResetReminderNotificationCenter {
    var pending: [ResetReminderRequest] = []
    private(set) var readCount = 0
    private(set) var added: [ResetReminderRequest] = []
    private(set) var removedIdentifiers: [String] = []

    func pendingRequests() async -> [ResetReminderRequest] {
        readCount += 1
        return pending
    }

    func add(_ request: ResetReminderRequest) async throws {
        added.append(request)
        pending.removeAll { $0.identifier == request.identifier }
        pending.append(request)
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers += identifiers
        pending.removeAll { identifiers.contains($0.identifier) }
    }
}

private struct IntegrationFailedQuotaUpdater: CodexQuotaUpdating {
    func update(_ account: ConnectedAccount) async throws -> ConnectedAccount { throw CodexQuotaError.failed }
}
