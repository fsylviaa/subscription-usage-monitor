import XCTest

final class LaunchTests: XCTestCase {
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
            XCTAssertTrue(app.buttons["settings.connect"].isEnabled)
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
