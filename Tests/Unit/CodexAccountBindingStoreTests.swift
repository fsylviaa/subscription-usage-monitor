import Foundation
import Security
import XCTest
@testable import SubscriptionUsage

@MainActor
final class CodexAccountBindingStoreTests: XCTestCase {
    func testVerifiedBindingPersistsIdentityAndCredentialWithoutInventedQuota() async throws {
        let fixture = try isolatedFixture()
        let login = verifiedLogin()
        let saved = try await fixture.binding.save(login)

        let reopened = CodexAccountBindingStore(
            accountStore: AccountStore(fileURL: fixture.fileURL),
            vault: CredentialVault(service: fixture.service)
        )
        let restored = try await reopened.load()
        let credentials = try await CredentialVault(service: fixture.service)
            .load(for: .credential(saved.credentialRef))
        XCTAssertEqual(restored, [saved])
        XCTAssertEqual(saved.remoteUserID, login.remoteUserID)
        XCTAssertEqual(saved.verifiedEmail, login.email)
        XCTAssertEqual(saved.scope, login.scope)
        XCTAssertNil(saved.displayName)
        XCTAssertEqual(saved.quotaState, .notFetched)
        XCTAssertTrue(credentials == login.credentials, "正式授权完整读回，不展开内容")

        let ordinaryFile = try Data(contentsOf: fixture.fileURL)
        XCTAssertNil(ordinaryFile.range(of: login.credentials.data))
        let text = String(decoding: ordinaryFile, as: UTF8.self)
        for forbidden in ["access_token", "refresh_token", "remaining", "lastSuccess", "plan"] {
            XCTAssertFalse(text.contains(forbidden))
        }
        print("T08 | 核验后保存并新建实例读取 | 身份和授权匹配；尚未获取额度；无编造姓名或套餐")
    }

    func testT16SecondBindingAppendsAndRetainsFirstCredential() async throws {
        let fixture = try isolatedFixture()
        let firstLogin = verifiedLogin()
        let first = try await fixture.binding.save(firstLogin)
        let secondLogin = verifiedLogin(email: "other@example.invalid")
        let second = try await fixture.binding.save(secondLogin)
        let restored = try await AccountStore(fileURL: fixture.fileURL).load()
        XCTAssertEqual(restored, [first, second])
        XCTAssertNotEqual(first.credentialRef, second.credentialRef)
        let a = try await fixture.vault.load(for: .credential(first.credentialRef))
        let b = try await fixture.vault.load(for: .credential(second.credentialRef))
        XCTAssertTrue(a == firstLogin.credentials)
        XCTAssertTrue(b == secondLogin.credentials)
    }

    func testT16CommittedTransactionIsNotAddedTwice() async throws {
        let fixture = try isolatedFixture()
        let id = UUID()
        let first = try await fixture.binding.save(verifiedLogin(), transactionID: id)
        let again = try await fixture.binding.save(verifiedLogin(), transactionID: id)
        XCTAssertEqual(first, again)
        XCTAssertEqual(fixture.client.addCount, 1)
    }

