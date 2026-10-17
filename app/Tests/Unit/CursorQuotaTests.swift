import XCTest
@testable import SubscriptionUsage

/// T92: Cursor usage interpretation and the refresh service, isolated (fake
/// transport, temporary store, in-memory credential; no network).
final class CursorQuotaTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_791_590_400)
    private let parser = CursorUsageParser()

    /// Structure of the T89 de-identified sample; values are fixtures.
    private func summary(total: Any? = 36, plan: [String: Any]? = nil, membership: Any = "pro", limitType: Any = "user",
                         individual: Any? = nil, end: Any = "2026-11-12T08:00:00.000Z") -> Data {
        var planObject: [String: Any] = ["apiPercentUsed": 20, "autoPercentUsed": 52,
            "breakdown": ["bonus": 0, "included": 720, "total": 720], "enabled": true,
            "limit": 2000, "remaining": 1280, "used": 720]
        if let total { planObject["totalPercentUsed"] = total }
        if let plan { planObject = plan }
        let root: [String: Any] = [
            "autoModelSelectedDisplayMessage": "text", "billingCycleEnd": end,
            "billingCycleStart": "2026-10-12T08:00:00.000Z",
            "individualUsage": individual ?? ["onDemand": ["enabled": true, "limit": NSNull(), "remaining": NSNull(), "used": 0],
                                              "plan": planObject],
            "isUnlimited": false, "limitType": limitType, "membershipType": membership,
            "namedModelSelectedDisplayMessage": "text", "teamUsage": [String: Any]()]
        return try! JSONSerialization.data(withJSONObject: root)
    }

    private func used(_ data: Data) throws -> Double? {
        guard case let .available(_, value, _) = try parser.interpret(data, observedAt: time) else { return nil }
        return value
    }

    func testT92SampleAndPercentUnits() throws {
        var rows: [String] = []
        // T89 sample shape: totalPercentUsed is already a percentage.
        guard case let .available(subscription, value, resetsAt) = try parser.interpret(summary(), observedAt: time) else {
            return XCTFail("样本必须得到本月额度")
        }
        XCTAssertEqual(value, 36); XCTAssertEqual(subscription.planType, "pro")
        XCTAssertEqual(resetsAt, ISO8601DateFormatter().date(from: "2026-11-12T08:00:00Z"))
        rows.append("T89样本 totalPercentUsed=36 → 已用36%（剩余64%），重置=billingCycleEnd")
        // 0.36 means 0.36%, never 36%.
        XCTAssertEqual(try used(summary(total: 0.36)), 0.36); rows.append("0.36 → 已用0.36%（剩余99.64%）")
        XCTAssertEqual(try used(summary(total: 0)), 0); rows.append("0 → 剩余100%")
        XCTAssertEqual(try used(summary(total: 100)), 100); rows.append("100 → 剩余0%")
        XCTAssertEqual(try used(summary(total: 66.67)), 66.67); rows.append("66.67 → 剩余33.33%")
        // Used up with on-demand billing on: truthfully 0% remaining.
        XCTAssertEqual(try used(summary(total: 142.5)), 100); rows.append("142.5（用完且开按量付费）→ 剩余0%")
        // No total: used/limit (both cents) as a percentage.
        XCTAssertEqual(try used(summary(plan: ["enabled": true, "used": 500, "limit": 2000])), 25)
        rows.append("无total，used=500/limit=2000（美分）→ 已用25%")
        // Missing reset time is shown as not provided, not invented.
        guard case let .available(_, _, missingEnd) = try parser.interpret(summary(end: NSNull()), observedAt: time) else { return XCTFail() }
        XCTAssertNil(missingEnd); rows.append("billingCycleEnd缺失 → 未提供重置时间")
        print("T92 | 解析样本 | " + rows.joined(separator: "；") + " | passed")
    }

    func testT92MissingValuesAreNeverZero() throws {
        for (name, data) in [
            ("plan启用但无任何百分比", summary(plan: ["enabled": true])),
            ("只有used无limit", summary(plan: ["enabled": true, "used": 10])),
            ("百分比是字符串且无used/limit", summary(plan: ["enabled": true, "totalPercentUsed": "36"])),
            ("百分比为负", summary(total: -1)),
            ("limit为负", summary(plan: ["enabled": true, "used": 1, "limit": -5])),
            ("individualUsage类型错误", summary(individual: "x")),
            ("plan类型错误", summary(individual: ["plan": 3])),
        ] {
            XCTAssertThrowsError(try parser.interpret(data, observedAt: time), name)
        }
        for body in ["", "not json", "[1,2]", "{\"membershipType\": 3, \"individualUsage\": {\"plan\": {\"enabled\": true}}}"] {
            XCTAssertThrowsError(try parser.interpret(Data(body.utf8), observedAt: time), body)
        }
        // A non-numeric total falls back to the plan's own used/limit (720/2000), never to 0.
        XCTAssertEqual(try used(summary(total: "36")), 36)
        print("T92 | 缺值/异常 | 11类输入均判失败（保留旧值），没有一个落成0 | passed")
    }

    func testT92NoPersonalQuotaIsNotApplicable() throws {
        func isNotApplicable(_ data: Data) throws -> Bool {
            if case .notApplicable = try parser.interpret(data, observedAt: time) { return true }
            return false
        }
        XCTAssertTrue(try isNotApplicable(summary(membership: "team")), "团队")
        XCTAssertTrue(try isNotApplicable(summary(membership: "enterprise")), "企业")
        XCTAssertTrue(try isNotApplicable(summary(membership: "business")), "Business")
        XCTAssertTrue(try isNotApplicable(summary(limitType: "team")), "limitType=team")
        XCTAssertTrue(try isNotApplicable(summary(membership: "free", individual: NSNull())), "免费版无个人数据")
        XCTAssertTrue(try isNotApplicable(Data("{\"membershipType\":\"free\"}".utf8)), "免费版只有套餐")
        XCTAssertTrue(try isNotApplicable(summary(membership: "free", individual: ["plan": NSNull()])), "plan为null")
        XCTAssertTrue(try isNotApplicable(summary(plan: ["enabled": false])), "plan未启用")
        XCTAssertTrue(try isNotApplicable(summary(plan: ["enabled": true, "used": 0, "limit": 0], membership: "hobby")), "limit为0")
        // A free plan that does report a personal percentage still shows it.
        XCTAssertEqual(try used(summary(total: 12, membership: "free")), 12)
        print("T92 | 无个人额度 | 团队/企业/Business/limitType=team/免费无数据/plan为null/未启用/limit=0 → 无适用额度；免费版有数据照常显示 | passed")
    }

    func testT92IdentityParsing() throws {
        let me = Data(#"{"automation_client":false,"created_at":"2026-01-01T00:00:00Z","email":"Cursor@Example.invalid","email_verified":true,"id":1,"name":"n","picture":"p","sub":"google-oauth2|user_1","updated_at":"2026-01-01T00:00:00Z"}"#.utf8)
        let identity = try parser.identity(me)
        XCTAssertEqual(identity, .init(email: "Cursor@Example.invalid", subject: "google-oauth2|user_1"))
        for bad in ["{}", #"{"email":"a@b.c"}"#, #"{"sub":"x"}"#, #"{"email":"no-at","sub":"x"}"#, "oops"] {
            XCTAssertThrowsError(try parser.identity(Data(bad.utf8)), bad)
        }
    }

    // MARK: Service

    func testT92ServiceSavesMonthlyQuotaOnlyForTheSamePerson() async throws {
        let setup = try await Setup.make(time: time)
        let transport = CursorFakeTransport(me: Setup.me(), usage: summary(total: 66.67))
        let updated = try await setup.service(transport).update(setup.account)
        XCTAssertEqual(updated.quotaState, .available)
        XCTAssertEqual(updated.quotaSnapshot?.weekly.window, .monthly)
        XCTAssertEqual(try XCTUnwrap(updated.quotaSnapshot?.weekly.amount.remainingPercent), 33.33, accuracy: 1e-9)
        XCTAssertEqual(updated.quotaSnapshot?.fiveHours.isApplicable, false)
        let input = QuotaStyledInput(account: WidgetSnapshot.projecting([updated]).account)
        XCTAssertEqual(input.windows.map(\.title), ["本月"]); XCTAssertEqual(input.platform, .cursor)
        // Only cookie auth, only cursor.com; the token never travels in a URL.
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.url), [CursorAPIClient.meURL, CursorAPIClient.usageURL, CursorAPIClient.grokBotURL])
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cookie")?.hasPrefix("WorkosCursorSessionToken=user_1%3A%3A") == true })
        XCTAssertTrue(requests.allSatisfy { $0.url?.query == nil && $0.value(forHTTPHeaderField: "Authorization") == nil })

        // Another person behind the stored credential: nothing is written.
        for other in [Setup.me(email: "other@example.invalid"), Setup.me(sub: "google-oauth2|someone_else")] {
            let before = try await setup.store.load()
            do { _ = try await setup.service(CursorFakeTransport(me: other, usage: summary(total: 1))).update(updated); XCTFail() }
            catch { XCTAssertEqual(error as? CodexQuotaError, .failed) }
            let after = try await setup.store.load()
            XCTAssertEqual(after.first?.quotaSnapshot, before.first?.quotaSnapshot, "身份不一致不写入额度")
        }
        print("T92 | 服务 | 同一人保存本月33.33%；邮箱或sub不同则不写额度 | passed")
    }

    func testT92ServiceFailuresKeepTrustedOldValue() async throws {
        let setup = try await Setup.make(time: time)
        let good = try await setup.service(CursorFakeTransport(me: Setup.me(), usage: summary(total: 20))).update(setup.account)
        let old = try XCTUnwrap(good.quotaSnapshot)
        let cases: [(String, CursorFakeTransport, NetworkScoreResult, CodexQuotaError)] = [
            ("auth/me 401（登录过期）", CursorFakeTransport(me: Setup.me(), usage: summary(), meStatus: 401), .allowed(score: 80), .failed),
            ("usage 500", CursorFakeTransport(me: Setup.me(), usage: summary(), usageStatus: 500), .allowed(score: 80), .failed),
            ("usage HTML", CursorFakeTransport(me: Setup.me(), usage: Data("<html>".utf8), mime: "text/html"), .allowed(score: 80), .failed),
            ("usage 缺百分比", CursorFakeTransport(me: Setup.me(), usage: summary(plan: ["enabled": true])), .allowed(score: 80), .failed),
            ("usage 异常JSON", CursorFakeTransport(me: Setup.me(), usage: Data("{".utf8)), .allowed(score: 80), .failed),
            ("网络不达标", CursorFakeTransport(me: Setup.me(), usage: summary()), .blocked(score: 30), .networkBlocked),
        ]
        var rows: [String] = []
        for (name, transport, network, expected) in cases {
            do { _ = try await setup.service(transport, network: network, now: time.addingTimeInterval(60)).update(good); XCTFail(name) }
            catch { XCTAssertEqual(error as? CodexQuotaError, expected, name) }
            let saved = try await setup.store.load()
            XCTAssertEqual(saved.first?.quotaSnapshot, old, "\(name)：保留旧值与原成功时间")
            XCTAssertEqual(saved.first?.quotaState, .available)
            let failure = try await setup.store.quotaFailure(for: good.id)
            let projected = WidgetSnapshot.projecting(saved, failures: failure.map { [good.id: $0] } ?? [:])
            XCTAssertEqual(QuotaStyledInput(account: projected.account).message,
                           expected == .networkBlocked ? "网络不达标，无法更新" : "刷新失败", name)
            if expected == .networkBlocked { let count = await transport.requests.count; XCTAssertEqual(count, 0, "网络不达标不发请求") }
            rows.append(name)
        }
        // No personal quota on a later refresh: shown as 无适用额度, never a fake 0.
        let none = try await setup.service(CursorFakeTransport(me: Setup.me(), usage: summary(membership: "team")),
                                           now: time.addingTimeInterval(120)).update(good)
        XCTAssertEqual(none.quotaState, .notApplicable); XCTAssertNil(none.quotaSnapshot)
        print("T92 | 服务失败 | " + rows.joined(separator: "；") + " → 均保留旧值和原成功时间；团队 → 无适用额度 | passed")
    }

    func testT92CredentialPayloadAndCookie() throws {
        let credential = CursorCredential(accessToken: Setup.token(sub: "auth0|abc_DEF-1.2"), refreshToken: "r")
        XCTAssertEqual(credential.userID, "abc_DEF-1.2")
        XCTAssertEqual(try CursorCredential(payload: try credential.payload), credential)
        XCTAssertFalse("\(credential)".contains(credential.accessToken))
        XCTAssertNil(CursorCredential(accessToken: "not-a-jwt", refreshToken: "r").cookie)
        XCTAssertThrowsError(try CursorCredential(payload: CredentialPayload(data: try JSONEncoder().encode(
            CursorCredential(accessToken: "a;b", refreshToken: "r")))))
    }
}

