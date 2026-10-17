import XCTest

final class CodexConnectionUITests: XCTestCase {
    @MainActor
    func testT16RealPickerOpensAndClosesWithoutStartingLogin() throws {
        guard ProcessInfo.processInfo.environment["T16_LIVE_PICKER"] == "1" else {
            throw XCTSkip("仅显式检查普通真机入口，不点平台、不申请登录、不拍真实账户截图。")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let connect = app.buttons["quota.toolbarConnect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        connect.tap()
        XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
        let title = app.staticTexts["connection.title"]
        XCTAssertEqual(title.label, "连接账号")
        XCTAssertGreaterThan(title.frame.minY, app.frame.height * 0.55)
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        XCTAssertLessThan(title.frame.minY, app.frame.height * 0.3)
        XCTAssertFalse(app.staticTexts["connection.code"].exists)
        app.buttons["connection.cancel"].tap()
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
    }

    /// T93: the picker offers Codex first, then Cursor, with spoken names.
    /// T98 (D-78): each tile shows its name under the icon and is fully visible at the short detent.
    @MainActor
    func testT93PickerShowsCodexThenCursor() throws {
        let app = launch("51")
        defer { app.terminate() }
        app.buttons["quota.toolbarConnect"].tap()
        let codex = app.buttons["platforms.codex"], cursor = app.buttons["platforms.cursor"]
        XCTAssertTrue(codex.waitForExistence(timeout: 5)); XCTAssertTrue(cursor.exists)
        XCTAssertEqual(codex.label, "Codex"); XCTAssertEqual(cursor.label, "Cursor")
        XCTAssertEqual(codex.frame.midY, cursor.frame.midY, accuracy: 1)
        XCTAssertLessThan(codex.frame.minX, cursor.frame.minX, "Codex在前")
        XCTAssertGreaterThanOrEqual(codex.frame.height, 88, "灰框放下图标和名称（矮档位悬浮弹层略缩放）")
        XCTAssertLessThan(codex.frame.height, 130, "灰框只略增")
        XCTAssertLessThanOrEqual(cursor.frame.maxY, app.frame.height - 8, "不上拉即可看到整格")
        XCTAssertTrue(cursor.isHittable)
        let shot = app.screenshot()
        saveFixtureScreenshot(app, name: "T93-平台选择")
        if let out = ProcessInfo.processInfo.environment["T93_OUT"] {
            try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
            try shot.pngRepresentation.write(to: URL(fileURLWithPath: out).appendingPathComponent("T93-picker.png"))
        }
    }

    @MainActor
    func testT16PlatformPickerStartsCompactExpandsAndReopensCompact() {
        let app = launch("51")
        defer { app.terminate() }
        app.buttons["quota.toolbarConnect"].tap()
        let title = app.staticTexts["connection.title"]
        let icon = app.buttons["platforms.codex"]
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "连接账号")
        XCTAssertGreaterThan(title.frame.minY, app.frame.height * 0.55)
        XCTAssertEqual(icon.label, "Codex", "读屏名称不变")
        XCTAssertLessThanOrEqual(icon.frame.maxY, app.frame.height - 8, "矮档位不上拉即可看到整格")
        XCTAssertFalse(app.staticTexts["GPT"].exists)
        XCTAssertFalse(app.staticTexts["connection.code"].exists)
        XCTAssertFalse(app.otherElements["connection.progress"].exists)
        saveFixtureScreenshot(app, name: "T16-平台选择-初始")
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        XCTAssertTrue(icon.isHittable)
        XCTAssertLessThan(title.frame.minY, app.frame.height * 0.3)
        saveFixtureScreenshot(app, name: "T16-平台选择-展开")
        app.buttons["connection.cancel"].tap()
        XCTAssertTrue(app.buttons["quota.toolbarConnect"].waitForExistence(timeout: 5))
        app.buttons["quota.toolbarConnect"].tap()
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(title.frame.minY, app.frame.height * 0.55)
        icon.tap()
        XCTAssertTrue(app.staticTexts["connection.code"].waitForExistence(timeout: 5))
        app.buttons["connection.cancel"].tap()
    }

    @MainActor
    func testT16ExpandedPickerScrollsOverflowBelowFixedHeader() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t07-isolated-ui", "51", "--t16-platform-grid-overflow"]
        app.launch()
        defer { app.terminate() }
        app.buttons["quota.toolbarConnect"].tap()
        XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
        let title = app.staticTexts["connection.title"]
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)))
        XCTAssertLessThan(title.frame.minY, app.frame.height * 0.3)
        let headerY = title.frame.minY
        for _ in 0..<4 { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(app.buttons["platforms.fixture.29"].isHittable)
        XCTAssertEqual(title.frame.minY, headerY, accuracy: 3)
        XCTAssertTrue(app.buttons["connection.cancel"].isHittable)
        saveFixtureScreenshot(app, name: "T16-平台选择-隔离溢出滚动")
        app.buttons["connection.cancel"].tap()
    }

    @MainActor
    func testCodeCopyAndCancelFromAllEntryPoints() {
        let app = launch("51")
        for entry in ["quota.connect", "quota.toolbarConnect"] {
            app.buttons[entry].tap()
            XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
            app.buttons["platforms.codex"].tap()
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
        }
        app.buttons["tab.quota"].tap()
        XCTAssertTrue(app.staticTexts["未连接账户"].exists)
    }

    /// T98 (D-78): light / dark at normal and the largest accessibility text. Names stay on one line,
    /// the short detent shows whole tiles without pulling up, and tapping still starts the same flow.
    @MainActor
    func testT98PickerNamesLightDarkAndMaximumText() {
        continueAfterFailure = false
        for large in [false, true] {
            for dark in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["--t07-isolated-ui", "51", "-appearance", dark ? "dark" : "light"]
                    + (large ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
                app.launch()
                app.buttons["quota.toolbarConnect"].tap()
                let codex = app.buttons["platforms.codex"], cursor = app.buttons["platforms.cursor"]
                XCTAssertTrue(codex.waitForExistence(timeout: 5))
                XCTAssertEqual(codex.label, "Codex"); XCTAssertEqual(cursor.label, "Cursor")
                XCTAssertTrue(codex.isHittable); XCTAssertTrue(cursor.isHittable)
                XCTAssertEqual(codex.frame.midY, cursor.frame.midY, accuracy: 1)
                XCTAssertLessThanOrEqual(cursor.frame.maxX, app.frame.width, "三列不溢出屏幕")
                XCTAssertLessThanOrEqual(cursor.frame.maxY, app.frame.height - 8, "不上拉即可看到整格")
                saveFixtureScreenshot(app, name: "T98-\(large ? "最大字号" : "常规")-\(dark ? "深色" : "浅色")")
                codex.tap()
                XCTAssertTrue(app.staticTexts["connection.code"].waitForExistence(timeout: 5), "点击后流程不变")
                app.buttons["connection.cancel"].tap()
                app.terminate()
            }
        }
    }

    @MainActor
    func testLowUnknownAndRequestFailureShowBriefResults() {
        for (scenario, message) in [("50", "网络不达标，无法连接"),
                                    ("unknown", "登录未完成，请重试"),
                                    ("request-failure", "登录未完成，请重试")] {
            let app = launch(scenario)
            app.buttons["quota.connect"].tap()
            XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
            app.buttons["platforms.codex"].tap()
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
        XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
        app.buttons["platforms.codex"].tap()
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
