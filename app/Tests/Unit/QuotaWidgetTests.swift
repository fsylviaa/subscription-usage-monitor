import XCTest
import SwiftUI
import WidgetKit
@testable import SubscriptionUsage

@MainActor
final class QuotaWidgetTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_791_590_400)

    private func fixture(state: WidgetSnapshot.State = .available,
                         weekly: WidgetSnapshot.Amount = .limited(usedPercent: 30),
                         five: WidgetSnapshot.Amount = .limited(usedPercent: 15),
                         reset: Bool = true, long: Bool = false) -> WidgetSnapshot {
        .init(schemaVersion: 1, account: .init(id: UUID(),
            identity: long ? "long.account.name.for.widget@example.invalid" : "work@example.invalid",
            plan: state == .notApplicable ? "Free" : "Plus", isDemo: false, state: state,
            subscriptionObservedAt: time, quotaObservedAt: state == .available ? time : nil,
            weekly: state == .available ? .init(amount: weekly, resetsAt: reset ? time.addingTimeInterval(86400 * 5) : nil, observedAt: time) : nil,
            fiveHours: state == .available ? .init(amount: five, resetsAt: reset ? time.addingTimeInterval(3600 * 4) : nil, observedAt: time) : nil))
    }

    func testT80SmallFormalHostInputsAndStaticRendering() throws { try verifyStage3WidgetHost(medium: false, task: 80) }

    func testT81MediumFormalHostInputsAndStaticRendering() throws { try verifyStage3WidgetHost(medium: true, task: 81) }

    private func verifyStage3WidgetHost(medium: Bool, task: Int) throws {
        var renders = 0
        for style in QuotaCardStyle.allCases {
            for dark in [false, true] {
                for scenario in ["normal", "endpoints", "weekly", "unknown", "unlimited", "failure", "long", "empty", "first"] {
                    let account = QuotaStyleLabView.fixtureAccount(scenario: scenario)
                    let snapshot = WidgetSnapshot(schemaVersion: 1, account: account)
                    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                    let before = try encoder.encode(snapshot)
                    let view = SmallQuotaWidgetView(content: .snapshot(snapshot), medium: medium)
                        .environment(\.quotaCardStyle, style).environment(\.colorScheme, dark ? .dark : .light)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                        .dynamicTypeSize(.accessibility5)
                        .frame(width: medium ? 360 : 170.5, height: 170.5)
                    let renderer = ImageRenderer(content: view); renderer.scale = 2
                    let first = try XCTUnwrap(renderer.uiImage)
                    let second = try XCTUnwrap(renderer.uiImage)
                    XCTAssertEqual(first.pngData(), second.pngData(), "组件与水印应静态")
                    XCTAssertEqual(before, try encoder.encode(snapshot), "样式不能写业务投影")
                    if scenario == "normal" || (style == .watermark && dark == false) {
                        let a = XCTAttachment(image: first); a.name = "T\(task)-正式组件宿主渲染-\(dark ? "dark" : "light")-\(style.rawValue)-\(scenario)"
                        a.lifetime = .keepAlways; add(a)
                    }
                    renders += 1
                }
            }
        }
        print("T\(task) | actual shared widget host, 13 styles x 2 themes x 9 inputs, largest type, identical repeated static pixels, immutable snapshots | renders=\(renders)")
    }

    func testT81ValidationCleanupAndOriginalConfigurations() async throws {
        guard ProcessInfo.processInfo.environment["T81_CLEANUP"] == "1" else { throw XCTSkip("阶段结束只读检查") }
        #if DEBUG
        let root=try WidgetSnapshotStore.sharedDirectory()
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("T35-validation-session").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath:root.appendingPathComponent("T36-route-session.json").path))
        XCTAssertEqual(try WidgetSnapshotStore.displayStore().resolvedURL(),try WidgetSnapshotStore.appGroupStore().resolvedURL())
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).contains { $0.lastPathComponent.hasPrefix("T35-validation-") })
        let cache=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0]
        for name in ["T78-stage3-audit.json","T78-stage3-config-audit.json","T78-stage3-reloads.json"] { XCTAssertFalse(FileManager.default.fileExists(atPath:cache.appendingPathComponent(name).path)) }
        let info:[WidgetInfo]=try await withCheckedThrowingContinuation { c in WidgetCenter.shared.getCurrentConfigurations { c.resume(with:$0) } }
        let ours=info.filter { $0.kind == WidgetAppearance.kind }
        XCTAssertEqual(ours.count,4)
        XCTAssertTrue(ours.allSatisfy { let id=$0.widgetConfigurationIntent(of:QuotaWidgetConfiguration.self)?.account?.id;return id == nil || id == WidgetAccountEntity.firstID })
        XCTAssertEqual(QuotaCardStylePreferences.effectiveValue(),QuotaCardStylePreferences.read(from:QuotaCardStylePreferences.sharedDefaults()))
        print("T81 | readonly cleanup | production source, no markers/private directories/audit files; four original resolved configurations retained | passed")
        #endif
    }

    func testT65PreferencesDefaultUnknownChangeAndProtectedKeys() throws {
        let localName = "T65-local-" + UUID().uuidString, sharedName = "T65-shared-" + UUID().uuidString
        let local = try XCTUnwrap(UserDefaults(suiteName: localName))
        let shared = try XCTUnwrap(UserDefaults(suiteName: sharedName))
        defer { local.removePersistentDomain(forName: localName); shared.removePersistentDomain(forName: sharedName) }
        let protected = ["appearance": "dark", "snapshot": "used=29.875", "credential": "isolated-sentinel",
                         "order": "second,first", "successTime": "original", "notification": "off", "intent.account": "pinned"]
        for (key, value) in protected { local.set(value, forKey: key); shared.set(value, forKey: key) }
        XCTAssertEqual(QuotaCardStylePreferences.read(from: local), .skala)
        local.set("future-unknown", forKey: QuotaCardStylePreferences.key)
        XCTAssertEqual(QuotaCardStylePreferences.read(from: local), .skala)
        // D-76: a saved former original style migrates silently to the default.
        local.set("original", forKey: QuotaCardStylePreferences.key)
        XCTAssertEqual(QuotaCardStylePreferences.read(from: local), .skala)
        XCTAssertEqual(local.string(forKey: QuotaCardStylePreferences.key), "original", "读取不改写原值")
        var requests = 0
        for style in QuotaCardStyle.allCases {
            QuotaCardStylePreferences.save(style, to: local, shared: shared) { requests += 1 }
            let reader = try XCTUnwrap(UserDefaults(suiteName: localName))
            XCTAssertEqual(QuotaCardStylePreferences.read(from: reader), style)
            for _ in 0..<3 { XCTAssertEqual(QuotaCardStylePreferences.read(from: shared), style) }
            QuotaCardStylePreferences.save(style, to: local, shared: shared) { requests += 1 }
        }
        XCTAssertEqual(requests, 13)
        QuotaCardStylePreferences.save(.skala, to: local, shared: shared) { requests += 1 }
        XCTAssertEqual(requests, 14)
        for (key, value) in protected {
            XCTAssertEqual(local.string(forKey: key), value)
            XCTAssertEqual(shared.string(forKey: key), value)
        }
        shared.set("unknown", forKey: QuotaCardStylePreferences.key)
        XCTAssertEqual(QuotaCardStylePreferences.read(from: shared), .skala)
        shared.set("original", forKey: QuotaCardStylePreferences.key)
        XCTAssertEqual(QuotaCardStylePreferences.read(from: shared), .skala)
        XCTAssertEqual(QuotaCardStylePreferences.read(from: nil), .skala)
        print("T84 | default skala, all 13 IDs, original/unknown/missing -> skala, repeated save, independent protected keys | passed requests=14")
    }

    func testT65ProcessOneWritesIsolatedPreference() throws {
        guard ProcessInfo.processInfo.environment["T65_RESTART_PHASE"] == "write" else { throw XCTSkip("显式跨进程持久化第一轮") }
        let localName = "T65-stage-restart-local-v1", sharedName = "T65-stage-restart-shared-v1"
        let local = try XCTUnwrap(UserDefaults(suiteName: localName)), shared = try XCTUnwrap(UserDefaults(suiteName: sharedName))
        local.removePersistentDomain(forName: localName); shared.removePersistentDomain(forName: sharedName)
        local.set(ProcessInfo.processInfo.processIdentifier, forKey: "test.writerPID")
        shared.set("pinned-sentinel", forKey: "intent.account")
        var reloads = 0
        QuotaCardStylePreferences.save(.watermark, to: local, shared: shared) { reloads += 1 }
        XCTAssertEqual(reloads, 1)
        XCTAssertTrue(local.synchronize()); XCTAssertTrue(shared.synchronize())
        print("T65 | process one | persisted watermark reloads=1 pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    func testT65ProcessTwoReadsAndCleansIsolatedPreference() throws {
        guard ProcessInfo.processInfo.environment["T65_RESTART_PHASE"] == "read" else { throw XCTSkip("显式跨进程持久化第二轮") }
        let localName = "T65-stage-restart-local-v1", sharedName = "T65-stage-restart-shared-v1"
        let local = try XCTUnwrap(UserDefaults(suiteName: localName)), shared = try XCTUnwrap(UserDefaults(suiteName: sharedName))
        defer { local.removePersistentDomain(forName: localName); shared.removePersistentDomain(forName: sharedName) }
        XCTAssertNotEqual(local.integer(forKey: "test.writerPID"), 0)
        XCTAssertNotEqual(local.integer(forKey: "test.writerPID"), Int(ProcessInfo.processInfo.processIdentifier))
        XCTAssertEqual(QuotaCardStylePreferences.read(from: local), .watermark)
        XCTAssertEqual(QuotaCardStylePreferences.read(from: shared), .watermark)
        XCTAssertEqual(shared.string(forKey: "intent.account"), "pinned-sentinel")
        var reloads = 0
        QuotaCardStylePreferences.save(.watermark, to: local, shared: shared) { reloads += 1 }
        XCTAssertEqual(reloads, 0)
        print("T65 | new process read | watermark retained, pinned retained, duplicate reloads=0 pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    func testT65ValidationPreferencesAreCleaned() throws {
        guard ProcessInfo.processInfo.environment["T65_CLEANUP_CHECK"] == "1" else { throw XCTSkip("本阶段结束只读清理核对") }
        for name in ["T65-stage-restart-local-v1", "T65-stage-restart-shared-v1"] {
            XCTAssertTrue((UserDefaults.standard.persistentDomain(forName: name) ?? [:]).isEmpty)
        }
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        for file in try FileManager.default.contentsOfDirectory(at: library.appendingPathComponent("Preferences"), includingPropertiesForKeys: nil) where file.pathExtension == "plist" {
            let name = file.deletingPathExtension().lastPathComponent
            if name.hasPrefix("T37-widget-") || name.hasPrefix("T65-local-") || name.hasPrefix("T65-shared-") {
                XCTAssertTrue((UserDefaults.standard.persistentDomain(forName: name) ?? [:]).isEmpty)
            }
        }
        try testT65ProductionDisplaySourceHasNoValidationOverride()
        print("T65 | cleanup readonly | T37/T65 isolated preferences empty, original production source | passed")
    }

    func testT65ProductionDisplaySourceHasNoValidationOverride() throws {
        #if DEBUG
        let root = try WidgetSnapshotStore.sharedDirectory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("T35-validation-session").path))
        XCTAssertEqual(try WidgetSnapshotStore.displayStore().resolvedURL(), try WidgetSnapshotStore.appGroupStore().resolvedURL())
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).contains {
            $0.lastPathComponent.hasPrefix("T35-validation-") && UUID(uuidString: String($0.lastPathComponent.dropFirst("T35-validation-".count))) != nil
        })
        print("T65 | production read path restored, no validation directory | passed")
        #endif
    }

    func testT64SharedRemainingInputPrecisionAndCatalogue() throws {
        XCTAssertEqual(QuotaCardStyle.allCases.count, 13)
        XCTAssertEqual(Set(QuotaCardStyle.allCases.map(\.rawValue)).count, 13)
        XCTAssertEqual(QuotaCardStyle.allCases.first, .skala)
        XCTAssertTrue(QuotaCardStyle.allCases.contains(.rave))
        XCTAssertNil(QuotaCardStyle(rawValue: "original"))
        XCTAssertEqual(QuotaCardStyle.rave.name, "霓虹派对")
        XCTAssertEqual(QuotaCardStyle.resolve(nil), .skala)
        XCTAssertEqual(QuotaCardStyle.resolve("original"), .skala)
        XCTAssertEqual(QuotaCardStyle.resolve("future"), .skala)
        for remaining in [0.0, 100, 0.1, 99.9, 33.33, 70.125] {
            let used = 100 - remaining
            let app = QuotaCardAmount(QuotaAmount.limited(try .init(used: used)))
            let widget = QuotaCardAmount(WidgetSnapshot.Amount.limited(usedPercent: used))
            XCTAssertEqual(app, widget)
            XCTAssertEqual(try XCTUnwrap(app.remainingFraction), remaining / 100, accuracy: 1e-12)
        }
        XCTAssertNil(QuotaCardAmount(QuotaAmount.unknown).remainingFraction)
        XCTAssertNil(QuotaCardAmount(WidgetSnapshot.Amount.unlimited).remainingFraction)
        XCTAssertEqual(QuotaCardSurface.smallWidget.motion(reduceMotion: false), .staticContent)
        XCTAssertEqual(QuotaCardSurface.mediumWidget.motion(reduceMotion: false), .staticContent)
        XCTAssertEqual(QuotaCardSurface.account.motion(reduceMotion: true), .staticContent)
    }

    func testT23NoFiveHourLimitRendersBothWidgetSizesInBothAppearances() throws {
        let snapshot = WidgetSnapshot(schemaVersion: 1, account: .init(id: UUID(),
            identity: "pro@example.invalid", plan: "Pro", isDemo: false, state: .available,
            subscriptionObservedAt: time, quotaObservedAt: time,
            weekly: .init(amount: .limited(usedPercent: 30), resetsAt: nil, observedAt: time),
            fiveHours: .init(amount: .unknown, resetsAt: nil, observedAt: time, isApplicable: false)))
        try snapshot.validate()
        for medium in [false, true] {
            for dark in [false, true] {
                let width: CGFloat = medium ? 338 : 158
                let view = SmallQuotaWidgetView(content: .snapshot(snapshot), medium: medium)
                    .frame(width: width, height: 158)
                    .background(Color("DesignCard"))
                    .environment(\.colorScheme, dark ? .dark : .light)
                let renderer = ImageRenderer(content: view); renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                let attachment = XCTAttachment(image: image)
                attachment.name = "T23-无5小时组件-\(medium ? "中" : "小")-\(dark ? "深" : "浅")"
                attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }


    func testRemainingAndUsedBarAgreeAtBoundariesAndMatchApp() throws {
        for used in [0.0, 30, 99.75, 100] {
            let amount = WidgetSnapshot.Amount.limited(usedPercent: used)
            XCTAssertEqual(QuotaWidgetContent.remainingFraction(amount), (100 - used) / 100)
            XCTAssertEqual(QuotaWidgetContent.amountText(amount), QuotaView.amountText(.limited(try .init(used: used))))
        }
        XCTAssertEqual(QuotaWidgetContent.amountText(.limited(usedPercent: 30)), "剩余 70%")
    }

    func testUnknownAndUnlimitedHaveNoInventedProgress() {
        XCTAssertNil(QuotaWidgetContent.remainingFraction(.unknown))
        XCTAssertNil(QuotaWidgetContent.remainingFraction(.unlimited))
        XCTAssertEqual(QuotaWidgetContent.amountText(.unknown), "未知")
        XCTAssertEqual(QuotaWidgetContent.amountText(.unlimited), "不限量")
    }

    func testEmptyUnfetchedAndFreeRemainDistinct() throws {
        let empty = QuotaWidgetContent.snapshot(.empty)
        let unfetched = QuotaWidgetContent.snapshot(fixture(state: .notFetched))
        let free = QuotaWidgetContent.snapshot(fixture(state: .notApplicable))
        XCTAssertEqual(empty.message, "添加账户")
        XCTAssertEqual(unfetched.message, "尚未获取额度")
        XCTAssertNotNil(unfetched.account)
        XCTAssertNil(free.message)
        XCTAssertEqual(free.account?.plan, "Free")
        XCTAssertNil(free.account?.quotaObservedAt)
        XCTAssertNil(free.account?.weekly)
    }

    func testSharedReaderKeepsIdentityBothValuesAndOriginalTimes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("T33-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WidgetSnapshotStore(fileURL: url), snapshot = fixture()
        try store.write(snapshot)
        let bytes = try Data(contentsOf: url)
        let content = QuotaWidgetContent.read(from: store)
        XCTAssertEqual(content, .snapshot(snapshot))
        XCTAssertEqual(content.account?.quotaObservedAt, time)
        XCTAssertEqual(content.account?.weekly?.amount.remainingPercent, 70)
        XCTAssertEqual(content.account?.fiveHours?.amount.remainingPercent, 85)
        // Even after these dates pass, rendering preserves the observation and the bytes.
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(content.account?.weekly?.resetsAt, time.addingTimeInterval(86400 * 5))
    }

    func testMissingOrCorruptPublicationIsNotSuccessfulEmptyAccount() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("T33-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = WidgetSnapshotStore(fileURL: url)
        XCTAssertEqual(QuotaWidgetContent.read(from: store), .notPublished)
        XCTAssertEqual(QuotaWidgetContent.read(from: store).message, "添加账户")
        try Data("broken".utf8).write(to: url)
        XCTAssertEqual(QuotaWidgetContent.read(from: store).message, "刷新失败")
        try store.write(.empty)
        XCTAssertEqual(QuotaWidgetContent.read(from: store).message, "添加账户")
    }

    func testCompactIdentityAndAddAccountRoute() {
        XCTAssertEqual(QuotaWidgetContent.compactIdentity("work@gmail.com"), "work")
        XCTAssertEqual(QuotaWidgetContent.compactIdentity("work@outlook.com"), "work")
        XCTAssertEqual(QuotaWidgetContent.compactIdentity("a.b+tag@example.invalid"), "a.b+tag")
        XCTAssertEqual(QuotaWidgetContent.compactIdentity("Codex 账户"), "Codex 账户")
        XCTAssertTrue(QuotaWidgetContent.isAddAccountURL(QuotaWidgetContent.addAccountURL))
        XCTAssertFalse(QuotaWidgetContent.isAddAccountURL(URL(string: "https://add-account")!))
        XCTAssertTrue(QuotaWidgetContent.notPublished.showsAddAccount)
        XCTAssertTrue(QuotaWidgetContent.snapshot(.empty).showsAddAccount)
        XCTAssertFalse(QuotaWidgetContent.unavailable.showsAddAccount)
        XCTAssertFalse(QuotaWidgetContent.snapshot(fixture(state: .notFetched)).showsAddAccount)
    }

    func testAppearancePublishesOnlyChangesAndResolvesManualPreference() throws {
        let suite = "WidgetAppearance-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        var reloads = 0
        WidgetAppearance.publish("dark", to: preferences) { reloads += 1 }
        WidgetAppearance.publish("dark", to: preferences) { reloads += 1 }
        XCTAssertEqual(reloads, 1)
        XCTAssertEqual(WidgetAppearance.colorScheme(preferences.string(forKey: WidgetAppearance.key)!), .dark)
        WidgetAppearance.publish("light", to: preferences) { reloads += 1 }
        XCTAssertEqual(WidgetAppearance.colorScheme(preferences.string(forKey: WidgetAppearance.key)!), .light)
        WidgetAppearance.publish("system", to: preferences) { reloads += 1 }
        XCTAssertNil(WidgetAppearance.colorScheme(preferences.string(forKey: WidgetAppearance.key)!))
        XCTAssertEqual(reloads, 3)
    }

    func testSmallWidgetIsolatedRendersLightDarkAndMissingFields() throws {
        var cachedFailure = fixture()
        cachedFailure = .init(schemaVersion: 1, account: cachedFailure.account.map { value in
            var value = value; value.failure = .refresh; return value
        })
        var blocked = try XCTUnwrap(cachedFailure.account)
        blocked.failure = .networkBlocked
        var firstFailure = try XCTUnwrap(fixture(state: .notFetched).account)
        firstFailure.failure = .refresh
        let cases: [(String, QuotaWidgetContent)] = [
            ("旧值刷新失败", .snapshot(cachedFailure)),
            ("旧值网络不达标", .snapshot(.init(schemaVersion: 1, account: blocked))),
            ("首次获取失败", .snapshot(.init(schemaVersion: 1, account: firstFailure))),
            ("70-85", .snapshot(fixture())),
            ("0-100", .snapshot(fixture(weekly: .limited(usedPercent: 100), five: .limited(usedPercent: 0)))),
            ("长标识-缺窗口时间", .snapshot(fixture(five: .unknown, reset: false, long: true))),
            ("不限量", .snapshot(fixture(weekly: .unlimited))),
            ("无账户", .snapshot(.empty)),
            ("尚未获取", .snapshot(fixture(state: .notFetched))),
            ("Free", .snapshot(fixture(state: .notApplicable))),
            ("读取失败", .unavailable)
        ]
        for (name, content) in cases {
            for medium in [false, true] {
            for dark in [false, true] {
                let width: CGFloat = medium ? 338 : 158
                let view = SmallQuotaWidgetView(content: content, medium: medium)
                    .frame(width: width, height: 158)
                    .background(Color("DesignCard"))
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size, CGSize(width: width, height: 158))
                let attachment = XCTAttachment(image: image)
                attachment.name = "T60账户选择-\(medium ? "中" : "小")-\(name)-\(dark ? "深" : "浅")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            }
        }
    }
}