/// Isolated store with one Cursor account and an in-memory credential.
private struct Setup {
    let store: AccountStore
    let account: ConnectedAccount
    let payload: CredentialPayload

    static func token(sub: String) -> String {
        func b64(_ s: String) -> String {
            Data(s.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        }
        return b64(#"{"alg":"none"}"#) + "." + b64("{\"sub\":\"\(sub)\",\"exp\":9999999999}") + ".sig"
    }

    static func me(email: String = "cursor@example.invalid", sub: String = "google-oauth2|user_1") -> Data {
        try! JSONSerialization.data(withJSONObject: ["email": email, "sub": sub, "email_verified": true, "id": 1])
    }

    static func make(time: Date) async throws -> Setup {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T92-\(UUID().uuidString)")
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let account = ConnectedAccount(provider: .cursor, product: .cursorSubscription, remoteUserID: "google-oauth2|user_1",
            verifiedEmail: "cursor@example.invalid", scope: .init(remoteAccountID: "google-oauth2|user_1", kind: .personal),
            credentialRef: UUID())
        try await store.append(account)
        let payload = try CursorCredential(accessToken: token(sub: "google-oauth2|user_1"), refreshToken: "refresh").payload
        return Setup(store: store, account: account, payload: payload)
    }

    func service(_ transport: CursorFakeTransport, network: NetworkScoreResult = .allowed(score: 80),
                 now: Date = Date(timeIntervalSince1970: 1_791_590_400)) -> CursorQuotaService {
        let payload = payload
        return CursorQuotaService(store: store, loadCredential: { _ in payload }, transport: transport,
                                  checkNetwork: { network }, now: { now })
    }
}

actor CursorFakeTransport: CodexDeviceAuthorizationTransport {
    private var me: Data, usage: Data, meStatus: Int, usageStatus: Int
    private var grokBot: Data, grokBotStatus: Int
    private var grokBotError: URLError?
    private let mime: String
    private let gate: UsageGate?
    private(set) var requests: [URLRequest] = []

    /// Default Grok Bot reply: no included quota, so the row stays hidden (D-80).
    static let noGrokBot = Data(#"{"hasAvailableUsage":false,"hasNonZeroIncludedLimit":false}"#.utf8)

    init(me: Data, usage: Data, meStatus: Int = 200, usageStatus: Int = 200, mime: String = "application/json",
         gate: UsageGate? = nil, grokBot: Data = CursorFakeTransport.noGrokBot, grokBotStatus: Int = 200) {
        self.me = me; self.usage = usage; self.meStatus = meStatus; self.usageStatus = usageStatus
        self.mime = mime; self.gate = gate; self.grokBot = grokBot; self.grokBotStatus = grokBotStatus
    }

    func setMe(_ data: Data) { me = data }
    func setUsageStatus(_ status: Int) { usageStatus = status }
    func setUsage(_ data: Data) { usage = data }
    func setGrokBot(_ data: Data, status: Int = 200) { grokBot = data; grokBotStatus = status; grokBotError = nil }
    func setGrokBotError(_ error: URLError) { grokBotError = error }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let isMe = request.url == CursorAPIClient.meURL
        let isGrokBot = request.url == CursorAPIClient.grokBotURL
        if !isMe, !isGrokBot, let gate { await gate.wait() }
        if isGrokBot, let grokBotError { throw grokBotError }
        let status = isMe ? meStatus : isGrokBot ? grokBotStatus : usageStatus
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": isMe || isGrokBot ? "application/json" : mime])!
        return (isMe ? me : isGrokBot ? grokBot : usage, response)
    }
}
