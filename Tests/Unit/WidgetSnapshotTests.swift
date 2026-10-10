import Foundation
import XCTest
@testable import SubscriptionUsage

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_791_590_400)

    private func fixture(_ name: String, used: Double = 30, fetched: Bool = true) throws -> ConnectedAccount {
        var result = ConnectedAccount(remoteUserID: "private-user-\(name)", verifiedEmail: "\(name)@example.invalid",
            scope: .init(remoteAccountID: "private-scope-\(name)", kind: .personal), credentialRef: UUID())
        if fetched {
            result.subscription = .init(planType: "Plus", observedAt: time)
            result.quotaState = .available
            result.quotaSnapshot = quota(result, used: used)
        }
        return result
    }

    private func quota(_ account: ConnectedAccount, used: Double, at date: Date? = nil) -> CodexQuotaSnapshot {
        let date = date ?? time
        return .init(accountID: account.id, provider: account.provider, product: account.product, scope: account.scope,
            generation: account.generation, planType: "Plus", observedAt: date,
            weekly: .init(window: .weekly, amount: .limited(try! .init(used: used)), resetsAt: date.addingTimeInterval(86400), observedAt: date),
            fiveHours: .init(window: .fiveHours, amount: .limited(try! .init(used: used + 10)), resetsAt: date.addingTimeInterval(3600), observedAt: date))
    }

    private func stores() throws -> (AccountStore, WidgetSnapshotStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T32-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let shared = WidgetSnapshotStore(fileURL: directory.appendingPathComponent("shared/first-account.json"))
        let accountsURL = directory.appendingPathComponent("private/accounts.json")
        return (AccountStore(fileURL: accountsURL, widgetStore: shared), shared, accountsURL)
    }

    func testPublicationRequestsReloadAfterDurableChangeAndNotUnchangedLoad() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WidgetReload-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = WidgetSnapshotStore(fileURL: root.appendingPathComponent("shared.json"))
        let probe = WidgetReloadProbe()
        let store = AccountStore(fileURL: root.appendingPathComponent("accounts.json"), widgetStore: shared,
            reloadWidgets: { probe.record(try? shared.read()) })
        let a = try fixture("a"), b = try fixture("b")
        try await store.append(a)
        try await store.append(b)
        let before = probe.snapshots.count
        _ = try await store.load()
        XCTAssertEqual(probe.snapshots.count, before)
        try await store.reorder([b.id, a.id])
        XCTAssertEqual(probe.snapshots.last?.account?.id, b.id)
        XCTAssertEqual(probe.snapshots.last, try shared.read())
        XCTAssertGreaterThan(probe.snapshots.count, before)
    }

    func testWidgetNumbersSwitchIndependentlyWithoutChangingAppOrder() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a"), b = try fixture("b", used: 60), c = try fixture("c", fetched: false)
        for account in [a, b, c] { try await store.append(account) }
        let initial = try XCTUnwrap(shared.read())
        let bytes = try Data(contentsOf: shared.resolvedURL())
        XCTAssertEqual(shared.selectedAccount(in: initial, number: 1)?.id, a.id)
        try shared.switchAccount(number: 1, displayedID: a.id, revision: initial.listRevision, direction: 1)
        XCTAssertEqual(shared.selectedAccount(in: initial, number: 1)?.id, b.id)
        XCTAssertEqual(shared.selectedAccount(in: initial, number: 2)?.id, a.id)
        XCTAssertEqual(shared.selectedAccount(in: initial, number: 1)?.weekly?.amount.remainingPercent, 40)
        try shared.switchAccount(number: 2, displayedID: a.id, revision: initial.listRevision, direction: -1)
        XCTAssertEqual(shared.selectedAccount(in: initial, number: 2)?.id, c.id)
        XCTAssertEqual(shared.selectedAccount(in: initial, number: 2)?.state, .notFetched)
        XCTAssertNil(shared.selectedAccount(in: initial, number: 2)?.weekly)
        XCTAssertEqual(try Data(contentsOf: shared.resolvedURL()), bytes)
        let order = try await store.load().map(\.id)
        XCTAssertEqual(order, [a.id, b.id, c.id])
    }

    func testReorderDeleteAndStaleButtonCannotRestoreOldSelection() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a"), b = try fixture("b"), c = try fixture("c")
        for account in [a, b, c] { try await store.append(account) }
        let old = try XCTUnwrap(shared.read())
        try shared.switchAccount(number: 1, displayedID: a.id, revision: old.listRevision, direction: 1)
        try await store.reorder([c.id, a.id, b.id])
        let reordered = try XCTUnwrap(shared.read())
        XCTAssertNotEqual(reordered.listRevision, old.listRevision)
        XCTAssertEqual(shared.selectedAccount(in: reordered, number: 1)?.id, c.id)
        try shared.switchAccount(number: 1, displayedID: a.id, revision: old.listRevision, direction: 1)
        XCTAssertEqual(shared.selectedAccount(in: reordered, number: 1)?.id, c.id)
        _ = try await store.markForDeletion(c.id); try await store.finishDeletion(c.id)
        let deleted = try XCTUnwrap(shared.read())
        XCTAssertEqual(shared.selectedAccount(in: deleted, number: 1)?.id, a.id)
        for id in [a.id, b.id] { _ = try await store.markForDeletion(id); try await store.finishDeletion(id) }
        XCTAssertNil(shared.selectedAccount(in: try XCTUnwrap(shared.read()), number: 1))
    }

    func testRefreshKeepsSelectionAndSingleAccountDoesNotSwitch() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a"), b = try fixture("b")
        try await store.append(a)
        let single = try XCTUnwrap(shared.read())
        try shared.switchAccount(number: 1, displayedID: a.id, revision: single.listRevision, direction: 1)
        XCTAssertEqual(shared.selectedAccount(in: single, number: 1)?.id, a.id)
        try await store.append(b)
        let two = try XCTUnwrap(shared.read())
        try shared.switchAccount(number: 1, displayedID: a.id, revision: two.listRevision, direction: 1)
        _ = try await store.load()
        let loaded = try XCTUnwrap(shared.read())
        XCTAssertEqual(loaded.listRevision, two.listRevision)
        XCTAssertEqual(shared.selectedAccount(in: loaded, number: 1)?.id, b.id)
    }

    func testFirstAccountBothWindowsAndReorderUseOneIdentityAndTarget() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a"), b = try fixture("b", used: 70)
        try await store.append(a); try await store.append(b)
        let first = try XCTUnwrap(shared.read())
        XCTAssertEqual(first.account?.id, a.id)
        XCTAssertEqual(first.account?.weekly?.amount.remainingPercent, 70)
        XCTAssertEqual(first.account?.fiveHours?.amount.remainingPercent, 60)
        XCTAssertEqual(first.account?.quotaObservedAt, time)
        XCTAssertEqual(first.clickTarget.query, "account=\(a.id.uuidString)")
        try await store.reorder([b.id, a.id])
        let reordered = try XCTUnwrap(WidgetSnapshotStore(fileURL: shared.resolvedURL()).read())
        XCTAssertEqual(reordered.account?.id, b.id)
        XCTAssertEqual(reordered.account?.identity, "b@example.invalid")
        XCTAssertEqual(reordered.account?.weekly?.amount.remainingPercent, 30)
        XCTAssertEqual(reordered.account?.fiveHours?.amount.remainingPercent, 20)
        XCTAssertEqual(reordered.account?.quotaObservedAt, time)
        XCTAssertEqual(reordered.clickTarget.query, "account=\(b.id.uuidString)")
        print("T32 | A在首位 | 周70% / 5小时60% | 原成功时间保持 | 点击A | 通过")
        print("T32 | B移到首位 | 周30% / 5小时20% | 原成功时间保持 | 点击B | 通过")
    }

    func testUnfetchedFirstDoesNotBorrowSecondQuota() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a", fetched: false), b = try fixture("b")
        try await store.append(a); try await store.append(b)
        let snapshot = try XCTUnwrap(shared.read())
        XCTAssertEqual(snapshot.account?.id, a.id)
        XCTAssertEqual(snapshot.emptyMessage, "尚未获取额度")
        XCTAssertNil(snapshot.account?.weekly); XCTAssertNil(snapshot.account?.fiveHours)
        XCTAssertNil(snapshot.account?.quotaObservedAt)
        XCTAssertEqual(snapshot.clickTarget.query, "account=\(a.id.uuidString)")
        print("T32 | A尚未取得 / B有额度 | 仍显示A，无数值无成功时间 | 点击A | 通过")
    }

    func testFreeFirstHasPlanAndNoFabricatedWindows() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a"), b = try fixture("b")
        try await store.append(a); try await store.append(b)
        _ = try await store.saveObservation(.init(planType: "Free", observedAt: time.addingTimeInterval(60)), quota: .notApplicable, for: a)
        let snapshot = try XCTUnwrap(shared.read())
        XCTAssertEqual(snapshot.account?.id, a.id)
        XCTAssertEqual(snapshot.account?.state, .notApplicable)
        XCTAssertEqual(snapshot.account?.plan, "Free")
        XCTAssertNil(snapshot.emptyMessage)
        XCTAssertNil(snapshot.account?.weekly); XCTAssertNil(snapshot.account?.fiveHours)
        XCTAssertNil(snapshot.account?.quotaObservedAt)
        XCTAssertEqual(snapshot.account?.subscriptionObservedAt, time.addingTimeInterval(60))
        print("T32 | A确认为Free | 显示A与Free，无额度区域 | 点击A | 通过")
    }

    func testDeletingFirstAndThenAllClearsOldIdentityAndTarget() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a"), b = try fixture("b", used: 70)
        try await store.append(a); try await store.append(b)
        _ = try await store.markForDeletion(a.id)
        XCTAssertEqual(try shared.read()?.account?.id, b.id)
        try await store.finishDeletion(a.id)
        _ = try await store.markForDeletion(b.id)
        try await store.finishDeletion(b.id)
        let empty = try XCTUnwrap(shared.read())
        XCTAssertEqual(empty, .empty)
        XCTAssertEqual(empty.emptyMessage, "添加账户")
        XCTAssertNil(empty.clickTarget.query)
        let raw = try String(contentsOf: shared.resolvedURL(), encoding: .utf8)
        XCTAssertFalse(raw.contains("example.invalid")); XCTAssertFalse(raw.contains(a.id.uuidString))
        print("T32 | 全部断开 | 添加账户 | 无旧身份数值时间 | 点击额度页 | 通过")
    }

    func testSameEmailReconnectionKeepsPositionAndOldSuccessfulValues() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a"), b = try fixture("b")
        try await store.append(a); try await store.append(b)
        let before = try shared.read()
        var incoming = try fixture("a", fetched: false)
        incoming.verifiedEmail = "A@example.invalid"
        let updated = try await store.commitLogin(incoming)
        XCTAssertEqual(updated.id, a.id)
        let result = try XCTUnwrap(shared.read())
        XCTAssertEqual(result.account?.weekly, before?.account?.weekly)
        XCTAssertEqual(result.account?.quotaObservedAt, before?.account?.quotaObservedAt)
        XCTAssertEqual(result.clickTarget, before?.clickTarget)
        let accounts = try await store.load()
        XCTAssertEqual(accounts.map(\.id), [a.id, b.id])
    }

    func testChangedScopeAndLateOldResultNeverRestorePreviousQuota() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a"), b = try fixture("b")
        try await store.append(a); try await store.append(b)
        var incoming = try fixture("a", fetched: false)
        incoming.scope = .init(remoteAccountID: "new-private-scope", kind: .workspace)
        _ = try await store.commitLogin(incoming)
        let changed = try shared.read()
        XCTAssertEqual(changed?.account?.id, a.id)
        XCTAssertEqual(changed?.account?.state, .notFetched)
        XCTAssertNil(changed?.account?.weekly)
        do {
            _ = try await store.saveQuota(quota(a, used: 10, at: time.addingTimeInterval(60)), for: a)
            XCTFail("Old result must be rejected")
        } catch { XCTAssertEqual(error as? AccountStore.StoreError, .staleQuotaContext) }
        XCTAssertEqual(try shared.read(), changed)
    }

    func testSuccessfulRefreshPublishesAndFailureRetainsOriginalQuotaTime() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a")
        try await store.append(a)
        let later = time.addingTimeInterval(120)
        let updated = try await store.saveObservation(.init(planType: "Plus", observedAt: later),
            quota: .available(quota(a, used: 20, at: later)), for: a)
        XCTAssertEqual(try shared.read()?.account?.weekly?.amount.remainingPercent, 80)
        _ = try await store.saveObservation(.init(planType: "Plus", observedAt: later.addingTimeInterval(60)), quota: .failed, for: updated)
        let failed = try XCTUnwrap(shared.read())
        XCTAssertEqual(failed.account?.weekly?.amount.remainingPercent, 80)
        XCTAssertEqual(failed.account?.fiveHours?.amount.remainingPercent, 70)
        XCTAssertEqual(failed.account?.quotaObservedAt, later)
        XCTAssertEqual(failed.account?.weekly?.observedAt, later)
        XCTAssertEqual(failed.account?.subscriptionObservedAt, later.addingTimeInterval(60))
    }

    func testUnknownUnlimitedAndRealZeroSurviveRoundTrip() throws {
        var a = try fixture("a")
        let original = try XCTUnwrap(a.quotaSnapshot)
        for amount in [QuotaAmount.unknown, .unlimited, .limited(try .init(used: 100))] {
            a.quotaSnapshot = .init(accountID: a.id, provider: a.provider, product: a.product, scope: a.scope,
                generation: a.generation, planType: "Plus", observedAt: time, weekly: original.weekly,
                fiveHours: .init(window: .fiveHours, amount: amount, resetsAt: nil, observedAt: time))
            let (_, shared, _) = try stores()
            let projected = WidgetSnapshot.projecting([a])
            try shared.write(projected)
            XCTAssertEqual(try shared.read(), projected)
            XCTAssertEqual(try shared.read()?.account?.fiveHours?.amount.remainingPercent, amount.remainingPercent)
        }
    }

    func testOnlyDisplayAllowlistIsSharedWithoutConnectionMetadata() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a")
        try await store.append(a)
        let data = try Data(contentsOf: shared.resolvedURL())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["schemaVersion", "account", "accounts", "listRevision"])
        let account = try XCTUnwrap(object["account"] as? [String: Any])
        XCTAssertEqual(Set(account.keys), ["id", "identity", "plan", "isDemo", "state", "subscriptionObservedAt", "quotaObservedAt", "weekly", "fiveHours"])
        let raw = String(decoding: data, as: UTF8.self)
        for forbidden in ["credential", "token", "authorization", "cookie", "remoteAccountID", "remoteUserID", "generation", "private-scope-a", "private-user-a", a.credentialRef.uuidString] {
            XCTAssertFalse(raw.contains(forbidden), forbidden)
        }
        XCTAssertFalse(try XCTUnwrap(shared.read()).clickTarget.absoluteString.contains("example.invalid"))
        print("T32 | 共享字段白名单与独立读取 | 只有必要展示数据，无授权、作用域或凭据引用 | 通过")
    }

    func testLaunchRepairsMissingAndCorruptSharedSnapshotFromTrustedAccountFile() async throws {
        let (store, shared, accountURL) = try stores()
        let a = try fixture("a")
        try await store.append(a)
        try shared.remove()
        let reopened = AccountStore(fileURL: accountURL, widgetStore: shared)
        _ = try await reopened.load()
        XCTAssertEqual(try shared.read()?.account?.id, a.id)
        try Data("corrupt".utf8).write(to: shared.resolvedURL())
        XCTAssertThrowsError(try shared.read())
        _ = try await reopened.load()
        XCTAssertEqual(try shared.read()?.account?.quotaObservedAt, time)
    }

    func testSharedWriteFailureDoesNotUndoCommittedLoginAndNextLoadRepairs() async throws {
        let (_, shared, accountURL) = try stores()
        let parent = try shared.resolvedURL().deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("blocked-directory".utf8).write(to: parent)
        let store = AccountStore(fileURL: accountURL, widgetStore: shared)
        let a = try fixture("a")
        _ = try await store.commitLogin(a)
        let failed = await store.widgetPublicationFailed
        XCTAssertTrue(failed)
        let privateRecords = try await AccountStore(fileURL: accountURL).load()
        XCTAssertEqual(privateRecords, [a])
        try FileManager.default.removeItem(at: parent)
        _ = try await store.load()
        let repaired = await store.widgetPublicationFailed
        XCTAssertFalse(repaired)
        XCTAssertEqual(try shared.read()?.account?.id, a.id)
    }

    func testInvalidAccountCommitCannotPublishUncommittedOrder() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a"), b = try fixture("b")
        try await store.append(a); try await store.append(b)
        let before = try shared.read()
        do { try await store.reorder([b.id]); XCTFail("Invalid order must fail") }
        catch { XCTAssertEqual(error as? AccountStore.StoreError, .invalidOrder) }
        XCTAssertEqual(try shared.read(), before)
    }

    func testDemoDisableRemovesSharedSampleAndUsesRealFirstAccount() async throws {
        let (store, shared, _) = try stores()
        _ = try await store.setDemoMode(true)
        let demo = try await store.addDemo(now: time)
        let real = try fixture("real")
        try await store.append(real)
        XCTAssertEqual(try shared.read()?.account?.id, demo.id)
        XCTAssertEqual(try shared.read()?.account?.isDemo, true)
        _ = try await store.setDemoMode(false)
        XCTAssertEqual(try shared.read()?.account?.id, real.id)
        XCTAssertEqual(try shared.read()?.account?.isDemo, false)
    }

    func testReaderRejectsUnsupportedCorruptAndOversizedFiles() throws {
        let (_, shared, _) = try stores()
        XCTAssertNil(try shared.read())
        try shared.write(.empty)
        try Data("{\"schemaVersion\":9}".utf8).write(to: shared.resolvedURL())
        XCTAssertThrowsError(try shared.read()) { XCTAssertEqual($0 as? WidgetSnapshotStore.StoreError, .unsupportedSchema) }
        try Data(repeating: 32, count: 65_537).write(to: shared.resolvedURL())
        XCTAssertThrowsError(try shared.read()) { XCTAssertEqual($0 as? WidgetSnapshotStore.StoreError, .oversizedSnapshot) }
        try Data("garbled".utf8).write(to: shared.resolvedURL())
        XCTAssertThrowsError(try shared.read())
    }

    func testReaderRejectsInvalidPercentageAndMismatchedWindowTime() throws {
        let (_, shared, _) = try stores()
        try shared.write(.projecting([fixture("a")]))
        let validData = try Data(contentsOf: shared.resolvedURL())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: validData) as? [String: Any])
        var account = try XCTUnwrap(object["account"] as? [String: Any])
        var weekly = try XCTUnwrap(account["weekly"] as? [String: Any])
        weekly["amount"] = ["limited": ["usedPercent": 101]]
        account["weekly"] = weekly; object["account"] = account
        try JSONSerialization.data(withJSONObject: object).write(to: shared.resolvedURL())
        XCTAssertThrowsError(try shared.read()) { XCTAssertEqual($0 as? WidgetSnapshotStore.StoreError, .invalidSnapshot) }
        weekly["amount"] = ["limited": ["usedPercent": 30]]
        weekly["observedAt"] = 0
        account["weekly"] = weekly; object["account"] = account
        try JSONSerialization.data(withJSONObject: object).write(to: shared.resolvedURL())
        XCTAssertThrowsError(try shared.read()) { XCTAssertEqual($0 as? WidgetSnapshotStore.StoreError, .invalidSnapshot) }
    }

    func testRealAppGroupContainerRoundTripUsesIsolatedFilename() async throws {
        let root = try WidgetSnapshotStore.sharedDirectory()
        let directory = root.appendingPathComponent("T32-Tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        // Uses the genuine entitled group, with a unique test path. Never reads or
        // overwrites the production first-account.json or real account/Keychain store.
        let shared = WidgetSnapshotStore(fileURL: directory.appendingPathComponent("first-account.json"))
        let privateURL = FileManager.default.temporaryDirectory.appendingPathComponent("T32-private-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: privateURL) }
        let store = AccountStore(fileURL: privateURL, widgetStore: shared)
        let a = try fixture("a"), b = try fixture("b", used: 70)
        try await store.append(a); try await store.append(b)
        XCTAssertEqual(try shared.read()?.account?.weekly?.amount.remainingPercent, 70)
        try await store.reorder([b.id, a.id])
        XCTAssertEqual(try WidgetSnapshotStore(fileURL: shared.resolvedURL()).read()?.account?.id, b.id)
        XCTAssertEqual(try shared.read()?.account?.fiveHours?.amount.remainingPercent, 20)
        _ = try await store.markForDeletion(b.id); try await store.finishDeletion(b.id)
        _ = try await store.markForDeletion(a.id); try await store.finishDeletion(a.id)
        XCTAssertEqual(try shared.read(), .empty)
        print("T32 | 系统App Group真实目录 | 独立写入、重读、排序、清空通过 | 样例与正式数据隔离")
    }
}

/// Explicit read-only check of the installed App's own files. No network,
/// Keychain access, account mutations, or production snapshot publication.
@MainActor
final class WidgetSnapshotLocalTests: XCTestCase {
    func testInstalledProductionSnapshotMatchesSavedFirstAccount() async throws {
        guard ProcessInfo.processInfo.environment["T32_LOCAL_SHARED_CHECK"] == "1" else {
            throw XCTSkip("正式本机快照核对须显式启用；默认只运行隔离样例。")
        }
        let accountURL = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("SubscriptionUsage/accounts.json")
        let before = try Data(contentsOf: accountURL)
        let shared = WidgetSnapshotStore.appGroupStore()
        let sharedBefore = try Data(contentsOf: shared.resolvedURL())
        let records = try await AccountStore(fileURL: accountURL).load()
        let actual = try XCTUnwrap(shared.read())
        let expected = WidgetSnapshot.projecting(records)
        // Boolean assertions avoid dumping real account values on a failure.
        XCTAssertTrue(actual.account == expected.account && actual.allAccounts == expected.allAccounts, "正式共享字段必须全部对应已保存账户")
        XCTAssertTrue(actual.clickTarget == expected.clickTarget, "正式点击目标必须对应首账户")
        XCTAssertTrue(try Data(contentsOf: accountURL) == before, "只读核对不能修改账户文件")
        XCTAssertTrue(try Data(contentsOf: shared.resolvedURL()) == sharedBefore, "只读核对不能补写共享文件")
        print("T32 | 正式版普通启动后的本机快照 | 首账户、套餐、双窗口、原时间与点击目标逐字段一致 | 只读检查通过")
    }
}

private final class WidgetReloadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [WidgetSnapshot] = []
    var snapshots: [WidgetSnapshot] { lock.withLock { values } }
    func record(_ snapshot: WidgetSnapshot?) {
        guard let snapshot else { return }
        lock.withLock { values.append(snapshot) }
    }
}
