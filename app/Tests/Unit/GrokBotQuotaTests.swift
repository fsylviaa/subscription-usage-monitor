import XCTest
@testable import SubscriptionUsage

/// T106: Grok Bot weekly quota on a Cursor account (D-80), isolated (fake transport,
/// temporary store, in-memory credential; no network).
final class GrokBotQuotaTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_791_590_400)
    private let parser = CursorUsageParser()
    private static let reset = "2026-10-20T07:00:00.000Z"

    /// Structure of the T105 de-identified sample; values are fixtures. Plan names are present but never read.
    static func sand(used: Any? = 75.5, reset: Any? = GrokBotQuotaTests.reset, nonZero: Any? = true,
                     limitZero: Any? = nil, trial: Any? = nil) -> Data {
        var root: [String: Any] = ["billingBrand": "text", "currentPeriodStart": "2026-10-13T07:00:00.000Z",
            "cursorPlanName": "text", "grokPlanLabel": "text", "hasAvailableUsage": true,
            "onDemandSettings": ["dashboardUrl": "text", "eligible": true, "enabled": true, "visible": true],
            "unifiedPlanMigration": ["href": "text"], "upgradeRecommendations": [[String: Any]]()]
        if let used { root["usagePercent"] = used }
        if let reset { root["nextResetTimestampUtc"] = reset }
        if let nonZero { root["hasNonZeroIncludedLimit"] = nonZero }
        if let limitZero { root["includedLimitZero"] = limitZero }
        if let trial { root["sandTrialExpiresAt"] = trial }
        return try! JSONSerialization.data(withJSONObject: root)
    }

    static func summary(total: Double) -> Data {
        try! JSONSerialization.data(withJSONObject: ["billingCycleEnd": "2026-11-12T08:00:00.000Z", "membershipType": "pro",
            "limitType": "user", "individualUsage": ["plan": ["enabled": true, "totalPercentUsed": total]]])
    }

    private func remaining(_ data: Data) throws -> Double? {
        try parser.grokBot(data, observedAt: time).displayed?.amount.remainingPercent
    }

    // MARK: Parser

    func testT106ParsingSampleAndEdges() throws {
        var rows: [String] = []
        let sample = try parser.grokBot(Self.sand(), observedAt: time)
        XCTAssertEqual(sample.state, .available); XCTAssertEqual(sample.window?.window, .weekly)
        XCTAssertEqual(try XCTUnwrap(sample.window?.amount.remainingPercent), 24.5, accuracy: 1e-9)
        XCTAssertEqual(sample.window?.resetsAt, ISO8601DateFormatter().date(from: "2026-10-20T07:00:00Z"))
        XCTAssertEqual(sample.window?.observedAt, time)
        rows.append("T105样本 usagePercent=75.5 → 剩余24.5%，重置=nextResetTimestampUtc")
        XCTAssertEqual(try remaining(Self.sand(used: 0)), 100); rows.append("0 → 剩余100%")
        XCTAssertEqual(try remaining(Self.sand(used: 100)), 0); rows.append("100（用完）→ 剩余0%")
        XCTAssertEqual(try XCTUnwrap(try remaining(Self.sand(used: 33.333))), 66.667, accuracy: 1e-9); rows.append("33.333 → 剩余66.667%")
        XCTAssertEqual(try remaining(Self.sand(used: 0.4)), 99.6); rows.append("0.4 → 剩余99.6%（不×100）")
        XCTAssertEqual(try remaining(Self.sand(used: 128)), 0); rows.append("128（超用）→ 剩余0%")
        XCTAssertNil(try parser.grokBot(Self.sand(reset: NSNull()), observedAt: time).window?.resetsAt)
        rows.append("无重置时间 → 未提供，不编造")
        // Only the newer flag present (T105 device sample had no includedLimitZero).
        XCTAssertEqual(try remaining(Self.sand(nonZero: nil, limitZero: false)), 24.5); rows.append("includedLimitZero=false → 有额度")
        XCTAssertEqual(try remaining(Self.sand(nonZero: nil)), 24.5); rows.append("两个标志都缺、有百分比 → 有额度")
        print("T106 | 解析 | " + rows.joined(separator: "；") + " | passed")
    }

    func testT106NoIncludedQuotaHidesRow() throws {
        let future = "2026-12-01T00:00:00.000Z"
        for (name, data) in [
            ("hasNonZeroIncludedLimit=false", Self.sand(used: 0, nonZero: false)),
            ("includedLimitZero=true", Self.sand(used: 0, nonZero: nil, limitZero: true)),
            ("includedLimitZero优先于hasNonZero", Self.sand(nonZero: true, limitZero: true)),
            ("仅免费试用（无套餐内额度、试用未到期）", Self.sand(used: 10, nonZero: false, trial: future)),
            ("无套餐内额度且无百分比", Self.sand(used: nil, reset: nil, nonZero: false)),
        ] {
            let value = try parser.grokBot(data, observedAt: time)
            XCTAssertEqual(value, .notApplicable, name); XCTAssertNil(value.displayed, name)
        }
        print("T106 | 无额度 | 无套餐内额度／仅试用5类 → 整行不显示（notApplicable） | passed")
    }

    func testT106MissingOrInvalidIsFailureNeverZero() throws {
        for (name, data) in [
            ("有额度但缺usagePercent", Self.sand(used: nil)),
            ("usagePercent为字符串", Self.sand(used: "75")),
            ("usagePercent为布尔", Self.sand(used: true)),
            ("usagePercent为负", Self.sand(used: -1)),
            ("空正文", Data()), ("非JSON", Data("oops".utf8)), ("数组", Data("[1]".utf8)),
        ] {
            XCTAssertThrowsError(try parser.grokBot(data, observedAt: time), name)
        }
        print("T106 | 缺值/异常 | 7类输入均判失败（保留旧值），没有落成0或满额 | passed")
    }

    // MARK: Service and store

    func testT106ServiceSavesBothWithSeparateTimes() async throws {
        let setup = try await GrokSetup.make()
        let transport = CursorFakeTransport(me: GrokSetup.me(), usage: Self.summary(total: 20), grokBot: Self.sand())
        let updated = try await setup.service(transport, now: time).update(setup.account)
        XCTAssertEqual(updated.quotaSnapshot?.weekly.amount.remainingPercent, 80)
        XCTAssertEqual(updated.grokBot?.state, .available)
        XCTAssertEqual(try XCTUnwrap(updated.grokBot?.window?.amount.remainingPercent), 24.5, accuracy: 1e-9)
        XCTAssertEqual(updated.grokBot?.window?.observedAt, time)
        let failure = try await setup.store.quotaFailure(for: updated.id)
        XCTAssertNil(failure)
        let requests = await transport.requests
        let grok = try XCTUnwrap(requests.last)
        XCTAssertEqual(grok.url, CursorAPIClient.grokBotURL); XCTAssertEqual(grok.httpMethod, "POST")
        XCTAssertEqual(grok.httpBody, Data("{}".utf8))
        XCTAssertEqual(grok.value(forHTTPHeaderField: "Origin"), "https://cursor.com")
        XCTAssertEqual(grok.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertTrue(grok.value(forHTTPHeaderField: "Cookie")?.hasPrefix("WorkosCursorSessionToken=user_1%3A%3A") == true)
        XCTAssertNil(grok.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(grok.url?.query)
        // Saved file round-trips.
        let reloaded = try await AccountStore(fileURL: setup.fileURL).load()
        XCTAssertEqual(reloaded.first?.grokBot, updated.grokBot)
        print("T106 | 服务 | 同一次刷新：本月剩余80%、Grok Bot剩余24.5%，各自成功时间；POST {}＋Cookie＋Origin，只到cursor.com | passed")
    }

    func testT106GrokBotFailureKeepsItsOldValueAndMonthlySucceeds() async throws {
        let setup = try await GrokSetup.make()
        let transport = CursorFakeTransport(me: GrokSetup.me(), usage: Self.summary(total: 20), grokBot: Self.sand())
        let good = try await setup.service(transport, now: time).update(setup.account)
        let oldGrok = try XCTUnwrap(good.grokBot)
        var rows: [String] = []
        let cases: [(String, (CursorFakeTransport) async -> Void)] = [
            ("非200（500）", { await $0.setGrokBot(Self.sand(), status: 500) }),
            ("401", { await $0.setGrokBot(Self.sand(), status: 401) }),
            ("超时", { await $0.setGrokBotError(URLError(.timedOut)) }),
            ("缺usagePercent", { await $0.setGrokBot(Self.sand(used: nil)) }),
            ("异常JSON", { await $0.setGrokBot(Data("{".utf8)) }),
        ]
        var current = good
        for (offset, (name, configure)) in cases.enumerated() {
            await configure(transport)
            await transport.setUsage(Self.summary(total: Double(30 + offset)))
            let later = time.addingTimeInterval(Double(60 * (offset + 1)))
            do { _ = try await setup.service(transport, now: later).update(current); XCTFail(name) }
            catch { XCTAssertEqual(error as? CodexQuotaError, .failed, name) }
            let list = try await setup.store.load()
            let saved = try XCTUnwrap(list.first)
            XCTAssertEqual(saved.grokBot, oldGrok, "\(name)：Grok Bot保留旧值与原成功时间")
            XCTAssertEqual(saved.quotaSnapshot?.observedAt, later, "\(name)：本月成功照常保存")
            XCTAssertEqual(saved.quotaSnapshot?.weekly.amount.usedPercent, Double(30 + offset))
            let failure = try await setup.store.quotaFailure(for: saved.id)
            XCTAssertEqual(failure, .refresh, "\(name)：提示刷新失败")
            current = saved
            rows.append(name)
        }
        // Next full success clears the failure and updates both.
        await transport.setGrokBot(Self.sand(used: 100))
        let recovered = try await setup.service(transport, now: time.addingTimeInterval(3600)).update(current)
        XCTAssertEqual(recovered.grokBot?.window?.amount.remainingPercent, 0, "用完如实0%")
        let cleared = try await setup.store.quotaFailure(for: recovered.id)
        XCTAssertNil(cleared)
        print("T106 | Grok Bot失败 | " + rows.joined(separator: "；") + " → Grok Bot旧值24.5%与原成功时间保留、本月照常更新、标记刷新失败；恢复后清除 | passed")
    }

    func testT106MonthlyFailureKeepsMonthlyAndSavesGrokBot() async throws {
        let setup = try await GrokSetup.make()
        let transport = CursorFakeTransport(me: GrokSetup.me(), usage: Self.summary(total: 20), grokBot: Self.sand())
        let good = try await setup.service(transport, now: time).update(setup.account)
        let oldMonthly = try XCTUnwrap(good.quotaSnapshot)
        await transport.setUsageStatus(500)
        await transport.setGrokBot(Self.sand(used: 80))
        let later = time.addingTimeInterval(60)
        do { _ = try await setup.service(transport, now: later).update(good); XCTFail() }
        catch { XCTAssertEqual(error as? CodexQuotaError, .failed) }
        let list = try await setup.store.load()
        var saved = try XCTUnwrap(list.first)
        XCTAssertEqual(saved.quotaSnapshot, oldMonthly, "本月保留旧值与原成功时间")
        XCTAssertEqual(saved.grokBot?.window?.amount.remainingPercent, 20); XCTAssertEqual(saved.grokBot?.window?.observedAt, later)
        var failure = try await setup.store.quotaFailure(for: saved.id)
        XCTAssertEqual(failure, .refresh)
        // Both fail: nothing changes except the failure mark.
        await transport.setGrokBot(Self.sand(), status: 500)
        let before = saved
        do { _ = try await setup.service(transport, now: later.addingTimeInterval(60)).update(saved); XCTFail() }
        catch { XCTAssertEqual(error as? CodexQuotaError, .failed) }
        let list2 = try await setup.store.load()
        saved = try XCTUnwrap(list2.first)
        XCTAssertEqual(saved, before)
        failure = try await setup.store.quotaFailure(for: saved.id)
        XCTAssertEqual(failure, .refresh)
        // Network gate failure: no Grok Bot request either.
        let count = await transport.requests.count
        do { _ = try await setup.service(transport, network: .blocked(score: 20), now: later.addingTimeInterval(120)).update(saved); XCTFail() }
        catch { XCTAssertEqual(error as? CodexQuotaError, .networkBlocked) }
        let after = await transport.requests.count
        XCTAssertEqual(after, count, "网络不达标不发请求")
        print("T106 | 本月失败 | 本月旧值保留、Grok Bot新值20%保存、标记刷新失败；两者都失败只标记失败；网络不达标不请求 | passed")
    }

    func testT106LaterNoQuotaHidesAndLegacyDataReads() async throws {
        let setup = try await GrokSetup.make()
        let transport = CursorFakeTransport(me: GrokSetup.me(), usage: Self.summary(total: 20), grokBot: Self.sand())
        let good = try await setup.service(transport, now: time).update(setup.account)
        await transport.setGrokBot(Self.sand(used: 0, nonZero: false))
        let none = try await setup.service(transport, now: time.addingTimeInterval(60)).update(good)
        XCTAssertEqual(none.grokBot, .notApplicable); XCTAssertNil(none.grokBot?.displayed)

        // A file written before D-80 (no grokBot key) still reads, monthly intact.
        let legacy = try JSONEncoder().encode(good)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        object.removeValue(forKey: "grokBot")
        let decoded = try JSONDecoder().decode(ConnectedAccount.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.grokBot); XCTAssertEqual(decoded.quotaSnapshot, good.quotaSnapshot)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T106-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("accounts.json")
        let document: [String: Any] = ["schemaVersion": 1, "accounts": [object]]
        try JSONSerialization.data(withJSONObject: document).write(to: url)
        let loaded = try await AccountStore(fileURL: url).load()
        XCTAssertEqual(loaded.first?.quotaSnapshot, good.quotaSnapshot); XCTAssertNil(loaded.first?.grokBot)
        print("T106 | 无额度与旧数据 | 后来无套餐内额度 → 隐藏；D-80前的文件读回本月不丢、Grok Bot为未获取 | passed")
    }

    func testT106SameEmailReAddDeletionAndValidation() async throws {
        let setup = try await GrokSetup.make()
        let transport = CursorFakeTransport(me: GrokSetup.me(), usage: Self.summary(total: 20), grokBot: Self.sand())
        let good = try await setup.service(transport, now: time).update(setup.account)
        // Same email, same person re-added: keeps position and Grok Bot value.
        let again = ConnectedAccount(provider: .cursor, product: .cursorSubscription, remoteUserID: good.remoteUserID,
            verifiedEmail: good.verifiedEmail, scope: good.scope, credentialRef: UUID())
        let replaced = try await setup.store.commitLogin(again)
        XCTAssertEqual(replaced.id, good.id); XCTAssertEqual(replaced.grokBot, good.grokBot)
        // Same email but a different subject: old values are dropped.
        let other = ConnectedAccount(provider: .cursor, product: .cursorSubscription, remoteUserID: "google-oauth2|other",
            verifiedEmail: good.verifiedEmail, scope: .init(remoteAccountID: "google-oauth2|other", kind: .personal), credentialRef: UUID())
        let switched = try await setup.store.commitLogin(other)
        XCTAssertNil(switched.grokBot); XCTAssertNil(switched.quotaSnapshot)
        // Deletion removes the record, Grok Bot included.
        _ = try await setup.store.markForDeletion(switched.id)
        try await setup.store.finishDeletion(switched.id)
        let remaining = try await setup.store.load()
        XCTAssertTrue(remaining.isEmpty)
        // A Grok Bot value can never be attached to a Codex account.
        var codex = ConnectedAccount(verifiedEmail: "codex@example.invalid",
            scope: .init(remoteAccountID: "acct", kind: .personal), credentialRef: UUID())
        codex.grokBot = good.grokBot
        do { try await setup.store.append(codex); XCTFail() }
        catch { XCTAssertEqual(error as? AccountStore.StoreError, .invalidQuotaSnapshot) }
        print("T106 | 账户处理 | 同邮箱同人重复添加保留Grok Bot；同邮箱换人清空；删除随账户移除；Codex账户不能带Grok Bot | passed")
    }
}

/// Isolated store with one Cursor account and an in-memory credential.
private struct GrokSetup {
    let store: AccountStore
    let fileURL: URL
    let account: ConnectedAccount
    let payload: CredentialPayload

    static func token(sub: String) -> String {
        func b64(_ s: String) -> String {
            Data(s.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return b64(#"{"alg":"none"}"#) + "." + b64("{\"sub\":\"\(sub)\",\"exp\":9999999999}") + ".sig"
    }

    static func me() -> Data {
        try! JSONSerialization.data(withJSONObject: ["email": "cursor@example.invalid", "sub": "google-oauth2|user_1"])
    }

    static func make() async throws -> GrokSetup {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("T106-\(UUID().uuidString)/accounts.json")
        let store = AccountStore(fileURL: url)
        let account = ConnectedAccount(provider: .cursor, product: .cursorSubscription, remoteUserID: "google-oauth2|user_1",
            verifiedEmail: "cursor@example.invalid", scope: .init(remoteAccountID: "google-oauth2|user_1", kind: .personal),
            credentialRef: UUID())
        try await store.append(account)
        let payload = try CursorCredential(accessToken: token(sub: "google-oauth2|user_1"), refreshToken: "refresh").payload
        return GrokSetup(store: store, fileURL: url, account: account, payload: payload)
    }

    func service(_ transport: CursorFakeTransport, network: NetworkScoreResult = .allowed(score: 80), now: Date) -> CursorQuotaService {
        let payload = payload
        return CursorQuotaService(store: store, loadCredential: { _ in payload }, transport: transport,
                                  checkNetwork: { network }, now: { now })
    }
}
