import XCTest

final class CodexQuotaUITests: XCTestCase {
    @MainActor
    func testT16SixAccountsRemainScrollableInBothLists() {
        let app = XCUIApplication()
        app.launchArguments = ["--t16-isolated-ui", "success", "--t16-run-id", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        for index in 1...6 {
            app.buttons[index == 1 ? "quota.connect" : "quota.toolbarConnect"].tap()
            XCTAssertTrue(app.buttons["connection.open"].waitForExistence(timeout: 5))
            app.buttons["connection.open"].tap()
            XCTAssertTrue(app.buttons["quota.toolbarConnect"].waitForExistence(timeout: 10))
            let deadline = Date().addingTimeInterval(10)
            while app.staticTexts["connection.title"].exists && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            XCTAssertFalse(app.staticTexts["connection.title"].exists)
        }
        for _ in 0..<4 { app.swipeUp() }
        XCTAssertTrue(app.staticTexts["account-6@example.invalid"].isHittable)
        screenshot(app, "T16-六账户滚动末尾")
        app.buttons["tab.settings"].tap()
        app.buttons["settings.accounts"].tap()
        XCTAssertTrue(app.staticTexts["account-6@example.invalid"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "accounts.identity").count, 6)
        screenshot(app, "T16-六账户管理")
    }

    @MainActor
    func testT16TwoAccountAdditionManagementAndReopen() {
        let app = XCUIApplication()
        app.launchArguments = ["--t16-isolated-ui", "success", "--t16-run-id", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        for index in 1...2 {
            let connect = app.buttons[index == 1 ? "quota.connect" : "quota.toolbarConnect"]
            XCTAssertTrue(connect.waitForExistence(timeout: 5))
            connect.tap()
            XCTAssertTrue(app.buttons["connection.open"].waitForExistence(timeout: 5))
            app.buttons["connection.open"].tap()
            XCTAssertTrue(app.staticTexts["account-\(index)@example.invalid"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["quota.weekly.remaining"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["quota.toolbarConnect"].waitForExistence(timeout: 5))
        }
        let identities = app.staticTexts.matching(identifier: "quota.accountIdentity")
        XCTAssertEqual(identities.allElementsBoundByIndex.map(\.label), ["account-1@example.invalid", "account-2@example.invalid"])
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label), ["剩余 80%", "剩余 35%"])
        screenshot(app, "T16-两账户独立额度")
        app.buttons["tab.settings"].tap()
        app.buttons["settings.accounts"].tap()
        XCTAssertTrue(app.buttons["accounts.connect"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "accounts.identity").allElementsBoundByIndex.map(\.label), ["account-1@example.invalid", "account-2@example.invalid"])
        screenshot(app, "T16-账户管理")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["account-2@example.invalid"].waitForExistence(timeout: 10))
        XCTAssertEqual(identities.allElementsBoundByIndex.map(\.label), ["account-1@example.invalid", "account-2@example.invalid"])
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.fiveHours.remaining").allElementsBoundByIndex.map(\.label), ["剩余 70%", "剩余 25%"])
    }

    @MainActor
    func testT16FailedSecondAccountKeepsFirstAndIdentifiesFailure() {
        let app = XCUIApplication()
        app.launchArguments = ["--t16-isolated-ui", "failure", "--t16-run-id", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        app.buttons["quota.connect"].tap()
        XCTAssertTrue(app.buttons["connection.open"].waitForExistence(timeout: 5))
        app.buttons["connection.open"].tap()
        XCTAssertTrue(app.staticTexts["quota.weekly.remaining"].waitForExistence(timeout: 10))
        app.buttons["quota.toolbarConnect"].tap()
        XCTAssertTrue(app.buttons["connection.open"].waitForExistence(timeout: 5))
        app.buttons["connection.open"].tap()
        XCTAssertTrue(app.buttons["connection.quotaClose"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["connection.accountIdentity"].label, "account-2@example.invalid")
        app.buttons["connection.quotaClose"].tap()
        XCTAssertTrue(app.staticTexts["account-2@example.invalid"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["quota.weekly.remaining"].label, "剩余 80%")
        XCTAssertEqual(app.staticTexts["quota.fiveHours.remaining"].label, "剩余 70%")
        screenshot(app, "T16-B失败保留A")
    }

    @MainActor
    func testAutomaticQuotaAfterLoginAndSameResultOnReopen() {
        let app = launch("success")
        defer { app.terminate() }
        completeFixtureLogin(app)
        assertSuccessfulCard(app)
        XCTAssertFalse(app.staticTexts["quota.updatedAt"].exists)
        XCTAssertFalse(app.staticTexts["connection.title"].exists)
        XCTAssertFalse(app.buttons["quota.refresh"].isEnabled)
        let card = app.otherElements["quota.card"]
        XCTAssertEqual(card.frame.minX, 16, accuracy: 1)
        XCTAssertEqual(app.frame.width - card.frame.maxX, 16, accuracy: 1)
        XCTAssertGreaterThan(app.buttons["tab.settings"].frame.midX, app.frame.width * 0.65)
        XCTAssertLessThan(app.buttons["tab.quota"].frame.midX, app.frame.width * 0.35)
        screenshot(app, "T13-样式-额度恢复")
        openDetails(app)
        let date = app.staticTexts["quota.updatedAt"].label
        screenshot(app, "T13-样式-展开时间")
        app.terminate()
        app.launch()
        assertSuccessfulCard(app)
        XCTAssertFalse(app.staticTexts["quota.updatedAt"].exists)
        openDetails(app)
        XCTAssertEqual(app.staticTexts["quota.updatedAt"].label, date)
    }

    @MainActor
    func testMissingWindowAndResetAreReadableWithoutFakeZero() {
        let app = launch("partial")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.staticTexts["quota.weekly.remaining"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.weekly.remaining"].label, "剩余 70%")
        XCTAssertEqual(app.staticTexts["quota.fiveHours.remaining"].label, "未知")
        XCTAssertEqual(app.staticTexts["quota.weekly.reset"].label, "未提供重置时间")
        XCTAssertEqual(app.staticTexts["quota.fiveHours.reset"].label, "未提供重置时间")
        XCTAssertTrue(app.otherElements["quota.weekly.bar"].exists)
        XCTAssertFalse(app.otherElements["quota.fiveHours.bar"].exists)
        screenshot(app, "T13-样式-未知窗口")
    }

    @MainActor
    func testFreeShowsPlatformPlanWithoutQuotaOrErrorAndPersists() {
        let app = launch("free")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.staticTexts["Codex · Free"].waitForExistence(timeout: 10))
        assertNoQuotaOrFailure(app)
        screenshot(app, "T13-样式-Free")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Codex · Free"].waitForExistence(timeout: 10))
        assertNoQuotaOrFailure(app)
    }

    @MainActor
    func testT13ConnectionFailureRetriesInSameBottomSheet() {
        let app = launch("retry-plan")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.buttons["connection.quotaRetry"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["connection.title"].label, "首次额度查询失败")
        XCTAssertEqual(app.staticTexts["connection.quotaFailure"].label, "获取失败")
        XCTAssertGreaterThan(app.staticTexts["connection.title"].frame.minY, app.frame.height / 2)
        let identity = app.staticTexts["connection.accountIdentity"].label
        screenshot(app, "T13-样式-连接弹层失败")
        app.buttons["connection.quotaRetry"].tap()
        assertSuccessfulCard(app)
        XCTAssertFalse(app.staticTexts["connection.title"].exists)
        XCTAssertEqual(app.staticTexts["quota.accountIdentity"].label, identity)
        XCTAssertEqual(planLabel(app), "Codex · Future Official Plan")
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").count, 1)
        screenshot(app, "T13-样式-弹层恢复")
    }

    @MainActor
    func testT13DashboardRetryUsesTopFeedbackAndCloseKeepsState() {
        let app = launch("retry-twice")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.buttons["connection.quotaClose"].waitForExistence(timeout: 10))
        app.buttons["connection.quotaClose"].tap()
        XCTAssertTrue(app.buttons["quota.refresh"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        let identity = app.staticTexts["quota.accountIdentity"].label
        app.buttons["quota.refresh"].tap()
        XCTAssertTrue(app.buttons["quota.retry"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["connection.title"].exists)
        XCTAssertLessThan(app.staticTexts["quota.failure"].frame.maxY, app.otherElements["quota.card"].frame.minY)
        screenshot(app, "T13-样式-顶部更新失败")
        let before = app.otherElements["quota.card"].frame.minY
        app.buttons["quota.closeFeedback"].tap()
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        XCTAssertLessThan(app.otherElements["quota.card"].frame.minY, before - 30)
        XCTAssertEqual(app.staticTexts["quota.accountStatus"].label, "获取失败")
        app.buttons["tab.settings"].tap()
        app.buttons["tab.quota"].tap()
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        XCTAssertEqual(app.staticTexts["quota.accountIdentity"].label, identity)
        app.buttons["quota.refresh"].tap()
        assertSuccessfulCard(app)
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        screenshot(app, "T13-样式-顶部恢复")
    }

    @MainActor
    func testT13LowUnknownAndRequestFailuresRecoverThroughRetryButton() {
        for scenario in ["retry-blocked", "retry-unknown", "retry-request"] {
            let app = launch(scenario)
            completeFixtureLogin(app)
            XCTAssertTrue(app.buttons["connection.quotaRetry"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.staticTexts["connection.quotaFailure"].label,
                           scenario == "retry-blocked" ? "网络不达标，无法更新" : "获取失败")
            app.buttons["connection.quotaRetry"].tap()
            assertSuccessfulCard(app)
            app.terminate()
        }
    }

    @MainActor
    func testT13RetryCanRecoverToFreeWithoutFalseFailure() {
        let app = launch("retry-free")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.buttons["connection.quotaRetry"].waitForExistence(timeout: 10))
        app.buttons["connection.quotaRetry"].tap()
        XCTAssertTrue(app.staticTexts["Codex · Free"].waitForExistence(timeout: 10))
        assertNoQuotaOrFailure(app)
    }

    @MainActor
    func testFailedQueryReopensWithTopFeedbackWithoutLosingAccount() {
        let app = launch("plan-only-failure")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.buttons["connection.quotaClose"].waitForExistence(timeout: 10))
        let identity = app.staticTexts["connection.accountIdentity"].label
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["connection.title"].exists)
        XCTAssertEqual(planLabel(app), "Codex · Future Official Plan")
        XCTAssertEqual(app.staticTexts["quota.accountIdentity"].label, identity)
        XCTAssertFalse(app.staticTexts["quota.updatedAt"].exists)
        XCTAssertFalse(app.staticTexts["quota.weekly.remaining"].exists)
    }

    @MainActor
    func testQueryProgressStaysWithItsOriginAndDoesNotOfferFailureClose() {
        let connection = launch("slow-quota")
        completeFixtureLogin(connection)
        XCTAssertTrue(connection.descendants(matching: .any)["connection.quotaProgress"].waitForExistence(timeout: 10))
        XCTAssertEqual(connection.staticTexts["connection.title"].label, "正在获取额度")
        screenshot(connection, "T13-样式-连接查询中")
        connection.buttons["connection.cancel"].tap()
        assertSuccessfulCard(connection)
        XCTAssertFalse(connection.staticTexts["connection.title"].exists)
        connection.terminate()

        let dashboard = launch("retry-slow")
        defer { dashboard.terminate() }
        completeFixtureLogin(dashboard)
        XCTAssertTrue(dashboard.buttons["connection.quotaClose"].waitForExistence(timeout: 10))
        dashboard.buttons["connection.quotaClose"].tap()
        dashboard.buttons["quota.refresh"].tap()
        XCTAssertTrue(dashboard.otherElements["quota.updating"].waitForExistence(timeout: 5))
        XCTAssertFalse(dashboard.buttons["quota.closeFeedback"].exists)
        XCTAssertFalse(dashboard.staticTexts["connection.title"].exists)
        screenshot(dashboard, "T13-样式-顶部查询中")
        assertSuccessfulCard(dashboard)
    }

    @MainActor
    func testLargeTextPreservesReadableCardAndReachableActions() {
        let app = launch("new-plan", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.staticTexts["quota.weekly.remaining"].waitForExistence(timeout: 10))
        XCTAssertEqual(planLabel(app), "Codex · Future Official Plan")
        XCTAssertTrue(app.buttons["quota.details"].isHittable)
        XCTAssertTrue(app.buttons["tab.settings"].isHittable)
        XCTAssertLessThanOrEqual(app.otherElements["quota.card"].frame.maxX, app.frame.width)
        screenshot(app, "T13-样式-大字")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["quota.fiveHours.remaining"].isHittable)
    }

    @MainActor
    func testRealSavedQuotaAppearsOnNormalLaunchAndReopen() throws {
        guard ProcessInfo.processInfo.environment["T12_LIVE_REOPEN"] == "1" else { throw XCTSkip("显式开启后才检查真实账户页面。") }
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["quota.card"].waitForExistence(timeout: 30))
        let identity = app.staticTexts["quota.accountIdentity"].label
        let plan = planLabel(app)
        XCTAssertTrue(plan.hasPrefix("Codex · "))
        let free = plan.lowercased() == "codex · free"
        if free { assertNoQuotaOrFailure(app) } else { openDetails(app) }
        let ids = ["quota.weekly.remaining", "quota.weekly.reset", "quota.fiveHours.remaining", "quota.fiveHours.reset", "quota.updatedAt"]
        let labels = free ? [] : ids.map { app.staticTexts[$0].label }
        app.terminate(); app.launch()
        XCTAssertTrue(app.otherElements["quota.card"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["quota.accountIdentity"].label == identity)
        XCTAssertTrue(planLabel(app) == plan)
        if free { assertNoQuotaOrFailure(app) }
        else { openDetails(app); XCTAssertTrue(ids.map { app.staticTexts[$0].label } == labels) }
        print("T13 样式 | 真实普通启动与重开 | 身份、套餐与数据保持；未输出账户资料或真实截图")
    }

    @MainActor
    func testT15OfflineCacheAndPartialFieldsAppearBeforeLoginRecovery() {
        for scenario in ["success", "partial"] {
            let app = launch(scenario)
            completeFixtureLogin(app)
            XCTAssertTrue(app.staticTexts["quota.weekly.remaining"].waitForExistence(timeout: 10))
            openDetails(app)
            let identity = app.staticTexts["quota.accountIdentity"].label
            let ids = ["quota.weekly.remaining", "quota.fiveHours.remaining", "quota.updatedAt"]
            let savedLabels = ids.map { app.staticTexts[$0].label }
            app.terminate()
            app.launchArguments += ["--t15-offline", "--t15-delay-login-read"]
            app.launch()
            XCTAssertTrue(app.otherElements["quota.card"].waitForExistence(timeout: 5), "不等待60秒登录恢复")
            XCTAssertEqual(app.staticTexts["quota.accountIdentity"].label, identity)
            XCTAssertFalse(app.staticTexts["quota.failure"].exists)
            XCTAssertFalse(app.otherElements["quota.updating"].exists)
            openDetails(app)
            XCTAssertEqual(ids.map { app.staticTexts[$0].label }, savedLabels)
            if scenario == "partial" {
                XCTAssertEqual(app.staticTexts["quota.fiveHours.remaining"].label, "未知")
                XCTAssertEqual(app.staticTexts["quota.weekly.reset"].label, "未提供重置时间")
            }
            screenshot(app, "T15-离线缓存-" + scenario)
            app.buttons["tab.settings"].tap()
            app.buttons["tab.quota"].tap()
            XCTAssertTrue(app.otherElements["quota.card"].exists)
            XCTAssertFalse(app.staticTexts["connection.title"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testT15NeverFetchedReadOnlyReopenKeepsIdentityAndNoInventedQuota() {
        let app = launch("plan-only-failure")
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.buttons["connection.quotaClose"].waitForExistence(timeout: 10))
        let identity = app.staticTexts["connection.accountIdentity"].label
        app.terminate()
        // This fixture isolates local reading. Production still performs T12's
        // first-fetch recovery; its pending/failure behavior is tested separately.
        app.launchArguments += ["--t15-read-only", "--t15-offline", "--t15-delay-login-read"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quota.notFetched"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["quota.notFetched"].label, "尚未获取额度")
        XCTAssertEqual(app.staticTexts["quota.accountIdentity"].label, identity)
        XCTAssertEqual(planLabel(app), "Codex · Future Official Plan")
        for id in ["quota.weekly.remaining", "quota.fiveHours.remaining", "quota.updatedAt", "quota.failure"] {
            XCTAssertFalse(app.staticTexts[id].exists)
        }
        screenshot(app, "T15-只读恢复未获取账户")
    }

    @MainActor private func assertSuccessfulCard(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["quota.weekly.remaining"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.weekly.remaining"].label, "剩余 70%")
        XCTAssertEqual(app.staticTexts["quota.fiveHours.remaining"].label, "剩余 20%")
        XCTAssertEqual(app.otherElements["quota.weekly.bar"].value as? String, "已用 30%，剩余 70%")
        XCTAssertEqual(app.otherElements["quota.fiveHours.bar"].value as? String, "已用 80%，剩余 20%")
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
    }
    @MainActor private func planLabel(_ app: XCUIApplication) -> String {
        let details = app.buttons["quota.details"]
        return details.exists ? details.label : app.staticTexts["quota.plan"].label
    }
    @MainActor private func openDetails(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["quota.details"].waitForExistence(timeout: 10))
        app.buttons["quota.details"].tap()
        XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 5))
    }
    @MainActor private func assertNoQuotaOrFailure(_ app: XCUIApplication) {
        for id in ["quota.accountStatus", "quota.failure", "quota.updatedAt", "quota.weekly.remaining", "quota.fiveHours.remaining", "quota.weekly.reset", "quota.fiveHours.reset", "quota.updating", "connection.quotaFailure"] {
            XCTAssertFalse(app.descendants(matching: .any)[id].exists, id)
        }
        XCTAssertTrue(app.staticTexts["quota.accountIdentity"].exists)
    }
    @MainActor private func launch(_ scenario: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t12-isolated-ui", scenario, "--t08-run-id", UUID().uuidString] + extra
        app.launch()
        return app
    }
    @MainActor private func completeFixtureLogin(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["quota.connect"].waitForExistence(timeout: 10))
        app.buttons["quota.connect"].tap()
        XCTAssertTrue(app.staticTexts["connection.code"].waitForExistence(timeout: 5))
        app.buttons["connection.open"].tap()
    }
    @MainActor private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
