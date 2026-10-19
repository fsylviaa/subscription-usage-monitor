import XCTest
import SwiftUI
import CryptoKit
@testable import SubscriptionUsage

/// T91: Cursor platform and the single “本月” window across every display surface,
/// with fixed in-memory samples only (no login, no network).
@MainActor
final class CursorDisplayTests: XCTestCase {
    private let time = QuotaStyleLabView.referenceTime

    private func cursorAccount(remaining: Double?, state: AccountQuotaState = .available) throws -> ConnectedAccount {
        let id = UUID(uuidString: "C0000000-0000-0000-0000-000000000001")!
        let scope = AccountScope(remoteAccountID: "fixture-cursor-user", kind: .personal)
        var account = ConnectedAccount(id: id, provider: .cursor, product: .cursorSubscription,
            remoteUserID: "fixture-cursor-user", verifiedEmail: "cursor@example.invalid", scope: scope,
            credentialRef: UUID(), generation: 2, quotaState: state,
            subscription: .init(planType: "pro", observedAt: time))
        guard state == .available else { return account }
        let amount: QuotaAmount = try remaining.map { .limited(try .init(used: 100 - $0)) } ?? .unknown
        account.quotaSnapshot = CodexQuotaSnapshot(accountID: id, provider: .cursor, product: .cursorSubscription,
            scope: scope, generation: 2, planType: "pro", observedAt: time,
            weekly: .init(window: .monthly, amount: amount, resetsAt: time.addingTimeInterval(86400 * 12), observedAt: time),
            fiveHours: CodexQuotaSnapshot.absentFiveHours(observedAt: time))
        return account
    }

    private func codexAccount() throws -> ConnectedAccount {
        let id = UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!
        let scope = AccountScope(remoteAccountID: "fixture-account-a", kind: .personal)
        var account = ConnectedAccount(id: id, remoteUserID: "fixture-user-a", verifiedEmail: "a@example.invalid",
            scope: scope, credentialRef: UUID(), generation: 3, quotaState: .available,
            subscription: .init(planType: "plus", observedAt: time, resetCardCount: 2))
        account.quotaSnapshot = CodexQuotaSnapshot(accountID: id, provider: .openAI, product: .codexSubscription,
            scope: scope, generation: 3, planType: "plus", observedAt: time,
            weekly: .init(window: .weekly, amount: .limited(try .init(used: 30)), resetsAt: time.addingTimeInterval(86400), observedAt: time),
            fiveHours: .init(window: .fiveHours, amount: .limited(try .init(used: 60)), resetsAt: time.addingTimeInterval(3600), observedAt: time))
        return account
    }

