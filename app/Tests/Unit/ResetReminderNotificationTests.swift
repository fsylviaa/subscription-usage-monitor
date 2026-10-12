import Foundation
import UserNotifications
import XCTest
@testable import SubscriptionUsage

/// Default tests only construct/inspect notification objects. The explicit
/// device opt-in below also reads existing requests; no test submits requests.
final class ResetReminderNotificationTests: XCTestCase {
    /// Opt-in, read-only verification of requests already scheduled by ordinary
    /// app usage. Never supplies synthetic data to the system center.
    @MainActor
    func testT39ReadRealPendingRequestsAgainstSavedResetTimes() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("真实待发核对仅在本人iPhone显式启用")
        #else
        guard ProcessInfo.processInfo.environment["T39_LIVE_READBACK"] == "1" else {
            throw XCTSkip("真实待发核对需显式启用；默认不读取正式账户或通知")
        }
        XCTAssertNil(AppBackgroundRuntime.shared.reminderScheduler,
                     "测试宿主不得安排或移除真实提醒")
        let started = Date()
        let preference = (SharedResetReminderRuntime.preferences ?? .standard).bool(forKey: ResetReminderSettings.preferenceKey)
        let authorization = try await SystemResetReminderAuthorizationService().authorizationStatus()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        print("T39 REAL | checked=\(Self.time(started)) | preference=\(preference) | permission=\(authorization) | lockScreen=\(settings.lockScreenSetting.rawValue)")
        XCTAssertTrue(preference, "全局提醒需由用户开启")
        XCTAssertTrue(authorization.permitsReminders, "系统必须实际允许通知")

