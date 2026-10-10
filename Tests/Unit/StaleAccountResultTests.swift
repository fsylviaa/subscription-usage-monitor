import Foundation
import XCTest
@testable import SubscriptionUsage

/// Every gate ignores task cancellation deliberately. Results are released only
/// after the replacement/deletion has committed, never by a timing-based sleep.
@MainActor
final class StaleAccountResultTests: XCTestCase {
    nonisolated private static let time = Date(timeIntervalSince1970: 1_800_000_000)

    func testT22CancelledLoginCannotCreateBindingWhenSuccessArrivesLate() async throws {
        let f = try await fixture()
        let gate = T22Gate()
        let transaction = UUID()
        let login = try Self.login("B", version: "late")
        let work = Task {
            await gate.hold()
            return try await f.binding.save(login, transactionID: transaction)
        }
        await gate.waitUntilStarted()
        let transactions = CodexLoginTransactionStore(vault: f.vault)
        try await transactions.cancel(transactionID: transaction)
        await gate.release()
        await rejected(work)
        try await unchanged(f, expected: [f.a, f.c])
        let pending = try await transactions.load()
        XCTAssertNil(pending)
        print("T22 | 取消添加后释放旧登录 | A/C完整保持，无B；重建读取一致")
    }

    func testT22OldQuotaCannotOverwriteNewLoginQuotaOrSuccessTime() async throws {
        let f = try await fixture()
        let gate = T22Gate()
        let work = Task { try await self.service(f, gate: gate, used: 99, time: 300).update(f.a) }
        await gate.waitUntilStarted()
        let login = try Self.login("A", version: "latest")
        let new = try await f.binding.save(login)
        let latest = try await service(f, used: 20, time: 200).update(new)
        await gate.release()
        await rejected(work)
        try await unchanged(f, expected: [latest, f.c])
        let payload = try await f.vault.load(for: .credential(latest.credentialRef))
        XCTAssertTrue(payload == login.credentials)
        XCTAssertEqual(latest.quotaSnapshot?.weekly.amount.remainingPercent, 80)
        XCTAssertEqual(latest.quotaSnapshot?.observedAt, Self.time.addingTimeInterval(200))
        print("T22 | 旧查询99%已用晚到 | 保留新连接剩余80%及t+200成功时间，C不变；重建一致")
    }

    func testT22DeletedAccountCannotReturnAfterLateQuota() async throws {
        let f = try await fixture()
        let gate = T22Gate()
        let work = Task { try await self.service(f, gate: gate).update(f.a) }
        await gate.waitUntilStarted()
        try await f.binding.removeAccount(f.a.id)
        await gate.release()
        await rejected(work)
        try await unchanged(f, expected: [f.c])
        let old = try await f.vault.load(for: .credential(f.a.credentialRef))
        XCTAssertNil(old)
        print("T22 | 删除A后释放旧查询 | 只有C，A授权及快照不复活；重建一致")
    }

    func testT22LateRenewalCannotWriteEvenWhenDeletionCleanupIsPending() async throws {
        for holdVerification in [false, true] {
            let f = try await fixture()
            let gate = T22Gate()
            let renewal = manager(f, gate: gate, holdVerification: holdVerification)
            let work = Task { try await renewal.credential(for: f.a, rejected: f.aPayload) }
            await gate.waitUntilStarted()
            // Exact durable state left by interrupted T21 Keychain cleanup.
            _ = try await f.store.markForDeletion(f.a.id)
            let before = try await f.vault.load(for: .credential(f.a.credentialRef))
            await gate.release()
            await rejected(work)
            let after = try await f.vault.load(for: .credential(f.a.credentialRef))
            XCTAssertTrue(before == after, "Neither response nor verified tokens may write behind a deletion marker")
            let reopened = CodexAccountBindingStore(accountStore: AccountStore(fileURL: f.url), vault: f.vault)
            let rows = try await reopened.load()
            XCTAssertEqual(rows, [f.c])
            let removed = try await f.vault.load(for: .credential(f.a.credentialRef))
            XCTAssertNil(removed)
            try await unchanged(f, expected: [f.c])
        }
        print("T22 | 删除清理中断，旧续期/核验晚到 | 两阶段均拒写，重开清理后仅C")
    }

