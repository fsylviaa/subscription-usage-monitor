import SwiftUI
import UIKit
import XCTest
@testable import SubscriptionUsage

final class RootViewTests: XCTestCase {
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
