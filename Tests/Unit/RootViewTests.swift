import SwiftUI
import UIKit
import XCTest
@testable import SubscriptionUsage

final class RootViewTests: XCTestCase {
    @MainActor
    func testResetDayLabelUsesCalendarDayInsteadOfRoundingDownFullDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 18, minute: 10)))
        let reset = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 18)))
        XCTAssertTrue(QuotaView.resetText(reset, now: now, calendar: calendar).hasPrefix("6 天后"))
    }

    @MainActor
    func testResetTextUsesReportedDeadlineWithoutInventingOne() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(QuotaView.resetText(nil, now: now), "未提供重置时间")
        XCTAssertEqual(QuotaView.resetText(now, now: now), "已到预计时间")
        XCTAssertEqual(QuotaView.resetText(now.addingTimeInterval(-1), now: now), "已到预计时间")
        XCTAssertEqual(QuotaView.resetText(now.addingTimeInterval(5_640), now: now), "1 小时 34 分后")
        XCTAssertEqual(QuotaView.resetText(now.addingTimeInterval(1), now: now), "1 分钟后")
    }

    @MainActor
    func testRootViewCanLoadAndLayOutInAppHost() {
        let controller = UIHostingController(rootView: RootView())
        controller.loadViewIfNeeded()

        let size = controller.sizeThatFits(in: CGSize(width: 393, height: 852))

        XCTAssertTrue(controller.isViewLoaded)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertTrue(size.width.isFinite && size.height.isFinite)
    }
}
