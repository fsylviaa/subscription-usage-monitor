import XCTest

final class ResetReminderUITests: XCTestCase {
    /// Run alone on a fresh simulator with T38_NOTIFICATION_PERMISSION_SCENARIO=allow.
    /// The management session isolates accounts and preferences; notification permission
    /// is deliberately the simulator's real, app-wide permission. No notification is sent.
    @MainActor
    func testT38FirstAllowPersistsAndExplicitOffSurvivesRelaunch() throws {
        try requireFreshSimulatorPermissionScenario("allow")
        let app = launchIsolatedApp()
        defer { app.terminate() }

        assertNoPermissionPrompt()
        openSettings(in: app)
        assertSingleReminder(in: app, enabled: false)
        setDarkAppearance(false, in: app)
        screenshot(app, "T38-允许前-浅色-默认关闭")

        tapSwitch(app.switches["settings.resetReminder"])
        respondToPermissionPrompt(allow: true)
        assertSingleReminder(in: app, enabled: true)
        XCTAssertFalse(app.buttons["settings.notificationSettings"].exists)
        screenshot(app, "T38-首次允许-已开启")

        relaunchAndOpenSettings(app)
        assertSingleReminder(in: app, enabled: true)
        assertNoPermissionPrompt()
        addDemoAccountAndVerifyQuota(in: app)
        openSettings(in: app)
        assertSingleReminder(in: app, enabled: true)
        setDarkAppearance(true, in: app)
        screenshot(app, "T38-允许并重开-深色-全局开启")

        tapSwitch(app.switches["settings.resetReminder"])
        assertSingleReminder(in: app, enabled: false)
        relaunchAndOpenSettings(app)
        assertSingleReminder(in: app, enabled: false)
        assertNoPermissionPrompt()
        screenshot(app, "T38-主动关闭后重开-保持关闭")
        verifyDemoQuota(in: app)
    }