    func testT91CursorFixedInputsProjectToOneMonthlyWindow() throws {
        var rows: [String] = []
        for value in [0.0, 100, 33.33, 70.125] {
            let projected = try XCTUnwrap(WidgetSnapshot.projecting([try cursorAccount(remaining: value)]).account)
            try WidgetSnapshot(schemaVersion: 1, account: projected).validate()
            let input = QuotaStyledInput(account: projected)
            XCTAssertEqual(input.platform, .cursor)
            XCTAssertEqual(input.windows.map(\.id), ["monthly"])
            XCTAssertEqual(input.windows.map(\.title), ["本月"])
            XCTAssertTrue(input.windows[0].weekly, "本月沿用主窗口配色")
            XCTAssertEqual(try XCTUnwrap(input.windows[0].amount.remainingFraction), value / 100, accuracy: 1e-12)
            XCTAssertNil(input.message)
            XCTAssertEqual(WidgetAccountEntity(account: projected).detail, "Cursor")
            rows.append("剩余\(value) → 本月 \(input.windows[0].amount.nativeText)")
        }
        // Unknown: shows 未知 rather than a guessed 0.
        let unknown = QuotaStyledInput(account: WidgetSnapshot.projecting([try cursorAccount(remaining: nil)]).account)
        XCTAssertEqual(unknown.windows.first?.amount.nativeText, "未知")
        XCTAssertNil(unknown.windows.first?.amount.remainingFraction)
        // No personal quota (team / free): existing “无适用额度”.
        let none = QuotaStyledInput(account: WidgetSnapshot.projecting([try cursorAccount(remaining: nil, state: .notApplicable)]).account)
        XCTAssertTrue(none.windows.isEmpty); XCTAssertEqual(none.message, "无适用额度"); XCTAssertEqual(none.platform, .cursor)
        // Failure keeps the trusted old value and the original success time.
        let ok = try cursorAccount(remaining: 33.33)
        let failed = QuotaStyledInput(account: WidgetSnapshot.projecting([ok], failures: [ok.id: .refresh]).account)
        let normal = QuotaStyledInput(account: WidgetSnapshot.projecting([ok]).account)
        XCTAssertEqual(failed.windows, normal.windows); XCTAssertEqual(failed.lastSuccess, time)
        XCTAssertEqual(failed.message, "刷新失败")
        let blocked = QuotaStyledInput(account: WidgetSnapshot.projecting([ok], failures: [ok.id: .networkBlocked]).account)
        XCTAssertEqual(blocked.message, "网络不达标，无法更新")
        print("T91 | Cursor固定输入 | " + rows.joined(separator: "；") + "；未知→未知；无适用额度；失败保留旧值与原时间 | passed")
    }

    func testT91DetailContentAndTargetForCursor() throws {
        let cursor = try cursorAccount(remaining: 70.125)
        let rows = CodexDetailContent(account: cursor).rows.map(\.id)
        XCTAssertEqual(rows, ["identity", "updatedAt", "remaining.monthly"], "Cursor没有重置额度卡，详情不显示该行")
        XCTAssertEqual(CodexDetailContent(account: try codexAccount()).rows.map(\.id), ["identity", "resetCards", "updatedAt", "remaining.fiveHours", "remaining.weekly"])
        let target = try XCTUnwrap(CodexDetailTarget(cursor))
        XCTAssertEqual(target.resolve(in: [try codexAccount(), cursor])?.id, cursor.id)
        // A Codex account reusing the same local ID never resolves for a Cursor target.
        var impostor = try codexAccount()
        impostor = ConnectedAccount(id: cursor.id, remoteUserID: cursor.remoteUserID, verifiedEmail: cursor.verifiedEmail,
                                    scope: impostor.scope, credentialRef: UUID())
        XCTAssertNil(target.resolve(in: [impostor]))
        let route = WidgetSnapshot.projecting([cursor]).clickTarget
        XCTAssertEqual(WidgetQuotaRoute(url: route)?.detailTarget(in: [cursor])?.id, cursor.id)
        XCTAssertNil(WidgetQuotaRoute(url: route)?.detailTarget(in: [impostor]))
    }

