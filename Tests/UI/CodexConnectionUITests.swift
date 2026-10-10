import XCTest

final class CodexConnectionUITests: XCTestCase {
    @MainActor
    func testCodeCopyAndCancelFromAllEntryPoints() {
        let app = launch("51")
        for entry in ["quota.connect", "quota.toolbarConnect", "settings.connect"] {
            if entry == "settings.connect" { app.buttons["tab.settings"].tap() }
            app.buttons[entry].tap()
            XCTAssertTrue(app.staticTexts["connection.code"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["connection.code"].label, "TEST-CODE")
            let copy = app.buttons["connection.copy"]
            XCTAssertTrue(copy.isHittable)
            copy.tap()
            XCTAssertTrue(app.buttons["已复制"].exists)
            XCTAssertTrue(app.buttons["connection.open"].isHittable)
            app.buttons["connection.open"].tap() // Isolated opener; never sends a test code to OpenAI.
            XCTAssertTrue(app.staticTexts["connection.code"].exists)
            saveFixtureScreenshot(app, name: entry)
            app.buttons["connection.cancel"].tap()
            XCTAssertTrue(app.buttons[entry].waitForExistence(timeout: 5))
            if entry == "settings.connect" { XCTAssertTrue(app.buttons["tab.settings"].isSelected) }
        }
        app.buttons["tab.quota"].tap()
        XCTAssertTrue(app.staticTexts["未连接账户"].exists)
    }

    @MainActor
    func testLowUnknownAndRequestFailureShowBriefResults() {
        for (scenario, message) in [("50", "网络不达标，无法连接"),
                                    ("unknown", "登录未完成，请重试"),
                                    ("request-failure", "登录未完成，请重试")] {
            let app = launch(scenario)
            app.buttons["quota.connect"].tap()
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["connection.code"].exists)
            XCTAssertFalse(app.buttons["connection.open"].exists)
            app.buttons["connection.retry"].tap()
            XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 5))
            saveFixtureScreenshot(app, name: scenario)
            app.buttons["connection.cancel"].tap()
            XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor
    func testCancelSlowCheckDoesNotReopenConnection() {
        let app = launch("slow")
        app.buttons["quota.toolbarConnect"].tap()
        XCTAssertTrue(app.staticTexts["连接中…"].waitForExistence(timeout: 5))
        app.buttons["connection.cancel"].tap()
        XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5))
        let lateCode = expectation(for: NSPredicate(format: "exists == true"), evaluatedWith: app.staticTexts["connection.code"])
        lateCode.isInverted = true
        wait(for: [lateCode], timeout: 4)
        XCTAssertTrue(app.staticTexts["未连接账户"].exists)
    }

    @MainActor
    func testRealDefaultBrowserHasOfficialPage() throws {
        guard ProcessInfo.processInfo.environment["T07_LIVE_BROWSER_VERIFY"] == "1" else {
            throw XCTSkip("仅在真实连接测试已通过系统打开官网后执行，不主动指定浏览器。")
        }
        continueAfterFailure = false
        let browsers = ["com.apple.mobilesafari", "com.google.chrome.ios", "org.mozilla.ios.Firefox",
                        "com.microsoft.msedge", "com.brave.ios.browser"]
        guard let browser = browsers.map({ XCUIApplication(bundleIdentifier: $0) })
            .first(where: { $0.state == .runningForeground }) else {
            XCTFail("没有识别到当前前台默认浏览器；需实机查看确认")
            return
        }
        // Inspect in memory, without screenshots or printing browser contents/account data.
        let page = browser.debugDescription
        XCTAssertTrue(page.contains("auth.openai.com"), "前台浏览器显示 OpenAI 认证官方域名")
        let officialContent = ["Log in", "Sign in", "Welcome", "Device", "device code", "Continue", "登录", "登入", "设备", "繼續"]
            .contains(where: { page.contains($0) })
        XCTAssertTrue(officialContent, "官方登录或设备确认页面已显示")
        print("T07 | 真机默认浏览器实见 | OpenAI 官方域名和登录/设备确认页面已显示；未输入或提交账户资料")
    }

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t07-isolated-ui", scenario]
        app.launch()
        XCTAssertTrue(app.buttons["quota.connect"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func saveFixtureScreenshot(_ app: XCUIApplication, name: String) {
        // This class uses only TEST-CODE, never captures a real authorization code.
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "T07-隔离-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
