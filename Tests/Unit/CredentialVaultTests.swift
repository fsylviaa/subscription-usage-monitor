import Foundation
import Security
import XCTest
@testable import SubscriptionUsage

@MainActor
final class CredentialVaultTests: XCTestCase {
    func testNewVaultRestoresIndependentPackagesForAAndB() async throws {
        let scope = isolatedScope()
        let payloadA = makePayload()
        let payloadB = makePayload()
        do {
            let writer = CredentialVault(service: scope.service)
            try await writer.save(payloadA, for: scope.accountA)
            try await writer.save(payloadB, for: scope.accountB)
        }

        let reader = CredentialVault(service: scope.service)
        let restoredA = try await reader.load(for: scope.accountA)
        let restoredB = try await reader.load(for: scope.accountB)
        XCTAssertTrue(restoredA == payloadA, "A 存在且匹配")
        XCTAssertTrue(restoredB == payloadB, "B 存在且匹配")
        print("T05 | 保存 A、B 后新建读取实例 | A 存在且匹配；B 存在且匹配")
    }

    func testReplacingAReplacesWholePackageAndPreservesB() async throws {
        let scope = isolatedScope()
        let vault = CredentialVault(service: scope.service)
        let originalA = makePayload()
        let replacementA = makePayload()
        let payloadB = makePayload()
        try await vault.save(originalA, for: scope.accountA)
        try await vault.save(payloadB, for: scope.accountB)
        try await vault.save(replacementA, for: scope.accountA)

        let reader = CredentialVault(service: scope.service)
        let restoredA = try await reader.load(for: scope.accountA)
        let restoredB = try await reader.load(for: scope.accountB)
        XCTAssertTrue(restoredA == replacementA, "A 完整包匹配新值")
        XCTAssertTrue(restoredA != originalA, "A 不再匹配旧值")
        XCTAssertTrue(restoredB == payloadB, "B 保持匹配")
        print("T05 | 只替换 A 的整份授权 | A 匹配新值；B 匹配原值")
    }

    func testRemovingAIsExactAndAlreadyAbsentRemovalIsSafe() async throws {
        let scope = isolatedScope()
        let vault = CredentialVault(service: scope.service)
        let payloadB = makePayload()
        try await vault.save(makePayload(), for: scope.accountA)
        try await vault.save(payloadB, for: scope.accountB)
        try await vault.remove(for: scope.accountA)
        try await vault.remove(for: scope.accountA)

        let reader = CredentialVault(service: scope.service)
        let restoredA = try await reader.load(for: scope.accountA)
        let restoredB = try await reader.load(for: scope.accountB)
        XCTAssertTrue(restoredA == nil, "A 不存在")
        XCTAssertTrue(restoredB == payloadB, "B 存在且匹配")
        print("T05 | 只删除 A 并重复删除 | A 不存在；B 存在且匹配")
    }

    func testFormalAndTemporaryEntriesWithSameUUIDRemainIndependent() async throws {
        let scope = isolatedScope()
        let vault = CredentialVault(service: scope.service)
        let formal = makePayload()
        let temporary = makePayload()
        let updatedTemporary = makePayload()
        try await vault.save(formal, for: scope.accountA)
        try await vault.save(temporary, for: scope.transactionA)
        try await vault.save(updatedTemporary, for: scope.transactionA)

        let restoredFormal = try await vault.load(for: scope.accountA)
        let restoredTemporary = try await vault.load(for: scope.transactionA)
        XCTAssertTrue(restoredFormal == formal, "正式条目仍匹配")
        XCTAssertTrue(restoredTemporary == updatedTemporary, "临时条目独立匹配新值")

        try await vault.remove(for: scope.transactionA)
        let remainingFormal = try await vault.load(for: scope.accountA)
        let removedTemporary = try await vault.load(for: scope.transactionA)
        XCTAssertTrue(remainingFormal == formal, "删除临时条目后正式条目仍匹配")
        XCTAssertTrue(removedTemporary == nil, "临时条目不存在")
    }

