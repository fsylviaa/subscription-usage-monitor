import XCTest

final class CodexQuotaUITests: XCTestCase {
    @MainActor
    private func showT35Desktop(_ springboard: XCUIApplication) {
        let cards = springboard.icons.matching(NSPredicate(format: "label == %@ AND value == %@", "订阅用量", "小组件"))
        func visible() -> Bool {
            cards.allElementsBoundByIndex.contains { $0.isHittable && $0.frame.width > 100 }
        }
        if visible() { return }
        // Home may reopen on any page (including Today View after a previous run).
        for _ in 0..<3 { springboard.swipeRight(); if visible() { return } }
        for _ in 0..<6 { springboard.swipeLeft(); if visible() { return } }
        XCTFail("未找到已有订阅用量组件所在桌面页")
    }

    @MainActor
    private func t35BothSizesContain(_ text: String, on springboard: XCUIApplication) -> Bool {
        let cards = springboard.icons.matching(NSPredicate(format: "label == %@ AND value == %@", "订阅用量", "小组件"))
            .allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
        guard cards.contains(where: { $0.frame.width < 230 }), cards.contains(where: { $0.frame.width > 230 }) else { return false }
        let labels = springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", text)).allElementsBoundByIndex
        return cards.allSatisfy { card in labels.contains { card.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) } }
    }

    @MainActor
    func testT35PinnedAccountFollowsIdentityOnDesktop() throws {
        guard ProcessInfo.processInfo.environment["T35_WIDGET_PICKER"] == "1" else {
            throw XCTSkip("显式启用已有固定账户桌面对照")
        }
        let app = XCUIApplication(), session = UUID().uuidString
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        defer {
            app.terminate()
            app.launchArguments = ["--t35-widget-fixture", "cleanup", session]
            app.launch(); app.terminate()
        }
        // Read an existing system choice through WidgetCenter; only the isolated
        // snapshot uses that ID. No widget configuration or real account is edited.
        for scenario in ["baseline", "reorder", "reorderRefresh", "failure", "remove"] {
            app.terminate()
            app.launchArguments = ["--t35-widget-fixture", scenario, session, "--t35-configured-account"]
            app.launch()
            XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 2)
            XCUIDevice.shared.press(.home)
            showT35Desktop(springboard)
            let expectedPinned = scenario == "remove" ? "batch-2" : "batch-1"
            let expectedDefault = ["reorder", "reorderRefresh", "remove"].contains(scenario) ? "batch-2" : "batch-1"
            XCTAssertTrue(springboard.staticTexts[expectedPinned].firstMatch.waitForExistence(timeout: 30))
            XCTAssertTrue(springboard.staticTexts[expectedDefault].firstMatch.waitForExistence(timeout: 30))
            let value = scenario == "failure" ? "网络不达标，无法更新" : (scenario == "reorderRefresh" ? "55%" : (scenario == "remove" ? "70%" : "90%"))
            XCTAssertTrue(springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", value)).firstMatch.waitForExistence(timeout: 30))
            Thread.sleep(forTimeInterval: 2)
            screenshot(springboard, "T35-固定账户-\(scenario)")
            print("T35 | 固定账户桌面对照 | \(scenario) | \(Date().ISO8601Format())")
        }
    }

    @MainActor
    func testT35ResizeFromContextMenu() throws {
        guard ProcessInfo.processInfo.environment["T35_WIDGET_RESIZE"] == "1" else {
            throw XCTSkip("显式启用尺寸切换复验；会调整已有组件尺寸")
        }
        let app = XCUIApplication(), session = UUID().uuidString
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        defer {
            app.terminate()
            app.launchArguments = ["--t35-widget-fixture", "cleanup", session]
            app.launch(); app.terminate()
        }
        app.launchArguments = ["--t35-widget-fixture", "baseline", session]
        app.launch()
        XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        let cards = springboard.icons.matching(NSPredicate(format: "label == %@ AND value == %@", "订阅用量", "小组件"))
        if !cards.firstMatch.waitForExistence(timeout: 5) {
            springboard.swipeLeft()
            if !cards.firstMatch.waitForExistence(timeout: 3) {
                for _ in 0..<3 {
                    springboard.swipeRight()
                    if cards.firstMatch.waitForExistence(timeout: 2) { break }
                }
            }
        }
        XCTAssertTrue(springboard.staticTexts["batch-1"].firstMatch.waitForExistence(timeout: 15),
                      "截图前必须已显示隔离样例")
        let toMedium = ProcessInfo.processInfo.environment["T35_RESIZE_TARGET"] != "small"
        // Width distinguishes the actual SpringBoard icon from the enlarged menu preview.
        let visibleCards = { cards.allElementsBoundByIndex.filter { $0.frame.width > 100 && $0.frame.height > 100 } }
        let candidates = visibleCards().filter { ($0.frame.width < 230) == toMedium }
        let card = try XCTUnwrap(candidates.first, "需要已有待切换尺寸的组件")
        let before = card.frame
        let targetCount = { visibleCards().filter { ($0.frame.width > 230) == toMedium }.count }
        let countBefore = targetCount()
        screenshot(springboard, "T35-尺寸切换前")
        print("T35 RESIZE BEFORE targetMedium=\(toMedium) frame=\(before) targetCount=\(countBefore)")
        card.press(forDuration: 0.7)
        let option = springboard.buttons[toMedium ? "中尺寸小组件" : "小型小组件"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        screenshot(springboard, "T35-尺寸菜单")
        option.tap()
        let changed = NSPredicate { _, _ in targetCount() == countBefore + 1 }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 15)
        screenshot(springboard, toMedium ? "T35-点中号后" : "T35-点小号后")
        print("T35 RESIZE AFTER targetMedium=\(toMedium) frames=\(visibleCards().map(\.frame))")
        XCTAssertEqual(result, .completed, "必须核对实际尺寸变化，不能只判断菜单消失")
    }

    @MainActor
    func testT35DesktopUsesIsolatedSharedSnapshot() throws {
        guard ProcessInfo.processInfo.environment["T35_WIDGET_DESKTOP"] == "1" else {
            throw XCTSkip("需要已放置两种桌面组件；由开发者显式启用隔离验收")
        }
        let app = XCUIApplication()
        let session = UUID().uuidString
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        defer {
            app.terminate()
            app.launchArguments = ["--t35-widget-fixture", "cleanup", session]
            app.launch()
            app.terminate()
        }
        var scenarios = ["baseline", "single", "all", "foreground", "failure", "reorder", "remove", "scope", "empty", "background"]
        if ProcessInfo.processInfo.environment["T35_SYSTEM_DEBUG"] == "1" { scenarios.append("systemBackground") }
        for scenario in scenarios {
            app.terminate()
            app.launchArguments = ["--t35-widget-fixture", scenario, session]
            if scenario == "systemBackground" { app.launchArguments.append("--t30-background-debug") }
            app.launch()
            XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 2)
            XCUIDevice.shared.press(.home)
            if scenario == "systemBackground" {
                print("T35 DEBUG READY background")
                Thread.sleep(forTimeInterval: 35)
            }
            let expected = scenario == "empty" ? "添加账户" : (scenario == "reorder" || scenario == "remove" ? "batch-2" : "batch-1")
            let labels = springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", expected))
            showT35Desktop(springboard)
            guard labels.firstMatch.waitForExistence(timeout: 15) else {
                screenshot(springboard, "T35-桌面未发现样例-\(scenario)")
                XCTFail("桌面尚未显示隔离组件样例，不能视为换图通过")
                return
            }
            let value: String
            switch scenario {
            case "single", "all", "foreground", "background", "systemBackground": value = "55%"
            case "failure": value = "网络不达标，无法更新"
            case "reorder", "remove": value = "70%"
            case "scope": value = "尚未获取额度"
            case "empty": value = "添加账户"
            default: value = "90%"
            }
            XCTAssertTrue(springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", value))
                .firstMatch.waitForExistence(timeout: scenario == "systemBackground" ? 120 : 15), "桌面应采用本轮值而非只更新身份")
            // Keep the actual two-size surface for visual review, not just reader assertions.
            Thread.sleep(forTimeInterval: 2)
            screenshot(springboard, "T35-桌面-\(scenario)")
            print("T35 | 桌面观察 | \(scenario) | \(Date().ISO8601Format())")
            if scenario == "systemBackground" {
                app.activate()
                XCTAssertEqual(app.staticTexts["quota.title"].value as? String, "T30 debug background=true success=2 failed=0")
                XCUIDevice.shared.press(.home)
            }
        }
    }

    @MainActor
    func testT35SystemBackgroundPublishesToDesktop() throws {
        guard ProcessInfo.processInfo.environment["T35_SYSTEM_DEBUG"] == "1" else {
            throw XCTSkip("需要开发者在隔离样例下触发真机系统后台任务")
        }
        let app = XCUIApplication(), session = UUID().uuidString
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        defer {
            app.terminate()
            app.launchArguments = ["--t35-widget-fixture", "cleanup", session]
            app.launch(); app.terminate()
        }
        app.launchArguments = ["--t35-widget-fixture", "baseline", session, "--t30-background-debug"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        XCUIDevice.shared.press(.home)
        let baseline = springboard.staticTexts["batch-1"].firstMatch
        showT35Desktop(springboard)
        XCTAssertTrue(baseline.waitForExistence(timeout: 15))
        let oldValue = NSPredicate { _, _ in self.t35BothSizesContain("90%", on: springboard) }
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: oldValue, object: nil)], timeout: 30) == .completed else {
            screenshot(springboard, "T35-系统后台基线未就绪")
            XCTFail("两种尺寸必须先实际显示旧值，避免将上一轮55%误算为后台更新")
            return
        }
        screenshot(springboard, "T35-系统后台前桌面")
        print("T35 DEBUG READY background")
        // Stay on the Home Screen: activating the app would be a separate trigger.
        let newValue = NSPredicate { _, _ in self.t35BothSizesContain("55%", on: springboard) }
        let changed = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: newValue, object: nil)], timeout: 180)
        XCTAssertEqual(changed, .completed, "两种尺寸都要采用新值；已请求更新不能替代实际换图")
        screenshot(springboard, "T35-真机系统后台后桌面")
        print("T35 | 系统后台后桌面观察 | \(Date().ISO8601Format())")
        app.activate()
        XCTAssertEqual(app.staticTexts["quota.title"].value as? String, "T30 debug background=true success=2 failed=0")
    }

    @MainActor
    func testT31SystemExpirationKeepsPartialCacheAndBackgroundRunsAgain() throws {
        guard ProcessInfo.processInfo.environment["T30_SYSTEM_DEBUG"] == "1" else {
            throw XCTSkip("需连接手机调试器；隔离样例，不是自然执行")
        }
        let app = launchD60("ui-t31-expire", extra: ["--t27-lifecycle", "--t30-background-debug"])
        defer { app.terminate() }
        let button = app.buttons["quota.toolbarConnect"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: button)
        waitForExpectations(timeout: 15)
        XCUIDevice.shared.press(.home)
        print("T31 DEBUG READY expire")
        Thread.sleep(forTimeInterval: 35)
        app.activate()
        XCTAssertEqual(app.staticTexts["quota.title"].value as? String, "T31 expired background=true")
        let cards = app.otherElements.matching(identifier: "quota.card")
        XCTAssertEqual(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 50%")
        XCTAssertEqual(cards.element(boundBy: 1).staticTexts["quota.weekly.remaining"].label, "剩余 55%")
        screenshot(app, "T31-中断后A新值B旧值")
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: button)
        waitForExpectations(timeout: 15)
        XCTAssertEqual(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 45%")
        XCTAssertEqual(cards.element(boundBy: 1).staticTexts["quota.weekly.remaining"].label, "剩余 50%")
        XCUIDevice.shared.press(.home)
        print("T31 DEBUG READY recover")
        Thread.sleep(forTimeInterval: 30)
        app.activate()
        XCTAssertEqual(app.staticTexts["quota.title"].value as? String, "T30 debug background=true success=2 failed=0")
        XCTAssertEqual(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 40%")
        XCTAssertEqual(cards.element(boundBy: 1).staticTexts["quota.weekly.remaining"].label, "剩余 45%")
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: button)
        waitForExpectations(timeout: 15)
        XCTAssertEqual(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 35%")
        screenshot(app, "T31-后台恢复后前台独立刷新")
    }

    @MainActor
    func testT30SystemDebugBackgroundSuccessThenIndependentForeground() throws {
        try runT30SystemDebug(scenario: "ui-foreground", expected: "success=2 failed=0")
    }

    @MainActor
    func testT30SystemDebugBackgroundScoreBlockedPreservesCache() throws {
        try runT30SystemDebug(scenario: "blocked", expected: "success=0 failed=2")
    }

    @MainActor
    private func runT30SystemDebug(scenario: String, expected: String) throws {
        guard ProcessInfo.processInfo.environment["T30_SYSTEM_DEBUG"] == "1" else {
            throw XCTSkip("需开发者连接手机调试器触发真实BGTaskScheduler，不作为自然执行")
        }
        let app = launchD60(scenario, extra: ["--t27-lifecycle", "--t30-background-debug"])
        defer { app.terminate() }
        let button = app.buttons["quota.toolbarConnect"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: button)
        waitForExpectations(timeout: 15)
        XCUIDevice.shared.press(.home)
        print("T30 DEBUG READY \(scenario)")
        // The developer invokes Apple's device-only debugger command here.
        Thread.sleep(forTimeInterval: 35)
        app.activate()
        let summary = app.staticTexts["quota.title"].value as? String ?? ""
        XCTAssertEqual(summary, "T30 debug background=true \(expected)")
        let cards = app.otherElements.matching(identifier: "quota.card")
        if scenario == "ui-foreground" {
            XCTAssertEqual(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 50%",
                           "先显示后台保存的第二次结果")
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: button)
            waitForExpectations(timeout: 10)
            XCTAssertEqual(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 45%",
                           "随后前台第三次查询独立成功")
        } else {
            XCTAssertEqual(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 90%")
            XCTAssertEqual(cards.element(boundBy: 1).staticTexts["quota.weekly.remaining"].label, "剩余 70%")
        }
        screenshot(app, "T30-系统调试-\(scenario)")
    }

    @MainActor
    func testT29CloseCollapsesLayoutAndTabReturnKeepsItClosedUntilNewFailure() {
        let app = launchD60("blocked")
        defer { app.terminate() }
        let cards = app.otherElements.matching(identifier: "quota.card")
        let originalY = cards.element(boundBy: 0).frame.minY
        app.pullAllQuota()
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForExistence(timeout: 8))
        let failureY = cards.element(boundBy: 0).frame.minY
        XCTAssertGreaterThan(failureY, originalY)
        app.buttons["quota.closeFeedback"].tap()
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        XCTAssertEqual(cards.element(boundBy: 0).frame.minY, originalY, accuracy: 1)
        app.buttons["tab.settings"].tap()
        app.buttons["tab.quota"].tap()
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        XCTAssertEqual(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 90%")
        screenshot(app, "T29-关闭后返回列表无占位")
        app.pullAllQuota()
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["quota.failure"].label, "网络不达标，无法更新")
        screenshot(app, "T29-新一轮失败再次显示")
    }

    @MainActor
    func testT28ManualCardJoinsAutomaticRequestWithoutSpinningOtherCard() {
        let app = launchD60("ui-staggered", extra: ["--t27-lifecycle"])
        defer { app.terminate() }
        let cards = app.otherElements.matching(identifier: "quota.card")
        let first = cards.element(boundBy: 0), second = cards.element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertFalse(first.descendants(matching: .any)["quota.refreshProgress"].exists)
        first.buttons["quota.menu"].tap()
        app.buttons["刷新额度"].tap()
        XCTAssertTrue(first.descendants(matching: .any)["quota.refreshProgress"].exists)
        XCTAssertFalse(second.descendants(matching: .any)["quota.refreshProgress"].exists)
        assertNoRefreshBanner(app)
        screenshot(app, "T28-自动在途仅手动目标转圈")
        XCTAssertTrue(app.buttons["quota.toolbarConnect"].waitForExistence(timeout: 5))
        let done = NSPredicate(format: "enabled == true")
        expectation(for: done, evaluatedWith: app.buttons["quota.toolbarConnect"])
        waitForExpectations(timeout: 25)
        XCTAssertEqual(first.staticTexts["quota.weekly.remaining"].label, "剩余 55%")
        XCTAssertEqual(second.staticTexts["quota.weekly.remaining"].label, "剩余 55%")
    }

    @MainActor
    func testT59PullRefreshUsesAllCardsAndReturnsToOriginalLayout() {
        let app = launchD60("ui-staggered")
        defer { app.terminate() }
        let cards = app.otherElements.matching(identifier: "quota.card")
        XCTAssertFalse(app.buttons["quota.refresh"].exists)
        let title = app.staticTexts["quota.title"].frame
        let top = cards.element(boundBy: 0).frame.minY
        let list = app.collectionViews["quota.list"]
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(cards.element(boundBy: 0).descendants(matching: .any)["quota.refreshProgress"].waitForExistence(timeout: 4))
        XCTAssertTrue(cards.element(boundBy: 1).descendants(matching: .any)["quota.refreshProgress"].exists)
        XCTAssertTrue(app.otherElements["quota.pullIndicator"].waitForNonExistence(timeout: 4))
        XCTAssertEqual(app.staticTexts["quota.title"].frame, title)
        XCTAssertEqual(cards.element(boundBy: 0).frame.minY, top, accuracy: 1)
        assertNoRefreshBanner(app)
        screenshot(app, "T59-松手回弹后全量卡片刷新")
        // A second pull while work is active must not queue another batch.
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)),
                    withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(cards.element(boundBy: 1).descendants(matching: .any)["quota.refreshProgress"].waitForNonExistence(timeout: 25))
        XCTAssertEqual(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 55%")
        XCTAssertEqual(cards.element(boundBy: 1).staticTexts["quota.weekly.remaining"].label, "剩余 55%")
        screenshot(app, "T59-下拉全部完成")
    }

    @MainActor
    func testT59ShortPullDoesNotRefreshAndFailureKeepsOldValues() {
        let app = launchD60("partial", extra: ["--t26-dark"])
        defer { app.terminate() }
        let cards = app.otherElements.matching(identifier: "quota.card")
        let start = app.collectionViews["quota.list"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 45)),
                    withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertEqual(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 90%")
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForExistence(timeout: 8))
        XCTAssertEqual(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 55%")
        XCTAssertEqual(cards.element(boundBy: 1).staticTexts["quota.weekly.remaining"].label, "剩余 70%")
        screenshot(app, "T59-深色下拉部分失败")
        app.buttons["quota.retry"].tap()
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForNonExistence(timeout: 8))
        XCTAssertEqual(cards.element(boundBy: 1).staticTexts["quota.weekly.remaining"].label, "剩余 50%")
    }

    @MainActor
    func testT26PullRefreshPartialFailureAndWholeScopeRetry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t26-isolated-ui", "partial"]
        app.launch()
        defer { app.terminate() }
        let cards = app.otherElements.matching(identifier: "quota.card")
        XCTAssertTrue(cards.element(boundBy: 1).waitForExistence(timeout: 10))
        let first = cards.element(boundBy: 0), second = cards.element(boundBy: 1)
        first.buttons["quota.details"].tap()
        second.buttons["quota.details"].tap()
        let oldTime = second.staticTexts["quota.updatedAt"].label
        app.pullAllQuota()
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["quota.failure"].label, "刷新失败")
        XCTAssertEqual(first.staticTexts["quota.weekly.remaining"].label, "剩余 55%")
        XCTAssertEqual(second.staticTexts["quota.weekly.remaining"].label, "剩余 70%")
        XCTAssertEqual(second.staticTexts["quota.updatedAt"].label, oldTime)
        let firstTime = first.staticTexts["quota.updatedAt"].label
        XCTAssertNotEqual(firstTime, oldTime)
        screenshot(app, "T26-部分成功与旧值保留")
        app.buttons["quota.retry"].tap()
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["quota.refreshProgress"].firstMatch.waitForNonExistence(timeout: 8))
        XCTAssertEqual(first.staticTexts["quota.weekly.remaining"].label, "剩余 50%")
        XCTAssertEqual(second.staticTexts["quota.weekly.remaining"].label, "剩余 50%")
        XCTAssertNotEqual(first.staticTexts["quota.updatedAt"].label, firstTime)
        XCTAssertNotEqual(second.staticTexts["quota.updatedAt"].label, oldTime)
        screenshot(app, "T26-整批重试全部成功")
    }

    @MainActor
    func testT26BlockedFailureCanCloseWithoutChangingCards() {
        let app = launchD60("blocked")
        defer { app.terminate() }
        let cards = app.otherElements.matching(identifier: "quota.card")
        app.pullAllQuota()
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["quota.failure"].label, "网络不达标，无法更新")
        app.buttons["quota.closeFeedback"].tap()
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        XCTAssertEqual(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 90%")
        XCTAssertEqual(cards.element(boundBy: 1).staticTexts["quota.weekly.remaining"].label, "剩余 70%")
        assertNoRefreshBanner(app)
        screenshot(app, "D60-关闭失败仅隐藏提示")
    }

    @MainActor
    func testD60ManualBatchSpinsBesidePlanAndEachCardStopsWithoutLayoutJump() {
        let app = launchD60("ui-staggered")
        defer { app.terminate() }
        let cards = app.otherElements.matching(identifier: "quota.card")
        let first = cards.element(boundBy: 0), second = cards.element(boundBy: 1)
        let plan = first.buttons["quota.details"].frame
        let identity = first.staticTexts["quota.accountIdentity"].frame
        let secondY = second.frame.minY
        app.pullAllQuota()
        let spinner = first.descendants(matching: .any)["quota.refreshProgress"]
        screenshot(app, "D60-开始手动刷新")
        XCTAssertTrue(spinner.waitForExistence(timeout: 3))
        XCTAssertTrue(second.descendants(matching: .any)["quota.refreshProgress"].exists)
        assertNoRefreshBanner(app)
        XCTAssertGreaterThan(spinner.frame.minX, first.buttons["quota.details"].frame.maxX)
        XCTAssertEqual(first.buttons["quota.details"].frame, plan)
        XCTAssertEqual(first.staticTexts["quota.accountIdentity"].frame, identity)
        XCTAssertEqual(second.frame.minY, secondY, accuracy: 1)
        screenshot(app, "D60-手动全量卡片小转圈")
        XCTAssertTrue(spinner.waitForNonExistence(timeout: 14))
        XCTAssertTrue(second.descendants(matching: .any)["quota.refreshProgress"].exists)
        XCTAssertEqual(first.staticTexts["quota.weekly.remaining"].label, "剩余 55%")
        screenshot(app, "D60-第一户完成第二户仍刷新")
        XCTAssertTrue(second.descendants(matching: .any)["quota.refreshProgress"].waitForNonExistence(timeout: 22))
        XCTAssertEqual(first.buttons["quota.details"].frame, plan)
        XCTAssertEqual(second.frame.minY, secondY, accuracy: 1)
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
    }

    @MainActor
    func testD60ManualSingleOnlySpinsSelectedCard() {
        let app = launchD60("ui-single", extra: ["--t26-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        let cards = app.otherElements.matching(identifier: "quota.card")
        cards.element(boundBy: 0).buttons["quota.menu"].tap()
        app.buttons["刷新额度"].tap()
        XCTAssertTrue(cards.element(boundBy: 0).descendants(matching: .any)["quota.refreshProgress"].waitForExistence(timeout: 3))
        let spinner = cards.element(boundBy: 0).descendants(matching: .any)["quota.refreshProgress"]
        XCTAssertLessThanOrEqual(spinner.frame.width, 20)
        XCTAssertLessThanOrEqual(spinner.frame.height, 20)
        XCTAssertGreaterThan(spinner.frame.minX, cards.element(boundBy: 0).buttons["quota.details"].frame.maxX)
        XCTAssertFalse(cards.element(boundBy: 1).descendants(matching: .any)["quota.refreshProgress"].exists)
        assertNoRefreshBanner(app)
        screenshot(app, "D60-手动单卡小转圈")
        XCTAssertTrue(cards.element(boundBy: 0).descendants(matching: .any)["quota.refreshProgress"].waitForNonExistence(timeout: 14))
        XCTAssertEqual(cards.element(boundBy: 1).staticTexts["quota.weekly.remaining"].label, "剩余 70%")
    }

    @MainActor
    func testD60AutomaticRefreshIsSilentAndOnlyFailureShowsBanner() {
        for scenario in ["ui-staggered", "ui-auto-failure"] {
            let app = launchD60(scenario, extra: ["--t26-auto"])
            let cards = app.otherElements.matching(identifier: "quota.card")
            let firstY = cards.element(boundBy: 0).frame.minY
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == false"),
                object: app.buttons["quota.toolbarConnect"])], timeout: 6), .completed)
            XCTAssertFalse(app.descendants(matching: .any)["quota.refreshProgress"].firstMatch.exists)
            assertNoRefreshBanner(app)
            XCTAssertFalse(app.staticTexts["quota.failure"].exists)
            screenshot(app, "D60-自动刷新无进度-\(scenario)")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),
                object: app.buttons["quota.toolbarConnect"])], timeout: 28), .completed)
            XCTAssertFalse(app.descendants(matching: .any)["quota.refreshProgress"].firstMatch.exists)
            if scenario == "ui-auto-failure" {
                XCTAssertEqual(app.staticTexts["quota.failure"].label, "刷新失败")
                XCTAssertEqual(cards.element(boundBy: 1).staticTexts["quota.weekly.remaining"].label, "剩余 70%")
                screenshot(app, "D60-自动刷新失败可关闭")
                app.buttons["quota.closeFeedback"].tap()
                XCTAssertFalse(app.staticTexts["quota.failure"].exists)
            } else {
                XCTAssertFalse(app.staticTexts["quota.failure"].exists)
                XCTAssertEqual(cards.element(boundBy: 0).frame.minY, firstY, accuracy: 1)
            }
            XCTAssertEqual(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 55%")
            screenshot(app, "D60-自动结束-\(scenario)")
            app.terminate()
        }
    }

    @MainActor
    func testT27ColdLaunchAndImmediateForegroundReturnsRefreshBothCardsSilently() {
        let app = launchD60("ui-foreground", extra: ["--t27-lifecycle"])
        defer { app.terminate() }
        let cards = app.otherElements.matching(identifier: "quota.card")
        let first = cards.element(boundBy: 0), second = cards.element(boundBy: 1)
        XCTAssertTrue(first.staticTexts["quota.weekly.remaining"].label.contains("90%"))
        XCTAssertTrue(second.staticTexts["quota.weekly.remaining"].label.contains("70%"))
        XCTAssertEqual(app.activityIndicators.count, 0)
        assertNoRefreshBanner(app)
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        screenshot(app, "T27-打开先显示缓存且无进度")
        for expected in ["55%", "50%", "45%"] {
            let updated = NSPredicate(format: "label CONTAINS %@", expected)
            expectation(for: updated, evaluatedWith: first.staticTexts["quota.weekly.remaining"])
            expectation(for: updated, evaluatedWith: second.staticTexts["quota.weekly.remaining"])
            waitForExpectations(timeout: 20)
            XCTAssertEqual(app.activityIndicators.count, 0)
            XCTAssertFalse(app.buttons["quota.closeFeedback"].exists)
            screenshot(app, "T27-两户自动成功-\(expected)")
            if expected != "45%" {
                XCUIDevice.shared.press(.home)
                app.activate()
                XCTAssertEqual(app.activityIndicators.count, 0)
            }
        }
        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.buttons["tab.quota"].exists)
        app.buttons["tab.quota"].tap()
        XCTAssertTrue(first.staticTexts["quota.weekly.remaining"].label.contains("45%"), "页签往返不冒充回前台")
    }

    @MainActor
    func testT27ForegroundBlockedKeepsCacheAndCanCloseFailure() {
        let app = launchD60("blocked", extra: ["--t27-lifecycle"])
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["网络不达标，无法更新"].waitForExistence(timeout: 10))
        let cards = app.otherElements.matching(identifier: "quota.card")
        XCTAssertTrue(cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label.contains("90%"))
        XCTAssertTrue(cards.element(boundBy: 1).staticTexts["quota.weekly.remaining"].label.contains("70%"))
        XCTAssertEqual(app.activityIndicators.count, 0)
        screenshot(app, "T27-自动失败保留原两户")
        app.buttons["quota.closeFeedback"].tap()
        XCTAssertFalse(app.staticTexts["网络不达标，无法更新"].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.staticTexts["网络不达标，无法更新"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["connection.cancel"].exists)
    }

    @MainActor private func launchD60(_ scenario: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t26-isolated-ui", scenario] + extra
        app.launch()
        XCTAssertTrue(app.otherElements.matching(identifier: "quota.card").element(boundBy: 1).waitForExistence(timeout: 10))
        return app
    }
    @MainActor private func assertNoRefreshBanner(_ app: XCUIApplication) {
        XCTAssertFalse(app.otherElements["quota.updating"].exists)
        XCTAssertFalse(app.buttons["quota.cancelUpdate"].exists)
        XCTAssertFalse(app.staticTexts["正在更新"].exists)
    }

    @MainActor
    func testT24RepeatedExpansionKeepsHeaderAndAmountsAnchored() {
        let app = launchT23("limits", appearance: "light")
        defer { app.terminate() }
        let cards = app.otherElements.matching(identifier: "quota.card")
        let first = cards.element(boundBy: 0), second = cards.element(boundBy: 1)
        let ids = ["quota.accountIdentity", "quota.weekly.remaining", "quota.fiveHours.remaining"]
        let originalY = ids.map { first.staticTexts[$0].frame.minY }
        let originalNextY = second.frame.minY
        for cycle in 0..<3 {
            first.buttons["quota.details"].tap()
            XCTAssertTrue(first.staticTexts["quota.updatedAt"].waitForExistence(timeout: 3))
            for (id, y) in zip(ids, originalY) { XCTAssertEqual(first.staticTexts[id].frame.minY, y, accuracy: 1) }
            XCTAssertGreaterThan(second.frame.minY, originalNextY + 10)
            XCTAssertFalse(second.staticTexts["quota.updatedAt"].exists)
            screenshot(app, "T24-展开-\(cycle)")
            first.buttons["quota.details"].tap()
            XCTAssertFalse(first.staticTexts["quota.updatedAt"].exists)
            for (id, y) in zip(ids, originalY) { XCTAssertEqual(first.staticTexts[id].frame.minY, y, accuracy: 1) }
            XCTAssertEqual(second.frame.minY, originalNextY, accuracy: 1)
            screenshot(app, "T24-收起-\(cycle)")
        }
    }

    @MainActor
    func testT24DetailsBelongToEachAccountAndMissingOrElapsedResetIsHonest() {
        for appearance in ["light", "dark"] {
            let app = launchT23("times", appearance: appearance)
            let cards = app.otherElements.matching(identifier: "quota.card")
            let first = cards.element(boundBy: 0), second = cards.element(boundBy: 1)
            let weekly = first.staticTexts["quota.weekly.reset"]
            let five = first.staticTexts["quota.fiveHours.reset"]
            XCTAssertTrue((weekly.value as? String ?? "").hasPrefix("6 天后"))
            XCTAssertEqual(five.value as? String, "1 小时 34 分后")
            XCTAssertNotEqual(weekly.label, five.label)
            XCTAssertEqual(second.staticTexts["quota.weekly.reset"].value as? String, "已到预计时间")
            XCTAssertEqual(second.staticTexts["quota.fiveHours.reset"].label, "未提供重置时间")
            first.buttons["quota.details"].tap()
            let firstTime = first.staticTexts["quota.updatedAt"].label
            XCTAssertEqual(firstTime, "更新于 \(Date(timeIntervalSince1970: 1_791_590_400).formatted(.dateTime.month().day().hour().minute()))")
            XCTAssertFalse(second.staticTexts["quota.updatedAt"].exists)
            second.buttons["quota.details"].tap()
            let secondTime = second.staticTexts["quota.updatedAt"].label
            XCTAssertEqual(secondTime, "更新于 \(Date(timeIntervalSince1970: 1_791_594_000).formatted(.dateTime.month().day().hour().minute()))")
            XCTAssertNotEqual(firstTime, secondTime)
            XCTAssertEqual(second.staticTexts["quota.weekly.remaining"].label, "剩余 70%")
            XCTAssertEqual(second.staticTexts["quota.fiveHours.remaining"].label, "剩余 20%")
            first.buttons["quota.details"].tap()
            XCTAssertEqual(second.staticTexts["quota.updatedAt"].label, secondTime)
            first.buttons["quota.details"].tap()
            XCTAssertEqual(first.staticTexts["quota.updatedAt"].label, firstTime)
            screenshot(app, "T24-各自时间与已到点-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testT24ExpansionRemainsReadableAtLargestAccessibilitySize() {
        let app = launchT23("limits", appearance: "dark", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        let first = app.otherElements.matching(identifier: "quota.card").element(boundBy: 0)
        let identityY = first.staticTexts["quota.accountIdentity"].frame.minY
        first.buttons["quota.details"].tap()
        XCTAssertEqual(first.staticTexts["quota.accountIdentity"].frame.minY, identityY, accuracy: 1)
        XCTAssertTrue(first.staticTexts["quota.updatedAt"].exists)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["quota.updatedAt"].isHittable)
        screenshot(app, "T24-大字号展开可读")
    }

    @MainActor
    func testT23AccessibilityLayoutUsesFullWidthIdentityAndSeparatesResetTime() {
        for appearance in ["light", "dark"] {
            for size in ["UICTContentSizeCategoryAccessibilityM", "UICTContentSizeCategoryAccessibilityXXXL"] {
                let app = launchT23("limits", appearance: appearance, extra: ["-UIPreferredContentSizeCategoryName", size])
                let card = app.otherElements.matching(identifier: "quota.card").element(boundBy: 0)
                let identity = card.staticTexts["quota.accountIdentity"]
                XCTAssertEqual(identity.frame.minX, card.frame.minX + 16, accuracy: 1)
                XCTAssertEqual(card.buttons["quota.details"].frame.minX, identity.frame.minX, accuracy: 1)
                for id in ["weekly", "fiveHours"] {
                    let value = card.staticTexts["quota.\(id).remaining"]
                    let bar = card.otherElements["quota.\(id).bar"]
                    let reset = card.staticTexts["quota.\(id).reset"]
                    XCTAssertLessThan(value.frame.maxY, bar.frame.minY)
                    XCTAssertLessThan(bar.frame.maxY, reset.frame.minY)
                    XCTAssertLessThanOrEqual(value.frame.maxX, card.frame.maxX - 15)
                }
                XCTAssertTrue(card.staticTexts["quota.fiveHours.remaining"].isHittable,
                              "常见短套餐在最大字号下仍应直接看到两项余额")
                screenshot(app, "T23-大字优化-\(size)-\(appearance)")
                card.buttons["quota.menu"].tap()
                XCTAssertTrue(app.buttons["删除账户"].waitForExistence(timeout: 3))
                app.terminate()
            }
        }
    }

    @MainActor
    func testT23TwoCardsKeepPlanIdentityAndZeroFullPartialBarsInBothAppearances() {
        for appearance in ["light", "dark"] {
            let app = launchT23("limits", appearance: appearance)
            let cards = app.otherElements.matching(identifier: "quota.card")
            XCTAssertEqual(cards.count, 2)
            let first = cards.element(boundBy: 0), second = cards.element(boundBy: 1)
            XCTAssertEqual(first.staticTexts["quota.accountIdentity"].label, "card-1@example.invalid")
            XCTAssertEqual(second.staticTexts["quota.accountIdentity"].label, "card-2@example.invalid")
            XCTAssertEqual(first.buttons["quota.details"].label, "Codex · Plus")
            XCTAssertEqual(second.buttons["quota.details"].label, "Codex · Future Official Plan")
            for (card, weekly, fiveHours) in [(first, 100, 0), (second, 70, 20)] {
                for (id, remaining) in [("weekly", weekly), ("fiveHours", fiveHours)] {
                    XCTAssertEqual(card.staticTexts["quota.\(id).remaining"].label, "剩余 \(remaining)%")
                    XCTAssertEqual(card.otherElements["quota.\(id).bar"].value as? String,
                                   "已用 \(100 - remaining)%，剩余 \(remaining)%")
                    XCTAssertTrue(card.staticTexts["quota.\(id).remaining"].isHittable)
                }
            }
            XCTAssertFalse(app.staticTexts["quota.updatedAt"].exists, "套餐名称必须在收起时可见")
            let title = app.staticTexts["quota.title"].frame
            for id in ["quota.toolbarConnect"] {
                XCTAssertEqual(app.buttons[id].frame.midY, title.midY, accuracy: 4)
            }
            screenshot(app, "T23-双账户-满额耗尽70与20-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testT23UnknownUnlimitedAndFreeHaveNoInventedBarsInBothAppearances() {
        for appearance in ["light", "dark"] {
            let app = launchT23("states", appearance: appearance)
            let cards = app.otherElements.matching(identifier: "quota.card")
            XCTAssertEqual(cards.count, 2)
            let first = cards.element(boundBy: 0), second = cards.element(boundBy: 1)
            XCTAssertEqual(first.staticTexts["quota.weekly.remaining"].label, "未知")
            XCTAssertEqual(first.staticTexts["quota.fiveHours.remaining"].label, "不限量")
            XCTAssertFalse(app.otherElements["quota.weekly.bar"].exists)
            XCTAssertFalse(app.otherElements["quota.fiveHours.bar"].exists)
            XCTAssertEqual(second.staticTexts["quota.plan"].label, "Codex · Free")
            XCTAssertEqual(second.staticTexts["quota.accountIdentity"].label, "card-2@example.invalid")
            for id in ["quota.weekly.remaining", "quota.fiveHours.remaining", "quota.weekly.reset",
                       "quota.fiveHours.reset", "quota.notFetched", "quota.accountStatus", "quota.updatedAt"] {
                XCTAssertFalse(second.descendants(matching: .any)[id].exists, id)
            }
            XCTAssertFalse(app.staticTexts["quota.failure"].exists)
            screenshot(app, "T23-未知不限量与Free-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testT23RefreshFailureKeepsVisiblePlanAmountsAndOriginalSuccessTime() {
        let app = launch("t23-cached-failure")
        defer { app.terminate() }
        completeFixtureLogin(app)
        assertSuccessfulCard(app)
        openDetails(app)
        let originalTime = app.staticTexts["quota.updatedAt"].label
        app.buttons["quota.menu"].tap()
        app.buttons["刷新额度"].tap()
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.failure"].label, "刷新失败")
        XCTAssertEqual(planLabel(app), "Codex · Plus")
        XCTAssertEqual(app.staticTexts["quota.weekly.remaining"].label, "剩余 70%")
        XCTAssertEqual(app.staticTexts["quota.fiveHours.remaining"].label, "剩余 20%")
        // Reconfiguration can collapse details; reopen only if needed.
        if !app.staticTexts["quota.updatedAt"].exists { openDetails(app) }
        XCTAssertEqual(app.staticTexts["quota.updatedAt"].label, originalTime)
        XCTAssertTrue(app.buttons["quota.retry"].exists)
        XCTAssertFalse(app.buttons["重新登录"].exists)
        screenshot(app, "T23-刷新失败保留旧值与时间")
    }

    @MainActor private func launchT23(_ scenario: String, appearance: String, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t23-card-fixture", scenario, appearance] + extra
        app.launch()
        XCTAssertTrue(app.staticTexts["card-2@example.invalid"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func testT17DragOrderAcrossPagesReopenAndAppend() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t16-isolated-ui", "success", "--t16-run-id", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        for index in 1...3 { addT17FixtureAccount(app, index: index) }
        let original = (1...3).map { "account-\($0)@example.invalid" }
        XCTAssertTrue(app.staticTexts[original[2]].waitForExistence(timeout: 5))
        moveT17Row(app, email: original[2], before: original[1])
        let partial = [original[0], original[2], original[1]]
        assertT17Order(app, identifier: "quota.accountIdentity", expected: partial)
        screenshot(app, "T17-三账户局部移动")
        moveT17Row(app, email: original[1], before: original[0])
        let expected = [original[1], original[0], original[2]]
        assertT17Order(app, identifier: "quota.accountIdentity", expected: expected)
        app.buttons["tab.quota"].tap()
        assertT17Order(app, identifier: "quota.accountIdentity", expected: expected)
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label), ["剩余 35%", "剩余 80%", "剩余 35%"])
        screenshot(app, "T17-额度页同序")
        app.terminate(); app.launch()
        assertT17Order(app, identifier: "quota.accountIdentity", expected: expected)
        addT17FixtureAccount(app, index: 4)
        assertT17Order(app, identifier: "quota.accountIdentity", expected: expected + ["account-4@example.invalid"])
        screenshot(app, "T17-排序后新增追加末尾")
    }

    @MainActor
    func testT17FailedDragRetainsOrderAndRetrySaves() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t16-isolated-ui", "order-failure", "--t16-run-id", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        for index in 1...2 { addT17FixtureAccount(app, index: index) }
        let original = ["account-1@example.invalid", "account-2@example.invalid"]
        moveT17Row(app, email: original[1], before: original[0])
        XCTAssertTrue(app.alerts["排序未保存，请重试"].waitForExistence(timeout: 5))
        screenshot(app, "T17-保存失败提示")
        app.alerts.buttons["好"].tap()
        assertT17Order(app, identifier: "quota.accountIdentity", expected: original)
        moveT17Row(app, email: original[1], before: original[0])
        assertT17Order(app, identifier: "quota.accountIdentity", expected: original.reversed())
        app.terminate(); app.launch()
        assertT17Order(app, identifier: "quota.accountIdentity", expected: original.reversed())
    }

    @MainActor
    func testT17RealAccountOrderPersistsAndOriginalOrderIsRestored() throws {
        guard ProcessInfo.processInfo.environment["T17_LIVE_ORDER"] == "1" else {
            throw XCTSkip("显式开启后只验证真实账户排序，不核对真实额度。")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["quota.accountIdentity"].firstMatch.waitForExistence(timeout: 15))
        let rows = app.staticTexts.matching(identifier: "quota.accountIdentity")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        let original = rows.allElementsBoundByIndex.map(\.label)
        guard original.count >= 2 else { throw XCTSkip("手机当前不足两个账户，真实排序待本人验收。") }
        let last = try XCTUnwrap(original.last)
        moveT17Row(app, email: last, before: original[0])
        let expected = [last] + original.dropLast()
        // Boolean assertions avoid printing real identity values to logs.
        XCTAssertTrue(waitT17Order(app, identifier: "quota.accountIdentity", expected: expected))
        app.buttons["tab.quota"].tap()
        XCTAssertTrue(waitT17Order(app, identifier: "quota.accountIdentity", expected: expected))
        app.terminate(); app.launch()
        XCTAssertTrue(waitT17Order(app, identifier: "quota.accountIdentity", expected: expected))
        let source = app.cells.containing(.staticText, identifier: last).firstMatch
        let target = app.cells.containing(.staticText, identifier: original[original.count - 2]).firstMatch
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            .press(forDuration: 0.7, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.95)))
        XCTAssertTrue(waitT17Order(app, identifier: "quota.accountIdentity", expected: original))
        app.terminate(); app.launch()
        XCTAssertTrue(waitT17Order(app, identifier: "quota.accountIdentity", expected: original))
        print("T17 | 真实账户末项置顶→跨页→重开→恢复原序 | 通过；未核对或输出真实额度与身份")
    }

    @MainActor private func addT17FixtureAccount(_ app: XCUIApplication, index: Int) {
        let connect = app.buttons[index == 1 ? "quota.connect" : "quota.toolbarConnect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10)); connect.tap()
        XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
        app.buttons["platforms.codex"].tap()
        XCTAssertTrue(app.buttons["connection.open"].waitForExistence(timeout: 5))
        app.buttons["connection.open"].tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.staticTexts["connection.title"])
        waitForExpectations(timeout: 15)
        XCTAssertTrue(app.buttons["quota.toolbarConnect"].isEnabled)
    }

    @MainActor private func moveT17Row(_ app: XCUIApplication, email: String, before other: String) {
        let source = app.cells.containing(.staticText, identifier: email).firstMatch
        let target = app.cells.containing(.staticText, identifier: other).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            .press(forDuration: 0.7, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
    }

    @MainActor private func waitT17Order(_ app: XCUIApplication, identifier: String, expected: [String]) -> Bool {
        let predicate = NSPredicate { _, _ in
            MainActor.assumeIsolated {
                app.staticTexts.matching(identifier: identifier).allElementsBoundByIndex.map(\.label) == expected
            }
        }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 10) == .completed
    }

    @MainActor private func assertT17Order(_ app: XCUIApplication, identifier: String, expected: [String]) {
        XCTAssertTrue(waitT17Order(app, identifier: identifier, expected: expected))
        XCTAssertEqual(app.staticTexts.matching(identifier: identifier).allElementsBoundByIndex.map(\.label), expected)
    }

    @MainActor
    func testT16SixAccountsRemainScrollableInBothLists() {
        let app = XCUIApplication()
        app.launchArguments = ["--t16-isolated-ui", "success", "--t16-run-id", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        for index in 1...6 {
            app.buttons[index == 1 ? "quota.connect" : "quota.toolbarConnect"].tap()
            XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
            app.buttons["platforms.codex"].tap()
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
        XCTAssertTrue(app.staticTexts["account-6@example.invalid"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["account-6@example.invalid"].isHittable)
        screenshot(app, "T16-六账户管理")
    }

    @MainActor
    func testT18DuplicateLoginKeepsPositionAndCountAfterReopenAndCancel() {
        let app = XCUIApplication()
        app.launchArguments = ["--t16-isolated-ui", "duplicate", "--t16-run-id", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        for index in 1...3 {
            let connect = app.buttons[index == 1 ? "quota.connect" : "quota.toolbarConnect"]
            XCTAssertTrue(connect.waitForExistence(timeout: 5))
            connect.tap()
            XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
            app.buttons["platforms.codex"].tap()
            XCTAssertTrue(app.buttons["connection.open"].waitForExistence(timeout: 5))
            app.buttons["connection.open"].tap()
            XCTAssertTrue(app.staticTexts[index == 3 ? "剩余 55%" : "account-\(index)@example.invalid"].waitForExistence(timeout: 10))
        }
        let identities = app.staticTexts.matching(identifier: "quota.accountIdentity")
        let expected = ["account-1@example.invalid", "account-2@example.invalid"]
        XCTAssertEqual(identities.allElementsBoundByIndex.map(\.label), expected)
        screenshot(app, "T18-重复成功保留两行原位置")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["剩余 55%"].waitForExistence(timeout: 10))
        XCTAssertEqual(identities.allElementsBoundByIndex.map(\.label), expected)
        app.buttons["quota.toolbarConnect"].tap()
        XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
        app.buttons["platforms.codex"].tap()
        XCTAssertTrue(app.buttons["connection.open"].waitForExistence(timeout: 5))
        app.buttons["connection.cancel"].tap()
        XCTAssertEqual(identities.allElementsBoundByIndex.map(\.label), expected)
        XCTAssertTrue(app.staticTexts["剩余 55%"].exists)
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
            XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
            app.buttons["platforms.codex"].tap()
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
        XCTAssertTrue(app.buttons["quota.toolbarConnect"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label), ["account-1@example.invalid", "account-2@example.invalid"])
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
        app.buttons["quota.toolbarConnect"].tap()
        XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
        app.buttons["platforms.codex"].tap()
        XCTAssertTrue(app.buttons["connection.open"].waitForExistence(timeout: 5))
        app.buttons["connection.open"].tap()
        XCTAssertTrue(app.staticTexts["quota.weekly.remaining"].waitForExistence(timeout: 10))
        app.buttons["quota.toolbarConnect"].tap()
        XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
        app.buttons["platforms.codex"].tap()
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
        XCTAssertFalse(app.buttons["quota.refresh"].exists)
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
        XCTAssertTrue(app.collectionViews["quota.list"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        let identity = app.staticTexts["quota.accountIdentity"].label
        app.pullAllQuota()
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
        app.pullAllQuota()
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
        dashboard.pullAllQuota()
        XCTAssertTrue(dashboard.descendants(matching: .any)["quota.refreshProgress"].waitForExistence(timeout: 5))
        assertNoRefreshBanner(dashboard)
        XCTAssertFalse(dashboard.buttons["quota.closeFeedback"].exists)
        XCTAssertFalse(dashboard.staticTexts["connection.title"].exists)
        screenshot(dashboard, "D60-已有卡片重试中")
        assertSuccessfulCard(dashboard)
    }

    @MainActor
    func testLargeTextPreservesReadableCardAndReachableActions() {
        let app = launch("new-plan", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        completeFixtureLogin(app)
        XCTAssertTrue(app.staticTexts["quota.weekly.remaining"].waitForExistence(timeout: 10))
        // The card is published before the successful connection sheet finishes dismissing.
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                 object: app.staticTexts["connection.title"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
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
        XCTAssertTrue(app.buttons["quota.toolbarConnect"].waitForExistence(timeout: 10))
        app.buttons["quota.toolbarConnect"].tap()
        XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
        app.buttons["platforms.codex"].tap()
        XCTAssertTrue(app.staticTexts["connection.code"].waitForExistence(timeout: 5))
        app.buttons["connection.open"].tap()
    }
    @MainActor private func screenshot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}


@MainActor
extension XCUIApplication {
    func pullAllQuota() {
        let list = collectionViews["quota.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
    }
}
