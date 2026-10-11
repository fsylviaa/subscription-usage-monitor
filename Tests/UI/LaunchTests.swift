import XCTest

final class LaunchTests: XCTestCase {
    @MainActor
    func testT58ManualAppearanceSurvivesRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        app.buttons["tab.settings"].tap()
        let toggle = app.switches["settings.darkAppearance"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let selected = original == "1" ? "0" : "1"
        XCTAssertTrue(NSPredicate(format: "value == %@", selected).evaluate(with: toggle) || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", selected), object: toggle)], timeout: 3) == .completed)
        saveScreenshot(of: app, name: "T58-手动外观")
        app.terminate(); app.launch()
        app.buttons["tab.settings"].tap()
        XCTAssertEqual(toggle.value as? String, selected)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.terminate(); app.launch()
        app.buttons["tab.settings"].tap()
        XCTAssertEqual(toggle.value as? String, original)
    }

    @MainActor
    func testT26DemoPullUpdatesEveryCardAndPersistsOnReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["quota.refresh"].exists)
        app.buttons["tab.settings"].tap()
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["tab.quota"].tap()
        for count in 1...2 {
            app.buttons["quota.toolbarConnect"].tap()
            let ready = NSPredicate { _, _ in MainActor.assumeIsolated {
                app.staticTexts.matching(identifier: "quota.accountIdentity").count == count
            }}
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 5), .completed)
        }
        let before = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
        app.pullAllQuota()
        let allChanged = NSPredicate { _, _ in MainActor.assumeIsolated {
            let after = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
            return after.count == 2 && zip(before, after).allSatisfy { $0 != $1 }
        }}
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: allChanged, object: nil)], timeout: 8), .completed)
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        let after = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
        let identities = app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label)
        saveScreenshot(of: app, name: "T26-演示全部刷新")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["quota.weekly.remaining"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label), identities)
        // T27 now refreshes the restored demo accounts on every cold launch.
        let refreshedOnLaunch = NSPredicate { _, _ in MainActor.assumeIsolated {
            let current = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
            return current.count == 2 && zip(after, current).allSatisfy { $0 != $1 }
        }}
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: refreshedOnLaunch, object: nil)], timeout: 8), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["quota.refreshProgress"].firstMatch.exists)
    }

    @MainActor
    func testManagementDemoMenuClearAndReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        app.buttons["tab.settings"].tap()
        XCTAssertFalse(app.buttons["settings.accounts"].exists)
        XCTAssertFalse(app.buttons["settings.connect"].exists)
        let demo = app.switches["settings.demo"]
        demo.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(demo.value as? String, "1")
        app.buttons["tab.quota"].tap()
        for count in 1...3 {
            app.buttons["quota.toolbarConnect"].tap()
            let countMatches = NSPredicate { _, _ in MainActor.assumeIsolated {
                app.staticTexts.matching(identifier: "quota.accountIdentity").count == count
            }}
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: countMatches, object: nil)], timeout: 5), .completed)
        }
        XCTAssertFalse(app.staticTexts["connection.code"].exists)
        let original = app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label)
        let amounts = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
        app.buttons.matching(identifier: "quota.menu").element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["刷新额度"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["删除账户"].exists)
        app.buttons["刷新额度"].tap()
        let changed = NSPredicate { _, _ in MainActor.assumeIsolated {
            app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label) != amounts
        }}
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 5), .completed)
        let after = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(after[0], amounts[0]); XCTAssertEqual(after[2], amounts[2]); XCTAssertNotEqual(after[1], amounts[1])
        app.buttons.matching(identifier: "quota.menu").element(boundBy: 1).tap()
        app.buttons["删除账户"].tap()
        XCTAssertTrue(app.alerts["删除账户？"].waitForExistence(timeout: 3))
        app.alerts.buttons["取消"].tap()
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label), original)
        app.buttons.matching(identifier: "quota.menu").element(boundBy: 1).tap()
        app.buttons["删除账户"].tap()
        app.alerts.buttons["删除账户"].tap()
        XCTAssertTrue(app.staticTexts[original[0]].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts[original[1]].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts[original[2]].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[original[1]].exists)
        saveScreenshot(of: app, name: "新版-删除后重开")
        app.buttons["tab.settings"].tap()
        XCTAssertEqual(demo.value as? String, "1")
        demo.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        saveScreenshot(of: app, name: "新版-设置")
        app.buttons["tab.quota"].tap()
        XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5))
        app.buttons["quota.toolbarConnect"].tap()
        XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
        app.buttons["connection.cancel"].tap()
    }

    @MainActor
    func testLongDemoListScrollAndDragToTop() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        app.buttons["tab.settings"].tap()
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["tab.quota"].tap()
        for _ in 1...6 { app.buttons["quota.toolbarConnect"].tap() }
        let list = app.collectionViews["quota.list"]
        list.swipeUp(); list.swipeUp()
        let last = app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.last!
        XCTAssertTrue(last.isHittable)
        let identity = last.label
        let cell = app.cells.containing(.staticText, identifier: identity).firstMatch
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            .press(forDuration: 0.7, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)),
                   withVelocity: .slow, thenHoldForDuration: 3)
        list.swipeDown(); list.swipeDown()
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").firstMatch.label, identity)
        saveScreenshot(of: app, name: "新版-长列表拖至首位")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts[identity].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").firstMatch.label, identity)
    }

    @MainActor
    func testT17LongDemoListDragFirstToBottomAndReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        app.buttons["tab.settings"].tap()
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["tab.quota"].tap()
        for _ in 1...6 { app.buttons["quota.toolbarConnect"].tap() }
        let list = app.collectionViews["quota.list"]
        let identity = app.staticTexts.matching(identifier: "quota.accountIdentity").firstMatch.label
        let cell = app.cells.containing(.staticText, identifier: identity).firstMatch
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            .press(forDuration: 0.7, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)),
                   withVelocity: .slow, thenHoldForDuration: 3)
        list.swipeUp(); list.swipeUp()
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.last?.label, identity)
        app.terminate(); app.launch()
        XCTAssertTrue(app.collectionViews["quota.list"].waitForExistence(timeout: 5))
        app.collectionViews["quota.list"].swipeUp(); app.collectionViews["quota.list"].swipeUp()
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.last?.label, identity)
    }

    @MainActor
    func testManualDarkQuotaDetailsAndMenu() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        app.buttons["tab.settings"].tap()
        let appearance = app.switches["settings.darkAppearance"]
        if appearance.value as? String != "1" {
            appearance.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["tab.quota"].tap()
        app.buttons["quota.toolbarConnect"].tap()
        XCTAssertTrue(app.buttons["quota.details"].waitForExistence(timeout: 5))
        app.buttons["quota.details"].tap()
        XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 5))
        saveScreenshot(of: app, name: "新版-手动深色额度详情")
        app.buttons["quota.menu"].tap()
        XCTAssertTrue(app.buttons["刷新额度"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["删除账户"].exists)
        saveScreenshot(of: app, name: "新版-手动深色账户菜单")
    }

    @MainActor
    func testNavigationEmptyStateAndUnavailableActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        assertEmptyQuota(in: app)
        XCTAssertEqual(app.state, .runningForeground)
        saveScreenshot(of: app, name: "额度")

        for _ in 0..<2 {
            app.buttons["tab.settings"].tap()
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["tab.settings"].isSelected)

            for identifier in ["settings.widgetTutorial", "settings.help", "settings.privacy", "settings.licenses"] {
                let action = app.buttons[identifier]
                XCTAssertTrue(action.exists, identifier)
                XCTAssertFalse(action.isEnabled, identifier)
            }
            XCTAssertFalse(app.buttons["settings.connect"].exists)
            XCTAssertFalse(app.buttons["settings.accounts"].exists)
            let reminder = app.switches["settings.resetReminder"]
            XCTAssertTrue(reminder.exists)
            XCTAssertTrue(reminder.isEnabled)
            XCTAssertEqual(reminder.value as? String, "0")
            saveScreenshot(of: app, name: "设置")

            app.buttons["tab.quota"].tap()
            assertEmptyQuota(in: app)
        }

        app.terminate()
        app.launch()
        assertEmptyQuota(in: app)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    private func assertEmptyQuota(in app: XCUIApplication) {
        let title = app.staticTexts["quota.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.isHittable)
        XCTAssertTrue(app.staticTexts["未连接账户"].exists)
        XCTAssertTrue(app.buttons["tab.quota"].isSelected)

        XCTAssertFalse(app.buttons["quota.refresh"].exists)
        let toolbarConnect = app.buttons["quota.toolbarConnect"]
        XCTAssertTrue(toolbarConnect.isEnabled)
        XCTAssertTrue(app.buttons["quota.connect"].isEnabled)
        // 顶部只保留标题右侧的连接入口。
        XCTAssertGreaterThan(toolbarConnect.frame.minX, title.frame.maxX)
        XCTAssertLessThan(abs(title.frame.midY - toolbarConnect.frame.midY), 12)
    }

    @MainActor
    private func saveScreenshot(of app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
