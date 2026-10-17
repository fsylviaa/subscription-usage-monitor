import XCTest
import SwiftUI
@testable import SubscriptionUsage

@MainActor
final class NativeQuotaStyleTests: XCTestCase {
    func testT66Skala() throws { try verify(.skala, task: 66) }

    func testT67Capsule() throws { try verify(.capsule, task: 67) }

    func testT68Ticks() throws { try verify(.ticks, task: 68) }

    func testT69Dials() throws { try verify(.dials, task: 69) }

    func testT70Island() throws { try verify(.island, task: 70) }

    func testT71Blocks() throws { try verify(.blocks, task: 71) }

    func testT72Liquid() throws { try verify(.liquid, task: 72) }

    func testT73Ticket() throws { try verify(.ticket, task: 73) }

    func testT74Journal() throws { try verify(.journal, task: 74) }

    func testT75Glass() throws { try verify(.glass, task: 75) }

    func testT76Panels() throws { try verify(.panels, task: 76) }

    func testT77Watermark() throws { try verify(.watermark, task: 77) }

    func testT84Rave() throws { try verify(.rave, task: 84) }

    /// D-76 graphics: 0% has no remaining emphasis, 100% is fully emphasised,
    /// and a sub-grain change still moves the boundary (no whole-grain steps).
    func testD76CompactBarsEndpointsAndContinuity() throws {
        func png(_ style: QuotaCardStyle, _ f: Double, mini: Bool, dark: Bool, secondary: Bool = false) throws -> Data {
            let view = CompactQuotaBar(style: style, fraction: f, mini: mini, secondary: secondary, phase: nil)
                .frame(width: mini ? 142 : 300, height: mini ? 16 : 32)
                .environment(\.colorScheme, dark ? .dark : .light)
            let r = ImageRenderer(content: view); r.scale = 2
            return try XCTUnwrap(r.uiImage?.pngData())
        }
        var checks = 0
        for style in QuotaCardStyle.allCases where style != .dials {
            for dark in [false, true] {
                for mini in [false, true] {
                    let zero = try png(style, 0, mini: mini, dark: dark), full = try png(style, 1, mini: mini, dark: dark)
                    XCTAssertNotEqual(zero, full, "\(style) 0与100须不同")
                    XCTAssertNotEqual(try png(style, 0.33, mini: mini, dark: dark), try png(style, 0.34, mini: mini, dark: dark), "\(style) 小数须连续")
                    XCTAssertEqual(try png(style, -0.2, mini: mini, dark: dark), zero, "\(style) 越界按0")
                    XCTAssertEqual(try png(style, 1.3, mini: mini, dark: dark), full, "\(style) 越界按100")
                    checks += 4
                }
            }
        }
        XCTAssertNotEqual(try png(.panels, 0.5, mini: false, dark: false, secondary: true), try png(.panels, 0.5, mini: false, dark: false))
        for dark in [false, true] {
            func dial(_ f: Double) throws -> Data {
                let r = ImageRenderer(content: CompactDial(fraction: f).frame(width: 160, height: 150).environment(\.colorScheme, dark ? .dark : .light))
                r.scale = 2; return try XCTUnwrap(r.uiImage?.pngData())
            }
            XCTAssertNotEqual(try dial(0), try dial(1)); XCTAssertNotEqual(try dial(0.33), try dial(0.34)); checks += 2
        }
        print("D76 | compact bars | 12 styles x 2 themes x 2 densities + dial | endpoints, continuity, clamping | checks=\(checks)")
    }

