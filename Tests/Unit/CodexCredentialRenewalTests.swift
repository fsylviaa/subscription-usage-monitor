import Foundation
import Security
import XCTest
@testable import SubscriptionUsage

@MainActor
final class CodexCredentialRenewalTests: XCTestCase {
    nonisolated private static let instant = Date(timeIntervalSince1970: 1_800_000_000)
    nonisolated private static let usage = Data(#"{"account_id":"renewal-account","plan_type":"plus","rate_limit":{"primary_window":{"limit_window_seconds":18000,"used_percent":80},"secondary_window":{"limit_window_seconds":604800,"used_percent":30}}}"#.utf8)

    func testCurrentAuthorizationQueriesWithoutRenewalOrBrowser() async throws {
        let f = try await fixture(expiresIn: 3600)
        let client = RenewalClientStub()
        let service = updater(f, renewal: manager(f, client: client))
        let result = try await service.update(f.account)
        let payload = try await f.vault.load(for: .credential(f.account.credentialRef))
        XCTAssertTrue(payload == f.original)
        XCTAssertEqual(result.quotaSnapshot?.weekly.amount.remainingPercent, 70)
        let count = await client.count
        XCTAssertEqual(count, 0)
        print("T14 | 有效授权 | 原授权查询成功；续期0次，无网页登录")
    }

    func testNearExpiryRenewsOnceSavesWholePackageThenQueriesAndReopens() async throws {
        let f = try await fixture()
        let client = RenewalClientStub()
        let transport = RenewalUsageTransport()
        let gate = RenewalNetworkGate([.allowed(score: 51)])
        let result = try await updater(f, renewal: manager(f, client: client), transport: transport, gate: gate).update(f.account)
        let reader = CredentialVault(service: f.service)
        let restored = try await reader.load(for: .credential(f.account.credentialRef))
        let payload = try XCTUnwrap(restored)
        let package = try CodexCredentialRenewal.package(payload, for: f.account)
        XCTAssertTrue(package.tokens.accessToken == "new-access" && package.tokens.refreshToken == "new-refresh")
        XCTAssertEqual(package.tokens.expiresAt, Self.instant.addingTimeInterval(3600))
        XCTAssertNil(package.renewal)
        XCTAssertEqual(package.renewalHistory?.count, 1)
        XCTAssertEqual(package.renewalHistory?.first?.trigger, .expiry)
        XCTAssertEqual(result.quotaSnapshot?.weekly.amount.remainingPercent, 70)
        XCTAssertEqual(result.quotaSnapshot?.fiveHours.amount.remainingPercent, 20)
        XCTAssertEqual(result.quotaSnapshot?.observedAt, Self.instant)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
        let count = await client.count
        XCTAssertEqual(count, 1)
        let checks = await gate.count
        XCTAssertEqual(checks, 2, "续期前检查及续期后的实际查询前检查")
        let file = try String(contentsOf: f.url, encoding: .utf8)
        XCTAssertFalse(file.contains("access") || file.contains("refresh") || file.contains("renewalHistory"))
        print("T14 | 临近到期 | 续期1次、查询1次；新授权整包读回匹配；周70%、5小时20%")
    }

    func testFirst401RenewsAndRetriesExactlyOnceWithFreshNetworkCheck() async throws {
        let f = try await fixture(expiresIn: 3600)
        let client = RenewalClientStub()
        let transport = RenewalUsageTransport(statuses: [401, 200])
        let gate = RenewalNetworkGate([.allowed(score: 51)])
        _ = try await updater(f, renewal: manager(f, client: client), transport: transport, gate: gate).update(f.account)
        let count = await client.count
        let requests = await transport.requests
        let checks = await gate.count
        XCTAssertEqual(count, 1); XCTAssertEqual(requests.count, 2); XCTAssertEqual(checks, 2)
        XCTAssertTrue(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer old-access")
        XCTAssertTrue(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
        print("T14 | 首次需要重新认证 | 自动续期1次、查询重试1次，成功；两次实际查询均重新评分")
    }

    func testSecond401AndPreemptiveRenewal401NeverLoopAndKeepOldQuota() async throws {
        for expires in [30.0, 3600.0] {
            let f = try await fixture(expiresIn: expires)
            let client = RenewalClientStub()
            let transport = RenewalUsageTransport(statuses: [401, 401])
            await expectFailure { _ = try await self.updater(f, renewal: self.manager(f, client: client), transport: transport).update(f.account) }
            try await assertOldData(f)
            let count = await client.count
            let requests = await transport.requests
            XCTAssertEqual(count, 1); XCTAssertEqual(requests.count, expires == 30 ? 1 : 2)
        }
        print("T14 | 再次认证失败 | 不循环续期；旧额度和原成功时间不变")
    }

    func test403429And500DoNotConsumeRefreshToken() async throws {
        for status in [403, 429, 500] {
            let f = try await fixture(expiresIn: 3600)
            let client = RenewalClientStub()
            await expectFailure { _ = try await self.updater(f, renewal: self.manager(f, client: client),
                transport: RenewalUsageTransport(statuses: [status])).update(f.account) }
            let count = await client.count
            XCTAssertEqual(count, 0)
            let payload = try await f.vault.load(for: .credential(f.account.credentialRef))
            XCTAssertTrue(payload == f.original)
            try await assertOldData(f)
        }
    }

    func testBlockedOrUnknownNetworkDoesNotRenewOrQuery() async throws {
        for result: NetworkScoreResult in [.blocked(score: 49), .blocked(score: 50), .unavailable(.transport)] {
            let f = try await fixture()
            let client = RenewalClientStub()
            let transport = RenewalUsageTransport()
            let gate = RenewalNetworkGate([result])
            do { _ = try await updater(f, renewal: manager(f, client: client), transport: transport, gate: gate).update(f.account); XCTFail("应被阻止") }
            catch {
                let message = (error as? CodexQuotaError)?.message
                if case .blocked = result { XCTAssertEqual(message, "网络不达标，无法更新") }
                else { XCTAssertEqual(message, "刷新失败") }
            }
            let count = await client.count
            let requests = await transport.requests
            XCTAssertEqual(count, 0); XCTAssertEqual(requests.count, 0)
            try await assertOldData(f)
        }
    }

    func testRetryNetworkFallingTo50PreventsSecondUsageRequest() async throws {
        let f = try await fixture(expiresIn: 3600)
        let client = RenewalClientStub()
        let transport = RenewalUsageTransport(statuses: [401, 200])
        do { _ = try await updater(f, renewal: manager(f, client: client), transport: transport,
            gate: RenewalNetworkGate([.allowed(score: 51), .blocked(score: 50)])).update(f.account); XCTFail("应阻止重查") }
        catch { XCTAssertEqual(error as? CodexQuotaError, .networkBlocked) }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        try await assertOldData(f)
    }

    func testUnansweredRenewalCannotReplayOldTokenEvenAfterNewInstance() async throws {
        let f = try await fixture()
        let client = RenewalClientStub(fails: true)
        for _ in 0..<2 {
            await expectFailure { _ = try await self.updater(f, renewal: self.manager(f, client: client)).update(f.account) }
        }
        let count = await client.count
        XCTAssertEqual(count, 1)
        let payload = try await readPayload(f)
        let package = try CodexCredentialRenewal.package(payload, for: f.account)
        XCTAssertTrue(package.tokens.accessToken == "old-access" && package.tokens.refreshToken == "old-refresh")
        XCTAssertNotNil(package.renewal)
        XCTAssertNil(package.renewal?.received)
        try await assertOldData(f)
        print("T14 | 续期网络结果不明 | 刷新失败；旧额度/时间/授权保留；重建实例仍不重放旧令牌")
    }

    func testExplicitRejectionKeepsAccountAndCannotRepeatGrant() async throws {
        let f = try await fixture()
        let transport = RenewalUsageTransport(statuses: [400], body: Data(#"{"error":"invalid_grant"}"#.utf8))
        let client = CodexTokenRenewalClient(transport: transport)
        for _ in 0..<2 {
            await expectFailure { _ = try await self.updater(f, renewal: self.manager(f, client: client)).update(f.account) }
        }
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        try await assertOldData(f)
        print("T14 | 平台明确不可续期 | 刷新失败；账户/旧额度/原时间保留，不自动打开官网")
    }

    func testMarkerSaveFailureDoesNotSendRenewal() async throws {
        let f = try await fixture()
        f.keychain.failUpdate(after: 1)
        let client = RenewalClientStub()
        await expectFailure { _ = try await self.updater(f, renewal: self.manager(f, client: client)).update(f.account) }
        let count = await client.count
        let saved = try await f.vault.load(for: .credential(f.account.credentialRef))
        XCTAssertEqual(count, 0); XCTAssertTrue(saved == f.original)
        try await assertOldData(f)
    }

    func testReceivedSaveFailureDoesNotPublishAndCanSaveSameResponseWithoutReplay() async throws {
        let f = try await fixture()
        f.keychain.failUpdate(after: 2)
        let client = RenewalClientStub()
        let renewal = manager(f, client: client)
        let transport = RenewalUsageTransport()
        let service = updater(f, renewal: renewal, transport: transport)
        await expectFailure { _ = try await service.update(f.account) }
        try await assertOldData(f)
        let requestsBefore = await transport.requests
        XCTAssertTrue(requestsBefore.isEmpty)
        _ = try await service.update(f.account)
        let count = await client.count
        XCTAssertEqual(count, 1)
        print("T14 | 新授权保存失败 | 首次刷新失败且旧额度不变；存储恢复后保存同一响应，不重复续期")
    }

    func testFinalSaveFailureAndVerificationFailureResumePersistedCandidateAfterReopen() async throws {
        for failSave in [true, false] {
            let f = try await fixture()
            let client = RenewalClientStub()
            if failSave { f.keychain.failUpdate(after: 3) }
            let first = CodexCredentialRenewal(vault: f.vault, client: client, now: { Self.instant }, verify: { tokens, _ in
                if !failSave { throw URLError(.timedOut) }
                return tokens
            })
            await expectFailure { _ = try await self.updater(f, renewal: first).update(f.account) }
            try await assertOldData(f)
            let saved = try await readPayload(f)
            let package = try CodexCredentialRenewal.package(saved, for: f.account)
            XCTAssertNotNil(package.renewal?.received)
            XCTAssertTrue(package.tokens.accessToken == "old-access")
            _ = try await updater(f, renewal: manager(f, client: client)).update(f.account)
            let count = await client.count
            XCTAssertEqual(count, 1, "重建实例只能恢复核验/保存，不再次消费续期令牌")
        }
    }

    func testConcurrentExpiryAndLate401ShareOneRotation() async throws {
        let f = try await fixture()
        let client = RenewalClientStub(hold: true)
        let renewal = manager(f, client: client)
        let a = Task { try await renewal.credential(for: f.account) }
        await client.waitUntilStarted()
        let b = Task { try await renewal.credential(for: f.account, rejected: f.original) }
        await client.release()
        let first = try await a.value
        let second = try await b.value
        XCTAssertTrue(first == second)
        _ = try await renewal.credential(for: f.account, rejected: f.original)
        let count = await client.count
        XCTAssertEqual(count, 1)
        print("T14 | 同时续期及旧请求迟到 | 同一授权只续期1次，迟到401复用已保存新授权")
    }

    func testReplacementDuringRenewalCannotBeOverwritten() async throws {
        let f = try await fixture()
        let client = RenewalClientStub(hold: true)
        let renewal = manager(f, client: client)
        let task = Task { try await renewal.credential(for: f.account) }
        await client.waitUntilStarted()
        var replacement = try CodexCredentialRenewal.package(f.original, for: f.account)
        replacement.tokens = .init(accessToken: "replacement-access", refreshToken: "replacement-refresh",
            idToken: "replacement-id", obtainedAt: Self.instant, expiresAt: Self.instant.addingTimeInterval(7200))
        let payload = CredentialPayload(data: try JSONEncoder().encode(replacement))
        try await f.vault.save(payload, for: .credential(f.account.credentialRef))
        await client.release()
        await expectFailure { _ = try await task.value }
        let actual = try await f.vault.load(for: .credential(f.account.credentialRef))
        XCTAssertTrue(actual == payload)
        try await assertOldData(f)
    }

    func testCancelledQueryStillSafelySavesRotationButDoesNotPublishQuota() async throws {
        let f = try await fixture()
        let client = RenewalClientStub(hold: true)
        let transport = RenewalUsageTransport()
        let service = updater(f, renewal: manager(f, client: client), transport: transport)
        let task = Task { try await service.update(f.account) }
        await client.waitUntilStarted()
        task.cancel()
        await client.release()
        do { _ = try await task.value; XCTFail("已取消查询不成功") }
        catch { XCTAssertTrue(error is CancellationError) }
        let payload = try await readPayload(f)
        let package = try CodexCredentialRenewal.package(payload, for: f.account)
        XCTAssertTrue(package.tokens.accessToken == "new-access")
        XCTAssertNil(package.renewal)
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
        try await assertOldData(f)
    }

    func testChangedCredentialDuringUsageRejectsLateQuota() async throws {
        let f = try await fixture(expiresIn: 3600)
        let transport = RenewalUsageTransport(beforeResponse: {
            try? await f.vault.save(.init(data: Data("replaced".utf8)), for: .credential(f.account.credentialRef))
        })
        await expectFailure { _ = try await self.updater(f, renewal: self.manager(f, client: RenewalClientStub()), transport: transport).update(f.account) }
        try await assertOldData(f)
    }

    func testRefreshClientUsesOfficialGrantAndSupportsOmittedIdentityAndRefresh() async throws {
        let transport = RenewalUsageTransport(body: Data(#"{"access_token":"new-access","expires_in":3600,"token_type":"Bearer"}"#.utf8))
        let client = CodexTokenRenewalClient(transport: transport, now: { Self.instant })
        let old = oldTokens(expiresIn: 30)
        let new = try await client.renew(old)
        XCTAssertTrue(new.refreshToken == old.refreshToken && new.idToken == old.idToken)
        XCTAssertEqual(new.expiresAt, Self.instant.addingTimeInterval(3600))
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url, CodexLoginClient.tokenURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization")); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(Set(body.keys), Set(["grant_type", "client_id", "refresh_token"]))
        XCTAssertEqual(body["grant_type"], "refresh_token")
        XCTAssertEqual(body["client_id"], CodexDeviceAuthorization.clientID)
        XCTAssertTrue(body["refresh_token"] == old.refreshToken)
    }

    func testRefreshClientRejectsMissingInvalidUnchangedAndErrorResponsesWithoutRetry() async throws {
        let bodies = ["{}", #"{"access_token":"old-access"}"#, #"{"access_token":"new-access","refresh_token":""}"#,
            #"{"access_token":"new-access","expires_in":-1}"#, #"{"access_token":"new-access","token_type":"Basic"}"#,
            #"{"access_token":"bad\nheader"}"#, "not-json"]
        for body in bodies {
            let transport = RenewalUsageTransport(body: Data(body.utf8))
            await expectFailure { _ = try await CodexTokenRenewalClient(transport: transport).renew(self.oldTokens(expiresIn: 30)) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
        for status in [400, 401, 403, 429, 500] {
            let transport = RenewalUsageTransport(statuses: [status], body: Data(#"{"error":"refresh_token_reused"}"#.utf8))
            await expectFailure { _ = try await CodexTokenRenewalClient(transport: transport).renew(self.oldTokens(expiresIn: 30)) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
        }
    }

    private func oldTokens(expiresIn: Double) -> CodexTokenResponse {
        .init(accessToken: "old-access", refreshToken: "old-refresh", idToken: "old-id",
              obtainedAt: Self.instant.addingTimeInterval(-3600), expiresAt: Self.instant.addingTimeInterval(expiresIn))
    }
    private struct Fixture: Sendable {
        let account: ConnectedAccount; let store: AccountStore; let vault: CredentialVault
        let original: CredentialPayload; let url: URL; let service: String; let keychain: RenewalKeychain
    }
    private func fixture(expiresIn: Double = 30) async throws -> Fixture {
        let service = "T14.tests.\(UUID().uuidString)"
        let keychain = RenewalKeychain()
        let vault = CredentialVault(service: service, client: keychain)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(service)
        let url = directory.appendingPathComponent("accounts.json")
        let store = AccountStore(fileURL: url)
        var account = ConnectedAccount(remoteUserID: "renewal-user", verifiedEmail: "renewal@example.invalid",
            scope: .init(remoteAccountID: "renewal-account", kind: .personal), credentialRef: UUID())
        let oldTime = Self.instant.addingTimeInterval(-100)
        account.subscription = .init(planType: "plus", observedAt: oldTime)
        account.quotaState = .available
        account.quotaSnapshot = try CodexUsageParser().parse(Self.usage, for: account, observedAt: oldTime)
        try await store.append(account)
        let package = CodexIdentityVerifier.CredentialPackage(credentialVersion: 1, issuer: CodexIdentityVerifier.issuer,
            clientID: CodexDeviceAuthorization.clientID, subject: "renewal-subject", remoteUserID: "renewal-user",
            scope: account.scope, tokens: oldTokens(expiresIn: expiresIn))
        let payload = CredentialPayload(data: try JSONEncoder().encode(package))
        try await vault.save(payload, for: .credential(account.credentialRef))
        let ref = account.credentialRef
        addTeardownBlock {
            try await vault.remove(for: .credential(ref))
            try FileManager.default.removeItem(at: directory)
        }
        return .init(account: account, store: store, vault: vault, original: payload, url: url, service: service, keychain: keychain)
    }
    private func manager(_ f: Fixture, client: any CodexTokenRenewing) -> CodexCredentialRenewal {
        CodexCredentialRenewal(vault: f.vault, client: client, now: { Self.instant }, verify: { tokens, _ in tokens })
    }
    private func updater(_ f: Fixture, renewal: any CodexCredentialPreparing,
                         transport: RenewalUsageTransport = .init(), gate: RenewalNetworkGate = .init([.allowed(score: 51)])) -> CodexQuotaService {
        CodexQuotaService(store: f.store, loadCredential: { try await f.vault.load(for: .credential($0)) },
            renewal: renewal, transport: transport, checkNetwork: { await gate.check() }, now: { Self.instant })
    }
    private func readPayload(_ f: Fixture) async throws -> CredentialPayload {
        let value = try await f.vault.load(for: .credential(f.account.credentialRef))
        return try XCTUnwrap(value)
    }
    private func assertOldData(_ f: Fixture, file: StaticString = #filePath, line: UInt = #line) async throws {
        let stored = try await f.store.load()
        XCTAssertTrue(stored == [f.account], "账户、套餐、旧额度与原时间均保持", file: file, line: line)
    }
    private func expectFailure(file: StaticString = #filePath, line: UInt = #line, _ operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("应失败且保留旧数据", file: file, line: line) }
        catch { /* Never print errors that could embed tokens or response bodies. */ }
    }
}

private actor RenewalClientStub: CodexTokenRenewing {
    private(set) var count = 0
    let fails: Bool
    let hold: Bool
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(fails: Bool = false, hold: Bool = false) { self.fails = fails; self.hold = hold }
    func renew(_ tokens: CodexTokenResponse) async throws -> CodexTokenResponse {
        count += 1
        if hold {
            started = true; startWaiter?.resume(); startWaiter = nil
            await withCheckedContinuation { waiter = $0 }
        }
        if fails { throw URLError(.timedOut) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return .init(accessToken: "new-access", refreshToken: "new-refresh", idToken: "new-id",
                     obtainedAt: date, expiresAt: date.addingTimeInterval(3600))
    }
    func waitUntilStarted() async { if !started { await withCheckedContinuation { startWaiter = $0 } } }
    func release() { waiter?.resume(); waiter = nil }
}
private actor RenewalNetworkGate {
    let results: [NetworkScoreResult]
    private(set) var count = 0
    init(_ results: [NetworkScoreResult]) { self.results = results }
    func check() -> NetworkScoreResult { defer { count += 1 }; return results[min(count, results.count - 1)] }
}
private actor RenewalUsageTransport: CodexDeviceAuthorizationTransport {
    private(set) var requests: [URLRequest] = []
    let statuses: [Int]
    let body: Data
    let beforeResponse: @Sendable () async -> Void
    init(statuses: [Int] = [200], body: Data = Data(#"{"account_id":"renewal-account","plan_type":"plus","rate_limit":{"primary_window":{"limit_window_seconds":18000,"used_percent":80},"secondary_window":{"limit_window_seconds":604800,"used_percent":30}}}"#.utf8),
         beforeResponse: @escaping @Sendable () async -> Void = {}) {
        self.statuses = statuses; self.body = body; self.beforeResponse = beforeResponse
    }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        await beforeResponse()
        return (body, HTTPURLResponse(url: request.url!, statusCode: statuses[min(requests.count - 1, statuses.count - 1)],
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }
}
private final class RenewalKeychain: KeychainClient, @unchecked Sendable {
    private let system = SystemKeychainClient()
    private let lock = NSLock()
    private var updates = 0
    private var failAt: Int?
    func failUpdate(after offset: Int) { lock.withLock { failAt = updates + offset } }
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) { system.copyMatching(query) }
    func add(_ attributes: [String: Any]) -> OSStatus { system.add(attributes) }
    func delete(_ query: [String: Any]) -> OSStatus { system.delete(query) }
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        let fail = lock.withLock { updates += 1; return updates == failAt }
        return fail ? errSecNotAvailable : system.update(query, attributes: attributes)
    }
}

@MainActor
final class CodexCredentialRenewalLiveTests: XCTestCase {
    func testT14ExistingPhoneAuthorizationQueriesWithProductionRenewalPath() async throws {
        guard ProcessInfo.processInfo.environment["T14_LIVE_QUERY"] == "1" else {
            throw XCTSkip("T14真实查询需显式启用；默认不读取正式账户或联网。")
        }
        let store = try AccountStore.applicationStore()
        let accounts = try await store.load()
        guard accounts.count == 1, let account = accounts.first else {
            XCTFail("需要本App独立登录的现有账户。")
            return
        }
        let vault = CredentialVault.applicationVault()
        let before = try await vault.load(for: .credential(account.credentialRef))
        guard let before else { XCTFail("现有授权不可读"); return }
        let priorPackage = try CodexCredentialRenewal.package(before, for: account)
        let checker = NetworkScoreChecker()
        let updater = CodexQuotaService(store: store, loadCredential: { try await vault.load(for: .credential($0)) },
            renewal: CodexCredentialRenewal(vault: vault), checkNetwork: {
                let result = await checker.check()
                switch result {
                case let .allowed(score): print("T14 | 真实网络 | 允许，评分\(score)")
                case let .blocked(score): print("T14 | 真实网络 | 阻止，评分\(score)")
                case .unavailable: print("T14 | 真实网络 | 无有效评分")
                case .cancelled: print("T14 | 真实网络 | 取消")
                }
                return result
            })
        let began = Date()
        let updated = try await updater.update(account)
        XCTAssertTrue(updated.id == account.id && updated.remoteUserID == account.remoteUserID
            && updated.verifiedEmail == account.verifiedEmail && updated.scope == account.scope
            && updated.credentialRef == account.credentialRef)
        let subscription = try XCTUnwrap(updated.subscription)
        XCTAssertTrue(subscription.observedAt >= began && subscription.observedAt <= Date())
        XCTAssertTrue(updated.quotaState == .available || updated.quotaState == .notApplicable)
        if updated.quotaState == .notApplicable {
            XCTAssertNil(updated.quotaSnapshot)
            print("T14 | 真实查询 | 套餐\(subscription.planType)；无适用周/5小时额度，不造数值或额度成功时间")
        } else {
            XCTAssertNotNil(updated.quotaSnapshot)
            print("T14 | 真实查询 | 有适用额度，身份/作用域与保存结果一致")
        }
        let reloaded = try await AccountStore.applicationStore().load()
        XCTAssertTrue(reloaded == [updated])
        let after = try await vault.load(for: .credential(account.credentialRef))
        guard let after else { XCTFail("完成后授权必须能读取"); return }
        let package = try CodexCredentialRenewal.package(after, for: account)
        XCTAssertNil(package.renewal)
        let changed = before != after
        print("T14 | 真实授权 | \(changed ? "本次自动续期后查询成功" : "原授权仍有效，未强制续期")；无网页登录、无更换身份")
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        print("T14 | 观察起点 | \(formatter.string(from: began))；原有效期\(CodexIdentityVerifier.expirationForScheduling(priorPackage.tokens).map(formatter.string) ?? "响应未提供")")
        for observation in package.renewalHistory ?? [] {
            print("T14 | 本链去敏续期记录 | 开始\(formatter.string(from: observation.startedAt))；完成\(formatter.string(from: observation.completedAt))；触发\(observation.trigger.rawValue)；原到期\(observation.previousExpiry.map(formatter.string) ?? "未提供")")
        }
        print("T14 | 真实保存重读 | 身份/套餐/适用性/观测时间一致；两次自然到期仍由T54核验")
    }
}
