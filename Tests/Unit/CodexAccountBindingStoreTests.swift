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

    func testExistingAccountAndCredentialAreNotReplacedByAnotherLogin() async throws {
        let fixture = try isolatedFixture()
        let firstLogin = verifiedLogin()
        let first = try await fixture.binding.save(firstLogin)
        let originalFile = try Data(contentsOf: fixture.fileURL)
        let originalAddCount = fixture.client.addCount

        do {
            _ = try await fixture.binding.save(verifiedLogin(email: "other@example.invalid"))
            XCTFail("T08 不能覆盖或追加已有账户")
        } catch {
            XCTAssertEqual(error as? AccountStore.StoreError, .accountAlreadyExists)
        }

        let restored = try await fixture.binding.load()
        let credentials = try await fixture.vault.load(for: .credential(first.credentialRef))
        XCTAssertEqual(restored, [first])
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), originalFile)
        XCTAssertTrue(credentials == firstLogin.credentials)
        XCTAssertEqual(fixture.client.addCount, originalAddCount)
        print("T08 | 已有账户时收到另一份核验结果 | 原账户和授权完整保留")
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

    func testConcurrentFirstBindingsCreateExactlyOneAccountAndCredential() async throws {
        let fixture = try isolatedFixture()
        let otherBinding = CodexAccountBindingStore(accountStore: fixture.accounts, vault: fixture.vault)
        let first = Task { try await fixture.binding.save(self.verifiedLogin()) }
        let second = Task { try await otherBinding.save(self.verifiedLogin(email: "other@example.invalid")) }
        let results = await [first.result, second.result]
        let successes = results.compactMap { try? $0.get() }
        XCTAssertEqual(successes.count, 1)
        let accounts = try await fixture.binding.load()
        XCTAssertEqual(accounts, successes)
        let remaining = fixture.client.successfulQueries.filter {
            SystemKeychainClient().copyMatching($0).0 == errSecSuccess
        }
        XCTAssertEqual(remaining.count, 1)
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

    private func verifiedLogin(email: String = "verified@example.invalid") -> CodexVerifiedLogin {
        .fixture(
            remoteUserID: "fixture-user-t08",
            email: email,
            scope: AccountScope(remoteAccountID: "fixture-account-t08", kind: .personal),
            credentials: CredentialPayload(data: Data("T08-runtime-only-\(UUID().uuidString)".utf8))
        )
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
