import SwiftUI
import UIKit
import XCTest
@testable import SubscriptionUsage

final class RootViewTests: XCTestCase {
    @MainActor
    func testT58SystemDefaultAndManualOverrideAcrossSystemChanges() async throws {
        let suite = "T58-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let controller = UIHostingController(rootView: RootView(connection: CodexConnectionFlow(), preferences: preferences))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 414, height: 896)
        window.rootViewController = controller
        window.overrideUserInterfaceStyle = .light
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(controller.view.traitCollection.userInterfaceStyle, .light)
        window.overrideUserInterfaceStyle = .dark
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(controller.view.traitCollection.userInterfaceStyle, .dark)
        preferences.set("light", forKey: "appearance")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(controller.view.traitCollection.userInterfaceStyle, .light)
        window.overrideUserInterfaceStyle = .light
        window.overrideUserInterfaceStyle = .dark
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(controller.view.traitCollection.userInterfaceStyle, .light)
        let reopened = UIHostingController(rootView: RootView(connection: CodexConnectionFlow(), preferences: preferences))
        window.rootViewController = reopened
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(reopened.view.traitCollection.userInterfaceStyle, .light)
    }

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
