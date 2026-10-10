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
    private func launch(_ scenario: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t08-isolated-ui", scenario, "--t08-run-id", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.buttons["quota.connect"].waitForExistence(timeout: 5))
        return app
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
        // Only TEST-CODE and example.invalid identities can occur in this launch mode.
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "T08-隔离-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func cleanUp(_ app: XCUIApplication) {
        app.terminate()
        app.launchArguments += ["--t08-reset-storage"]
        app.launch()
        XCTAssertTrue(app.buttons["quota.connect"].waitForExistence(timeout: 5))
        app.terminate()
    }
}