    func testActualKeychainAttributesUseLocalOnlyProtectionWithoutSync() async throws {
        let scope = isolatedScope()
        let vault = CredentialVault(service: scope.service)
        for entry in [scope.accountA, scope.transactionA] {
            try await vault.save(makePayload(), for: entry)
            var query = scope.query(for: entry)
            query[kSecReturnAttributes as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            XCTAssertTrue(status == errSecSuccess, "测试条目属性可读取")
            guard let attributes = result as? [String: Any] else {
                XCTFail("测试条目属性不可读取")
                continue
            }
            XCTAssertTrue(
                attributes[kSecAttrAccessible as String] as? String
                    == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
                "正式和临时条目均采用本机首次解锁后可读策略"
            )
            XCTAssertTrue(attributes[kSecAttrSynchronizable as String] as? Bool == false,
                          "测试条目不参与跨设备同步")
        }
    }

    func testMissingEntryReturnsNilWithoutCreatingAnItem() async throws {
        let scope = isolatedScope()
        let vault = CredentialVault(service: scope.service)
        let result = try await vault.load(for: scope.accountA)
        XCTAssertTrue(result == nil, "不存在的条目返回不存在")
        let (status, _) = SystemKeychainClient().copyMatching(scope.query(for: scope.accountA))
        XCTAssertTrue(status == errSecItemNotFound, "读取没有创建测试条目")
    }

    func testTemporaryReadFailuresPreservePackagesAndOrdinaryAccountData() async throws {
        let scope = isolatedScope()
        let client = FaultInjectingKeychainClient()
        let vault = CredentialVault(service: scope.service, client: client)
        let payloadA = makePayload()
        let payloadB = makePayload()
        try await vault.save(payloadA, for: scope.accountA)
        try await vault.save(payloadB, for: scope.accountB)
        let accounts = try await makeAccountFixture(scope: scope)

        for status in [errSecInteractionNotAllowed, errSecNotAvailable] {
            client.setFault(.read(status, nil))
            await assertVaultError(.temporarilyUnavailable) {
                _ = try await vault.load(for: scope.accountA)
            }
            try await assertAccountsUnchanged(accounts)
            client.setFault(nil)
            let restoredA = try await vault.load(for: scope.accountA)
            let restoredB = try await vault.load(for: scope.accountB)
            XCTAssertTrue(restoredA == payloadA, "恢复后 A 存在且匹配")
            XCTAssertTrue(restoredB == payloadB, "恢复后 B 存在且匹配")
        }
        print("T05 | 暂时无法读取后恢复 | A、B 仍匹配；账户文件保持匹配")
    }

    func testOtherReadFailureIsNotReportedAsMissingAndKeepsSavedPackage() async throws {
        let scope = isolatedScope()
        let client = FaultInjectingKeychainClient()
        let vault = CredentialVault(service: scope.service, client: client)
        let payload = makePayload()
        try await vault.save(payload, for: scope.accountA)
        client.setFault(.read(errSecAuthFailed, nil))

        await assertVaultError(.keychainFailure(errSecAuthFailed)) {
            _ = try await vault.load(for: scope.accountA)
        }
        client.setFault(nil)
        let restored = try await vault.load(for: scope.accountA)
        XCTAssertTrue(restored == payload, "读取失败恢复后原授权仍匹配")
    }

    func testFailedUpdateKeepsOldWholePackageOtherAccountAndAccountFile() async throws {
        let scope = isolatedScope()
        let client = FaultInjectingKeychainClient()
        let vault = CredentialVault(service: scope.service, client: client)
        let payloadA = makePayload()
        let payloadB = makePayload()
        try await vault.save(payloadA, for: scope.accountA)
        try await vault.save(payloadB, for: scope.accountB)
        let accounts = try await makeAccountFixture(scope: scope)
        client.setFault(.update(errSecNotAvailable))

        await assertVaultError(.temporarilyUnavailable) {
            try await vault.save(self.makePayload(), for: scope.accountA)
        }
        client.setFault(nil)
        let restoredA = try await vault.load(for: scope.accountA)
        let restoredB = try await vault.load(for: scope.accountB)
        XCTAssertTrue(restoredA == payloadA, "写入失败后 A 的完整旧包仍匹配")
        XCTAssertTrue(restoredB == payloadB, "写入失败后 B 仍匹配")
        try await assertAccountsUnchanged(accounts)
    }

    func testFailedDeleteKeepsEntriesAndAccountFileAndCanBeRetried() async throws {
        let scope = isolatedScope()
        let client = FaultInjectingKeychainClient()
        let vault = CredentialVault(service: scope.service, client: client)
        let payloadA = makePayload()
        let payloadB = makePayload()
        try await vault.save(payloadA, for: scope.accountA)
        try await vault.save(payloadB, for: scope.accountB)
        let accounts = try await makeAccountFixture(scope: scope)
        client.setFault(.delete(errSecAuthFailed))

        await assertVaultError(.keychainFailure(errSecAuthFailed)) {
            try await vault.remove(for: scope.accountA)
        }
        client.setFault(nil)
        let preservedA = try await vault.load(for: scope.accountA)
        let preservedB = try await vault.load(for: scope.accountB)
        XCTAssertTrue(preservedA == payloadA, "删除失败后 A 仍匹配")
        XCTAssertTrue(preservedB == payloadB, "删除失败后 B 仍匹配")
        try await assertAccountsUnchanged(accounts)

        try await vault.remove(for: scope.accountA)
        let removedA = try await vault.load(for: scope.accountA)
        let remainingB = try await vault.load(for: scope.accountB)
        XCTAssertTrue(removedA == nil, "恢复后可以重试删除 A")
        XCTAssertTrue(remainingB == payloadB, "重试删除 A 不影响 B")
    }

    func testFailedFirstSaveDoesNotCreateAnEmptyItem() async throws {
        let scope = isolatedScope()
        let client = FaultInjectingKeychainClient()
        let vault = CredentialVault(service: scope.service, client: client)
        client.setFault(.add(errSecNotAvailable))
        await assertVaultError(.temporarilyUnavailable) {
            try await vault.save(self.makePayload(), for: scope.accountA)
        }
        client.setFault(nil)
        let result = try await vault.load(for: scope.accountA)
        XCTAssertTrue(result == nil, "首次保存失败后条目不存在")
    }

    func testEmptySaveIsRejectedWithoutChangingExistingOrMissingEntries() async throws {
        let scope = isolatedScope()
        let vault = CredentialVault(service: scope.service)
        let original = makePayload()
        try await vault.save(original, for: scope.accountA)
        for entry in [scope.accountA, scope.accountB] {
            await assertVaultError(.invalidPayload) {
                try await vault.save(CredentialPayload(data: Data()), for: entry)
            }
        }
        let restoredA = try await vault.load(for: scope.accountA)
        let restoredB = try await vault.load(for: scope.accountB)
        XCTAssertTrue(restoredA == original, "空授权不能覆盖原授权")
        XCTAssertTrue(restoredB == nil, "空授权不能创建新条目")
    }

    func testSuccessfulReadWithoutUsablePayloadIsRejectedWithoutDeletion() async throws {
        let scope = isolatedScope()
        let client = FaultInjectingKeychainClient()
        let vault = CredentialVault(service: scope.service, client: client)
        let original = makePayload()
        try await vault.save(original, for: scope.accountA)
        let unusableResults: [Data?] = [nil, Data()]
        for returnedData in unusableResults {
            client.setFault(.read(errSecSuccess, returnedData))
            await assertVaultError(.invalidPayload) {
                _ = try await vault.load(for: scope.accountA)
            }
            client.setFault(nil)
            let restored = try await vault.load(for: scope.accountA)
            XCTAssertTrue(restored == original, "无效读取结果不能删除原授权")
        }
    }

    func testDescriptionsAndReflectionNeverExposePayload() {
        let marker = "T05-runtime-only-\(UUID().uuidString)"
        let payload = CredentialPayload(data: Data(marker.utf8))
        let description = String(describing: payload)
        let debugDescription = String(reflecting: payload)
        var reflection = ""
        dump(payload, to: &reflection)
        XCTAssertTrue(description == "CredentialPayload(<redacted>)", "普通描述已去敏")
        XCTAssertTrue(debugDescription == "CredentialPayload(<redacted>)", "调试描述已去敏")
        XCTAssertTrue(!reflection.contains(marker), "反射描述不含授权原文")
        XCTAssertTrue(Mirror(reflecting: payload).children.isEmpty, "反射不展开授权数据")
    }

    private func isolatedScope() -> VaultTestScope {
        let scope = VaultTestScope()
        addTeardownBlock {
            for entry in [scope.accountA, scope.accountB, scope.transactionA] {
                let status = SecItemDelete(scope.query(for: entry) as CFDictionary)
                XCTAssertTrue(status == errSecSuccess || status == errSecItemNotFound,
                              "只清理本测试的精确条目")
            }
        }
        return scope
    }

    /// Generated only in memory. The opaque package changes all fictional fields together.
    private func makePayload() -> CredentialPayload {
        let encoded = "T05-runtime-only|\(UUID().uuidString)|\(UUID().uuidString)|\(UUID().uuidString)"
        return CredentialPayload(data: Data(encoded.utf8))
    }

    private func makeAccountFixture(scope: VaultTestScope) async throws -> AccountFileFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("T05-accounts-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        let fileURL = directory.appendingPathComponent("accounts.json")
        let store = AccountStore(fileURL: fileURL)
        let accountA = ConnectedAccount(
            verifiedEmail: "a@example.invalid",
            displayName: "A",
            scope: AccountScope(remoteAccountID: "fixture-account-a", kind: .personal),
            credentialRef: scope.idA
        )
        let accountB = ConnectedAccount(
            verifiedEmail: "b@example.invalid",
            displayName: "B",
            scope: AccountScope(remoteAccountID: "fixture-account-b", kind: .personal),
            credentialRef: scope.idB
        )
        try await store.append(accountA)
        try await store.append(accountB)
        return AccountFileFixture(fileURL: fileURL,
                                  data: try Data(contentsOf: fileURL),
                                  accounts: [accountA, accountB])
    }

    private func assertAccountsUnchanged(_ fixture: AccountFileFixture) async throws {
        let restored = try await AccountStore(fileURL: fixture.fileURL).load()
        let persisted = try Data(contentsOf: fixture.fileURL)
        XCTAssertTrue(restored == fixture.accounts, "账户和原状态保持匹配")
        XCTAssertTrue(persisted == fixture.data, "普通账户文件逐字节保持匹配")
    }

    private func assertVaultError(
        _ expected: CredentialVault.VaultError,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("预期操作报告可处理的失败", file: file, line: line)
        } catch {
            XCTAssertTrue(error as? CredentialVault.VaultError == expected,
                          "内部失败状态应匹配；不展开授权内容", file: file, line: line)
        }
    }
}

