import Foundation
import XCTest
@testable import SubscriptionUsage

/// Only an in-memory notification center receives these synthetic accounts and times.
final class ResetReminderSchedulerTests: XCTestCase {
    @MainActor
    func testUnknownInputSuspendsOldBatchWithoutErasingPreviouslyAcceptedRequests() async throws {
        let accounts = [try account(id: firstID), try account(id: secondID, offset: 60)]
        let center = SchedulerNotificationCenterDouble()
        center.pending = [try XCTUnwrap(plan(accounts).last)]
        center.suspendsNextAdd = true
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })
        let work = Task {
            await scheduler.update(accounts: accounts, wantsReminders: true, authorization: .authorized)
        }
        await center.waitForSuspendedAdd()
        scheduler.suspend()
        center.finishAdd()
        await work.value
        XCTAssertEqual(center.added.count, 1, "未知权限/读取中暂停后不继续旧批次")
        XCTAssertTrue(center.removedIdentifiers.isEmpty, "尚未确认失效的旧提醒不因临时读取而清空")
        XCTAssertNil(scheduler.lastResult, "被暂停的旧批次不产出成功证据")
        await scheduler.update(accounts: accounts, wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(scheduler.lastResult?.accepted.count, 4)
    }

    private let now = Date(timeIntervalSince1970: 1_791_700_000)
    private let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!

    @MainActor
    func testTwoAccountsScheduleFourIndependentRequestsConfirmedByReadback() async throws {
        let accounts = [try account(id: firstID), try account(id: secondID, offset: 60)]
        let center = SchedulerNotificationCenterDouble()
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })

        await scheduler.update(accounts: accounts, wantsReminders: true, authorization: .authorized)

        let result = try XCTUnwrap(scheduler.lastResult)
        XCTAssertEqual(result.planned.count, 4)
        XCTAssertEqual(result.accepted.count, 4)
        XCTAssertEqual(Set(result.accepted.map(\.identifier)).count, 4)
        XCTAssertTrue(result.failedIdentifiers.isEmpty)
        XCTAssertEqual(center.added.count, 4)
        XCTAssertGreaterThanOrEqual(center.readCount, 2, "必须在安排后回读，不能把 add 成功直接当系统接受")
        for account in accounts {
            let snapshot = try XCTUnwrap(account.quotaSnapshot)
            for window in [snapshot.weekly, snapshot.fiveHours] {
                let accepted = try XCTUnwrap(result.accepted.first {
                    $0.accountID == account.id && $0.window == window.window
                })
                XCTAssertEqual(accepted.resetsAt, window.resetsAt)
                XCTAssertTrue(center.pending.contains(accepted))
                XCTAssertEqual(accepted.title, "Codex · \(try XCTUnwrap(account.verifiedEmail))")
            }
        }
    }

    @MainActor
    func testSuccessfulAddWithoutRetainedRequestCannotBeReportedAsAccepted() async throws {
        let center = SchedulerNotificationCenterDouble()
        center.retainsAdds = false
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })

        await scheduler.update(accounts: [try account()], wantsReminders: true, authorization: .authorized)

        XCTAssertEqual(center.added.count, 2)
        XCTAssertEqual(scheduler.lastResult?.planned.count, 2)
        XCTAssertTrue(try XCTUnwrap(scheduler.lastResult).accepted.isEmpty)
        XCTAssertTrue(center.pending.isEmpty)
    }

    @MainActor
    func testFailedWindowDoesNotBlockAnotherAndCanRetryOnNextUpdate() async throws {
        let accounts = [try account()]
        let requests = plan(accounts)
        let failedID = try XCTUnwrap(requests.first?.identifier)
        let center = SchedulerNotificationCenterDouble()
        center.failingIdentifiers = [failedID]
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })

        await scheduler.update(accounts: accounts, wantsReminders: true, authorization: .authorized)

        XCTAssertEqual(scheduler.lastResult?.failedIdentifiers, [failedID])
        XCTAssertEqual(scheduler.lastResult?.accepted.count, 1)
        XCTAssertEqual(center.added.count, 2)
        center.failingIdentifiers = []
        await scheduler.update(accounts: accounts, wantsReminders: true, authorization: .authorized)

        XCTAssertEqual(scheduler.lastResult?.accepted.count, 2)
        XCTAssertTrue(try XCTUnwrap(scheduler.lastResult).failedIdentifiers.isEmpty)
        XCTAssertEqual(center.added.count, 3, "仅重试失败窗口，已回读确认的另一窗口不重复安排")
    }

    @MainActor
    func testRepeatedRoundAndReorderingDoNotAddDuplicatePendingRequests() async throws {
        let accounts = [try account(id: firstID), try account(id: secondID, offset: 60)]
        let center = SchedulerNotificationCenterDouble()
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })

        await scheduler.update(accounts: accounts, wantsReminders: true, authorization: .authorized)
        await scheduler.update(accounts: accounts, wantsReminders: true, authorization: .authorized)
        await scheduler.update(accounts: Array(accounts.reversed()), wantsReminders: true, authorization: .authorized)

        XCTAssertEqual(center.added.count, 4)
        XCTAssertEqual(center.pending.count, 4)
        XCTAssertEqual(scheduler.lastResult?.accepted.count, 4)
    }

    @MainActor
    func testOffOrUnpermittedStateClearsExistingRemindersWithoutAdding() async throws {
        let accounts = [try account()]
        let states: [(Bool, ResetReminderAuthorizationStatus)] = [
            (false, .authorized), (true, .denied), (true, .notDetermined), (true, .unknown)
        ]
        for (wantsReminders, authorization) in states {
            let center = SchedulerNotificationCenterDouble()
            center.pending = plan(accounts)
            let scheduler = ResetReminderScheduler(center: center, now: { self.now })

            await scheduler.update(accounts: accounts, wantsReminders: wantsReminders,
                                   authorization: authorization)

            XCTAssertTrue(center.added.isEmpty)
            XCTAssertTrue(center.pending.isEmpty)
            XCTAssertTrue(try XCTUnwrap(scheduler.lastResult).planned.isEmpty)
            XCTAssertTrue(try XCTUnwrap(scheduler.lastResult).accepted.isEmpty)
        }
    }

    @MainActor
    func testClearingRemindersLeavesAnotherNotificationNamespaceUntouched() async throws {
        let center = SchedulerNotificationCenterDouble()
        let own = plan([try account()])
        let unrelated = replacing(try XCTUnwrap(own.first), identifier: "unrelated.notice")
        center.pending = own + [unrelated]
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })

        await scheduler.update(accounts: [], wantsReminders: false, authorization: .authorized)

        XCTAssertEqual(center.pending, [unrelated])
        XCTAssertFalse(center.removedIdentifiers.contains(unrelated.identifier))
        XCTAssertEqual(Set(center.removedIdentifiers), Set(own.map(\.identifier)))
    }

    @MainActor
    func testMatchingIdentifierWithChangedReadbackContentIsNotAccepted() async throws {
        let center = SchedulerNotificationCenterDouble()
        center.transformAdded = { self.replacing($0, body: "额度已恢复") }
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })

        await scheduler.update(accounts: [try account()], wantsReminders: true, authorization: .authorized)

        XCTAssertEqual(center.pending.count, 2)
        XCTAssertTrue(try XCTUnwrap(scheduler.lastResult).accepted.isEmpty,
                      "标识相同也必须核对真实回读的内容")
    }

    @MainActor
    func testReadbackAllowsCeilingToWholeSecondAndKeepsActualAcceptedTime() async throws {
        let accounts = [try account(offset: 0.25)]
        let center = SchedulerNotificationCenterDouble()
        center.transformAdded = { request in
            self.replacing(request, resetsAt: Date(timeIntervalSince1970:
                ceil(request.resetsAt.timeIntervalSince1970)))
        }
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })

        await scheduler.update(accounts: accounts, wantsReminders: true, authorization: .authorized)

        let result = try XCTUnwrap(scheduler.lastResult)
        XCTAssertEqual(result.accepted.count, 2)
        for accepted in result.accepted {
            let planned = try XCTUnwrap(result.planned.first { $0.identifier == accepted.identifier })
            XCTAssertEqual(accepted.resetsAt.timeIntervalSince(planned.resetsAt), 0.75, accuracy: 0.001)
            XCTAssertTrue(center.pending.contains(accepted), "接受结果保留系统回读值，不能用拟安排对象冒充")
        }
    }

    @MainActor
    func testReadbackAtEarlierOrDifferentFutureTimeIsNotAccepted() async throws {
        for offset: TimeInterval in [-0.1, 1, 2] {
            let center = SchedulerNotificationCenterDouble()
            center.transformAdded = { self.replacing($0, resetsAt: $0.resetsAt.addingTimeInterval(offset)) }
            let scheduler = ResetReminderScheduler(center: center, now: { self.now })

            await scheduler.update(accounts: [try account()], wantsReminders: true, authorization: .authorized)

            XCTAssertTrue(try XCTUnwrap(scheduler.lastResult).accepted.isEmpty,
                          "重置时间不能任意偏移：\(offset)")
        }
    }

    @MainActor
    func testDisableWhileAddIsSuspendedRemovesLateRequestAndStopsOldBatch() async throws {
        let accounts = [try account(id: firstID), try account(id: secondID, offset: 60)]
        let center = SchedulerNotificationCenterDouble()
        center.suspendsNextAdd = true
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })
        let firstUpdate = Task {
            await scheduler.update(accounts: accounts, wantsReminders: true, authorization: .authorized)
        }
        await center.waitForSuspendedAdd()
        let disabledStarted = SchedulerTestSignal()
        let disable = Task {
            disabledStarted.signal()
            await scheduler.update(accounts: accounts, wantsReminders: false, authorization: .authorized)
        }
        await disabledStarted.wait()
        center.finishAdd()
        await firstUpdate.value
        await disable.value

        XCTAssertEqual(center.added.count, 1, "关闭后不得继续旧批次的其他窗口或账户")
        XCTAssertTrue(center.pending.isEmpty, "关闭后的迟到 add 也必须最终清理")
        XCTAssertTrue(try XCTUnwrap(scheduler.lastResult).planned.isEmpty)
        XCTAssertTrue(try XCTUnwrap(scheduler.lastResult).accepted.isEmpty)
    }

    @MainActor
    func testNewAccountsWinOverSuspendedPendingReadFromOldUpdate() async throws {
        let first = try account(id: firstID)
        let second = try account(id: secondID, offset: 60)
        let center = SchedulerNotificationCenterDouble()
        center.suspendsNextRead = true
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })
        let oldUpdate = Task {
            await scheduler.update(accounts: [first], wantsReminders: true, authorization: .authorized)
        }
        await center.waitForSuspendedRead()
        let latestStarted = SchedulerTestSignal()
        let latestUpdate = Task {
            latestStarted.signal()
            await scheduler.update(accounts: [second], wantsReminders: true, authorization: .authorized)
        }
        await latestStarted.wait()
        center.finishRead(with: [])
        await oldUpdate.value
        await latestUpdate.value

        XCTAssertEqual(center.added.count, 2)
        XCTAssertTrue(center.added.allSatisfy { $0.accountID == secondID })
        XCTAssertEqual(center.pending.count, 2)
        XCTAssertTrue(center.pending.allSatisfy { $0.accountID == secondID })
        XCTAssertTrue(try XCTUnwrap(scheduler.lastResult).accepted.allSatisfy { $0.accountID == secondID })
    }

    @MainActor
    func testTimeAdvancingDoesNotSendCatchUpOrMutateStoredQuotaAndSuccessTime() async throws {
        let account = try account()
        let original = account
        let clock = SchedulerTestClock(now)
        let center = SchedulerNotificationCenterDouble()
        let scheduler = ResetReminderScheduler(center: center, now: { clock.value })
        await scheduler.update(accounts: [account], wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(center.added.count, 2)

        clock.value = now.addingTimeInterval(300)
        await scheduler.update(accounts: [account], wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(scheduler.lastResult?.planned.map(\.window), [.weekly])
        clock.value = now.addingTimeInterval(600)
        await scheduler.update(accounts: [account], wantsReminders: true, authorization: .authorized)

        XCTAssertEqual(center.added.count, 2, "越过重置时间不另发补提醒")
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertTrue(try XCTUnwrap(scheduler.lastResult).planned.isEmpty)
        XCTAssertEqual(account, original)
        XCTAssertEqual(account.quotaSnapshot?.weekly.amount.remainingPercent, 70)
        XCTAssertEqual(account.quotaSnapshot?.fiveHours.amount.remainingPercent, 35)
        XCTAssertEqual(account.quotaSnapshot?.observedAt, now.addingTimeInterval(-60))
    }

    @MainActor
    func testT40DeliveredRoundPersistsAfterDismissalRelaunchAndSameEmailReconnect() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T40-rounds-\(UUID())")
        let url = directory.appendingPathComponent("rounds.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try account()
        let center = SchedulerNotificationCenterDouble()
        center.delivered = plan([original])
        let first = ResetReminderScheduler(center: center, now: { self.now }, journalURL: url)
        await first.update(accounts: [original], wantsReminders: true, authorization: .authorized)
        XCTAssertTrue(center.added.isEmpty)
        XCTAssertTrue(try XCTUnwrap(first.lastResult).planned.isEmpty)
        center.delivered = [] // The user cleared Notification Center.
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        var verified = original
        verified.remoteUserID = "same-verified-user"
        // Model a genuine same-identity commit, not a manually changed generation.
        try await store.append(verified)
        let incoming = ConnectedAccount(remoteUserID: verified.remoteUserID, verifiedEmail: verified.verifiedEmail,
            scope: verified.scope, credentialRef: UUID())
        let reconnected = try await store.commitLogin(incoming)
        // Record this binding's delivered round, then reload with no delivered notifications.
        center.delivered = plan([verified])
        let bindingScheduler = ResetReminderScheduler(center: center, now: { self.now }, journalURL: url)
        await bindingScheduler.update(accounts: [verified], wantsReminders: true, authorization: .authorized)
        center.delivered = []
        let relaunched = ResetReminderScheduler(center: center, now: { self.now }, journalURL: url)
        await relaunched.update(accounts: [reconnected], wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(reconnected.id, verified.id)
        XCTAssertEqual(reconnected.generation, verified.generation + 1)
        XCTAssertTrue(center.added.isEmpty, "重复添加及重开不重放已处理的同轮")
        XCTAssertTrue(center.pending.isEmpty)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(text.contains("example.invalid"))
        XCTAssertFalse(text.contains("same-verified-user"))
        print("T40 TABLE | A | 周/5小时 | 同轮已处理，清除历史、重开、同邮箱连接 | pending=0")
    }

    @MainActor
    func testT40AcceptedElapsedRoundCannotReplayAfterClockRollbackAndRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T40-elapsed-\(UUID())")
        let url = directory.appendingPathComponent("rounds.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let accounts = [try account()]
        let clock = SchedulerTestClock(now)
        let center = SchedulerNotificationCenterDouble()
        let scheduler = ResetReminderScheduler(center: center, now: { clock.value }, journalURL: url)
        await scheduler.update(accounts: accounts, wantsReminders: true, authorization: .authorized)
        center.pending = [] // Delivery/dismissal is not presented as proven actual delivery.
        clock.value = now.addingTimeInterval(700)
        let afterTime = ResetReminderScheduler(center: center, now: { clock.value }, journalURL: url)
        await afterTime.update(accounts: accounts, wantsReminders: true, authorization: .authorized)
        clock.value = now
        let afterRollback = ResetReminderScheduler(center: center, now: { clock.value }, journalURL: url)
        await afterRollback.update(accounts: accounts, wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(center.added.count, 2)
        XCTAssertTrue(center.pending.isEmpty)
    }

    @MainActor
    func testT40NewResetReplacesOnlyAffectedWindowAndKeepsOtherAccount() async throws {
        var a = try account()
        let b = try account(id: secondID, offset: 60)
        let center = SchedulerNotificationCenterDouble()
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })
        await scheduler.update(accounts: [a, b], wantsReminders: true, authorization: .authorized)
        let old = center.pending
        let oldWeekly = try XCTUnwrap(old.first { $0.accountID == a.id && $0.window == .weekly })
        a = try revised(a, weeklyReset: now.addingTimeInterval(900))
        await scheduler.update(accounts: [a, b], wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(center.pending.count, 4)
        XCTAssertEqual(center.added.count, 5)
        XCTAssertEqual(center.removedIdentifiers, [oldWeekly.identifier])
        XCTAssertEqual(center.pending.filter { $0.accountID == b.id }, old.filter { $0.accountID == b.id })
        XCTAssertEqual(center.pending.first { $0.accountID == a.id && $0.window == .weekly }?.resetsAt,
                       now.addingTimeInterval(900))
        print("T40 TABLE | A | 周 | 原+600→新+900秒 | pending=1; B两窗口不变")
    }

    @MainActor
    func testT40SwitchReenableDoesNotCatchUpAndNewAccountObeysSwitchAndOrder() async throws {
        let a = try account()
        let b = try account(id: secondID, offset: 60)
        let center = SchedulerNotificationCenterDouble()
        let clock = SchedulerTestClock(now)
        let scheduler = ResetReminderScheduler(center: center, now: { clock.value })
        await scheduler.update(accounts: [a], wantsReminders: true, authorization: .authorized)
        await scheduler.update(accounts: [a, b], wantsReminders: false, authorization: .authorized)
        XCTAssertTrue(center.pending.isEmpty)
        XCTAssertEqual(center.added.count, 2)
        clock.value = now.addingTimeInterval(350)
        await scheduler.update(accounts: [b, a], wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(center.pending.count, 3, "A五小时已过去，不补发；B两窗口仍在未来")
        let saved = center.pending
        await scheduler.update(accounts: [a, b], wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(center.pending, saved)
        XCTAssertEqual(center.added.count, 5)
        print("T40 TABLE | A/B | 有效未来窗口 | 关闭0，重开A周1+B两项2，排序不变 | pending=3")
    }

    @MainActor
    func testT40DeletionScopeAndSubscriptionInvalidationCancelOnlyAffectedRequests() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T40-scope-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let a = try account()
        let b = try account(id: secondID, offset: 60)
        try await store.append(a); try await store.append(b)
        let center = SchedulerNotificationCenterDouble()
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })
        await scheduler.update(accounts: try await store.load(), wantsReminders: true, authorization: .authorized)
        let bRequests = center.pending.filter { $0.accountID == b.id }
        let incoming = ConnectedAccount(remoteUserID: a.remoteUserID, verifiedEmail: a.verifiedEmail,
            scope: .init(remoteAccountID: "new-verified-scope", kind: .personal), credentialRef: UUID())
        _ = try await store.commitLogin(incoming)
        await scheduler.update(accounts: try await store.load(), wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(center.pending, bRequests, "新作用域没有成功数据，不沿用旧A的时间")
        _ = try await store.markForDeletion(b.id)
        await scheduler.update(accounts: try await store.load(), wantsReminders: true, authorization: .authorized)
        XCTAssertTrue(center.pending.isEmpty, "持久删除标记出现时即可取消，无须等待凭据清理")
        try await store.finishDeletion(b.id)
        await scheduler.update(accounts: try await store.load(), wantsReminders: true, authorization: .authorized)
        XCTAssertTrue(center.pending.isEmpty)
        var changed = a
        changed.subscription = .init(planType: "free", observedAt: now)
        changed.quotaSnapshot = nil
        changed.quotaState = .notApplicable
        await scheduler.update(accounts: [a], wantsReminders: true, authorization: .authorized)
        await scheduler.update(accounts: [changed], wantsReminders: true, authorization: .authorized)
        XCTAssertTrue(center.pending.isEmpty)
        print("T40 TABLE | A | 作用域变更无有效数据 | pending=0; B两项保持，删除B后总0")
    }

    @MainActor
    func testT40NewScopeWithSameTimeDoesNotInheritProcessedRound() async throws {
        var a = try account()
        let center = SchedulerNotificationCenterDouble()
        center.delivered = plan([a])
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })
        await scheduler.update(accounts: [a], wantsReminders: true, authorization: .authorized)
        a.scope = .init(remoteAccountID: "new-scope", kind: .personal)
        a = try revised(a)
        await scheduler.update(accounts: [a], wantsReminders: true, authorization: .authorized)
        XCTAssertEqual(center.pending.count, 2)
        XCTAssertEqual(center.delivered.count, 2, "取消仅影响待发，不删除系统历史")
    }

    @MainActor
    func testT40DurableLatestInputWinsOverStaleForegroundAndLateAdd() async throws {
        let a = try account()
        let b = try account(id: secondID, offset: 60)
        let latest = SchedulerInputBox(.init(accounts: [a, b], wantsReminders: true, authorization: .authorized))
        let center = SchedulerNotificationCenterDouble()
        center.suspendsNextAdd = true
        let scheduler = ResetReminderScheduler(center: center, now: { self.now }, currentInput: { latest.value })
        let task = Task {
            await scheduler.update(accounts: [a, b], wantsReminders: true, authorization: .authorized)
        }
        await center.waitForSuspendedAdd()
        latest.value = .init(accounts: [b], wantsReminders: true, authorization: .authorized)
        center.finishAdd()
        await task.value
        XCTAssertEqual(center.pending.count, 2)
        XCTAssertTrue(center.pending.allSatisfy { $0.accountID == b.id })
        latest.value = .init(accounts: [b], wantsReminders: false, authorization: .authorized)
        await scheduler.update(accounts: [a, b], wantsReminders: true, authorization: .authorized)
        XCTAssertTrue(center.pending.isEmpty, "旧前台快照不得覆盖另一执行者持久保存的关闭状态")
    }

    @MainActor
    func testT40TwoExecutorsShareJournalAndCenterWithoutDuplicateAdds() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T40-process-\(UUID())")
        let url = directory.appendingPathComponent("rounds.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try account()
        let center = SchedulerNotificationCenterDouble()
        center.suspendsNextAdd = true
        let foreground = ResetReminderScheduler(center: center, now: { self.now }, journalURL: url)
        let other = ResetReminderScheduler(center: center, now: { self.now }, journalURL: url)
        let first = Task { await foreground.update(accounts: [a], wantsReminders: true, authorization: .authorized) }
        await center.waitForSuspendedAdd()
        let second = Task { await other.update(accounts: [a], wantsReminders: true, authorization: .authorized) }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(center.added.count, 1, "第二执行者等待共享通知租约")
        center.finishAdd()
        await first.value; await second.value
        XCTAssertEqual(center.added.count, 2)
        XCTAssertEqual(center.pending.count, 2)
        XCTAssertEqual(other.lastResult?.accepted.count, 2)
    }

    @MainActor
    func testT40CorruptJournalDoesNotForgetProcessedRoundsOrClaimSuccess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T40-corrupt-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("rounds.json")
        let original = Data("not valid journal".utf8)
        try original.write(to: url)
        let center = SchedulerNotificationCenterDouble()
        let scheduler = ResetReminderScheduler(center: center, now: { self.now }, journalURL: url)
        await scheduler.update(accounts: [try account()], wantsReminders: true, authorization: .authorized)
        XCTAssertTrue(center.added.isEmpty)
        XCTAssertNil(scheduler.lastResult)
        XCTAssertEqual(try Data(contentsOf: url), original)
        center.pending = plan([try account()])
        await scheduler.update(accounts: [], wantsReminders: false, authorization: .authorized)
        XCTAssertTrue(center.pending.isEmpty, "去重记录不可读也不能阻止明确关闭取消待发")
        XCTAssertNil(scheduler.lastResult)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    @MainActor
    func testT40SharedPreferenceMigrationKeepsCurrentSwitchAndSurvivesSettingsReload() async throws {
        let legacySuite = "T40-legacy-\(UUID())"
        let sharedSuite = "T40-shared-\(UUID())"
        let legacy = try XCTUnwrap(UserDefaults(suiteName: legacySuite))
        let shared = try XCTUnwrap(UserDefaults(suiteName: sharedSuite))
        defer { legacy.removePersistentDomain(forName: legacySuite); shared.removePersistentDomain(forName: sharedSuite) }
        legacy.set(true, forKey: ResetReminderSettings.preferenceKey)
        SharedResetReminderRuntime.migratePreference(from: legacy, to: shared)
        XCTAssertTrue(shared.bool(forKey: ResetReminderSettings.preferenceKey))
        let model = ResetReminderSettings(defaults: shared)
        await model.setEnabled(false) // Off never reads/requests real permission.
        SharedResetReminderRuntime.migratePreference(from: legacy, to: shared)
        XCTAssertFalse(shared.bool(forKey: ResetReminderSettings.preferenceKey), "旧的独立偏好不得覆盖最新关闭")
        let reloaded = ResetReminderSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: sharedSuite)))
        XCTAssertFalse(reloaded.wantsReminders)
    }

    private func revised(_ account: ConnectedAccount, weeklyReset: Date? = nil) throws -> ConnectedAccount {
        var result = account
        let snapshot = try XCTUnwrap(account.quotaSnapshot)
        result.quotaSnapshot = .init(accountID: account.id, provider: account.provider, product: account.product,
            scope: account.scope, generation: account.generation, planType: snapshot.planType,
            observedAt: snapshot.observedAt,
            weekly: .init(window: .weekly, amount: snapshot.weekly.amount,
                          resetsAt: weeklyReset ?? snapshot.weekly.resetsAt, observedAt: snapshot.observedAt),
            fiveHours: snapshot.fiveHours)
        return result
    }

    private func account(id: UUID? = nil, offset: TimeInterval = 0) throws -> ConnectedAccount {
        let id = id ?? firstID
        var result = ConnectedAccount(id: id, verifiedEmail: "account-\(id.uuidString.suffix(3))@example.invalid",
            scope: .init(remoteAccountID: "scope-\(id)", kind: .personal), credentialRef: UUID(),
            generation: 2, quotaState: .available)
        let observed = now.addingTimeInterval(-60)
        result.subscription = .init(planType: "plus", observedAt: observed)
        result.quotaSnapshot = .init(accountID: result.id, provider: result.provider, product: result.product,
            scope: result.scope, generation: result.generation, planType: "plus", observedAt: observed,
            weekly: .init(window: .weekly, amount: .limited(try .init(used: 30)),
                          resetsAt: now.addingTimeInterval(600 + offset), observedAt: observed),
            fiveHours: .init(window: .fiveHours, amount: .limited(try .init(used: 65)),
                             resetsAt: now.addingTimeInterval(300 + offset), observedAt: observed))
        return result
    }

    private func plan(_ accounts: [ConnectedAccount]) -> [ResetReminderRequest] {
        ResetReminderPlan.requests(accounts: accounts, wantsReminders: true, authorization: .authorized, now: now)
    }

    private func replacing(_ request: ResetReminderRequest, identifier: String? = nil,
                           resetsAt: Date? = nil, body: String? = nil) -> ResetReminderRequest {
        .init(identifier: identifier ?? request.identifier, accountID: request.accountID, window: request.window,
              resetsAt: resetsAt ?? request.resetsAt, title: request.title, body: body ?? request.body)
    }
}

