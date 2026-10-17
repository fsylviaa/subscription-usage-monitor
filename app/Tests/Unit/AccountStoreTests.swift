import Foundation
import XCTest
@testable import SubscriptionUsage

@MainActor
final class AccountStoreTests: XCTestCase {
    func testNewStoreRestoresBothAccountIdentitiesAndAppendOrder() async throws {
        let fileURL = try isolatedFileURL()
        let accountA = makeAccountA()
        let accountB = makeAccountB()

        do {
            let writer = AccountStore(fileURL: fileURL)
            try await writer.append(accountA)
            try await writer.append(accountB)
        }

        let restored = try await AccountStore(fileURL: fileURL).load()
        XCTAssertEqual(restored, [accountA, accountB])
        print("T04 | 保存 A、B 后新建读取实例 | \(restored.compactMap(\.displayName).joined(separator: ",")) | 身份与顺序按完整记录核对")
    }

    func testUpdatingAChangesOnlyItsMetadataAndKeepsItsPosition() async throws {
        let fileURL = try isolatedFileURL()
        let accountA = makeAccountA()
        let accountB = makeAccountB()
        let store = AccountStore(fileURL: fileURL)
        try await store.append(accountA)
        try await store.append(accountB)

        var updatedA = accountA
        updatedA.remoteUserID = "fixture-user-a-updated"
        updatedA.verifiedEmail = "a-updated@example.invalid"
        updatedA.displayName = "A 已更新"
        updatedA.scope = AccountScope(
            remoteAccountID: "fixture-workspace-a",
            kind: .workspace,
            label: "A 测试工作区"
        )
        updatedA.credentialRef = UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!
        updatedA.generation += 1
        try await store.update(updatedA)

        let restored = try await AccountStore(fileURL: fileURL).load()
        XCTAssertEqual(restored, [updatedA, accountB])
        XCTAssertEqual(restored.first?.id, accountA.id)
        XCTAssertEqual(restored.last, accountB, "修改 A 不能改变 B 的身份、平台、作用域或连接引用")
        print("T04 | 只修改 A 的身份与作用域 | \(restored.compactMap(\.displayName).joined(separator: ",")) | B 完整记录未变")
    }

