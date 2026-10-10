import UIKit
import XCTest
@testable import SubscriptionUsage

/// Explicit opt-in only. Uses the unmodified real network gate and official endpoint.
/// No screen or authorization body is attached, no account/token is created.
@MainActor
final class CodexConnectionLiveTests: XCTestCase {
    func testT10IsolatedSavedIdentityAndCleanup() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["T10_LIVE_SAVED_ACCOUNT"] == "1" else {
            throw XCTSkip("T10 独立真实登录需本人官网确认后显式核验。")
        }
        let context = try t10Context(environment)
        let original = try await officialSnapshot()
        let accounts = try await context.accounts.load()
        guard accounts.count == 1, let account = accounts.first,
              let payload = try await context.vault.load(for: .credential(account.credentialRef)) else {
            XCTFail("T10 独立真实登录尚未保存一条账户，不能用原有账户代替。")
            return
        }
        struct Package: Decodable { let tokens: CodexTokenResponse }
        let package = try JSONDecoder().decode(Package.self, from: payload.data)
        let verified = try await CodexIdentityVerifier().verify(package.tokens)
        guard verified.email == account.verifiedEmail,
              verified.remoteUserID == account.remoteUserID,
              verified.scope == account.scope,
              account.quotaState == .notFetched else {
            XCTFail("T10 真实身份重核验与独立保存记录不一致。")
            return
        }
        let active = try await context.transactions.load()
        let cancelled = try await context.transactions.loadCancelledTransactionID()
        XCTAssertTrue(active == nil && cancelled == nil, "完成后原事务已清理，不会恢复或重复创建")
        let reopened = try await AccountStore(fileURL: context.directory.appendingPathComponent("accounts.json")).load()
        XCTAssertTrue(reopened == accounts, "重开存储后仅有同一条真实账户；不打印身份")
        if environment["T10_LIVE_CLEANUP"] == "1" {
            try await cleanUpT10(context)
            let credential = try await context.vault.load(for: .credential(account.credentialRef))
            XCTAssertTrue(credential == nil, "本次独立验收授权已精确删除")
        }
        try await assertOfficialSnapshot(original)
        print("T10 | 真实保存与恢复收口 | 一条账户身份、签名、作用域及授权核验通过；事务已清除；原正式账户和授权未变；不输出身份和秘密")
    }

    func testT10CleanupIsolatedRun() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["T10_LIVE_CLEANUP_ONLY"] == "1" else {
            throw XCTSkip("仅显式清理指定 T10 独立验收编号；不删除正式账户。")
        }
        let context = try t10Context(environment)
        let original = try await officialSnapshot()
        try await cleanUpT10(context)
        let accounts = try await context.accounts.load()
        let active = try await context.transactions.load()
        let cancelled = try await context.transactions.loadCancelledTransactionID()
        XCTAssertTrue(accounts.isEmpty && active == nil && cancelled == nil,
                      "指定独立验收的账户和登录事务已清理")
        try await assertOfficialSnapshot(original)
        print("T10 | 精确清理 | 仅清理指定验收编号的账户、事务和授权；原正式账户、顺序、原状态及授权未变")
    }

    private struct T10Context {
        let directory: URL
        let accounts: AccountStore
        let vault: CredentialVault
        let transactions: CodexLoginTransactionStore
        let pending: CodexPendingLoginStore
    }

    private func t10Context(_ environment: [String: String]) throws -> T10Context {
        guard let rawID = environment["T10_LIVE_RUN_ID"], let runID = UUID(uuidString: rawID),
              rawID.uppercased() == runID.uuidString else {
            throw NSError(domain: "T10LiveAcceptance", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "T10 真实验收需要有效独立编号；未访问账户。"])
        }
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("T10-live-\(runID.uuidString)", isDirectory: true)
        let vault = CredentialVault(service: "T10.live.\(runID.uuidString)")
        return T10Context(directory: directory,
            accounts: AccountStore(fileURL: directory.appendingPathComponent("accounts.json")),
            vault: vault, transactions: CodexLoginTransactionStore(vault: vault),
            pending: CodexPendingLoginStore(vault: vault))
    }

    private func cleanUpT10(_ context: T10Context) async throws {
        if let authorization = try await context.transactions.load() {
            try await context.transactions.cancel(transactionID: authorization.transactionID)
            try await context.pending.remove(transactionID: authorization.transactionID)
            try await context.transactions.remove(transactionID: authorization.transactionID)
        }
        if let cancelledID = try await context.transactions.loadCancelledTransactionID() {
            try await context.pending.remove(transactionID: cancelledID)
            try await context.transactions.remove(transactionID: cancelledID)
        }
        for account in try await context.accounts.load() {
            if let credential = try await context.vault.load(for: .credential(account.credentialRef)) {
                try await context.vault.remove(ifMatching: credential, for: .credential(account.credentialRef))
            }
        }
        if FileManager.default.fileExists(atPath: context.directory.path) {
            try FileManager.default.removeItem(at: context.directory)
        }
    }

    private struct OfficialSnapshot {
        let accounts: [ConnectedAccount]
        let credentials: [UUID: CredentialPayload]
    }

    private func officialSnapshot() async throws -> OfficialSnapshot {
        let accounts = try await AccountStore.applicationStore().load()
        let vault = CredentialVault.applicationVault()
        var credentials: [UUID: CredentialPayload] = [:]
        for account in accounts {
            credentials[account.credentialRef] = try await vault.load(for: .credential(account.credentialRef))
        }
        return OfficialSnapshot(accounts: accounts, credentials: credentials)
    }

    private func assertOfficialSnapshot(_ original: OfficialSnapshot) async throws {
        let after = try await officialSnapshot()
        XCTAssertTrue(after.accounts == original.accounts, "正式账户、顺序和原状态未变；不打印身份")
        XCTAssertTrue(after.credentials == original.credentials, "正式账户授权完整保留")
    }

    func testT09RealCancellationPreservesSavedAccountAndAllowsFreshCode() async throws {
        guard ProcessInfo.processInfo.environment["T09_LIVE_CANCEL"] == "1" else {
            throw XCTSkip("T09 真实取消复测需显式开启，默认不联网。")
        }
        let official = try AccountStore.applicationStore()
        let officialVault = CredentialVault.applicationVault()
        let before = try await official.load()
        var credentials: [UUID: CredentialPayload] = [:]
        for account in before {
            credentials[account.credentialRef] = try await officialVault.load(for: .credential(account.credentialRef))
        }
        let runID = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("T09-cancel-\(runID)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let accounts = AccountStore(fileURL: directory.appendingPathComponent("accounts.json"))
        let vault = CredentialVault(service: "com.iceflying.SubscriptionUsage.tests.T09.cancel.\(runID)")
        let transactions = CodexLoginTransactionStore(vault: vault)
        let pending = CodexPendingLoginStore(vault: vault)
        let flow = CodexConnectionFlow(transactions: transactions, completer: CodexLoginClient(),
            verifier: CodexIdentityVerifier(), bindings: CodexAccountBindingStore(accountStore: accounts, vault: vault),
            pending: pending, copyCode: { _, _ in })
        defer { flow.cancel() }

        try await XCTUnwrap(flow.begin()).value
        guard case let .code(first) = flow.state else {
            XCTFail("T09 真实待授权流程未到达代码步骤；保留真实失败，不能用隔离结果代替。")
            return
        }
        await flow.openWebsite()
        XCTAssertFalse(flow.browserFailed, "系统接受真实官网打开请求")
        flow.cancel()
        XCTAssertFalse(flow.isPresented)
        XCTAssertTrue(flow.accounts.isEmpty)
        try await XCTUnwrap(flow.begin()).value // Joins cancellation and exact cleanup.
        guard case let .code(second) = flow.state else {
            XCTFail("T09 取消后尚未取得第二次真实有效代码。")
            return
        }
        XCTAssertTrue(first.transactionID != second.transactionID && first.userCode != second.userCode,
                      "取消后的新流程获得不同真实代码，不打印代码")
        XCTAssertTrue(second.expiresAt > Date())
        flow.cancel()
        // Idempotent exact cleanup; no account confirmation was submitted.
        try await pending.remove(transactionID: first.transactionID)
        try await pending.remove(transactionID: second.transactionID)
        try await transactions.remove(transactionID: second.transactionID)
        let isolated = try await accounts.load()
        XCTAssertTrue(isolated.isEmpty, "真实取消不保存账户")
        let after = try await official.load()
        XCTAssertTrue(before == after, "正式账户数量、身份、顺序及原状态不变，不打印身份")
        for account in before {
            let afterCredential = try await officialVault.load(for: .credential(account.credentialRef))
            XCTAssertTrue(afterCredential == credentials[account.credentialRef], "原正式授权完整保留")
        }
        print("T09 | 真实待授权取消与再次申请 | 官网打开请求成功；取消不保存；再次评分并取得新代码；原正式账户与授权未变")
    }

    func testRealGateCodeClipboardAndDefaultBrowserDispatch() async throws {
        guard ProcessInfo.processInfo.environment["T07_LIVE_CONNECTION"] == "1" else {
            throw XCTSkip("真实连接起点需显式开启；普通验收不联网。")
        }
        let vault = CredentialVault(service: "com.iceflying.SubscriptionUsage.tests.T07.\(UUID())")
        let transactions = CodexLoginTransactionStore(vault: vault)
        let flow = CodexConnectionFlow(checkNetwork: {
            let result = await NetworkScoreChecker().check()
            switch result {
            case let .allowed(score): print("T07 | 真实网络 | 有效评分 \(score)，允许申请")
            case let .blocked(score): print("T07 | 真实网络 | 有效评分 \(score)，阻止申请")
            case .unavailable: print("T07 | 真实网络 | 未取得有效评分，阻止申请")
            case .cancelled: print("T07 | 真实网络 | 已取消")
            }
            return result
        }, transactions: transactions)

        try await XCTUnwrap(flow.begin()).value
        guard case let .code(authorization) = flow.state else {
            flow.cancel()
            XCTFail("T07 真实代码步骤尚未到达；保留真实网络拦截或申请失败结果，不能以隔离测试代替。")
            return
        }
        // All comparisons are boolean so an XCTest failure cannot print a live code.
        flow.copy()
        XCTAssertTrue(UIPasteboard.general.string == authorization.userCode, "复制内容与显示代码一致")
        print("T07 | 真实代码 | 已申请并安全暂存；主动复制内容一致（不记录代码）")
        await flow.openWebsite()
        XCTAssertFalse(flow.browserFailed, "系统默认打开行为接受官方设备确认地址")
        print("T07 | 真实官网 | 已调用系统默认HTTPS打开；网页实际到达另行核对")
        if UIPasteboard.general.string == authorization.userCode { UIPasteboard.general.items = [] }
        flow.cancel()
        try await transactions.remove(transactionID: authorization.transactionID)
    }
}
