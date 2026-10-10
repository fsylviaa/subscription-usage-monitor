import XCTest
@testable import SubscriptionUsage

/// User performs the website's password/confirmation first. This test only reads
/// this iPhone App's own binding and verifies it against the official server.
@MainActor
final class CodexLoginLiveTests: XCTestCase {
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