    func testNotFetchedSurvivesReloadWithoutQuotaValuesTimesOrSecretsOnDisk() async throws {
        let fileURL = try isolatedFileURL()
        let accountA = makeAccountA()
        try await AccountStore(fileURL: fileURL).append(accountA)

        let restored = try await AccountStore(fileURL: fileURL).load()
        XCTAssertEqual(restored.first?.quotaState, .notFetched)

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL))
        let document = try XCTUnwrap(object as? [String: Any])
        let records = try XCTUnwrap(document["accounts"] as? [[String: Any]])
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record["quotaState"] as? String, "notFetched")
        XCTAssertEqual(record["credentialRef"] as? String, accountA.credentialRef.uuidString)

        let forbiddenFragments = [
            "token", "password", "secret", "cookie", "authorization",
            "percent", "remaining", "reset", "success", "timestamp"
        ]
        let forbiddenKeys = allKeys(in: object).filter { key in
            forbiddenFragments.contains { key.lowercased().contains($0) }
        }
        XCTAssertTrue(forbiddenKeys.isEmpty, "尚未获取不能写入额度/时间，普通账户文件不能写入授权秘密：\(forbiddenKeys)")
        print("T04 | 保存尚未获取额度 | \(restored.first?.quotaState.rawValue ?? "缺失") | 磁盘无额度百分比、重置/成功时间、授权秘密字段")
    }

    func testReorderingPersistsWithoutChangingEitherAccount() async throws {
        let fileURL = try isolatedFileURL()
        let accountA = makeAccountA()
        let accountB = makeAccountB()

        do {
            let writer = AccountStore(fileURL: fileURL)
            try await writer.append(accountA)
            try await writer.append(accountB)
            try await writer.reorder([accountB.id, accountA.id])
        }

        let restored = try await AccountStore(fileURL: fileURL).load()
        XCTAssertEqual(restored, [accountB, accountA])
        print("T04 | 将 A、B 移为 B、A 后新建读取实例 | \(restored.compactMap(\.displayName).joined(separator: ",")) | 两账户完整记录未变")
    }

    func testMissingFileReturnsEmptyWithoutCreatingAccountData() async throws {
        let fileURL = try isolatedFileURL()

        let restored = try await AccountStore(fileURL: fileURL).load()

        XCTAssertTrue(restored.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testCorruptFilesAreReportedAndNeverOverwrittenByAppend() async throws {
        let fileURL = try isolatedFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        // An empty existing file is corrupt too; only an absent file means no saved accounts.
        for damagedData in [Data(), Data("{\"schemaVersion\":1,\"accounts\":[".utf8)] {
            try damagedData.write(to: fileURL)
            let store = AccountStore(fileURL: fileURL)
            do {
                _ = try await store.load()
                XCTFail("损坏文件不能被解释为空账户")
            } catch {
                XCTAssertTrue(error is DecodingError)
            }
            do {
                try await store.append(makeAccountA())
                XCTFail("新增账户不能覆盖损坏文件")
            } catch {
                XCTAssertTrue(error is DecodingError)
            }
            XCTAssertEqual(try Data(contentsOf: fileURL), damagedData)
        }
    }

    func testUnsupportedSchemaIsReportedAndNeverOverwrittenByAppend() async throws {
        let fileURL = try isolatedFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let futureDocument = Data("{\"schemaVersion\":2,\"accounts\":[]}".utf8)
        try futureDocument.write(to: fileURL)
        let store = AccountStore(fileURL: fileURL)

        await assertStoreError(.unsupportedSchemaVersion(2)) {
            _ = try await store.load()
        }
        await assertStoreError(.unsupportedSchemaVersion(2)) {
            try await store.append(self.makeAccountA())
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), futureDocument)
    }

    func testRejectedMutationsLeaveCommittedFileUnchanged() async throws {
        let fileURL = try isolatedFileURL()
        let accountA = makeAccountA()
        let accountB = makeAccountB()
        let store = AccountStore(fileURL: fileURL)
        try await store.append(accountA)
        try await store.append(accountB)
        let committedData = try Data(contentsOf: fileURL)

        var duplicateA = accountA
        duplicateA.displayName = "不能覆盖原 A"
        await assertStoreError(.duplicateLocalID) {
            try await store.append(duplicateA)
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), committedData)

        let unknownAccount = ConnectedAccount(
            id: UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!,
            scope: AccountScope(remoteAccountID: "fixture-account-c", kind: .personal),
            credentialRef: UUID(uuidString: "C0000000-0000-0000-0000-000000000002")!
        )
        await assertStoreError(.accountNotFound) {
            try await store.update(unknownAccount)
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), committedData)

        for invalidOrder in [[accountA.id], [accountA.id, accountA.id], [accountA.id, unknownAccount.id]] {
            await assertStoreError(.invalidOrder) {
                try await store.reorder(invalidOrder)
            }
            XCTAssertEqual(try Data(contentsOf: fileURL), committedData)
        }

        let restored = try await AccountStore(fileURL: fileURL).load()
        XCTAssertEqual(restored, [accountA, accountB])
    }

    func testDuplicateLocalIDsInSavedDocumentCannotBeLoadedOrOverwritten() async throws {
        let fileURL = try isolatedFileURL()
        let accountA = makeAccountA()
        try await AccountStore(fileURL: fileURL).append(accountA)
        var document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        )
        let records = try XCTUnwrap(document["accounts"] as? [[String: Any]])
        document["accounts"] = records + records
        let duplicateData = try JSONSerialization.data(withJSONObject: document)
        try duplicateData.write(to: fileURL)
        let store = AccountStore(fileURL: fileURL)

        await assertStoreError(.duplicateLocalID) {
            _ = try await store.load()
        }
        await assertStoreError(.duplicateLocalID) {
            try await store.append(self.makeAccountB())
        }
        XCTAssertEqual(try Data(contentsOf: fileURL), duplicateData)
    }

    func testUnavailableStoragePathFailsAndCommittedAccountsCanBeRecovered() async throws {
        let fileURL = try isolatedFileURL()
        let accountA = makeAccountA()
        let accountB = makeAccountB()
        let store = AccountStore(fileURL: fileURL)
        try await store.append(accountA)
        try await store.append(accountB)
        let committedData = try Data(contentsOf: fileURL)
        let directory = fileURL.deletingLastPathComponent()
        let backupDirectory = directory.deletingLastPathComponent().appendingPathComponent("saved-directory")
        try FileManager.default.moveItem(at: directory, to: backupDirectory)
        try Data("普通文件，不能用作账户目录".utf8).write(to: directory)

        var updatedA = accountA
        updatedA.displayName = "不可用期间的修改"
        do {
            try await store.update(updatedA)
            XCTFail("存储路径不可用不能报告写入成功")
        } catch {
            // The failure can occur while reading or writing; neither may replace saved data.
        }

        try FileManager.default.removeItem(at: directory)
        try FileManager.default.moveItem(at: backupDirectory, to: directory)
        XCTAssertEqual(try Data(contentsOf: fileURL), committedData)
        let restored = try await AccountStore(fileURL: fileURL).load()
        XCTAssertEqual(restored, [accountA, accountB])
    }

    func testT57DemoAdditionRefreshAndAtomicClearPreserveRealAccounts() async throws {
        let url = try isolatedFileURL()
        let store = AccountStore(fileURL: url)
        let realA = makeAccountA(), realB = makeAccountB()
        try await store.append(realA)
        try await store.append(realB)
        let enabled = try await store.setDemoMode(true)
        let cursor = try XCTUnwrap(enabled.last)
        XCTAssertEqual(enabled.count, 3, "打开演示自动追加一个Cursor示例")
        XCTAssertTrue(cursor.isDemo && cursor.platform == .cursor)
        let a = try await store.addDemo(now: .now)
        let b = try await store.addDemo(now: .now)
        XCTAssertTrue(a.isDemo && b.isDemo)
        XCTAssertNotEqual(a.verifiedEmail, b.verifiedEmail)
        XCTAssertNotEqual(a.quotaSnapshot?.weekly.amount, b.quotaSnapshot?.weekly.amount)
        try await store.reorder([b.id, realB.id, cursor.id, a.id, realA.id])
        let refreshed = try await store.refreshDemo(a, now: .now.addingTimeInterval(5))
        XCTAssertNotEqual(a.quotaSnapshot, refreshed.quotaSnapshot)
        let beforeClear = try await AccountStore(fileURL: url).load()
        XCTAssertEqual(beforeClear, [b, realB, cursor, refreshed, realA])
        let mode = try await AccountStore(fileURL: url).demoModeEnabled()
        XCTAssertTrue(mode)
        let after = try await store.setDemoMode(false)
        XCTAssertEqual(after, [realB, realA])
        let reopened = try await AccountStore(fileURL: url).load()
        XCTAssertEqual(reopened, after)
        let off = try await AccountStore(fileURL: url).demoModeEnabled()
        XCTAssertFalse(off)
        do { _ = try await store.refreshDemo(a, now: .now); XCTFail("Deleted sample must not return") } catch {}
        do { _ = try await store.addDemo(now: .now); XCTFail("Disabled mode must reject samples") } catch {}
        _ = try await store.setDemoMode(true)
        let next = try await store.addDemo(now: .now)
        XCTAssertNotEqual(next.id, a.id)
        do { _ = try await store.refreshDemo(realA, now: .now); XCTFail("Real account must not be simulated") } catch {}
    }

    func testT96DemoSwitchProvidesOneLocalCursorMonthlySampleAndClearsIt() async throws {
        let url = try isolatedFileURL()
        let store = AccountStore(fileURL: url)
        let real = makeAccountA()
        try await store.append(real)
        let enabled = try await store.setDemoMode(true)
        XCTAssertEqual(enabled.first, real, "真实账户不动，示例追加在末尾")
        let cursor = try XCTUnwrap(enabled.last)
        XCTAssertEqual(enabled.count, 2)
        XCTAssertTrue(cursor.isDemo)
        XCTAssertEqual(cursor.provider, .cursor)
        XCTAssertEqual(cursor.product, .cursorSubscription)
        XCTAssertEqual(cursor.quotaState, .available)
        let snapshot = try XCTUnwrap(cursor.quotaSnapshot)
        XCTAssertEqual(snapshot.weekly.window, .monthly, "只有“本月”一条")
        XCTAssertEqual(snapshot.weekly.amount.usedPercent, 42)
        XCTAssertNotNil(snapshot.weekly.resetsAt)
        XCTAssertEqual(snapshot.fiveHours.isApplicable, false, "没有5小时")
        XCTAssertFalse(snapshot.fiveHours.shouldDisplay)
        let again = try await store.setDemoMode(true)
        XCTAssertEqual(again, enabled, "再次打开不重复追加")
        let codex = try await store.addDemo(now: .now)
        XCTAssertEqual(codex.platform, .codex, "连接入口仍添加Codex示例")
        let refreshed = try await store.refreshDemo(cursor, now: .now.addingTimeInterval(5))
        XCTAssertEqual(refreshed.quotaSnapshot?.weekly.window, .monthly)
        XCTAssertNotEqual(refreshed.quotaSnapshot?.weekly.amount, snapshot.weekly.amount, "演示刷新为本地模拟更新")
        XCTAssertEqual(refreshed.quotaSnapshot?.fiveHours.isApplicable, false)
        let reopened = try await AccountStore(fileURL: url).load()
        XCTAssertEqual(reopened, [real, refreshed, codex], "重开后保持")
        try await store.reorder([refreshed.id, real.id, codex.id])
        _ = try await store.markForDeletion(refreshed.id)
        try await store.finishDeletion(refreshed.id)
        let afterDelete = try await store.load()
        XCTAssertEqual(afterDelete, [real, codex], "排序后示例可单独删除")
        let off = try await store.setDemoMode(false)
        XCTAssertEqual(off, [real], "关闭清除全部演示账户")
        let cleared = try await AccountStore(fileURL: url).load()
        XCTAssertEqual(cleared, [real])
        do { _ = try await store.refreshDemo(cursor, now: .now); XCTFail("已清除的示例不能复活") } catch {}
    }

    func testT57LegacyFileDefaultsToRealAccountsAndDemoDisabled() async throws {
        let url = try isolatedFileURL()
        let store = AccountStore(fileURL: url)
        try await store.append(makeAccountA())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json.removeValue(forKey: "demoEnabled")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, [makeAccountA()])
        XCTAssertFalse(loaded[0].isDemo)
        let enabled = try await store.demoModeEnabled()
        XCTAssertFalse(enabled)
    }

    private func isolatedFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("T04-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("account-data", isDirectory: true)
            .appendingPathComponent("accounts.json")
    }

    private func makeAccountA() -> ConnectedAccount {
        ConnectedAccount(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!,
            remoteUserID: "fixture-user-a",
            verifiedEmail: "a@example.invalid",
            displayName: "A",
            scope: AccountScope(remoteAccountID: "fixture-account-a", kind: .personal, label: "A 个人"),
            credentialRef: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
            generation: 3
        )
    }

    private func makeAccountB() -> ConnectedAccount {
        ConnectedAccount(
            id: UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!,
            remoteUserID: "fixture-user-b",
            verifiedEmail: "b@example.invalid",
            displayName: "B",
            scope: AccountScope(remoteAccountID: "fixture-workspace-b", kind: .workspace, label: "B 工作区"),
            credentialRef: UUID(uuidString: "B0000000-0000-0000-0000-000000000002")!,
            generation: 9
        )
    }

    private func allKeys(in object: Any) -> [String] {
        if let dictionary = object as? [String: Any] {
            return Array(dictionary.keys) + dictionary.values.flatMap { allKeys(in: $0) }
        }
        if let array = object as? [Any] {
            return array.flatMap { allKeys(in: $0) }
        }
        return []
    }

    private func assertStoreError(
        _ expected: AccountStore.StoreError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("预期存储拒绝此操作：\(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? AccountStore.StoreError, expected, file: file, line: line)
        }
    }
}


