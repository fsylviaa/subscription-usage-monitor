import XCTest

final class CodexLoginCompletionUITests: XCTestCase {
    @MainActor
    func testVerifiedIdentityAppearsWithoutQuotaAndSurvivesRelaunch() {
        let app = launch("success")
        defer { cleanUp(app) }
        app.buttons["quota.connect"].tap()
        XCTAssertTrue(app.staticTexts["connection.code"].waitForExistence(timeout: 5))
        assertNoAccountAppears(in: app, during: 2)
        app.buttons["connection.open"].tap() // Stub opener; no browser or network request.

        assertConnectedIdentity(in: app)
        saveFixtureScreenshot(app, name: "核验成功")
        app.terminate()
        app.launch() // Same unique run ID restores only this test's temporary account file.
        assertConnectedIdentity(in: app)
        saveFixtureScreenshot(app, name: "重开账户仍在")
        app.tabBars.buttons["设置"].tap()
        XCTAssertFalse(app.buttons["settings.connect"].isEnabled)
    }

    @MainActor
    func testIdentityVerificationFailureDoesNotCreateAccount() {
        let app = launch("verification-failure")
        defer { cleanUp(app) }
        app.buttons["quota.connect"].tap()
        XCTAssertTrue(app.staticTexts["connection.code"].waitForExistence(timeout: 5))
        app.buttons["connection.open"].tap()
        XCTAssertTrue(app.staticTexts["登录未完成，请重试"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["quota.accountIdentity"].exists)
        XCTAssertTrue(app.buttons["connection.retry"].exists)
        saveFixtureScreenshot(app, name: "核验失败")
        app.buttons["connection.cancel"].tap()
        XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["quota.connect"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["quota.accountIdentity"].exists)
    }

    @MainActor
    func testOpeningWebsiteAloneKeepsWaitingWithoutAccount() {
        let app = launch("pending")
        defer { cleanUp(app) }
        app.buttons["quota.connect"].tap()
        XCTAssertTrue(app.staticTexts["connection.code"].waitForExistence(timeout: 5))
        app.buttons["connection.open"].tap()
        assertNoAccountAppears(in: app, during: 3)
        XCTAssertTrue(app.staticTexts["connection.code"].exists)
        XCTAssertFalse(app.staticTexts["登录未完成，请重试"].exists)
        saveFixtureScreenshot(app, name: "仅打开官网仍等待")
        app.buttons["connection.cancel"].tap()
        XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDeniedLoginCanRetryWithNewCodeAndComplete() {
        assertFailedLoginCanRetry(scenario: "denied", screenshotName: "授权拒绝可重试")
    }

    @MainActor
    func testExchangeFailureCanRetryWithNewCodeAndComplete() {
        assertFailedLoginCanRetry(scenario: "exchange-failure", screenshotName: "交换失败可重试")
    }

    @MainActor
    func testExpiredCodeIsReplacedAndNewLoginCompletes() {
        let app = launchRecovery("expired")
        defer { cleanUp(app) }
        app.buttons["quota.connect"].tap()
        let code = app.staticTexts["connection.code"]
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertEqual(code.label, "TEST-0001")
        assertRecoverableFailure(in: app)
        saveFixtureScreenshot(app, name: "代码到期可重试")
        app.buttons["connection.retry"].tap()
        assertNewCodeAndComplete(in: app)
        saveFixtureScreenshot(app, name: "到期后新码成功")
    }

    @MainActor
    func testCancelledLoginReturnsToEntryAndNextLoginCompletes() {
        let app = launchRecovery("cancel")
        defer { cleanUp(app) }
        app.buttons["quota.connect"].tap()
        XCTAssertTrue(app.staticTexts["connection.code"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["connection.code"].label, "TEST-0001")
        app.buttons["connection.cancel"].tap()
        XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["quota.accountIdentity"].exists)
        XCTAssertFalse(app.staticTexts["connection.code"].exists)
        saveFixtureScreenshot(app, name: "取消返回原入口")
        app.buttons["quota.connect"].tap()
        assertNewCodeAndComplete(in: app)
        saveFixtureScreenshot(app, name: "取消后新码成功")
    }

    @MainActor
    func testRealSavedAccountSurvivesRelaunch() throws {
        guard ProcessInfo.processInfo.environment["T08_LIVE_REOPEN"] == "1" else {
            throw XCTSkip("仅在用户官网确认后显式核验真实账户重开；不附真实身份截图。")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let identity = app.staticTexts["quota.accountIdentity"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10), "正常启动后真实账户可见")
        let original = identity.label
        XCTAssertTrue(original.contains("@") && !original.hasSuffix(".invalid"), "真实账户标识存在，非隔离样例")
        XCTAssertTrue(app.staticTexts["quota.notFetched"].exists)
        XCTAssertFalse(app.buttons["quota.toolbarConnect"].isEnabled)
        app.terminate()
        app.launch()
        XCTAssertTrue(identity.waitForExistence(timeout: 10), "关闭并重开后账户存在")
        XCTAssertTrue(identity.label == original, "重开后身份一致；不在报告打印邮箱")
        XCTAssertTrue(app.staticTexts["quota.notFetched"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "%")).count, 0)
        print("T08 | 真实页面重开 | 正常启动显示真实身份；关闭重开后同账户仍在，尚未获取额度，无虚构百分比；不记录邮箱或截图")
    }

    @MainActor
    func testRealT09IsolatedAccountSurvivesRelaunch() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["T09_LIVE_REOPEN"] == "1" else {
            throw XCTSkip("仅显式核验已完成官网确认的 T09 独立账户；不附真实身份截图。")
        }
        continueAfterFailure = false
        guard let suppliedID = environment["T09_LIVE_RUN_ID"],
              let runID = UUID(uuidString: suppliedID), suppliedID.uppercased() == runID.uuidString else {
            XCTFail("T09 真实重开检查需要有效的 T09_LIVE_RUN_ID；未启动 App。")
            return
        }
        let app = XCUIApplication()
        app.launchArguments = ["--t09-live-ui", "--t09-live-run-id", runID.uuidString]
        app.launch()
        let identity = app.staticTexts["quota.accountIdentity"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10), "指定隔离账户已完成真实登录")
        let original = identity.label
        XCTAssertTrue(original.contains("@") && !original.hasSuffix(".invalid"), "真实账户标识存在，非虚构样例")
        XCTAssertTrue(app.staticTexts["quota.notFetched"].exists)
        XCTAssertFalse(app.buttons["quota.toolbarConnect"].isEnabled)
        app.terminate()
        app.launch()
        XCTAssertTrue(identity.waitForExistence(timeout: 10), "重开后指定隔离账户仍存在")
        XCTAssertTrue(identity.label == original, "重开后身份一致；不在报告打印邮箱")
        XCTAssertTrue(app.staticTexts["quota.notFetched"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "%")).count, 0)
        print("T09 | 真实隔离页面重开 | 指定独立存储显示真实身份；关闭重开后同账户仍在，尚未获取额度；未读取正式账户，不记录邮箱或截图")
    }

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t08-isolated-ui", scenario, "--t08-run-id", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["quota.connect"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func launchRecovery(_ scenario: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t09-isolated-ui", scenario, "--t09-run-id", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["quota.connect"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func assertFailedLoginCanRetry(scenario: String, screenshotName: String) {
        let app = launchRecovery(scenario)
        defer { cleanUp(app) }
        app.buttons["quota.connect"].tap()
        XCTAssertTrue(app.staticTexts["connection.code"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["connection.code"].label, "TEST-0001")
        app.buttons["connection.open"].tap()
        assertRecoverableFailure(in: app)
        saveFixtureScreenshot(app, name: screenshotName)
        app.buttons["connection.retry"].tap()
        assertNewCodeAndComplete(in: app)
        saveFixtureScreenshot(app, name: "\(screenshotName)-新码成功")
    }

    @MainActor
    private func assertRecoverableFailure(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["登录未完成，请重试"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["connection.retry"].isEnabled)
        XCTAssertTrue(app.buttons["connection.cancel"].isEnabled)
        XCTAssertFalse(app.staticTexts["connection.code"].exists)
        XCTAssertFalse(app.staticTexts["quota.accountIdentity"].exists)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "%")).count, 0)
    }

    @MainActor
    private func assertNewCodeAndComplete(in app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["connection.code"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["connection.code"].label, "TEST-0002")
        XCTAssertFalse(app.staticTexts["quota.accountIdentity"].exists)
        app.buttons["connection.open"].tap()
        assertConnectedIdentity(in: app)
    }

    @MainActor
    private func assertConnectedIdentity(in app: XCUIApplication) {
        let identity = app.staticTexts["quota.accountIdentity"]
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        XCTAssertEqual(identity.label, "test-user@example.invalid")
        XCTAssertTrue(app.staticTexts["quota.notFetched"].exists)
        XCTAssertEqual(app.staticTexts["quota.notFetched"].label, "尚未获取额度")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "%")).count, 0)
        XCTAssertFalse(app.buttons["quota.toolbarConnect"].isEnabled)
        XCTAssertFalse(app.buttons["quota.refresh"].isEnabled)
        XCTAssertFalse(app.buttons["connection.cancel"].exists)
    }

    @MainActor
    private func assertNoAccountAppears(in app: XCUIApplication, during timeout: TimeInterval) {
        let unexpectedAccount = expectation(for: NSPredicate(format: "exists == true"),
                                            evaluatedWith: app.staticTexts["quota.accountIdentity"])
        unexpectedAccount.isInverted = true
        wait(for: [unexpectedAccount], timeout: timeout)
    }

    @MainActor
    private func saveFixtureScreenshot(_ app: XCUIApplication, name: String) {
        // Only TEST codes and example.invalid identities can occur in these launch modes.
        let attachment = XCTAttachment(screenshot: app.screenshot())
        let task = app.launchArguments.contains("--t09-isolated-ui") ? "T09" : "T08"
        attachment.name = "\(task)-隔离-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func cleanUp(_ app: XCUIApplication) {
        app.terminate()
        let reset = app.launchArguments.contains("--t09-isolated-ui") ? "--t09-reset-storage" : "--t08-reset-storage"
        app.launchArguments += [reset]
        app.launch()
        XCTAssertTrue(app.buttons["quota.connect"].waitForExistence(timeout: 5))
        app.terminate()
    }
}