@MainActor
private final class SchedulerTestClock {
    var value: Date
    init(_ value: Date) { self.value = value }
}

@MainActor
private final class SchedulerTestSignal {
    private var isSignalled = false
    private var continuation: CheckedContinuation<Void, Never>?

    func signal() {
        isSignalled = true
        continuation?.resume()
        continuation = nil
    }

    func wait() async {
        guard !isSignalled else { return }
        await withCheckedContinuation { continuation = $0 }
    }
}

@MainActor
private final class SchedulerNotificationCenterDouble: ResetReminderNotificationCenter {
    enum Failure: Error { case rejected }
    var pending: [ResetReminderRequest] = []
    var delivered: [ResetReminderRequest] = []
    func deliveredRequests() async -> [ResetReminderRequest] { delivered }
    var retainsAdds = true
    var failingIdentifiers: Set<String> = []
    var transformAdded: ((ResetReminderRequest) -> ResetReminderRequest)?
    var suspendsNextAdd = false
    var suspendsNextRead = false
    private(set) var added: [ResetReminderRequest] = []
    private(set) var removedIdentifiers: [String] = []
    private(set) var readCount = 0
    private var addContinuation: CheckedContinuation<Void, Never>?
    private var readContinuation: CheckedContinuation<[ResetReminderRequest], Never>?
    private let addSuspended = SchedulerTestSignal()
    private let readSuspended = SchedulerTestSignal()

