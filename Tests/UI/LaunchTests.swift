import XCTest

final class LaunchTests: XCTestCase {
    /// Opt-in system check, with the existing expiring widget fixture. No real
    /// accounts are read or cleared; existing desktop widgets are retained.
    @MainActor
    func testT42ActualSystemGalleryAndAddWidgetFollowingTutorial() throws {
        guard ProcessInfo.processInfo.environment["T42_WIDGET_ADD"] == "1" else {
            throw XCTSkip("显式启用主屏幕添加验证，使用隔离组件会话")
        }
        continueAfterFailure = false
        let app = XCUIApplication(), session = UUID().uuidString
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // XCTest's stop-on-failure exception can bypass a Swift defer.
        addTeardownBlock { [session] in
            await MainActor.run {
                let cleanup = XCUIApplication()
                cleanup.terminate()
                XCUIDevice.shared.press(.home)
                XCUIDevice.shared.press(.home)
                cleanup.launchArguments = ["--t36-desktop-fixture", "cleanup", session]
                cleanup.launch()
                XCTAssertTrue(cleanup.staticTexts["未连接账户"].waitForExistence(timeout: 8))
                cleanup.terminate()
            }
        }
        app.launchArguments = ["--t36-desktop-fixture", "baseline", session]
        app.launch()
        XCTAssertTrue(app.buttons["quota.widgetTutorial"].waitForExistence(timeout: 10))
        app.buttons["quota.widgetTutorial"].tap()
        assertT42Step(in: app, second: false)
        app.buttons["tutorial.next"].tap()
        assertT42Step(in: app, second: true)
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.press(.home)
        let widgets = springboard.icons.matching(NSPredicate(format: "label == %@ AND value == %@", "订阅用量", "小组件"))
        let before = widgets.count
        let occupied = springboard.icons.allElementsBoundByIndex.filter(\.isHittable).map(\.frame)
        let screen = springboard.frame
        var blank: CGPoint?
        for y in stride(from: 0.78, through: 0.20, by: -0.04) {
            for x in stride(from: 0.90, through: 0.10, by: -0.10) {
                let point = CGPoint(x: screen.width * x, y: screen.height * y)
                if !occupied.contains(where: { $0.insetBy(dx: -8, dy: -8).contains(point) }) {
                    blank = point; break
                }
            }
            if blank != nil { break }
        }
        let point = try XCTUnwrap(blank, "需要一处主屏幕空白区域")
        springboard.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).press(forDuration: 1.5)
        XCTAssertTrue(springboard.buttons["编辑"].waitForExistence(timeout: 8))
        springboard.buttons["编辑"].tap()
        XCTAssertTrue(springboard.buttons["添加小组件"].waitForExistence(timeout: 5))
        springboard.buttons["添加小组件"].tap()
        let search = springboard.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap(); search.typeText("订阅用量")
        let result = springboard.collectionViews["add-sheet-collection-view"].cells["订阅用量"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()
        let add = springboard.buttons.matching(NSPredicate(format: "label CONTAINS %@", "添加小组件")).firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        let preview = springboard.buttons["订阅用量, 订阅额度"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        XCTAssertEqual(preview.value as? String, "小组件, 小")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.56))
            .press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.56)))
        let medium = NSPredicate(format: "value == %@", "小组件, 中")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: medium, object: preview)], timeout: 8), .completed)
        print("T42 SYSTEM | native small and medium pages verified")
        add.tap()
        XCTAssertTrue(springboard.buttons["完成"].waitForExistence(timeout: 8))
        springboard.buttons["完成"].tap()
        let added = NSPredicate { _, _ in MainActor.assumeIsolated { widgets.count == before + 1 } }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: added, object: nil)], timeout: 15), .completed)
        XCTAssertTrue(springboard.staticTexts["batch-1"].firstMatch.waitForExistence(timeout: 30))
        print("T42 SYSTEM | added medium | widget count \(before) -> \(widgets.count) | default fixture first account visible")
        app.activate()
        assertT42Step(in: app, second: true)
        app.buttons["tutorial.next"].tap()
        XCTAssertTrue(app.buttons["quota.widgetTutorial"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testT42BothSourcesCloseEitherStepCompleteAndRestart() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        cleanT42Fixture(in: app)
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["quota.widgetTutorial"].waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(app.buttons["quota.widgetTutorial"].frame.maxY, app.buttons["tab.quota"].frame.minY)
        for settings in [false, true] {
            if settings { app.buttons["tab.settings"].tap() }
            let entry = app.buttons[settings ? "settings.widgetTutorial" : "quota.widgetTutorial"]
            for secondStep in [false, true] {
                XCTAssertTrue(entry.waitForExistence(timeout: 5))
                entry.tap()
                assertT42Step(in: app, second: false)
                swipeTutorial(in: app, forward: true)
                assertT42Step(in: app, second: true)
                swipeTutorial(in: app, forward: false)
                assertT42Step(in: app, second: false)
                if secondStep {
                    app.buttons["tutorial.next"].tap()
                    assertT42Step(in: app, second: true)
                }
                saveScreenshot(of: app, name: "T42-\(settings ? "设置" : "额度")-第\(secondStep ? 2 : 1)步")
                app.buttons["tutorial.close"].tap()
                XCTAssertTrue(entry.waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons[settings ? "tab.settings" : "tab.quota"].isSelected)
            }
            entry.tap()
            assertT42Step(in: app, second: false)
            app.buttons["tutorial.next"].tap()
            assertT42Step(in: app, second: true)
            // Going Home does not consume the second step or imply installation.
            XCUIDevice.shared.press(.home)
            app.activate()
            assertT42Step(in: app, second: true)
            app.buttons["tutorial.next"].tap()
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons[settings ? "tab.settings" : "tab.quota"].isSelected)
            entry.tap()
            assertT42Step(in: app, second: false)
            app.buttons["tutorial.close"].tap()
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testT42ConnectedListAndLightDarkTutorialRemainUsable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        cleanT42Fixture(in: app)
        app.launch()
        defer { app.terminate() }
        app.buttons["tab.settings"].tap()
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        for dark in [false, true] {
            let toggle = app.switches["settings.darkAppearance"]
            if toggle.value as? String != (dark ? "1" : "0") {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            app.buttons["tab.quota"].tap()
            if !app.buttons["quota.details"].firstMatch.exists { app.buttons["quota.toolbarConnect"].tap() }
            XCTAssertTrue(app.buttons["quota.details"].firstMatch.waitForExistence(timeout: 5))
            saveScreenshot(of: app, name: "T42-额度页入口-\(dark ? "深" : "浅")")
            app.buttons["quota.widgetTutorial"].tap()
            assertT42Step(in: app, second: false)
            saveScreenshot(of: app, name: "T42-第1步-\(dark ? "深" : "浅")")
            app.buttons["tutorial.next"].tap()
            assertT42Step(in: app, second: true)
            saveScreenshot(of: app, name: "T42-第2步-\(dark ? "深" : "浅")")
            app.buttons["tutorial.next"].tap()
            XCTAssertTrue(app.buttons["quota.details"].firstMatch.waitForExistence(timeout: 5))
            app.buttons["quota.details"].firstMatch.tap()
            XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 5))
            app.buttons["detail.close"].tap()
            app.buttons["tab.settings"].tap()
        }
    }

    @MainActor
    func testT42MaximumTextSizeKeepsInstructionsAndControlsReachable() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString,
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        cleanT42Fixture(in: app)
        app.launch()
        defer { app.terminate() }
        app.buttons["quota.widgetTutorial"].tap()
        for second in [false, true] {
            XCTAssertTrue(app.buttons["tutorial.next"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["tutorial.close"].isHittable)
            XCTAssertTrue(app.buttons["tutorial.next"].isHittable)
            let instructions = app.staticTexts["tutorial.instructions.\(second ? 1 : 0)"]
            app.scrollViews.firstMatch.swipeUp()
            XCTAssertTrue(instructions.isHittable)
            XCTAssertGreaterThanOrEqual(instructions.frame.minX, 0)
            XCTAssertLessThanOrEqual(instructions.frame.maxX, app.frame.maxX)
            XCTAssertLessThanOrEqual(instructions.frame.maxY, app.buttons["tutorial.next"].frame.minY)
            XCTAssertFalse(app.staticTexts["tutorial.defaultAccount"].exists)
            saveScreenshot(of: app, name: "T42-最大字号-第\(second ? 2 : 1)步")
            app.buttons["tutorial.next"].tap()
        }
        XCTAssertTrue(app.buttons["quota.widgetTutorial"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func swipeTutorial(in app: XCUIApplication, forward: Bool) {
        let pager = app
        let start = pager.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.85 : 0.15, dy: 0.5))
        let end = pager.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.15 : 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func assertT42Step(in app: XCUIApplication, second: Bool) {
        let text = app.staticTexts["tutorial.instructions.\(second ? 1 : 0)"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual(text.label, second ? "长按小组件，选择要显示的账号" : "长按主屏幕，然后添加 Token 仪表盘。")
        XCTAssertFalse(app.staticTexts["tutorial.stepTitle"].exists)
        XCTAssertFalse(app.staticTexts["tutorial.defaultAccount"].exists)
        XCTAssertEqual(app.buttons["tutorial.next"].label, second ? "完成" : "继续")
        XCTAssertTrue(app.buttons["tutorial.close"].isHittable)
        XCTAssertTrue(app.buttons["tutorial.next"].isHittable)
    }

    @MainActor
    private func cleanT42Fixture(in app: XCUIApplication) {
        let arguments = app.launchArguments
        app.launchArguments = ["--t36-desktop-fixture", "cleanup", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 8))
        app.terminate()
        app.launchArguments = arguments
    }

    @MainActor
    func testT58ManualAppearanceSurvivesRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        app.buttons["tab.settings"].tap()
        let toggle = app.switches["settings.darkAppearance"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let selected = original == "1" ? "0" : "1"
        XCTAssertTrue(NSPredicate(format: "value == %@", selected).evaluate(with: toggle) || XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", selected), object: toggle)], timeout: 3) == .completed)
        saveScreenshot(of: app, name: "T58-手动外观")
        app.terminate(); app.launch()
        app.buttons["tab.settings"].tap()
        XCTAssertEqual(toggle.value as? String, selected)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.terminate(); app.launch()
        app.buttons["tab.settings"].tap()
        XCTAssertEqual(toggle.value as? String, original)
    }

    @MainActor
    func testT26DemoPullUpdatesEveryCardAndPersistsOnReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["quota.refresh"].exists)
        app.buttons["tab.settings"].tap()
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["tab.quota"].tap()
        for count in 1...2 {
            app.buttons["quota.toolbarConnect"].tap()
            let ready = NSPredicate { _, _ in MainActor.assumeIsolated {
                app.staticTexts.matching(identifier: "quota.accountIdentity").count == count
            }}
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 5), .completed)
        }
        let before = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
        app.pullAllQuota()
        let allChanged = NSPredicate { _, _ in MainActor.assumeIsolated {
            let after = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
            return after.count == 2 && zip(before, after).allSatisfy { $0 != $1 }
        }}
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: allChanged, object: nil)], timeout: 8), .completed)
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        let after = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
        let identities = app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label)
        saveScreenshot(of: app, name: "T26-演示全部刷新")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["quota.weekly.remaining"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label), identities)
        // T27 now refreshes the restored demo accounts on every cold launch.
        let refreshedOnLaunch = NSPredicate { _, _ in MainActor.assumeIsolated {
            let current = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
            return current.count == 2 && zip(after, current).allSatisfy { $0 != $1 }
        }}
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: refreshedOnLaunch, object: nil)], timeout: 8), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["quota.refreshProgress"].firstMatch.exists)
    }

    @MainActor
    func testManagementDemoMenuClearAndReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        app.buttons["tab.settings"].tap()
        XCTAssertFalse(app.buttons["settings.accounts"].exists)
        XCTAssertFalse(app.buttons["settings.connect"].exists)
        let demo = app.switches["settings.demo"]
        demo.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(demo.value as? String, "1")
        app.buttons["tab.quota"].tap()
        for count in 1...3 {
            app.buttons["quota.toolbarConnect"].tap()
            let countMatches = NSPredicate { _, _ in MainActor.assumeIsolated {
                app.staticTexts.matching(identifier: "quota.accountIdentity").count == count
            }}
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: countMatches, object: nil)], timeout: 5), .completed)
        }
        XCTAssertFalse(app.staticTexts["connection.code"].exists)
        let original = app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label)
        let amounts = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
        app.buttons.matching(identifier: "quota.menu").element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["刷新额度"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["删除账户"].exists)
        app.buttons["刷新额度"].tap()
        let changed = NSPredicate { _, _ in MainActor.assumeIsolated {
            app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label) != amounts
        }}
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 5), .completed)
        let after = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(after[0], amounts[0]); XCTAssertEqual(after[2], amounts[2]); XCTAssertNotEqual(after[1], amounts[1])
        app.buttons.matching(identifier: "quota.menu").element(boundBy: 1).tap()
        app.buttons["删除账户"].tap()
        XCTAssertTrue(app.alerts["删除账户？"].waitForExistence(timeout: 3))
        app.alerts.buttons["取消"].tap()
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label), original)
        app.buttons.matching(identifier: "quota.menu").element(boundBy: 1).tap()
        app.buttons["删除账户"].tap()
        app.alerts.buttons["删除账户"].tap()
        XCTAssertTrue(app.staticTexts[original[0]].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts[original[1]].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts[original[2]].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[original[1]].exists)
        saveScreenshot(of: app, name: "新版-删除后重开")
        app.buttons["tab.settings"].tap()
        XCTAssertEqual(demo.value as? String, "1")
        demo.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        saveScreenshot(of: app, name: "新版-设置")
        app.buttons["tab.quota"].tap()
        XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5))
        app.buttons["quota.toolbarConnect"].tap()
        XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
        app.buttons["connection.cancel"].tap()
    }

    @MainActor
    func testLongDemoListScrollAndDragToTop() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        app.buttons["tab.settings"].tap()
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["tab.quota"].tap()
        for _ in 1...6 { app.buttons["quota.toolbarConnect"].tap() }
        let list = app.collectionViews["quota.list"]
        list.swipeUp(); list.swipeUp()
        let last = app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.last!
        XCTAssertTrue(last.isHittable)
        let identity = last.label
        let cell = app.cells.containing(.staticText, identifier: identity).firstMatch
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            .press(forDuration: 0.7, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02)),
                   withVelocity: .slow, thenHoldForDuration: 3)
        list.swipeDown(); list.swipeDown()
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").firstMatch.label, identity)
        saveScreenshot(of: app, name: "新版-长列表拖至首位")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts[identity].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").firstMatch.label, identity)
    }

    @MainActor
    func testT17LongDemoListDragFirstToBottomAndReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        app.buttons["tab.settings"].tap()
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["tab.quota"].tap()
        for _ in 1...6 { app.buttons["quota.toolbarConnect"].tap() }
        let list = app.collectionViews["quota.list"]
        let identity = app.staticTexts.matching(identifier: "quota.accountIdentity").firstMatch.label
        let cell = app.cells.containing(.staticText, identifier: identity).firstMatch
        cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            .press(forDuration: 0.7, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)),
                   withVelocity: .slow, thenHoldForDuration: 3)
        list.swipeUp(); list.swipeUp()
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.last?.label, identity)
        app.terminate(); app.launch()
        XCTAssertTrue(app.collectionViews["quota.list"].waitForExistence(timeout: 5))
        app.collectionViews["quota.list"].swipeUp(); app.collectionViews["quota.list"].swipeUp()
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.last?.label, identity)
    }

    @MainActor
    func testManualDarkQuotaDetailsAndMenu() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        app.buttons["tab.settings"].tap()
        let appearance = app.switches["settings.darkAppearance"]
        if appearance.value as? String != "1" {
            appearance.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["tab.quota"].tap()
        app.buttons["quota.toolbarConnect"].tap()
        XCTAssertTrue(app.buttons["quota.details"].waitForExistence(timeout: 5))
        app.buttons["quota.details"].tap()
        XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 5))
        saveScreenshot(of: app, name: "新版-手动深色额度详情")
        app.buttons["detail.menu"].tap()
        XCTAssertTrue(app.buttons["刷新额度"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["删除账户"].exists)
        saveScreenshot(of: app, name: "新版-手动深色账户菜单")
    }

    @MainActor
    func testNavigationEmptyStateAndUnavailableActions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        assertEmptyQuota(in: app)
        XCTAssertEqual(app.state, .runningForeground)
        saveScreenshot(of: app, name: "额度")

        for _ in 0..<2 {
            app.buttons["tab.settings"].tap()
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["tab.settings"].isSelected)

            for identifier in ["settings.help", "settings.privacy", "settings.licenses"] {
                let action = app.buttons[identifier]
                XCTAssertTrue(action.exists, identifier)
                XCTAssertFalse(action.isEnabled, identifier)
            }
            XCTAssertTrue(app.buttons["settings.widgetTutorial"].isEnabled)
            XCTAssertFalse(app.buttons["settings.connect"].exists)
            XCTAssertFalse(app.buttons["settings.accounts"].exists)
            let reminder = app.switches["settings.resetReminder"]
            XCTAssertTrue(reminder.exists)
            XCTAssertTrue(reminder.isEnabled)
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

        XCTAssertFalse(app.buttons["quota.refresh"].exists)
        let toolbarConnect = app.buttons["quota.toolbarConnect"]
        XCTAssertTrue(toolbarConnect.isEnabled)
        XCTAssertTrue(app.buttons["quota.connect"].isEnabled)
        // 顶部只保留标题右侧的连接入口。
        XCTAssertGreaterThan(toolbarConnect.frame.minX, title.frame.maxX)
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
