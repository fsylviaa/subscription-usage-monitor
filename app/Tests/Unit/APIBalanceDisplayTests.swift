import XCTest
import SwiftUI
@testable import SubscriptionUsage

/// T115: balance amounts on the account card, detail and both widget sizes (D-82).
@MainActor
final class APIBalanceDisplayTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_791_590_400)

    private func account(_ provider: ProviderID, _ amounts: [BalanceAmount]?, tail: String = "a1b2") -> ConnectedAccount {
        let key = APIBalanceStoreTests.key(tail)
        var value = ConnectedAccount(provider: provider,
            product: provider == .openRouter ? .openRouterCredits : .deepSeekBalance,
            remoteUserID: key.fingerprint(for: provider), displayName: key.masked,
            scope: .init(remoteAccountID: key.fingerprint(for: provider), kind: .personal), credentialRef: UUID(),
            quotaState: amounts == nil ? .notFetched : .available)
        value.balance = amounts.map { APIBalanceSnapshot(amounts: $0, observedAt: time) }
        return value
    }

    private func d(_ text: String) -> Decimal { Decimal(string: text)! }

    func testMoneyFormattingRoundsHalfUpToTwoDecimals() {
        let cases: [(String, String, String)] = [
            ("12.345", "USD", "$12.35"), ("12.344", "USD", "$12.34"), ("0", "USD", "$0.00"), ("0", "CNY", "¥0.00"),
            ("1234.5", "USD", "$1234.50"), ("9.995", "USD", "$10.00"), ("0.005", "CNY", "¥0.01"),
            ("0.0049", "CNY", "¥0.00"), ("-1.005", "CNY", "-¥1.01"), ("5", "EUR", "EUR 5.00"),
            ("123456789.987654321", "CNY", "¥123456789.99"),
        ]
        for (value, currency, expected) in cases {
            XCTAssertEqual(BalanceAmount.money(d(value), currency: currency), expected, value)
        }
        print("T115 | 金额格式 | " + cases.map { "\($0.0) \($0.1)→\($0.2)" }.joined(separator: "；") + " | passed")
    }

    func testCardAndWidgetInputShowBalanceOnly() throws {
        let or = account(.openRouter, [BalanceAmount(currency: "USD", total: d("12.3456"))])
        var input = QuotaStyledInput(account: WidgetSnapshot.projecting([or]).account)
        XCTAssertEqual(input.platform, .openRouter)
        XCTAssertEqual(input.windows.map(\.id), ["balance.USD"])
        XCTAssertEqual(input.windows.map(\.title), ["余额"])
        XCTAssertEqual(input.windows.first?.amount.nativeText, "$12.35")
        XCTAssertNil(input.windows.first?.amount.remainingFraction, "no bar, no percentage")
        XCTAssertNil(input.windows.first?.resetsAt)
        XCTAssertNil(input.message)

        // Failure keeps the trusted amount; first failure has nothing to keep.
        input = QuotaStyledInput(account: WidgetSnapshot.projecting([or], failures: [or.id: .refresh]).account)
        XCTAssertEqual(input.windows.first?.amount.nativeText, "$12.35")
        XCTAssertEqual(input.message, "刷新失败")
        let never = account(.openRouter, nil)
        XCTAssertEqual(QuotaStyledInput(account: WidgetSnapshot.projecting([never]).account).message, "尚未获取余额")
        XCTAssertEqual(QuotaStyledInput(account: WidgetSnapshot.projecting([never], failures: [never.id: .refresh]).account).message, "刷新失败")
        XCTAssertEqual(QuotaStyledInput(account: WidgetSnapshot.projecting([or], failures: [or.id: .networkBlocked]).account).message,
                       "网络不达标，无法更新")

        let ds = account(.deepSeek, [BalanceAmount(currency: "CNY", total: d("66.6"), toppedUp: 60, granted: d("6.6")),
                                    BalanceAmount(currency: "USD", total: 0)])
        let dsInput = QuotaStyledInput(account: WidgetSnapshot.projecting([ds]).account)
        XCTAssertEqual(dsInput.windows.map(\.amount.nativeText), ["¥66.60", "$0.00"], "0 shown as is, one row per currency")
        XCTAssertEqual(dsInput.windows.map(\.id), ["balance.CNY", "balance.USD"])

        // Widget: no identity, no time on the card; D-64 entity names the masked key.
        let snapshot = WidgetSnapshot.projecting([or, ds])
        XCTAssertEqual(snapshot.allAccounts.map(\.identity), ["sk-…a1b2", "sk-…a1b2"])
        let entity = WidgetAccountEntity(account: snapshot.allAccounts[1])
        XCTAssertEqual(entity.identity, "sk-…a1b2"); XCTAssertEqual(entity.detail, "DeepSeek")
        XCTAssertNoThrow(try snapshot.validate())
    }

    func testDetailRowsPerPlatform() {
        let or = account(.openRouter, [BalanceAmount(currency: "USD", total: d("12.34"))])
        XCTAssertEqual(CodexDetailContent(account: or).rows.map(\.title), ["账号", "更新时间"])
        XCTAssertEqual(CodexDetailContent(account: or).rows.first?.value, "sk-…a1b2")

        let ds = account(.deepSeek, [BalanceAmount(currency: "CNY", total: d("110"), toppedUp: d("100"), granted: d("10.005"))])
        let rows = CodexDetailContent(account: ds).rows
        XCTAssertEqual(rows.map(\.title), ["账号", "更新时间", "充值余额", "赠送余额"])
        XCTAssertEqual(rows.suffix(2).map(\.value), ["¥100.00", "¥10.01"])

        let two = account(.deepSeek, [BalanceAmount(currency: "CNY", total: 1, toppedUp: 1),
                                     BalanceAmount(currency: "USD", total: 2, granted: 2)])
        XCTAssertEqual(CodexDetailContent(account: two).rows.map(\.title),
                       ["账号", "更新时间", "充值余额（CNY）", "赠送余额（USD）"], "unknown parts are hidden")
        XCTAssertEqual(CodexDetailContent(account: account(.deepSeek, nil)).rows.map(\.title), ["账号"])
        XCTAssertEqual(QuotaView.deletionMessage(for: ds), "仅删除本 App 保存的 key，不会撤销平台上的 key。")
        print("T115 | 详情行 | OpenRouter：账号、更新时间；DeepSeek：另列充值余额、赠送余额（多币种带币种，缺的隐藏）；未获取只显示账号 | passed")
    }

    func testPlatformMarksFillTheirCanvas() {
        for platform in [QuotaPlatform.openRouter, .deepSeek] {
            let bounds = PlatformMarkShape(platform: platform).path(in: CGRect(x: 0, y: 0, width: 24, height: 24)).boundingRect
            XCTAssertGreaterThan(bounds.width, 18, "\(platform)")
            XCTAssertGreaterThan(bounds.height, 10, "\(platform)")
            XCTAssertGreaterThanOrEqual(bounds.minX, -0.5); XCTAssertLessThanOrEqual(bounds.maxX, 24.5)
        }
    }

    /// 13 styles × account card / detail card / small / medium × light/dark × both platforms,
    /// plus failure, long amounts and the largest text size. Images go to T115_OUT when set.
    func testT115BalanceGallery() throws {
        let out = ProcessInfo.processInfo.environment["T115_OUT"].map { URL(fileURLWithPath: $0) }
        let failedOR = account(.openRouter, [BalanceAmount(currency: "USD", total: d("12.34"))])
        let scenarios: [(String, ConnectedAccount, [UUID: WidgetSnapshot.Failure])] = [
            ("openrouter", account(.openRouter, [BalanceAmount(currency: "USD", total: d("12.3456"))]), [:]),
            ("deepseek", account(.deepSeek, [BalanceAmount(currency: "CNY", total: d("66.6"), toppedUp: 60, granted: d("6.6"))]), [:]),
            ("deepseek-two-long", account(.deepSeek, [BalanceAmount(currency: "CNY", total: d("123456.78")),
                                                       BalanceAmount(currency: "USD", total: 0)]), [:]),
            ("openrouter-failed", failedOR, [failedOR.id: .refresh]),
            ("openrouter-never", account(.openRouter, nil), [:]),
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
                        AnyView(QuotaStyledCard(style: style, input: input, surface: .detail, now: time).frame(width: 366)),
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
                if let out { try write(stack(rows), out, "T115-\(name)-\(dark ? "dark" : "light").png") }
            }
            var large: [UIImage] = []
            for style in QuotaCardStyle.allCases {
                let snapshot = WidgetSnapshot.projecting([scenarios[2].1])
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
            if let out { try write(stack(large), out, "T115-large-\(dark ? "dark" : "light").png") }
        }
        print("T115 | 余额隔离渲染 | 13款 x 账户卡/详情卡/小号/中号 x 5种情况 x 浅深 ＋ 最大字号 | renders=\(renders)")
    }

    /// The real detail panel for both platforms; images go to T115_OUT when set.
    func testT115DetailPanelRendering() async throws {
        let out = ProcessInfo.processInfo.environment["T115_OUT"].map { URL(fileURLWithPath: $0) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 414, height: 900)
        defer { window.isHidden = true; window.rootViewController = nil }
        let accounts = [("openrouter", account(.openRouter, [BalanceAmount(currency: "USD", total: d("12.34"))])),
                        ("deepseek", account(.deepSeek, [BalanceAmount(currency: "CNY", total: d("66.6"), toppedUp: 60, granted: d("6.6"))]))]
        for (name, account) in accounts {
            for scheme: ColorScheme in [.light, .dark] {
                for style in [QuotaCardStyle.allCases[0], QuotaCardStyle.allCases[11], QuotaCardStyle.allCases[12]] {
                    let host = UIHostingController(rootView: CodexDetailPanel(account: account)
                        .environment(\.quotaCardStyle, style).environment(\.colorScheme, scheme)
                        .environment(\.nativeQuotaStatic, true).environment(\.locale, Locale(identifier: "zh_CN")))
                    window.rootViewController = host; window.makeKeyAndVisible()
                    try await Task.sleep(for: .milliseconds(400))
                    window.layoutIfNeeded()
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    if let out { try write(image, out, "T115-detail-\(name)-\(style.rawValue)-\(scheme == .dark ? "dark" : "light").png") }
                }
            }
        }
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