    /// Run alone on a different fresh simulator with T38_NOTIFICATION_PERMISSION_SCENARIO=deny.
    @MainActor
    func testT38FirstDenyAndSystemSettingsRoundTripReflectActualPermission() throws {
        try requireFreshSimulatorPermissionScenario("deny")
        let app = launchIsolatedApp()
        defer { app.terminate() }

        assertNoPermissionPrompt()
        openSettings(in: app)
        assertSingleReminder(in: app, enabled: false)
        tapSwitch(app.switches["settings.resetReminder"])
        respondToPermissionPrompt(allow: false)
        assertDeniedReminder(in: app)
        setDarkAppearance(false, in: app)
        screenshot(app, "T38-首次拒绝-浅色-通知未允许")

        for _ in 0..<2 {
            app.buttons["tab.quota"].tap()
            XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5))
            openSettings(in: app)
            assertDeniedReminder(in: app)
            assertNoPermissionPrompt()
        }
        relaunchAndOpenSettings(app)
        assertDeniedReminder(in: app)
        assertNoPermissionPrompt()
        addDemoAccountAndVerifyQuota(in: app)
        openSettings(in: app)
        assertDeniedReminder(in: app)
        setDarkAppearance(true, in: app)
        screenshot(app, "T38-拒绝并重开-深色-额度仍可用")

        app.buttons["settings.notificationSettings"].tap()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 8))
        let systemToggle = notificationPermissionSwitch(in: settings)
        XCTAssertTrue(systemToggle.waitForExistence(timeout: 8), "入口应直接打开本 App 的通知设置")
        XCTAssertEqual(systemToggle.value as? String, "0")
        screenshot(settings, "T38-系统通知设置-未允许")
        tapSwitch(systemToggle)
        waitForSwitch(systemToggle, enabled: true)
        screenshot(settings, "T38-系统设置-允许通知")

        app.activate()
        assertSingleReminder(in: app, enabled: true)
        XCTAssertFalse(app.buttons["settings.notificationSettings"].exists)
        screenshot(app, "T38-系统允许后返回-自动开启")
        relaunchAndOpenSettings(app)
        assertSingleReminder(in: app, enabled: true)

        // Revisit only the exact notification pane opened by the App above.
        settings.activate()
        let reopenedSystemToggle = notificationPermissionSwitch(in: settings)
        XCTAssertTrue(reopenedSystemToggle.waitForExistence(timeout: 8))
        XCTAssertEqual(reopenedSystemToggle.value as? String, "1")
        tapSwitch(reopenedSystemToggle)
        waitForSwitch(reopenedSystemToggle, enabled: false)
        screenshot(settings, "T38-系统设置-关闭通知")
        app.activate()
        assertDeniedReminder(in: app)
        screenshot(app, "T38-系统关闭后返回-自动关闭")
        relaunchAndOpenSettings(app)
        assertDeniedReminder(in: app)
        assertNoPermissionPrompt()
        verifyDemoQuota(in: app)
    }

    /// Safe for the user's iPhone: does not tap the reminder or change system permission.
    @MainActor
    func testT38DisabledReminderKeepsQuotaUsableInLightAndDarkAppearance() {
        let app = launchIsolatedApp()
        defer { app.terminate() }
        assertNoPermissionPrompt()
        openSettings(in: app)
        assertSingleReminder(in: app, enabled: false)
        XCTAssertFalse(app.buttons["settings.notificationSettings"].exists)
        for dark in [false, true] {
            setDarkAppearance(dark, in: app)
            assertSingleReminder(in: app, enabled: false)
            screenshot(app, "T38-无账户-\(dark ? "深色" : "浅色")-默认关闭")
        }
        addDemoAccountAndVerifyQuota(in: app)
        for dark in [false, true] {
            openSettings(in: app)
            setDarkAppearance(dark, in: app)
            assertSingleReminder(in: app, enabled: false)
            XCTAssertFalse(app.buttons["settings.notificationSettings"].exists)
            screenshot(app, "T38-已有账户-\(dark ? "深色" : "浅色")-单一全局开关")
            verifyDemoQuota(in: app)
            screenshot(app, "T38-提醒关闭-\(dark ? "深色" : "浅色")-额度可用")
        }
        relaunchAndOpenSettings(app)
        assertSingleReminder(in: app, enabled: false)
        assertNoPermissionPrompt()
        verifyDemoQuota(in: app)
    }

    private func requireFreshSimulatorPermissionScenario(_ scenario: String) throws {
        #if targetEnvironment(simulator)
        guard ProcessInfo.processInfo.environment["T38_NOTIFICATION_PERMISSION_SCENARIO"] == scenario else {
            throw XCTSkip("仅在独立干净模拟器显式启用 T38 通知权限 \(scenario) 场景")
        }
        #else
        throw XCTSkip("通知权限允许／拒绝专项仅用于独立模拟器，不修改正式手机权限")
        #endif
    }

    @MainActor
    private func launchIsolatedApp() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["未连接账户"].exists)
        return app
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func relaunchAndOpenSettings(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 8))
        openSettings(in: app)
    }

    @MainActor
    private func assertSingleReminder(in app: XCUIApplication, enabled: Bool) {
        let reminders = app.switches.matching(identifier: "settings.resetReminder")
        let toggle = reminders.firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(reminders.count, 1)
        XCTAssertTrue(toggle.label.contains("重置提醒"))
        let usable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [usable], timeout: 5), .completed)
        waitForSwitch(toggle, enabled: enabled)
        XCTAssertFalse(app.staticTexts["重置时自动提醒"].exists)
    }

    @MainActor
    private func assertDeniedReminder(in app: XCUIApplication) {
        assertSingleReminder(in: app, enabled: false)
        let settingsLink = app.buttons["settings.notificationSettings"]
        XCTAssertTrue(settingsLink.waitForExistence(timeout: 5))
        XCTAssertTrue(settingsLink.isEnabled)
        XCTAssertTrue(settingsLink.label.contains("通知未允许"))
        XCTAssertTrue(settingsLink.label.contains("去设置"))
    }

    @MainActor
    private func assertNoPermissionPrompt() {
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertFalse(system.alerts.firstMatch.waitForExistence(timeout: 1), "未主动开启提醒时不应出现系统权限申请")
    }

    @MainActor
    private func respondToPermissionPrompt(allow: Bool) {
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = system.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8), "必须观察真实首次通知权限窗口，不能复用既有授权")
        screenshot(system, "T38-真实系统通知授权窗口-\(allow ? "允许" : "拒绝")")
        let labels = allow ? ["Allow", "允许"] : ["Don’t Allow", "Don't Allow", "不允许"]
        let action = alert.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 3))
        action.tap()
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: alert)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
    }

    @MainActor
    private func notificationPermissionSwitch(in settings: XCUIApplication) -> XCUIElement {
        let labels = ["Allow Notifications", "允许通知"]
        let row = settings.switches.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
        // Some iOS releases expose a row and a nested UISwitch; use the real control.
        if row.waitForExistence(timeout: 8), row.switches.firstMatch.exists {
            return row.switches.firstMatch
        }
        return row
    }

    @MainActor
    private func addDemoAccountAndVerifyQuota(in app: XCUIApplication) {
        openSettings(in: app)
        let demo = app.switches["settings.demo"]
        XCTAssertTrue(demo.waitForExistence(timeout: 5))
        if demo.value as? String != "1" { tapSwitch(demo) }
        waitForSwitch(demo, enabled: true)
        app.buttons["tab.quota"].tap()
        app.buttons["quota.toolbarConnect"].tap()
        verifyDemoQuota(in: app)
    }

    @MainActor
    private func verifyDemoQuota(in app: XCUIApplication) {
        app.buttons["tab.quota"].tap()
        XCTAssertTrue(app.staticTexts["quota.accountIdentity"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").count, 1)
        XCTAssertTrue(app.staticTexts["quota.weekly.remaining"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quota.details"].firstMatch.isEnabled)
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        XCTAssertFalse(app.switches["settings.resetReminder"].exists)
    }

    @MainActor
    private func setDarkAppearance(_ enabled: Bool, in app: XCUIApplication) {
        let toggle = app.switches["settings.darkAppearance"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String != (enabled ? "1" : "0") { tapSwitch(toggle) }
        waitForSwitch(toggle, enabled: enabled)
    }

    @MainActor
    private func tapSwitch(_ toggle: XCUIElement) {
        XCTAssertTrue(toggle.isHittable)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    @MainActor
    private func waitForSwitch(_ toggle: XCUIElement, enabled: Bool) {
        let expected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }

    @MainActor
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