        // applicationStore.load() also publishes widget state. Decode the
        // existing atomic file in memory to keep this inspection read-only.
        let url = try AccountStore.sharedFileURL()
        let before = try Data(contentsOf: url)
        let document = try JSONDecoder().decode(LiveReminderDocument.self, from: before)
        XCTAssertEqual(document.schemaVersion, 1)
        XCTAssertTrue(Set(document.accounts.map(\.id)).count == document.accounts.count,
                      "账户身份不得重复")
        let expected = ResetReminderPlan.requests(accounts: document.accounts,
            wantsReminders: preference, authorization: authorization, now: started)
        XCTAssertFalse(expected.isEmpty, "至少需要一个真实有效未来重置窗口；没有时不能宣称调度通过")
        let actual = await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(SystemResetReminderNotificationCenter.namespace) }
        let decoded = actual.compactMap(SystemResetReminderNotificationCenter.decode)
        print("T39 REAL | totalAccounts=\(document.accounts.count) | demoAccounts=\(document.accounts.filter(\.isDemo).count) | pendingDeletion=\(document.accounts.filter { $0.deletionPending == true }.count) | realAccounts=\(document.accounts.filter { !$0.isDemo && $0.deletionPending != true }.count) | expected=\(expected.count) | systemPending=\(actual.count) | decoded=\(decoded.count)")
        XCTAssertEqual(actual.count, expected.count, "实际待发数量应与有效窗口一致")
        XCTAssertEqual(decoded.count, actual.count, "每条实际待发都需有可核对的身份和日历时间")
        XCTAssertTrue(Set(actual.map(\.identifier)) == Set(expected.map(\.identifier)),
                      "系统待发应恰好覆盖当前有效账户及窗口")
        for (index, account) in document.accounts.enumerated() where !account.isDemo {
            let accountExpected = expected.filter { $0.accountID == account.id }
            if accountExpected.isEmpty {
                print("T39 REAL | account=\(index + 1) | applicableFutureWindows=0")
            }
            for planned in accountExpected {
                guard let stored = actual.first(where: { $0.identifier == planned.identifier }),
                      let read = SystemResetReminderNotificationCenter.decode(stored),
                      let trigger = stored.trigger as? UNCalendarNotificationTrigger else {
                    XCTFail("账户\(index + 1)的有效窗口缺少可核对待发请求")
                    continue
                }
                let dateMatches = read.resetsAt.timeIntervalSince1970 == ceil(planned.resetsAt.timeIntervalSince1970)
                let contentMatches = read.title == planned.title && read.body == planned.body
                let identityMatches = read.accountID == planned.accountID && read.window == planned.window
                let nextMatches = trigger.nextTriggerDate() == read.resetsAt
                XCTAssertTrue(dateMatches && contentMatches && identityMatches && nextMatches && !trigger.repeats,
                              "实际身份、文案、未来触发时间须与保存快照一致")
                let window = read.window == .weekly ? "周" : "5小时"
                // Never print the actual email, internal ID, raw content, or quota.
                let safeContent = contentMatches ? "Codex · [账户\(index + 1)] / \(planned.body)" : "内容不匹配"
                print("T39 REAL | account=\(index + 1) | window=\(window) | savedReset=\(Self.time(planned.resetsAt)) | systemTrigger=\(Self.time(read.resetsAt)) | identity=\(identityMatches) | time=\(dateMatches && nextMatches) | content=\(safeContent)")
            }
        }
        let unchanged = before == (try Data(contentsOf: url))
        let preferenceUnchanged = preference == (SharedResetReminderRuntime.preferences ?? .standard).bool(forKey: ResetReminderSettings.preferenceKey)
        let permissionUnchanged = authorization == (try await SystemResetReminderAuthorizationService().authorizationStatus())
        XCTAssertTrue(unchanged, "核对期间成功快照改变时应另次重读，不能沿用混合证据")
        XCTAssertTrue(preferenceUnchanged && permissionUnchanged)
        print("T39 REAL | snapshotUnchanged=\(unchanged) | preferenceUnchanged=\(preferenceUnchanged) | permissionUnchanged=\(permissionUnchanged) | completed=\(Self.time(Date())) | delivery=notObserved")
        #endif
    }

    private struct LiveReminderDocument: Decodable {
        let schemaVersion: Int
        let accounts: [ConnectedAccount]
    }

    private static func time(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        return formatter.string(from: date)
    }

    @MainActor
    func testCalendarRequestUsesExactUTCInstantAndDoesNotRepeat() throws {
        let planned = request(at: 1_800_000_000)
        let native = SystemResetReminderNotificationCenter.makeRequest(planned)
        let trigger = try XCTUnwrap(native.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.timeZone?.secondsFromGMT(), 0)
        XCTAssertEqual(SystemResetReminderNotificationCenter.decode(native), planned)
        XCTAssertNotNil(native.content.sound)
        XCTAssertNil(native.content.badge)
    }

    @MainActor
    func testFractionalResetIsRoundedUpByLessThanOneSecond() throws {
        let planned = request(at: 1_800_000_000.25)
        let actual = try XCTUnwrap(SystemResetReminderNotificationCenter.decode(
            SystemResetReminderNotificationCenter.makeRequest(planned)))
        XCTAssertEqual(actual.resetsAt.timeIntervalSince1970, 1_800_000_001)
        XCTAssertEqual(actual.identifier, planned.identifier)
    }

    @MainActor
    func testReadbackUsesActualTriggerAndContentInsteadOfIntendedMetadata() throws {
        let planned = request(at: 1_800_000_000)
        let original = SystemResetReminderNotificationCenter.makeRequest(planned)
        let content = try XCTUnwrap(original.content.mutableCopy() as? UNMutableNotificationContent)
        content.body = "实际中心返回的内容"
        content.userInfo["resetsAt"] = planned.resetsAt.timeIntervalSince1970
        let changedTime = SystemResetReminderNotificationCenter.makeRequest(request(at: 1_800_001_000))
        let changed = UNNotificationRequest(identifier: original.identifier, content: content, trigger: changedTime.trigger)
        let result = try XCTUnwrap(SystemResetReminderNotificationCenter.decode(changed))
        XCTAssertEqual(result.resetsAt.timeIntervalSince1970, 1_800_001_000)
        XCTAssertEqual(result.body, content.body)
    }

    @MainActor
    func testUnrelatedMalformedAndRepeatingNotificationsAreNotAcceptedAsQuotaEvidence() throws {
        let native = SystemResetReminderNotificationCenter.makeRequest(request(at: 1_800_000_000))
        XCTAssertNil(SystemResetReminderNotificationCenter.decode(UNNotificationRequest(
            identifier: "another-feature", content: native.content, trigger: native.trigger)))
        XCTAssertNil(SystemResetReminderNotificationCenter.decode(UNNotificationRequest(
            identifier: native.identifier, content: UNMutableNotificationContent(), trigger: native.trigger)))
        let trigger = try XCTUnwrap(native.trigger as? UNCalendarNotificationTrigger)
        XCTAssertNil(SystemResetReminderNotificationCenter.decode(UNNotificationRequest(
            identifier: native.identifier, content: native.content,
            trigger: UNCalendarNotificationTrigger(dateMatching: trigger.dateComponents, repeats: true))))
    }

    func testEveryFixtureAndTestHostDisablesSystemScheduling() {
        XCTAssertFalse(ResetReminderRuntime.permitsSystemScheduling(arguments: [], isTestHost: true))
        for argument in ["--management-ui", "--t23-card-fixture", "--t35-widget-fixture",
                         "--t30-background-debug", "--t09-live-ui", "--t39-any-future-fixture"] {
            XCTAssertFalse(ResetReminderRuntime.permitsSystemScheduling(arguments: [argument], isTestHost: false))
        }
        XCTAssertTrue(ResetReminderRuntime.permitsSystemScheduling(arguments: ["SubscriptionUsage"], isTestHost: false))
    }

    private func request(at seconds: TimeInterval) -> ResetReminderRequest {
        ResetReminderRequest(identifier: "quota-reset.v1.unit-test", accountID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            window: .weekly, resetsAt: Date(timeIntervalSince1970: seconds),
            title: "Codex · first@example.invalid", body: "周额度预计重置，打开查看")
    }
}


