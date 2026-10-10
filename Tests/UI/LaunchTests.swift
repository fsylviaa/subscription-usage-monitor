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
            app.tabBars.buttons["设置"].tap()
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.tabBars.buttons["设置"].isSelected)

            for identifier in ["settings.connect", "settings.widgetTutorial", "settings.help", "settings.privacy", "settings.licenses"] {
                let action = app.buttons[identifier]
                XCTAssertTrue(action.exists, identifier)
                XCTAssertFalse(action.isEnabled, identifier)
            }
            let reminder = app.switches["settings.resetReminder"]
            XCTAssertTrue(reminder.exists)
            XCTAssertFalse(reminder.isEnabled)
            XCTAssertEqual(reminder.value as? String, "0")
            saveScreenshot(of: app, name: "设置")

            app.tabBars.buttons["额度"].tap()
            assertEmptyQuota(in: app)
        }

        app.terminate()
        app.launch()
        assertEmptyQuota(in: app)
        XCTAssertEqual(app.state, .runningForeground)
    }

    @MainActor
    private func assertEmptyQuota(in app: XCUIApplication) {
        let title = app.navigationBars.staticTexts["订阅额度"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.isHittable)
        XCTAssertTrue(app.staticTexts["未连接账户"].exists)
        XCTAssertTrue(app.tabBars.buttons["额度"].isSelected)

        let refresh = app.buttons["quota.refresh"]
        let toolbarConnect = app.buttons["quota.toolbarConnect"]
        for action in [refresh, toolbarConnect, app.buttons["quota.connect"]] {
            XCTAssertTrue(action.exists)
            XCTAssertFalse(action.isEnabled)
        }
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