    func testT22OldRenewalCannotOverwriteLatestLoginEvenWithRetiredCredentialPresent() async throws {
        for holdVerification in [false, true] {
            let f = try await fixture()
            let gate = T22Gate()
            let renewal = manager(f, gate: gate, holdVerification: holdVerification)
            let work = Task { try await renewal.credential(for: f.a, rejected: f.aPayload) }
            await gate.waitUntilStarted()
            let login = try Self.login("A", version: "latest")
            let incoming = ConnectedAccount(remoteUserID: login.remoteUserID, verifiedEmail: login.email,
                scope: login.scope, credentialRef: UUID(), loginTransactionID: UUID())
            try await f.vault.save(login.credentials, for: .credential(incoming.credentialRef))
            // Same durable state as T18 commit followed by failed old-credential cleanup.
            let new = try await f.store.commitLogin(incoming)
            let oldBefore = try await f.vault.load(for: .credential(f.a.credentialRef))
            await gate.release()
            await rejected(work)
            let oldAfter = try await f.vault.load(for: .credential(f.a.credentialRef))
            let current = try await f.vault.load(for: .credential(new.credentialRef))
            XCTAssertTrue(oldBefore == oldAfter)
            XCTAssertTrue(current == login.credentials)
            let capture = T22Transport(body: Self.body("A", used: 20))
            let latest = try await service(f, time: 200, transport: capture).update(new)
            let authorization = await capture.authorization
            XCTAssertTrue(authorization == "Bearer latest-access")
            let reopened = CodexAccountBindingStore(accountStore: AccountStore(fileURL: f.url), vault: f.vault)
            let rows = try await reopened.load()
            XCTAssertEqual(rows.map(\.id), [latest.id, f.c.id])
            XCTAssertEqual(rows.first?.quotaSnapshot, latest.quotaSnapshot)
            XCTAssertEqual(rows.last, f.c)
            let retired = try await f.vault.load(for: .credential(f.a.credentialRef))
            XCTAssertNil(retired)
            try await unchanged(f, expected: rows)
        }
        print("T22 | 新登录后释放旧续期/核验 | 两阶段均拒写，后续用新授权，C与重开结果保持")
    }

    func testT22CancelledQuotaPreservesOldSnapshotAndTimeAfterLateSuccess() async throws {
        let f = try await fixture()
        let gate = T22Gate()
        let work = Task { try await self.service(f, gate: gate).update(f.a) }
        await gate.waitUntilStarted()
        work.cancel()
        await gate.release()
        await rejected(work)
        try await unchanged(f, expected: [f.a, f.c])
    }

    func testT22DeletionFromPageDoesNotWaitForNonCooperativeQuery() async throws {
        let f = try await fixture()
        let gate = T22Gate()
        let flow = CodexConnectionFlow(bindings: f.binding, quotaUpdater: service(f, gate: gate))
        await flow.loadAccounts()
        flow.refreshQuota(for: f.a.id)
        await gate.waitUntilStarted()
        // Finish deletion before releasing the old query. A regression would hang
        // here, so observe completion with a bounded XCTest expectation.
        let deleted = expectation(description: "Deletion does not join a held request")
        let deletion = try XCTUnwrap(flow.deleteAccount(f.a.id))
        let observer = Task { await deletion.value; deleted.fulfill() }
        await fulfillment(of: [deleted], timeout: 2)
        let beforeRelease = flow.accounts
        await gate.release()
        await observer.value
        await flow.waitForInitialQuota()
        XCTAssertEqual(beforeRelease, [f.c])
        XCTAssertEqual(flow.accounts, [f.c])
        XCTAssertNil(flow.quotaFailureID)
        try await unchanged(f, expected: [f.c])
    }

    private struct Fixture {
        let url: URL
        let service: String
        let store: AccountStore
        let vault: CredentialVault
        let binding: CodexAccountBindingStore
        let a: ConnectedAccount
        let c: ConnectedAccount
        let aPayload: CredentialPayload
        let cPayload: CredentialPayload
    }

    private func fixture() async throws -> Fixture {
        let name = "T22.tests.\(UUID())"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let url = directory.appendingPathComponent("accounts.json")
        let store = AccountStore(fileURL: url)
        let vault = CredentialVault(service: name)
        let binding = CodexAccountBindingStore(accountStore: store, vault: vault)
        let la = try Self.login("A", version: "old")
        let lc = try Self.login("C", version: "untouched")
        var a = try await binding.save(la)
        var c = try await binding.save(lc)
        for account in [a, c] {
            let snapshot = try CodexUsageParser().parse(Self.body(account == a ? "A" : "C", used: 60),
                for: account, observedAt: Self.time)
            let updated = try await store.saveObservation(.init(planType: "plus", observedAt: Self.time),
                quota: .available(snapshot), for: account)
            if account.id == a.id { a = updated } else { c = updated }
        }
        let originals = [a.credentialRef, c.credentialRef]
        addTeardownBlock {
            let rows = (try? await store.load()) ?? []
            for ref in Set(originals + rows.flatMap { [$0.credentialRef] + ($0.retiredCredentialRefs ?? []) }) {
                try await vault.remove(for: .credential(ref))
            }
            let transactions = CodexLoginTransactionStore(vault: vault)
            if let id = try await transactions.loadCancelledTransactionID() { try await transactions.remove(transactionID: id) }
            try FileManager.default.removeItem(at: directory)
        }
        return Fixture(url: url, service: name, store: store, vault: vault, binding: binding,
                       a: a, c: c, aPayload: la.credentials, cPayload: lc.credentials)
    }