final class ResetReminderNavigationTests: XCTestCase {
    @MainActor
    func testActualPlannerAndSystemAdapterProduceCompatibleTargetsForBothWindows() async throws {
        let fixture = T26BatchFixture(scenario: "success")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let saved = try await fixture.load()
        let now = try XCTUnwrap(saved.first?.quotaSnapshot?.observedAt).addingTimeInterval(1)
        let planned = ResetReminderPlan.requests(accounts: saved, wantsReminders: true,
            authorization: .authorized, now: now)
        XCTAssertEqual(planned.count, 4)
        for request in planned {
            let native = SystemResetReminderNotificationCenter.makeRequest(request)
            let target = try XCTUnwrap(ResetReminderTarget(request: native))
            XCTAssertEqual(target.accountID, request.accountID)
            XCTAssertEqual(target.window, request.window)
            XCTAssertEqual(target.resetsAt, request.resetsAt)
            XCTAssertEqual(target.detailTarget(in: Array(saved.reversed()))?.id, request.accountID)
        }
    }

    @MainActor
    func testV1DeliveredWindowTargetsResolveEvenAfterResetAndReordering() throws {
        let a = account(), b = account()
        for window in [QuotaWindow.weekly, .fiveHours] {
            let target = try XCTUnwrap(ResetReminderTarget(request: native(a, window: window)))
            XCTAssertEqual(target.window, window)
            XCTAssertEqual(target.resetsAt, Date(timeIntervalSince1970: 1_700_000_000.25))
            XCTAssertEqual(target.detailTarget(in: [b, a])?.id, a.id)
        }
    }

