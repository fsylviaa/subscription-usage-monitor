import XCTest
import Security
@testable import SubscriptionUsage

/// T93: adding a Cursor account through the real flow, binding store and
/// account file, with an isolated Keychain service and fake network only.
@MainActor
final class CursorConnectionTests: XCTestCase {
    private let time = Date(timeIntervalSince1970: 1_791_590_400)

    private struct Harness {
        let flow: CodexConnectionFlow
        let store: AccountStore
        let vault: CredentialVault
        let poller: CursorPollerStub
        let api: CursorFakeTransport
        let usage: CursorFakeTransport
        let opened: OpenedURLs
        let fileURL: URL
    }

    final class OpenedURLs { var urls: [URL] = [] }

    private func harness(polls: [CursorPollOutcome] = [.waiting, .waiting, .confirmed(CursorConnectionTests.cursorCredential())],
                         me: Data = CursorConnectionTests.me(), meStatus: Int = 200,
                         usage: Data = CursorConnectionTests.usage(used: 25), usageStatus: Int = 200,
                         network: [NetworkScoreResult] = [.allowed(score: 80)],
                         gate: UsageGate? = nil) async throws -> Harness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T93-\(UUID().uuidString)")
        let service = "com.iceflying.SubscriptionUsage.tests.T93.\(UUID().uuidString)"
        let vault = CredentialVault(service: service)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
            for namespace in ["credentials", "login-transactions"] {
                SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: "\(service).\(namespace)"] as CFDictionary)
            }
        }
        let store = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let poller = CursorPollerStub(polls)
        let api = CursorFakeTransport(me: me, usage: usage, meStatus: meStatus, usageStatus: usageStatus)
        let usageTransport = CursorFakeTransport(me: me, usage: usage, meStatus: meStatus, usageStatus: usageStatus, gate: gate)
        let scores = FlowScoreQueue(network)
        let quota = CoordinatedQuotaUpdater(store: store, service: FailingCodexService(),
            cursorService: CursorQuotaService(store: store, loadCredential: { try await vault.load(for: .credential($0)) },
                                              transport: usageTransport, checkNetwork: { .allowed(score: 80) },
                                              now: { [time] in time }))
        let opened = OpenedURLs()
        let flow = CodexConnectionFlow(checkNetwork: { await scores.next() },
            transactions: CodexLoginTransactionStore(vault: vault),
            bindings: CodexAccountBindingStore(accountStore: store, vault: vault),
            quotaUpdater: quota, cursorPoller: poller, cursorAPI: CursorAPIClient(transport: api),
            foregroundRefreshEnabled: false, now: { [time] in time },
            openURL: { url in opened.urls.append(url); return true })
        flow.cursorPollDelay = { _ in 0 }
        return Harness(flow: flow, store: store, vault: vault, poller: poller, api: api, usage: usageTransport, opened: opened,
                       fileURL: directory.appendingPathComponent("accounts.json"))
    }

    static func token(_ sub: String = "google-oauth2|user_1") -> String {
        func b64(_ s: String) -> String { CursorLoginRequest.base64url(Data(s.utf8)) }
        return b64(#"{"alg":"none"}"#) + "." + b64("{\"sub\":\"\(sub)\"}") + ".sig"
    }
    private static func cursorCredential(_ sub: String = "google-oauth2|user_1") -> CursorCredential {
        CursorCredential(accessToken: Self.token(sub), refreshToken: "refresh-\(UUID().uuidString)")
    }
    static func me(email: String = "cursor@example.invalid", sub: String = "google-oauth2|user_1") -> Data {
        try! JSONSerialization.data(withJSONObject: ["email": email, "sub": sub])
    }
    static func usage(used: Double) -> Data {
        try! JSONSerialization.data(withJSONObject: ["membershipType": "pro", "billingCycleEnd": "2026-11-12T08:00:00.000Z",
            "individualUsage": ["plan": ["enabled": true, "totalPercentUsed": used]]])
    }

    private func add(_ h: Harness) async throws {
        h.flow.showPlatformPicker()
        XCTAssertEqual(h.flow.state, .choosingPlatform)
        let work = try XCTUnwrap(h.flow.selectPlatform(.cursor))
        await work.value
        await h.flow.waitForInitialQuota()
    }

    func testT93AddCursorAccountShowsMonthlyQuota() async throws {
        let h = try await harness()
        try await add(h)
        XCTAssertEqual(h.flow.state, .idle); XCTAssertFalse(h.flow.isPresented)
        let saved = try await h.store.load()
        XCTAssertEqual(saved.count, 1)
        let account = try XCTUnwrap(saved.first)
        XCTAssertEqual(account.platform, .cursor); XCTAssertEqual(account.verifiedEmail, "cursor@example.invalid")
        XCTAssertEqual(account.remoteUserID, "google-oauth2|user_1"); XCTAssertNil(account.loginTransactionID)
        XCTAssertEqual(account.quotaState, .available)
        XCTAssertEqual(account.quotaSnapshot?.weekly.amount.remainingPercent, 75)
        XCTAssertEqual(h.flow.accounts, saved)
        // Official page, opened once; the token is in Keychain only.
        let url = try XCTUnwrap(h.opened.urls.first)
        XCTAssertEqual(h.opened.urls.count, 1)
        XCTAssertEqual(url.host, "cursor.com"); XCTAssertEqual(url.path, "/loginDeepControl")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "redirectTarget" }?.value, "cli")
        XCTAssertNotNil(items.first { $0.name == "challenge" }?.value)
        XCTAssertNil(items.first { $0.name == "verifier" }, "verifier不能进浏览器")
        let pollCount = await h.poller.count
        XCTAssertEqual(pollCount, 3)
        let stored = try await h.vault.load(for: .credential(account.credentialRef))
        XCTAssertNotNil(try stored.map(CursorCredential.init(payload:)))
        let file = try String(contentsOf: h.fileURL, encoding: .utf8)
        XCTAssertFalse(file.contains("eyJ") || file.contains("refresh-") || file.contains("WorkosCursor"), "凭据不进账户文件")
        let input = QuotaStyledInput(account: WidgetSnapshot.projecting(saved).account)
        XCTAssertEqual(input.platform, .cursor); XCTAssertEqual(input.windows.map(\.title), ["本月"])
        print("T93 | 添加Cursor | 网络检查→官方页→第3次领取→身份→保存→首次查询，本月剩余75% | passed")
    }

    func testT93SameEmailUpdatesInPlaceNextToCodex() async throws {
        let h = try await harness()
        // An existing Codex account first, then Cursor, then another Codex.
        let codexA = ConnectedAccount(remoteUserID: "u-a", verifiedEmail: "cursor@example.invalid",
            scope: .init(remoteAccountID: "acct-a", kind: .personal), credentialRef: UUID())
        try await h.store.append(codexA)
        await h.flow.loadAccounts()
        await h.flow.waitForInitialQuota() // the Codex fixture's own first query (fails, irrelevant here)
        try await add(h)
        let codexB = ConnectedAccount(remoteUserID: "u-b", verifiedEmail: "b@example.invalid",
            scope: .init(remoteAccountID: "acct-b", kind: .personal), credentialRef: UUID())
        try await h.store.append(codexB)
        let first = try await h.store.load()
        let cursor = try XCTUnwrap(first.first { $0.platform == .cursor })
        // Same Cursor e-mail logs in again with fresh tokens.
        await h.poller.reset([.confirmed(Self.cursorCredential())])
        try await add(h)
        let second = try await h.store.load()
        XCTAssertEqual(second.map(\.id), first.map(\.id), "原位更新，位置不变，未新增")
        let updated = try XCTUnwrap(second.first { $0.id == cursor.id })
        XCTAssertEqual(updated.generation, cursor.generation + 1)
        XCTAssertNotEqual(updated.credentialRef, cursor.credentialRef)
        XCTAssertEqual(second.filter { $0.platform == .codex }.map(\.verifiedEmail), ["cursor@example.invalid", "b@example.invalid"],
                       "同邮箱的Codex账户不受影响")
        let oldCredential = try await h.vault.load(for: .credential(cursor.credentialRef))
        XCTAssertNil(oldCredential, "旧凭据已清理")
        // A different Cursor e-mail is appended at the end.
        await h.poller.reset([.confirmed(Self.cursorCredential("google-oauth2|user_2"))])
        await h.api.setMe(Self.me(email: "second@example.invalid", sub: "google-oauth2|user_2"))
        await h.usage.setMe(Self.me(email: "second@example.invalid", sub: "google-oauth2|user_2"))
        try await add(h)
        let third = try await h.store.load()
        XCTAssertEqual(third.count, 4); XCTAssertEqual(third.last?.verifiedEmail, "second@example.invalid")
        print("T93 | 同邮箱 | 原位更新（位置、ID不变，generation+1，旧凭据清理）；与Codex并存；不同邮箱追加到末尾 | passed")
    }

    func testT93CancelTimeoutAndFailuresLeaveNoPartialAccount() async throws {
        var rows: [String] = []
        // Cancel while waiting for browser confirmation.
        do {
            let h = try await harness(polls: Array(repeating: .waiting, count: 1000))
            h.flow.cursorPollDelay = { _ in 0.02 }
            h.flow.showPlatformPicker()
            let work = try XCTUnwrap(h.flow.selectPlatform(.cursor))
            while h.flow.state != .browser { await Task.yield() }
            try await Task.sleep(for: .milliseconds(100))
            h.flow.cancel()
            await work.value
            let polls = await h.poller.count
            try await Task.sleep(for: .milliseconds(100))
            let after = await h.poller.count
            XCTAssertEqual(polls, after, "取消后不再轮询")
            XCTAssertEqual(h.flow.state, .idle); XCTAssertFalse(h.flow.isPresented)
            let saved = try await h.store.load(); XCTAssertTrue(saved.isEmpty)
            rows.append("等待确认时取消")
        }
        // Timeout: never confirmed within the official 150 polls.
        do {
            let h = try await harness(polls: Array(repeating: .waiting, count: 200))
            try await addExpectingFailure(h, "登录未完成，请重试")
            let polls = await h.poller.count; XCTAssertEqual(polls, CursorLoginClient.maxPolls)
            rows.append("150次未确认超时")
        }
        // Three consecutive poll errors.
        do {
            let h = try await harness(polls: [.waiting, .failed, .failed, .failed, .confirmed(Self.cursorCredential())])
            try await addExpectingFailure(h, "登录未完成，请重试")
            rows.append("连续3次领取错误")
        }
        // Network below the bar: no browser, no poll.
        do {
            let h = try await harness(network: [.blocked(score: 30)])
            try await addExpectingFailure(h, "网络不达标，无法连接")
            XCTAssertTrue(h.opened.urls.isEmpty); let polls = await h.poller.count; XCTAssertEqual(polls, 0)
            rows.append("网络不达标（不开浏览器）")
        }
        // Identity cannot be confirmed: nothing saved, no credential left.
        do {
            let h = try await harness(meStatus: 401)
            try await addExpectingFailure(h, "登录未完成，请重试")
            rows.append("身份核对失败")
        }
        // Retry after a failure starts a fresh attempt and succeeds.
        do {
            let h = try await harness(network: [.blocked(score: 30), .allowed(score: 80)])
            try await addExpectingFailure(h, "网络不达标，无法连接")
            let work = try XCTUnwrap(h.flow.begin(), "失败后可重新开始")
            await work.value; await h.flow.waitForInitialQuota()
            let saved = try await h.store.load(); XCTAssertEqual(saved.count, 1)
            rows.append("失败后点重试成功")
        }
        print("T93 | 不产生半成品 | " + rows.joined(separator: "；") + " | passed")
    }

    private func addExpectingFailure(_ h: Harness, _ message: String) async throws {
        h.flow.showPlatformPicker()
        let work = try XCTUnwrap(h.flow.selectPlatform(.cursor))
        await work.value
        XCTAssertEqual(h.flow.state, .failure(message))
        XCTAssertTrue(h.flow.isPresented)
        let saved = try await h.store.load()
        XCTAssertTrue(saved.isEmpty, "\(message)：不产生账户")
        XCTAssertTrue(h.flow.accounts.isEmpty)
    }

    func testT93FirstQueryFailureKeepsAccountAndRetries() async throws {
        let h = try await harness(usageStatus: 500)
        try await add(h)
        XCTAssertEqual(h.flow.state, .quota)
        XCTAssertEqual(h.flow.quotaFailure, "获取失败")
        let saved = try await h.store.load()
        XCTAssertEqual(saved.count, 1, "登录已确认的账户保留")
        XCTAssertEqual(saved.first?.quotaState, .notFetched)
        await h.usage.setUsageStatus(200)
        h.flow.retryInitialQuota(for: try XCTUnwrap(saved.first?.id), location: .connection)
        await h.flow.waitForInitialQuota()
        XCTAssertEqual(h.flow.state, .idle)
        let after = try await h.store.load()
        XCTAssertEqual(after.first?.quotaState, .available)
        print("T93 | 首次查询失败 | 显示“获取失败”，账户保留；重试后显示本月 | passed")
    }

    func testT93DeletedAccountIsNotRevivedByLateResult() async throws {
        let gate = UsageGate()
        let h = try await harness(gate: gate)
        h.flow.showPlatformPicker()
        let work = try XCTUnwrap(h.flow.selectPlatform(.cursor))
        await work.value
        while await !gate.waiting { await Task.yield() }
        let account = try XCTUnwrap(h.flow.accounts.first)
        h.flow.cancel() // close the sheet while the first query is in flight
        let deletion = try XCTUnwrap(h.flow.deleteAccount(account.id))
        await deletion.value
        await gate.release()
        await h.flow.waitForInitialQuota()
        try await Task.sleep(for: .milliseconds(100))
        let saved = try await h.store.load()
        XCTAssertTrue(saved.isEmpty, "删除后迟到结果不复活")
        XCTAssertTrue(h.flow.accounts.isEmpty)
        let credential = try await h.vault.load(for: .credential(account.credentialRef))
        XCTAssertNil(credential, "删除清除凭据")
        print("T93 | 删除 | 查询途中删除，迟到结果不复活，凭据清除 | passed")
    }
}

actor CursorPollerStub: CursorLoginPolling {
    private var outcomes: [CursorPollOutcome]
    private(set) var count = 0
    init(_ outcomes: [CursorPollOutcome]) { self.outcomes = outcomes }
    func reset(_ outcomes: [CursorPollOutcome]) { self.outcomes = outcomes; count = 0 }
    func poll(_ request: CursorLoginRequest) async -> CursorPollOutcome {
        count += 1
        return outcomes.isEmpty ? .waiting : outcomes.removeFirst()
    }
}

actor FlowScoreQueue {
    private var values: [NetworkScoreResult]
    init(_ values: [NetworkScoreResult]) { self.values = values }
    func next() -> NetworkScoreResult { values.count > 1 ? values.removeFirst() : values[0] }
}

actor UsageGate {
    private(set) var waiting = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async { waiting = true; await withCheckedContinuation { continuation = $0 } }
    func release() { continuation?.resume(); continuation = nil }
}

struct FailingCodexService: CodexQuotaUpdating {
    func update(_ account: ConnectedAccount) async throws -> ConnectedAccount { throw CodexQuotaError.failed }
}
