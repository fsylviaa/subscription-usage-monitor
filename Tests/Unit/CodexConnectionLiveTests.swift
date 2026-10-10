import UIKit
import XCTest
@testable import SubscriptionUsage

/// Explicit opt-in only. Uses the unmodified real network gate and official endpoint.
/// No screen or authorization body is attached, no account/token is created.
@MainActor
final class CodexConnectionLiveTests: XCTestCase {
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