    nonisolated private static func login(_ name: String, version: String) throws -> CodexVerifiedLogin {
        let scope = AccountScope(remoteAccountID: "account-\(name)", kind: .personal)
        let package = CodexIdentityVerifier.CredentialPackage(credentialVersion: 1,
            issuer: CodexIdentityVerifier.issuer, clientID: CodexDeviceAuthorization.clientID,
            subject: "subject-\(name)", remoteUserID: "user-\(name)", scope: scope,
            tokens: tokens(version))
        return .fixture(remoteUserID: "user-\(name)", email: "\(name)@example.invalid", scope: scope,
                        credentials: .init(data: try JSONEncoder().encode(package)))
    }
    nonisolated private static func tokens(_ version: String) -> CodexTokenResponse {
        .init(accessToken: "\(version)-access", refreshToken: "\(version)-refresh", idToken: "\(version)-id",
              obtainedAt: time, expiresAt: time.addingTimeInterval(3600))
    }
    nonisolated private static func body(_ name: String, used: Int) -> Data {
        Data("""
        {"account_id":"account-\(name)","plan_type":"plus","rate_limit":{"primary_window":{"limit_window_seconds":18000,"used_percent":\(used)},"secondary_window":{"limit_window_seconds":604800,"used_percent":\(used)}}}
        """.utf8)
    }
    private func service(_ f: Fixture, gate: T22Gate? = nil, used: Int = 99, time: Double = 300,
                         transport: T22Transport? = nil) -> CodexQuotaService {
        CodexQuotaService(store: f.store, loadCredential: { try await f.vault.load(for: .credential($0)) },
            transport: transport ?? T22Transport(body: Self.body("A", used: used), gate: gate),
            checkNetwork: { .allowed(score: 51) }, now: { Self.time.addingTimeInterval(time) })
    }
    private func manager(_ f: Fixture, gate: T22Gate, holdVerification: Bool) -> CodexCredentialRenewal {
        CodexCredentialRenewal(vault: f.vault, store: f.store,
            client: T22Renewal(gate: holdVerification ? nil : gate, tokens: Self.tokens("renewed")),
            now: { Self.time }, verify: { tokens, _ in
                if holdVerification { await gate.hold() }
                return tokens
            })
    }
    private func unchanged(_ f: Fixture, expected: [ConnectedAccount]) async throws {
        let current = try await f.store.load()
        let reopened = try await AccountStore(fileURL: f.url).load()
        let other = try await CredentialVault(service: f.service).load(for: .credential(f.c.credentialRef))
        XCTAssertEqual(current, expected)
        XCTAssertEqual(reopened, expected)
        XCTAssertEqual(reopened.first(where: { $0.id == f.c.id }), f.c)
        XCTAssertTrue(other == f.cPayload)
    }
    private func rejected<T>(_ task: Task<T, Error>) async {
        do { _ = try await task.value; XCTFail("Stale operation must be rejected") } catch {}
    }
}

private actor T22Gate {
    private var started = false
    private var start: CheckedContinuation<Void, Never>?
    private var finish: CheckedContinuation<Void, Never>?
    func hold() async {
        started = true
        start?.resume(); start = nil
        await withCheckedContinuation { finish = $0 }
    }
    func waitUntilStarted() async { if !started { await withCheckedContinuation { start = $0 } } }
    func release() { finish?.resume(); finish = nil }
}
private actor T22Transport: CodexDeviceAuthorizationTransport {
    let body: Data
    let gate: T22Gate?
    private(set) var authorization: String?
    init(body: Data, gate: T22Gate? = nil) { self.body = body; self.gate = gate }
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        authorization = request.value(forHTTPHeaderField: "Authorization")
        await gate?.hold()
        return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
private struct T22Renewal: CodexTokenRenewing {
    let gate: T22Gate?
    let tokens: CodexTokenResponse
    func renew(_ old: CodexTokenResponse) async throws -> CodexTokenResponse {
        await gate?.hold()
        return tokens
    }
}