    func pendingRequests() async -> [ResetReminderRequest] {
        readCount += 1
        if suspendsNextRead {
            suspendsNextRead = false
            return await withCheckedContinuation { continuation in
                readContinuation = continuation
                readSuspended.signal()
            }
        }
        return pending
    }

    func add(_ request: ResetReminderRequest) async throws {
        added.append(request)
        if suspendsNextAdd {
            suspendsNextAdd = false
            await withCheckedContinuation { continuation in
                addContinuation = continuation
                addSuspended.signal()
            }
        }
        if failingIdentifiers.contains(request.identifier) { throw Failure.rejected }
        if retainsAdds {
            pending.removeAll { $0.identifier == request.identifier }
            pending.append(transformAdded?(request) ?? request)
        }
    }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers += identifiers
        pending.removeAll { identifiers.contains($0.identifier) }
    }

    func waitForSuspendedAdd() async { await addSuspended.wait() }
    func waitForSuspendedRead() async { await readSuspended.wait() }

    func finishAdd() {
        addContinuation?.resume()
        addContinuation = nil
    }

    func finishRead(with requests: [ResetReminderRequest]) {
        readContinuation?.resume(returning: requests)
        readContinuation = nil
    }
}

@MainActor
private final class SchedulerInputBox {
    var value: ResetReminderScheduler.Input
    init(_ value: ResetReminderScheduler.Input) { self.value = value }
}