    func testT91StoreAcceptsCursorMonthlyAndRejectsMismatchedWindows() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T91-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let codex = try codexAccount(), cursor = try cursorAccount(remaining: 33.33)
        try await store.append(codex)
        try await store.append(cursor)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, [codex, cursor])
        XCTAssertEqual(loaded.map(\.platform), [.codex, .cursor])

        var weeklyCursor = cursor
        weeklyCursor.quotaSnapshot = CodexQuotaSnapshot(accountID: cursor.id, provider: .cursor, product: .cursorSubscription,
            scope: cursor.scope, generation: 2, planType: "pro", observedAt: time,
            weekly: .init(window: .weekly, amount: .limited(try .init(used: 1)), resetsAt: nil, observedAt: time),
            fiveHours: CodexQuotaSnapshot.absentFiveHours(observedAt: time))
        do { try await store.update(weeklyCursor); XCTFail("Cursor主窗口必须是本月") } catch {}
        let mixed = ConnectedAccount(provider: .cursor, product: .codexSubscription, scope: cursor.scope, credentialRef: UUID())
        do { try await store.append(mixed); XCTFail("平台与产品必须配对") } catch {}
        let after = try await store.load()
        XCTAssertEqual(after, [codex, cursor], "拒绝的写入不改变已存数据")
    }

    /// Upgrade: data written before D-77 has no platform fields and must read back unchanged.
    func testT91LegacyCodexDataReadsBackIdentically() throws {
        let codex = try codexAccount()
        let encoded = try JSONEncoder().encode(codex)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["provider"] as? String, "openai"); XCTAssertEqual(object["product"] as? String, "codexSubscription")
        XCTAssertEqual(try JSONDecoder().decode(ConnectedAccount.self, from: encoded), codex)

        let projected = try XCTUnwrap(WidgetSnapshot.projecting([codex]).account)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(WidgetSnapshot.projecting([codex]))) as? [String: Any])
        for key in ["account"] {
            var account = try XCTUnwrap(legacy[key] as? [String: Any]); account.removeValue(forKey: "platform"); legacy[key] = account
        }
        legacy["accounts"] = [legacy["account"]!]
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.account?.platform)
        XCTAssertEqual(decoded.account?.resolvedPlatform, .codex)
        XCTAssertTrue(decoded.hasSameVisibleContent(as: WidgetSnapshot.projecting([codex])))
        let legacyInput = QuotaStyledInput(account: decoded.account), currentInput = QuotaStyledInput(account: projected)
        XCTAssertEqual(legacyInput, currentInput)
        XCTAssertEqual(currentInput.windows.map(\.id), ["weekly", "fiveHours"])
        XCTAssertEqual(currentInput.windows.map(\.title), ["每周", "5 小时"])
        // Existing widget links keep their exact identity key.
        let oldKey = SHA256.hash(data: Data("codex:false:a@example.invalid".utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(WidgetQuotaRoute.identityKey("a@example.invalid", isDemo: false), oldKey)
        XCTAssertNotEqual(WidgetQuotaRoute.identityKey("a@example.invalid", isDemo: false, platform: .cursor), oldKey)
        XCTAssertEqual(WidgetAccountEntity(account: projected).detail, "Codex")
    }

    /// Native ImageRenderer images (isolated rendering, not the desktop) for the result table.
    func testT91CursorGalleryAllStyles() throws {
        let out = ProcessInfo.processInfo.environment["T91_OUT"].map { URL(fileURLWithPath: $0) }
        var renders = 0
        for dark in [false, true] {
            for (name, account) in [("33.33", try cursorAccount(remaining: 33.33)), ("0", try cursorAccount(remaining: 0)),
                                    ("none", try cursorAccount(remaining: nil, state: .notApplicable))] {
                var rows: [UIImage] = []
                for style in QuotaCardStyle.allCases {
                    let input = QuotaStyledInput(account: WidgetSnapshot.projecting([account]).account)
                    let cells: [AnyView] = [
                        AnyView(QuotaStyledCard(style: style, input: input, now: time).frame(width: 366)),
                        AnyView(QuotaStyledCard(style: style, input: input.singleWindow("monthly"), surface: .detail, now: time).frame(width: 366)),
                        AnyView(SmallQuotaWidgetView(content: .snapshot(WidgetSnapshot.projecting([account])))
                            .frame(width: 170, height: 170).background(CompactQuotaBackground(style: style, widget: true))
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))),
                        AnyView(SmallQuotaWidgetView(content: .snapshot(WidgetSnapshot.projecting([account])), medium: true)
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
                let sheet = stack(rows)
                if let out {
                    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                    try XCTUnwrap(sheet.pngData()).write(to: out.appendingPathComponent("T91-cursor-\(name)-\(dark ? "dark" : "light").png"))
                }
            }
        }
        print("T91 | Cursor隔离渲染 | 16款 x 4表面 x 3状态 x 浅深 | renders=\(renders)")
    }

    /// T102: Lobe marks cut their holes with the even-odd rule. Points are probed against the
    /// upstream SVG rasterised by the system (hole = background, solid = mark) for both the native
    /// shapes and the template image assets.
    func testT102PlatformMarksKeepEvenOddHoles() throws {
        let probes: [(QuotaPlatform, String, holes: [CGPoint], solid: [CGPoint])] = [
            (.codex, "DesignCodex", [CGPoint(x: 12, y: 12), CGPoint(x: 3, y: 10)], [CGPoint(x: 12, y: 0.5), CGPoint(x: 0.5, y: 10.5)]),
            (.cursor, "DesignCursor", [CGPoint(x: 15, y: 8), CGPoint(x: 12, y: 20)], [CGPoint(x: 2, y: 12), CGPoint(x: 12, y: 1.5)]),
        ]
        func alpha(_ image: UIImage, _ p: CGPoint) throws -> UInt8 {
            let cg = try XCTUnwrap(image.cgImage)
            var pixel = [UInt8](repeating: 0, count: 4)
            let context = try XCTUnwrap(CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let scale = CGFloat(cg.width) / 24
            context.draw(cg, in: CGRect(x: -p.x * scale, y: -(CGFloat(cg.height) - p.y * scale), width: CGFloat(cg.width), height: CGFloat(cg.height)))
            return pixel[3]
        }
        var checks = 0
        for (platform, asset, holes, solid) in probes {
            let shape = ImageRenderer(content: PlatformMarkShape(platform: platform).fill(Color.black, style: PlatformMarkShape.fillStyle).frame(width: 240, height: 240))
            shape.scale = 1
            let template = try XCTUnwrap(UIImage(named: asset)).withTintColor(.black, renderingMode: .alwaysOriginal)
            let asImage = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { _ in template.draw(in: CGRect(x: 0, y: 0, width: 240, height: 240)) }
            for image in [try XCTUnwrap(shape.uiImage), asImage] {
                for p in holes { XCTAssertLessThan(try alpha(image, p), 40, "\(asset) \(p) 应为镂空"); checks += 1 }
                for p in solid { XCTAssertGreaterThan(try alpha(image, p), 215, "\(asset) \(p) 应为实心"); checks += 1 }
            }
        }
        print("T102 | Lobe标志奇偶填充 | 原生形状与图片资源 x OpenAI/Cursor | checks=\(checks)")
    }

    /// T102/T103: 13 styles × account card / detail card / small / medium × Codex/Cursor × light/dark,
    /// native ImageRenderer (isolated rendering, not the desktop). Images go to MARK_GALLERY_OUT when set.
    func testT102PlatformMarkGallery() throws {
        let out = ProcessInfo.processInfo.environment["MARK_GALLERY_OUT"].map { URL(fileURLWithPath: $0) }
        var renders = 0
        for dark in [false, true] {
            for (name, account, single) in [("codex", try codexAccount(), nil as String?), ("cursor", try cursorAccount(remaining: 33.33), "monthly")] {
                var rows: [UIImage] = []
                for style in QuotaCardStyle.allCases {
                    let snapshot = WidgetSnapshot.projecting([account])
                    let input = QuotaStyledInput(account: snapshot.account)
                    let cells: [AnyView] = [
                        AnyView(QuotaStyledCard(style: style, input: input, now: time).frame(width: 366)),
                        AnyView(QuotaStyledCard(style: style, input: single.map { input.singleWindow($0) } ?? input.singleWindow("weekly"), surface: .detail, now: time).frame(width: 366)),
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
                if let out {
                    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                    try XCTUnwrap(stack(rows).pngData()).write(to: out.appendingPathComponent("marks-\(name)-\(dark ? "dark" : "light").png"))
                }
            }
        }
        print("T102 | 平台标志隔离渲染 | 16款 x 4表面 x Codex/Cursor x 浅深 | renders=\(renders)")
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
