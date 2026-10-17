import XCTest
import Security
import SwiftUI
@testable import SubscriptionUsage

/// T114: adding OpenRouter / DeepSeek through the real connection flow, binding store
/// and account file, with an isolated Keychain service and fake network. Synthetic keys.
@MainActor
final class APIBalanceConnectionTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_791_590_400)
    private let pasted = "  sk-or-v1-synthetic0000000000a1b2\n"

    private struct Harness {
        let flow: CodexConnectionFlow
        let store: AccountStore
        let vault: CredentialVault
        let transport: BalanceFakeTransport
        let fileURL: URL
    }

    private func harness(network: [NetworkScoreResult] = [.allowed(score: 80)], gate: UsageGate? = nil) async throws -> Harness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T114-\(UUID().uuidString)")
        let service = "com.iceflying.SubscriptionUsage.tests.T114.\(UUID().uuidString)"
        let vault = CredentialVault(service: service)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            for namespace in ["credentials", "login-transactions"] {
                SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: "\(service).\(namespace)"] as CFDictionary)
            }
        }
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let transport = BalanceFakeTransport(openRouter: BalanceFakeTransport.openRouterRaw(#"{"data":{"total_credits":20,"total_usage":7.66}}"#),
            deepSeek: BalanceFakeTransport.deepSeek([BalanceFakeTransport.cny("88.80")]), gate: gate)
        let scores = FlowScoreQueue(network)
        let flow = CodexConnectionFlow(checkNetwork: { await scores.next() },
            transactions: CodexLoginTransactionStore(vault: vault),
            bindings: CodexAccountBindingStore(accountStore: store, vault: vault),
            quotaUpdater: FailingCodexService(), balanceClient: APIBalanceClient(transport: transport),
            foregroundRefreshEnabled: false, now: { [time] in time })
        await flow.loadAccounts()
        return Harness(flow: flow, store: store, vault: vault, transport: transport,
                       fileURL: directory.appendingPathComponent("accounts.json"))
    }

    private func open(_ h: Harness, _ platform: ConnectionPlatform) async throws {
        h.flow.showPlatformPicker()
        XCTAssertEqual(h.flow.state, .choosingPlatform)
        try await XCTUnwrap(h.flow.selectPlatform(platform)).value
    }

    private func connect(_ h: Harness, _ text: String) async throws {
        try await XCTUnwrap(h.flow.connectAPIKey(text)).value
    }

    func testPickerListsFourPlatformsInOrder() {
        XCTAssertEqual(ConnectionPlatform.allCases.map(\.accessibilityName), ["Codex", "Cursor", "OpenRouter", "DeepSeek"])
        XCTAssertEqual(ConnectionPlatform.allCases.map(\.balanceProvider), [nil, nil, .openRouter, .deepSeek])
        for platform in ConnectionPlatform.allCases {
            XCTAssertNotNil(UIImage(named: "Design" + platform.iconName), platform.accessibilityName)
        }
    }

    func testSuccessfulKeyCreatesAccountAndCloses() async throws {
        let h = try await harness()
        try await open(h, .openRouter)
        XCTAssertEqual(h.flow.state, .keyEntry)
        XCTAssertTrue(h.flow.accounts.isEmpty, "nothing stored before 连接")
        try await connect(h, pasted)
        XCTAssertEqual(h.flow.state, .idle)
        XCTAssertFalse(h.flow.isPresented)
        let account = try XCTUnwrap(h.flow.accounts.first)
        XCTAssertEqual(account.platform, .openRouter)
        XCTAssertEqual(account.identityText, "sk-…a1b2")
        XCTAssertEqual(account.balance?.amounts, [BalanceAmount(currency: "USD", total: Decimal(string: "12.34")!)])
        let saved = try await h.store.load()
        XCTAssertEqual(saved, h.flow.accounts)
        let key = try await h.vault.load(for: .credential(account.credentialRef))
        XCTAssertEqual(key, APIKeyCredential(pasted: pasted)!.payload)
        let requests = await h.transport.requests
        XCTAssertEqual(requests.map(\.url), [APIBalanceClient.openRouterURL])
        print("T114 | 添加OpenRouter | 网络检查→输入页→连接查余额成功才建账户（$12.34，sk-…a1b2），key存钥匙串，弹层关闭 | passed")
    }

    func testSameKeyAgainUpdatesInPlaceAndOtherKeyAppends() async throws {
        let h = try await harness()
        try await open(h, .deepSeek); try await connect(h, pasted)
        try await open(h, .openRouter); try await connect(h, "sk-or-v1-other00000000000000c3d4")
        let firstIDs = h.flow.accounts.map(\.id)
        await h.transport.set(APIBalanceClient.deepSeekURL, BalanceFakeTransport.deepSeek([BalanceFakeTransport.cny("1.23")]))
        try await open(h, .deepSeek); try await connect(h, pasted)
        XCTAssertEqual(h.flow.accounts.map(\.id), firstIDs, "same key: same account, same position")
        XCTAssertEqual(h.flow.accounts.first?.balance?.amounts.first?.total, Decimal(string: "1.23"))
        let saved = try await h.store.load()
        XCTAssertEqual(saved.map(\.id), firstIDs)
        XCTAssertEqual(saved.map(\.platform), [.deepSeek, .openRouter])
    }

    func testRejectedKeyCreatesNothingAndCanRetry() async throws {
        let h = try await harness()
        await h.transport.set(APIBalanceClient.openRouterURL, BalanceFakeTransport.openRouterRaw(#"{"error":{"code":403}}"#, status: 403))
        try await open(h, .openRouter)
        try await connect(h, pasted)
        XCTAssertEqual(h.flow.state, .keyEntry, "stays on the input page")
        XCTAssertTrue(h.flow.isPresented)
        XCTAssertEqual(h.flow.keyFailure, "key 无效或不是 Management key")
        XCTAssertFalse(h.flow.keyVerifying)
        let none = try await h.store.load()
        XCTAssertTrue(none.isEmpty)
        // A server error is a plain short failure.
        await h.transport.set(APIBalanceClient.openRouterURL, BalanceFakeTransport.openRouter(credits: 1, usage: 0, status: 500))
        try await connect(h, pasted)
        XCTAssertEqual(h.flow.keyFailure, "连接失败，请重试")
        // Corrected key now works.
        await h.transport.set(APIBalanceClient.openRouterURL, BalanceFakeTransport.openRouter(credits: 3, usage: 1))
        try await connect(h, "sk-or-v1-management000000000e5f6")
        XCTAssertFalse(h.flow.isPresented)
        XCTAssertNil(h.flow.keyFailure)
        XCTAssertEqual(h.flow.accounts.map(\.identityText), ["sk-…e5f6"])
        // DeepSeek refusal wording.
        await h.transport.set(APIBalanceClient.deepSeekURL, BalanceFakeTransport.deepSeek([], status: 401))
        try await open(h, .deepSeek); try await connect(h, pasted)
        XCTAssertEqual(h.flow.keyFailure, "key 无效，请检查后重试")
        XCTAssertEqual(h.flow.accounts.count, 1)
        print("T114 | 被拒/失败 | 403提示“key 无效或不是 Management key”、500提示“连接失败，请重试”、DeepSeek 401提示“key 无效，请检查后重试”；均不建账户、可改后重试 | passed")
    }

    func testNetworkGateBlocksBeforeInputAndBeforeQuery() async throws {
        let h = try await harness(network: [.blocked(score: 30), .allowed(score: 80), .blocked(score: 30)])
        try await open(h, .deepSeek)
        XCTAssertEqual(h.flow.state, .failure("网络不达标，无法连接"))
        // 重试 reopens the gate for the same platform.
        try await XCTUnwrap(h.flow.begin()).value
        XCTAssertEqual(h.flow.state, .keyEntry)
        try await connect(h, pasted)
        XCTAssertEqual(h.flow.keyFailure, "网络不达标，无法连接")
        let requests = await h.transport.requests
        XCTAssertTrue(requests.isEmpty, "no balance request without a passing network check")
        let none = try await h.store.load()
        XCTAssertTrue(none.isEmpty)
    }

    func testInvalidPasteAndCancelLeaveNothing() async throws {
        let gate = UsageGate()
        let h = try await harness(gate: gate)
        try await open(h, .openRouter)
        XCTAssertNil(h.flow.connectAPIKey("   "))
        XCTAssertEqual(h.flow.keyFailure, "请粘贴完整的 key")
        XCTAssertNil(h.flow.connectAPIKey("sk-has space inside"))
        let work = try XCTUnwrap(h.flow.connectAPIKey(pasted))
        XCTAssertTrue(h.flow.keyVerifying)
        while !(await gate.waiting) { await Task.yield() }
        h.flow.cancel()
        XCTAssertEqual(h.flow.state, .idle)
        XCTAssertFalse(h.flow.keyVerifying)
        await gate.release()
        await work.value
        let none = try await h.store.load()
        XCTAssertTrue(none.isEmpty, "a cancelled connection stores nothing")
        XCTAssertTrue(h.flow.accounts.isEmpty)
        // Reopening starts clean.
        await h.transport.clearGate()
        h.flow.showPlatformPicker()
        XCTAssertEqual(h.flow.state, .choosingPlatform)
        XCTAssertNil(h.flow.keyFailure)
    }

    /// Isolated rendering of the real sheet: picker, both key pages, a refusal; light / dark
    /// and a large text size. Images go to T114_OUT when set. No key is ever typed.
    func testT114SheetRendering() async throws {
        let out = ProcessInfo.processInfo.environment["T114_OUT"].map { URL(fileURLWithPath: $0) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 760)
        defer { window.isHidden = true; window.rootViewController = nil }
        var renders = 0
        for (name, platform, refuse) in [("picker", ConnectionPlatform?.none, false), ("openrouter", .openRouter, false),
                                         ("deepseek", .deepSeek, false), ("openrouter-refused", .openRouter, true)] {
            let h = try await harness()
            await h.transport.set(APIBalanceClient.openRouterURL, BalanceFakeTransport.openRouterRaw("{}", status: 403))
            h.flow.showPlatformPicker()
            if let platform { try await XCTUnwrap(h.flow.selectPlatform(platform)).value }
            if refuse { try await XCTUnwrap(h.flow.connectAPIKey("sk-or-v1-render00000000000000000")).value }
            for scheme: ColorScheme in [.light, .dark] {
                for size: DynamicTypeSize in [.large, .accessibility2] {
                    let host = UIHostingController(rootView: CodexConnectionView(flow: h.flow)
                        .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
                        .environment(\.locale, Locale(identifier: "zh_CN")))
                    host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
                    window.rootViewController = host; window.makeKeyAndVisible()
                    try await Task.sleep(for: .milliseconds(400))
                    window.layoutIfNeeded()
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    XCTAssertGreaterThan(image.size.width, 0)
                    renders += 1
                    if let out {
                        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
                        try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent(
                            "T114-\(name)-\(scheme == .dark ? "dark" : "light")-\(size == .large ? "default" : "ax2").png"))
                    }
                }
            }
        }
        print("T114 | 弹层隔离渲染 | 四格选择/OpenRouter输入页/DeepSeek输入页/被拒提示 x 浅深 x 默认与大字号 | renders=\(renders)")
    }
}
