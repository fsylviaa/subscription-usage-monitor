import Foundation
import XCTest
@testable import SubscriptionUsage

@MainActor
final class NetworkScoreLiveTests: XCTestCase {
    func testCurrentNetworkReturnsSpecifiedSourceScore() async throws {
        guard ProcessInfo.processInfo.environment["T06_LIVE_NETWORK_CHECK"] == "1" else {
            throw XCTSkip("真实取分需显式启用；普通测试只运行隔离样例。")
        }

        let result = await NetworkScoreChecker().check()
        switch result {
        case let .allowed(score):
            XCTAssertGreaterThan(score, 50)
            XCTAssertLessThanOrEqual(score, 100)
            print("T06 | 真实网络 | 指定来源有效评分 \(score)；允许继续")
        case let .blocked(score):
            XCTAssertGreaterThanOrEqual(score, 0)
            XCTAssertLessThanOrEqual(score, 50)
            print("T06 | 真实网络 | 指定来源有效评分 \(score)；阻止继续")
        case .unavailable:
            XCTFail("T06 | 真实网络 | 无法取得指定来源有效评分；本项未通过")
        case .cancelled:
            XCTFail("T06 | 真实网络 | 检查已取消；本项未完成")
        }
    }
}
