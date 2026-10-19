import XCTest
import SwiftUI
@testable import SubscriptionUsage

/// T107: Cursor's Grok Bot row on the account card, detail cards and small/medium
/// widget layouts (D-80). Isolated rendering only, not the real App or desktop.
@MainActor
final class GrokBotDisplayTests: XCTestCase {
    private let time = QuotaStyleLabView.referenceTime

    private func cursor(monthly: Double = 64, grokBot: Double?, grokBotTime: Date? = nil,
                        state: AccountQuotaState = .available) throws -> ConnectedAccount {
        let id = UUID(uuidString: "C0000000-0000-0000-0000-000000000107")!
        let scope = AccountScope(remoteAccountID: "fixture-cursor-user", kind: .personal)
        var account = ConnectedAccount(id: id, provider: .cursor, product: .cursorSubscription,
            remoteUserID: "fixture-cursor-user", verifiedEmail: "cursor@example.invalid", scope: scope,
            credentialRef: UUID(), generation: 1, quotaState: .available, subscription: .init(planType: "pro", observedAt: time))
        account.quotaSnapshot = CodexQuotaSnapshot(accountID: id, provider: .cursor, product: .cursorSubscription,
            scope: scope, generation: 1, planType: "pro", observedAt: time,
            weekly: .init(window: .monthly, amount: .limited(try .init(used: 100 - monthly)),
                          resetsAt: time.addingTimeInterval(86400 * 12), observedAt: time),
            fiveHours: CodexQuotaSnapshot.absentFiveHours(observedAt: time))
        switch state {
        case .available:
            account.grokBot = try grokBot.map { try .available(used: 100 - $0, resetsAt: time.addingTimeInterval(86400 * 3),
                                                               observedAt: grokBotTime ?? time) }
        case .notApplicable: account.grokBot = .notApplicable
        case .notFetched: account.grokBot = nil
        }
        return account
    }

