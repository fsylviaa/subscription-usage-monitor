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

    func testT35ConcurrentFixtureLoadsWaitForCompleteAccountList() async throws {
        let fixture = T26BatchFixture(scenario: "success", count: 4)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        async let first = fixture.load()
        async let second = fixture.load()
        async let third = fixture.load()
        let results = try await [first, second, third]
        for accounts in results {
            XCTAssertEqual(accounts.count, 4)
            XCTAssertEqual(accounts.map(\.id), results[0].map(\.id))
        }
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

    func testT35MetadataOnlyRefreshPersistsWithoutReloadButVisibleChangesStillReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("T35-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = WidgetSnapshotStore(fileURL: root.appendingPathComponent("shared.json"))
        let probe = WidgetReloadProbe()
        let store = AccountStore(fileURL: root.appendingPathComponent("accounts.json"), widgetStore: shared,
            reloadWidgets: { probe.record(try? shared.read()) })
        let a = try fixture("a"), b = try fixture("b")
        try await store.append(a); try await store.append(b)
        let before = probe.snapshots.count
        let later = time.addingTimeInterval(60)
        _ = try await store.saveObservation(.init(planType: "Plus", observedAt: later),
            quota: .available(quota(a, used: 30, at: later)), for: a)
        XCTAssertEqual(probe.snapshots.count, before, "时间变化不改变无时间的组件画面")
        XCTAssertEqual(try shared.read()?.account?.quotaObservedAt, later)
        XCTAssertEqual(try shared.read()?.account?.weekly?.resetsAt, later.addingTimeInterval(86400))
        let updatedB = try await store.saveObservation(.init(planType: "Plus", observedAt: later),
            quota: .available(quota(b, used: 60, at: later)), for: b)
        XCTAssertEqual(probe.snapshots.count, before + 1, "非首账户也可能被组件固定选择")
        XCTAssertEqual(probe.snapshots.last, try shared.read(), "必须先落盘再请求更新")
        try await store.saveQuotaFailure(.refresh, for: updatedB)
        XCTAssertEqual(probe.snapshots.count, before + 2)
        let recoveredAt = later.addingTimeInterval(60)
        _ = try await store.saveObservation(.init(planType: "Plus", observedAt: recoveredAt),
            quota: .available(quota(b, used: 60, at: recoveredAt)), for: updatedB)
        XCTAssertEqual(probe.snapshots.count, before + 3, "成功清除失败提示仍须更新，即使额度不变")
        XCTAssertNil(try shared.read()?.allAccounts.last?.failure)
    }

    func testT35FailurePersistsSeparatelyClearsOnSuccessAndKeepsOtherAccount() async throws {
        let (store, shared, url) = try stores()
        let a = try fixture("a"), b = try fixture("b", used: 60)
        try await store.append(a); try await store.append(b)
        let old = try XCTUnwrap(shared.read())
        try await store.saveQuotaFailure(.networkBlocked, for: a)
        let failed = QuotaWidgetContent.read(from: shared)
        XCTAssertEqual(failed.message, "网络不达标，无法更新")
        XCTAssertEqual(failed.account?.weekly, old.account?.weekly)
        XCTAssertEqual(failed.account?.quotaObservedAt, time)
        XCTAssertNil(failed.selecting(accountID: b.id.uuidString).message)
        let records = try await store.load()
        XCTAssertEqual(records, [a, b], "失败不改可信账户与成功快照")
        try shared.remove()
        _ = try await AccountStore(fileURL: url, widgetStore: shared).load()
        XCTAssertEqual(QuotaWidgetContent.read(from: shared).message, failed.message)
        _ = try await store.saveObservation(.init(planType: "Plus", observedAt: time.addingTimeInterval(10)),
            quota: .available(quota(a, used: 10, at: time.addingTimeInterval(10))), for: a)
        XCTAssertNil(QuotaWidgetContent.read(from: shared).message)
        XCTAssertEqual(try shared.read()?.account?.weekly?.amount.remainingPercent, 90)
    }

    func testT35FirstFailureFreeAndReconnectionDoNotBorrowValuesOrKeepOldError() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a", fetched: false), b = try fixture("b")
        try await store.append(a); try await store.append(b)
        try await store.saveQuotaFailure(.refresh, for: a)
        XCTAssertEqual(QuotaWidgetContent.read(from: shared).message, "获取失败")
        XCTAssertNil(try shared.read()?.account?.weekly)
        let free = try await store.saveObservation(.init(planType: "Free", observedAt: time), quota: .notApplicable, for: a)
        XCTAssertNil(QuotaWidgetContent.read(from: shared).message)
        try await store.saveQuotaFailure(.refresh, for: free)
        XCTAssertEqual(QuotaWidgetContent.read(from: shared).message, "刷新失败")
        XCTAssertNil(try shared.read()?.account?.weekly)
        let incoming = try fixture("a", fetched: false)
        _ = try await store.commitLogin(incoming)
        XCTAssertNil(try shared.read()?.account?.failure)
        do { try await store.saveQuotaFailure(.refresh, for: free); XCTFail("旧连接失败不可回写") }
        catch { XCTAssertEqual(error as? AccountStore.StoreError, .staleQuotaContext) }
        XCTAssertNil(try shared.read()?.account?.failure)
    }

    func testT35NewSuccessRejectsOldFailureAndDeletionRejectsBothLateResults() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("T35-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = WidgetSnapshotStore(fileURL: root.appendingPathComponent("shared.json"))
        let probe = WidgetReloadProbe()
        let store = AccountStore(fileURL: root.appendingPathComponent("accounts.json"), widgetStore: shared,
            reloadWidgets: { probe.record(try? shared.read()) })
        let a = try fixture("a"), b = try fixture("b")
        try await store.append(a); try await store.append(b)
        _ = try await store.saveObservation(.init(planType: "Plus", observedAt: time.addingTimeInterval(10)),
            quota: .available(quota(a, used: 10, at: time.addingTimeInterval(10))), for: a)
        let before = probe.snapshots.count
        do { try await store.saveQuotaFailure(.refresh, for: a); XCTFail("较新成功不可被旧失败标记") }
        catch { XCTAssertEqual(error as? AccountStore.StoreError, .staleQuotaContext) }
        XCTAssertEqual(probe.snapshots.count, before)
        for id in [a.id, b.id] { _ = try await store.markForDeletion(id); try await store.finishDeletion(id) }
        XCTAssertEqual(probe.snapshots.last, .empty)
        let count = probe.snapshots.count
        do { _ = try await store.saveQuota(quota(a, used: 0, at: time.addingTimeInterval(20)), for: a); XCTFail("旧成功不得恢复账户") }
        catch { XCTAssertEqual(error as? AccountStore.StoreError, .accountNotFound) }
        do { try await store.saveQuotaFailure(.refresh, for: a); XCTFail("旧失败不得恢复账户") }
        catch { XCTAssertEqual(error as? AccountStore.StoreError, .staleQuotaContext) }
        XCTAssertEqual(probe.snapshots.count, count)
        XCTAssertEqual(try shared.read(), .empty)
    }

    func testT35FailureFollowsPinnedIdentityAcrossSortAndDeletionWithReloadAfterWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("T35-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = WidgetSnapshotStore(fileURL: root.appendingPathComponent("shared.json"))
        let probe = WidgetReloadProbe()
        let store = AccountStore(fileURL: root.appendingPathComponent("accounts.json"), widgetStore: shared,
            reloadWidgets: { probe.record(try? shared.read()) })
        let a = try fixture("a"), b = try fixture("b", used: 60)
        try await store.append(a); try await store.append(b)
        try await store.saveQuotaFailure(.refresh, for: a)
        XCTAssertEqual(probe.snapshots.last?.account?.failure, .refresh)
        try await store.reorder([b.id, a.id])
        let content = QuotaWidgetContent.read(from: shared)
        XCTAssertNil(content.message)
        XCTAssertEqual(content.selecting(accountID: a.id.uuidString).message, "刷新失败")
        XCTAssertEqual(probe.snapshots.last, try shared.read())
        _ = try await store.markForDeletion(a.id); try await store.finishDeletion(a.id)
        let fallback = QuotaWidgetContent.read(from: shared).selecting(accountID: a.id.uuidString)
        XCTAssertEqual(fallback.account?.id, b.id)
        XCTAssertNil(fallback.message)
        XCTAssertEqual(probe.snapshots.last, try shared.read())
    }

    func testConfiguredAccountsAreIndependentAndDoNotChangeAppOrder() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a"), b = try fixture("b", used: 60), c = try fixture("c", fetched: false)
        for account in [a, b, c] { try await store.append(account) }
        let bytes = try Data(contentsOf: shared.resolvedURL())
        let content = QuotaWidgetContent.read(from: shared)
        XCTAssertEqual(content.selecting(accountID: nil).account?.id, a.id)
        XCTAssertEqual(content.selecting(accountID: WidgetAccountEntity.firstID).account?.id, a.id)
        XCTAssertEqual(content.selecting(accountID: b.id.uuidString).account?.weekly?.amount.remainingPercent, 40)
        XCTAssertEqual(content.selecting(accountID: c.id.uuidString).account?.state, .notFetched)
        XCTAssertNil(content.selecting(accountID: c.id.uuidString).account?.weekly)
        XCTAssertEqual(content.selecting(accountID: a.id.uuidString).account?.id, a.id)
        XCTAssertEqual(try Data(contentsOf: shared.resolvedURL()), bytes)
        let order = try await store.load().map(\.id)
        XCTAssertEqual(order, [a.id, b.id, c.id])
    }

    func testPinnedAccountSurvivesReorderAndRefreshWhileDefaultFollowsFirst() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a"), b = try fixture("b"), c = try fixture("c")
        for account in [a, b, c] { try await store.append(account) }
        try await store.reorder([c.id, a.id, b.id])
        var content = QuotaWidgetContent.read(from: shared)
        XCTAssertEqual(content.selecting(accountID: nil).account?.id, c.id)
        XCTAssertEqual(content.selecting(accountID: b.id.uuidString).account?.id, b.id)
        _ = try await store.saveObservation(.init(planType: "Plus", observedAt: time.addingTimeInterval(60)),
            quota: .available(quota(b, used: 60, at: time.addingTimeInterval(60))), for: b)
        _ = try await store.load()
        content = QuotaWidgetContent.read(from: shared)
        XCTAssertEqual(content.selecting(accountID: b.id.uuidString).account?.weekly?.amount.remainingPercent, 40)
        XCTAssertEqual(content.selecting(accountID: nil).account?.id, c.id)
    }

    func testRemovedSelectionFallsBackWithoutRestoringDeletedData() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a"), b = try fixture("b", used: 60)
        try await store.append(a); try await store.append(b)
        _ = try await store.markForDeletion(b.id); try await store.finishDeletion(b.id)
        let content = QuotaWidgetContent.read(from: shared).selecting(accountID: b.id.uuidString)
        XCTAssertEqual(content.account?.id, a.id)
        XCTAssertEqual(content.account?.weekly?.amount.remainingPercent, 70)
        _ = try await store.markForDeletion(a.id); try await store.finishDeletion(a.id)
        XCTAssertTrue(QuotaWidgetContent.read(from: shared).selecting(accountID: b.id.uuidString).showsAddAccount)
        XCTAssertEqual(QuotaWidgetContent.unavailable.selecting(accountID: b.id.uuidString), .unavailable)
    }

    func testAccountPickerUsesFullIdentityCurrentOrderAndOnlyValidAccounts() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("same"), b = try fixture("second", fetched: false)
        try await store.append(a); try await store.append(b)
        let query = WidgetAccountQuery(store: shared)
        let options = try await query.suggestedEntities()
        XCTAssertEqual(options.map(\.id), [WidgetAccountEntity.firstID, a.id.uuidString, b.id.uuidString])
        XCTAssertEqual(options[1].identity, "same@example.invalid")
        XCTAssertEqual(options[1].detail, "Codex · Plus")
        let defaultOption = await query.defaultResult()
        XCTAssertEqual(defaultOption?.id, WidgetAccountEntity.firstID)
        _ = try await store.markForDeletion(b.id); try await store.finishDeletion(b.id)
        let resolved = try await query.entities(for: [b.id.uuidString, a.id.uuidString, WidgetAccountEntity.firstID])
        XCTAssertEqual(resolved.map(\.id), [a.id.uuidString, WidgetAccountEntity.firstID])
    }

    func testLegacyNumberFilesDoNotOverrideNewDefaultOrConfiguredAccount() async throws {
        let (store, shared, _) = try stores()
        let a = try fixture("a"), b = try fixture("b")
        try await store.append(a); try await store.append(b)
        let snapshot = try XCTUnwrap(shared.read())
        let oldSelection: [String: String] = ["revision": try XCTUnwrap(snapshot.listRevision).uuidString, "accountID": b.id.uuidString]
        try JSONSerialization.data(withJSONObject: oldSelection).write(to: shared.resolvedURL().deletingLastPathComponent().appendingPathComponent("selection-1.json"))
        let content = QuotaWidgetContent.read(from: shared)
        XCTAssertEqual(content.selecting(accountID: nil).account?.id, a.id)
        XCTAssertEqual(content.selecting(accountID: b.id.uuidString).account?.id, b.id)
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
        // This read-only check compares trusted account fields; failure metadata is
        // independently persisted and covered by the isolated T35 round-trip tests.
        let actualMeasurements = actual.allAccounts.map { value in
            var value = value; value.failure = nil; return value
        }
        XCTAssertTrue(actualMeasurements == expected.allAccounts, "正式共享字段必须全部对应已保存账户")
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
