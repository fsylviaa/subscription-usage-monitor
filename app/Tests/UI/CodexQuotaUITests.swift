import XCTest
import CryptoKit
import UIKit

final class CodexQuotaUITests: XCTestCase {

    private let stage3Styles = ["skala", "capsule", "ticks", "dials", "island", "blocks", "liquid", "ticket", "journal", "glass", "panels", "watermark", "rave", "liquidGlass", "neumorph", "clay"]

    private let stage3Names = ["彩色斜粒", "薄荷胶囊", "精密刻度", "金色仪表", "黑岛绿线", "紫色模块", "横向液体", "黑白票签", "暖黄手账", "冰蓝玻璃", "橙色双面板", "蓝条水印", "霓虹派对", "液态玻璃", "薄荷新拟态", "马卡龙粘土"]

    @MainActor
    private func chooseStage3Style(_ style: String, app: XCUIApplication) {
        Thread.sleep(forTimeInterval:0.6)
        app.buttons["tab.settings"].tap()
        let entry = app.buttons["settings.cardStyle"]
        if !entry.waitForExistence(timeout:2) { app.buttons["tab.settings"].tap() }
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let option = app.buttons["style.option.\(style)"]
        for _ in 0..<15 {
            if option.exists {
                let rect = option.frame
                print("T78 target \(style) rect=\(rect) nav=\(app.navigationBars.firstMatch.frame) bottom=\(app.buttons["tab.settings"].frame)")
                if option.isHittable && rect.minY > app.navigationBars.firstMatch.frame.maxY + 4 && rect.maxY < app.buttons["tab.settings"].frame.minY - 4 { break }
                if rect.minY < app.navigationBars.firstMatch.frame.maxY + 4 { app.swipeDown(velocity: .slow) }
                else { app.swipeUp(velocity: .slow) }
            } else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(option.isHittable, "样式入口应可操作：\(style)")
        option.tap()
        XCTAssertEqual(option.value as? String, "已选择")
        if ["skala", "blocks", "rave"].contains(style) { screenshot(app, "T78-选择页-\(style)") }
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["tab.quota"].tap()
    }

    /// D-76: a stored former original value (or nothing) shows 彩色斜粒, and the
    /// catalogue offers 16 styles (13 + 液态玻璃 D-83, 薄荷新拟态 D-84, 马卡龙粘土 D-85) without the original one.
    @MainActor
    func testD76OriginalPreferenceMigratesToSkala() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t26-isolated-ui", "success", "-card.style", "original"]
        app.launch()
        let cards = app.otherElements.matching(identifier: "quota.card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(cards.count, 2)
        XCTAssertTrue(cards.allElementsBoundByIndex.allSatisfy { $0.value as? String == "彩色斜粒" })
        screenshot(app, "D76-旧原样式迁移-额度页")
        app.buttons["tab.settings"].tap()
        let entry = app.buttons["settings.cardStyle"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertTrue(entry.label.contains("彩色斜粒"), entry.label)
        screenshot(app, "D76-旧原样式迁移-设置")
        entry.tap()
        XCTAssertTrue(app.buttons["style.option.skala"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["style.option.skala"].value as? String, "已选择")
        XCTAssertFalse(app.buttons["style.option.original"].exists)
        let rave = app.buttons["style.option.rave"]
        for _ in 0..<8 where !rave.isHittable { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(rave.isHittable)
        app.terminate()
    }

    private let d76Styles = ["skala", "capsule", "ticks", "dials", "island", "blocks", "liquid", "ticket", "journal", "glass", "panels", "watermark", "rave", "liquidGlass", "neumorph", "clay"]

    /// Real App, isolated two accounts (90%／70%): each style's quota page and
    /// detail card in both appearances, plus the D-74 one-screen check.
    @MainActor
    func testD76AccountAndDetailCapture() throws {
        guard ProcessInfo.processInfo.environment["D76_CAPTURE"] == "1" else { throw XCTSkip("按需截图") }
        let only = ProcessInfo.processInfo.environment["D76_STYLES"].map { $0.split(separator: ",").map(String.init) } ?? d76Styles
        for dark in [false, true] {
            for style in only {
                let app = XCUIApplication()
                let large = ProcessInfo.processInfo.environment["D76_LARGE"] == "1"
                app.launchArguments = ["--t26-isolated-ui", "success", "-card.style", style] + (dark ? ["--t26-dark"] : [])
                    + (large ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
                app.launch()
                let cards = app.otherElements.matching(identifier: "quota.card")
                XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15))
                Thread.sleep(forTimeInterval: 1.2)
                if large {
                    screenshot(app, "D76-最大字号-\(dark ? "dark" : "light")-\(style)")
                    app.swipeUp(velocity: .slow)
                    screenshot(app, "D76-最大字号-\(dark ? "dark" : "light")-\(style)-下滑")
                    app.terminate(); continue
                }
                XCTAssertEqual(cards.count, 2)
                // Both accounts fully on one screen, above the bottom help button.
                let limit = app.buttons["quota.widgetTutorial"].frame.minY
                let second = cards.element(boundBy: 1).frame
                XCTAssertLessThanOrEqual(second.maxY, limit + 1, "\(style) 第二张卡应完整在一屏内")
                print("D76 | \(style) | \(dark ? "dark" : "light") | card1=\(cards.element(boundBy: 0).frame.height) card2=\(second.height) bottom=\(second.maxY) limit=\(limit)")
                XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == '剩余'")).count, 0)
                screenshot(app, "D76-额度页-\(dark ? "dark" : "light")-\(style)")
                cards.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
                XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 8))
                Thread.sleep(forTimeInterval: 1.2)
                screenshot(app, "D76-详情-\(dark ? "dark" : "light")-\(style)")
                app.terminate()
            }
        }
    }

    @MainActor
    private static func openReduceMotion(_ settings: XCUIApplication) {
        let toggle = settings.switches["REDUCE_MOTION"]
        settings.terminate(); settings.launch()
        if toggle.waitForExistence(timeout: 3) { return }
        let entry = settings.buttons["com.apple.settings.accessibility"]
        for _ in 0..<8 { if entry.isHittable { break }; settings.swipeUp() }
        XCTAssertTrue(entry.isHittable); entry.tap()
        let motion = settings.staticTexts["动态效果"]
        for _ in 0..<5 { if motion.isHittable { break }; settings.swipeUp() }
        XCTAssertTrue(motion.waitForExistence(timeout: 5)); motion.tap()
    }

    /// Actual system Reduce Motion (Settings → 辅助功能 → 动态效果) on the formal
    /// quota page: living styles change between two frames only when motion is on.
    @MainActor
    func testD76ActualSystemReduceMotion() throws {
        guard ProcessInfo.processInfo.environment["D76_MOTION"] == "1" else { throw XCTSkip("显式启用：会临时切换系统减弱动态效果并恢复") }
        continueAfterFailure = false
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        let toggle = settings.switches["REDUCE_MOTION"]
        Self.openReduceMotion(settings)
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = try XCTUnwrap(toggle.value as? String)
        addTeardownBlock {
            await MainActor.run {
                Self.openReduceMotion(settings)
                XCTAssertTrue(toggle.waitForExistence(timeout: 5))
                if toggle.value as? String != original { toggle.coordinate(withNormalizedOffset: .init(dx: 0.9, dy: 0.5)).tap() }
                XCTAssertEqual(toggle.value as? String, original)
                print("D76 | system Reduce Motion restored original=\(original)")
            }
        }
        for reduced in [false, true] {
            Self.openReduceMotion(settings)
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            if toggle.value as? String != (reduced ? "1" : "0") { toggle.coordinate(withNormalizedOffset: .init(dx: 0.9, dy: 0.5)).tap() }
            XCTAssertEqual(toggle.value as? String, reduced ? "1" : "0")
            for style in ["capsule", "glass", "rave", "dials"] {
                let app = XCUIApplication()
                app.launchArguments = ["--t26-isolated-ui", "success", "-card.style", style]
                app.launch()
                let card = app.otherElements.matching(identifier: "quota.card").firstMatch
                XCTAssertTrue(card.waitForExistence(timeout: 15))
                if style == "dials" {
                    // The needle swings in from E each time the quota page appears.
                    Thread.sleep(forTimeInterval: 1.5)
                    app.buttons["tab.settings"].tap(); app.buttons["tab.quota"].tap()
                } else { Thread.sleep(forTimeInterval: 1) }
                let a = card.screenshot().pngRepresentation
                Thread.sleep(forTimeInterval: style == "dials" ? 1.6 : 0.7)
                let b = card.screenshot().pngRepresentation
                if reduced { XCTAssertEqual(a, b, "\(style) 减弱动态效果时应静止") }
                else { XCTAssertNotEqual(a, b, "\(style) 正常时应有动效") }
                print("D76 | motion | \(style) | systemReduced=\(reduced) | framesDiffer=\(a != b)")
                app.terminate()
            }
        }
    }

    /// Production preference path, run explicitly on a disposable simulator whose
    /// stored values were set to the former original style beforehand.
    @MainActor
    func testD76ProductionPreferenceMigration() throws {
        guard ProcessInfo.processInfo.environment["D76_MIGRATION"] == "1" else { throw XCTSkip("一次性模拟器上的正式偏好迁移检查") }
        let app = XCUIApplication()
        app.launch()
        app.buttons["tab.settings"].tap()
        let entry = app.buttons["settings.cardStyle"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertTrue(entry.label.contains("彩色斜粒"), entry.label)
        screenshot(app, "D76-正式路径-设置")
        app.terminate(); app.launch()
        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.buttons["settings.cardStyle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settings.cardStyle"].label.contains("彩色斜粒"))
        app.terminate()
    }

    @MainActor
    func testD73MediumPreviewSelectionStaysOnPage() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t26-isolated-ui", "success"]
        app.launch()
        XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout: 15))
        for dark in [false, true] {
            app.buttons["tab.settings"].tap()
            let toggle = app.switches["settings.darkAppearance"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            if (toggle.value as? String == "1") != dark { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
            app.buttons["settings.cardStyle"].tap()
            let original = app.buttons["style.option.skala"]
            XCTAssertTrue(original.waitForExistence(timeout: 5))
            original.tap()
            XCTAssertEqual(original.value as? String, "已选择")
            // Medium previews fill the row width with no visible style names.
            XCTAssertGreaterThan(original.frame.width, app.windows.firstMatch.frame.width - 40)
            // Visible text only; the shared widget view reports the style as an accessibility value.
            XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label IN %@", stage3Names)).count, 0, "选择页不显示样式名称")
            let island = app.buttons["style.option.capsule"]
            XCTAssertTrue(island.isHittable)
            island.tap()
            XCTAssertEqual(island.value as? String, "已选择")
            XCTAssertNotEqual(original.value as? String, "已选择")
            XCTAssertTrue(app.navigationBars["卡片样式"].exists, "点选后留在本页")
            screenshot(app, "D73-选择页-\(dark ? "dark" : "light")-top")
            app.swipeUp(velocity: .slow); app.swipeUp(velocity: .slow)
            screenshot(app, "D73-选择页-\(dark ? "dark" : "light")-middle")
            let watermark = app.buttons["style.option.rave"]
            for _ in 0..<6 where !watermark.isHittable { app.swipeUp(velocity: .slow) }
            screenshot(app, "D73-选择页-\(dark ? "dark" : "light")-bottom")
            for _ in 0..<6 where !original.isHittable { app.swipeDown(velocity: .fast) }
            original.tap()
            XCTAssertEqual(original.value as? String, "已选择")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.buttons["settings.cardStyle"].waitForExistence(timeout: 5))
        }
        let toggle = app.switches["settings.darkAppearance"]
        if toggle.value as? String == "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        // D-76: choose 霓虹派对, the settings row names it, and it survives a relaunch.
        app.buttons["tab.quota"].tap()
        chooseStage3Style("rave", app: app)
        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.buttons["settings.cardStyle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.cardStyle"].label.contains("霓虹派对"))
        app.terminate(); app.launch()
        XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(app.otherElements["quota.card"].firstMatch.value as? String, "霓虹派对")
        app.buttons["tab.settings"].tap()
        XCTAssertTrue(app.buttons["settings.cardStyle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.cardStyle"].label.contains("霓虹派对"))
        screenshot(app, "D76-设置行-霓虹派对")
        app.buttons["settings.cardStyle"].tap(); XCTAssertTrue(app.buttons["style.option.skala"].waitForExistence(timeout: 5))
        app.buttons["style.option.skala"].tap()
        app.terminate()
    }

    @MainActor
    func testT78FormalSelectionAndAccountHosts() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t26-isolated-ui", "success"]
        app.launch()
        XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout: 15))
        for dark in (ProcessInfo.processInfo.environment["T78_DARK_ONLY"] == "1" ? [true] : [false, true]) {
            app.buttons["tab.settings"].tap()
            let toggle = app.switches["settings.darkAppearance"]
            if (toggle.value as? String == "1") != dark { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
            XCTAssertEqual(toggle.value as? String, dark ? "1" : "0")
            screenshot(app, "T78-设置-\(dark ? "dark" : "light")")
            app.buttons["tab.quota"].tap()
            for style in stage3Styles {
                chooseStage3Style(style, app: app)
                let cards = app.otherElements.matching(identifier: "quota.card")
                XCTAssertEqual(cards.count, 2)
                XCTAssertTrue(cards.allElementsBoundByIndex.allSatisfy { $0.value as? String == stage3Names[stage3Styles.firstIndex(of: style)!] })
                // Identity is spoken only; it is never drawn on the card.
                XCTAssertEqual(app.staticTexts.matching(identifier: "quota.accountIdentity").count, 2)
                XCTAssertTrue(app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.allSatisfy { $0.frame.width <= 1 })
                XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == '剩余'")).count, 0)
                screenshot(app, "T78-正式账户-\(dark ? "dark" : "light")-\(style)")
            }
        }
        app.terminate(); app.launch()
        XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(app.otherElements["quota.card"].firstMatch.value as? String, "霓虹派对")
        app.buttons["quota.menu"].firstMatch.tap()
        XCTAssertTrue(app.buttons["刷新额度"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["删除账户"].exists)
        XCTAssertFalse(app.buttons["重新登录"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.1)).tap()
        chooseStage3Style("skala", app: app)
        XCTAssertEqual(app.otherElements["quota.card"].firstMatch.value as? String, "彩色斜粒")
        app.terminate()
    }

    @MainActor
    func testT78NewCardExistingTouches() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t26-isolated-ui", "success", "-card.style", "capsule"]
        app.launch()
        let cards = app.otherElements.matching(identifier: "quota.card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(cards.firstMatch.value as? String, "薄荷胶囊")
        cards.firstMatch.buttons["quota.menu"].tap()
        app.buttons["刷新额度"].tap()
        let value = cards.firstMatch.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "55%"))
        XCTAssertTrue(value.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["detail.close"].exists, "菜单刷新不得误开详情")
        let first = cards.element(boundBy: 0), second = cards.element(boundBy: 1)
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.35)).press(forDuration: 0.7,
            thenDragTo: first.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.2)), withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertFalse(app.buttons["detail.close"].exists, "拖动不得误开详情")
        cards.firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.identity"].label, "batch-2@example.invalid")
        app.buttons["detail.close"].tap()
        app.pullAllQuota()
        XCTAssertTrue(cards.firstMatch.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "55%")).firstMatch.waitForExistence(timeout: 10))
        cards.firstMatch.buttons["quota.menu"].tap(); app.buttons["删除账户"].tap()
        XCTAssertTrue(app.alerts["删除账户？"].waitForExistence(timeout: 5))
        app.alerts.buttons["取消"].tap()
        XCTAssertEqual(cards.count, 2)
        screenshot(app, "T78-新卡菜单下拉拖动删除取消")
        app.terminate()
    }

    @MainActor
    func testT78FormalSelectionLargestType() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--t26-isolated-ui", "long", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 15))
        chooseStage3Style("watermark", app: app)
        XCTAssertEqual(app.otherElements["quota.card"].firstMatch.value as? String, "蓝条水印")
        screenshot(app, "T78-正式账户-最大字号")
        let finalWindow = app.staticTexts.matching(NSPredicate(format: "identifier == 'quota.fiveHours.remaining' AND label CONTAINS '70%'")).firstMatch
        for _ in 0..<8 {
            if finalWindow.exists && finalWindow.isHittable && finalWindow.frame.maxY < app.buttons["quota.widgetTutorial"].frame.minY - 4 && finalWindow.frame.minY > app.staticTexts["quota.title"].frame.maxY { break }
            let list = app.collectionViews["quota.list"]
            let bottom = min(list.frame.maxY, app.buttons["quota.widgetTutorial"].frame.minY) - 20
            let top = max(list.frame.minY, app.staticTexts["quota.title"].frame.maxY) + 30
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.midX, dy: bottom))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: list.frame.midX, dy: top))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        XCTAssertTrue(finalWindow.isHittable, "最大字号仍可滚到末户5小时读数")
        print("T78 actual scroll list=\(app.collectionViews["quota.list"].frame) lastCell=\(app.collectionViews["quota.list"].cells.allElementsBoundByIndex.last?.frame ?? .zero) window=\(finalWindow.frame) tutorial=\(app.buttons["quota.widgetTutorial"].frame)")
        XCTAssertLessThan(finalWindow.frame.maxY, app.buttons["quota.widgetTutorial"].frame.minY - 4, "全部末户窗口须实际进入列表可见范围")
        XCTAssertTrue(app.buttons["quota.toolbarConnect"].isHittable, "滚动后固定顶部入口仍可用")
        screenshot(app, "T78-正式账户-最大字号-底部读数")
        app.buttons["tab.settings"].tap(); app.buttons["settings.cardStyle"].tap()
        screenshot(app, "T78-选择页-最大字号")
        app.terminate()
    }

    @MainActor
    func testT79FormalDetailHostsAllStyles() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        for dark in [false, true] {
            for style in (ProcessInfo.processInfo.environment["T79_LAYOUT_REGRESSION"] == "1" ? ["skala", "dials", "liquid", "watermark"] : stage3Styles) {
                app.launchArguments = ["--t26-isolated-ui", "success", "-card.style", style] + (dark ? ["--t26-dark"] : [])
                app.launch()
                let card = app.otherElements["quota.card"].firstMatch
                XCTAssertTrue(card.waitForExistence(timeout: 15))
                card.tap()
                XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 5))
                XCTAssertEqual(app.staticTexts["detail.identity"].label, "batch-1@example.invalid")
                let five = app.descendants(matching: .any)["detail.style.fiveHours.\(style)"], week = app.descendants(matching: .any)["detail.style.weekly.\(style)"]
                XCTAssertTrue(five.exists); XCTAssertTrue(week.exists)
                XCTAssertLessThan(five.frame.minY, week.frame.minY)
                XCTAssertEqual(app.staticTexts["detail.weekly.remaining"].label, "剩余 90%")
                XCTAssertLessThan(app.staticTexts["detail.fiveHours.remaining"].frame.minY, app.staticTexts["detail.weekly.remaining"].frame.minY)
                XCTAssertTrue(app.staticTexts["quota.updatedAt"].exists)
                XCTAssertTrue(app.buttons["detail.refresh"].isEnabled)
                screenshot(app, "T79-正式详情-\(dark ? "dark" : "light")-\(style)")
                app.buttons["detail.close"].tap(); app.terminate()
            }
        }
    }

    @MainActor
    func testT79SecondAccountFailureAndLargestType() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t26-isolated-ui", "partial", "-card.style", "watermark"]
        app.launch()
        XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout: 15))
        app.otherElements.matching(identifier: "quota.card").element(boundBy: 1).tap()
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.identity"].label, "batch-2@example.invalid")
        let originalTime = app.staticTexts["quota.updatedAt"].label
        app.buttons["detail.refresh"].tap()
        XCTAssertTrue(app.staticTexts["detail.failure"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.updatedAt"].label, originalTime)
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "剩余 70%")).firstMatch.exists)
        app.buttons["detail.menu"].tap(); XCTAssertTrue(app.buttons["删除账户"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["重新登录"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.3)).tap()
        screenshot(app, "T79-第二户失败旧值原成功时间")
        app.buttons["detail.close"].tap(); app.terminate()
        for scenario in ["noFive", "states", "times"] {
            app.launchArguments = ["--t23-card-fixture", scenario, "dark", "-card.style", "watermark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch()
            let card = app.otherElements["quota.card"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 15)); card.tap()
            XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 5))
            if scenario != "times" { XCTAssertFalse(app.descendants(matching: .any)["detail.style.fiveHours.watermark"].exists) }
            let scroll = app.scrollViews.firstMatch
            for _ in 0..<5 { scroll.swipeUp(velocity: .slow) }
            XCTAssertTrue(app.staticTexts["detail.identity"].isHittable)
            XCTAssertTrue(app.buttons["detail.close"].isHittable)
            screenshot(app, "T79-正式详情-大字号-\(scenario)")
            app.buttons["detail.close"].tap(); app.terminate()
        }
    }

    @MainActor
    func testT79FormalDetailMissingUnlimitedLongAndGoldScroll() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        for scenario in ["gold", "unlimited", "long"] {
            let style = scenario == "gold" ? "dials" : "watermark"
            app.launchArguments = scenario == "gold"
                ? ["--t26-isolated-ui", "success", "--t26-dark", "-card.style", style]
                : ["--t23-card-fixture", scenario, "dark", "-card.style", style, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launch(); XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout: 15))
            app.otherElements["quota.card"].firstMatch.tap()
            XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 5))
            screenshot(app, "T79-补充-\(scenario)-额度")
            if scenario == "unlimited" {
                XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "不限量")).firstMatch.exists)
                XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "%")).firstMatch.exists)
            }
            let scroll = app.scrollViews.firstMatch
            if scenario == "gold" {
                let week = app.descendants(matching: .any)["detail.style.weekly.dials"]
                scroll.swipeUp(velocity: .slow)
                XCTAssertLessThan(week.frame.maxY, app.frame.height - 35)
                screenshot(app, "T79-补充-金色仪表第二窗口完整")
            }
            for _ in 0..<5 { scroll.swipeUp(velocity: .slow) }
            XCTAssertTrue(app.staticTexts["detail.identity"].isHittable)
            XCTAssertFalse(app.staticTexts["detail.plan"].exists, "D-77：详情不显示套餐行")
            XCTAssertFalse(app.staticTexts["套餐"].exists)
            screenshot(app, "T79-补充-\(scenario)-详情字段")
            XCTAssertTrue(app.buttons["detail.close"].isHittable)
            app.buttons["detail.close"].tap(); app.terminate()
        }
    }

    @MainActor
    func testT79LongDetailHeaderVisibility() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t23-card-fixture", "long", "dark", "-card.style", "watermark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout: 15))
        app.otherElements["quota.card"].firstMatch.tap()
        let close = app.buttons["detail.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let first = app.descendants(matching: .any)["detail.style.fiveHours.watermark"]
        print("T79 long header close=\(close.frame) quota=\(first.frame) scroll=\(app.scrollViews.firstMatch.frame)")
        XCTAssertGreaterThanOrEqual(first.frame.minY, close.frame.maxY)
        XCTAssertLessThanOrEqual(app.scrollViews.firstMatch.frame.maxX, app.frame.width)
        Thread.sleep(forTimeInterval: 1)
        screenshot(app, "T79-长内容-顶栏复核-进入")
        let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screen.name = "T79-长内容-物理屏幕进入"; screen.lifetime = .keepAlways; add(screen)
        let button = XCTAttachment(screenshot: close.screenshot())
        button.name = "T79-关闭按钮实际像素"; button.lifetime = .keepAlways; add(button)
        app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 1)
        screenshot(app, "T79-长内容-顶栏复核-滚动")
        let after = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        after.name = "T79-长内容-物理屏幕滚动"; after.lifetime = .keepAlways; add(after)
        XCTAssertTrue(close.isHittable)
        close.tap(); app.terminate()
    }

    @MainActor
    func testT80AllSmallStylesOnExistingDesktop() throws {
        guard ProcessInfo.processInfo.environment["T80_DESKTOP"] == "1" else { throw XCTSkip("显式启用本人手机现有组件") }
        continueAfterFailure = false
        let app = XCUIApplication(), board = XCUIApplication(bundleIdentifier: "com.apple.springboard"), session = UUID().uuidString
        addTeardownBlock {
            app.terminate(); app.launchArguments = ["--t78-desktop-fixture", "cleanup", session, "light"]
            app.launch(); XCTAssertTrue(app.staticTexts["quota.empty"].waitForExistence(timeout: 15)); app.terminate()
        }
        app.launchArguments = ["--t78-desktop-fixture", "normal", session, "light"]
        app.launch(); XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout: 15))
        for dark in [false, true] {
            app.buttons["tab.settings"].tap()
            let toggle = app.switches["settings.darkAppearance"]
            if (toggle.value as? String == "1") != dark { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
            XCTAssertEqual(toggle.value as? String, dark ? "1" : "0")
            app.buttons["tab.quota"].tap()
            for style in (ProcessInfo.processInfo.environment["T80_HOST_REGRESSION"] == "1" ? ["skala", "dials", "liquid", "watermark"] : stage3Styles) {
                let index = stage3Styles.firstIndex(of:style)!
                chooseStage3Style(style, app: app)
                print("T80 request \(style) \(dark ? "dark" : "light") | \(Date().ISO8601Format())")
                XCUIDevice.shared.press(.home); showT35Desktop(board)
                let ready = NSPredicate { _, _ in
                    if style == "original" {
                        return board.descendants(matching: .any).matching(NSPredicate(format: "value == %@", self.stage3Names[index])).count >= 3
                    }
                    return board.descendants(matching: .any).matching(identifier: "native.\(style).smallWidget").count >= 2
                }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 60), .completed)
                let widgets = board.icons.matching(NSPredicate(format: "(label == %@ OR label == %@) AND value == %@", "订阅用量", "TokenLeft", "小组件")).allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
                XCTAssertEqual(widgets.filter { $0.frame.width < 230 }.count, 2)
                for (n,w) in widgets.enumerated() where w.frame.width < 230 {
                    attachT65Crop(board, rect: w.frame, name: "T80-桌面-\(dark ? "dark" : "light")-\(style)-实例\(n)")
                }
                print("T80 observed \(style) \(dark ? "dark" : "light") | \(Date().ISO8601Format())")
                if style == "liquid", let first = widgets.first(where: { $0.frame.width < 230 }) {
                    let before = first.screenshot().image.pngData()
                    Thread.sleep(forTimeInterval:3)
                    let after = first.screenshot().image.pngData()
                    XCTAssertEqual(before, after, "实际桌面液体和水印应静止")
                    attachT65Crop(board, rect:first.frame, name:"T80-实际静态复照-\(dark ? "dark" : "light")")
                    print("T80 actual desktop static pixels identical \(dark ? "dark" : "light")")
                }
                if style == "watermark" {
                    for w in widgets where w.frame.width < 230 {
                        let texts = board.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "%")).allElementsBoundByIndex.filter { w.frame.contains(CGPoint(x:$0.frame.midX,y:$0.frame.midY)) }.map(\.label)
                        print("T80 instance before click | \(texts)")
                        w.tap()
                        XCTAssertTrue(app.staticTexts["detail.identity"].waitForExistence(timeout: 10))
                        let identity = app.staticTexts["detail.identity"].label
                        print("T80 instance detail | \(identity)")
                        XCTAssertTrue(identity.contains("stage3-"))
                        screenshot(app, "T80-点击对应详情-\(dark ? "dark" : "light")-\(identity.contains("stage3-1") ? "default" : "pinned")")
                        app.buttons["detail.close"].tap(); XCUIDevice.shared.press(.home)
                    }
                }
                app.activate()
            }
        }
        app.terminate(); app.launch()
        XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout:15))
        XCTAssertEqual(app.otherElements["quota.card"].firstMatch.value as? String, "蓝条水印")
    }

    @MainActor
    func testT80SmallDesktopControlledInputs() throws {
        guard ProcessInfo.processInfo.environment["T80_DESKTOP"] == "1" else { throw XCTSkip("显式启用现有组件受控场景") }
        continueAfterFailure = false
        let app = XCUIApplication(), board = XCUIApplication(bundleIdentifier: "com.apple.springboard"), session = UUID().uuidString
        addTeardownBlock {
            app.terminate(); app.launchArguments = ["--t78-desktop-fixture", "cleanup", session, "light"]
            app.launch(); XCTAssertTrue(app.staticTexts["quota.empty"].waitForExistence(timeout: 15)); app.terminate()
        }
        for scenario in (ProcessInfo.processInfo.environment["T80_EXTRA_REMAINING"] == "1" ? ["unknown", "unlimited", "failure", "long"] : ["endpoints", "weekly", "unknown", "unlimited", "failure", "long"]) {
            app.terminate(); app.launchArguments = ["--t78-desktop-fixture", scenario, session, "light"]
            app.launch(); XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout: 15))
            chooseStage3Style("watermark", app: app)
            print("T80 controlled request \(scenario) | \(Date().ISO8601Format())")
            XCUIDevice.shared.press(.home); showT35Desktop(board)
            let expected = ["endpoints":"每周，剩余0%", "weekly":"每周，剩余70%", "unknown":"每周，剩余未知", "unlimited":"每周，剩余不限量", "failure":"每周，剩余70%", "long":"每周，剩余70%"][scenario]!
            XCTAssertTrue(board.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch.waitForExistence(timeout: 60))
            let widgets = board.icons.matching(NSPredicate(format: "(label == %@ OR label == %@) AND value == %@", "订阅用量", "TokenLeft", "小组件")).allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 && $0.frame.width < 230 }
            XCTAssertEqual(widgets.count, 2)
            for (n,w) in widgets.enumerated() { attachT65Crop(board, rect:w.frame, name:"T80-桌面受控-\(scenario)-实例\(n)") }
            print("T80 controlled observed \(scenario) | \(Date().ISO8601Format())")
        }
    }

    @MainActor
    func testT80TemporaryPinnedInstanceSurvivesStyleAndRestart() throws {
        guard ProcessInfo.processInfo.environment["T80_DESKTOP"] == "1" else { throw XCTSkip("仅开发者临时桌面实例") }
        continueAfterFailure = false
        let app = XCUIApplication(), board = XCUIApplication(bundleIdentifier:"com.apple.springboard"), session = UUID().uuidString
        var created = false
        func visibleWidgets() -> [XCUIElement] {
            board.icons.matching(NSPredicate(format:"label == %@ OR label == %@", "订阅用量", "TokenLeft")).allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
        }
        addTeardownBlock {
            XCUIDevice.shared.press(.home)
            if created {
                // The dedicated last blank page contains only the added widget.
                for _ in 0..<8 {
                    let newLabel = board.icons.matching(NSPredicate(format:"label == %@", "TokenLeft")).allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
                    if newLabel.count == 1 && visibleWidgets().count == 1 { break }
                    board.swipeLeft()
                }
                let own = visibleWidgets()
                XCTAssertEqual(own.count,1,"只移除本轮空白页的临时实例，不能动原组件")
                if own.count == 1 {
                    own[0].press(forDuration:0.7)
                    let remove = board.buttons["移除小组件"]
                    XCTAssertTrue(remove.waitForExistence(timeout:5)); remove.tap()
                    if board.alerts.buttons["移除"].waitForExistence(timeout:5) { board.alerts.buttons["移除"].tap() }
                    XCTAssertTrue(visibleWidgets().isEmpty || visibleWidgets().count == 3,"必须实际移除临时实例；空白页移除后可回到原三实例页")
                }
            }
            XCUIDevice.shared.press(.home)
            if created {
                app.terminate(); app.launch()
                XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout:15))
            }
            app.terminate(); app.launchArguments = ["--t78-desktop-fixture", "cleanup", session, "light"]
            app.launch(); app.terminate()
        }
        app.launchArguments = ["--t78-desktop-fixture", "normal", session, "light"]
        app.launch(); XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout:15))
        chooseStage3Style("watermark",app:app)
        XCUIDevice.shared.press(.home); showT35Desktop(board)
        let fullPage = NSPredicate { _, _ in visibleWidgets().count == 3 }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:fullPage,object:nil)],timeout:15),.completed)
        let old = visibleWidgets(); XCTAssertEqual(old.count,3)
        board.coordinate(withNormalizedOffset:CGVector(dx:0.985,dy:0.74)).press(forDuration:1.2)
        if !board.buttons["完成"].waitForExistence(timeout:3) {
            old[0].press(forDuration:0.7)
            XCTAssertTrue(board.buttons["编辑主屏幕"].waitForExistence(timeout:5)); board.buttons["编辑主屏幕"].tap()
        }
        // iOS exposes an extra final empty page while editing. No existing page
        // or icon is moved; addition/removal is confined to that empty page.
        for _ in 0..<3 {
            let onGrid = board.icons.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.minY < 700 }
            if onGrid.isEmpty { break }
            board.swipeLeft()
        }
        XCTAssertTrue(board.icons.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.minY < 700 }.isEmpty,"必须先到独立空白页")
        board.buttons["编辑"].tap(); board.buttons["添加小组件"].tap()
        let search = board.searchFields["搜索小组件"]; XCTAssertTrue(search.waitForExistence(timeout:5));search.tap();search.typeText("Token")
        let result = board.cells["TokenLeft"];XCTAssertTrue(result.waitForExistence(timeout:5));result.tap()
        print("T80 temporary gallery selected | \(board.debugDescription)")
        let add = board.buttons.matching(NSPredicate(format:"label CONTAINS %@", "添加小组件")).firstMatch;XCTAssertTrue(add.waitForExistence(timeout:5));add.tap();created = true
        if board.buttons["完成"].waitForExistence(timeout:5) { board.buttons["完成"].tap() }
        XCTAssertEqual(visibleWidgets().count,1)
        visibleWidgets()[0].press(forDuration:0.7)
        board.buttons["编辑小组件"].tap()
        print("T80 temporary account field | \(board.debugDescription)")
        let field = board.buttons.matching(NSPredicate(format:"label CONTAINS %@", "显示账户")).firstMatch
        if field.exists { field.tap() }
        else { board.descendants(matching:.any).matching(NSPredicate(format:"label == %@", "跟随列表首个账户")).firstMatch.tap() }
        let second = board.descendants(matching:.any).matching(NSPredicate(format:"label BEGINSWITH %@", "stage3-2@example.invalid")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout:5));second.tap()
        board.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.9)).tap()
        for style in ["watermark", "skala"] {
            app.activate(); chooseStage3Style(style,app:app)
            print("T80 pinned request \(style) | \(Date().ISO8601Format())")
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(board.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "30%")).firstMatch.waitForExistence(timeout:60))
            let own = try XCTUnwrap(visibleWidgets().first)
            attachT65Crop(board,rect:own.frame,name:"T80-临时指定户-\(style)")
            own.tap(); XCTAssertTrue(app.staticTexts["detail.identity"].waitForExistence(timeout:10))
            XCTAssertEqual(app.staticTexts["detail.identity"].label,"stage3-2@example.invalid")
            app.buttons["detail.close"].tap();app.terminate();app.launch()
            XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout:15))
            XCTAssertEqual(app.otherElements["quota.card"].firstMatch.value as? String,stage3Names[stage3Styles.firstIndex(of:style)!])
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(board.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "30%")).firstMatch.waitForExistence(timeout:60))
            // Previous page: unchanged original two defaults and medium.
            board.swipeRight();XCTAssertEqual(visibleWidgets().count,3)
            XCTAssertTrue(board.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "70%")).firstMatch.waitForExistence(timeout:30))
            let original = try XCTUnwrap(visibleWidgets().first { $0.frame.width < 230 })
            original.tap();XCTAssertTrue(app.staticTexts["detail.identity"].waitForExistence(timeout:10))
            XCTAssertEqual(app.staticTexts["detail.identity"].label,"stage3-1@example.invalid")
            app.buttons["detail.close"].tap();XCUIDevice.shared.press(.home);board.swipeLeft()
            print("T80 default and pinned observed \(style) | \(Date().ISO8601Format())")
        }
    }

    /// Disposable simulator only: adds one small and one medium widget, then
    /// photographs the actual home-screen widgets for every style and appearance.
    @MainActor
    func testD76SimulatorDesktopBothSizes() throws {
        guard ProcessInfo.processInfo.environment["D76_DESKTOP"] == "1" else { throw XCTSkip("仅一次性模拟器：添加两尺寸组件并逐款拍实际桌面") }
        continueAfterFailure = false
        let app = XCUIApplication(), board = XCUIApplication(bundleIdentifier: "com.apple.springboard"), session = UUID().uuidString
        addTeardownBlock {
            app.terminate(); app.launchArguments = ["--t78-desktop-fixture", "cleanup", session, "light"]
            app.launch(); XCTAssertTrue(app.staticTexts["quota.empty"].waitForExistence(timeout: 15)); app.terminate()
        }
        app.launchArguments = ["--t78-desktop-fixture", "normal", session, "light"]
        app.launch(); XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout: 15))
        let ours = board.icons.matching(NSPredicate(format: "label == %@ OR label == %@", "订阅用量", "TokenLeft"))
        let widgetIcons = board.icons.matching(NSPredicate(format: "(label == %@ OR label == %@) AND value == %@", "订阅用量", "TokenLeft", "小组件"))
        func widgetCount() -> Int { widgetIcons.count }
        func addWidget(medium: Bool) throws {
            XCUIDevice.shared.press(.home)
            let before = widgetCount()
            board.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).press(forDuration: 1.5)
            XCTAssertTrue(board.buttons["编辑"].waitForExistence(timeout: 8))
            board.buttons["编辑"].tap()
            XCTAssertTrue(board.buttons["添加小组件"].waitForExistence(timeout: 5)); board.buttons["添加小组件"].tap()
            let search = board.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("Token")
            let result = board.collectionViews["add-sheet-collection-view"].cells.firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 10)); result.tap()
            let add = board.buttons.matching(NSPredicate(format: "label CONTAINS %@", "添加小组件")).firstMatch
            XCTAssertTrue(add.waitForExistence(timeout: 8))
            if medium {
                board.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.56))
                    .press(forDuration: 0.1, thenDragTo: board.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.56)))
                Thread.sleep(forTimeInterval: 1)
            }
            add.tap()
            if board.buttons["完成"].waitForExistence(timeout: 8) { board.buttons["完成"].tap() }
            Thread.sleep(forTimeInterval: 3)
            print("D76 desktop | added \(medium ? "medium" : "small") | before=\(before)")
        }
        XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 1.5)
        // Explicit one-time setup on a freshly erased simulator; later runs reuse the two instances.
        if ProcessInfo.processInfo.environment["D76_DESKTOP_SETUP"] == "1" {
            try addWidget(medium: false); try addWidget(medium: true)
        }
        app.activate()
        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 10))
        for dark in [false, true] {
            app.buttons["tab.settings"].tap()
            let toggle = app.switches["settings.darkAppearance"]
            if !toggle.waitForExistence(timeout: 5) { app.buttons["tab.settings"].tap() }
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            if (toggle.value as? String == "1") != dark { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
            app.buttons["tab.quota"].tap()
            for style in stage3Styles {
                chooseStage3Style(style, app: app)
                let requested = Date()
                XCUIDevice.shared.press(.home)
                for _ in 0..<3 { board.swipeRight() }
                var seen = Set<String>()
                for _ in 0..<4 where seen.count < 2 {
                    let visible = ours.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
                    for w in visible {
                        let size = w.frame.width > 230 ? "mediumWidget" : "smallWidget"
                        let ready = NSPredicate { _, _ in board.descendants(matching: .any).matching(identifier: "native.\(style).\(size)").count >= 1 }
                        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 60), .completed, "\(style) \(size)")
                        print("D76 desktop | \(style) | \(dark ? "dark" : "light") | \(size) appeared after \(String(format: "%.1f", Date().timeIntervalSince(requested)))s")
                        attachT65Crop(board, rect: w.frame, name: "D76-实际桌面-\(dark ? "dark" : "light")-\(style)-\(size == "mediumWidget" ? "中号" : "小号")")
                        seen.insert(size)
                    }
                    XCTAssertEqual(board.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "@", "剩余 ")).count, 0, "组件无邮箱、无“剩余”可见文字")
                    if seen.count < 2 { board.swipeLeft() }
                }
                XCTAssertEqual(seen.count, 2, "\(style) 两尺寸都应实际出现")
                app.activate()
            }
        }
        XCUIDevice.shared.press(.home)
        for _ in 0..<3 { board.swipeRight() }
        for _ in 0..<4 where !ours.allElementsBoundByIndex.contains(where: { $0.isHittable && $0.frame.width > 230 }) { board.swipeLeft() }
        let medium = try XCTUnwrap(ours.allElementsBoundByIndex.first { $0.isHittable && $0.frame.width > 230 })
        let before = medium.screenshot().pngRepresentation
        Thread.sleep(forTimeInterval: 3)
        XCTAssertEqual(before, medium.screenshot().pngRepresentation, "实际桌面组件静止")
        medium.tap()
        XCTAssertTrue(app.staticTexts["detail.identity"].waitForExistence(timeout: 10))
        print("D76 desktop | medium tap opens detail | \(app.staticTexts["detail.identity"].label)")
    }

    @MainActor
    func testT81AllMediumStylesOnExistingDesktop() throws {
        guard ProcessInfo.processInfo.environment["T81_DESKTOP"] == "1" else { throw XCTSkip("显式启用本人手机现有组件") }
        continueAfterFailure = false
        let app = XCUIApplication(), board = XCUIApplication(bundleIdentifier: "com.apple.springboard"), session = UUID().uuidString
        addTeardownBlock {
            app.terminate(); app.launchArguments = ["--t78-desktop-fixture", "cleanup", session, "light"]
            app.launch(); XCTAssertTrue(app.staticTexts["quota.empty"].waitForExistence(timeout: 15)); app.terminate()
        }
        app.launchArguments = ["--t78-desktop-fixture", "normal", session, "light"]
        app.launch(); XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout: 15))
        for dark in [false, true] {
            app.buttons["tab.settings"].tap()
            let toggle = app.switches["settings.darkAppearance"]
            if (toggle.value as? String == "1") != dark { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
            XCTAssertEqual(toggle.value as? String, dark ? "1" : "0")
            app.buttons["tab.quota"].tap()
            for style in (ProcessInfo.processInfo.environment["T81_HOST_REGRESSION"] == "1" ? ["skala", "dials", "liquid", "watermark"] : stage3Styles) {
                let index = stage3Styles.firstIndex(of:style)!
                chooseStage3Style(style, app: app)
                print("T81 request \(style) \(dark ? "dark" : "light") | \(Date().ISO8601Format())")
                XCUIDevice.shared.press(.home); showT35Desktop(board)
                let ready = NSPredicate { _, _ in
                    if style == "original" {
                        return board.descendants(matching: .any).matching(NSPredicate(format: "value == %@", self.stage3Names[index])).count >= 3
                    }
                    return board.descendants(matching: .any).matching(identifier: "native.\(style).mediumWidget").count >= 1
                }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 60), .completed)
                let widgets = board.icons.matching(NSPredicate(format: "label == %@ OR label == %@", "订阅用量", "TokenLeft")).allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
                XCTAssertEqual(widgets.filter { $0.frame.width > 230 }.count, 1)
                for (n,w) in widgets.enumerated() where w.frame.width > 230 {
                    attachT65Crop(board, rect: w.frame, name: "T81-桌面-\(dark ? "dark" : "light")-\(style)-实例\(n)")
                }
                print("T81 observed \(style) \(dark ? "dark" : "light") | \(Date().ISO8601Format())")
                if ["skala", "watermark"].contains(style) {
                    let small = widgets.filter { $0.frame.width < 230 }
                    XCTAssertEqual(small.count,2)
                    if style != "original" { XCTAssertGreaterThanOrEqual(board.descendants(matching:.any).matching(identifier:"native.\(style).smallWidget").count,2) }
                    for (n,w) in small.enumerated() { attachT65Crop(board,rect:w.frame,name:"T81-共享变更小号回归-\(dark ? "dark" : "light")-\(style)-\(n)") }
                }
                if style == "liquid", let first = widgets.first(where: { $0.frame.width > 230 }) {
                    let before = first.screenshot().image.pngData()
                    Thread.sleep(forTimeInterval:3)
                    let after = first.screenshot().image.pngData()
                    XCTAssertEqual(before, after, "实际桌面液体和水印应静止")
                    attachT65Crop(board, rect:first.frame, name:"T81-实际静态复照-\(dark ? "dark" : "light")")
                    print("T81 actual desktop static pixels identical \(dark ? "dark" : "light")")
                }
                if style == "watermark" {
                    for w in widgets where w.frame.width > 230 {
                        let texts = board.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "%")).allElementsBoundByIndex.filter { w.frame.contains(CGPoint(x:$0.frame.midX,y:$0.frame.midY)) }.map(\.label)
                        print("T81 instance before click | \(texts)")
                        w.tap()
                        XCTAssertTrue(app.staticTexts["detail.identity"].waitForExistence(timeout: 10))
                        let identity = app.staticTexts["detail.identity"].label
                        print("T81 instance detail | \(identity)")
                        XCTAssertTrue(identity.contains("stage3-"))
                        screenshot(app, "T81-点击对应详情-\(dark ? "dark" : "light")-\(identity.contains("stage3-1") ? "default" : "pinned")")
                        app.buttons["detail.close"].tap(); XCUIDevice.shared.press(.home)
                    }
                }
                app.activate()
            }
        }
        app.terminate(); app.launch()
        XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout:15))
        XCTAssertEqual(app.otherElements["quota.card"].firstMatch.value as? String, "蓝条水印")
    }

    @MainActor
    func testT81MediumDesktopControlledInputs() throws {
        guard ProcessInfo.processInfo.environment["T81_DESKTOP"] == "1" else { throw XCTSkip("显式启用现有组件受控场景") }
        continueAfterFailure = false
        let app = XCUIApplication(), board = XCUIApplication(bundleIdentifier: "com.apple.springboard"), session = UUID().uuidString
        addTeardownBlock {
            app.terminate(); app.launchArguments = ["--t78-desktop-fixture", "cleanup", session, "light"]
            app.launch(); XCTAssertTrue(app.staticTexts["quota.empty"].waitForExistence(timeout: 15)); app.terminate()
        }
        for scenario in (ProcessInfo.processInfo.environment["T81_LONG_ONLY"] == "1" ? ["long"] : (ProcessInfo.processInfo.environment["T81_EXTRA_REMAINING"] == "1" ? ["unknown", "unlimited", "failure", "long"] : ["endpoints", "weekly", "unknown", "unlimited", "failure", "long"])) {
            app.terminate(); app.launchArguments = ["--t78-desktop-fixture", scenario, session, "light"]
            app.launch(); XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout: 15))
            chooseStage3Style("watermark", app: app)
            print("T81 controlled request \(scenario) | \(Date().ISO8601Format())")
            XCUIDevice.shared.press(.home); showT35Desktop(board)
            let expected = ["endpoints":"每周，剩余0%", "weekly":"每周，剩余70%", "unknown":"每周，剩余未知", "unlimited":"每周，剩余不限量", "failure":"每周，剩余70%", "long":"每周，剩余70%"][scenario]!
            XCTAssertTrue(board.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch.waitForExistence(timeout: 60))
            let widgets = board.icons.matching(NSPredicate(format: "label == %@ OR label == %@", "订阅用量", "TokenLeft")).allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 && $0.frame.width > 230 }
            XCTAssertEqual(widgets.count, 1)
            for (n,w) in widgets.enumerated() { attachT65Crop(board, rect:w.frame, name:"T81-桌面受控-\(scenario)-实例\(n)") }
            if scenario == "long" {
                XCTAssertTrue(board.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","Enterprise")).firstMatch.exists,"必须实际接入长套餐，不以场景名冒充")
                let all=board.icons.matching(NSPredicate(format:"label == %@ OR label == %@","订阅用量","TokenLeft")).allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
                for (n,w) in all.enumerated() where w.frame.width < 230 { attachT65Crop(board,rect:w.frame,name:"T81-补T80实际长套餐小号-\(n)") }
            }
            print("T81 controlled observed \(scenario) | \(Date().ISO8601Format())")
        }
    }

    @MainActor
    func testT81TemporaryMediumPinnedInstanceSurvivesStyleAndRestart() throws {
        guard ProcessInfo.processInfo.environment["T81_DESKTOP"] == "1" else { throw XCTSkip("仅开发者临时桌面实例") }
        continueAfterFailure = false
        let app = XCUIApplication(), board = XCUIApplication(bundleIdentifier:"com.apple.springboard"), session = UUID().uuidString
        var created = false
        func visibleWidgets() -> [XCUIElement] {
            board.icons.matching(NSPredicate(format:"label == %@ OR label == %@", "订阅用量", "TokenLeft")).allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
        }
        addTeardownBlock {
            XCUIDevice.shared.press(.home)
            if created {
                // The dedicated last blank page contains only the added widget.
                for _ in 0..<8 {
                    let newLabel = board.icons.matching(NSPredicate(format:"label == %@", "TokenLeft")).allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
                    if newLabel.count == 1 && visibleWidgets().count == 1 { break }
                    board.swipeLeft()
                }
                let own = visibleWidgets()
                XCTAssertEqual(own.count,1,"只移除本轮空白页的临时实例，不能动原组件")
                if own.count == 1 {
                    own[0].press(forDuration:0.7)
                    let remove = board.buttons["移除小组件"]
                    XCTAssertTrue(remove.waitForExistence(timeout:5)); remove.tap()
                    if board.alerts.buttons["移除"].waitForExistence(timeout:5) { board.alerts.buttons["移除"].tap() }
                    XCTAssertTrue(visibleWidgets().isEmpty || visibleWidgets().count == 3,"必须实际移除临时实例；空白页移除后可回到原三实例页")
                }
            }
            XCUIDevice.shared.press(.home)
            if created {
                app.terminate(); app.launch()
                XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout:15))
            }
            app.terminate(); app.launchArguments = ["--t78-desktop-fixture", "cleanup", session, "light"]
            app.launch(); app.terminate()
        }
        app.launchArguments = ["--t78-desktop-fixture", "normal", session, "light"]
        app.launch(); XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout:15))
        chooseStage3Style("watermark",app:app)
        XCUIDevice.shared.press(.home); showT35Desktop(board)
        let fullPage = NSPredicate { _, _ in visibleWidgets().count == 3 }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:fullPage,object:nil)],timeout:15),.completed)
        let old = visibleWidgets(); XCTAssertEqual(old.count,3)
        board.coordinate(withNormalizedOffset:CGVector(dx:0.985,dy:0.74)).press(forDuration:1.2)
        if !board.buttons["完成"].waitForExistence(timeout:3) {
            old[0].press(forDuration:0.7)
            XCTAssertTrue(board.buttons["编辑主屏幕"].waitForExistence(timeout:5)); board.buttons["编辑主屏幕"].tap()
        }
        // iOS exposes an extra final empty page while editing. No existing page
        // or icon is moved; addition/removal is confined to that empty page.
        for _ in 0..<3 {
            let onGrid = board.icons.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.minY < 700 }
            if onGrid.isEmpty { break }
            board.swipeLeft()
        }
        XCTAssertTrue(board.icons.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.minY < 700 }.isEmpty,"必须先到独立空白页")
        board.buttons["编辑"].tap(); board.buttons["添加小组件"].tap()
        let search = board.searchFields["搜索小组件"]; XCTAssertTrue(search.waitForExistence(timeout:5));search.tap();search.typeText("Token")
        let result = board.cells["TokenLeft"];XCTAssertTrue(result.waitForExistence(timeout:5));result.tap()
        print("T81 temporary gallery selected | \(board.debugDescription)")
        board.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.57)).press(forDuration:0.05,thenDragTo:board.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:0.57)))
        let add = board.buttons.matching(NSPredicate(format:"label CONTAINS %@", "添加小组件")).firstMatch;XCTAssertTrue(add.waitForExistence(timeout:5));add.tap();created = true
        if board.buttons["完成"].waitForExistence(timeout:5) { board.buttons["完成"].tap() }
        XCTAssertEqual(visibleWidgets().count,1)
        XCTAssertGreaterThan(visibleWidgets()[0].frame.width,230,"必须实际是新增中号")
        visibleWidgets()[0].press(forDuration:0.7)
        board.buttons["编辑小组件"].tap()
        print("T81 temporary account field | \(board.debugDescription)")
        let field = board.buttons.matching(NSPredicate(format:"label CONTAINS %@", "显示账户")).firstMatch
        if field.exists { field.tap() }
        else { board.descendants(matching:.any).matching(NSPredicate(format:"label == %@", "跟随列表首个账户")).firstMatch.tap() }
        let second = board.descendants(matching:.any).matching(NSPredicate(format:"label BEGINSWITH %@", "stage3-2@example.invalid")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout:5));second.tap()
        board.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.9)).tap()
        for style in ["watermark", "skala"] {
            app.activate(); chooseStage3Style(style,app:app)
            print("T81 pinned request \(style) | \(Date().ISO8601Format())")
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(board.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "30%")).firstMatch.waitForExistence(timeout:60))
            let own = try XCTUnwrap(visibleWidgets().first)
            attachT65Crop(board,rect:own.frame,name:"T81-临时指定户-\(style)")
            own.tap(); XCTAssertTrue(app.staticTexts["detail.identity"].waitForExistence(timeout:10))
            XCTAssertEqual(app.staticTexts["detail.identity"].label,"stage3-2@example.invalid")
            app.buttons["detail.close"].tap();app.terminate();app.launch()
            XCTAssertTrue(app.otherElements["quota.card"].firstMatch.waitForExistence(timeout:15))
            XCTAssertEqual(app.otherElements["quota.card"].firstMatch.value as? String,stage3Names[stage3Styles.firstIndex(of:style)!])
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(board.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "30%")).firstMatch.waitForExistence(timeout:60))
            // Previous page: unchanged original two defaults and medium.
            board.swipeRight();XCTAssertEqual(visibleWidgets().count,3)
            XCTAssertTrue(board.staticTexts.matching(NSPredicate(format:"label CONTAINS %@", "70%")).firstMatch.waitForExistence(timeout:30))
            let original = try XCTUnwrap(visibleWidgets().first { $0.frame.width < 230 })
            original.tap();XCTAssertTrue(app.staticTexts["detail.identity"].waitForExistence(timeout:10))
            XCTAssertEqual(app.staticTexts["detail.identity"].label,"stage3-1@example.invalid")
            app.buttons["detail.close"].tap();XCUIDevice.shared.press(.home);board.swipeLeft()
            print("T81 default and pinned observed \(style) | \(Date().ISO8601Format())")
        }
    }

    @MainActor
    func testT81NormalProductionStyleChain() throws {
        guard ProcessInfo.processInfo.environment["T81_REAL_APP"] == "1" else { throw XCTSkip("显式本人手机正式App展示检查") }
        continueAfterFailure = false
        let app=XCUIApplication(),board=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        app.launchArguments=[];app.launch()
        let card=app.otherElements["quota.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout:20),"必须实际有本人已有账户，不新增／重登")
        let prior = try XCTUnwrap(card.value as? String)
        let priorIndex = try XCTUnwrap(stage3Names.firstIndex(of:prior))
        let chosen = prior == "冰蓝玻璃" ? "capsule" : "glass"
        chooseStage3Style(chosen,app:app)
        XCTAssertEqual(card.value as? String,stage3Names[stage3Styles.firstIndex(of:chosen)!])
        let crop=XCTAttachment(image:card.screenshot().image);crop.name="Stage3-真实正式账户新卡";crop.lifetime = .keepAlways;add(crop)
        card.tap();XCTAssertTrue(app.staticTexts["detail.identity"].waitForExistence(timeout:10))
        let identity=app.staticTexts["detail.identity"].label
        XCTAssertTrue(app.otherElements["detail.style.weekly.\(chosen)"].exists,"实际适用每周额度卡应同款")
        let detail=app.otherElements["detail.style.weekly.\(chosen)"]
        let q=XCTAttachment(image:detail.screenshot().image);q.name="Stage3-真实正式详情额度卡";q.lifetime = .keepAlways;add(q)
        app.buttons["detail.close"].tap()
        let confirmedAt=Date();print("Stage3 production setting returned | \(confirmedAt.ISO8601Format())")
        XCUIDevice.shared.press(.home);showT35Desktop(board)
        let ready=NSPredicate { _,_ in
            board.descendants(matching:.any).matching(identifier:"native.\(chosen).smallWidget").count >= 2 && board.descendants(matching:.any).matching(identifier:"native.\(chosen).mediumWidget").count >= 1
        }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:ready,object:nil)],timeout:120),.completed)
        print("Stage3 actual production both sizes observed | \(Date().ISO8601Format())")
        let widgets=board.icons.matching(NSPredicate(format:"label == %@ OR label == %@","订阅用量","TokenLeft")).allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
        for medium in [false,true] {
            let w=try XCTUnwrap(widgets.first { ($0.frame.width > 230) == medium })
            attachT65Crop(board,rect:w.frame,name:"Stage3-真实正式桌面-\(medium ? "中" : "小")")
            w.tap();XCTAssertTrue(app.staticTexts["detail.identity"].waitForExistence(timeout:10))
            XCTAssertEqual(app.staticTexts["detail.identity"].label,identity,"现有默认实例仍为原账户")
            app.buttons["detail.close"].tap();XCUIDevice.shared.press(.home)
        }
        app.terminate();app.launch()
        XCTAssertTrue(card.waitForExistence(timeout:20));XCTAssertEqual(card.value as? String,stage3Names[stage3Styles.firstIndex(of:chosen)!])
        chooseStage3Style(stage3Styles[priorIndex],app:app)
        XCTAssertEqual(card.value as? String,prior)
        XCUIDevice.shared.press(.home);showT35Desktop(board)
        let restored=NSPredicate { _,_ in
            if self.stage3Styles[priorIndex] == "original" { return board.descendants(matching:.any).matching(NSPredicate(format:"value == %@",prior)).count >= 3 }
            return board.descendants(matching:.any).matching(identifier:"native.\(self.stage3Styles[priorIndex]).smallWidget").count >= 2 && board.descendants(matching:.any).matching(identifier:"native.\(self.stage3Styles[priorIndex]).mediumWidget").count >= 1
        }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:restored,object:nil)],timeout:120),.completed)
        app.activate();print("Stage3 production restart and previous style restored | \(Date().ISO8601Format())")
    }

    @MainActor
    func testT66NativeSkalaUI() throws { try nativeStyleUI(index: 0, task: 66, name: "彩色斜粒") }

    @MainActor
    func testT67NativeCapsuleUI() throws { try nativeStyleUI(index: 1, task: 67, name: "薄荷胶囊") }

    @MainActor
    func testT68NativeTicksUI() throws { try nativeStyleUI(index: 2, task: 68, name: "精密刻度") }

    @MainActor
    func testT69NativeDialsUI() throws { try nativeStyleUI(index: 3, task: 69, name: "金色仪表") }

    @MainActor
    func testT70NativeIslandUI() throws { try nativeStyleUI(index: 4, task: 70, name: "黑岛绿线") }

    @MainActor
    func testT71NativeBlocksUI() throws { try nativeStyleUI(index: 5, task: 71, name: "紫色模块") }

    @MainActor
    func testT72NativeLiquidUI() throws { try nativeStyleUI(index: 6, task: 72, name: "横向液体") }

    @MainActor
    func testT73NativeTicketUI() throws { try nativeStyleUI(index: 7, task: 73, name: "黑白票签") }

    @MainActor
    func testT74NativeJournalUI() throws { try nativeStyleUI(index: 8, task: 74, name: "暖黄手账") }

    @MainActor
    func testT75NativeGlassUI() throws { try nativeStyleUI(index: 9, task: 75, name: "冰蓝玻璃") }

    @MainActor
    func testT76NativePanelsUI() throws { try nativeStyleUI(index: 10, task: 76, name: "橙色双面板") }

    @MainActor
    func testT77NativeWatermarkUI() throws { try nativeStyleUI(index: 11, task: 77, name: "蓝条水印") }

    @MainActor
    func testStage2MotionAndActualSystemReduceMotion() throws {
        guard ProcessInfo.processInfo.environment["T66_SYSTEM_MOTION"] == "1" else { throw XCTSkip("仅显式启用本阶段系统专项，原值精确恢复") }
        continueAfterFailure = false
        let app = XCUIApplication(), settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        let toggle = settings.switches["REDUCE_MOTION"]
        if !toggle.waitForExistence(timeout: 5) {
            for _ in 0..<6 {
                if settings.navigationBars.firstMatch.identifier == "设置" { break }
                let back = settings.navigationBars.firstMatch.buttons.firstMatch
                if back.exists { back.tap() } else { break }
            }
            let entry = settings.buttons["com.apple.settings.accessibility"]
            for _ in 0..<8 { if entry.isHittable { break }; settings.swipeUp() }
            XCTAssertTrue(entry.isHittable); entry.tap()
            let motion = settings.staticTexts["动态效果"]
            for _ in 0..<5 { if motion.isHittable { break }; settings.swipeUp() }
            XCTAssertTrue(motion.waitForExistence(timeout: 5)); motion.tap()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = try XCTUnwrap(toggle.value as? String)
        addTeardownBlock {
            await MainActor.run {
                settings.activate()
                if toggle.value as? String != original { toggle.coordinate(withNormalizedOffset: .init(dx: 0.9, dy: 0.5)).tap() }
                XCTAssertEqual(toggle.value as? String, original)
                app.terminate()
                print("STAGE2 | actual system Reduce Motion restored original=\(original)")
            }
        }
        for reduced in [false, true] {
            settings.activate()
            if toggle.value as? String != (reduced ? "1" : "0") { toggle.coordinate(withNormalizedOffset: .init(dx: 0.9, dy: 0.5)).tap() }
            XCTAssertEqual(toggle.value as? String, reduced ? "1" : "0")
            for index in 0..<12 {
                let task = index + 66
                app.launchArguments = ["--t66-native-lab", "--style-index", String(index), "--lab-probe", "--lab-parent-animation", "disabled"]
                if reduced { app.launchArguments += ["--lab-size", "large", "--lab-scenario", "long"] }
                app.launch()
                let status = app.staticTexts["lab.systemMotion"]
                XCTAssertTrue(status.waitForExistence(timeout: 8))
                XCTAssertEqual(status.label, reduced ? "系统减少动态：开" : "系统减少动态：关")
                app.buttons["lab.change"].tap()
                let trace = app.staticTexts["lab.trace"]
                if reduced {
                    XCTAssertEqual(nativeMotionCount(app, "mid"), 0)
                    XCTAssertEqual(nativeMotionCount(app, "phase"), 0)
                } else {
                    let predicate = NSPredicate(format: "label MATCHES %@", ".*mid=[1-9][0-9]*.*")
                    XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: trace)], timeout: 8), .completed, trace.label)
                    XCTAssertGreaterThan(nativeMotionCount(app, "mid"), 0)
                }
                screenshot(app, "T\(task)-系统\(reduced ? "减少动态大字号" : "正常动效")")
                print("STAGE2 | T\(task) | systemReduced=\(reduced) | \(trace.label)")
                if index == 6 && !reduced {
                    XCTAssertGreaterThan(nativeMotionCount(app, "phase"), 0)
                    let scroll = app.scrollViews["lab.scroll"]
                    for _ in 0..<3 { scroll.swipeUp() }
                    let off = nativeMotionCount(app, "phase")
                    Thread.sleep(forTimeInterval: 1.2)
                    XCTAssertLessThanOrEqual(nativeMotionCount(app, "phase") - off, 1)
                    for _ in 0..<4 { scroll.swipeDown() }
                    XCTAssertLessThanOrEqual(nativeMotionCount(app, "off"), 1)
                    XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 1.2); app.activate()
                    XCTAssertLessThanOrEqual(nativeMotionCount(app, "bg"), 1)
                    print("STAGE2 | liquid actual offscreen/background pause | \(app.staticTexts["lab.trace"].label)")
                }
                app.terminate()
            }
        }
    }

    @MainActor
    private func nativeMotionCount(_ app: XCUIApplication, _ key: String) -> Int {
        let field = app.staticTexts["lab.trace"].label.split(separator: " ").first { $0.hasPrefix(key + "=") }
        return field.flatMap { Int($0.dropFirst(key.count + 1)) } ?? -1
    }

    @MainActor
    private func nativeStyleUI(index: Int, task: Int, name: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--t66-native-lab", "--style-index", String(index)]
        app.launch()
        XCTAssertTrue(app.staticTexts["lab.style"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["lab.style"].label.contains(name))
        screenshot(app, "T\(task)-App隔离-light-normal")
        app.buttons["lab.change"].tap()
        screenshot(app, "T\(task)-App隔离-change")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "94%")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["lab.theme"].tap()
        screenshot(app, "T\(task)-App隔离-dark-normal")
        app.buttons["lab.motion"].tap()
        XCTAssertEqual(app.buttons["lab.motion"].label, "恢复动态")
        app.buttons["lab.change"].tap()
        screenshot(app, "T\(task)-App隔离-dark-static")
        app.buttons["lab.size"].tap()
        screenshot(app, "T\(task)-App隔离-dark-large")
        let scroll = app.scrollViews["lab.scroll"]
        for _ in 0..<5 { scroll.swipeUp() }
        XCTAssertTrue(app.staticTexts["此处两尺寸为布局验收，桌面宿主尚未接入。数据仅在内存，不是平台查询。"].exists)
        print("T\(task) | actual isolated native App | light/dark, changed data, static injection, accessibility5 scroll | passed")
        app.terminate()
    }
    @MainActor
    func testT65ProductionAppAndConfiguredDesktopRestore() throws {
        guard ProcessInfo.processInfo.environment["T65_NORMAL_APP_CHECK"] == "1" else { throw XCTSkip("仅显式启用本人手机正常启动检查") }
        continueAfterFailure = false
        let app = XCUIApplication(), springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        defer { app.terminate() }
        app.launchArguments = []
        app.launch()
        let card = app.otherElements.matching(identifier: "quota.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30), "正式账户应恢复；不得用隔离数据冒充")
        let identity = card.staticTexts["quota.accountIdentity"].label
        let formalCards = app.otherElements.matching(identifier: "quota.card").allElementsBoundByIndex
        let plans = formalCards.map { $0.staticTexts["quota.plan"].label }
        let weeklyValues = formalCards.map { $0.staticTexts["quota.weekly.remaining"].label }
        XCTAssertFalse(identity.contains("t37-"), "当前保存演示账户允许存在；只排除本轮隔离样例")
        XCTAssertFalse(identity.isEmpty)
        card.buttons["quota.details"].tap()
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["detail.identity"].label == identity, "正式卡片与详情应为同户，日志不输出身份")
        let detail = app.staticTexts["detail.weekly.remaining"]
        if detail.exists {
            let region = CGRect(x: 15, y: 100, width: app.frame.width - 30,
                                height: min(220, app.frame.height - 100))
            attachT65Crop(app, rect: region, name: "T65-正式详情额度区域")
        }
        app.buttons["detail.close"].tap()
        XCUIDevice.shared.press(.home)
        showT35Desktop(springboard)
        let ready = NSPredicate { _, _ in
            let widgets = springboard.icons.matching(NSPredicate(format: "(label == %@ OR label == %@) AND value == %@", "订阅用量", "TokenLeft", "小组件"))
                .allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
            guard widgets.contains(where: { $0.frame.width > 230 }), widgets.contains(where: { $0.frame.width < 230 }) else { return false }
            return widgets.allSatisfy { widget in
                let labels = springboard.staticTexts.allElementsBoundByIndex.filter {
                    widget.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
                }.map(\.label)
                return plans.contains(where: { labels.contains($0) }) && weeklyValues.contains(where: { value in
                    value.isEmpty || labels.contains(where: { $0.contains(value) })
                })
            }
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 120), .completed,
                       "正式账户和可信额度应恢复到实际两尺寸；未出现不能记通过")
        let widgets = springboard.icons.matching(NSPredicate(format: "(label == %@ OR label == %@) AND value == %@", "订阅用量", "TokenLeft", "小组件"))
            .allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
        for medium in [false, true] {
            let widget = try XCTUnwrap(widgets.first { ($0.frame.width > 230) == medium })
            attachT65Crop(springboard, rect: widget.frame, name: "T65-正式桌面\(medium ? "中" : "小")号")
        }
        print("T65 | normal saved-account App and existing desktop small/medium restored | \(Date().ISO8601Format())")
    }

    @MainActor
    private func attachT65Crop(_ app: XCUIApplication, rect: CGRect, name: String) {
        let screenshot = app.screenshot().image
        guard let cg = screenshot.cgImage else { XCTFail("截图缺失"); return }
        let scale = CGFloat(cg.width) / app.frame.width
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        guard let crop = cg.cropping(to: pixels) else { XCTFail("截取范围无效"); return }
        let attachment = XCTAttachment(image: UIImage(cgImage: crop))
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    @MainActor
    func testT64OriginalAppAndExistingDesktopBothSizes() throws {
        guard ProcessInfo.processInfo.environment["T64_WIDGET_DESKTOP"] == "1" else { throw XCTSkip("仅显式启用本人手机现有两尺寸组件检查") }
        continueAfterFailure = false
        let app = XCUIApplication(), springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let session = UUID().uuidString
        addTeardownBlock {
            app.terminate()
            app.launchArguments = ["--t37-widget-fixture", "cleanup", session, "light"]
            app.launch()
            XCTAssertTrue(app.staticTexts["quota.empty"].waitForExistence(timeout: 15))
            app.terminate()
        }
        for appearance in ["light", "dark"] {
            for scenario in ["normal", "endpoints"] {
                app.launchArguments = ["--t37-widget-fixture", scenario, session, appearance]
                app.launch()
                XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 15))
                let weekly = scenario == "normal" ? "70%" : "0%"
                let five = scenario == "normal" ? "85%" : "100%"
                XCTAssertEqual(app.staticTexts["quota.weekly.remaining"].label, "剩余 " + weekly)
                screenshot(app, "T64-App-\(appearance)-\(scenario)")
                app.buttons["quota.details"].firstMatch.tap()
                XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 5))
                XCTAssertEqual(app.staticTexts["detail.weekly.remaining"].label, "剩余 " + weekly)
                screenshot(app, "T64-详情-\(appearance)-\(scenario)")
                app.buttons["detail.close"].tap()
                XCUIDevice.shared.press(.home)
                showT35Desktop(springboard)
                let ready = NSPredicate { _, _ in
                    self.t35BothSizesContain(weekly, on: springboard) && self.t35BothSizesContain(five, on: springboard)
                }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 60), .completed)
                let cards = springboard.icons.matching(NSPredicate(format: "(label == %@ OR label == %@) AND value == %@", "订阅用量", "TokenLeft", "小组件"))
                    .allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
                for card in cards {
                    let labels = springboard.staticTexts.allElementsBoundByIndex.filter {
                        card.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
                    }.map(\.label)
                    XCTAssertFalse(labels.contains { $0.contains("t37-") || $0.contains("@") || $0.contains("更新于") || $0.contains("重置") })
                }
                screenshot(springboard, "T64-实际桌面-\(appearance)-\(scenario)")
                if scenario == "normal" {
                    for medium in [false, true] {
                        let card = try XCTUnwrap(cards.first { ($0.frame.width > 230) == medium })
                        card.tap()
                        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 10))
                        XCTAssertEqual(app.staticTexts["detail.identity"].label, "t37-normal@example.invalid")
                        screenshot(app, "T64-实际\(medium ? "中" : "小")号点击详情-\(appearance)")
                        app.buttons["detail.close"].tap()
                        XCUIDevice.shared.press(.home)
                        showT35Desktop(springboard)
                    }
                }
                app.terminate()
            }
        }
    }

    @MainActor
    func testT37PhoneWidgetLightDarkStateMatrix() throws {
        guard ProcessInfo.processInfo.environment["T37_WIDGET_DESKTOP"] == "1" else { throw XCTSkip("仅显式启用本人手机既有两尺寸组件隔离验收") }
        continueAfterFailure = false
        let app = XCUIApplication(), springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let session = UUID().uuidString
        addTeardownBlock {
            app.terminate()
            app.launchArguments = ["--t37-widget-fixture", "cleanup", session, "light"]
            app.launch()
            XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["quota.empty"].waitForExistence(timeout: 15))
            app.terminate()
        }
        let environment = ProcessInfo.processInfo.environment
        let appearances = environment["T37_APPEARANCES"]?.split(separator: ",").map(String.init) ?? ["light", "dark"]
        for appearance in appearances {
            let scenarios = environment["T37_SCENARIOS"]?.split(separator: ",").map(String.init)
                ?? (environment["T37_REMAINING_ONLY"] == "1" && appearance == "light" ? ["notFetched", "unknown", "long", "empty"] : ["normal", "updating", "failure", "blocked", "endpoints", "free", "notFetched", "unknown", "long", "empty"])
            for scenario in scenarios {
                app.terminate()
                app.launchArguments = ["--t37-widget-fixture", scenario, session, appearance]
                app.launch()
                XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 15))
                if scenario == "updating" {
                    XCTAssertTrue(app.descendants(matching: .any)["quota.refreshProgress"].waitForExistence(timeout: 15), "必须实际有在途刷新")
                }
                XCUIDevice.shared.press(.home)
                showT35Desktop(springboard)
                let expected = scenario == "empty" ? "添加账户" : "t37-" + scenario
                let ready = NSPredicate { _, _ in self.t35BothSizesContain(expected, on: springboard) }
                guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 40) == .completed else {
                    screenshot(springboard, "T37-未就绪-\(appearance)-\(scenario)")
                    XCTFail("两种尺寸未同时显示本状态；不能记通过")
                    return
                }
                for text in (scenario == "failure" ? ["刷新失败", "70%", "85%"] : scenario == "blocked" ? ["网络不达标，无法更新", "70%", "85%"] : scenario == "normal" || scenario == "updating" || scenario == "long" ? ["70%", "85%"] : scenario == "endpoints" ? ["0%", "100%"] : scenario == "unknown" ? ["未知"] : scenario == "notFetched" ? ["尚未获取额度"] : scenario == "free" ? ["Free"] : []) {
                    XCTAssertTrue(t35BothSizesContain(text, on: springboard), "两尺寸应显示\(text)")
                }
                screenshot(springboard, "T37-手机桌面-\(appearance)-\(scenario)")
                print("T37 | actual desktop both sizes | \(appearance) | \(scenario) | \(Date().ISO8601Format())")
            }
        }
    }

    @MainActor
    func testT47DarkUpdatingAndBothFailureMessagesRemainReadable() {
        continueAfterFailure = false
        let updating = launchD60("ui-staggered", extra: ["--t26-dark"])
        let cards = updating.otherElements.matching(identifier: "quota.card")
        updating.pullAllQuota()
        XCTAssertTrue(cards.element(boundBy: 0).descendants(matching: .any)["quota.refreshProgress"].waitForExistence(timeout: 3))
        XCTAssertTrue(cards.element(boundBy: 1).descendants(matching: .any)["quota.refreshProgress"].exists)
        assertNoRefreshBanner(updating)
        screenshot(updating, "T47-深色两户更新中")
        XCTAssertTrue(cards.element(boundBy: 0).descendants(matching: .any)["quota.refreshProgress"].waitForNonExistence(timeout: 14))
        XCTAssertTrue(cards.element(boundBy: 1).descendants(matching: .any)["quota.refreshProgress"].exists)
        screenshot(updating, "T47-深色第一户完成第二户仍等待")
        XCTAssertTrue(cards.element(boundBy: 1).descendants(matching: .any)["quota.refreshProgress"].waitForNonExistence(timeout: 22))
        updating.terminate()
        for (scenario, message) in [("blocked", "网络不达标，无法更新"), ("unknown", "刷新失败")] {
            let app = launchD60(scenario, extra: ["--t26-dark"])
            app.pullAllQuota()
            let text = app.staticTexts["quota.failure"]
            XCTAssertTrue(text.waitForExistence(timeout: 8))
            XCTAssertEqual(text.label, message)
            XCTAssertTrue(text.isHittable)
            XCTAssertTrue(app.buttons["quota.retry"].isHittable)
            XCTAssertTrue(app.buttons["quota.closeFeedback"].isHittable)
            XCTAssertFalse(app.buttons["重新登录"].exists)
            screenshot(app, "T47-深色失败条-\(scenario)")
            app.buttons["quota.closeFeedback"].tap()
            XCTAssertFalse(text.exists)
            XCTAssertEqual(app.otherElements.matching(identifier: "quota.card").element(boundBy: 0).staticTexts["quota.weekly.remaining"].label, "剩余 90%")
            XCTAssertEqual(app.otherElements.matching(identifier: "quota.card").element(boundBy: 1).staticTexts["quota.weekly.remaining"].label, "剩余 70%")
            app.buttons.matching(identifier: "quota.menu").firstMatch.tap()
            XCTAssertTrue(app.buttons["刷新额度"].isHittable)
            XCTAssertTrue(app.buttons["删除账户"].isHittable)
            screenshot(app, "T47-深色账户菜单")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)).tap()
            XCTAssertFalse(app.buttons["删除账户"].exists)
            app.terminate()
        }
    }

    @MainActor
    func testT42WidgetAndNotificationReturnDismissTutorialBeforeOpeningAccount() {
        continueAfterFailure = false
        let app = XCUIApplication(), first = UUID(), second = UUID()
        app.launchArguments = ["--t36-desktop-fixture", "cleanup", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.staticTexts["未连接账户"].waitForExistence(timeout: 8))
        app.terminate()
        app.launchArguments = ["--t26-isolated-ui", "success", "--t41-notification-ui", "--t41-warm-only",
                               "--t36-account-ids", first.uuidString, second.uuidString]
        app.launch()
        defer { app.terminate() }
        for notification in [false, true] {
            app.buttons["tab.settings"].tap()
            app.buttons["settings.widgetTutorial"].tap()
            XCTAssertTrue(app.buttons["tutorial.next"].waitForExistence(timeout: 5))
            app.buttons["tutorial.next"].tap()
            XCUIDevice.shared.press(.home)
            app.open(notification ? notificationFixtureURL("second") : t36URL(id: second, identity: "batch-2@example.invalid"))
            XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 8))
            XCTAssertEqual(app.staticTexts["detail.identity"].label, "batch-2@example.invalid")
            XCTAssertFalse(app.buttons["tutorial.close"].exists)
            screenshot(app, "T42-\(notification ? "通知" : "组件")返回关闭教程直达对应账户")
            app.buttons["detail.close"].tap()
            XCTAssertTrue(app.buttons["tab.quota"].isSelected)
        }
    }

    private func notificationFixtureURL(_ target: String) -> URL {
        URL(string: "subscriptionusage://notification-fixture?target=\(target)")!
    }

    private func notificationFixtureArguments(_ scenario: String, extra: [String] = []) -> [String] {
        ["--t26-isolated-ui", scenario, "--t27-lifecycle", "--t41-notification-ui",
         "--t36-account-ids", UUID().uuidString, UUID().uuidString] + extra
    }

    @MainActor
    func testT41ColdNotificationOpensSecondAccountFromCacheThenAutomaticallyUpdates() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = notificationFixtureArguments("ui-foreground")
        app.launch()
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["detail.identity"].label, "batch-2@example.invalid")
        XCTAssertEqual(app.staticTexts["detail.weekly.remaining"].label, "剩余 70%")
        XCTAssertFalse(app.descendants(matching: .any)["quota.refreshProgress"].exists)
        screenshot(app, "T41-冷启动先显示第二账户可信缓存")
        let updated = NSPredicate(format: "label == %@", "剩余 55%")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: updated,
            object: app.staticTexts["detail.weekly.remaining"])], timeout: 12), .completed)
        screenshot(app, "T41-通知打开后自动更新无转圈")
        app.terminate()
    }

    @MainActor
    func testT41BackgroundNotificationReturnsFromSettingsToCorrespondingAccount() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = notificationFixtureArguments("success", extra: ["--t41-warm-only"])
        app.launch()
        XCTAssertTrue(app.buttons["tab.settings"].waitForExistence(timeout: 8))
        app.buttons["tab.settings"].tap()
        XCUIDevice.shared.press(.home)
        let background = NSPredicate { _, _ in app.state == .runningBackground }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: background, object: nil)], timeout: 5), .completed)
        app.open(notificationFixtureURL("second"))
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["detail.identity"].label, "batch-2@example.invalid")
        screenshot(app, "T41-后台从设置返回通知账户")
        app.open(notificationFixtureURL("first"))
        let first = NSPredicate(format: "label == %@", "batch-1@example.invalid")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: first,
            object: app.staticTexts["detail.identity"])], timeout: 5), .completed)
        screenshot(app, "T41-新通知目标覆盖旧面板")
        app.terminate()
    }

    @MainActor
    func testT41DeletedChangedAndMalformedNotificationFallBackWithoutOpeningOtherAccount() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = notificationFixtureArguments("success")
        app.launch()
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 8))
        for target in ["deleted", "replaced", "malformed"] {
            app.open(notificationFixtureURL(target))
            XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 6))
            XCTAssertFalse(app.buttons["detail.close"].exists)
            XCTAssertFalse(app.buttons["connection.cancel"].exists)
            XCTAssertEqual(app.otherElements.matching(identifier: "quota.card").count, 2)
            screenshot(app, "T41-旧通知安全回退-\(target)")
        }
        app.terminate()
    }

    @MainActor
    func testT41NoAccountsColdNotificationOpensExistingConnectionPicker() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--management-ui", UUID().uuidString, "--t41-notification-ui", "--t41-empty"]
        app.launch()
        XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["detail.close"].exists)
        screenshot(app, "T41-无账户旧通知进入连接引导")
        app.buttons["connection.cancel"].tap()
        app.terminate()
    }

    @MainActor
    func testT41ColdNotificationFailureKeepsOldQuotaAndUsesExistingMessages() {
        continueAfterFailure = false
        for scenario in ["blocked", "unknown"] {
            let app = XCUIApplication()
            app.launchArguments = notificationFixtureArguments(scenario)
            app.launch()
            XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 8))
            XCTAssertEqual(app.staticTexts["detail.identity"].label, "batch-2@example.invalid")
            XCTAssertTrue(app.staticTexts["detail.failure"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["detail.failure"].label, scenario == "blocked" ? "网络不达标，无法更新" : "刷新失败")
            XCTAssertEqual(app.staticTexts["detail.weekly.remaining"].label, "剩余 70%")
            XCTAssertFalse(app.buttons["重新登录"].exists)
            screenshot(app, "T41-失败保留原账户旧值-\(scenario)")
            app.terminate()
        }
    }

    @MainActor
    func testT41ColdNotificationDoesNotWaitForLoginRestoration() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = notificationFixtureArguments("success", extra: ["--t36-delay-login-read"])
        app.launch()
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["detail.identity"].label, "batch-2@example.invalid")
        screenshot(app, "T41-通知缓存路由不等登录恢复")
        app.terminate()
    }

    @MainActor
    func testT36ActualSmallAndMediumWidgetTapColdAndBackground() throws {
        guard ProcessInfo.processInfo.environment["T36_WIDGET_DESKTOP"] == "1" else {
            throw XCTSkip("显式启用：复用已放置的两种尺寸组件，仅隔离会话")
        }
        continueAfterFailure = false
        let app = XCUIApplication(), session = UUID().uuidString
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        defer {
            app.terminate()
            app.launchArguments = ["--t36-desktop-fixture", "cleanup", session]
            app.launch(); app.terminate()
        }
        app.launchArguments = ["--t36-desktop-fixture", "baseline", session]
        app.launch()
        XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        showT35Desktop(springboard)
        let ready = NSPredicate { _, _ in self.t35BothSizesContain("batch-", on: springboard) }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 45), .completed)
        screenshot(springboard, "T36-真实桌面两尺寸隔离基线")
        func widget(_ medium: Bool) -> XCUIElement? {
            springboard.icons.matching(NSPredicate(format: "(label == %@ OR label == %@) AND value == %@", "订阅用量", "TokenLeft", "小组件"))
                .allElementsBoundByIndex.first { $0.isHittable && $0.frame.width > 100 && ($0.frame.width > 230) == medium }
        }
        for medium in [false, true] {
            for cold in [true, false] {
                if cold { app.terminate() }
                else { app.activate(); XCUIDevice.shared.press(.home) }
                showT35Desktop(springboard)
                let card = try XCTUnwrap(widget(medium))
                let labels = springboard.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "batch-"))
                    .allElementsBoundByIndex.filter { card.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
                let identity = try XCTUnwrap(labels.first?.label)
                card.tap()
                XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 10))
                XCTAssertEqual(app.staticTexts["detail.identity"].label, identity + "@example.invalid")
                XCTAssertFalse(app.staticTexts["connection.title"].exists)
                screenshot(app, "T36-\(medium ? "中号" : "小号")-\(cold ? "冷启动" : "后台返回")")
                app.buttons["detail.close"].tap()
                XCUIDevice.shared.press(.home)
            }
        }
    }

    @MainActor
    func testT36ColdWidgetURLDoesNotWaitForPendingLoginRestoration() {
        continueAfterFailure = false
        let app = XCUIApplication(), first = UUID(), second = UUID()
        app.launchArguments = ["--t26-isolated-ui", "success", "--t27-lifecycle", "--t36-delay-login-read",
                               "--t36-account-ids", first.uuidString, second.uuidString]
        app.open(t36URL(id: second, identity: "batch-2@example.invalid"))
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 8), "不等待60秒登录恢复")
        XCTAssertEqual(app.staticTexts["detail.identity"].label, "batch-2@example.invalid")
        screenshot(app, "T36-冷启动缓存面板不等待登录恢复")
        app.terminate()
    }

    @MainActor
    func testT62IdentityNowLivesInDetailsAndResetCardsShowVerifiedTwoOrDefaultZero() {
        for appearance in ["light", "dark"] {
            let app = launchT23("resetCards", appearance: appearance)
            let cards = app.otherElements.matching(identifier: "quota.card")
            for index in 0..<2 {
                cards.element(boundBy: index).buttons["quota.details"].tap()
                XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 3))
                let identity = app.staticTexts["detail.identity"]
                XCTAssertEqual(identity.label, "card-\(index + 1)@example.invalid")
                XCTAssertGreaterThan(identity.frame.minY, app.staticTexts["detail.weekly.remaining"].frame.maxY)
                let inventory = app.staticTexts["detail.resetCards"]
                XCTAssertEqual(inventory.label, "重置额度，\(index == 0 ? "2" : "0")")
                screenshot(app, "T62-账号移入详情-卡数\(index == 0 ? "2" : "0")-\(appearance)")
                app.buttons["detail.close"].tap()
            }
            app.terminate()
        }
    }

    private func t36URL(id: UUID, identity: String) -> URL {
        let key = SHA256.hash(data: Data("codex:false:\(identity.lowercased())".utf8))
            .map { String(format: "%02x", $0) }.joined()
        var url = URLComponents()
        url.scheme = "subscriptionusage"; url.host = "quota"
        url.queryItems = [.init(name: "account", value: id.uuidString), .init(name: "identity", value: key)]
        return url.url!
    }

    @MainActor
    func testT36SystemURLColdLaunchAndBackgroundReturnOpenSelectedPanel() {
        continueAfterFailure = false
        let app = XCUIApplication(), first = UUID(), second = UUID()
        app.launchArguments = ["--t26-isolated-ui", "ui-foreground", "--t27-lifecycle",
                               "--t36-account-ids", first.uuidString, second.uuidString]
        app.open(t36URL(id: second, identity: "batch-2@example.invalid"))
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["detail.identity"].label, "batch-2@example.invalid")
        XCTAssertFalse(app.descendants(matching: .any)["quota.refreshProgress"].exists)
        screenshot(app, "T36-系统URL冷启动对应第二账户")
        let updated = NSPredicate(format: "label == %@", "剩余 55%")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: updated,
            object: app.staticTexts["detail.weekly.remaining"])], timeout: 10), .completed)
        app.buttons["detail.close"].tap()
        XCUIDevice.shared.press(.home)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.state == .runningBackground
        }, object: nil)], timeout: 5), .completed)
        app.open(t36URL(id: first, identity: "batch-1@example.invalid"))
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["detail.identity"].label, "batch-1@example.invalid")
        screenshot(app, "T36-系统URL后台返回对应第一账户")
        app.buttons["detail.close"].tap()
        app.open(t36URL(id: second, identity: "different@example.invalid"))
        XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["detail.close"].exists)
        XCTAssertFalse(app.staticTexts["connection.title"].exists)
        app.terminate()
    }

    @MainActor
    func testT36UnavailableOldTargetAndEmptyTargetFallBackSafely() {
        continueAfterFailure = false
        let app = XCUIApplication(), first = UUID(), second = UUID()
        for scenario in ["blocked", "unknown"] {
            app.launchArguments = ["--t26-isolated-ui", scenario, "--t27-lifecycle",
                                   "--t36-account-ids", first.uuidString, second.uuidString]
            app.open(t36URL(id: second, identity: "batch-2@example.invalid"))
            XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 8))
            XCTAssertEqual(app.staticTexts["detail.identity"].label, "batch-2@example.invalid")
            XCTAssertTrue(app.staticTexts["detail.failure"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["detail.weekly.remaining"].label, "剩余 70%")
            screenshot(app, "T36-组件链接失败保留旧值-\(scenario)")
            app.buttons["detail.close"].tap()
            app.open(t36URL(id: UUID(), identity: "deleted@example.invalid"))
            XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["detail.close"].exists)
            XCTAssertFalse(app.buttons["connection.cancel"].exists)
            app.terminate()
        }
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.open(t36URL(id: first, identity: "old@example.invalid"))
        XCTAssertTrue(app.buttons["platforms.codex"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["detail.close"].exists)
        screenshot(app, "T36-已无账户进入连接入口")
        app.buttons["connection.cancel"].tap()
        app.terminate()
    }

    @MainActor
    func testT62CardOpensSamePanelClosesAndMenuKeepsItsScope() {
        continueAfterFailure = false
        let app = XCUIApplication()
        for appearance in ["light", "dark"] {
            app.launchArguments = ["--t23-card-fixture", "times", appearance]
            app.launch()
            let cards = app.otherElements.matching(identifier: "quota.card")
            XCTAssertEqual(cards.count, 2)
            let card = cards.element(boundBy: 0)
            let resetLabels = ["fiveHours", "weekly"].map { card.staticTexts["quota.\($0).reset"].label }
            screenshot(app, "T62-额度页卡片对照-\(appearance)")
            cards.element(boundBy: 0).buttons["quota.details"].tap()
            XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["每周限额"].exists)
            for (index, id) in ["fiveHours", "weekly"].enumerated() {
                let reset = app.staticTexts["detail.\(id).reset"]
                let amount = app.staticTexts["detail.\(id).remaining"]
                let bar = app.descendants(matching: .any)["detail.\(id).bar"].firstMatch
                XCTAssertEqual(reset.label, resetLabels[index])
                XCTAssertTrue(reset.isHittable)
                XCTAssertLessThanOrEqual(reset.frame.maxY, bar.frame.minY)
                XCTAssertLessThanOrEqual(amount.frame.maxY, bar.frame.minY)
            }
            XCTAssertEqual(app.staticTexts["detail.identity"].label, "card-1@example.invalid")
            XCTAssertLessThan(app.staticTexts["detail.fiveHours.remaining"].frame.minY,
                              app.staticTexts["detail.weekly.remaining"].frame.minY)
            XCTAssertTrue(app.staticTexts["detail.fiveHours.remaining"].label.contains("0%"))
            XCTAssertTrue(app.staticTexts["detail.weekly.remaining"].label.contains("100%"))
            screenshot(app, "T62-面板-\(appearance)")
            app.buttons["detail.menu"].tap()
            XCTAssertTrue(app.buttons["刷新额度"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["删除账户"].exists)
            XCTAssertFalse(app.buttons["重新登录"].exists)
            app.buttons["detail.close"].coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
            // Dismiss the menu first, then close the sheet.
            if app.buttons["detail.close"].exists { app.buttons["detail.close"].tap() }
            XCTAssertTrue(cards.element(boundBy: 1).waitForExistence(timeout: 3))
            cards.element(boundBy: 1).staticTexts["quota.weekly.remaining"].tap()
            XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.staticTexts["detail.identity"].label, "card-2@example.invalid")
            XCTAssertTrue(app.staticTexts["detail.fiveHours.remaining"].label.contains("20%"))
            app.buttons["detail.close"].tap()
            XCTAssertFalse(app.buttons["detail.close"].exists)
            cards.element(boundBy: 0).buttons["quota.menu"].tap()
            XCTAssertTrue(app.buttons["删除账户"].waitForExistence(timeout: 3))
            XCTAssertFalse(app.buttons["detail.close"].exists, "菜单不能误开详情")
            app.terminate()
        }
    }

    @MainActor
    func testT62RefreshFailureRetainsOldPanelAndDeleteReturnsToList() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--t26-isolated-ui", "blocked"]
        app.launch()
        let cards = app.otherElements.matching(identifier: "quota.card")
        XCTAssertEqual(cards.count, 2)
        let oldValue = cards.element(boundBy: 0).staticTexts["quota.weekly.remaining"].label
        cards.element(boundBy: 0).buttons["quota.details"].tap()
        let oldTime = app.descendants(matching: .any)["quota.updatedAt"].firstMatch.label
        app.buttons["detail.refresh"].tap()
        XCTAssertTrue(app.staticTexts["detail.failure"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detail.failure"].label, "网络不达标，无法更新")
        XCTAssertEqual(app.staticTexts["detail.weekly.remaining"].label, oldValue)
        XCTAssertEqual(app.descendants(matching: .any)["quota.updatedAt"].firstMatch.label, oldTime)
        screenshot(app, "T62-失败保留原值原时间")
        app.buttons["detail.close"].tap()
        app.terminate()
        app.launchArguments = ["--management-ui", UUID().uuidString]
        app.launch()
        app.buttons["tab.settings"].tap()
        app.switches["settings.demo"].coordinate(withNormalizedOffset: .init(dx: 0.9, dy: 0.5)).tap()
        app.buttons["tab.quota"].tap()
        // T96: the switch itself provides the single Cursor sample.
        XCTAssertTrue(app.buttons["quota.details"].waitForExistence(timeout: 5))
        app.buttons["quota.details"].tap()
        app.buttons["detail.menu"].tap()
        app.buttons["删除账户"].tap()
        app.alerts.buttons["删除账户"].tap()
        XCTAssertTrue(app.staticTexts["quota.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["detail.close"].exists)
    }

    private var t35ObservationPhase = "standard"

    @MainActor
    private func t35WidgetDeveloperMode(_ desired: Bool? = nil) throws -> Bool {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        if !settings.navigationBars["开发者"].waitForExistence(timeout: 2) {
            let developer = settings.buttons["com.apple.settings.developer"]
            for _ in 0..<8 {
                if developer.exists && developer.isHittable { break }
                settings.swipeUp()
            }
            guard developer.waitForExistence(timeout: 5), developer.isHittable else {
                throw NSError(domain: "T35.Settings", code: 1)
            }
            developer.tap()
        }
        let row = settings.cells["WIDGETKIT_DEVELOPER_MODE_ENABLED"]
        for _ in 0..<10 {
            if row.exists && row.isHittable { break }
            if row.exists && row.frame.midY < 100 { settings.swipeDown() }
            else { settings.swipeUp() }
        }
        // The outer row reports a stale value; its child is the actual UISwitch.
        let toggle = settings.switches["WIDGETKIT_DEVELOPER_MODE_ENABLED"].firstMatch.switches.firstMatch
        guard row.exists && row.isHittable, toggle.exists,
              let value = toggle.value as? String, ["0", "1"].contains(value) else {
            screenshot(settings, "T35-系统预算开关未就绪")
            throw NSError(domain: "T35.Settings", code: 2)
        }
        if let desired, (value == "1") != desired {
            guard toggle.isHittable else { throw NSError(domain: "T35.Settings", code: 4) }
            toggle.tap()
            let expected = NSPredicate(format: "value == %@", desired ? "1" : "0")
            guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: expected, object: toggle)], timeout: 5) == .completed else {
                screenshot(settings, "T35-系统预算开关切换失败")
                throw NSError(domain: "T35.Settings", code: 3)
            }
        }
        let enabled = (toggle.value as? String) == "1"
        print("T35 | WidgetKit开发者模式 | enabled=\(enabled) | \(Date().ISO8601Format())")
        screenshot(settings, "T35-WidgetKit开发者模式-\(enabled)")
        XCUIDevice.shared.press(.home)
        return enabled
    }

    @MainActor
    func testT35WidgetBudgetControl() throws {
        guard ProcessInfo.processInfo.environment["T35_BUDGET_CONTROL"] == "1" else {
            throw XCTSkip("仅显式启用临时预算对照，结束恢复原设置")
        }
        let initial = try t35WidgetDeveloperMode()
        // A resumed interrupted diagnostic can restore the value recorded before it began.
        let original = ProcessInfo.processInfo.environment["T35_WIDGET_ORIGINAL_MODE"]
            .flatMap { $0 == "0" ? false : ($0 == "1" ? true : nil) } ?? initial
        defer {
            do { _ = try t35WidgetDeveloperMode(original) }
            catch { XCTFail("必须恢复WidgetKit开发者模式原设置：\(error)") }
        }
        let phases = ProcessInfo.processInfo.environment["T35_BUDGET_SKIP_BEFORE"] == "1"
            ? [("budget-on", true), ("budget-off-after", false)]
            : [("budget-off-before", false), ("budget-on", true), ("budget-off-after", false)]
        for (phase, mode) in phases where ProcessInfo.processInfo.environment["T35_BUDGET_PHASE"].map({ $0 == phase }) ?? true {
            _ = try t35WidgetDeveloperMode(mode)
            t35ObservationPhase = phase
            print("T35 | 预算对照阶段 | \(phase)")
            try testT35SystemBackgroundPublishesToDesktop()
        }
    }

    @MainActor
    private func showT35Desktop(_ springboard: XCUIApplication) {
        let cards = springboard.icons.matching(NSPredicate(format: "label == %@ OR label == %@", "订阅用量", "TokenLeft"))
        func visible() -> Bool {
            let visible = cards.allElementsBoundByIndex.filter { $0.isHittable && $0.frame.width > 100 }
            return visible.contains { $0.frame.width < 230 } && visible.contains { $0.frame.width > 230 }
        }
        if visible() { return }
        // Home may reopen on any page (including Today View after a previous run).
        for _ in 0..<3 { springboard.swipeRight(); if visible() { return } }
        for _ in 0..<6 { springboard.swipeLeft(); if visible() { return } }
        XCTFail("未找到已有订阅用量组件所在桌面页")
    }

    @MainActor
    private func t35BothSizesContain(_ text: String, on springboard: XCUIApplication) -> Bool {
        let cards = springboard.icons.matching(NSPredicate(format: "(label == %@ OR label == %@) AND value == %@", "订阅用量", "TokenLeft", "小组件"))
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
        let cards = springboard.icons.matching(NSPredicate(format: "(label == %@ OR label == %@) AND value == %@", "订阅用量", "TokenLeft", "小组件"))
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
                if ProcessInfo.processInfo.environment["T35_BASELINE_ONLY"] == "1" { return }
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
    func testT61WidgetFetchesWithoutAppQueryAndKeepsBothSizes() throws {
        guard ProcessInfo.processInfo.environment["T61_WIDGET_ACCEPTANCE"] == "1" else {
            throw XCTSkip("显式启用隔离桌面验收")
        }
        let app = XCUIApplication(), session = UUID().uuidString
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        defer {
            app.terminate()
            app.launchArguments = ["--t35-widget-fixture", "cleanup", session]
            app.launch(); app.terminate()
        }
        for (scenario, value) in [("backgroundBaseline", "90%"), ("autonomous", "55%")] {
            app.terminate()
            app.launchArguments = ["--t35-widget-fixture", scenario, session, "--t35-configured-account"]
            app.launch()
            XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 10))
            Thread.sleep(forTimeInterval: 3)
            XCUIDevice.shared.press(.home)
            showT35Desktop(springboard)
            let predicate = NSPredicate { _, _ in self.t35BothSizesContain(value, on: springboard) }
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 90)
            screenshot(springboard, "T61-桌面-\(scenario)")
            XCTAssertEqual(result, .completed, "两种尺寸桌面数字必须实际变化")
            print("T61 | \(scenario) | desktop=\(value) | passed=\(result == .completed)")
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
        if ProcessInfo.processInfo.environment["T35_PRESERVE_CONFIGURED_ACCOUNTS"] == "1" {
            app.launchArguments = ["--t35-widget-fixture", "backgroundBaseline", session,
                                   "--t30-background-debug", "--t35-configured-account"]
        }
        if let preserved = ProcessInfo.processInfo.environment["T35_PRESERVED_ACCOUNT_ID"], UUID(uuidString: preserved) != nil {
            app.launchArguments += ["--t35-preserved-account-id", preserved]
        }
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
        screenshot(springboard, "T35-系统后台前桌面-\(t35ObservationPhase)")
        if ProcessInfo.processInfo.environment["T35_BASELINE_ONLY"] == "1" { return }
        print("T35 DEBUG READY background")
        // Stay on the Home Screen: activating the app would be a separate trigger.
        let newValue = NSPredicate { _, _ in self.t35BothSizesContain("55%", on: springboard) }
        let observationSeconds = min(2_400, max(30,
            Double(ProcessInfo.processInfo.environment["T35_OBSERVATION_SECONDS"] ?? "") ?? 180))
        print("T35 | 桌面观察窗口 | \(observationSeconds)秒 | \(Date().ISO8601Format())")
        let changed = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: newValue, object: nil)], timeout: observationSeconds)
        XCTAssertEqual(changed, .completed, "两种尺寸都要采用新值；已请求更新不能替代实际换图")
        screenshot(springboard, "T35-真机系统后台后桌面-\(t35ObservationPhase)")
        print("T35 | 系统后台后桌面观察 | \(Date().ISO8601Format()) | phase=\(t35ObservationPhase) passed=\(changed == .completed)")
        app.activate()
        XCTAssertEqual(app.staticTexts["quota.title"].value as? String, "T30 debug background=true success=2 failed=0")
        if ProcessInfo.processInfo.environment["T35_FOREGROUND_CONTROL"] == "1" {
            // Separate control, never evidence that background presentation worked.
            // Reload the same shared 55% without a new query or fixture reset.
            app.terminate()
            app.launchArguments = ["--t35-widget-fixture", "reloadOnly", session]
            app.launch()
            XCTAssertTrue(app.staticTexts["quota.title"].waitForExistence(timeout: 10))
            XCUIDevice.shared.press(.home)
            showT35Desktop(springboard)
            let control = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: newValue, object: nil)], timeout: 30)
            screenshot(springboard, "T35-同一后台数据-前台仅请求更新对照")
            print("T35 | 前台仅请求更新对照 | \(Date().ISO8601Format()) | passed=\(control == .completed)")
            XCTAssertEqual(control, .completed)
        }
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
        func time(_ card: XCUIElement) -> String {
            card.buttons["quota.details"].tap()
            XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 3))
            let result = app.staticTexts["quota.updatedAt"].label
            app.buttons["detail.close"].tap()
            return result
        }
        let oldTime = time(second)
        app.pullAllQuota()
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForExistence(timeout: 8))
        XCTAssertEqual(first.staticTexts["quota.weekly.remaining"].label, "剩余 55%")
        XCTAssertEqual(second.staticTexts["quota.weekly.remaining"].label, "剩余 70%")
        XCTAssertEqual(time(second), oldTime)
        let firstTime = time(first)
        XCTAssertNotEqual(firstTime, oldTime)
        screenshot(app, "T26-部分成功与旧值保留")
        app.buttons["quota.retry"].tap()
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["quota.refreshProgress"].firstMatch.waitForNonExistence(timeout: 8))
        XCTAssertEqual(first.staticTexts["quota.weekly.remaining"].label, "剩余 50%")
        XCTAssertEqual(second.staticTexts["quota.weekly.remaining"].label, "剩余 50%")
        XCTAssertNotEqual(time(first), firstTime)
        XCTAssertNotEqual(time(second), oldTime)
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
        let secondY = second.frame.minY
        app.pullAllQuota()
        let spinner = first.descendants(matching: .any)["quota.refreshProgress"]
        screenshot(app, "D60-开始手动刷新")
        XCTAssertTrue(spinner.waitForExistence(timeout: 3))
        XCTAssertTrue(second.descendants(matching: .any)["quota.refreshProgress"].exists)
        assertNoRefreshBanner(app)
        XCTAssertGreaterThan(spinner.frame.minX, first.buttons["quota.details"].frame.maxX)
        XCTAssertEqual(first.buttons["quota.details"].frame, plan)
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
        let originalNextY = second.frame.minY
        for cycle in 0..<3 {
            first.buttons["quota.details"].tap()
            XCTAssertTrue(app.staticTexts["quota.updatedAt"].waitForExistence(timeout: 3))
            screenshot(app, "T62-重复打开-\(cycle)")
            app.buttons["detail.close"].tap()
            XCTAssertTrue(app.buttons["detail.close"].waitForNonExistence(timeout: 3))
            XCTAssertEqual(second.frame.minY, originalNextY, accuracy: 1)
        }
    }

    @MainActor
    func testT24DetailsBelongToEachAccountAndMissingOrElapsedResetIsHonest() {
        for appearance in ["light", "dark"] {
            let app = launchT23("times", appearance: appearance)
            let cards = app.otherElements.matching(identifier: "quota.card")
            cards.element(boundBy: 0).buttons["quota.details"].tap()
            XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 3))
            let firstTime = app.staticTexts["quota.updatedAt"].label
            XCTAssertTrue((app.staticTexts["detail.weekly.reset"].value as? String ?? "").hasPrefix("预计重置 · "))
            app.buttons["detail.close"].tap()
            cards.element(boundBy: 1).buttons["quota.details"].tap()
            XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 3))
            XCTAssertNotEqual(app.staticTexts["quota.updatedAt"].label, firstTime)
            XCTAssertEqual(app.staticTexts["detail.weekly.reset"].value as? String, "已到预计时间")
            XCTAssertEqual(app.staticTexts["detail.fiveHours.reset"].label, "未提供重置时间")
            XCTAssertEqual(app.staticTexts["detail.weekly.remaining"].label, "剩余 70%")
            XCTAssertEqual(app.staticTexts["detail.fiveHours.remaining"].label, "剩余 20%")
            screenshot(app, "T62-各自时间与已到点-\(appearance)")
            app.terminate()
        }
    }

    @MainActor
    func testT24ExpansionRemainsReadableAtLargestAccessibilitySize() {
        let app = launchT23("limits", appearance: "dark", extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        app.buttons["quota.details"].firstMatch.tap()
        XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 3))
        let reset = app.staticTexts["detail.fiveHours.reset"]
        let bar = app.descendants(matching: .any)["detail.fiveHours.bar"].firstMatch
        XCTAssertTrue(reset.isHittable)
        XCTAssertLessThanOrEqual(reset.frame.maxY, bar.frame.minY)
        let time = app.staticTexts["quota.updatedAt"]
        for _ in 0..<4 where !time.isHittable { app.swipeUp() }
        XCTAssertTrue(time.isHittable)
        screenshot(app, "T62-大字号滚动可读")
        XCTAssertTrue(app.buttons["detail.close"].isHittable, "大字号滚动后顶部关闭必须可用")
        app.buttons["detail.close"].tap()
    }

    @MainActor
    func testT23AccessibilityLayoutUsesFullWidthIdentityAndSeparatesResetTime() {
        for appearance in ["light", "dark"] {
            for size in ["UICTContentSizeCategoryAccessibilityM", "UICTContentSizeCategoryAccessibilityXXXL"] {
                let app = launchT23("limits", appearance: appearance, extra: ["-UIPreferredContentSizeCategoryName", size])
                let card = app.otherElements.matching(identifier: "quota.card").element(boundBy: 0)
                // D-76 card: name, reset time, number and graphic stack at accessibility sizes.
                XCTAssertGreaterThanOrEqual(card.buttons["quota.details"].frame.minX, card.frame.minX + 16)
                for id in ["weekly", "fiveHours"] {
                    let value = card.staticTexts["quota.\(id).remaining"]
                    let bar = card.otherElements["quota.\(id).bar"]
                    let reset = card.staticTexts["quota.\(id).reset"]
                    XCTAssertLessThanOrEqual(reset.frame.maxY, value.frame.minY + 1)
                    XCTAssertLessThan(value.frame.maxY, bar.frame.minY)
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
            XCTAssertEqual(first.staticTexts["quota.plan"].label, "Codex", "D-77：不显示套餐名")
            XCTAssertEqual(second.staticTexts["quota.plan"].label, "Codex")
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
    func testT23NoFiveHourLimitHidesOnlyThatWindowOnCardAndDetails() {
        for appearance in ["light", "dark"] {
            let app = launchT23("noFive", appearance: appearance)
            let cards = app.otherElements.matching(identifier: "quota.card")
            let pro = cards.element(boundBy: 0), plus = cards.element(boundBy: 1)
            XCTAssertEqual(pro.staticTexts["quota.weekly.remaining"].label, "剩余 70%")
            for id in ["remaining", "bar", "reset"] {
                XCTAssertFalse(pro.descendants(matching: .any)["quota.fiveHours.\(id)"].exists)
            }
            XCTAssertEqual(plus.staticTexts["quota.fiveHours.remaining"].label, "未知")
            screenshot(app, "T23-无5小时与真实未知区分-\(appearance)")
            pro.buttons["quota.details"].tap()
            XCTAssertTrue(app.buttons["detail.close"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["detail.weekly.remaining"].label, "剩余 70%")
            XCTAssertFalse(app.staticTexts["detail.fiveHours.remaining"].exists)
            XCTAssertTrue(app.staticTexts["quota.updatedAt"].exists)
            screenshot(app, "T23-无5小时详情-\(appearance)")
            app.buttons["detail.close"].tap()
            plus.buttons["quota.details"].tap()
            XCTAssertTrue(app.staticTexts["detail.fiveHours.remaining"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["detail.fiveHours.remaining"].label, "未知")
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
            XCTAssertFalse(first.staticTexts["quota.fiveHours.remaining"].exists, "无5小时限额不展示")
            XCTAssertFalse(app.otherElements["quota.weekly.bar"].exists)
            XCTAssertFalse(app.otherElements["quota.fiveHours.bar"].exists)
            XCTAssertEqual(second.staticTexts["quota.plan"].label, "Codex")
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
        app.buttons["detail.close"].tap()
        app.buttons["quota.menu"].tap()
        app.buttons["刷新额度"].tap()
        XCTAssertTrue(app.staticTexts["quota.failure"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["quota.failure"].label, "刷新失败")
        XCTAssertEqual(planLabel(app), "Codex")
        XCTAssertEqual(app.staticTexts["quota.weekly.remaining"].label, "剩余 70%")
        XCTAssertEqual(app.staticTexts["quota.fiveHours.remaining"].label, "剩余 20%")
        // Reconfiguration can collapse details; reopen only if needed.
        if !app.staticTexts["quota.updatedAt"].exists { openDetails(app) }
        XCTAssertEqual(app.staticTexts["quota.updatedAt"].label, originalTime)
        XCTAssertTrue(app.buttons["detail.retry"].exists)
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
        // Four D-76 cards exceed one screen: check the head, then scroll to the appended tail.
        assertT17Order(app, identifier: "quota.accountIdentity", expected: expected)
        let appended = app.staticTexts["account-4@example.invalid"]
        for _ in 0..<4 where !appended.exists { app.collectionViews["quota.list"].swipeUp(velocity: .slow) }
        XCTAssertTrue(appended.exists)
        let labels = app.staticTexts.matching(identifier: "quota.accountIdentity").allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(labels.last, "account-4@example.invalid")
        XCTAssertEqual(Set(labels).count, labels.count)
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
        // D-76 cards are taller; grab inside the visible header area of the row.
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            .press(forDuration: 0.7, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
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
        XCTAssertTrue(waitT17Order(app, identifier: identifier, expected: expected),
                      "\(app.staticTexts.matching(identifier: identifier).allElementsBoundByIndex.map(\.label)) != \(expected)")
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
        // The sheet may still be finishing its dismissal when the card is already readable.
        XCTAssertTrue(app.staticTexts["connection.title"].waitForNonExistence(timeout: 3))
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
        XCTAssertTrue(app.staticTexts["quota.notApplicable"].waitForExistence(timeout: 10))
        XCTAssertEqual(planLabel(app), "Codex")
        assertNoQuotaOrFailure(app)
        screenshot(app, "T13-样式-Free")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["quota.notApplicable"].waitForExistence(timeout: 10))
        XCTAssertEqual(planLabel(app), "Codex")
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
        XCTAssertEqual(planLabel(app), "Codex")
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
        XCTAssertEqual(app.staticTexts["quota.accountStatus"].label, "刷新失败")
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
        XCTAssertTrue(app.staticTexts["quota.notApplicable"].waitForExistence(timeout: 10))
        XCTAssertEqual(planLabel(app), "Codex")
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
        XCTAssertEqual(planLabel(app), "Codex")
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
        XCTAssertEqual(planLabel(app), "Codex")
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
        XCTAssertEqual(plan, "Codex", "D-77：不显示套餐名")
        let free = app.staticTexts["quota.notApplicable"].exists
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
            // Since T27 opening the App refreshes automatically; offline that refresh fails and,
            // per D-60, shows "刷新失败" while the saved values and original success time stay.
            XCTAssertTrue(app.staticTexts["quota.failure"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["quota.failure"].label, "刷新失败")
            XCTAssertFalse(app.otherElements["quota.updating"].exists)
            openDetails(app)
            XCTAssertEqual(ids.map { app.staticTexts[$0].label }, savedLabels)
            if scenario == "partial" {
                XCTAssertEqual(app.staticTexts["quota.fiveHours.remaining"].label, "未知")
                XCTAssertEqual(app.staticTexts["quota.weekly.reset"].label, "未提供重置时间")
            }
            screenshot(app, "T15-离线缓存-" + scenario)
            app.buttons["detail.close"].tap()
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
        XCTAssertEqual(planLabel(app), "Codex")
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
        let plan = app.staticTexts["quota.plan"]
        return plan.exists ? plan.label : app.staticTexts["quota.plan"].label
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