    @MainActor
    func testSameIdentityReconnectKeepsTargetAndDoesNotRequireQuotaSuccess() throws {
        var a = account()
        let target = try XCTUnwrap(ResetReminderTarget(request: native(a)))
        a.generation += 1; a.credentialRef = UUID(); a.quotaState = .notFetched
        XCTAssertEqual(target.detailTarget(in: [a])?.id, a.id)
        XCTAssertNil(a.quotaSnapshot, "路由不伪造成功值")
    }

    @MainActor
    func testDeletionAndDeletionPendingNeverChooseAnotherAccount() throws {
        var a = account(); let b = account()
        let target = try XCTUnwrap(ResetReminderTarget(request: native(a)))
        XCTAssertNil(target.detailTarget(in: [b]))
        XCTAssertNil(target.detailTarget(in: []))
        a.deletionPending = true
        XCTAssertNil(target.detailTarget(in: [b, a]))
    }

    @MainActor
    func testSameLocalIDWithDifferentUserScopeOrDemoIsRejected() throws {
        let a = account()
        let target = try XCTUnwrap(ResetReminderTarget(request: native(a)))
        var changed = a; changed.remoteUserID = "another-user"
        XCTAssertNil(target.detailTarget(in: [changed]))
        changed = a; changed.scope = .init(remoteAccountID: "other", kind: .personal)
        XCTAssertNil(target.detailTarget(in: [changed]))
        changed = a; changed.scope = .init(remoteAccountID: a.scope.remoteAccountID, kind: .workspace)
        XCTAssertNil(target.detailTarget(in: [changed]))
        changed = a; changed.source = .demo
        XCTAssertNil(target.detailTarget(in: [changed]))
    }

    @MainActor
    func testInvalidIdentityWindowTimeAndMetadataCannotChooseAnAccount() throws {
        let a = account(), window = QuotaWindow.weekly.rawValue
        let request = native(a)
        let prefix = "quota-reset.v1.\(a.id.uuidString.lowercased())."
        let key = ResetReminderPlan.bindingKey(a)
        for suffix in ["x.\(window).1700000000", "\(key).99.1700000000", "\(key).\(window).nan", "\(key).\(window).inf", "\(key).\(window).0", "\(key).\(window).253402300800", "\(key).\(window).1700000000.extra"] {
            XCTAssertNil(ResetReminderTarget(request: UNNotificationRequest(identifier: prefix + suffix,
                content: request.content, trigger: nil)))
        }
        XCTAssertNil(ResetReminderTarget(request: UNNotificationRequest(identifier: "quota-reset.v1.invalid-id.\(key).\(window).1700000000", content: request.content, trigger: nil)))
        let original = native(a)
        let content = try XCTUnwrap(original.content.mutableCopy() as? UNMutableNotificationContent)
        content.userInfo["accountID"] = UUID().uuidString
        XCTAssertNil(ResetReminderTarget(request: UNNotificationRequest(identifier: original.identifier, content: content, trigger: nil)))
        content.userInfo["accountID"] = a.id.uuidString; content.userInfo["window"] = QuotaWindow.fiveHours.rawValue
        XCTAssertNil(ResetReminderTarget(request: UNNotificationRequest(identifier: original.identifier, content: content, trigger: nil)))
    }

    @MainActor
    func testOnlyDefaultOwnedTapProducesEventAndMalformedOwnedTapFallsBack() {
        let request = native(account())
        XCTAssertNotNil(ResetReminderOpenEvent(request: request, actionIdentifier: UNNotificationDefaultActionIdentifier))
        XCTAssertNil(ResetReminderOpenEvent(request: request, actionIdentifier: UNNotificationDismissActionIdentifier))
        XCTAssertNil(ResetReminderOpenEvent(request: request, actionIdentifier: "unhandled-action"))
        let foreign = UNNotificationRequest(identifier: "unrelated", content: request.content, trigger: nil)
        XCTAssertNil(ResetReminderOpenEvent(request: foreign, actionIdentifier: UNNotificationDefaultActionIdentifier))
        let malformed = UNNotificationRequest(identifier: "quota-reset.v1.old", content: request.content, trigger: nil)
        XCTAssertNil(ResetReminderOpenEvent(request: malformed, actionIdentifier: UNNotificationDefaultActionIdentifier)?.target)
        XCTAssertNotNil(ResetReminderOpenEvent(request: malformed, actionIdentifier: UNNotificationDefaultActionIdentifier))
    }