    func testCredentialSaveFailureCannotPublishAnAccount() async throws {
        let fixture = try isolatedFixture(addStatus: errSecNotAvailable)
        do {
            _ = try await fixture.binding.save(verifiedLogin())
            XCTFail("授权未保存不能形成账户")
        } catch {
            XCTAssertEqual(error as? CredentialVault.VaultError, .temporarilyUnavailable)
        }
        let accounts = try await fixture.binding.load()
        XCTAssertTrue(accounts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
        XCTAssertTrue(fixture.client.successfulQueries.isEmpty)
    }

    func testUnreadableAccountFileIsPreservedBeforeAnyCredentialWrite() async throws {
        let fixture = try isolatedFixture()
        try FileManager.default.createDirectory(
            at: fixture.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let original = Data("damaged-account-file".utf8)
        try original.write(to: fixture.fileURL)
        do {
            _ = try await fixture.binding.save(verifiedLogin())
            XCTFail("不能把损坏文件当空账户覆盖")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), original)
        XCTAssertEqual(fixture.client.addCount, 0)
    }

    func testAccountCommitFailureRemovesOnlyNewCredential() async throws {
        let fixture = try isolatedFixture()
        let directory = fixture.fileURL.deletingLastPathComponent()
        fixture.client.afterSuccessfulAdd = {
            // The preflight found no account; make only this test's parent path
            // unavailable before the subsequent account-file transaction.
            try? Data("blocked".utf8).write(to: directory)
        }
        do {
            _ = try await fixture.binding.save(verifiedLogin())
            XCTFail("账户落盘失败不能报告成功")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }
        XCTAssertEqual(fixture.client.addCount, 1)
        XCTAssertEqual(fixture.client.deleteCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
        assertCreatedCredentialsAbsent(fixture.client)
        print("T08 | 授权保存后账户写入失败 | 没有正式账户；本次新授权已回滚")
    }

    func testCancellationAfterCredentialSaveRollsBackBeforeAccountCommit() async throws {
        let fixture = try isolatedFixture()
        fixture.client.afterSuccessfulAdd = {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let save = Task { try await fixture.binding.save(self.verifiedLogin()) }
        do {
            _ = try await save.value
            XCTFail("提交前取消不能形成正式账户")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let accounts = try await fixture.binding.load()
        XCTAssertTrue(accounts.isEmpty)
        XCTAssertEqual(fixture.client.addCount, 1)
        XCTAssertEqual(fixture.client.deleteCount, 1)
        assertCreatedCredentialsAbsent(fixture.client)
        print("T08 | 保存授权后立即取消 | 不增加账户；本次新授权已回滚")
    }

    func testAlreadyCancelledSaveDoesNotTouchStorage() async throws {
        let fixture = try isolatedFixture()
        let save = Task { () throws -> ConnectedAccount in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await fixture.binding.save(self.verifiedLogin())
        }
        do {
            _ = try await save.value
            XCTFail("已取消请求不能保存")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(fixture.client.addCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    func testT16ConcurrentDifferentBindingsRetainBothAccountsAndCredentials() async throws {
        let fixture = try isolatedFixture()
        let otherBinding = CodexAccountBindingStore(accountStore: fixture.accounts, vault: fixture.vault)
        let first = Task { try await fixture.binding.save(self.verifiedLogin()) }
        let second = Task { try await otherBinding.save(self.verifiedLogin(email: "other@example.invalid")) }
        let results = await [first.result, second.result]
        let successes = results.compactMap { try? $0.get() }
        XCTAssertEqual(successes.count, 2)
        let accounts = try await fixture.binding.load()
        XCTAssertEqual(Set(accounts.map(\.id)), Set(successes.map(\.id)))
        let remaining = fixture.client.successfulQueries.filter {
            SystemKeychainClient().copyMatching($0).0 == errSecSuccess
        }
        XCTAssertEqual(remaining.count, 2)
    }

    func testRollbackFailureIsReportedWithoutPublishingAnAccount() async throws {
        let fixture = try isolatedFixture(deleteStatus: errSecNotAvailable)
        fixture.client.afterSuccessfulAdd = {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        let save = Task { try await fixture.binding.save(self.verifiedLogin()) }
        do {
            _ = try await save.value
            XCTFail("回滚失败不能报告连接成功")
        } catch {
            XCTAssertEqual(error as? CodexAccountBindingStore.BindingError, .credentialCleanupFailed)
        }
        let accounts = try await fixture.binding.load()
        XCTAssertTrue(accounts.isEmpty)
        XCTAssertEqual(fixture.client.deleteCount, 1)
        // Teardown bypasses this injected fault and deletes the exact test item.
    }

    func testT16SixLoginsKeepOwnCredentialsQuotaOrderAndReopenSnapshots() async throws {
        let f = multiFixture()
        let flow = f.makeFlow()
        await flow.loadAccounts()
        var saved: [ConnectedAccount] = []
        for index in 1...6 {
            try await addAccount(flow)
            XCTAssertEqual(flow.accounts.count, index)
            XCTAssertEqual(Array(flow.accounts.dropLast()), saved)
            let account = try XCTUnwrap(flow.accounts.last)
            XCTAssertEqual(account.verifiedEmail, "account-\(index)@example.invalid")
            XCTAssertEqual(account.quotaSnapshot?.weekly.amount.remainingPercent, index == 1 ? 80 : 35)
            XCTAssertEqual(account.quotaSnapshot?.fiveHours.amount.remainingPercent, index == 1 ? 70 : 25)
            saved = flow.accounts
        }
        let reopened = f.makeFlow()
        await reopened.loadAccounts()
        await reopened.waitForInitialQuota()
        XCTAssertEqual(reopened.accounts, saved)
        XCTAssertEqual(Set(saved.map(\.credentialRef)).count, 6)
        let requests = await f.server.requests
        XCTAssertEqual(requests.count, 6, "已有成功快照重开不会重查或串号")
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "ChatGPT-Account-Id") }, (1...6).map { "t16-\($0)" })
        print("T16 | 连续添加6账户→重开 | 身份、独立授权、数值、时间、顺序保留；作用域与授权逐个匹配")
    }

    func testT16SecondQuotaFailureKeepsFirstExactSnapshotAndSecondIdentity() async throws {
        let f = multiFixture(failSecond: true)
        let flow = f.makeFlow()
        await flow.loadAccounts()
        try await addAccount(flow)
        let first = try XCTUnwrap(flow.accounts.first)
        try await addAccount(flow, fails: true)
        XCTAssertEqual(flow.accounts.count, 2)
        XCTAssertEqual(flow.accounts.first, first)
        let second = try XCTUnwrap(flow.accounts.last)
        XCTAssertEqual(second.verifiedEmail, "account-2@example.invalid")
        XCTAssertEqual(second.quotaState, .notFetched)
        XCTAssertNil(second.quotaSnapshot)
        XCTAssertEqual(flow.quotaFailureID, second.id)
        let saved = try await f.store.load()
        XCTAssertEqual(saved, [first, second])
        flow.cancel()
        let reopened = f.makeFlow()
        await reopened.loadAccounts()
        await reopened.waitForInitialQuota()
        XCTAssertEqual(reopened.accounts, [first, second])
        XCTAssertEqual(reopened.quotaFailureID, second.id, "重开也会补查第二个未获取账户")
        print("T16 | B首次查询失败及重开 | A身份、额度、原成功时间完全不变；B保留且只重试B")
    }

    func testT16SecondLoginCancellationLeavesFirstUnchanged() async throws {
        let f = multiFixture()
        let flow = f.makeFlow()
        await flow.loadAccounts()
        try await addAccount(flow)
        let original = flow.accounts
        try await XCTUnwrap(flow.begin()).value
        flow.cancel()
        try await Task.sleep(for: .milliseconds(100))
        let stored = try await f.store.load()
        XCTAssertEqual(flow.accounts, original)
        XCTAssertEqual(stored, original)
    }

    func testT16PendingSecondLoginRestoresOriginalTransactionWithFirstVisible() async throws {
        let f = multiFixture()
        let flow = f.makeFlow()
        await flow.loadAccounts()
        try await addAccount(flow)
        let first = try XCTUnwrap(flow.accounts.first)
        // Seed a durable second login, as if its process ended before approval.
        let auth = try await f.server.requestAuthorization()
        try await CodexLoginTransactionStore(vault: f.vault).save(auth)
        let reopened = f.makeFlow()
        await reopened.loadAccounts()
        XCTAssertEqual(reopened.accounts, [first])
        XCTAssertEqual(reopened.state, .code(auth))
        await reopened.openWebsite()
        try await waitUntil { reopened.accounts.count == 2 && reopened.state == .idle && reopened.quotaUpdatingID == nil }
        XCTAssertEqual(reopened.accounts.first, first)
        XCTAssertEqual(reopened.accounts.last?.loginTransactionID, auth.transactionID)
        // Crash after commit but before cleanup: do not append the same transaction again.
        try await CodexLoginTransactionStore(vault: f.vault).save(auth)
        let again = f.makeFlow()
        await again.loadAccounts()
        XCTAssertEqual(again.accounts, reopened.accounts)
        XCTAssertFalse(again.isPresented)
        let pending = try await CodexLoginTransactionStore(vault: f.vault).load()
        XCTAssertNil(pending)
        print("T16 | 添加B中断后重开／提交后残留 | A始终在；原事务完成B；已提交事务不会重复添加")
    }

    func testT16ReopenQueriesEveryUnfetchedAccountWithOwnScope() async throws {
        let f = multiFixture(failSecond: true)
        for index in 1...3 {
            let tokens = try await f.server.exchange(.init(code: "\(index)", verifier: String(repeating: "v", count: 43)))
            let login = try await f.server.verify(tokens)
            _ = try await f.bindings.save(login)
        }
        let flow = f.makeFlow()
        await flow.loadAccounts()
        await flow.waitForInitialQuota()
        XCTAssertEqual(flow.accounts.map(\.quotaState), [.available, .notFetched, .available])
        XCTAssertEqual(flow.quotaFailureID, flow.accounts[1].id, "C成功不应清除B的失败与重试入口")
        XCTAssertEqual(Set(flow.quotaFailures.keys), [flow.accounts[1].id])
        let requests = await f.server.requests
        XCTAssertEqual(requests.map { $0.value(forHTTPHeaderField: "ChatGPT-Account-Id") }, ["t16-1", "t16-2", "t16-3"])
        XCTAssertNil(flow.accounts[1].quotaSnapshot)
        XCTAssertEqual(flow.accounts[2].quotaSnapshot?.weekly.amount.remainingPercent, 35)
    }

    func testT16CancelledSecondCredentialSavePreservesFirstFileAndAuthorization() async throws {
        let fixture = try isolatedFixture()
        let login = verifiedLogin()
        let first = try await fixture.binding.save(login)
        let bytes = try Data(contentsOf: fixture.fileURL)
        fixture.client.afterSuccessfulAdd = { withUnsafeCurrentTask { $0?.cancel() } }
        let task = Task { try await fixture.binding.save(self.verifiedLogin(email: "second@example.invalid")) }
        do { _ = try await task.value; XCTFail("取消不能提交B") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), bytes)
        let credential = try await fixture.vault.load(for: .credential(first.credentialRef))
        XCTAssertTrue(credential == login.credentials)
        XCTAssertEqual(fixture.client.deleteCount, 1)
    }

    func testT17MovePersistsFullRecordsAndNewLoginAppendsAfterManualOrder() async throws {
        let f = multiFixture()
        let flow = f.makeFlow()
        await flow.loadAccounts()
        for _ in 0..<3 { try await addAccount(flow) }
        let original = flow.accounts
        var credentials: [UUID: CredentialPayload] = [:]
        for account in original {
            credentials[account.id] = try await f.vault.load(for: .credential(account.credentialRef))
        }
        try await XCTUnwrap(flow.moveAccounts(from: IndexSet(integer: 2), to: 1)).value
        XCTAssertEqual(flow.accounts, [original[0], original[2], original[1]])
        try await XCTUnwrap(flow.moveAccounts(from: IndexSet(integer: 2), to: 0)).value
        XCTAssertEqual(flow.accounts, [original[1], original[0], original[2]])
        try await XCTUnwrap(flow.moveAccounts(from: IndexSet(integer: 0), to: 3)).value
        XCTAssertEqual(flow.accounts, [original[0], original[2], original[1]])
        try await addAccount(flow)
        XCTAssertEqual(Array(flow.accounts.prefix(3)), [original[0], original[2], original[1]])
        XCTAssertEqual(flow.accounts.last?.verifiedEmail, "account-4@example.invalid")
        let reopened = f.makeFlow()
        await reopened.loadAccounts()
        XCTAssertEqual(reopened.accounts, flow.accounts, "全记录对照包含额度、原成功时间、作用域及代次")
        for account in original {
            let saved = try await f.vault.load(for: .credential(account.credentialRef))
            XCTAssertTrue(saved == credentials[account.id], "排序不改授权包")
        }
        print("T17 | C移到B前、末项置顶、首项移末、再添加D及重开 | 顺序准确；账户完整数据与授权不变")
    }

    func testT17SaveFailureKeepsPublishedOrderAndCanRetry() async throws {
        let f = multiFixture()
        let flow = f.makeFlow()
        await flow.loadAccounts()
        for _ in 0..<2 { try await addAccount(flow) }
        let original = flow.accounts
        let backup = f.directory.appendingPathExtension("backup")
        try FileManager.default.moveItem(at: f.directory, to: backup)
        try Data("not a directory".utf8).write(to: f.directory)
        await flow.moveAccounts(from: IndexSet(integer: 1), to: 0)?.value
        XCTAssertEqual(flow.accounts, original)
        XCTAssertTrue(flow.accountOrderFailed)
        XCTAssertFalse(flow.reorderingAccounts)
        flow.dismissAccountOrderFailure()
        XCTAssertFalse(flow.accountOrderFailed)
        try FileManager.default.removeItem(at: f.directory)
        try FileManager.default.moveItem(at: backup, to: f.directory)
        let disk = try await f.store.load()
        XCTAssertEqual(disk, original)
        try await XCTUnwrap(flow.moveAccounts(from: IndexSet(integer: 1), to: 0)).value
        XCTAssertEqual(flow.accounts, original.reversed())
        XCTAssertFalse(flow.accountOrderFailed)
        print("T17 | 存储不可用后移动→恢复重试 | 失败保留旧顺序、提示失败；恢复后可保存")
    }

    func testT17SingleAccountAndInvalidOrNoOpMovesDoNothing() async throws {
        let f = multiFixture()
        let flow = f.makeFlow()
        await flow.loadAccounts()
        XCTAssertFalse(flow.canReorderAccounts)
        try await addAccount(flow)
        XCTAssertFalse(flow.canReorderAccounts)
        XCTAssertNil(flow.moveAccounts(from: IndexSet(integer: 0), to: 1))
        try await addAccount(flow)
        let original = flow.accounts
        for (offsets, destination) in [(IndexSet(), 0), (IndexSet(integer: 9), 0),
                                        (IndexSet(integer: 0), -1), (IndexSet(integer: 0), 3),
                                        (IndexSet(integer: 0), 1)] {
            XCTAssertNil(flow.moveAccounts(from: offsets, to: destination))
        }
        XCTAssertEqual(flow.accounts, original)
        flow.showPlatformPicker()
        XCTAssertFalse(flow.canReorderAccounts)
        XCTAssertNil(flow.moveAccounts(from: IndexSet(integer: 1), to: 0))
        flow.cancel()
    }

    func testT17PublishesOnlyAfterSaveAndPreventsOverlappingMovesOrLogin() async throws {
        let f = multiFixture()
        let seed = f.makeFlow()
        await seed.loadAccounts()
        for _ in 0..<2 { try await addAccount(seed) }
        let delayed = T17DelayedOrdering(base: f.bindings)
        let flow = CodexConnectionFlow(transactions: CodexLoginTransactionStore(vault: f.vault), bindings: delayed)
        await flow.loadAccounts()
        let original = flow.accounts
        let move = try XCTUnwrap(flow.moveAccounts(from: IndexSet(integer: 1), to: 0))
        try await waitUntil { delayed.waiting != nil }
        XCTAssertEqual(flow.accounts, original, "保存完成前不发布新顺序")
        XCTAssertTrue(flow.reorderingAccounts)
        XCTAssertFalse(flow.canConnect)
        XCTAssertNil(flow.begin())
        XCTAssertNil(flow.moveAccounts(from: IndexSet(integer: 0), to: 2))
        delayed.waiting?.resume(); delayed.waiting = nil
        await move.value
        XCTAssertEqual(flow.accounts, original.reversed())
        XCTAssertTrue(flow.canConnect)
        XCTAssertTrue(flow.canReorderAccounts)
    }

    private func multiFixture(failSecond: Bool = false) -> T16MultiAccountFixture {
        let fixture = T16MultiAccountFixture(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("T16-unit-\(UUID())"), failSecond: failSecond)
        addTeardownBlock { try await fixture.cleanup() }
        return fixture
    }

    private func addAccount(_ flow: CodexConnectionFlow, fails: Bool = false) async throws {
        let oldCount = flow.accounts.count
        try await XCTUnwrap(flow.begin()).value
        await flow.openWebsite()
        try await waitUntil {
            flow.accounts.count == oldCount + 1 && flow.quotaUpdatingID == nil
                && (fails ? flow.quotaFailureID == flow.accounts.last?.id : flow.state == .idle)
        }
        XCTAssertEqual(flow.isPresented, fails)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("T16流程未在10秒内达到预期")
    }

    private func verifiedLogin(email: String = "verified@example.invalid") -> CodexVerifiedLogin {
        .fixture(
            remoteUserID: "fixture-user-t08",
            email: email,
            scope: AccountScope(remoteAccountID: "fixture-account-t08", kind: .personal),
            credentials: CredentialPayload(data: Data("T08-runtime-only-\(UUID().uuidString)".utf8))
        )
    }

    func testT21RemovalDeletesOnlyTargetCredentialAndSurvivesReopen() async throws {
        let f = try isolatedFixture()
        let a = try await f.binding.save(verifiedLogin())
        let b = try await f.binding.save(verifiedLogin(email: "other@example.invalid"))
        try await f.binding.removeAccount(a.id)
        let rows = try await f.binding.load()
        XCTAssertEqual(rows, [b])
        let removed = try await f.vault.load(for: .credential(a.credentialRef))
        let retained = try await f.vault.load(for: .credential(b.credentialRef))
        XCTAssertNil(removed)
        XCTAssertNotNil(retained)
        try await f.binding.removeAccount(a.id)
        try await f.binding.removeAccount(b.id)
        let empty = try await f.binding.load()
        XCTAssertTrue(empty.isEmpty)
    }

    func testT21InterruptedCleanupRetainsReferencesAndReopenFinishes() async throws {
        let f = try isolatedFixture(deleteStatus: errSecNotAvailable)
        let account = try await f.binding.save(verifiedLogin())
        do { try await f.binding.removeAccount(account.id); XCTFail("Cleanup failure must surface") } catch {}
        let marked = try await f.accounts.load()
        XCTAssertEqual(marked.first?.id, account.id)
        XCTAssertEqual(marked.first?.deletionPending, true)
        let recovered = CodexAccountBindingStore(accountStore: f.accounts, vault: CredentialVault(service: f.service))
        let rows = try await recovered.load()
        XCTAssertTrue(rows.isEmpty)
        let credential = try await f.vault.load(for: .credential(account.credentialRef))
        XCTAssertNil(credential)
    }

    private func isolatedFixture(
        addStatus: OSStatus? = nil,
        deleteStatus: OSStatus? = nil
    ) throws -> BindingFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("T08-binding-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fileURL = root.appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent("accounts.json")
        let service = "com.iceflying.SubscriptionUsage.Tests.T08.Binding.\(UUID().uuidString)"
        let client = BindingKeychainClient(addStatus: addStatus, deleteStatus: deleteStatus)
        let vault = CredentialVault(service: service, client: client)
        let accounts = AccountStore(fileURL: fileURL)
        addTeardownBlock {
            for query in client.successfulQueries {
                let status = SecItemDelete(query as CFDictionary)
                XCTAssertTrue(status == errSecSuccess || status == errSecItemNotFound)
            }
            try FileManager.default.removeItem(at: root)
        }
        return BindingFixture(
            fileURL: fileURL, service: service, client: client, vault: vault, accounts: accounts,
            binding: CodexAccountBindingStore(accountStore: accounts, vault: vault)
        )
    }

    private func assertCreatedCredentialsAbsent(_ client: BindingKeychainClient) {
        for query in client.successfulQueries {
            XCTAssertEqual(SystemKeychainClient().copyMatching(query).0, errSecItemNotFound)
        }
    }
}

private struct BindingFixture {
    let fileURL: URL
    let service: String
    let client: BindingKeychainClient
    let vault: CredentialVault
    let accounts: AccountStore
    let binding: CodexAccountBindingStore
}

/// Uses only a random, test-owned service. The synchronous hook allows exact
/// cancellation/failure injection after Keychain save and before account commit.
private final class BindingKeychainClient: KeychainClient, @unchecked Sendable {
    private let lock = NSLock()
    private let system = SystemKeychainClient()
    private let addStatus: OSStatus?
    private let deleteStatus: OSStatus?
    private var queries: [[String: Any]] = []
    private var additions = 0
    private var deletions = 0
    private var afterAdd: (@Sendable () -> Void)?

    init(addStatus: OSStatus?, deleteStatus: OSStatus?) {
        self.addStatus = addStatus
        self.deleteStatus = deleteStatus
    }

    var afterSuccessfulAdd: (@Sendable () -> Void)? {
        get { lock.withLock { afterAdd } }
        set { lock.withLock { afterAdd = newValue } }
    }
    var successfulQueries: [[String: Any]] { lock.withLock { queries } }
    var addCount: Int { lock.withLock { additions } }
    var deleteCount: Int { lock.withLock { deletions } }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) { system.copyMatching(query) }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock { additions += 1 }
        if let addStatus { return addStatus }
        let status = system.add(attributes)
        if status == errSecSuccess {
            var query = attributes
            query.removeValue(forKey: kSecValueData as String)
            query.removeValue(forKey: kSecAttrAccessible as String)
            lock.withLock { queries.append(query) }
            afterSuccessfulAdd?()
        }
        return status
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        system.update(query, attributes: attributes)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lock.withLock { deletions += 1 }
        return deleteStatus ?? system.delete(query)
    }
}

@MainActor
private final class T17DelayedOrdering: CodexAccountBinding, AccountOrdering {
    let base: CodexAccountBindingStore
    var waiting: CheckedContinuation<Void, Never>?
    init(base: CodexAccountBindingStore) { self.base = base }
    func load() async throws -> [ConnectedAccount] { try await base.load() }
    func save(_ login: CodexVerifiedLogin) async throws -> ConnectedAccount { try await base.save(login) }
    func reorder(_ ids: [UUID]) async throws {
        await withCheckedContinuation { waiting = $0 }
        try await base.reorder(ids)
    }
}
