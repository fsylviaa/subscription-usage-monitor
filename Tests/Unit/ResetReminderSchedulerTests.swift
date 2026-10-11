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