@MainActor
final class SharedAutomaticRefreshTests: XCTestCase {
    private func files() throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T61-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return (directory.appendingPathComponent("legacy.json"), directory.appendingPathComponent("shared/accounts.json"))
    }
    private func account() -> ConnectedAccount {
        ConnectedAccount(verifiedEmail: "t61@example.invalid", scope: .init(remoteAccountID: "t61", kind: .personal), credentialRef: UUID())
    }

    func testT61ProductionMigrationPreservesBindingsAndReadableAuthorization() async throws {
        guard ProcessInfo.processInfo.environment["T61_LIVE_MIGRATION"] == "1" else {
            throw XCTSkip("只在升级验收时核对真实绑定和授权可读性，不查询额度")
        }
        struct Legacy: Decodable { let accounts: [ConnectedAccount] }
        let legacyURL = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: false).appendingPathComponent("SubscriptionUsage/accounts.json")
        let legacyData = try Data(contentsOf: legacyURL)
        let original = try JSONDecoder().decode(Legacy.self, from: legacyData).accounts
        let store = try AccountStore.applicationStore()
        let shared = try await store.load()
        XCTAssertTrue(original.map(\.id) == shared.map(\.id), "账户与顺序应保留；不输出身份")
        XCTAssertTrue(zip(original, shared).allSatisfy { old, new in
            old.credentialRef == new.credentialRef && old.generation == new.generation && old.scope == new.scope
                && old.remoteUserID == new.remoteUserID && old.verifiedEmail == new.verifiedEmail
        }, "绑定与授权引用保持")
        for account in shared where !account.isDemo && account.deletionPending != true {
            let payload = try await CredentialVault.applicationVault().load(for: .credential(account.credentialRef))
            XCTAssertTrue(payload != nil, "原授权仍可读取，不输出内容")
        }
        XCTAssertTrue(try Data(contentsOf: legacyURL) == legacyData, "保留原文件")
        print("T61 | 正式升级 | 账户顺序与绑定保持，原授权可读，原文件保留；未查询或比较真实额度")
    }

    func testMigrationPreservesIdentityAndDoesNotResurrectDeletedAccounts() async throws {
        let (legacy, shared) = try files(), original = account()
        try await AccountStore(fileURL: legacy).append(original)
        let originalBytes = try Data(contentsOf: legacy)
        let app = AccountStore(fileURL: shared, legacyURL: legacy)
        let first = try await app.load()
        XCTAssertEqual(first, [original])
        let widget = AccountStore(fileURL: shared)
        let restored = try await widget.load()
        XCTAssertEqual(restored, first)
        _ = try await app.markForDeletion(original.id)
        try await app.finishDeletion(original.id)
        let restarted = try await AccountStore(fileURL: shared, legacyURL: legacy).load()
        XCTAssertTrue(restarted.isEmpty)
        XCTAssertEqual(try Data(contentsOf: legacy), originalBytes)
    }

    func testUnreadableLegacyCannotMigrateAsAnEmptyInstallation() async throws {
        let (legacy, shared) = try files()
        // A directory at the source path produces a real read error, not ENOENT.
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        do { _ = try await AccountStore(fileURL: shared, legacyURL: legacy).load(); XCTFail("Must retain migration failure") }
        catch { XCTAssertFalse(FileManager.default.fileExists(atPath: shared.path)) }
    }

    func testCorruptSharedFileDoesNotFallBackToObsoleteLegacyData() async throws {
        let (legacy, shared) = try files()
        try await AccountStore(fileURL: legacy).append(account())
        _ = try await AccountStore(fileURL: shared, legacyURL: legacy).load()
        try Data("broken".utf8).write(to: shared)
        do { _ = try await AccountStore(fileURL: shared, legacyURL: legacy).load(); XCTFail("Must preserve the error") }
        catch { XCTAssertEqual(try Data(contentsOf: shared), Data("broken".utf8)) }
    }

    func testSeparateFileDescriptorBlocksMutationAndReleasesAfterOwnerExits() async throws {
        let (_, shared) = try files(), original = account()
        let app = AccountStore(fileURL: shared)
        try await app.append(original)
        var lease: SharedFileLease? = try SharedFileLease(url: shared.appendingPathExtension("lock"))
        do { _ = try await AccountStore(fileURL: shared).markForDeletion(original.id); XCTFail("Other writer must not enter") }
        catch SharedFileLease.LockError.busy { }
        withExtendedLifetime(lease) {}
        lease = nil
        let restored = try await app.load()
        XCTAssertEqual(restored, [original])
        _ = try await app.markForDeletion(original.id)
    }

    func testSuspendedQueryClaimExpiresAndOldOwnerCannotWriteOrRemoveNewClaim() async throws {
        let (_, shared) = try files(), original = account()
        let url = shared.appendingPathExtension("query")
        var old: SharedQueryLease? = try SharedQueryLease(url: url, at: Date(timeIntervalSince1970: 100))
        XCTAssertThrowsError(try SharedQueryLease(url: url, at: Date(timeIntervalSince1970: 101)))
        let replacement = try SharedQueryLease(url: url, at: Date(timeIntervalSince1970: 191))
        let store = AccountStore(fileURL: shared)
        try await store.append(original)
        let retained = try XCTUnwrap(old)
        do {
            _ = try await store.saveObservation(.init(planType: "free", observedAt: Date()), quota: .notApplicable,
                for: original, validateRequest: { try retained.validate(at: Date(timeIntervalSince1970: 192)) })
            XCTFail("Expired owner must not commit late success")
        } catch is CancellationError { }
        do {
            try await store.saveQuotaFailure(.refresh, for: original,
                validateRequest: { try retained.validate(at: Date(timeIntervalSince1970: 192)) })
            XCTFail("Expired owner must not commit late failure")
        } catch is CancellationError { }
        old = nil
        XCTAssertNoThrow(try replacement.validate(at: Date(timeIntervalSince1970: 192)))
        let restored = try await store.load()
        XCTAssertEqual(restored, [original])
        let failure = try await store.quotaFailure(for: original.id)
        XCTAssertNil(failure)
    }

    func testAppAndWidgetMergeConcurrentQueriesAndKeepNewestObservation() async throws {
        let (_, shared) = try files(), original = account()
        let app = AccountStore(fileURL: shared), widget = AccountStore(fileURL: shared)
        try await app.append(original)
        let worker = RefreshWorker(store: app)
        let foreground = CoordinatedQuotaUpdater(store: app, service: worker)
        let background = CoordinatedQuotaUpdater(store: widget, service: worker, opportunistic: true)
        async let a = foreground.update(original)
        async let b = background.update(original)
        let values = try await [a, b]
        XCTAssertEqual(values[0], values[1])
        let calls = await worker.calls
        XCTAssertEqual(calls, 1)
    }

    func testWaitingForegroundMustNotTreatAnotherProcessPartialFailureAsSuccess() async throws {
        let (_, shared) = try files(), original = account()
        let store = AccountStore(fileURL: shared)
        try await store.append(original)
        let worker = PartialObservationWorker(store: store)
        let widget = CoordinatedQuotaUpdater(store: store, service: worker, opportunistic: true)
        let app = CoordinatedQuotaUpdater(store: store, service: worker)
        let first = Task { try await widget.update(original) }
        try await Task.sleep(for: .milliseconds(50))
        let recovered = try await app.update(original)
        do { _ = try await first.value; XCTFail("First query must fail") } catch CodexQuotaError.failed {}
        let calls = await worker.calls
        XCTAssertEqual(calls, 2, "A changed plan observation does not prove a successful quota query")
        XCTAssertEqual(recovered.quotaState, .notApplicable)
    }

    func testAutomaticFailureIsNotSuccessAndManualRetryIsNotThrottled() async throws {
        let (_, shared) = try files()
        var original = account()
        original.subscription = .init(planType: "free", observedAt: Date(timeIntervalSince1970: 100))
        original.quotaState = .notApplicable
        let store = AccountStore(fileURL: shared)
        try await store.append(original)
        let worker = RefreshWorker(store: store, fail: true)
        let automatic = CoordinatedQuotaUpdater(store: store, service: worker, opportunistic: true)
        do { _ = try await automatic.update(original); XCTFail("Expected failure") } catch CodexQuotaError.failed {}
        let cached = try await automatic.update(original)
        XCTAssertEqual(cached, original)
        let manual = CoordinatedQuotaUpdater(store: store, service: worker)
        do { _ = try await manual.update(original); XCTFail("Expected failure") } catch CodexQuotaError.failed {}
        let calls = await worker.calls
        XCTAssertEqual(calls, 2)
        let stored = try await store.load()
        XCTAssertEqual(stored, [original])
    }

    func testDeletedBindingCannotBeQueriedByStaleWidget() async throws {
        let (_, shared) = try files(), original = account()
        let store = AccountStore(fileURL: shared)
        try await store.append(original)
        _ = try await store.markForDeletion(original.id)
        let worker = RefreshWorker(store: store)
        do { _ = try await CoordinatedQuotaUpdater(store: store, service: worker).update(original); XCTFail("Deleted binding") }
        catch AccountStore.StoreError.staleQuotaContext { }
        let calls = await worker.calls
        XCTAssertEqual(calls, 0)
    }
}

private actor RefreshWorker: CodexQuotaUpdating {
    let store: AccountStore
    let fail: Bool
    var calls = 0
    init(store: AccountStore, fail: Bool = false) { self.store = store; self.fail = fail }
    func update(_ account: ConnectedAccount) async throws -> ConnectedAccount {
        calls += 1
        try await Task.sleep(for: .milliseconds(150))
        if fail { throw CodexQuotaError.failed }
        return try await store.saveObservation(.init(planType: "free", observedAt: Date()), quota: .notApplicable, for: account)
    }
}

private actor PartialObservationWorker: CodexQuotaUpdating {
    let store: AccountStore
    var calls = 0
    init(store: AccountStore) { self.store = store }
    func update(_ account: ConnectedAccount) async throws -> ConnectedAccount {
        calls += 1
        let first = calls == 1
        try await Task.sleep(for: .milliseconds(150))
        let result = try await store.saveObservation(.init(planType: "free", observedAt: Date()),
            quota: first ? .failed : .notApplicable, for: account)
        if first { throw CodexQuotaError.failed }
        return result
    }
}