    @MainActor
    func testColdLaunchEventSurvivesAndOldConsumptionCannotEraseNewTap() throws {
        let nav = ResetReminderNavigation()
        let first = try XCTUnwrap(ResetReminderOpenEvent(request: native(account()), actionIdentifier: UNNotificationDefaultActionIdentifier))
        nav.receive(first); XCTAssertEqual(nav.pending, first)
        let next = try XCTUnwrap(ResetReminderOpenEvent(request: native(account()), actionIdentifier: UNNotificationDefaultActionIdentifier))
        nav.receive(next); nav.consume(first.id)
        XCTAssertEqual(nav.pending, next)
        nav.consume(next.id); XCTAssertNil(nav.pending)
    }

    @MainActor
    func testTapResolutionUsesForegroundMergeAndRetainsOldValuesOnFailure() async throws {
        for scenario in ["success", "blocked", "unknown", "slow"] {
            let fixture = T26BatchFixture(scenario: scenario)
            defer { try? FileManager.default.removeItem(at: fixture.directory) }
            let saved = try await fixture.load()
            let flow = CodexConnectionFlow(transactions: T41Transactions(), bindings: fixture, quotaUpdater: fixture)
            let target = try XCTUnwrap(ResetReminderTarget(request: native(saved[1])))
            flow.sceneActivityChanged(true); await flow.loadAccounts()
            for _ in 0..<3 { XCTAssertEqual(target.detailTarget(in: flow.accounts)?.id, saved[1].id) }
            flow.sceneActivityChanged(true)
            if scenario == "slow" { await fixture.release() }
            await flow.waitForInitialQuota()
            XCTAssertTrue(flow.visibleQuotaUpdatingIDs.isEmpty)
            if scenario == "success" || scenario == "slow" {
                let requests = await fixture.requests
                XCTAssertEqual(requests.values.reduce(0, +), 2, "每账户仅查询一次，不新增通知查询")
            } else {
                XCTAssertEqual(flow.accounts, saved)
                XCTAssertEqual(flow.quotaFailure, scenario == "blocked" ? "网络不达标，无法更新" : "刷新失败")
                let requests = await fixture.requests
                XCTAssertTrue(requests.isEmpty, "网络检查失败不请求额度")
            }
        }
    }

    private func account() -> ConnectedAccount {
        ConnectedAccount(remoteUserID: "t41-user-\(UUID())", verifiedEmail: "t41@example.invalid",
            scope: .init(remoteAccountID: "t41-scope-\(UUID())", kind: .personal), credentialRef: UUID())
    }

    @MainActor
    private func native(_ account: ConnectedAccount, window: QuotaWindow = .weekly) -> UNNotificationRequest {
        let seconds = 1_700_000_000.25
        return SystemResetReminderNotificationCenter.makeRequest(.init(
            identifier: "quota-reset.v1.\(account.id.uuidString.lowercased()).\(ResetReminderPlan.bindingKey(account)).\(window.rawValue).\(seconds)",
            accountID: account.id, window: window, resetsAt: Date(timeIntervalSince1970: seconds),
            title: "Codex · 隔离账户", body: "预计重置，打开查看"))
    }
}

private actor T41Transactions: CodexLoginTransactionStoring {
    func save(_ authorization: CodexDeviceAuthorization) { }
    func remove(transactionID: UUID) { }
}
