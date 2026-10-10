import XCTest

final class CodexQuotaUITests: XCTestCase {
    @MainActor
    func testAutomaticQuotaAfterLoginAndSameResultOnReopen() {
        let app = launch("success")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.weekly.remaining"].label, "剩余 70%")
        XCTAssertEqual(app.staticTexts["quota.fiveHours.remaining"].label, "剩余 20%")
        XCTAssertTrue(app.staticTexts["quota.weekly.reset"].label.contains("预计重置于"))
        XCTAssertTrue(app.staticTexts["quota.fiveHours.reset"].label.contains("预计重置于"))
        XCTAssertFalse(app.staticTexts["quota.notFetched"].exists)
        let date = app.staticTexts["quota.updatedAt"].label
        screenshot(app, "T12-成功-隔离")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.updatedAt"].label, date)
        XCTAssertEqual(app.staticTexts["quota.weekly.remaining"].label, "剩余 70%")
        XCTAssertEqual(app.staticTexts["quota.fiveHours.remaining"].label, "剩余 20%")
    }

    @MainActor
    func testQueryGate50RetainsIdentityAndDoesNotShowSuccess() {
        let app = launch("blocked")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.failure"].label, "网络不达标，无法更新")
        XCTAssertTrue(app.staticTexts["quota.accountIdentity"].exists)
        XCTAssertTrue(app.staticTexts["quota.notFetched"].exists)
        XCTAssertFalse(app.staticTexts["quota.updatedAt"].exists)
        XCTAssertFalse(app.staticTexts["quota.weekly.remaining"].exists)
        screenshot(app, "T12-网络阻止-隔离")
    }

    @MainActor
    func testMissingWindowAndResetAreReadableWithoutFakeZero() {
        let app = launch("partial")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.weekly.remaining"].label, "剩余 70%")
        XCTAssertEqual(app.staticTexts["quota.fiveHours.remaining"].label, "未知")
        XCTAssertEqual(app.staticTexts["quota.weekly.reset"].label, "未提供重置时间")
        XCTAssertEqual(app.staticTexts["quota.fiveHours.reset"].label, "未提供重置时间")
        screenshot(app, "T12-部分响应-隔离")
    }

    @MainActor
    func testRealSavedQuotaAppearsOnNormalLaunchAndReopen() throws {
        guard ProcessInfo.processInfo.environment["T12_LIVE_REOPEN"] == "1" else {
            throw XCTSkip("显式开启后才检查真实账户页面。")
        }
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 60))
        guard app.staticTexts["quota.updatedAt"].exists else { return }
        // Compare in memory; never print identity or attach real screenshots.
        let identity = app.staticTexts["quota.accountIdentity"].label
        let ids = ["quota.weekly.remaining", "quota.weekly.reset", "quota.fiveHours.remaining", "quota.fiveHours.reset", "quota.updatedAt"]
        let labels = ids.map { app.staticTexts[$0].label }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["quota.accountIdentity"].label == identity)
        XCTAssertTrue(ids.map { app.staticTexts[$0].label } == labels)
        XCTAssertFalse(app.staticTexts["quota.notFetched"].exists)
        print("T12 | 真实普通启动与重开 | 两窗口、重置和原成功时间显示一致；身份未输出")
    }

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--t12-isolated-ui", scenario, "--t08-run-id", UUID().uuidString]
        app.launch()
        return app
    }
    @MainActor
    private func completeFixtureLogin(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["quota.connect"].waitForExistence(timeout: 10))
        app.buttons["quota.connect"].tap()
        XCTAssertTrue(app.staticTexts["connection.code"].waitForExistence(timeout: 5))
        app.buttons["connection.open"].tap()
    }
    @MainActor
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