    func testT107RowsProjectionAndDetailContent() throws {
        var rows: [String] = []
        let two = QuotaStyledInput(account: WidgetSnapshot.projecting([try cursor(grokBot: 24.5)]).account)
        XCTAssertEqual(two.windows.map(\.title), ["本月", "Grok Bot"]); XCTAssertEqual(two.windows.map(\.weekly), [true, false])
        XCTAssertEqual(two.windows[1].amount.nativeText, "25%"); XCTAssertNotNil(two.windows[1].resetsAt)
        XCTAssertEqual(two.singleWindow("grokBot").windows.map(\.title), ["Grok Bot"])
        rows.append("有额度 → 本月（主配色）＋Grok Bot（次行样式），24.5%显示25%（D-81）")
        XCTAssertEqual(QuotaStyledInput(account: WidgetSnapshot.projecting([try cursor(grokBot: 0)]).account).windows[1].amount.nativeText, "0%")
        rows.append("用完 → 0%")
        for (name, account) in [("从未取得", try cursor(grokBot: nil, state: .notFetched)),
                                ("无套餐内额度", try cursor(grokBot: nil, state: .notApplicable))] {
            XCTAssertEqual(QuotaStyledInput(account: WidgetSnapshot.projecting([account]).account).windows.map(\.title), ["本月"], name)
        }
        rows.append("从未取得／无套餐内额度 → 只有本月一行")
        // Failure keeps both trusted rows and shows the single short message.
        let failed = WidgetSnapshot.projecting([try cursor(grokBot: 24.5)], failures: [UUID(uuidString: "C0000000-0000-0000-0000-000000000107")!: .refresh])
        let failedInput = QuotaStyledInput(account: failed.account)
        XCTAssertEqual(failedInput.windows, two.windows); XCTAssertEqual(failedInput.message, "刷新失败")
        rows.append("失败 → 两行旧值保留＋刷新失败")
        // Codex is untouched.
        var codex = ConnectedAccount(verifiedEmail: "a@example.invalid", scope: .init(remoteAccountID: "a", kind: .personal), credentialRef: UUID())
        codex.quotaState = .available; codex.subscription = .init(planType: "plus", observedAt: time)
        codex.quotaSnapshot = CodexQuotaSnapshot(accountID: codex.id, provider: .openAI, product: .codexSubscription, scope: codex.scope,
            generation: 0, planType: "plus", observedAt: time,
            weekly: .init(window: .weekly, amount: .limited(try .init(used: 30)), resetsAt: nil, observedAt: time),
            fiveHours: .init(window: .fiveHours, amount: .limited(try .init(used: 60)), resetsAt: nil, observedAt: time))
        let codexSnapshot = WidgetSnapshot.projecting([codex])
        XCTAssertNil(codexSnapshot.account?.grokBot)
        XCTAssertEqual(QuotaStyledInput(account: codexSnapshot.account).windows.map(\.title), ["每周", "5 小时"])
        rows.append("Codex 仍为每周＋5 小时")
        // Widget publication: valid, and a Grok Bot change alone reloads the widget.
        let a = WidgetSnapshot.projecting([try cursor(grokBot: 24.5)]), b = WidgetSnapshot.projecting([try cursor(grokBot: 20)])
        try a.validate(); try b.validate()
        XCTAssertFalse(a.hasSameVisibleContent(as: b))
        XCTAssertEqual(try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(a)), a)
        rows.append("组件发布有效；只有Grok Bot变化也触发组件刷新")
        // Detail: the separate Grok Bot success time appears only after it fell behind.
        XCTAssertFalse(CodexDetailContent(account: try cursor(grokBot: 24.5)).rows.contains { $0.id == "grokBotUpdatedAt" })
        let behind = CodexDetailContent(account: try cursor(grokBot: 24.5, grokBotTime: time.addingTimeInterval(-3600)))
        XCTAssertEqual(behind.rows.map(\.title), ["账号", "更新时间", "Grok Bot 更新时间", "本月剩余", "Grok Bot 剩余"])
        rows.append("详情：Grok Bot失败后另列其原成功时间，平时不多一行")
        print("T107 | 两行数据 | " + rows.joined(separator: "；") + " | passed")
    }

    private func codex(weekly: QuotaAmount, fiveHours: QuotaAmount, fiveHoursApplicable: Bool? = nil) -> ConnectedAccount {
        var codex = ConnectedAccount(verifiedEmail: "a@example.invalid", scope: .init(remoteAccountID: "a", kind: .personal), credentialRef: UUID())
        codex.quotaState = .available; codex.subscription = .init(planType: "plus", observedAt: time)
        codex.quotaSnapshot = CodexQuotaSnapshot(accountID: codex.id, provider: .openAI, product: .codexSubscription, scope: codex.scope,
            generation: 0, planType: "plus", observedAt: time,
            weekly: .init(window: .weekly, amount: weekly, resetsAt: time.addingTimeInterval(86400 * 4), observedAt: time),
            fiveHours: .init(window: .fiveHours, amount: fiveHours, resetsAt: time.addingTimeInterval(3600),
                             observedAt: time, isApplicable: fiveHoursApplicable))
        return codex
    }

    /// T110 (D-81): every surface reads whole percents; the detail list adds exact two-decimal rows.
    func testT110WholePercentReadingsAndExactDetailRows() throws {
        var rows: [String] = []
        for (value, whole, precise) in [(75.4321, "75%", "75.43%"), (0.4, "0%", "0.40%"), (99.6, "100%", "99.60%"),
                                        (24.5, "25%", "24.50%"), (0, "0%", "0.00%"), (100, "100%", "100.00%"),
                                        (66.667, "67%", "66.67%"), (70.125, "70%", "70.13%")] {
            let amount = QuotaCardAmount.remaining(value)
            XCTAssertEqual(amount.nativeText, whole, "\(value)"); XCTAssertEqual(amount.preciseText, precise, "\(value)")
            XCTAssertEqual(try XCTUnwrap(amount.remainingFraction), value / 100, accuracy: 1e-12, "进度条仍按精确值")
            rows.append("\(value)→\(whole)／\(precise)")
        }
        XCTAssertEqual(QuotaCardAmount.unknown.nativeText, "未知"); XCTAssertNil(QuotaCardAmount.unknown.preciseText)
        XCTAssertEqual(QuotaCardAmount.unlimited.nativeText, "不限量"); XCTAssertNil(QuotaCardAmount.unlimited.preciseText)
        XCTAssertEqual(QuotaWidgetContent.amountText(.limited(usedPercent: 24.5678)), "剩余 75%")
        XCTAssertEqual(QuotaView.amountText(.limited(try .init(used: 24.5678))), "剩余 75%")
        // Detail: Codex five-hour then weekly (card order); Cursor monthly then Grok Bot.
        let both = CodexDetailContent(account: codex(weekly: .limited(try .init(used: 24.5679)), fiveHours: .limited(try .init(used: 0))))
        XCTAssertEqual(both.rows.map(\.title), ["账号", "重置额度", "更新时间", "5 小时剩余", "每周剩余"])
        XCTAssertEqual(both.rows.suffix(2).map(\.value), ["100.00%", "75.43%"])
        let noFive = CodexDetailContent(account: codex(weekly: .limited(try .init(used: 50)), fiveHours: .unknown, fiveHoursApplicable: false))
        XCTAssertEqual(noFive.rows.map(\.title), ["账号", "重置额度", "更新时间", "每周剩余"])
        let unknown = CodexDetailContent(account: codex(weekly: .unknown, fiveHours: .unlimited))
        XCTAssertEqual(unknown.rows.map(\.title), ["账号", "重置额度", "更新时间"], "未知、不限量不加行")
        let cursorRows = CodexDetailContent(account: try cursor(monthly: 33.333, grokBot: 24.5)).rows
        XCTAssertEqual(cursorRows.map(\.title), ["账号", "更新时间", "本月剩余", "Grok Bot 剩余"])
        XCTAssertEqual(cursorRows.suffix(2).map(\.value), ["33.33%", "24.50%"])
        XCTAssertEqual(CodexDetailContent(account: try cursor(grokBot: nil, state: .notApplicable)).rows.map(\.title), ["账号", "更新时间", "本月剩余"])
        rows.append("详情：Codex 5 小时剩余→每周剩余；无5小时只有每周剩余；未知／不限量不加；Cursor 本月剩余→Grok Bot 剩余；无Grok Bot不加")
        print("T110 | 百分比显示 | " + rows.joined(separator: "；") + " | passed")
    }

    /// T110 isolated rendering of the real detail panel; images go to T110_OUT when set.
    func testT110DetailPanelRendering() async throws {
        let out = ProcessInfo.processInfo.environment["T110_OUT"].map { URL(fileURLWithPath: $0) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 414, height: 1100)
        defer { window.isHidden = true; window.rootViewController = nil }
        let accounts = [("codex", codex(weekly: .limited(try .init(used: 24.5679)), fiveHours: .limited(try .init(used: 0.4)))),
                        ("cursor", try cursor(monthly: 33.333, grokBot: 24.5))]
        for (name, account) in accounts {
            for scheme: ColorScheme in [.light, .dark] {
                for style in [QuotaCardStyle.allCases[0], QuotaCardStyle.allCases[5], QuotaCardStyle.allCases[12]] {
                    let host = UIHostingController(rootView: CodexDetailPanel(account: account)
                        .environment(\.quotaCardStyle, style).environment(\.colorScheme, scheme)
                        .environment(\.nativeQuotaStatic, true).environment(\.locale, Locale(identifier: "zh_CN")))
                    window.rootViewController = host; window.makeKeyAndVisible()
                    try await Task.sleep(for: .milliseconds(400))
                    window.layoutIfNeeded()
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    if let out { try write(image, out, "T110-detail-\(name)-\(style.rawValue)-\(scheme == .dark ? "dark" : "light").png") }
                }
            }
        }
    }

    /// 13 styles × account card / detail cards / small / medium × light/dark, plus
    /// accessibility5. Images go to GROK_GALLERY_OUT when set (isolated rendering).
    func testT107GrokBotGallery() throws {
        let out = ProcessInfo.processInfo.environment["GROK_GALLERY_OUT"].map { URL(fileURLWithPath: $0) }
        let id = UUID(uuidString: "C0000000-0000-0000-0000-000000000107")!
        let scenarios: [(String, ConnectedAccount, [UUID: WidgetSnapshot.Failure])] = [
            ("two", try cursor(grokBot: 24.5), [:]),
            ("ends", try cursor(monthly: 100, grokBot: 0), [:]),
            ("decimal", try cursor(monthly: 33.33, grokBot: 66.667), [:]),
            ("single", try cursor(grokBot: nil, state: .notApplicable), [:]),
            ("failure", try cursor(grokBot: 24.5), [id: .refresh]),
        ]
        var renders = 0
        for dark in [false, true] {
            for (name, account, failures) in scenarios {
                var rows: [UIImage] = []
                for style in QuotaCardStyle.allCases {
                    let snapshot = WidgetSnapshot.projecting([account], failures: failures)
                    let input = QuotaStyledInput(account: snapshot.account)
                    let cells: [AnyView] = [
                        AnyView(QuotaStyledCard(style: style, input: input, now: time).frame(width: 366)),
                        AnyView(VStack(spacing: 8) { ForEach(input.windows) { w in
                            QuotaStyledCard(style: style, input: input.singleWindow(w.id), surface: .detail, now: self.time) } }.frame(width: 366)),
                        AnyView(SmallQuotaWidgetView(content: .snapshot(snapshot))
                            .frame(width: 170, height: 170).background(CompactQuotaBackground(style: style, widget: true))
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))),
                        AnyView(SmallQuotaWidgetView(content: .snapshot(snapshot), medium: true)
                            .frame(width: 364, height: 170).background(CompactQuotaBackground(style: style, widget: true))
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))),
                    ]
                    let row = HStack(alignment: .top, spacing: 12) { ForEach(0..<cells.count, id: \.self) { cells[$0] } }
                        .padding(10).background(Color.quotaHex(dark ? "1c1c1e" : "e8e8ec"))
                        .environment(\.quotaCardStyle, style).environment(\.colorScheme, dark ? .dark : .light)
                        .environment(\.nativeQuotaStatic, true).environment(\.locale, Locale(identifier: "zh_CN"))
                    let r = ImageRenderer(content: row); r.scale = 1
                    rows.append(try XCTUnwrap(r.uiImage)); renders += 4
                }
                if let out { try write(stack(rows), out, "grok-\(name)-\(dark ? "dark" : "light").png") }
            }
            // Largest accessibility size on the account card and both widget layouts.
            var large: [UIImage] = []
            for style in QuotaCardStyle.allCases {
                let snapshot = WidgetSnapshot.projecting([try cursor(monthly: 33.33, grokBot: 66.667)])
                let input = QuotaStyledInput(account: snapshot.account)
                let row = HStack(alignment: .top, spacing: 12) {
                    QuotaStyledCard(style: style, input: input, now: time).frame(width: 338)
                    QuotaStyledCard(style: style, input: input, surface: .smallWidget, now: time).frame(width: 158, height: 158)
                    QuotaStyledCard(style: style, input: input, surface: .mediumWidget, now: time).frame(width: 338, height: 158)
                }
                .padding(10).background(Color.quotaHex(dark ? "1c1c1e" : "e8e8ec"))
                .environment(\.quotaCardStyle, style).environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.dynamicTypeSize, .accessibility5).environment(\.nativeQuotaStatic, true)
                let r = ImageRenderer(content: row); r.scale = 1
                large.append(try XCTUnwrap(r.uiImage)); renders += 3
            }
            if let out { try write(stack(large), out, "grok-large-\(dark ? "dark" : "light").png") }
        }
        print("T107 | Grok Bot隔离渲染 | 14款 x 账户卡/详情卡/小号/中号 x 5种情况 x 浅深 ＋ 最大字号 | renders=\(renders)")
    }

    private func write(_ image: UIImage, _ out: URL, _ name: String) throws {
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent(name))
    }

    private func stack(_ images: [UIImage]) -> UIImage {
        let width = images.map(\.size.width).max() ?? 1
        let height = images.reduce(0) { $0 + $1.size.height }
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { _ in
            var y: CGFloat = 0
            for image in images { image.draw(at: CGPoint(x: 0, y: y)); y += image.size.height }
        }
    }
}
