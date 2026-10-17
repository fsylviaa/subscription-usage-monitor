import XCTest
import Security
@testable import SubscriptionUsage

/// Fake balance host: one programmable response per platform URL. Records only the
/// URL and whether a Bearer header was present, never the key itself.
actor BalanceFakeTransport: CodexDeviceAuthorizationTransport {
    struct Reply { var status: Int; var body: Data; var mime = "application/json"; var error: URLError? = nil }
    private var replies: [URL: Reply] = [:]
    private(set) var requests: [(url: URL, bearer: Bool)] = []
    private var gate: UsageGate?

    init(openRouter: Reply? = nil, deepSeek: Reply? = nil, gate: UsageGate? = nil) {
        if let openRouter { replies[APIBalanceClient.openRouterURL] = openRouter }
        if let deepSeek { replies[APIBalanceClient.deepSeekURL] = deepSeek }
        self.gate = gate
    }

    func set(_ url: URL, _ reply: Reply) { replies[url] = reply }
    func clearGate() { gate = nil }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let url = try XCTUnwrap(request.url)
        requests.append((url, request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer sk-") == true))
        if let gate { await gate.wait() }
        guard let reply = replies[url] else { throw URLError(.cannotConnectToHost) }
        if let error = reply.error { throw error }
        return (reply.body, HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil,
                                            headerFields: ["Content-Type": reply.mime])!)
    }

    static func openRouter(credits: Any, usage: Any, status: Int = 200) -> Reply {
        Reply(status: status, body: try! JSONSerialization.data(withJSONObject: ["data": ["total_credits": credits, "total_usage": usage]]))
    }
    static func openRouterRaw(_ json: String, status: Int = 200) -> Reply { Reply(status: status, body: Data(json.utf8)) }
    static func deepSeek(_ infos: [[String: Any]], available: Bool = true, status: Int = 200) -> Reply {
        Reply(status: status, body: try! JSONSerialization.data(withJSONObject: ["is_available": available, "balance_infos": infos]))
    }
    static func cny(_ total: String, toppedUp: String? = "8.00", granted: String? = "2.00") -> [String: Any] {
        var info: [String: Any] = ["currency": "CNY", "total_balance": total]
        if let toppedUp { info["topped_up_balance"] = toppedUp }
        if let granted { info["granted_balance"] = granted }
        return info
    }
}

