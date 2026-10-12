import SwiftUI
import UIKit
import XCTest
@testable import SubscriptionUsage

final class RootViewTests: XCTestCase {
    @MainActor
    func testT36DesktopValidationMarkersWereCleaned() throws {
        guard ProcessInfo.processInfo.environment["T36_CLEANUP_CHECK"] == "1" else {
            throw XCTSkip("实际桌面隔离会话结束后，显式启用只读清理核对")
        }
        #if DEBUG
        let root = try WidgetSnapshotStore.sharedDirectory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("T36-route-session.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("T35-validation-session").path))
        XCTAssertEqual(try WidgetSnapshotStore.displayStore().resolvedURL(), try WidgetSnapshotStore.appGroupStore().resolvedURL())
        XCTAssertFalse(CodexConnectionUITestSupport.isWidgetRouteValidationActive)
        print("T36 | 桌面隔离结束 | 路由标记及组件读路径已恢复，未读取正式账户/授权")
        #endif
    }

    func testT36SelectedWidgetLinksResolveIdentityAcrossSortReconnectAndDeletion() throws {
        var a = ConnectedAccount(verifiedEmail: "first@example.invalid", scope: .init(remoteAccountID: "a", kind: .personal), credentialRef: UUID())
        var b = ConnectedAccount(verifiedEmail: "selected@example.invalid", scope: .init(remoteAccountID: "b", kind: .personal), credentialRef: UUID())
        let publication = WidgetSnapshot.projecting([a, b])
        let selected = QuotaWidgetContent.snapshot(publication).selecting(accountID: b.id.uuidString)
        let link = selected.destinationURL
        XCTAssertFalse(link.absoluteString.contains("example.invalid"))
        let route = try XCTUnwrap(WidgetQuotaRoute(url: link))
        XCTAssertEqual(route.detailTarget(in: [a, b])?.id, b.id)
        XCTAssertEqual(route.detailTarget(in: [b, a])?.id, b.id)
        b.generation += 1; b.credentialRef = UUID()
        XCTAssertEqual(route.detailTarget(in: [a, b])?.id, b.id, "同邮箱更新连接保持目标")
        b.verifiedEmail = "replacement@example.invalid"
        XCTAssertNil(route.detailTarget(in: [a, b]), "不得把旧目标嫁接到另一身份")
        XCTAssertNil(route.detailTarget(in: [a]))
        XCTAssertNil(route.detailTarget(in: []))
        a.deletionPending = true
        let deleted = WidgetQuotaRoute(url: WidgetQuotaRoute.url(accountID: a.id, identity: "first@example.invalid", isDemo: false))
        XCTAssertNil(deleted?.detailTarget(in: [a]))
        XCTAssertEqual(QuotaWidgetContent.snapshot(.empty).destinationURL, QuotaWidgetContent.addAccountURL)
        XCTAssertEqual(WidgetQuotaRoute(url: QuotaWidgetContent.unavailable.destinationURL), .quota(accountID: nil, identityKey: nil))
    }

    func testT36MalformedAndForeignURLsNeverChooseAnAccount() {
        for raw in ["https://quota", "subscriptionusage://quota/path", "subscriptionusage://user:secret@quota", "subscriptionusage://quota#fragment"] {
            XCTAssertNil(WidgetQuotaRoute(url: URL(string: raw)!))
        }
        for raw in ["subscriptionusage://quota", "subscriptionusage://quota?account=broken", "subscriptionusage://quota?account=\(UUID())", "subscriptionusage://quota?account=\(UUID())&account=\(UUID())&identity=bad"] {
            XCTAssertEqual(WidgetQuotaRoute(url: URL(string: raw)!), .quota(accountID: nil, identityKey: nil))
        }
    }

    @MainActor
    func testT36RoutingDoesNotAddQuotaRequestsToForegroundMergedRefresh() async throws {
        let fixture = T26BatchFixture(scenario: "success")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let flow = CodexConnectionFlow(transactions: T36Transactions(), bindings: fixture, quotaUpdater: fixture)
        flow.sceneActivityChanged(true)
        await flow.loadAccounts()
        let selected = flow.accounts[1]
        let route = try XCTUnwrap(WidgetQuotaRoute(url: WidgetQuotaRoute.url(accountID: selected.id,
            identity: selected.verifiedEmail!, isDemo: false)))
        for _ in 0..<3 { XCTAssertEqual(route.detailTarget(in: flow.accounts)?.id, selected.id) }
        flow.sceneActivityChanged(true)
        await flow.waitForInitialQuota()
        let counts = await fixture.requests
        XCTAssertEqual(counts.values.reduce(0, +), 2, "每户仅前台自动查询一次，路由不查")
        XCTAssertTrue(flow.visibleQuotaUpdatingIDs.isEmpty)
        for scenario in ["blocked", "unknown"] {
            let failing = T26BatchFixture(scenario: scenario)
            defer { try? FileManager.default.removeItem(at: failing.directory) }
            let f = CodexConnectionFlow(transactions: T36Transactions(), bindings: failing, quotaUpdater: failing)
            let saved = try await failing.load()
            f.sceneActivityChanged(true); await f.loadAccounts(); await f.waitForInitialQuota()
            XCTAssertEqual(f.accounts, saved)
            let link = WidgetQuotaRoute.url(accountID: saved[1].id, identity: saved[1].verifiedEmail!, isDemo: false)
            XCTAssertEqual(WidgetQuotaRoute(url: link)?.detailTarget(in: f.accounts)?.id, saved[1].id)
            XCTAssertEqual(f.quotaFailure, scenario == "blocked" ? "网络不达标，无法更新" : "刷新失败")
        }
    }

    func testT62AccountAndResetCardsUseEachAccountsMetadataAndMissingDefaultsOnlyInUI() {
        let now = Date()
        var account = ConnectedAccount(verifiedEmail: "first@example.invalid", scope: .init(remoteAccountID: "first", kind: .personal), credentialRef: UUID(),
            quotaState: .notApplicable, subscription: .init(planType: "Actual Plan", observedAt: now, resetCardCount: 2))
        var rows = CodexDetailContent(account: account).rows
        XCTAssertEqual(rows.map(\.id), ["identity", "plan", "resetCards"])
        XCTAssertEqual(rows.first?.value, "first@example.invalid")
        XCTAssertEqual(rows.first { $0.id == "resetCards" }?.value, "2")
        account.verifiedEmail = "second@example.invalid"
        account.subscription = .init(planType: "Actual Plan", observedAt: now, resetCardCount: 7)
        rows = CodexDetailContent(account: account).rows
        XCTAssertEqual(rows.first?.value, "second@example.invalid")
        XCTAssertEqual(rows.first { $0.id == "resetCards" }?.value, "7")
        for count: Int64? in [nil, 0, -1] {
            account.subscription = .init(planType: "Actual Plan", observedAt: now, resetCardCount: count)
            XCTAssertEqual(CodexDetailContent(account: account).rows.first { $0.id == "resetCards" }?.value, "0")
        }
        XCTAssertNil(account.quotaSnapshot, "补充0不会伪造主窗口成功")
    }

    func testT62DetailIdentityAndTrustedRowsNeverBorrowAnotherAccount() throws {
        let now = Date(timeIntervalSince1970: 1_791_590_400)
        var first = ConnectedAccount(remoteUserID: "user-a", verifiedEmail: "a@example.invalid",
            scope: .init(remoteAccountID: "scope-a", kind: .personal), credentialRef: UUID(),
            quotaState: .available, subscription: .init(planType: "Actual Plan", observedAt: now))
        first.quotaSnapshot = .init(accountID: first.id, provider: first.provider, product: first.product,
            scope: first.scope, generation: first.generation, planType: "Actual Plan", observedAt: now,
            weekly: .init(window: .weekly, amount: .limited(try .init(used: 0)), resetsAt: now, observedAt: now),
            fiveHours: .init(window: .fiveHours, amount: .limited(try .init(used: 100)), resetsAt: nil, observedAt: now))
        let target = try XCTUnwrap(CodexDetailTarget(first))
        var second = first
        second.verifiedEmail = "b@example.invalid"
        XCTAssertNil(target.resolve(in: [second]))
        XCTAssertEqual(target.resolve(in: [second, first]), first)
        second.deletionPending = true
        XCTAssertNil(CodexDetailTarget(second))
        XCTAssertNil(target.resolve(in: []))
        var content = CodexDetailContent(account: first)
        XCTAssertEqual(content.rows.map(\.id), ["identity", "plan", "resetCards", "updatedAt"])
        XCTAssertEqual(content.snapshot?.weekly.amount.remainingPercent, 100)
        XCTAssertEqual(content.snapshot?.fiveHours.amount.remainingPercent, 0)
        XCTAssertEqual(content.snapshot?.weekly.amount.progress?.usedFraction, 0)
        XCTAssertEqual(content.snapshot?.fiveHours.amount.progress?.usedFraction, 1)
        first.scope = .init(remoteAccountID: "new-scope", kind: .personal)
        content = CodexDetailContent(account: first)
        XCTAssertNil(content.snapshot)
        XCTAssertEqual(content.rows.map(\.id), ["identity", "plan", "resetCards"])
        first.subscription = nil; first.quotaSnapshot = nil; first.quotaState = .notApplicable
        XCTAssertEqual(CodexDetailContent(account: first).rows.map(\.id), ["identity", "resetCards"])
    }

    @MainActor
    func testT62PanelRendersLightDarkLargestTextAndUnknownWindows() async throws {
        let now = Date(timeIntervalSince1970: 1_791_590_400)
        var account = ConnectedAccount(verifiedEmail: "long-identity-for-detail@example.invalid",
            scope: .init(remoteAccountID: "detail", kind: .personal), credentialRef: UUID(),
            quotaState: .available, subscription: .init(planType: "Actual Long Official Plan", observedAt: now))
        account.quotaSnapshot = .init(accountID: account.id, provider: account.provider, product: account.product,
            scope: account.scope, generation: 0, planType: nil, observedAt: now,
            weekly: .init(window: .weekly, amount: .unknown, resetsAt: nil, observedAt: now),
            fiveHours: .init(window: .fiveHours, amount: .limited(try .init(used: 80)), resetsAt: now, observedAt: now))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 414, height: 896)
        defer { window.isHidden = true; window.rootViewController = nil }
        for scheme: ColorScheme in [.light, .dark] {
            for size: DynamicTypeSize in [.large, .accessibility5] {
                let host = UIHostingController(rootView: CodexDetailPanel(account: account, failure: "刷新失败")
                    .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size))
                window.rootViewController = host; window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(400))
                window.layoutIfNeeded()
                XCTAssertGreaterThan(host.view.bounds.height, 800)
                let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                })
                attachment.name = "T62-\(scheme)-\(size)"; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }

    @MainActor
    func testT59HostedListPullPresentationAndReleaseUsesExistingRefreshAction() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("T59-\(UUID())")
        let store = AccountStore(fileURL: root.appendingPathComponent("accounts.json"))
        _ = try await store.setDemoMode(true)
        for _ in 0..<2 { _ = try await store.addDemo(now: Date()) }
        let accounts = try await store.load()
        defer { try? FileManager.default.removeItem(at: root) }
        var refreshes = 0
        let host = UIHostingController(rootView: QuotaView(accounts: accounts, canRefreshAll: true,
                                                         refreshAll: { refreshes += 1 }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 414, height: 896)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(400))
        func find(_ view: UIView) -> UICollectionView? {
            if let collection = view as? UICollectionView { return collection }
            return view.subviews.compactMap { find($0) }.first
        }
        let list = try XCTUnwrap(find(host.view))
        let indicator = try XCTUnwrap(list.subviews.first { $0 is QuotaPullIndicator })
        let topInset = list.adjustedContentInset.top
        func position(_ distance: CGFloat) {
            list.contentOffset.y = -topInset - distance
            list.delegate?.scrollViewDidScroll?(list)
            window.layoutIfNeeded()
        }
        for style: UIUserInterfaceStyle in [.light, .dark] {
            window.overrideUserInterfaceStyle = style
            position(0)
            list.delegate?.scrollViewWillBeginDragging?(list)
            let previous = refreshes
            var lastWidth: CGFloat = 0
            for distance: CGFloat in [24, 48, 100, 160] {
                position(distance)
                XCTAssertFalse(indicator.isHidden)
                XCTAssertGreaterThanOrEqual(indicator.frame.width, lastWidth)
                lastWidth = indicator.frame.width
                XCTAssertEqual(refreshes, previous, "手指未松开不能刷新")
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "T59-拉动-\(style == .dark ? "深" : "浅")-\(Int(distance))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            position(30)
            list.delegate?.scrollViewDidEndDragging?(list, willDecelerate: true)
            XCTAssertEqual(refreshes, previous, "超过后收回再松手不触发")
            position(0)
            list.delegate?.scrollViewWillBeginDragging?(list)
            position(100)
            list.delegate?.scrollViewDidEndDragging?(list, willDecelerate: true)
            XCTAssertEqual(refreshes, previous + 1)
            position(0)
            XCTAssertTrue(indicator.isHidden)
        }
    }


    @MainActor
    func testT59PullThresholdReleaseRetractionAndOneHapticPerGesture() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        scroll.contentInset.top = 16
        let pull = QuotaPullRefreshGesture()
        pull.attach(to: scroll)
        var haptics = 0
        pull.onThreshold = { haptics += 1 }
        func position(_ distance: CGFloat) {
            scroll.contentOffset.y = -scroll.adjustedContentInset.top - distance
            pull.update(enabled: true)
        }
        position(0)
        pull.begin(enabled: true)
        position(24)
        XCTAssertFalse(pull.end(enabled: true))
        XCTAssertEqual(haptics, 0)
        position(0)
        XCTAssertTrue(pull.indicator.isHidden)
        pull.begin(enabled: true)
        position(100)
        XCTAssertEqual(haptics, 1)
        for distance: CGFloat in [140, 65, 120, 60, 110, 20] { position(distance) }
        XCTAssertEqual(haptics, 1, "同一手势反复经过门槛也不重复震动")
        XCTAssertFalse(pull.end(enabled: true), "收回后松手不刷新")
        position(0)
        pull.begin(enabled: true)
        position(100)
        XCTAssertEqual(haptics, 2)
        XCTAssertTrue(pull.end(enabled: true))
        XCTAssertFalse(pull.end(enabled: true), "一次松手只能提交一次")
        position(0)
        XCTAssertTrue(pull.indicator.isHidden)
    }

    @MainActor
    func testT59DisabledCancelledAndOrdinaryScrollNeverTrigger() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let pull = QuotaPullRefreshGesture()
        pull.attach(to: scroll)
        var haptics = 0
        pull.onThreshold = { haptics += 1 }
        pull.begin(enabled: false)
        scroll.contentOffset.y = -140
        pull.update(enabled: false)
        XCTAssertTrue(pull.indicator.isHidden)
        XCTAssertFalse(pull.end(enabled: false))
        XCTAssertEqual(haptics, 0)
        scroll.contentOffset.y = 200
        pull.begin(enabled: true)
        pull.update(enabled: true)
        XCTAssertTrue(pull.indicator.isHidden)
        XCTAssertFalse(pull.end(enabled: true))
        scroll.contentOffset.y = 0
        pull.begin(enabled: true)
        scroll.contentOffset.y = -140
        pull.update(enabled: true)
        XCTAssertFalse(pull.end(enabled: true, cancelled: true))
        XCTAssertTrue(pull.indicator.isHidden)
        scroll.contentOffset.y = 0
        pull.begin(enabled: true)
        scroll.contentOffset.y = -140
        pull.update(enabled: true)
        pull.cancelGesture() // Account movement / another operation interrupts the pull.
        XCTAssertFalse(pull.end(enabled: true))
        XCTAssertEqual(haptics, 2)
    }

    @MainActor
    func testT59StaticIndicatorScalesCapsAndRetractsWithoutHoldingContent() {
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        scroll.contentInset.top = 12
        let pull = QuotaPullRefreshGesture()
        pull.onThreshold = {}
        pull.attach(to: scroll)
        scroll.contentOffset.y = -12
        pull.begin(enabled: true)
        var widths: [CGFloat] = []
        for distance: CGFloat in [18, 36, 72, 140] {
            scroll.contentOffset.y = -12 - distance
            pull.update(enabled: true)
            widths.append(pull.indicator.frame.width)
            XCTAssertEqual(pull.indicator.frame.midY - scroll.contentOffset.y, distance / 2, accuracy: 0.1)
            XCTAssertTrue((pull.indicator.layer.animationKeys() ?? []).isEmpty, "下拉阶段圆圈不能旋转")
        }
        XCTAssertLessThan(widths[0], widths[1])
        XCTAssertLessThan(widths[1], widths[2])
        XCTAssertEqual(widths[2], widths[3])
        XCTAssertLessThanOrEqual(widths[3], 24)
        XCTAssertTrue(pull.end(enabled: true))
        pull.cancelGesture() // Refresh disables a second gesture while bounce continues.
        scroll.contentOffset.y = -36
        pull.update(enabled: false)
        XCTAssertFalse(pull.indicator.isHidden)
        XCTAssertLessThan(pull.indicator.frame.width, widths[3])
        scroll.contentOffset.y = -12
        pull.update(enabled: false)
        XCTAssertTrue(pull.indicator.isHidden)
        XCTAssertEqual(scroll.contentInset.top, 12, "不修改原生回弹或停留高度")
    }


    func testT17StableBoundariesHandleMixedHeightsMicroMovementAndReversal() {
        for centers: [CGFloat] in [[44, 167.17, 337.5], [91, 261, 431], [44, 290, 620]] {
            for source in centers.indices {
                var position = QuotaReorderPosition(source: source, centers: centers)
                for target in (0..<centers.count).reversed() {
                    let y = target == source ? centers[source] : centers[target] + (target > source ? 12 : -12)
                    XCTAssertEqual(position.update(y: y), target)
                    for tick in 0..<30 {
                        XCTAssertEqual(position.update(y: y + (tick.isMultiple(of: 2) ? -0.5 : 0.5)), target)
                    }
                }
                XCTAssertEqual(position.update(y: centers.last! + 20), centers.count - 1)
                XCTAssertEqual(position.update(y: centers.first! - 20), 0)
            }
        }
    }

    func testT17CrossingDeadbandDoesNotAlternateAndNewDragResets() {
        var position = QuotaReorderPosition(source: 0, centers: [44, 167, 337])
        XCTAssertEqual(position.update(y: 180), 1)
        for y: CGFloat in [166.5, 167.5, 165, 170, 163] { XCTAssertEqual(position.update(y: y), 1) }
        XCTAssertEqual(position.update(y: 155), 0)
        for y: CGFloat in [166.5, 167.5, 170] { XCTAssertEqual(position.update(y: y), 0) }
        XCTAssertEqual(position.update(y: 180), 1)
        position = QuotaReorderPosition(source: 2, centers: [44, 167, 337])
        XCTAssertEqual(position.update(y: 337), 2)
        XCTAssertEqual(position.update(y: .nan), 2)
    }

    @MainActor
    func testT17UnequalHeightUIKitMovementHoldsThenReversesWithoutOscillation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("T17-hold-\(UUID())")
        let store = AccountStore(fileURL: root.appendingPathComponent("accounts.json"))
        _ = try await store.setDemoMode(true)
        for _ in 0..<3 { _ = try await store.addDemo(now: Date()) }
        var accounts = try await store.load()
        accounts[0].source = nil
        accounts[0].quotaSnapshot = nil
        accounts[0].quotaState = .notApplicable
        accounts[0].subscription = .init(planType: "Free", observedAt: Date())
        defer { try? FileManager.default.removeItem(at: root) }
        var committedDestinations: [Int] = []
        let controller = UIHostingController(rootView: QuotaView(accounts: accounts, canReorder: true,
            move: { _, destination in committedDestinations.append(destination) }))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 414, height: 896)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(600))
        func find(_ view: UIView) -> UICollectionView? {
            if let collection = view as? UICollectionView { return collection }
            return view.subviews.compactMap { find($0) }.first
        }
        let collection = try XCTUnwrap(find(controller.view))
        let layout = try XCTUnwrap(collection.collectionViewLayout as? QuotaReorderLayout)
        let frames = (0..<3).compactMap { layout.layoutAttributesForItem(at: IndexPath(item: $0, section: 0))?.frame }
        XCTAssertEqual(frames.count, 3)
        XCTAssertLessThan(frames[0].height, frames[1].height)
        // Replay every original failing position, plus an unambiguous crossing.
        for fraction in [0.05, 0.25, 0.49, 0.51, 0.60, 0.75, 0.95] {
            layout.beginMovement(at: IndexPath(item: 0, section: 0))
            XCTAssertTrue(collection.beginInteractiveMovementForItem(at: IndexPath(item: 0, section: 0)))
            let y = frames[1].minY + frames[1].height * fraction
            var destinations: [Int] = []
            for tick in 0..<30 {
                collection.updateInteractiveMovementTargetPosition(CGPoint(x: frames[0].midX,
                    y: y + (tick.isMultiple(of: 2) ? -0.5 : 0.5)))
                try await Task.sleep(for: .milliseconds(40))
                destinations.append(try XCTUnwrap(layout.movement?.destination))
            }
            XCTAssertEqual(Set(destinations).count, 1, "停留微动不能来回换位")
            let expected = y > frames[1].midY + 6 ? 1 : 0
            XCTAssertEqual(destinations.last, expected)
            let firstHeight = try XCTUnwrap(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame.height)
            XCTAssertEqual(firstHeight, frames[expected].height, accuracy: 1, "实际卡片布局也应保持稳定")
            print("T17 FIX | target fraction=\(fraction) | 30次微动保持同一位置=\(expected)")
            collection.cancelInteractiveMovement()
            layout.finishMovement()
            try await Task.sleep(for: .milliseconds(350))
        }
        XCTAssertTrue(committedDestinations.isEmpty, "取消不保存临时顺序")
        layout.beginMovement(at: IndexPath(item: 0, section: 0))
        XCTAssertTrue(collection.beginInteractiveMovementForItem(at: IndexPath(item: 0, section: 0)))
        for (y, expected) in [(frames[1].midY + 12, 1), (frames[2].midY + 12, 2),
                              (frames[2].midY - 12, 1), (frames[1].midY - 12, 0),
                              (frames[1].midY + 12, 1)] {
            collection.updateInteractiveMovementTargetPosition(CGPoint(x: frames[0].midX, y: y))
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertEqual(layout.movement?.destination, expected)
        }
        collection.endInteractiveMovement()
        layout.finishMovement()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(committedDestinations, [2], "松手仅保存最终的第二位")
        XCTAssertNil(layout.movement)
    }

    @MainActor
    func testT58SystemDefaultAndManualOverrideAcrossSystemChanges() async throws {
        let suite = "T58-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let controller = UIHostingController(rootView: RootView(connection: CodexConnectionFlow(), preferences: preferences))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 414, height: 896)
        window.rootViewController = controller
        window.overrideUserInterfaceStyle = .light
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(controller.view.traitCollection.userInterfaceStyle, .light)
        window.overrideUserInterfaceStyle = .dark
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(controller.view.traitCollection.userInterfaceStyle, .dark)
        preferences.set("light", forKey: "appearance")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(controller.view.traitCollection.userInterfaceStyle, .light)
        window.overrideUserInterfaceStyle = .light
        window.overrideUserInterfaceStyle = .dark
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(controller.view.traitCollection.userInterfaceStyle, .light)
        let reopened = UIHostingController(rootView: RootView(connection: CodexConnectionFlow(), preferences: preferences))
        window.rootViewController = reopened
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(reopened.view.traitCollection.userInterfaceStyle, .light)
    }

    @MainActor
    func testResetDayLabelUsesCalendarDayInsteadOfRoundingDownFullDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 18, minute: 10)))
        let reset = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 18)))
        XCTAssertTrue(QuotaView.resetText(reset, now: now, calendar: calendar).hasPrefix("6 天后"))
    }

    @MainActor
    func testResetTextUsesReportedDeadlineWithoutInventingOne() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        XCTAssertEqual(QuotaView.resetText(nil, now: now), "未提供重置时间")
        XCTAssertEqual(QuotaView.resetText(now, now: now), "已到预计时间")
        XCTAssertEqual(QuotaView.resetText(now.addingTimeInterval(-1), now: now), "已到预计时间")
        XCTAssertEqual(QuotaView.resetText(now.addingTimeInterval(5_640), now: now), "1 小时 34 分后")
        XCTAssertEqual(QuotaView.resetText(now.addingTimeInterval(1), now: now), "1 分钟后")
    }

    @MainActor
    func testRootViewCanLoadAndLayOutInAppHost() {
        let controller = UIHostingController(rootView: RootView())
        controller.loadViewIfNeeded()

        let size = controller.sizeThatFits(in: CGSize(width: 393, height: 852))

        XCTAssertTrue(controller.isViewLoaded)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertTrue(size.width.isFinite && size.height.isFinite)
    }
}


private actor T36Transactions: CodexLoginTransactionStoring {
    func save(_ authorization: CodexDeviceAuthorization) { }
    func remove(transactionID: UUID) { }
}
