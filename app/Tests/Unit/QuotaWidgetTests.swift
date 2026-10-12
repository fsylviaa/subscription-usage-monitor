import XCTest
import SwiftUI
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
            XCTAssertEqual(QuotaWidgetContent.usedFraction(amount), used / 100)
            XCTAssertEqual(QuotaWidgetContent.amountText(amount), QuotaView.amountText(.limited(try .init(used: used))))
        }
        XCTAssertEqual(QuotaWidgetContent.amountText(.limited(usedPercent: 30)), "剩余 70%")
    }

    func testUnknownAndUnlimitedHaveNoInventedProgress() {
        XCTAssertNil(QuotaWidgetContent.usedFraction(.unknown))
        XCTAssertNil(QuotaWidgetContent.usedFraction(.unlimited))
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