private struct VaultTestScope: Sendable {
    let service = "com.iceflying.SubscriptionUsage.Tests.T05.\(UUID().uuidString)"
    let idA = UUID()
    let idB = UUID()
    var accountA: CredentialVault.Entry { .credential(idA) }
    var accountB: CredentialVault.Entry { .credential(idB) }
    var transactionA: CredentialVault.Entry { .loginTransaction(idA) }

    /// Always includes both service and account; never enumerates another test or App item.
    func query(for entry: CredentialVault.Entry) -> [String: Any] {
        let namespace: String
        let id: UUID
        switch entry {
        case let .credential(value):
            namespace = "credentials"
            id = value
        case let .loginTransaction(value):
            namespace = "login-transactions"
            id = value
        }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "\(service).\(namespace)",
            kSecAttrAccount as String: id.uuidString,
            kSecAttrSynchronizable as String: false
        ]
    }
}

private struct AccountFileFixture {
    let fileURL: URL
    let data: Data
    let accounts: [ConnectedAccount]
}

/// All mutable injected state is protected by a lock; real Keychain calls stay synchronous.
private final class FaultInjectingKeychainClient: KeychainClient, @unchecked Sendable {
    enum Fault: Sendable {
        case read(OSStatus, Data?)
        case add(OSStatus)
        case update(OSStatus)
        case delete(OSStatus)
    }

    private let lock = NSLock()
    private let system = SystemKeychainClient()
    private var fault: Fault?

    func setFault(_ fault: Fault?) {
        lock.lock()
        defer { lock.unlock() }
        self.fault = fault
    }

    private func currentFault() -> Fault? {
        lock.lock()
        defer { lock.unlock() }
        return fault
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        if case let .read(status, data) = currentFault() { return (status, data) }
        return system.copyMatching(query)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        if case let .add(status) = currentFault() { return status }
        return system.add(attributes)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        if case let .update(status) = currentFault() { return status }
        return system.update(query, attributes: attributes)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        if case let .delete(status) = currentFault() { return status }
        return system.delete(query)
    }
}
