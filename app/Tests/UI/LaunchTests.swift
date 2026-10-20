import XCTest

final class LaunchTests: XCTestCase {
    /// The missing dark / maximum-text / static combination. Restore Motion exactly.
    @MainActor
    func testT47DarkMaximumTextReducedMotionTutorial() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString,
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let motion = settings.switches["REDUCE_MOTION"]
        if !motion.waitForExistence(timeout: 5) {
            for _ in 0..<6 {
                if settings.navigationBars.firstMatch.identifier == "设置" { break }
                let back = settings.navigationBars.firstMatch.buttons.firstMatch
                if back.exists { back.tap() } else { break }
            }
            let accessibility = settings.buttons["com.apple.settings.accessibility"]
            for _ in 0..<8 { if accessibility.isHittable { break }; settings.swipeUp() }
            XCTAssertTrue(accessibility.isHittable); accessibility.tap()
            let entry = settings.staticTexts["动态效果"]
            for _ in 0..<5 { if entry.isHittable { break }; settings.swipeUp() }
            XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        }
        XCTAssertTrue(motion.waitForExistence(timeout: 5))
        let original = try XCTUnwrap(motion.value as? String)
        addTeardownBlock {
            await MainActor.run {
                settings.activate()
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: motion)], timeout: 8), .completed)
                if motion.value as? String != original {
                    motion.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", original), object: motion)], timeout: 5), .completed)
                app.terminate()
                print("T47 motion: exact original restored")
            }
        }
        if original != "1" { motion.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: motion)], timeout: 5), .completed)
        app.launch()
        app.buttons["tab.settings"].tap()
        let dark = app.switches["settings.darkAppearance"]
        if dark.value as? String != "1" { dark.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        XCTAssertEqual(dark.value as? String, "1")
        openT45Entry("widgetTutorial", in: app)
        for page in 0..<2 {
            assertT42Step(in: app, second: page == 1)
            let demo = app.descendants(matching: .any).matching(identifier: "tutorial.demo.\(page)").firstMatch
            XCTAssertEqual(demo.value as? String, "静态关键画面")
            saveScreenshot(of: app, name: "T47-深色最大字号静态-第\(page+1)页-顶部")
            let text = app.staticTexts["tutorial.instructions.\(page)"]
            for offset in 0..<30 {
                if text.isHittable && text.frame.maxY <= app.buttons["tutorial.next"].frame.minY { break }
                app.scrollViews.firstMatch.swipeUp()
                saveScreenshot(of: app, name: "T47-深色最大字号静态-第\(page+1)页-滚动\(offset)")
            }
            XCTAssertTrue(text.isHittable)
            XCTAssertLessThanOrEqual(text.frame.maxY, app.buttons["tutorial.next"].frame.minY)
            XCTAssertLessThanOrEqual(text.frame.maxX, app.frame.maxX)
            XCTAssertTrue(app.buttons["tutorial.close"].isHittable)
            XCTAssertTrue(app.buttons["tutorial.next"].isHittable)
            app.buttons["tutorial.next"].tap()
        }
        XCTAssertTrue(app.buttons["tab.settings"].isSelected)
        openT45Entry("widgetTutorial", in: app)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "tutorial.demo.0").firstMatch.value as? String, "静态关键画面")
        app.buttons["tutorial.close"].tap()
        XCTAssertTrue(app.buttons["tab.settings"].isSelected)
    }

    @MainActor
    func testT47DarkConnectionWaitingCodeAndFailuresStayReadable() {
        continueAfterFailure = false
        for scenario in ["slow", "51", "50", "unknown"] {
            let app = XCUIApplication()
            // Argument-domain override only; never write the formal appearance preference.
            app.launchArguments = ["--t07-isolated-ui", scenario, "-appearance", "dark"]
            app.launch()
            XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 8))
            app.buttons["tab.settings"].tap()
            XCTAssertEqual(app.switches["settings.darkAppearance"].value as? String, "1")
            app.buttons["tab.quota"].tap()
            app.buttons["quota.toolbarConnect"].tap()
            XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
            saveScreenshot(of: app, name: "T47-深色连接-\(scenario)-平台弹层")
            app.buttons["platforms.codex"].tap()
            if scenario == "slow" {
                let progress = app.descendants(matching: .any).matching(identifier: "connection.progress").firstMatch
                XCTAssertTrue(progress.waitForExistence(timeout: 2))
                saveScreenshot(of: app, name: "T47-深色连接-等待")
            } else if scenario == "51" {
                XCTAssertTrue(app.staticTexts["connection.code"].waitForExistence(timeout: 5))
                XCTAssertEqual(app.staticTexts["connection.code"].label, "TEST-CODE")
                XCTAssertTrue(app.buttons["connection.copy"].isHittable)
                XCTAssertTrue(app.buttons["connection.open"].isHittable)
                saveScreenshot(of: app, name: "T47-深色连接-代码")
            } else {
                let failure = app.staticTexts["connection.failure"]
                XCTAssertTrue(failure.waitForExistence(timeout: 5))
                XCTAssertEqual(failure.label, scenario == "50" ? "网络不达标，无法连接" : "登录未完成，请重试")
                XCTAssertTrue(app.buttons["connection.retry"].isHittable)
                saveScreenshot(of: app, name: "T47-深色连接-\(scenario)-失败")
            }
            XCTAssertTrue(app.buttons["connection.cancel"].isHittable)
            app.buttons["connection.cancel"].tap()
            XCTAssertTrue(app.buttons["tab.quota"].isSelected)
            app.terminate()
        }
    }

    @MainActor
    func testT46IntegratedSettingsRoutesCancelAndDemoCleanup() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 8))
        app.buttons["tab.settings"].tap()
        let reminder = app.switches["settings.resetReminder"]
        XCTAssertEqual(reminder.value as? String, "0")
        for identifier in ["settings.accounts", "settings.connect", "settings.refreshFrequency", "settings.quotaPerspective"] {
            XCTAssertFalse(app.descendants(matching: .any)[identifier].exists)
        }
        // Existing pages are checked here as one interleaved navigation session.
        for (entry, title) in [("help", "帮助与说明"), ("privacy", "隐私说明"), ("licenses", "开源许可")] {
            openT45Entry(entry, in: app)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            app.buttons["tab.quota"].tap()
            XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5))
            app.buttons["tab.settings"].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            if entry == "help" {
                // Visit the system app without changing permission or any switch.
                let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
                settings.activate()
                XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 8))
                app.activate()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            }
            if entry == "licenses" {
                app.buttons["licenses.lobeIcons"].tap()
                XCTAssertTrue(app.navigationBars["Lobe Icons 许可"].waitForExistence(timeout: 5))
                app.navigationBars["Lobe Icons 许可"].buttons.firstMatch.tap()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            }
            app.navigationBars[title].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        }
        for _ in 0..<8 { if app.buttons["settings.widgetTutorial"].isHittable { break }; app.swipeDown() }
        for second in [false, true] {
            app.buttons["settings.widgetTutorial"].tap()
            assertT42Step(in: app, second: false)
            if second { app.buttons["tutorial.next"].tap(); assertT42Step(in: app, second: true) }
            app.buttons["tutorial.close"].tap()
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["tab.settings"].isSelected)
        }
        for _ in 0..<8 { if app.switches["settings.demo"].isHittable { break }; app.swipeUp() }
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["tab.quota"].tap()
        for count in 1...2 {
            app.buttons["quota.toolbarConnect"].tap()
            let ready = NSPredicate { _, _ in MainActor.assumeIsolated {
                app.staticTexts.matching(identifier: "quota.accountIdentity").count == count + 1 // + T96 Cursor sample
            }}
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 5), .completed)
        }
        let before = app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label)
        app.buttons.matching(identifier: "quota.menu").firstMatch.tap()
        app.buttons["删除账户"].tap()
        app.alerts.buttons["取消"].tap()
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label), before)
        saveScreenshot(of: app, name: "T46-额度菜单删除取消后两户保持")
        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertEqual(reminder.value as? String, "0")
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        saveScreenshot(of: app, name: "T46-返回设置关闭演示")
        app.buttons["tab.quota"].tap()
        XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5))
        app.buttons["quota.toolbarConnect"].tap()
        XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 5))
        app.buttons["connection.cancel"].tap()
        XCTAssertTrue(app.buttons["tab.quota"].isSelected)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5))
        app.buttons["tab.settings"].tap()
        XCTAssertEqual(app.switches["settings.demo"].value as? String, "0")
        XCTAssertEqual(reminder.value as? String, "0")
        XCTAssertTrue(app.buttons["settings.widgetTutorial"].isEnabled)
        saveScreenshot(of: app, name: "T46-重开设置入口仍可用")
    }

    @MainActor
    func testT44HelpNavigationLightAndDark() {
        checkT44Help(maximumText: false)
    }

    @MainActor
    func testT44HelpMaximumTextRemainsScrollable() {
        checkT44Help(maximumText: true)
    }

    @MainActor
    private func checkT44Help(maximumText: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        if maximumText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        defer { app.terminate() }
        app.buttons["tab.settings"].tap()
        for dark in [false, true] {
            if dark { app.switches["settings.darkAppearance"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
            let entry = app.buttons["settings.help"]
            // At the largest text the row can sit under the tab bar while still reported hittable.
            for _ in 0..<6 {
                if entry.isHittable, entry.frame.maxY < app.buttons["tab.settings"].frame.minY { break }
                app.swipeUp()
            }
            XCTAssertTrue(entry.isHittable); entry.tap()
            XCTAssertTrue(app.navigationBars["帮助与说明"].waitForExistence(timeout: 5))
            for identifier in ["quota", "refresh", "reminders", "widgets"] {
                let text = app.staticTexts["help.\(identifier)"]
                for _ in 0..<12 { if text.isHittable { break }; app.swipeUp() }
                XCTAssertTrue(text.isHittable, identifier)
                XCTAssertGreaterThanOrEqual(text.frame.minX, 0)
                XCTAssertLessThanOrEqual(text.frame.maxX, app.frame.maxX)
                saveScreenshot(of: app, name: "T44-\(maximumText ? "大字号" : "正常")-\(dark ? "深" : "浅")-\(identifier)")
                for _ in 0..<12 {
                    if text.frame.maxY < app.buttons["tab.settings"].frame.minY { break }
                    app.swipeUp()
                }
                XCTAssertLessThan(text.frame.maxY, app.buttons["tab.settings"].frame.minY)
                saveScreenshot(of: app, name: "T44-\(maximumText ? "大字号" : "正常")-\(dark ? "深" : "浅")-\(identifier)-末尾")
            }
            app.navigationBars["帮助与说明"].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
            for _ in 0..<8 { if app.switches["settings.darkAppearance"].isHittable { break }; app.swipeDown() }
        }
        app.buttons["tab.quota"].tap()
        assertEmptyQuota(in: app)
    }

    @MainActor
    func testT45PrivacyAndBundledLicenseLightDarkOffline() {
        checkT45Support(maximumText: false)
    }

    @MainActor
    func testT45PrivacyAndLicenseMaximumText() {
        checkT45Support(maximumText: true)
    }

    @MainActor
    private func checkT45Support(maximumText: Bool) {
        continueAfterFailure = false
        let app = XCUIApplication()
        // Existing management isolation refuses all account-network requests.
        app.launchArguments = ["--management-ui", UUID().uuidString]
        if maximumText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        defer { app.terminate() }
        let mode = maximumText ? "大字号" : "离线正常"
        for dark in [false, true] {
            app.buttons["tab.settings"].tap()
            if dark {
                for _ in 0..<12 { if app.switches["settings.darkAppearance"].isHittable { break }; app.swipeDown() }
                app.switches["settings.darkAppearance"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            openT45Entry("privacy", in: app)
            XCTAssertTrue(app.navigationBars["隐私说明"].waitForExistence(timeout: 5))
            for identifier in ["source", "network", "storage", "collection", "deletion"] {
                let text = app.staticTexts["privacy.\(identifier)"]
                for _ in 0..<16 { if text.isHittable { break }; app.swipeUp() }
                XCTAssertTrue(text.isHittable)
                saveScreenshot(of: app, name: "T45-\(mode)-\(dark ? "深" : "浅")-隐私-\(identifier)-开头")
                for _ in 0..<24 { if text.frame.maxY < app.buttons["tab.settings"].frame.minY { break }; app.swipeUp() }
                XCTAssertLessThan(text.frame.maxY, app.buttons["tab.settings"].frame.minY)
                saveScreenshot(of: app, name: "T45-\(mode)-\(dark ? "深" : "浅")-隐私-\(identifier)-末尾")
            }
            app.navigationBars["隐私说明"].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
            openT45Entry("licenses", in: app)
            let license = app.buttons["licenses.lobeIcons"]
            XCTAssertTrue(license.waitForExistence(timeout: 5)); XCTAssertTrue(license.label.contains("MIT"))
            saveScreenshot(of: app, name: "T45-\(mode)-\(dark ? "深" : "浅")-清单")
            license.tap()
            XCTAssertTrue(app.navigationBars["Lobe Icons 许可"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["license.unavailable"].exists)
            XCTAssertEqual(app.staticTexts["license.paragraph.0"].label, "MIT License")
            XCTAssertEqual(app.staticTexts["license.paragraph.1"].label, "Copyright (c) 2023 LobeHub")
            saveScreenshot(of: app, name: "T45-\(mode)-\(dark ? "深" : "浅")-许可开头")
            let end = app.staticTexts["license.paragraph.4"]
            for _ in 0..<40 {
                if end.exists && end.isHittable && end.frame.maxY < app.buttons["tab.settings"].frame.minY { break }
                app.swipeUp()
            }
            XCTAssertTrue(end.isHittable)
            XCTAssertTrue(end.label.contains("THE SOFTWARE IS PROVIDED"))
            XCTAssertTrue(end.label.hasSuffix("SOFTWARE.\n"))
            XCTAssertLessThan(end.frame.maxY, app.buttons["tab.settings"].frame.minY)
            saveScreenshot(of: app, name: "T45-\(mode)-\(dark ? "深" : "浅")-许可末尾")
            app.navigationBars["Lobe Icons 许可"].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["开源许可"].waitForExistence(timeout: 5))
            let lucide = app.buttons["licenses.lucide"]
            XCTAssertTrue(lucide.waitForExistence(timeout: 5)); XCTAssertTrue(lucide.label.contains("ISC"))
            lucide.tap()
            XCTAssertTrue(app.navigationBars["Lucide 许可"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["license.unavailable"].exists)
            XCTAssertEqual(app.staticTexts["license.paragraph.0"].label, "ISC License")
            XCTAssertTrue(app.staticTexts["license.paragraph.1"].label.contains("Lucide Contributors 2022"))
            let lucideEnd = app.staticTexts["license.paragraph.3"]
            for _ in 0..<40 {
                if lucideEnd.exists && lucideEnd.isHittable && lucideEnd.frame.maxY < app.buttons["tab.settings"].frame.minY { break }
                app.swipeUp()
            }
            XCTAssertTrue(lucideEnd.isHittable)
            XCTAssertTrue(lucideEnd.label.contains("THE SOFTWARE IS PROVIDED"))
            XCTAssertTrue(lucideEnd.label.hasSuffix("SOFTWARE.\n"))
            saveScreenshot(of: app, name: "T99-\(mode)-\(dark ? "深" : "浅")-Lucide许可末尾")
            app.navigationBars["Lucide 许可"].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["开源许可"].waitForExistence(timeout: 5))
            app.navigationBars["开源许可"].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
            if !maximumText && !dark {
                app.terminate(); app.launch()
                // Cold reopen still reads all support content without a usable connection.
            }
        }
        app.buttons["tab.quota"].tap()
        assertEmptyQuota(in: app)
    }

    @MainActor
    private func openT45Entry(_ identifier: String, in app: XCUIApplication) {
        let entry = app.buttons["settings.\(identifier)"]
        for _ in 0..<12 {
            if entry.isHittable && entry.frame.maxY < app.buttons["tab.settings"].frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(entry.isHittable)
        XCTAssertLessThan(entry.frame.maxY, app.buttons["tab.settings"].frame.minY)
        entry.tap()
    }

    /// Read-only by default; explicit T43_LAYOUT_ADD checks and cleans one new instance.
    @MainActor
    func testT43ReadActualAddingPageLayouts() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["T43_LAYOUT_REFERENCE"] == "1" || environment["T43_LAYOUT_ADD"] == "1" else {
            throw XCTSkip("显式启用本人系统页面参照；普通回归不操作主屏幕")
        }
        continueAfterFailure = false
        let app = XCUIApplication(), session = UUID().uuidString
        let board = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        addTeardownBlock {
            await MainActor.run {
                XCUIDevice.shared.press(.home); XCUIDevice.shared.press(.home)
                app.terminate()
                app.launchArguments = ["--t36-desktop-fixture", "cleanup", session]
                app.launch()
                XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 8))
                app.terminate()
            }
        }
        app.launchArguments = ["--t36-desktop-fixture", "baseline", session]
        app.launch()
        XCTAssertTrue(app.buttons["quota.widgetTutorial"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home); XCUIDevice.shared.press(.home)
        let addForLayout = ProcessInfo.processInfo.environment["T43_LAYOUT_ADD"] == "1"
        let widgets = board.icons.matching(NSPredicate(format: "label == %@ AND value == %@", "订阅用量", "小组件"))
        if addForLayout {
            for _ in 0..<10 { if widgets.count == 0 { break }; board.swipeLeft() }
            XCTAssertEqual(widgets.count, 0, "只在无本App组件的页面添加，保护旧实例")
        }
        saveScreenshot(of: board, name: "T43R-系统-主屏幕")
        let occupied = board.icons.allElementsBoundByIndex.filter(\.isHittable).map(\.frame)
        var blank: CGPoint?
        for y in stride(from: 0.78, through: 0.20, by: -0.04) {
            for x in stride(from: 0.90, through: 0.10, by: -0.10) {
                let point = CGPoint(x: board.frame.width * x, y: board.frame.height * y)
                if !occupied.contains(where: { $0.insetBy(dx: -8, dy: -8).contains(point) }) { blank = point; break }
            }
            if blank != nil { break }
        }
        let point = try XCTUnwrap(blank)
        board.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).press(forDuration: 1.5)
        XCTAssertTrue(board.buttons["编辑"].waitForExistence(timeout: 8))
        saveScreenshot(of: board, name: "T43R-系统-编辑状态")
        board.buttons["编辑"].tap()
        XCTAssertTrue(board.buttons["添加小组件"].waitForExistence(timeout: 5))
        saveScreenshot(of: board, name: "T43R-系统-编辑菜单")
        board.buttons["添加小组件"].tap()
        let search = board.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        saveScreenshot(of: board, name: "T43R-系统-图库")
        search.tap(); search.typeText("订阅用量")
        let result = board.collectionViews["add-sheet-collection-view"].cells["订阅用量"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        saveScreenshot(of: board, name: "T43R-系统-搜索结果")
        result.tap()
        let preview = board.buttons["订阅用量, 订阅额度"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        XCTAssertEqual(preview.value as? String, "小组件, 小")
        Thread.sleep(forTimeInterval: 1) // Let SpringBoard finish its carousel transition.
        saveScreenshot(of: board, name: "T43R-系统-小号预览")
        board.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.56)).press(forDuration: 0.1,
            thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.56)))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "小组件, 中"), object: preview)], timeout: 8), .completed)
        Thread.sleep(forTimeInterval: 1)
        saveScreenshot(of: board, name: "T43R-系统-中号预览")
        if addForLayout {
            XCTAssertEqual(widgets.count, 0)
            let add = board.buttons.matching(NSPredicate(format: "label CONTAINS %@", "添加小组件")).firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
            XCTAssertTrue(board.buttons["完成"].waitForExistence(timeout: 8))
            XCTAssertEqual(widgets.count, 1)
            // No older App widget existed on this page; this is the new owned instance.
            let owned = widgets.firstMatch
            addTeardownBlock {
                await MainActor.run {
                    XCTAssertEqual(widgets.count, 1, "新实例无法唯一识别时停止，不猜测删除")
                    owned.press(forDuration: 1.5)
                    let remove = board.buttons["移除小组件"]
                    XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
                    let confirm = board.alerts.buttons["移除"]
                    XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
                    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                        MainActor.assumeIsolated { widgets.count == 0 }
                    }, object: nil)], timeout: 8), .completed)
                    print("T43R cleanup: uniquely new medium removed; page count 1→0")
                }
            }
            Thread.sleep(forTimeInterval: 1)
            saveScreenshot(of: board, name: "T43R-系统-添加后编辑状态")
            board.buttons["完成"].tap()
            XCTAssertTrue(board.staticTexts["batch-1"].firstMatch.waitForExistence(timeout: 30))
            saveScreenshot(of: board, name: "T43R-系统-新增临时中号")
            print("T43R reference: full first flow observed; uniquely new 0→1 medium; teardown checks removal")
        } else {
            XCUIDevice.shared.press(.home); XCUIDevice.shared.press(.home)
            print("T43R reference: home/edit/menu/gallery/search/small/medium observed; no widget mutation")
        }
    }

    @MainActor
    func testT43FirstAnimationAllLayoutsLightAndDark() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        cleanT42Fixture(in: app); app.launch()
        defer { app.terminate() }
        for dark in [false, true] {
            app.buttons["tab.settings"].tap()
            let toggle = app.switches["settings.darkAppearance"]
            if toggle.value as? String != (dark ? "1" : "0") {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            app.buttons["settings.widgetTutorial"].tap()
            let demo = app.descendants(matching: .any).matching(identifier: "tutorial.demo.0").firstMatch
            XCTAssertTrue(demo.waitForExistence(timeout: 5))
            // Capture on a clock rather than waiting for transient accessibility values.
            // On the physical phone, hierarchy snapshots may outlast an entire frame.
            for capture in 0..<24 {
                saveScreenshot(of: app, name: "T43R-第一动画-\(dark ? "深" : "浅")-连续\(capture)")
                Thread.sleep(forTimeInterval: 1)
            }
            let cycle = Int((demo.value as? String)?.components(separatedBy: "循环 ").last ?? "") ?? 0
            XCTAssertGreaterThanOrEqual(cycle, 2, "第一动画必须重复播放，不保留终点")
            assertT42Step(in: app, second: false)
            app.buttons["tutorial.close"].tap()
            XCTAssertTrue(app.buttons["tab.settings"].isSelected)
        }
    }

    @MainActor
    func testT43ContentSizedSheetsAndMatchingAnimationRegions() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        cleanT42Fixture(in: app); app.launch()
        defer { app.terminate() }
        for dark in [false, true] {
            app.buttons["tab.settings"].tap()
            let toggle = app.switches["settings.darkAppearance"]
            if toggle.value as? String != (dark ? "1" : "0") {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            app.buttons["settings.widgetTutorial"].tap()
            var firstSize = CGSize.zero
            for page in 0..<2 {
                assertT42Step(in: app, second: page == 1)
                // Wait for the native sheet's content-sized detent to settle.
                Thread.sleep(forTimeInterval: 1)
                let demo = app.descendants(matching: .any).matching(identifier: "tutorial.demo.\(page)").firstMatch
                let text = app.staticTexts["tutorial.instructions.\(page)"]
                let close = app.buttons["tutorial.close"]
                let next = app.buttons["tutorial.next"]
                let height = app.frame.maxY - close.frame.minY
                let gap = next.frame.minY - text.frame.maxY
                XCTAssertLessThan(height, app.frame.height * 0.65, "正常字号弹窗应接近半屏")
                XCTAssertGreaterThan(height, app.frame.height * 0.45)
                XCTAssertGreaterThanOrEqual(gap, 14)
                XCTAssertLessThan(gap, 80, "正文与底部按钮不应有大块空白")
                XCTAssertGreaterThanOrEqual(text.frame.minX, 0)
                XCTAssertLessThanOrEqual(text.frame.maxX, app.frame.maxX)
                XCTAssertLessThanOrEqual(text.frame.maxY, next.frame.minY)
                XCTAssertTrue(text.isHittable)
                XCTAssertLessThanOrEqual(next.frame.maxY, app.frame.maxY)
                if page == 0 { firstSize = demo.frame.size } else {
                    XCTAssertEqual(demo.frame.width, firstSize.width, accuracy: 1)
                    XCTAssertEqual(demo.frame.height, firstSize.height, accuracy: 1)
                }
                print("T43 LAYOUT | \(dark ? "dark" : "light") page=\(page + 1) height=\(height) screen=\(app.frame.height) gap=\(gap) animation=\(demo.frame.size)")
                saveScreenshot(of: app, name: "T43L-\(dark ? "深" : "浅")-第\(page + 1)页")
                if page == 1 {
                    // Include intermediate content as the second demonstration advances.
                    for capture in 0..<8 {
                        saveScreenshot(of: app, name: "T43L-\(dark ? "深" : "浅")-第二动画-\(capture)")
                        Thread.sleep(forTimeInterval: 1)
                    }
                    XCTAssertEqual(demo.value as? String, "画面 4，共 4 个")
                }
                app.buttons["tutorial.next"].tap()
            }
            XCTAssertTrue(app.buttons["tab.settings"].isSelected)
        }
    }

    /// Changes only Motion, restores its exact original value even on test failure.
    @MainActor
    func testT43SystemMotionPreferenceAnimationAndStaticKeyframes() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        cleanT42Fixture(in: app)
        app.launch()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let toggle = settings.switches["REDUCE_MOTION"]
        if !toggle.waitForExistence(timeout: 5) {
            for _ in 0..<6 {
                if settings.navigationBars.firstMatch.identifier == "设置" { break }
                let back = settings.navigationBars.firstMatch.buttons.firstMatch
                if back.exists { back.tap() } else { break }
            }
            let accessibility = settings.buttons["com.apple.settings.accessibility"]
            for _ in 0..<8 { if accessibility.isHittable { break }; settings.swipeUp() }
            XCTAssertTrue(accessibility.isHittable, settings.debugDescription)
            accessibility.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "identifier == %@", "辅助功能"), object: settings.navigationBars.firstMatch)], timeout: 5), .completed, settings.debugDescription)
            let motion = settings.staticTexts["动态效果"]
            for _ in 0..<5 { if motion.isHittable { break }; settings.swipeUp() }
            XCTAssertTrue(motion.waitForExistence(timeout: 5), settings.debugDescription); motion.tap()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), settings.debugDescription)
        let original = try XCTUnwrap(toggle.value as? String)
        addTeardownBlock {
            await MainActor.run {
                settings.activate()
                XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 8))
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: toggle)], timeout: 8), .completed)
                if toggle.value as? String != original {
                    toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", original), object: toggle)], timeout: 5), .completed)
                app.terminate()
            }
        }
        for reduced in [false, true] {
            settings.activate()
            XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 8))
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: toggle)], timeout: 8), .completed)
            if toggle.value as? String != (reduced ? "1" : "0") {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", reduced ? "1" : "0"), object: toggle)], timeout: 5), .completed)
            app.terminate()
            if reduced {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 8))
            if reduced { app.buttons["tab.settings"].tap() }
            let entry = app.buttons[reduced ? "settings.widgetTutorial" : "quota.widgetTutorial"]
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hittable == true"), object: entry)], timeout: 8), .completed)
            entry.tap()
            for page in 0..<2 {
                assertT42Step(in: app, second: page == 1)
                let demo = app.descendants(matching: .any).matching(identifier: "tutorial.demo.\(page)").firstMatch
                XCTAssertTrue(demo.waitForExistence(timeout: 5))
                if reduced {
                    XCTAssertEqual(demo.value as? String, "静态关键画面")
                    saveScreenshot(of: app, name: "T43-系统减少动态-第\(page + 1)步-顶部")
                    let instructions = app.staticTexts["tutorial.instructions.\(page)"]
                    for offset in 0..<30 {
                        if instructions.isHittable && instructions.frame.maxY <= app.buttons["tutorial.next"].frame.minY { break }
                        app.scrollViews.firstMatch.swipeUp()
                        saveScreenshot(of: app, name: "T43-系统减少动态-第\(page + 1)步-滚动\(offset)")
                    }
                    XCTAssertTrue(instructions.isHittable)
                    XCTAssertLessThanOrEqual(instructions.frame.maxY, app.buttons["tutorial.next"].frame.minY)
                    saveScreenshot(of: app, name: "T43-系统减少动态-第\(page + 1)步-关键画面")
                    XCTAssertEqual(demo.value as? String, "静态关键画面")
                    XCTAssertTrue(app.buttons["tutorial.close"].isHittable)
                    XCTAssertTrue(app.buttons["tutorial.next"].isHittable)
                } else {
                    XCTAssertTrue((demo.value as? String)?.contains("画面") == true)
                    saveScreenshot(of: app, name: "T43-动画-第\(page + 1)步-开始")
                    let final = "画面 \(page == 0 ? 8 : 4)，共 \(page == 0 ? 8 : 4) 个"
                    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "value BEGINSWITH %@", final), object: demo)], timeout: 30), .completed)
                    saveScreenshot(of: app, name: "T43-动画-第\(page + 1)步-结束")
                }
                app.buttons["tutorial.next"].tap()
            }
            XCTAssertTrue(app.buttons[reduced ? "tab.settings" : "tab.quota"].isSelected)
        }
        print("T43 MOTION | system toggle normal/static verified; exact original restored by teardown")
    }

    @MainActor
    func testT43AnimationDoesNotBlockPagingClosingOrBackgroundReturn() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        cleanT42Fixture(in: app); app.launch()
        defer { app.terminate() }
        for settings in [false, true] {
            if settings { app.buttons["tab.settings"].tap() }
            let entry = app.buttons[settings ? "settings.widgetTutorial" : "quota.widgetTutorial"]
            entry.tap()
            swipeTutorial(in: app, forward: true); assertT42Step(in: app, second: true)
            swipeTutorial(in: app, forward: false); assertT42Step(in: app, second: false)
            XCUIDevice.shared.press(.home); app.activate()
            assertT42Step(in: app, second: false)
            let firstDemo = app.descendants(matching: .any).matching(identifier: "tutorial.demo.0").firstMatch
            XCTAssertTrue((firstDemo.value as? String)?.contains("循环 ") == true)
            app.buttons["tutorial.close"].tap()
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap(); app.buttons["tutorial.next"].tap()
            XCUIDevice.shared.press(.home); app.activate()
            assertT42Step(in: app, second: true)
            app.buttons["tutorial.close"].tap()
            XCTAssertTrue(entry.waitForExistence(timeout: 5))
            entry.tap(); app.buttons["tutorial.next"].tap(); app.buttons["tutorial.next"].tap()
            XCTAssertTrue(app.buttons[settings ? "tab.settings" : "tab.quota"].isSelected)
        }
    }


    /// Opt-in system check, with the existing expiring widget fixture. No real
    /// accounts are read or cleared; existing desktop widgets are retained.
    @MainActor
    func testT43ActualSystemAddAndSelectNewWidget() throws {
        guard ProcessInfo.processInfo.environment["T43_SYSTEM_WIDGET_FLOW"] == "1" else {
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
        XCUIDevice.shared.press(.home)
        XCUIDevice.shared.press(.home)
        let widgets = springboard.icons.matching(NSPredicate(format: "label == %@ AND value == %@", "订阅用量", "小组件"))

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
        // Add on a page without this App's widgets, so the new instance is unambiguous.
        for _ in 0..<10 {
            if widgets.count == 0 { break }
            springboard.swipeLeft()
        }
        XCTAssertEqual(widgets.count, 0, "没有找到空组件页，不改现有配置")
        let before = widgets.count
        let previousFrames = widgets.allElementsBoundByIndex.map(\.frame)
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
        print("T43 SYSTEM | native small and medium pages verified")
        add.tap()
        XCTAssertTrue(springboard.buttons["完成"].waitForExistence(timeout: 8))
        springboard.buttons["完成"].tap()
        let added = NSPredicate { _, _ in MainActor.assumeIsolated { widgets.count == before + 1 } }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: added, object: nil)], timeout: 15), .completed)
        XCTAssertTrue(springboard.staticTexts["batch-1"].firstMatch.waitForExistence(timeout: 30))
        print("T43 SYSTEM | added medium | widget count \(before) -> \(widgets.count) | default fixture first account visible")
        let currentFrames = widgets.allElementsBoundByIndex.map(\.frame)
        // Never guess which existing widget to configure. Require unchanged old positions.
        XCTAssertTrue(previousFrames.allSatisfy { currentFrames.contains($0) }, "旧组件位置变化，停止选择，保护原配置")
        let newFrames = currentFrames.filter { !previousFrames.contains($0) }
        let newFrame = try XCTUnwrap(newFrames.count == 1 ? newFrames.first : nil)
        app.activate()
        assertT42Step(in: app, second: false)
        app.buttons["tutorial.next"].tap()
        assertT42Step(in: app, second: true)
        XCUIDevice.shared.press(.home)
        springboard.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: newFrame.midX, dy: newFrame.midY)).press(forDuration: 1.5)
        let edit = springboard.buttons["编辑小组件"]
        XCTAssertTrue(edit.waitForExistence(timeout: 8), springboard.debugDescription)
        edit.tap()
        let accountRow = springboard.buttons["跟随列表首个账户"]
        XCTAssertTrue(accountRow.waitForExistence(timeout: 8))
        accountRow.tap()
        let secondAccount = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "batch-2@example.invalid")).firstMatch
        XCTAssertTrue(secondAccount.waitForExistence(timeout: 8))
        secondAccount.tap()
        saveScreenshot(of: springboard, name: "T43-实际系统-新组件显示账户选第二户")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(springboard.staticTexts["batch-2"].firstMatch.waitForExistence(timeout: 20))
        print("T43 SYSTEM | edited only newly added medium; selected fixture second account visible")
        // Remove only this uniquely identified temporary widget; all older instances are elsewhere.
        XCTAssertEqual(widgets.count, 1)
        springboard.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: newFrame.midX, dy: newFrame.midY)).press(forDuration: 1.5)
        let remove = springboard.buttons["移除小组件"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        let confirm = springboard.alerts.buttons["移除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            MainActor.assumeIsolated { widgets.count == 0 }
        }, object: nil)], timeout: 8), .completed)
        print("T43 SYSTEM | removed only temporary selected widget; existing configurations retained")
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
            for _ in 0..<8 {
                if instructions.isHittable && instructions.frame.maxY <= app.buttons["tutorial.next"].frame.minY { break }
                app.scrollViews.firstMatch.swipeUp()
            }
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
        let pager = app.descendants(matching: .any).matching(identifier: "tutorial.pages").firstMatch
        let start = pager.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.85 : 0.15, dy: 0.5))
        let end = pager.coordinate(withNormalizedOffset: CGVector(dx: forward ? 0.15 : 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func assertT42Step(in app: XCUIApplication, second: Bool) {
        let text = app.staticTexts["tutorial.instructions.\(second ? 1 : 0)"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertEqual(text.label, second ? "长按小组件，选择要显示的账号" : "长按主屏幕，然后添加 TokenLeft。")
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
                app.staticTexts.matching(identifier: "quota.accountIdentity").count == count + 1 // + T96 Cursor sample
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
                app.staticTexts.matching(identifier: "quota.accountIdentity").count == count + 1 // + T96 Cursor sample
            }}
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: countMatches, object: nil)], timeout: 5), .completed)
        }
        XCTAssertFalse(app.staticTexts["connection.code"].exists)
        let original = app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label)
        let amounts = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
        app.buttons.matching(identifier: "quota.menu").element(boundBy: 2).tap()
        XCTAssertTrue(app.buttons["刷新额度"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["删除账户"].exists)
        app.buttons["刷新额度"].tap()
        let changed = NSPredicate { _, _ in MainActor.assumeIsolated {
            app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label) != amounts
        }}
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 5), .completed)
        let after = app.staticTexts.matching(identifier: "quota.weekly.remaining").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(after[0], amounts[0]); XCTAssertEqual(after[2], amounts[2]); XCTAssertNotEqual(after[1], amounts[1])
        app.buttons.matching(identifier: "quota.menu").element(boundBy: 2).tap()
        app.buttons["删除账户"].tap()
        XCTAssertTrue(app.alerts["删除账户？"].waitForExistence(timeout: 3))
        app.alerts.buttons["取消"].tap()
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label), original)
        app.buttons.matching(identifier: "quota.menu").element(boundBy: 2).tap()
        app.buttons["删除账户"].tap()
        app.alerts.buttons["删除账户"].tap()
        XCTAssertTrue(app.staticTexts[original[1]].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts[original[2]].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts[original[3]].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[original[0]].exists, "Cursor示例保留")
        XCTAssertFalse(app.staticTexts[original[2]].exists)
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
    func testT96DemoSwitchShowsCursorMonthlySampleAndClears() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        app.buttons["tab.settings"].tap()
        for _ in 0..<8 { if app.switches["settings.demo"].isHittable { break }; app.swipeUp() }
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["tab.quota"].tap()
        let monthly = app.staticTexts["quota.monthly.remaining"]
        XCTAssertTrue(monthly.waitForExistence(timeout: 5), "打开演示即出现Cursor示例的“本月”")
        XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").count, 1)
        XCTAssertFalse(app.staticTexts["quota.weekly.remaining"].exists)
        XCTAssertFalse(app.staticTexts["quota.fiveHours.remaining"].exists, "Cursor示例没有5小时")
        XCTAssertTrue(app.staticTexts["quota.grokBot.remaining"].exists, "Cursor示例第二行Grok Bot（D-80）")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "本月")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["quota.failure"].exists)
        saveScreenshot(of: app, name: "T96-演示Cursor示例")
        app.buttons["quota.toolbarConnect"].tap()
        let mixed = NSPredicate { _, _ in MainActor.assumeIsolated {
            app.staticTexts.matching(identifier: "quota.accountIdentity").count == 2
        }}
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: mixed, object: nil)], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["quota.weekly.remaining"].exists, "连接入口仍添加Codex示例")
        let before = monthly.label
        app.buttons.matching(identifier: "quota.menu").element(boundBy: 0).tap()
        app.buttons["刷新额度"].tap()
        let changed = NSPredicate { _, _ in MainActor.assumeIsolated { monthly.label != before } }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: changed, object: nil)], timeout: 5), .completed,
                       "演示刷新为本地模拟更新")
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["quota.monthly.remaining"].waitForExistence(timeout: 5), "重开后保持")
        app.buttons["tab.settings"].tap()
        for _ in 0..<8 { if app.switches["settings.demo"].isHittable { break }; app.swipeUp() }
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["tab.quota"].tap()
        XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 5), "关闭清除全部演示账户")
        XCTAssertFalse(app.staticTexts["quota.monthly.remaining"].exists)
        saveScreenshot(of: app, name: "T96-关闭后清除")
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
        XCTAssertTrue(app.buttons["quota.details"].firstMatch.waitForExistence(timeout: 5))
        app.buttons.matching(identifier: "quota.details").element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 5))
        saveScreenshot(of: app, name: "新版-手动深色额度详情")
        app.buttons["detail.menu"].tap()
        XCTAssertTrue(app.buttons["刷新额度"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["删除账户"].exists)
        saveScreenshot(of: app, name: "新版-手动深色账户菜单")
    }

    @MainActor
    func testT100LucideDetailAndMenusLightDark() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        app.buttons["tab.settings"].tap()
        app.switches["settings.demo"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        let appearance = app.switches["settings.darkAppearance"]
        for pass in 0..<2 {
            let dark = appearance.value as? String == "1"
            let mode = dark ? "深" : "浅"
            app.buttons["tab.quota"].tap()
            if pass == 0 { app.buttons["quota.toolbarConnect"].tap() }
            XCTAssertTrue(app.buttons["quota.details"].firstMatch.waitForExistence(timeout: 5))
            app.buttons["quota.menu"].firstMatch.tap()
            XCTAssertTrue(app.buttons["刷新额度"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["删除账户"].exists)
            saveScreenshot(of: app, name: "T100-\(mode)-卡片菜单")
            app.buttons["刷新额度"].tap()
            app.buttons.matching(identifier: "quota.details").firstMatch.tap()
            XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["detail.close"].label, "关闭详情")
            XCTAssertTrue(app.buttons["detail.refresh"].isHittable)
            XCTAssertEqual(app.buttons["detail.menu"].label, "账户操作")
            saveScreenshot(of: app, name: "T100-\(mode)-详情")
            app.buttons["detail.menu"].tap()
            XCTAssertTrue(app.buttons["删除账户"].waitForExistence(timeout: 5))
            saveScreenshot(of: app, name: "T100-\(mode)-详情菜单")
            app.buttons["删除账户"].tap()
            XCTAssertTrue(app.alerts["删除账户？"].waitForExistence(timeout: 5))
            app.alerts["删除账户？"].buttons["取消"].tap()
            app.buttons["detail.close"].tap()
            XCTAssertFalse(app.buttons["detail.close"].waitForExistence(timeout: 2))
            app.buttons["tab.settings"].tap()
            app.buttons["settings.cardStyle"].tap()
            XCTAssertTrue(app.otherElements["style.selection"].firstMatch.waitForExistence(timeout: 5)
                          || app.navigationBars["卡片样式"].waitForExistence(timeout: 5))
            saveScreenshot(of: app, name: "T100-\(mode)-卡片样式选中")
            app.navigationBars["卡片样式"].buttons.firstMatch.tap()
            for _ in 0..<12 { if appearance.isHittable { break }; app.swipeDown() }
            appearance.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
    }

    @MainActor
    func testNavigationEmptyStateAndSupportEntries() {
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

            XCTAssertTrue(app.buttons["settings.help"].isEnabled)
            for identifier in ["settings.privacy", "settings.licenses"] {
                let action = app.buttons[identifier]
                XCTAssertTrue(action.exists, identifier)
                XCTAssertTrue(action.isEnabled, identifier)
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
    func testT99LucideIconsAlignedLightDarkAndMaximumText() {
        for maximumText in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--management-ui", UUID().uuidString]
            if maximumText {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launch()
            let mode = maximumText ? "最大字号" : "常规"
            for pass in 0..<2 {
                assertEmptyQuota(in: app)
                XCTAssertTrue(app.buttons["quota.widgetTutorial"].isHittable)
                saveScreenshot(of: app, name: "T99-\(mode)-第\(pass + 1)轮-额度")
                app.buttons["tab.settings"].tap()
                XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
                let darkSwitch = app.switches["settings.darkAppearance"]
                let dark = darkSwitch.value as? String == "1"
                // Switch rows expose their title frame: both start after the same icon slot.
                // Link rows report the whole row frame, so their icons are checked by screenshot.
                var starts: [CGFloat] = []
                for title in ["卡片样式", "深色模式", "重置提醒", "如何添加小组件", "帮助与说明", "隐私说明", "开源许可"] {
                    let text = app.staticTexts[title].firstMatch
                    for _ in 0..<12 {
                        if text.isHittable && text.frame.maxY < app.buttons["tab.settings"].frame.minY { break }
                        app.swipeUp()
                    }
                    XCTAssertTrue(text.isHittable, title)
                    if title == "深色模式" || title == "重置提醒" { starts.append(text.frame.minX) }
                    if title == "深色模式" || title == "开源许可" { saveScreenshot(of: app, name: "T99-\(mode)-\(dark ? "深" : "浅")-设置-\(title)") }
                }
                XCTAssertLessThan((starts.max() ?? 0) - (starts.min() ?? 0), 1.5, "\(starts)")
                XCTAssertGreaterThan(starts.min() ?? 0, maximumText ? 70 : 52)
                for _ in 0..<12 { if darkSwitch.isHittable { break }; app.swipeDown() }
                darkSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
                XCTAssertEqual(darkSwitch.value as? String, dark ? "0" : "1")
                app.buttons["tab.quota"].tap()
            }
            app.terminate()
        }
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
