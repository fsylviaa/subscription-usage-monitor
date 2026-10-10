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
        XCTAssertFalse(app.staticTexts["quota.notFetched"].exists)
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
    func testFreeShowsPlatformPlanWithoutQuotaOrErrorAndPersists() {
        let app = launch("free")
        defer { app.terminate() }
        completeFixtureLogin(app)
        let title = app.staticTexts["quota.plan"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Codex · Free"].waitForExistence(timeout: 10))
        assertNoQuotaOrFailure(app)
        screenshot(app, "T12-Free-隔离")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Codex · Free"].waitForExistence(timeout: 10))
        assertNoQuotaOrFailure(app)
    }

    @MainActor
    func testReliablePlanStillAppearsWhenQuotaFails() {
        let app = launch("plan-only-failure")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.plan"].label, "Codex · Future Official Plan")
        XCTAssertEqual(app.staticTexts["quota.failure"].label, "获取失败")
        XCTAssertFalse(app.staticTexts["quota.updatedAt"].exists)
        XCTAssertFalse(app.staticTexts["quota.notFetched"].exists)
        screenshot(app, "T12-套餐成功额度失败-隔离")
    }

    @MainActor
    func testPreviouslyUnknownPlanDisplaysWithSupportedQuota() {
        let app = launch("new-plan")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.plan"].label, "Codex · Future Official Plan")
        XCTAssertEqual(app.staticTexts["quota.weekly.remaining"].label, "剩余 70%")
    }

    @MainActor
    private func assertNoQuotaOrFailure(_ app: XCUIApplication) {
        for id in ["quota.notFetched", "quota.failure", "quota.updatedAt", "quota.weekly.remaining",
                   "quota.fiveHours.remaining", "quota.weekly.reset", "quota.fiveHours.reset", "quota.updating"] {
            XCTAssertFalse(app.descendants(matching: .any)[id].exists, id)
        }
        XCTAssertTrue(app.staticTexts["quota.accountIdentity"].exists)
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
        XCTAssertTrue(app.staticTexts["quota.plan"].waitForExistence(timeout: 30))
        // Compare in memory; never print identity or attach real screenshots.
        let identity = app.staticTexts["quota.accountIdentity"].label
        let plan = app.staticTexts["quota.plan"].label
        XCTAssertTrue(plan.hasPrefix("Codex · "))
        let freeWithoutQuota = plan.lowercased() == "codex · free" && !app.staticTexts["quota.updatedAt"].exists
        let ids = ["quota.weekly.remaining", "quota.weekly.reset", "quota.fiveHours.remaining", "quota.fiveHours.reset", "quota.updatedAt"]
        let labels = freeWithoutQuota ? [] : ids.map { app.staticTexts[$0].label }
        if freeWithoutQuota { assertNoQuotaOrFailure(app) }
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["quota.plan"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["quota.accountIdentity"].label == identity)
        XCTAssertEqual(app.staticTexts["quota.plan"].label, plan)
        if freeWithoutQuota { assertNoQuotaOrFailure(app) }
        else { XCTAssertTrue(ids.map { app.staticTexts[$0].label } == labels) }
        XCTAssertFalse(app.staticTexts["quota.notFetched"].exists)
        print("T12 | 真实普通启动与重开 | 平台套餐与适用性一致；Free无额度区域和失败提示；身份未输出")
    }

    @MainActor
    func testT13FailedQueryReopensThenRetryKeepsIdentityAndPlan() {
        let app = launch("retry-plan")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.buttons["quota.retry"].waitForExistence(timeout: 10))
        let identity = app.staticTexts["quota.accountIdentity"].label
        XCTAssertEqual(app.staticTexts["quota.plan"].label, "Codex · Future Official Plan")
        XCTAssertEqual(app.staticTexts["quota.failure"].label, "获取失败")
        XCTAssertFalse(app.staticTexts["quota.updatedAt"].exists)
        XCTAssertFalse(app.staticTexts["quota.weekly.remaining"].exists)
        screenshot(app, "T13-失败可重试-隔离")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["quota.retry"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.accountIdentity"].label, identity)
        XCTAssertEqual(app.staticTexts["quota.plan"].label, "Codex · Future Official Plan")
        XCTAssertFalse(app.staticTexts["quota.updatedAt"].exists)
        app.buttons["quota.retry"].tap()
        XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.accountIdentity"].label, identity)
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").count, 1)
        XCTAssertEqual(app.staticTexts["quota.plan"].label, "Codex · Future Official Plan")
        XCTAssertEqual(app.staticTexts["quota.weekly.remaining"].label, "剩余 70%")
        XCTAssertEqual(app.staticTexts["quota.fiveHours.remaining"].label, "剩余 20%")
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        XCTAssertFalse(app.buttons["quota.retry"].exists)
        screenshot(app, "T13-重试成功-隔离")
        let timestamp = app.staticTexts["quota.updatedAt"].label
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.updatedAt"].label, timestamp)
    }

    @MainActor
    func testT13LowUnknownAndRequestFailuresRecoverThroughRetryButton() {
        for scenario in ["retry-blocked", "retry-unknown", "retry-request"] {
            let app = launch(scenario)
            completeFixtureLogin(app)
            XCTAssertTrue(app.buttons["quota.retry"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["quota.failure"].label,
                           scenario == "retry-blocked" ? "网络不达标，无法更新" : "获取失败")
            XCTAssertEqual(app.staticTexts["quota.plan"].label, "Codex")
            XCTAssertFalse(app.staticTexts["quota.updatedAt"].exists)
            XCTAssertFalse(app.staticTexts["quota.weekly.remaining"].exists)
            app.buttons["quota.retry"].tap()
            XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["quota.retry"].exists)
            XCTAssertFalse(app.staticTexts["quota.failure"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testT13RetryCanRecoverToFreeWithoutFalseFailure() {
        let app = launch("retry-free")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.buttons["quota.retry"].waitForExistence(timeout: 10))
        app.buttons["quota.retry"].tap()
        XCTAssertTrue(app.staticTexts["Codex · Free"].waitForExistence(timeout: 10))
        assertNoQuotaOrFailure(app)
        XCTAssertFalse(app.buttons["quota.retry"].exists)
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
