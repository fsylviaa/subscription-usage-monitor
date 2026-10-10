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
        _ = try await store.setDemoMode(true)
        let a = try await store.addDemo(now: .now)
        let b = try await store.addDemo(now: .now)
        XCTAssertTrue(a.isDemo && b.isDemo)
        XCTAssertNotEqual(a.verifiedEmail, b.verifiedEmail)
        XCTAssertNotEqual(a.quotaSnapshot?.weekly.amount, b.quotaSnapshot?.weekly.amount)
        try await store.reorder([b.id, realB.id, a.id, realA.id])
        let refreshed = try await store.refreshDemo(a, now: .now.addingTimeInterval(5))
        XCTAssertNotEqual(a.quotaSnapshot, refreshed.quotaSnapshot)
        let beforeClear = try await AccountStore(fileURL: url).load()
        XCTAssertEqual(beforeClear, [b, realB, refreshed, realA])
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
