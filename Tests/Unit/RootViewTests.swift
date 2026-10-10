import SwiftUI
import UIKit
import XCTest
@testable import SubscriptionUsage

final class RootViewTests: XCTestCase {
    func testT17StableBoundariesHandleMixedHeightsMicroMovementAndReversal() {
        for centers: [CGFloat] in [[44, 167.17, 337.5], [91, 261, 431], [44, 290, 620]] {
            for source in centers.indices {
                var position = QuotaReorderPosition(source: source, centers: centers)
                for target in (0..<centers.count).reversed() {
                    let y = target == source ? centers[source] : centers[target] + (target > source ? 12 : -12)
                    XCTAssertEqual(position.update(y: y), target)
                    for tick in 0..<30 {
                        XCTAssertEqual(position.update(y: y + (tick.isMultiple(of: 2) ? -0.5 : 0.5)), target)
                    }
                }
                XCTAssertEqual(position.update(y: centers.last! + 20), centers.count - 1)
                XCTAssertEqual(position.update(y: centers.first! - 20), 0)
            }
        }
    }

    func testT17CrossingDeadbandDoesNotAlternateAndNewDragResets() {
        var position = QuotaReorderPosition(source: 0, centers: [44, 167, 337])
        XCTAssertEqual(position.update(y: 180), 1)
        for y: CGFloat in [166.5, 167.5, 165, 170, 163] { XCTAssertEqual(position.update(y: y), 1) }
        XCTAssertEqual(position.update(y: 155), 0)
        for y: CGFloat in [166.5, 167.5, 170] { XCTAssertEqual(position.update(y: y), 0) }
        XCTAssertEqual(position.update(y: 180), 1)
        position = QuotaReorderPosition(source: 2, centers: [44, 167, 337])
        XCTAssertEqual(position.update(y: 337), 2)
        XCTAssertEqual(position.update(y: .nan), 2)
    }

    @MainActor
    func testT17UnequalHeightUIKitMovementHoldsThenReversesWithoutOscillation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("T17-hold-\(UUID())")
        let store = AccountStore(fileURL: root.appendingPathComponent("accounts.json"))
        _ = try await store.setDemoMode(true)
        for _ in 0..<3 { _ = try await store.addDemo(now: Date()) }
        var accounts = try await store.load()
        accounts[0].source = nil
        accounts[0].quotaSnapshot = nil
        accounts[0].quotaState = .notApplicable
        accounts[0].subscription = .init(planType: "Free", observedAt: Date())
        defer { try? FileManager.default.removeItem(at: root) }
        var committedDestinations: [Int] = []
        let controller = UIHostingController(rootView: QuotaView(accounts: accounts, canReorder: true,
            move: { _, destination in committedDestinations.append(destination) }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 414, height: 896)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(600))
        func find(_ view: UIView) -> UICollectionView? {
            if let collection = view as? UICollectionView { return collection }
            return view.subviews.compactMap { find($0) }.first
        }
        let collection = try XCTUnwrap(find(controller.view))
        let layout = try XCTUnwrap(collection.collectionViewLayout as? QuotaReorderLayout)
        let frames = (0..<3).compactMap { layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame }
        XCTAssertEqual(frames.count, 3)
        XCTAssertLessThan(frames[0].height, frames[1].height)
        // Replay every original failing position, plus an unambiguous crossing.
        for fraction in [0.05, 0.25, 0.49, 0.51, 0.60, 0.75, 0.95] {
            layout.beginMovement(at: IndexPath(item: 0, section: 0))
            XCTAssertTrue(collection.beginInteractiveMovementForItem(at: IndexPath(item: 0, section: 0)))
            let y = frames[1].minY + frames[1].height * fraction
            var destinations: [Int] = []
            for tick in 0..<30 {
                collection.updateInteractiveMovementTargetPosition(CGPoint(x: frames[0].midX,
                    y: y + (tick.isMultiple(of: 2) ? -0.5 : 0.5)))
                try await Task.sleep(for: .milliseconds(40))
                destinations.append(try XCTUnwrap(layout.movement?.destination))
            }
            XCTAssertEqual(Set(destinations).count, 1, "停留微动不能来回换位")
            let expected = y > frames[1].midY + 6 ? 1 : 0
            XCTAssertEqual(destinations.last, expected)
            let firstHeight = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame.height)
            XCTAssertEqual(firstHeight, frames[expected].height, accuracy: 1, "实际卡片布局也应保持稳定")
            print("T17 FIX | target fraction=\(fraction) | 30次微动保持同一位置=\(expected)")
            collection.cancelInteractiveMovement()
            layout.finishMovement()
            try await Task.sleep(for: .milliseconds(350))
        }
        XCTAssertTrue(committedDestinations.isEmpty, "取消不保存临时顺序")
        layout.beginMovement(at: IndexPath(item: 0, section: 0))
        XCTAssertTrue(collection.beginInteractiveMovementForItem(at: IndexPath(item: 0, section: 0)))
        for (y, expected) in [(frames[1].midY + 12, 1), (frames[2].midY + 12, 2),
                              (frames[2].midY - 12, 1), (frames[1].midY - 12, 0),
                              (frames[1].midY + 12, 1)] {
            collection.updateInteractiveMovementTargetPosition(CGPoint(x: frames[0].midX, y: y))
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertEqual(layout.movement?.destination, expected)
        }
        collection.endInteractiveMovement()
        layout.finishMovement()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(committedDestinations, [2], "松手仅保存最终的第二位")
        XCTAssertNil(layout.movement)
    }

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