    /// Isolated render of the real widget view (not the desktop): 13 styles,
    /// small 170×170 and medium 364×170 as on the comparison page, two accounts.
    func testD76WidgetGallery() throws {
        func account(_ remaining: Double, five: Bool = true) -> WidgetSnapshot.Account {
            let t = QuotaStyleLabView.referenceTime
            return .init(id: UUID(), identity: "gallery@example.invalid", plan: "Plus", isDemo: false, state: .available,
                         subscriptionObservedAt: t, quotaObservedAt: t,
                         weekly: .init(amount: .limited(usedPercent: 100 - remaining), resetsAt: t.addingTimeInterval(86400), observedAt: t),
                         fiveHours: .init(amount: five ? .limited(usedPercent: 100 - remaining) : .unknown, resetsAt: nil, observedAt: t, isApplicable: five))
        }
        for dark in [false, true] {
            var rows: [UIImage] = []
            for style in QuotaCardStyle.allCases {
                let cells = [(90.0, false), (70.0, false), (90.0, true), (70.0, true)].map { value, medium in
                    SmallQuotaWidgetView(content: .snapshot(.init(schemaVersion: 1, account: account(value))), medium: medium)
                        .frame(width: medium ? 364 : 170, height: 170)
                        .background(CompactQuotaBackground(style: style, widget: true))
                        .modifier(CompactWidgetChrome(style: style, shape: RoundedRectangle(cornerRadius: 22, style: .continuous)))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                let row = HStack(spacing: 16) { ForEach(0..<4, id: \.self) { cells[$0] } }
                    .padding(12).background(Color.quotaHex("4a5470"))
                    .environment(\.quotaCardStyle, style).environment(\.colorScheme, dark ? .dark : .light)
                let r = ImageRenderer(content: row); r.scale = 2
                let image = try XCTUnwrap(r.uiImage)
                let again = try XCTUnwrap(ImageRenderer(content: row).uiImage)
                XCTAssertNotNil(again)
                rows.append(image)
            }
            attach(stack(rows, labels: QuotaCardStyle.allCases.map(\.name)), "D76-组件隔离渲染-\(dark ? "dark" : "light")")
            for style in [QuotaCardStyle.skala, .dials, .panels, .rave] {
                let only = SmallQuotaWidgetView(content: .snapshot(.init(schemaVersion: 1, account: account(42.5, five: false))), medium: true)
                    .frame(width: 364, height: 170).background(CompactQuotaBackground(style: style, widget: true))
                    .environment(\.quotaCardStyle, style).environment(\.colorScheme, dark ? .dark : .light)
                attach(try XCTUnwrap(ImageRenderer(content: only).uiImage), "D76-组件-仅每周-\(style.rawValue)-\(dark ? "dark" : "light")")
            }
        }
    }

    /// No visible “剩余” on any surface; VoiceOver labels keep it.
    func testD76NoVisibleRemainingWordAndAccessibleLabel() throws {
        let input = QuotaStyledInput(plan: "Plus", windows: [.init(weekly: true, amount: .remaining(90), resetsAt: nil),
                                                           .init(weekly: false, amount: .remaining(70), resetsAt: nil)])
        for style in QuotaCardStyle.allCases {
            XCTAssertFalse(input.windows[0].amount.nativeText.contains("剩余"))
            for surface in [QuotaCardSurface.account, .detail] {
                let r = ImageRenderer(content: QuotaStyledCard(style: style, input: surface == .detail ? input.singleWindow("weekly") : input, surface: surface)
                    .frame(width: 380).environment(\.nativeQuotaStatic, true))
                XCTAssertNotNil(r.uiImage)
            }
        }
        XCTAssertEqual(QuotaCardAmount.remaining(70.125).nativeText, "70%")
    }

    private func verify(_ style: QuotaCardStyle, task: Int) throws {
        let time = QuotaStyleLabView.referenceTime
        let surfaces: [QuotaCardSurface] = [.account, .detail, .smallWidget, .mediumWidget]
        let values = [0.0, 100, 0.1, 99.9, 33.33, 70.125]
        var renders = 0
        for dark in [false, true] {
            for scenario in ["normal", "endpoints", "weekly", "empty", "unknown", "unlimited", "first", "failure", "long"] {
                let account = QuotaStyleLabView.fixtureAccount(scenario: scenario)
                try WidgetSnapshot(schemaVersion: 1, account: account).validate()
                let input = QuotaStyledInput(account: account)
                let before = input
                var images: [UIImage] = []
                for surface in surfaces {
                    let detail = surface == .detail
                    let widget = surface == .smallWidget || surface == .mediumWidget
                    let width: CGFloat = surface == .smallWidget ? 158 : surface == .mediumWidget ? 338 : 366
                    let view = QuotaStyledCard(style: style, input: detail ? input.singleWindow(input.windows.first?.id ?? "weekly") : input,
                        surface: surface, now: time)
                        .frame(width: width, height: widget ? 158 : nil)
                        .environment(\.colorScheme, dark ? .dark : .light)
                        .environment(\.nativeQuotaStatic, true)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    let renderer = ImageRenderer(content: view); renderer.scale = 2
                    let image = try XCTUnwrap(renderer.uiImage)
                    XCTAssertGreaterThan(image.size.height, 20); images.append(image); renders += 1
                    XCTAssertEqual(input, before)
                }
                attach(stack(images, labels: ["账户整卡", "详情单窗口", "小号布局（非桌面）", "中号布局（非桌面）"]),
                       "T\(task)-\(dark ? "dark" : "light")-\(scenario)")
                if scenario == "failure" {
                    let normal = QuotaStyleLabView.fixture(scenario: "normal")
                    XCTAssertEqual(input.windows, normal.windows); XCTAssertEqual(input.lastSuccess, normal.lastSuccess)
                    XCTAssertEqual(input.message, "刷新失败")
                }
                if scenario == "weekly" { XCTAssertEqual(input.windows.map(\.id), ["weekly"]) }
                if scenario == "empty" || scenario == "first" { XCTAssertTrue(input.windows.isEmpty) }
                if scenario == "unknown" { XCTAssertNil(input.windows.first?.amount.remainingFraction) }
            }
            for surface in surfaces {
                let widget = surface == .smallWidget || surface == .mediumWidget
                let input = QuotaStyleLabView.fixture(scenario: "long")
                let view = QuotaStyledCard(style: style, input: surface == .detail ? input.singleWindow("weekly") : input, surface: surface, now: time)
                    .frame(width: surface == .smallWidget ? 158 : 338, height: widget ? 158 : nil)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .environment(\.dynamicTypeSize, .accessibility5)
                    .environment(\.nativeQuotaStatic, true)
                let r = ImageRenderer(content: view); r.scale = 2
                let image = try XCTUnwrap(r.uiImage)
                attach(image, "T\(task)-\(dark ? "dark" : "light")-large-\(String(describing: surface))"); renders += 1
            }
            var graphs: [UIImage] = []
            for value in values {
                let input = QuotaCardAmount(WidgetSnapshot.Amount.limited(usedPercent: 100 - value))
                XCTAssertEqual(try XCTUnwrap(input.remainingFraction), value / 100, accuracy: 1e-12)
                let graphic: AnyView = style == .dials ? AnyView(CompactDial(fraction: value / 100).frame(width: 160, height: 150))
                    : AnyView(CompactQuotaBar(style: style, fraction: value / 100, phase: nil).frame(width: 400, height: 32))
                let r = ImageRenderer(content: graphic.environment(\.colorScheme, dark ? .dark : .light))
                r.scale = 2; graphs.append(try XCTUnwrap(r.uiImage)); renders += 1
            }
            XCTAssertNotEqual(graphs[0].pngData(), graphs[1].pngData(), "0与100须实际不同")
            attach(stack(graphs, labels: values.map { "剩余\($0)%" }), "T\(task)-\(dark ? "dark" : "light")-precision")
        }
        let old = QuotaStyleLabView.fixture(scenario: "normal")
        let expired = old.windows.map { NativeQuotaReset.text($0.resetsAt, now: time.addingTimeInterval(86400 * 7)) }
        XCTAssertTrue(expired.allSatisfy { $0 == "已到预计时间" })
        XCTAssertEqual(old.windows.first?.amount.nativeText, "70%")
        XCTAssertEqual(QuotaCardSurface.smallWidget.motion(reduceMotion: false), .staticContent)
        XCTAssertEqual(QuotaCardSurface.mediumWidget.motion(reduceMotion: false), .staticContent)
        XCTAssertEqual(QuotaCardSurface.account.motion(reduceMotion: true), .staticContent)
        print("T\(task) | \(style.rawValue) | native ImageRenderer \(renders) renders | 2 themes, 4 surfaces, 9 states, accessibility5, 6 precision values | passed")
    }
    private func attach(_ image: UIImage, _ name: String) {
        let a = XCTAttachment(image: image); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func stack(_ images: [UIImage], labels: [String]) -> UIImage {
        let width = images.map(\.size.width).max() ?? 366
        let height = images.reduce(0) { $0 + $1.size.height + 30 }
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height)).image { ctx in
            UIColor(white: 0.88, alpha: 1).setFill(); ctx.fill(CGRect(x: 0,y: 0,width: width,height: height))
            var y: CGFloat = 0
            for (i,image) in images.enumerated() {
                (labels[i] as NSString).draw(at: CGPoint(x: 8,y: y+5), withAttributes: [.font:UIFont.systemFont(ofSize: 12),.foregroundColor:UIColor.black])
                image.draw(at: CGPoint(x: 0,y: y+25)); y += image.size.height + 30
            }
        }
    }
}
