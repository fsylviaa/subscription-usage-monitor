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
    func testNavigationEmptyStateAndUnavailableActions() {
        continueAfterFailure = false
        let app = XCUIApplication()

        app.launch()
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
            XCTAssertFalse(reminder.isEnabled)
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

        let refresh = app.buttons["quota.refresh"]
        let toolbarConnect = app.buttons["quota.toolbarConnect"]
        for action in [refresh] {
            XCTAssertTrue(action.exists)
            XCTAssertFalse(action.isEnabled)
        }
        XCTAssertTrue(toolbarConnect.isEnabled)
        XCTAssertTrue(app.buttons["quota.connect"].isEnabled)
        // 顶部两个操作位于标题右侧同一行。
        XCTAssertGreaterThan(refresh.frame.minX, title.frame.maxX)
        XCTAssertGreaterThan(toolbarConnect.frame.minX, refresh.frame.minX)
        XCTAssertLessThan(abs(title.frame.midY - refresh.frame.midY), 12)
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
