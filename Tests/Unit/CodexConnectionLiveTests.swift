import UIKit
import XCTest
@testable import SubscriptionUsage

/// Explicit opt-in only. Uses the unmodified real network gate and official endpoint.
/// No screen or authorization body is attached, no account/token is created.
@MainActor
final class CodexConnectionLiveTests: XCTestCase {
    func testT09RealCancellationPreservesSavedAccountAndAllowsFreshCode() async throws {
        guard ProcessInfo.processInfo.environment["T09_LIVE_CANCEL"] == "1" else {
            throw XCTSkip("T09 真实取消复测需显式开启，默认不联网。")
        }
        let official = try AccountStore.applicationStore()
        let officialVault = CredentialVault.applicationVault()
        let before = try await official.load()
        var credentials: [UUID: CredentialPayload] = [:]
        for account in before {
            credentials[account.credentialRef] = try await officialVault.load(for: .credential(account.credentialRef))
        }
        let runID = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T09-cancel-\(runID)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let accounts = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let vault = CredentialVault(service: "com.iceflying.SubscriptionUsage.tests.T09.cancel.\(runID)")
        let transactions = CodexLoginTransactionStore(vault: vault)
        let pending = CodexPendingLoginStore(vault: vault)
        let flow = CodexConnectionFlow(transactions: transactions, completer: CodexLoginClient(),
            verifier: CodexIdentityVerifier(), bindings: CodexAccountBindingStore(accountStore: accounts, vault: vault),
            pending: pending, copyCode: { _, _ in })
        defer { flow.cancel() }

        try await XCTUnwrap(flow.begin()).value
        guard case let .code(first) = flow.state else {
            XCTFail("T09 真实待授权流程未到达代码步骤；保留真实失败，不能用隔离结果代替。")
            return
        }
        await flow.openWebsite()
        XCTAssertFalse(flow.browserFailed, "系统接受真实官网打开请求")
        flow.cancel()
        XCTAssertFalse(flow.isPresented)
        XCTAssertTrue(flow.accounts.isEmpty)
        try await XCTUnwrap(flow.begin()).value // Joins cancellation and exact cleanup.
        guard case let .code(second) = flow.state else {
            XCTFail("T09 取消后尚未取得第二次真实有效代码。")
            return
        }
        XCTAssertTrue(first.transactionID != second.transactionID && first.userCode != second.userCode,
                      "取消后的新流程获得不同真实代码，不打印代码")
        XCTAssertTrue(second.expiresAt > Date())
        flow.cancel()
        // Idempotent exact cleanup; no account confirmation was submitted.
        try await pending.remove(transactionID: first.transactionID)
        try await pending.remove(transactionID: second.transactionID)
        try await transactions.remove(transactionID: second.transactionID)
        let isolated = try await accounts.load()
        XCTAssertTrue(isolated.isEmpty, "真实取消不保存账户")
        let after = try await official.load()
        XCTAssertTrue(before == after, "正式账户数量、身份、顺序及原状态不变，不打印身份")
        for account in before {
            let afterCredential = try await officialVault.load(for: .credential(account.credentialRef))
            XCTAssertTrue(afterCredential == credentials[account.credentialRef], "原正式授权完整保留")
        }
        print("T09 | 真实待授权取消与再次申请 | 官网打开请求成功；取消不保存；再次评分并取得新代码；原正式账户与授权未变")
    }

    func testRealGateCodeClipboardAndDefaultBrowserDispatch() async throws {
        guard ProcessInfo.processInfo.environment["T07_LIVE_CONNECTION"] == "1" else {
            throw XCTSkip("真实连接起点需显式开启；普通验收不联网。")
        }
        let vault = CredentialVault(service: "com.iceflying.SubscriptionUsage.tests.T07.\(UUID())")
        let transactions = CodexLoginTransactionStore(vault: vault)
        let flow = CodexConnectionFlow(checkNetwork: {
            let result = await NetworkScoreChecker().check()
            switch result {
            case let .allowed(score): print("T07 | 真实网络 | 有效评分 \(score)，允许申请")
            case let .blocked(score): print("T07 | 真实网络 | 有效评分 \(score)，阻止申请")
            case .unavailable: print("T07 | 真实网络 | 未取得有效评分，阻止申请")
            case .cancelled: print("T07 | 真实网络 | 已取消")
            }
            return result
        }, transactions: transactions)

        try await XCTUnwrap(flow.begin()).value
        guard case let .code(authorization) = flow.state else {
            flow.cancel()
            XCTFail("T07 真实代码步骤尚未到达；保留真实网络拦截或申请失败结果，不能以隔离测试代替。")
            return
        }
        // All comparisons are boolean so an XCTest failure cannot print a live code.
        flow.copy()
        XCTAssertTrue(UIPasteboard.general.string == authorization.userCode, "复制内容与显示代码一致")
        print("T07 | 真实代码 | 已申请并安全暂存；主动复制内容一致（不记录代码）")
        await flow.openWebsite()
        XCTAssertFalse(flow.browserFailed, "系统默认打开行为接受官方设备确认地址")
        print("T07 | 真实官网 | 已调用系统默认HTTPS打开；网页实际到达另行核对")
        if UIPasteboard.general.string == authorization.userCode { UIPasteboard.general.items = [] }
        flow.cancel()
        try await transactions.remove(transactionID: authorization.transactionID)
    }
}