/// T95: Cursor's billing-month reset joins the same global switch and scheduler.
final class CursorResetReminderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_700_000)

    func testCursorPlansOneMonthlyReminderWithItsOwnTitleAndBody() throws {
        let cursor = try cursorAccount(reset: now.addingTimeInterval(86_400 * 12.5))
        let result = ResetReminderPlan.requests(accounts: [cursor], wantsReminders: true, authorization: .authorized, now: now)
        XCTAssertEqual(result.count, 1, "Cursor只有“本月”一条，没有5小时")
        let request = try XCTUnwrap(result.first)
        XCTAssertEqual(request.window, .monthly)
        XCTAssertEqual(request.resetsAt, cursor.quotaSnapshot?.weekly.resetsAt)
        XCTAssertEqual(request.title, "Cursor · cursor@example.invalid")
        XCTAssertEqual(request.body, "本月额度预计重置，打开查看")
        XCTAssertTrue(request.identifier.hasPrefix("quota-reset.v1.\(cursor.id.uuidString.lowercased())."))
    }

    func testMixedAccountsKeepCodexRemindersUnchanged() throws {
        let codex = try codexAccount()
        let cursor = try cursorAccount(reset: now.addingTimeInterval(3_600))
        let alone = ResetReminderPlan.requests(accounts: [codex], wantsReminders: true, authorization: .authorized, now: now)
        let mixed = ResetReminderPlan.requests(accounts: [codex, cursor], wantsReminders: true, authorization: .authorized, now: now)
        XCTAssertEqual(alone.map(\.body), ["周额度预计重置，打开查看", "5 小时额度预计重置，打开查看"])
        XCTAssertEqual(Array(mixed.prefix(2)), alone, "Codex提醒标识、时间、文字都不变")
        XCTAssertEqual(mixed.last?.window, .monthly)
    }

    func testCursorWithoutTrustedFutureResetOrApplicableQuotaIsNotPlanned() throws {
        var unknownTime = try cursorAccount(reset: nil)
        let past = try cursorAccount(reset: now.addingTimeInterval(-1))
        var inapplicable = try cursorAccount(reset: now.addingTimeInterval(600)); inapplicable.quotaState = .notApplicable
        var demo = try cursorAccount(reset: now.addingTimeInterval(600)); demo.source = .demo
        unknownTime.quotaState = .available
        for input in [unknownTime, past, inapplicable, demo] {
            XCTAssertTrue(ResetReminderPlan.requests(accounts: [input], wantsReminders: true, authorization: .authorized, now: now).isEmpty)
        }
        let cursor = try cursorAccount(reset: now.addingTimeInterval(600))
        XCTAssertTrue(ResetReminderPlan.requests(accounts: [cursor], wantsReminders: false, authorization: .authorized, now: now).isEmpty,
                      "共用总开关：关闭时Cursor也不安排")
    }

    @MainActor
    func testSchedulerAddsCursorReminderAndCancelsItAfterDeletion() async throws {
        let codex = try codexAccount()
        let cursor = try cursorAccount(reset: now.addingTimeInterval(86_400 * 3))
        let center = SchedulerNotificationCenterDouble()
        let scheduler = ResetReminderScheduler(center: center, now: { self.now })

        await scheduler.update(accounts: [codex, cursor], wantsReminders: true, authorization: .authorized)
        let accepted = try XCTUnwrap(scheduler.lastResult).accepted
        XCTAssertEqual(accepted.count, 3)
        let monthly = try XCTUnwrap(accepted.first { $0.accountID == cursor.id })
        XCTAssertEqual(monthly.title, "Cursor · cursor@example.invalid")
        XCTAssertEqual(monthly.body, "本月额度预计重置，打开查看")

        await scheduler.update(accounts: [codex], wantsReminders: true, authorization: .authorized)
        XCTAssertTrue(center.removedIdentifiers.contains(monthly.identifier), "删除Cursor账户取消其待发提醒")
        XCTAssertFalse(center.pending.contains { $0.accountID == cursor.id })
        XCTAssertEqual(center.pending.filter { $0.accountID == codex.id }.count, 2, "Codex提醒保留")
    }

    @MainActor
    func testSystemRequestRoundTripsAndTapOpensCursorDetail() throws {
        let cursor = try cursorAccount(reset: Date(timeIntervalSince1970: 1_793_000_000.5))
        let request = try XCTUnwrap(ResetReminderPlan.requests(accounts: [cursor], wantsReminders: true,
            authorization: .authorized, now: now).first)
        let native = SystemResetReminderNotificationCenter.makeRequest(request)
        let decoded = try XCTUnwrap(SystemResetReminderNotificationCenter.decode(native))
        XCTAssertEqual(decoded.window, .monthly)
        XCTAssertEqual(decoded.body, "本月额度预计重置，打开查看")
        let target = try XCTUnwrap(ResetReminderTarget(request: native))
        XCTAssertEqual(target.window, .monthly)
        let other = try codexAccount()
        XCTAssertEqual(target.detailTarget(in: [other, cursor])?.id, cursor.id, "点通知进入对应Cursor账户详情")
        var deleted = cursor; deleted.deletionPending = true
        XCTAssertNil(target.detailTarget(in: [other, deleted]))
        var demo = cursor; demo.source = .demo
        XCTAssertNil(target.detailTarget(in: [demo]))
    }

    private func cursorAccount(reset: Date?) throws -> ConnectedAccount {
        var result = ConnectedAccount(id: UUID(), provider: .cursor, product: .cursorSubscription,
            remoteUserID: "google-oauth2|t95", verifiedEmail: "cursor@example.invalid",
            scope: .init(remoteAccountID: "google-oauth2|t95", kind: .personal), credentialRef: UUID(),
            generation: 3, quotaState: .available)
        let observed = now.addingTimeInterval(-60)
        result.subscription = .init(planType: "pro", observedAt: observed)
        result.quotaSnapshot = .init(accountID: result.id, provider: .cursor, product: .cursorSubscription,
            scope: result.scope, generation: result.generation, planType: "pro", observedAt: observed,
            weekly: .init(window: .monthly, amount: .limited(try QuotaPercentage(used: 42)), resetsAt: reset, observedAt: observed),
            fiveHours: CodexQuotaSnapshot.absentFiveHours(observedAt: observed))
        return result
    }

    private func codexAccount() throws -> ConnectedAccount {
        var result = ConnectedAccount(id: UUID(), remoteUserID: "verified-user", verifiedEmail: "codex@example.invalid",
            scope: .init(remoteAccountID: "verified-scope", kind: .personal), credentialRef: UUID(),
            generation: 7, quotaState: .available)
        let observed = now.addingTimeInterval(-60)
        result.subscription = .init(planType: "plus", observedAt: observed)
        result.quotaSnapshot = .init(accountID: result.id, provider: result.provider, product: result.product,
            scope: result.scope, generation: result.generation, planType: "plus", observedAt: observed,
            weekly: .init(window: .weekly, amount: .limited(try QuotaPercentage(used: 30)), resetsAt: now.addingTimeInterval(600), observedAt: observed),
            fiveHours: .init(window: .fiveHours, amount: .limited(try QuotaPercentage(used: 30)), resetsAt: now.addingTimeInterval(300), observedAt: observed))
        return result
    }
}