/// T113: parsing (T111 field shapes), classification and the shared refresh paths.
@MainActor
final class APIBalanceQueryTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_791_590_400)
    private let key = APIBalanceStoreTests.key()

    private func query(_ provider: ProviderID, _ reply: BalanceFakeTransport.Reply) async throws -> APIBalanceSnapshot {
        let transport = provider == .openRouter ? BalanceFakeTransport(openRouter: reply) : BalanceFakeTransport(deepSeek: reply)
        return try await APIBalanceClient(transport: transport).balance(provider, key: key, observedAt: time)
    }

    private func outcome(_ provider: ProviderID, _ reply: BalanceFakeTransport.Reply) async -> APIBalanceQueryError? {
        do { _ = try await query(provider, reply); return nil } catch { return (error as? APIBalanceQueryError) ?? .failed }
    }

    func testOpenRouterCreditsMinusUsageExactAndClampedAtZero() async throws {
        let normal = try await query(.openRouter, BalanceFakeTransport.openRouterRaw(#"{"data":{"total_credits":10.1,"total_usage":0.3}}"#))
        XCTAssertEqual(normal.amounts, [BalanceAmount(currency: "USD", total: Decimal(string: "9.8")!)])
        XCTAssertEqual(normal.observedAt, time)
        let precise = try await query(.openRouter, BalanceFakeTransport.openRouterRaw(#"{"data":{"total_credits":25,"total_usage":3.123456789}}"#))
        XCTAssertEqual(precise.amounts.first?.total, Decimal(string: "21.876543211"))
        let zero = try await query(.openRouter, BalanceFakeTransport.openRouter(credits: 5, usage: 5))
        XCTAssertEqual(zero.amounts.first?.total, 0)
        let over = try await query(.openRouter, BalanceFakeTransport.openRouter(credits: 5, usage: 7.5))
        XCTAssertEqual(over.amounts.first?.total, 0, "never negative")
        print("T113 | OpenRouter解析 | 10.1−0.3=9.8精确；25−3.123456789=21.876543211；相等为0；超用下限0 | passed")
    }

    func testOpenRouterRejectsNonNumbersMissingFieldsAndClassifiesStatus() async {
        for json in [#"{"data":{"total_credits":"10","total_usage":1}}"#, #"{"data":{"total_credits":10}}"#,
                     #"{"data":{"total_credits":true,"total_usage":1}}"#, #"{"data":{"total_credits":null,"total_usage":1}}"#,
                     #"{"credits":10}"#, "not json"] {
            let result = await outcome(.openRouter, BalanceFakeTransport.openRouterRaw(json))
            XCTAssertEqual(result, .failed, json)
        }
        // A normal (non-management) key: official 403 “Only management keys…”.
        let normalKey = await outcome(.openRouter, BalanceFakeTransport.openRouterRaw(#"{"error":{"code":403,"message":"Only management keys can perform this operation"}}"#, status: 403))
        XCTAssertEqual(normalKey, .rejected)
        let invalid = await outcome(.openRouter, BalanceFakeTransport.openRouterRaw(#"{"error":{"code":401}}"#, status: 401))
        XCTAssertEqual(invalid, .rejected)
        let server = await outcome(.openRouter, BalanceFakeTransport.openRouter(credits: 1, usage: 0, status: 500))
        XCTAssertEqual(server, .failed)
        let html = await outcome(.openRouter, .init(status: 200, body: Data("<html></html>".utf8), mime: "text/html"))
        XCTAssertEqual(html, .failed)
        let timeout = await outcome(.openRouter, .init(status: 200, body: Data(), error: URLError(.timedOut)))
        XCTAssertEqual(timeout, .failed)
        print("T113 | OpenRouter异常 | 字符串/缺字段/布尔/null/非JSON→失败；403普通key与401→被拒；500/HTML/超时→失败 | passed")
    }

    func testDeepSeekCurrenciesDecimalAndUnavailableIsNotFailure() async throws {
        let one = try await query(.deepSeek, BalanceFakeTransport.deepSeek([BalanceFakeTransport.cny("110.00", toppedUp: "100.00", granted: "10.00")]))
        XCTAssertEqual(one.amounts, [BalanceAmount(currency: "CNY", total: 110, toppedUp: 100, granted: 10)])
        let two = try await query(.deepSeek, BalanceFakeTransport.deepSeek([
            BalanceFakeTransport.cny("0.005"), ["currency": "usd", "total_balance": "1234.5678", "granted_balance": "0"]],
            available: false))
        XCTAssertEqual(two.amounts.map(\.currency), ["CNY", "USD"])
        XCTAssertEqual(two.amounts[0].total, Decimal(string: "0.005"))
        XCTAssertEqual(two.amounts[1].total, Decimal(string: "1234.5678"))
        XCTAssertNil(two.amounts[1].toppedUp, "missing part is unknown, not 0")
        XCTAssertEqual(two.amounts[1].granted, 0)
        let zero = try await query(.deepSeek, BalanceFakeTransport.deepSeek([BalanceFakeTransport.cny("0.00", toppedUp: "0.00", granted: "0.00")], available: false))
        XCTAssertEqual(zero.amounts.first?.total, 0)
        print("T113 | DeepSeek解析 | CNY110/100/10；CNY+USD两行、小数精确、缺充值为未知；is_available=false仍成功；0余额 | passed")
    }

    func testDeepSeekMalformedAndStatuses() async {
        let cases: [BalanceFakeTransport.Reply] = [
            BalanceFakeTransport.deepSeek([]),
            BalanceFakeTransport.deepSeek([["currency": "CNY"]]),
            BalanceFakeTransport.deepSeek([["currency": "CNY", "total_balance": 12.5]]),
            BalanceFakeTransport.deepSeek([["currency": "CNY", "total_balance": "abc"]]),
            BalanceFakeTransport.deepSeek([BalanceFakeTransport.cny("1", toppedUp: "x")]),
            BalanceFakeTransport.deepSeek([BalanceFakeTransport.cny("1"), BalanceFakeTransport.cny("2")]),
            BalanceFakeTransport.deepSeek([["currency": "RMB元", "total_balance": "1"]]),
            .init(status: 200, body: Data(#"{"balance_infos":[{"currency":"CNY","total_balance":"1"}]}"#.utf8)),
        ]
        for (index, reply) in cases.enumerated() {
            let result = await outcome(.deepSeek, reply)
            XCTAssertEqual(result, .failed, "case \(index)")
        }
        let rejected = await outcome(.deepSeek, BalanceFakeTransport.deepSeek([], status: 401))
        XCTAssertEqual(rejected, .rejected)
        let forbidden = await outcome(.deepSeek, BalanceFakeTransport.deepSeek([], status: 403))
        XCTAssertEqual(forbidden, .rejected)
        let server = await outcome(.deepSeek, BalanceFakeTransport.deepSeek([BalanceFakeTransport.cny("1")], status: 503))
        XCTAssertEqual(server, .failed)
        let offline = await outcome(.deepSeek, .init(status: 0, body: Data(), error: URLError(.notConnectedToInternet)))
        XCTAssertEqual(offline, .failed)
        print("T113 | DeepSeek异常 | 空数组/缺总额/数字非字符串/非数字/重复币种/非法币种/缺is_available→失败；401/403被拒；503/离线失败 | passed")
    }

    func testRequestGoesOnlyToTheFixedHostWithBearer() async throws {
        let transport = BalanceFakeTransport(openRouter: BalanceFakeTransport.openRouter(credits: 2, usage: 1),
                                             deepSeek: BalanceFakeTransport.deepSeek([BalanceFakeTransport.cny("1")]))
        let client = APIBalanceClient(transport: transport)
        _ = try await client.balance(.openRouter, key: key, observedAt: time)
        _ = try await client.balance(.deepSeek, key: key, observedAt: time)
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.url), [URL(string: "https://openrouter.ai/api/v1/credits")!,
                                             URL(string: "https://api.deepseek.com/user/balance")!])
        XCTAssertTrue(requests.allSatisfy(\.bearer))
        do { _ = try await client.balance(.cursor, key: key, observedAt: time); XCTFail() } catch {}
    }

    // MARK: Refresh paths

    actor CodexDouble: CodexQuotaUpdating {
        private(set) var calls = 0
        var fail = false
        func setFail(_ value: Bool) { fail = value }
        func update(_ account: ConnectedAccount) async throws -> ConnectedAccount {
            calls += 1
            if fail { throw CodexQuotaError.failed }
            return account
        }
    }

    private struct Setup {
        let store: AccountStore
        let vault: CredentialVault
        let flow: CodexConnectionFlow
        let transport: BalanceFakeTransport
        let codex: CodexDouble
        let codexAccount: ConnectedAccount
        let openRouter: ConnectedAccount
        let deepSeek: ConnectedAccount
        let updater: CoordinatedQuotaUpdater
    }

    private func setup(network: NetworkScoreResult = .allowed(score: 80)) async throws -> Setup {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T113-\(UUID().uuidString)")
        let service = "com.iceflying.SubscriptionUsage.tests.T113.\(UUID().uuidString)"
        let vault = CredentialVault(service: service)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: "\(service).credentials"] as CFDictionary)
        }
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let bindings = CodexAccountBindingStore(accountStore: store, vault: vault)
        let codexAccount = ConnectedAccount(remoteUserID: "u-a", verifiedEmail: "a@example.invalid",
            scope: .init(remoteAccountID: "acct-a", kind: .personal), credentialRef: UUID())
        try await store.append(codexAccount)
        let openRouter = try await bindings.save(balance: .init(provider: .openRouter, credential: key,
            balance: APIBalanceStoreTests.usd("1.00", at: time.addingTimeInterval(-3600))))
        let deepSeek = try await bindings.save(balance: .init(provider: .deepSeek, credential: APIBalanceStoreTests.key("dddd"),
            balance: APIBalanceSnapshot(amounts: [BalanceAmount(currency: "CNY", total: 3)], observedAt: time.addingTimeInterval(-3600))))
        let transport = BalanceFakeTransport(openRouter: BalanceFakeTransport.openRouter(credits: 12.5, usage: 2.25),
                                             deepSeek: BalanceFakeTransport.deepSeek([BalanceFakeTransport.cny("66.60")]))
        let codex = CodexDouble()
        let updater = CoordinatedQuotaUpdater(store: store, service: codex, cursorService: FailingCodexService(),
            balanceService: APIBalanceService(store: store, loadCredential: { try await vault.load(for: .credential($0)) },
                transport: transport, checkNetwork: { network }, now: { [time] in time }))
        let flow = CodexConnectionFlow(transactions: CodexLoginTransactionStore(vault: vault), bindings: bindings,
            quotaUpdater: updater, foregroundRefreshEnabled: false, now: { [time] in time })
        await flow.loadAccounts()
        await flow.waitForInitialQuota()
        return Setup(store: store, vault: vault, flow: flow, transport: transport, codex: codex, codexAccount: codexAccount,
                     openRouter: openRouter, deepSeek: deepSeek, updater: updater)
    }

    func testMixedRefreshPathsAreIndependent() async throws {
        let s = try await setup()
        // Cold load (opening the App) already queried every account through its own service.
        var or = try XCTUnwrap(s.flow.accounts.first { $0.id == s.openRouter.id })
        XCTAssertEqual(or.balance?.amounts.first?.total, Decimal(string: "10.25"))
        XCTAssertEqual(or.balance?.observedAt, time)
        let ds = try XCTUnwrap(s.flow.accounts.first { $0.id == s.deepSeek.id })
        XCTAssertEqual(ds.balance?.amounts.first?.total, Decimal(string: "66.60"))
        XCTAssertEqual(ds.balance?.amounts.first?.toppedUp, 8)
        let coldCodexCalls = await s.codex.calls
        XCTAssertEqual(coldCodexCalls, 1)

        // DeepSeek fails on pull-to-refresh: it keeps its value and time, others still update.
        await s.transport.set(APIBalanceClient.deepSeekURL, BalanceFakeTransport.deepSeek([], status: 500))
        await s.transport.set(APIBalanceClient.openRouterURL, BalanceFakeTransport.openRouter(credits: 12.5, usage: 3))
        s.flow.refreshAllQuota()
        XCTAssertEqual(s.flow.quotaUpdatingIDs, [s.codexAccount.id, s.openRouter.id, s.deepSeek.id])
        await s.flow.waitForInitialQuota()
        or = try XCTUnwrap(s.flow.accounts.first { $0.id == s.openRouter.id })
        XCTAssertEqual(or.balance?.amounts.first?.total, Decimal(string: "9.5"))
        let failedDS = try XCTUnwrap(s.flow.accounts.first { $0.id == s.deepSeek.id })
        XCTAssertEqual(failedDS.balance, ds.balance, "old value and its success time kept")
        XCTAssertEqual(s.flow.quotaFailureID, s.deepSeek.id)
        XCTAssertEqual(s.flow.quotaFailure, "刷新失败")
        let codexCalls = await s.codex.calls
        XCTAssertEqual(codexCalls, 2)
        let failure = try await s.store.quotaFailure(for: s.deepSeek.id)
        XCTAssertEqual(failure, .refresh)

        // A refused key is the same simple failure; single-card refresh touches that card only.
        await s.transport.set(APIBalanceClient.openRouterURL, BalanceFakeTransport.openRouterRaw("{}", status: 403))
        s.flow.refreshQuota(for: s.openRouter.id)
        XCTAssertEqual(s.flow.quotaUpdatingIDs, [s.openRouter.id])
        await s.flow.waitForInitialQuota()
        XCTAssertEqual(s.flow.quotaFailures[s.openRouter.id], "刷新失败")
        XCTAssertEqual(s.flow.accounts.first { $0.id == s.openRouter.id }?.balance, or.balance)
        let codexAfter = await s.codex.calls
        XCTAssertEqual(codexAfter, 2)
        print("T113 | 混合刷新 | 冷启动三账户各走各的查询；DeepSeek失败保留旧值与时间，OpenRouter/Codex照常；403与单卡刷新只影响本卡 | passed")
    }

    func testNetworkGateBlocksBeforeAnyRequest() async throws {
        let s = try await setup(network: .blocked(score: 20))
        let requests = await s.transport.requests
        XCTAssertTrue(requests.isEmpty, "no balance request when the network check fails")
        XCTAssertEqual(s.flow.quotaFailures[s.openRouter.id], "网络不达标，无法更新")
        XCTAssertEqual(s.flow.accounts.first { $0.id == s.openRouter.id }?.balance?.observedAt, time.addingTimeInterval(-3600))
        let failure = try await s.store.quotaFailure(for: s.openRouter.id)
        XCTAssertEqual(failure, .networkBlocked)
    }

    func testAutomaticUpdateSkipsWithinIntervalAndQueriesAfter() async throws {
        let s = try await setup()
        let before = await s.transport.requests.count
        let loaded = try await s.store.load()
        let fresh = try XCTUnwrap(loaded.first { $0.id == s.openRouter.id })
        var opportunistic = s.updater
        opportunistic.opportunistic = true
        _ = try await opportunistic.update(fresh)
        let afterSkip = await s.transport.requests.count
        XCTAssertEqual(afterSkip, before, "widget / background update skips a success under 30 minutes old")
        opportunistic.now = { [time] in time.addingTimeInterval(31 * 60) }
        _ = try await opportunistic.update(fresh)
        let afterQuery = await s.transport.requests.count
        XCTAssertEqual(afterQuery, before + 1)
    }

    func testKeyRemovedOrSwappedNeverSavesAnotherKeysResult() async throws {
        let s = try await setup()
        let loaded = try await s.store.load()
        let current = try XCTUnwrap(loaded.first { $0.id == s.openRouter.id })
        try await s.vault.save(APIBalanceStoreTests.key("ffff").payload, for: .credential(current.credentialRef))
        await s.transport.set(APIBalanceClient.openRouterURL, BalanceFakeTransport.openRouter(credits: 99, usage: 0))
        do { _ = try await s.updater.update(current); XCTFail() } catch {}
        let after = try await s.store.load().first { $0.id == s.openRouter.id }
        XCTAssertEqual(after?.balance, current.balance)
    }
}
