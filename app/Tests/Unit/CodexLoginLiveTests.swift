import XCTest
@testable import SubscriptionUsage

/// User performs the website's password/confirmation first. This test only reads
/// this iPhone App's own binding and verifies it against the official server.
@MainActor
final class CodexLoginLiveTests: XCTestCase {
    func testT09IsolatedSavedIdentityAndCleanup() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["T09_LIVE_SAVED_ACCOUNT"] == "1" else {
            throw XCTSkip("T09 独立真实登录需本人官网确认后显式核验。")
        }
        guard let rawID = environment["T09_LIVE_RUN_ID"], let runID = UUID(uuidString: rawID),
              rawID.uppercased() == runID.uuidString else {
            XCTFail("T09 缺少有效独立验收编号。")
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T09-live-\(runID.uuidString)")
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let vault = CredentialVault(service: "T09.live.\(runID.uuidString)")
        let accounts = try await store.load()
        guard accounts.count == 1, let account = accounts.first,
              let payload = try await vault.load(for: .credential(account.credentialRef)) else {
            XCTFail("T09 独立真实登录尚未保存，不能用原有账户代替。")
            return
        }
        struct Package: Decodable { let tokens: CodexTokenResponse }
        let package = try JSONDecoder().decode(Package.self, from: payload.data)
        let verified = try await CodexIdentityVerifier().verify(package.tokens)
        guard verified.email == account.verifiedEmail, verified.remoteUserID == account.remoteUserID,
              verified.scope == account.scope, account.quotaState == .notFetched else {
            XCTFail("T09 真实身份重核验与独立保存记录不一致。")
            return
        }
        let slot = CredentialVault.Entry.loginTransaction(UUID(uuidString: "2BCEFFDE-7DC2-4F6A-89B0-020023689458")!)
        let transaction = try await vault.load(for: slot)
        XCTAssertNil(transaction, "成功后设备事务已清理")
        if environment["T09_LIVE_CLEANUP"] == "1" {
            // Exact items in this caller-selected test namespace only.
            if let transaction,
               let authorization = try? JSONDecoder().decode(CodexDeviceAuthorization.self, from: transaction.data) {
                try await vault.remove(for: .loginTransaction(authorization.transactionID))
            }
            try await vault.remove(for: slot)
            try await vault.remove(ifMatching: payload, for: .credential(account.credentialRef))
            try FileManager.default.removeItem(at: directory)
            let credential = try await vault.load(for: .credential(account.credentialRef))
            XCTAssertNil(credential, "本次独立验收授权已精确删除")
        }
        print("T09 | 取消后再次真实登录 | 已保存账户的签名、身份、作用域及授权重新核验通过；仍为尚未获取额度；不输出身份和秘密")
    }

    func testRealSavedIdentityCredentialAndReopen() async throws {
        guard ProcessInfo.processInfo.environment["T08_LIVE_SAVED_ACCOUNT"] == "1" else {
            throw XCTSkip("真实账户需用户本人在官网确认后显式验收；普通测试不联网。")
        }
        let store = try AccountStore.applicationStore()
        let accounts = try await store.load()
        guard accounts.count == 1, let account = accounts.first else {
            XCTFail("真实登录尚未保存，不能用隔离账户代替。")
            return
        }
        guard let payload = try await CredentialVault.applicationVault().load(for: .credential(account.credentialRef)) else {
            XCTFail("账户所指的本机授权未找到。")
            return
        }
        struct Package: Decodable { let tokens: CodexTokenResponse }
        let package = try JSONDecoder().decode(Package.self, from: payload.data)
        let verified = try await CodexIdentityVerifier().verify(package.tokens)
        XCTAssertTrue(verified.email == account.verifiedEmail, "重新核验的可靠邮箱与已保存身份一致")
        XCTAssertTrue(verified.remoteUserID == account.remoteUserID, "服务端用户与已保存用户一致")
        XCTAssertTrue(verified.scope == account.scope, "服务端账户作用域一致")
        XCTAssertTrue(account.quotaState == .notFetched, "未发布额度或伪造更新时间")
        XCTAssertNil(account.displayName, "本步未编造姓名")
        let reopened = try await AccountStore.applicationStore().load()
        XCTAssertTrue(reopened == accounts, "重建存储实例后身份与原账户一致")
        let pending = try await CredentialVault.applicationVault().load(for: .loginTransaction(
            UUID(uuidString: "2BCEFFDE-7DC2-4F6A-89B0-020023689458")!))
        XCTAssertNil(pending, "成功绑定后的设备事务已清除")
        print("T08 | 真实iPhone | 双令牌签名、issuer/audience/subject、网络检查、服务端scope核对通过")
        print("T08 | 真实保存重读 | 邮箱/用户/作用域匹配，授权可读；尚未获取额度；临时设备事务已清除；不记录邮箱或秘密")
    }
}
